with Ada.Streams;
with CryptoLib.Checksums;
with Zlib.LZMA_Properties;
with Zlib.Seven_Zip_AES;
with Zlib.Seven_Zip_Numbers;

package body Zlib.Seven_Zip_Header_Reading is
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;
   use type Zlib.Seven_Zip_Methods.Seven_Zip_Coder_Method;

   Empty : constant Byte_Array (1 .. 0) := [others => 0];

   function Read_Number
     (Data  : Byte_Array;
      Pos   : in out Natural;
      Last  : Natural;
      Value : out Interfaces.Unsigned_64) return Boolean
      renames Zlib.Seven_Zip_Numbers.Read_Number;

   function Read_Byte
     (Data : Byte_Array;
      Pos  : in out Natural;
      Last : Natural;
      B    : out Byte) return Boolean
      renames Zlib.Seven_Zip_Container.Read_Byte;

   function Expect_Byte
     (Data     : Byte_Array;
      Pos      : in out Natural;
      Last     : Natural;
      Expected : Byte) return Boolean
      renames Zlib.Seven_Zip_Container.Expect_Byte;

   function Has_Bytes
     (Pos   : Natural;
      Last  : Natural;
      Count : Natural) return Boolean is
     (Zlib.Seven_Zip_Container.Has_Bytes (Pos, Last, Count))
     with SPARK_Mode => On;

   function U32_At
     (Data : Byte_Array;
      Pos  : Natural) return Interfaces.Unsigned_32
      renames Zlib.Seven_Zip_Numbers.U32_At;

   function Valid_PPMd_Props
     (Order  : Natural;
      Memory : Interfaces.Unsigned_32) return Boolean
     with SPARK_Mode => On
   is
   begin
      return Order in 2 .. 64
        and then Memory >= 2 ** 11
        and then Memory <= Interfaces.Unsigned_32'Last - 36;
   end Valid_PPMd_Props;

   function Compute_CRC32 (Data : Byte_Array) return Interfaces.Unsigned_32 is
      State : CryptoLib.Checksums.CRC32_State;
   begin
      CryptoLib.Checksums.CRC32_Reset (State);
      for B of Data loop
         CryptoLib.Checksums.CRC32_Update (State, Ada.Streams.Stream_Element (B));
      end loop;
      return CryptoLib.Checksums.CRC32_Value (State);
   end Compute_CRC32;

   function Parse_AES_Properties
     (Data     : Byte_Array;
      Pos      : in out Natural;
      Last     : Natural;
      Cycles   : out Natural;
      Salt_Len : out Natural;
      IV_Len   : out Natural;
      Salt     : out Byte_Array;
      IV       : out Byte_Array) return Boolean
   is
      Prop_Size : Interfaces.Unsigned_64 := 0;
   begin
      Cycles := 0;
      Salt_Len := 0;
      IV_Len := 0;
      Salt := [others => 0];
      IV := [others => 0];

      if not Read_Number (Data, Pos, Last, Prop_Size)
        or else Prop_Size < 1
        or else Prop_Size > Interfaces.Unsigned_64 (Natural'Last)
        or else not Has_Bytes (Pos, Last, Natural (Prop_Size))
      then
         return False;
      end if;

      declare
         PB         : Byte_Array (1 .. Natural (Prop_Size));
         B0, B1, P : Natural := 0;
      begin
         for J in PB'Range loop
            PB (J) := Data (Pos);
            Pos := Pos + 1;
         end loop;

         B0 := Natural (PB (1));
         Cycles := B0 mod 64;
         if (B0 / 64) /= 0 and then PB'Length >= 2 then
            B1 := Natural (PB (2));
            P := 3;
         else
            P := 2;
         end if;

         Salt_Len := ((B0 / 128) mod 2) + (B1 / 16);
         IV_Len := ((B0 / 64) mod 2) + (B1 mod 16);
         if Salt_Len > Salt'Length
           or else IV_Len > IV'Length
           or else PB'Length < (P - 1) + Salt_Len + IV_Len
         then
            return False;
         end if;

         for J in 1 .. Salt_Len loop
            Salt (J) := PB (P + J - 1);
         end loop;
         for J in 1 .. IV_Len loop
            IV (J) := PB (P + Salt_Len + J - 1);
         end loop;
      end;

      return True;
   end Parse_AES_Properties;

   function Decode_AES_Header
     (Archive_Image : Byte_Array;
      Password      : String;
      Info          : Zlib.Seven_Zip_Container.Start_Header_Info;
      Decode        : not null access function
        (Input          : Byte_Array;
         Method         : Zlib.Seven_Zip_Methods.Seven_Zip_Coder_Method;
         LZMA_Props     : Byte_Array;
         Expected_Size  : Natural;
         Delta_Distance : Positive;
         PPMd_Order     : Natural;
         PPMd_Memory    : Interfaces.Unsigned_32;
         Status         : out Status_Code) return Byte_Array;
      Pack_Pos_Out  : out Natural;
      Status        : out Status_Code) return Byte_Array
   is
      P         : Natural := Info.Header_First;
      V         : Interfaces.Unsigned_64 := 0;
      B         : Byte := 0;
      Pack_Pos  : Interfaces.Unsigned_64 := 0;
      Pack_Size : Interfaces.Unsigned_64 := 0;
      HC_Size   : Interfaces.Unsigned_64 := 0;
      Hdr_Size  : Interfaces.Unsigned_64 := 0;
      Cycles    : Natural := 0;
      Salt_Len  : Natural := 0;
      IV_Len    : Natural := 0;
      Salt      : Byte_Array (1 .. 16) := [others => 0];
      IV        : Byte_Array (1 .. 16) := [others => 0];
      LZMA_P    : LZMA_Props := [others => 0];
      Num_Coders : Natural := 0;
   begin
      Pack_Pos_Out := 0;
      Status := Unsupported_Method;

      if not Expect_Byte (Archive_Image, P, Info.Header_Last, 16#17#) then
         return Empty;
      end if;
      if P <= Info.Header_Last and then Archive_Image (P) = 16#04# then
         P := P + 1;
      end if;

      if not Expect_Byte (Archive_Image, P, Info.Header_Last, 16#06#)
        or else not Read_Number (Archive_Image, P, Info.Header_Last, Pack_Pos)
        or else not Read_Number (Archive_Image, P, Info.Header_Last, V)
        or else V /= 1
        or else not Expect_Byte (Archive_Image, P, Info.Header_Last, 16#09#)
        or else not Read_Number (Archive_Image, P, Info.Header_Last, Pack_Size)
      then
         return Empty;
      end if;

      if P <= Info.Header_Last and then Archive_Image (P) = 16#0A# then
         P := P + 1;
         if not Expect_Byte (Archive_Image, P, Info.Header_Last, 1)
           or else not Has_Bytes (P, Info.Header_Last, 4)
         then
            return Empty;
         end if;
         P := P + 4;
      end if;

      if not Expect_Byte (Archive_Image, P, Info.Header_Last, 0)
        or else not Expect_Byte (Archive_Image, P, Info.Header_Last, 16#07#)
        or else not Expect_Byte (Archive_Image, P, Info.Header_Last, 16#0B#)
        or else not Read_Number (Archive_Image, P, Info.Header_Last, V)
        or else V /= 1
        or else not Expect_Byte (Archive_Image, P, Info.Header_Last, 0)
        or else not Read_Number (Archive_Image, P, Info.Header_Last, V)
        or else V not in 1 | 2
      then
         return Empty;
      end if;
      Num_Coders := Natural (V);

      if not Read_Byte (Archive_Image, P, Info.Header_Last, B)
        or else (B and 16#0F#) /= 4
        or else (B and 16#20#) = 0
        or else not Expect_Byte (Archive_Image, P, Info.Header_Last, 16#06#)
        or else not Expect_Byte (Archive_Image, P, Info.Header_Last, 16#F1#)
        or else not Expect_Byte (Archive_Image, P, Info.Header_Last, 16#07#)
        or else not Expect_Byte (Archive_Image, P, Info.Header_Last, 16#01#)
        or else not Parse_AES_Properties
          (Archive_Image, P, Info.Header_Last, Cycles, Salt_Len, IV_Len, Salt, IV)
      then
         return Empty;
      end if;

      if Num_Coders = 2 then
         if not Expect_Byte (Archive_Image, P, Info.Header_Last, 16#23#)
           or else not Expect_Byte (Archive_Image, P, Info.Header_Last, 16#03#)
           or else not Expect_Byte (Archive_Image, P, Info.Header_Last, 16#01#)
           or else not Expect_Byte (Archive_Image, P, Info.Header_Last, 16#01#)
           or else not Expect_Byte (Archive_Image, P, Info.Header_Last, 5)
         then
            return Empty;
         end if;

         for J in LZMA_P'Range loop
            if not Read_Byte (Archive_Image, P, Info.Header_Last, LZMA_P (J)) then
               return Empty;
            end if;
         end loop;
         if not Zlib.LZMA_Properties.Valid_Props (LZMA_P (1)) then
            return Empty;
         end if;

         if not Read_Number (Archive_Image, P, Info.Header_Last, V)
           or else V /= 1
           or else not Read_Number (Archive_Image, P, Info.Header_Last, V)
           or else V /= 0
         then
            return Empty;
         end if;
      end if;

      if not Expect_Byte (Archive_Image, P, Info.Header_Last, 16#0C#)
        or else not Read_Number (Archive_Image, P, Info.Header_Last, HC_Size)
      then
         return Empty;
      end if;
      if Num_Coders = 2 then
         if not Read_Number (Archive_Image, P, Info.Header_Last, Hdr_Size) then
            return Empty;
         end if;
      else
         Hdr_Size := HC_Size;
      end if;

      if P <= Info.Header_Last and then Archive_Image (P) = 16#0A# then
         P := P + 1;
         if not Expect_Byte (Archive_Image, P, Info.Header_Last, 1)
           or else not Has_Bytes (P, Info.Header_Last, 4)
         then
            return Empty;
         end if;
         P := P + 4;
      end if;

      if not Expect_Byte (Archive_Image, P, Info.Header_Last, 0)
        or else not Expect_Byte (Archive_Image, P, Info.Header_Last, 0)
      then
         return Empty;
      end if;

      if Pack_Pos > Interfaces.Unsigned_64 (Natural'Last)
        or else Pack_Size > Interfaces.Unsigned_64 (Natural'Last)
        or else Pack_Pos > Interfaces.Unsigned_64 (Info.Payload_Count)
        or else Pack_Size > Interfaces.Unsigned_64 (Info.Payload_Count) - Pack_Pos
        or else Natural (Pack_Size) mod 16 /= 0
        or else Natural (Pack_Size) = 0
        or else Password'Length = 0
      then
         return Empty;
      end if;

      Pack_Pos_Out := Natural (Pack_Pos);
      declare
         Enc_First : constant Natural := Info.Payload_First + Natural (Pack_Pos);
         Enc       : constant Byte_Array :=
           Archive_Image (Enc_First .. Enc_First + Natural (Pack_Size) - 1);
         Key       : constant Byte_Array :=
           Zlib.Seven_Zip_AES.Derive_Key (Password, Salt (1 .. Salt_Len), Cycles);
         Dec       : constant Byte_Array := Zlib.Seven_Zip_AES.Decrypt_CBC (Key, IV, Enc);
         Local     : Status_Code := Ok;
      begin
         if Natural (HC_Size) > Dec'Length then
            return Empty;
         end if;

         declare
            Trunc : constant Byte_Array :=
              Dec (Dec'First .. Dec'First + Natural (HC_Size) - 1);
            Plain : constant Byte_Array :=
              Decode
                (Trunc,
                 (if Num_Coders = 2
                  then Zlib.Seven_Zip_Methods.Seven_Zip_LZMA_Method
                  else Zlib.Seven_Zip_Methods.Seven_Zip_Copy),
                 LZMA_P, Natural (Hdr_Size), 1, 0, 0, Local);
         begin
            if Local /= Ok then
               Status := Local;
               return Empty;
            end if;
            Status := Ok;
            return Plain;
         end;
      end;
   exception
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end Decode_AES_Header;

   function Decode_Generic_Header
     (Archive_Image : Byte_Array;
      Info          : Zlib.Seven_Zip_Container.Start_Header_Info;
      Decode        : not null access function
        (Input          : Byte_Array;
         Method         : Zlib.Seven_Zip_Methods.Seven_Zip_Coder_Method;
         LZMA_Props     : Byte_Array;
         Expected_Size  : Natural;
         Delta_Distance : Positive;
         PPMd_Order     : Natural;
         PPMd_Memory    : Interfaces.Unsigned_32;
         Status         : out Status_Code) return Byte_Array;
      Pack_Pos_Out  : out Natural;
      Status        : out Status_Code) return Byte_Array
   is
      use Zlib.Seven_Zip_Methods;

      P             : Natural := Info.Header_First;
      V             : Interfaces.Unsigned_64 := 0;
      B             : Byte := 0;
      Pack_Pos      : Interfaces.Unsigned_64 := 0;
      Pack_Size     : Interfaces.Unsigned_64 := 0;
      Pack_CRC      : Interfaces.Unsigned_32 := 0;
      Pack_CRC_OK   : Boolean := False;
      Method        : Seven_Zip_Coder_Method := Seven_Zip_Copy;
      Delta_Distance : Positive := 1;
      PPMd_Order    : Natural := 0;
      PPMd_Memory   : Interfaces.Unsigned_32 := 0;
      LZMA_P        : LZMA_Props :=
        LZMA_Props
          (Zlib.LZMA_Properties.Default_Dict_Properties
             (Zlib.LZMA_Properties.Default_Props));
      Unpack_Size   : Interfaces.Unsigned_64 := 0;
      Unpack_CRC    : Interfaces.Unsigned_32 := 0;
      Unpack_CRC_OK : Boolean := False;
   begin
      Pack_Pos_Out := 0;
      Status := Unsupported_Method;

      if not Expect_Byte (Archive_Image, P, Info.Header_Last, 16#17#) then
         return Empty;
      end if;
      if P <= Info.Header_Last and then Archive_Image (P) = 16#04# then
         P := P + 1;
      end if;

      if not Expect_Byte (Archive_Image, P, Info.Header_Last, 16#06#)
        or else not Read_Number (Archive_Image, P, Info.Header_Last, Pack_Pos)
        or else not Read_Number (Archive_Image, P, Info.Header_Last, V)
        or else V /= 1
        or else not Expect_Byte (Archive_Image, P, Info.Header_Last, 16#09#)
        or else not Read_Number (Archive_Image, P, Info.Header_Last, Pack_Size)
      then
         return Empty;
      end if;

      if P <= Info.Header_Last and then Archive_Image (P) = 16#0A# then
         P := P + 1;
         if not Expect_Byte (Archive_Image, P, Info.Header_Last, 1)
           or else not Has_Bytes (P, Info.Header_Last, 4)
         then
            return Empty;
         end if;
         Pack_CRC := U32_At (Archive_Image, P);
         Pack_CRC_OK := True;
         P := P + 4;
      end if;

      if not Expect_Byte (Archive_Image, P, Info.Header_Last, 0)
        or else not Expect_Byte (Archive_Image, P, Info.Header_Last, 16#07#)
        or else not Expect_Byte (Archive_Image, P, Info.Header_Last, 16#0B#)
        or else not Read_Number (Archive_Image, P, Info.Header_Last, V)
        or else V /= 1
        or else not Expect_Byte (Archive_Image, P, Info.Header_Last, 0)
        or else not Read_Number (Archive_Image, P, Info.Header_Last, V)
        or else V /= 1
        or else not Read_Byte (Archive_Image, P, Info.Header_Last, B)
      then
         return Empty;
      end if;

      if B = 1 then
         if not Expect_Byte (Archive_Image, P, Info.Header_Last, 0) then
            return Empty;
         end if;
         Method := Seven_Zip_Copy;
      elsif B = 3 then
         if not Expect_Byte (Archive_Image, P, Info.Header_Last, 16#04#)
           or else not Read_Byte (Archive_Image, P, Info.Header_Last, B)
         then
            return Empty;
         end if;

         if B = 16#01# then
            if not Expect_Byte (Archive_Image, P, Info.Header_Last, 16#08#) then
               return Empty;
            end if;
            Method := Seven_Zip_Deflate_Method;
         elsif B = 16#02# then
            if not Expect_Byte (Archive_Image, P, Info.Header_Last, 16#02#) then
               return Empty;
            end if;
            Method := Seven_Zip_BZip2_Method;
         else
            return Empty;
         end if;
      elsif B = 16#23# then
         if not Expect_Byte (Archive_Image, P, Info.Header_Last, 16#03#)
           or else not Read_Byte (Archive_Image, P, Info.Header_Last, B)
         then
            return Empty;
         end if;

         if B = 16#01# then
            if not Expect_Byte (Archive_Image, P, Info.Header_Last, 16#01#)
              or else not Expect_Byte (Archive_Image, P, Info.Header_Last, 5)
            then
               return Empty;
            end if;

            for J in LZMA_P'Range loop
               if not Read_Byte (Archive_Image, P, Info.Header_Last, LZMA_P (J)) then
                  return Empty;
               end if;
            end loop;
            if not Zlib.LZMA_Properties.Valid_Props (LZMA_P (1)) then
               return Empty;
            end if;
            Method := Seven_Zip_LZMA_Method;
         elsif B = 16#04# then
            if not Expect_Byte (Archive_Image, P, Info.Header_Last, 16#01#)
              or else not Expect_Byte (Archive_Image, P, Info.Header_Last, 5)
              or else not Read_Byte (Archive_Image, P, Info.Header_Last, B)
              or else not Has_Bytes (P, Info.Header_Last, 4)
            then
               return Empty;
            end if;

            PPMd_Order := Natural (B);
            PPMd_Memory := U32_At (Archive_Image, P);
            if not Valid_PPMd_Props (PPMd_Order, PPMd_Memory) then
               return Empty;
            end if;
            P := P + 4;
            Method := Seven_Zip_PPMd_Method;
         else
            return Empty;
         end if;
      elsif B = 16#21# then
         if not Read_Byte (Archive_Image, P, Info.Header_Last, B) then
            return Empty;
         end if;

         if B = 16#21# then
            if not Expect_Byte (Archive_Image, P, Info.Header_Last, 1)
              or else not Read_Byte (Archive_Image, P, Info.Header_Last, B)
              or else B > 40
            then
               return Empty;
            end if;
            Method := Seven_Zip_LZMA2_Method;
         elsif B = 16#03# then
            if not Expect_Byte (Archive_Image, P, Info.Header_Last, 1)
              or else not Read_Byte (Archive_Image, P, Info.Header_Last, B)
            then
               return Empty;
            end if;
            Delta_Distance := Natural (B) + 1;
            Method := Seven_Zip_Delta_Method;
         else
            return Empty;
         end if;
      else
         return Empty;
      end if;

      if not Expect_Byte (Archive_Image, P, Info.Header_Last, 16#0C#)
        or else not Read_Number (Archive_Image, P, Info.Header_Last, Unpack_Size)
      then
         return Empty;
      end if;

      if P <= Info.Header_Last and then Archive_Image (P) = 16#0A# then
         P := P + 1;
         if not Expect_Byte (Archive_Image, P, Info.Header_Last, 1)
           or else not Has_Bytes (P, Info.Header_Last, 4)
         then
            return Empty;
         end if;
         Unpack_CRC := U32_At (Archive_Image, P);
         Unpack_CRC_OK := True;
         P := P + 4;
      end if;

      if not Expect_Byte (Archive_Image, P, Info.Header_Last, 0)
        or else not Expect_Byte (Archive_Image, P, Info.Header_Last, 0)
      then
         return Empty;
      end if;

      if P /= Info.Header_Last + 1
        or else Pack_Pos > Interfaces.Unsigned_64 (Natural'Last)
        or else Pack_Size > Interfaces.Unsigned_64 (Natural'Last)
        or else Unpack_Size > Interfaces.Unsigned_64 (Natural'Last)
        or else Pack_Pos > Interfaces.Unsigned_64 (Info.Payload_Count)
        or else Pack_Size > Interfaces.Unsigned_64 (Info.Payload_Count) - Pack_Pos
      then
         return Empty;
      end if;

      Pack_Pos_Out := Natural (Pack_Pos);
      declare
         Enc_First : constant Natural := Info.Payload_First + Natural (Pack_Pos);
         Enc_Size  : constant Natural := Natural (Pack_Size);
         Enc_Last  : constant Natural :=
           (if Enc_Size = 0 then Enc_First - 1 else Enc_First + Enc_Size - 1);
         Encoded   : constant Byte_Array :=
           (if Enc_Size = 0 then Empty else Archive_Image (Enc_First .. Enc_Last));
         Local     : Status_Code := Ok;
         Decoded   : constant Byte_Array :=
           Decode
             (Encoded, Method, LZMA_P, Natural (Unpack_Size), Delta_Distance,
              PPMd_Order, PPMd_Memory, Local);
      begin
         if Pack_CRC_OK and then Compute_CRC32 (Encoded) /= Pack_CRC then
            Status := Invalid_Checksum;
            return Empty;
         end if;

         if Local /= Ok then
            Status := Local;
            return Empty;
         end if;

         if Decoded'Length /= Natural (Unpack_Size)
           or else (Unpack_CRC_OK and then Compute_CRC32 (Decoded) /= Unpack_CRC)
         then
            Status := Invalid_Checksum;
            return Empty;
         end if;

         Status := Ok;
         return Decoded;
      end;
   exception
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end Decode_Generic_Header;

   function Decode_Encoded_Header
     (Archive_Image : Byte_Array;
      Password      : String;
      Info          : Zlib.Seven_Zip_Container.Start_Header_Info;
      Decode        : not null access function
        (Input          : Byte_Array;
         Method         : Zlib.Seven_Zip_Methods.Seven_Zip_Coder_Method;
         LZMA_Props     : Byte_Array;
         Expected_Size  : Natural;
         Delta_Distance : Positive;
         PPMd_Order     : Natural;
         PPMd_Memory    : Interfaces.Unsigned_32;
         Status         : out Status_Code) return Byte_Array;
      Pack_Pos      : out Natural;
      Status        : out Status_Code) return Byte_Array
   is
      AES_Status     : Status_Code := Ok;
      AES_Pack_Pos   : Natural := 0;
      AES_Header     : constant Byte_Array :=
        Decode_AES_Header
          (Archive_Image, Password, Info, Decode, AES_Pack_Pos, AES_Status);
      Generic_Status : Status_Code := Ok;
      Generic_Pos    : Natural := 0;
      Generic_Header : constant Byte_Array :=
        (if AES_Status = Ok
         then Empty
         else Decode_Generic_Header
           (Archive_Image, Info, Decode, Generic_Pos, Generic_Status));
   begin
      if AES_Status = Ok then
         Pack_Pos := AES_Pack_Pos;
         Status := Ok;
         return AES_Header;
      end if;

      Pack_Pos := Generic_Pos;
      Status := Generic_Status;
      return Generic_Header;
   end Decode_Encoded_Header;

end Zlib.Seven_Zip_Header_Reading;
