with Ada.Streams;
with CryptoLib.Checksums;
with Zlib.PPMd7;
with Zlib.Seven_Zip_AES;
with Zlib.Seven_Zip_Filters;
with Zlib.Seven_Zip_Methods; use Zlib.Seven_Zip_Methods;
with Zlib.Seven_Zip_Numbers;

package body Zlib.Seven_Zip_Folder_Decoding is
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;

   function Read_Number
     (Data : Byte_Array;
      Pos  : in out Natural;
      Last : Natural;
      N    : out Interfaces.Unsigned_64) return Boolean
      renames Zlib.Seven_Zip_Numbers.Read_Number;

   function Compute_CRC32 (Data : Byte_Array) return Interfaces.Unsigned_32 is
      State : CryptoLib.Checksums.CRC32_State;
   begin
      CryptoLib.Checksums.CRC32_Reset (State);
      for B of Data loop
         CryptoLib.Checksums.CRC32_Update (State, Ada.Streams.Stream_Element (B));
      end loop;
      return CryptoLib.Checksums.CRC32_Value (State);
   end Compute_CRC32;

   function Analyze_Bind_Pairs
     (Archive_Image : Byte_Array;
      Pos           : in out Natural;
      Header_Last   : Natural;
      Coder_Count   : Positive;
      Methods       : Folder_Method_Array;
      Info          : out Folder_Graph_Info) return Boolean
   is
      Forward_Binds        : Boolean := True;
      Reverse_Binds        : Boolean := True;
      Standard_Linear_Binds : Boolean := True;
      Generic_Binds        : Boolean := True;
      Legacy_Generic_Binds : Boolean := True;
      Next_Coder           : Coder_Link_Array := [others => 0];
      Legacy_Next_Coder    : Coder_Link_Array := [others => 0];
      Input_Bound          : array (1 .. Max_Folder_Coders) of Boolean :=
        [others => False];
      Output_Bound         : array (1 .. Max_Folder_Coders) of Boolean :=
        [others => False];
      Legacy_Input_Bound   : array (1 .. Max_Folder_Coders) of Boolean :=
        [others => False];
      Legacy_Output_Bound  : array (1 .. Max_Folder_Coders) of Boolean :=
        [others => False];
      Value                : Interfaces.Unsigned_64 := 0;
   begin
      Info := (others => <>);

      if Coder_Count > Max_Folder_Coders
        or else Methods'Length < Coder_Count
      then
         return False;
      end if;

      if Methods (Methods'First) = Seven_Zip_BCJ2_Method then
         Info.Pack_Count := 4;
         Info.Terminal_Coder := 1;
         return True;
      elsif Coder_Count = 1 then
         Info.Terminal_Coder := 1;
         return True;
      end if;

      for Bind_Index in 1 .. Coder_Count - 1 loop
         declare
            Bind_Out  : Interfaces.Unsigned_64 := 0;
            Bind_In   : Interfaces.Unsigned_64 := 0;
            Out_Coder : Natural := 0;
            In_Coder  : Natural := 0;
         begin
            if not Read_Number (Archive_Image, Pos, Header_Last, Bind_Out)
              or else not Read_Number (Archive_Image, Pos, Header_Last, Bind_In)
            then
               return False;
            end if;

            if Generic_Binds
              and then Bind_Out < Interfaces.Unsigned_64 (Coder_Count)
              and then Bind_In < Interfaces.Unsigned_64 (Coder_Count)
            then
               --  7z BindPair is (InIndex, OutIndex). The coder whose output
               --  is bound is OutIndex's coder; the coder whose input is bound
               --  is InIndex's coder.
               Out_Coder := Natural (Bind_In) + 1;
               In_Coder := Natural (Bind_Out) + 1;
               if Output_Bound (Out_Coder) or else Input_Bound (In_Coder) then
                  Generic_Binds := False;
               else
                  Output_Bound (Out_Coder) := True;
                  Input_Bound (In_Coder) := True;
                  Next_Coder (Out_Coder) := In_Coder;
               end if;
            else
               Generic_Binds := False;
            end if;

            if Legacy_Generic_Binds
              and then Bind_Out in 1 .. Interfaces.Unsigned_64 (Coder_Count)
              and then Bind_In in 1 .. Interfaces.Unsigned_64 (Coder_Count)
            then
               Out_Coder := Natural (Bind_In);
               In_Coder := Natural (Bind_Out);
               if Legacy_Output_Bound (Out_Coder) or else Legacy_Input_Bound (In_Coder) then
                  Legacy_Generic_Binds := False;
               else
                  Legacy_Output_Bound (Out_Coder) := True;
                  Legacy_Input_Bound (In_Coder) := True;
                  Legacy_Next_Coder (Out_Coder) := In_Coder;
               end if;
            else
               Legacy_Generic_Binds := False;
            end if;

            if Bind_Out /= Interfaces.Unsigned_64 (Bind_Index + 1)
              or else Bind_In /= Interfaces.Unsigned_64 (Bind_Index)
            then
               Forward_Binds := False;
            end if;

            if Bind_Out /= Interfaces.Unsigned_64 (Bind_Index)
              or else Bind_In /= Interfaces.Unsigned_64 (Bind_Index - 1)
            then
               Reverse_Binds := False;
            end if;

            if Bind_Out /= Interfaces.Unsigned_64 (Bind_Index - 1)
              or else Bind_In /= Interfaces.Unsigned_64 (Bind_Index)
            then
               Standard_Linear_Binds := False;
            end if;
         end;
      end loop;

      if Reverse_Binds
        and then Coder_Count = 5
        and then Methods (Methods'First + Coder_Count - 1) = Seven_Zip_BCJ2_Method
      then
         for Coder_Index in 1 .. Coder_Count - 1 loop
            if not Is_BCJ2_Main_Chain_Coder (Methods (Methods'First + Coder_Index - 1)) then
               return False;
            end if;
         end loop;

         Info.Packed_Coder := Coder_Count;
         Info.Terminal_Coder := Coder_Count;
         Info.Pack_Count := 4;
         Info.Pack_Indices_Read := True;
         Generic_Binds := False;
         Legacy_Generic_Binds := False;

         for Relative_Index in 0 .. 3 loop
            if not Read_Number (Archive_Image, Pos, Header_Last, Value) then
               return False;
            end if;

            if (Relative_Index = 0 and then Value /= 0)
              or else
                (Relative_Index > 0
                 and then Value /= Interfaces.Unsigned_64 (Coder_Count + Relative_Index - 1))
            then
               return False;
            end if;
         end loop;
      elsif Reverse_Binds or else Forward_Binds or else Standard_Linear_Binds then
         if not Generic_Binds then
            if Reverse_Binds then
               Info.Packed_Coder := Coder_Count;
               Info.Terminal_Coder := 1;
               Info.Reverse_Chain := True;
               for Coder_Index in 2 .. Coder_Count loop
                  Info.Next_Coder (Coder_Index) := Coder_Index - 1;
               end loop;
            else
               Info.Packed_Coder := 1;
               Info.Terminal_Coder := Coder_Count;
               for Coder_Index in 1 .. Coder_Count - 1 loop
                  Info.Next_Coder (Coder_Index) := Coder_Index + 1;
               end loop;
            end if;
         end if;
      else
         if not Generic_Binds and then not Legacy_Generic_Binds then
            return False;
         end if;
      end if;

      if Generic_Binds or else Legacy_Generic_Binds then
         declare
            Packed_Coder   : Natural := 0;
            Terminal_Coder : Natural := 0;
            Visited        : array (1 .. Max_Folder_Coders) of Boolean :=
              [others => False];
            Current        : Natural := 0;
            Visited_Count  : Natural := 0;
         begin
            for Coder_Index in 1 .. Coder_Count loop
               if not
                 (if Generic_Binds
                  then Input_Bound (Coder_Index)
                  else Legacy_Input_Bound (Coder_Index))
               then
                  if Packed_Coder /= 0 then
                     return False;
                  end if;
                  Packed_Coder := Coder_Index;
               end if;

               if not
                 (if Generic_Binds
                  then Output_Bound (Coder_Index)
                  else Legacy_Output_Bound (Coder_Index))
               then
                  if Terminal_Coder /= 0 then
                     return False;
                  end if;
                  Terminal_Coder := Coder_Index;
               end if;
            end loop;

            if Packed_Coder = 0 or else Terminal_Coder = 0 then
               return False;
            end if;

            Current := Packed_Coder;
            loop
               if Current = 0
                 or else Current > Coder_Count
                 or else Visited (Current)
               then
                  return False;
               end if;

               Visited (Current) := True;
               Visited_Count := Visited_Count + 1;
               exit when Current = Terminal_Coder;
               Current :=
                 (if Generic_Binds
                  then Next_Coder (Current)
                  else Legacy_Next_Coder (Current));
            end loop;

            if Visited_Count /= Coder_Count then
               return False;
            end if;

            Info.Packed_Coder := Packed_Coder;
            Info.Terminal_Coder := Terminal_Coder;
            Info.Reverse_Chain := Reverse_Binds;

            for Coder_Index in 1 .. Coder_Count loop
               Info.Next_Coder (Coder_Index) :=
                 (if Generic_Binds
                  then Next_Coder (Coder_Index)
                  else Legacy_Next_Coder (Coder_Index));
            end loop;
         end;
      end if;

      return True;
   end Analyze_Bind_Pairs;

   function Decode_Coder_Chain
     (Input       : Byte_Array;
      Password    : String;
      Coders      : Folder_Coder_Array;
      First_Coder : Natural;
      Next_Coder  : Coder_Link_Array;
      Decode_Core : not null access function
        (Input         : Byte_Array;
         Method        : Zlib.Seven_Zip_Methods.Seven_Zip_Coder_Method;
         LZMA_Props    : Byte_Array;
         Expected_Size : Natural;
         Status        : out Status_Code) return Byte_Array;
      Status      : out Status_Code) return Byte_Array
   is
      Empty : constant Byte_Array (1 .. 0) := [others => 0];

      function Run
        (Coder_Index : Natural;
         Data        : Byte_Array) return Byte_Array
      is
         Coder        : Folder_Coder_Info;
         Decode_Status : Status_Code := Ok;

         function Continue
           (Decoded : Byte_Array) return Byte_Array
         is
         begin
            if Decode_Status /= Ok then
               Status := Decode_Status;
               return Empty;
            end if;

            return Run (Next_Coder (Coder_Index), Decoded);
         end Continue;
      begin
         if Coder_Index = 0 then
            Status := Ok;
            return Data;
         end if;

         if Coder_Index not in Coders'Range then
            Status := Unsupported_Method;
            return Empty;
         end if;

         Coder := Coders (Coder_Index);

         case Coder.Method is
            when Seven_Zip_Copy =>
               return Run (Next_Coder (Coder_Index), Data);

            when Seven_Zip_Delta_Method =>
               return Continue
                 (Zlib.Seven_Zip_Filters.Delta_Decode_Checked
                    (Data, Coder.Delta_Distance, Decode_Status));

            when Seven_Zip_AES_Method =>
               if Password'Length = 0 or else Data'Length mod 16 /= 0 then
                  Status := Unsupported_Method;
                  return Empty;
               end if;

               declare
                  Salt : Byte_Array (1 .. Coder.AES_Salt_Len);
                  IV   : Byte_Array (1 .. 16) := [others => 0];
               begin
                  for J in 1 .. Coder.AES_Salt_Len loop
                     Salt (J) := Coder.AES_Salt (J);
                  end loop;
                  for J in 1 .. Coder.AES_IV_Len loop
                     IV (J) := Coder.AES_IV (J);
                  end loop;

                  return Run
                    (Next_Coder (Coder_Index),
                     Zlib.Seven_Zip_AES.Decrypt_CBC
                       (Zlib.Seven_Zip_AES.Derive_Key
                          (Password, Salt, Coder.AES_Cycles),
                        IV, Data));
               end;

            when Seven_Zip_BCJ_X86_Method =>
               return Continue
                 (Zlib.Seven_Zip_Filters.X86_BCJ_Decode
                    (Data, Decode_Status));

            when Seven_Zip_PPMd_Method =>
               declare
                  Decoded : constant Byte_Array :=
                    Zlib.PPMd7.Decompress
                      (Data, Coder.Expected_Size, Coder.PPMd_Order,
                       Coder.PPMd_Memory, Decode_Status);
               begin
                  if Decode_Status = Ok
                    and then Decoded'Length = Coder.Expected_Size
                  then
                     return Run (Next_Coder (Coder_Index), Decoded);
                  end if;

                  Status := Decode_Status;
                  return Empty;
               end;

            when Seven_Zip_Deflate_Method
               | Seven_Zip_BZip2_Method
               | Seven_Zip_LZMA_Method
               | Seven_Zip_LZMA2_Method =>
               return Continue
                 (Decode_Core
                    (Data, Coder.Method, Coder.LZMA_Props,
                     Coder.Expected_Size, Decode_Status));

            when Seven_Zip_BCJ2_Method =>
               Status := Unsupported_Method;
               return Empty;

            when others =>
               if Is_Branch_Converter (Coder.Method) then
                  return Run
                    (Next_Coder (Coder_Index),
                     Zlib.Seven_Zip_Filters.Branch_Convert
                       (Branch_Arch_Of (Coder.Method), Data,
                        Encoding => False));
               end if;

               Status := Unsupported_Method;
               return Empty;
         end case;
      end Run;
   begin
      Status := Ok;
      return Run (First_Coder, Input);
   end Decode_Coder_Chain;

   function Decode_BCJ2_Graph
     (Main_Input : Byte_Array;
      Call_Input : Byte_Array;
      Jump_Input : Byte_Array;
      Range_Input : Byte_Array;
      Coders      : Folder_Coder_Array;
      Output_Size : Natural;
      Decode_Core : not null access function
        (Input         : Byte_Array;
         Method        : Zlib.Seven_Zip_Methods.Seven_Zip_Coder_Method;
         LZMA_Props    : Byte_Array;
         Expected_Size : Natural;
         Status        : out Status_Code) return Byte_Array;
      Status      : out Status_Code) return Byte_Array
   is
      Empty : constant Byte_Array (1 .. 0) := [others => 0];

      function Run_Main_Chain
        (Coder_Index : Natural;
         Data        : Byte_Array) return Byte_Array
      is
         Coder         : Folder_Coder_Info;
         Decode_Status : Status_Code := Ok;

         function Continue_Decoded
           (Decoded : Byte_Array) return Byte_Array
         is
         begin
            if Decode_Status /= Ok then
               Status := Decode_Status;
               return Empty;
            end if;

            if Decoded'Length /= Coder.Expected_Size then
               Status := Invalid_Block_Type;
               return Empty;
            end if;

            return Run_Main_Chain (Coder_Index + 1, Decoded);
         end Continue_Decoded;
      begin
         if Coder_Index > Coders'Last then
            Status := Unsupported_Method;
            return Empty;
         end if;

         Coder := Coders (Coder_Index);

         if Coder.Method = Seven_Zip_BCJ2_Method then
            return Zlib.Seven_Zip_Filters.BCJ2_Decode
              (Data, Call_Input, Jump_Input, Range_Input, Output_Size,
               Status);
         end if;

         if Coder_Index = Coders'Last then
            Status := Unsupported_Method;
            return Empty;
         end if;

         case Coder.Method is
            when Seven_Zip_Copy =>
               return Run_Main_Chain (Coder_Index + 1, Data);

            when Seven_Zip_Delta_Method =>
               return Continue_Decoded
                 (Zlib.Seven_Zip_Filters.Delta_Decode_Checked
                    (Data, Coder.Delta_Distance, Decode_Status));

            when Seven_Zip_BCJ_X86_Method =>
               return Continue_Decoded
                 (Zlib.Seven_Zip_Filters.X86_BCJ_Decode
                    (Data, Decode_Status));

            when Seven_Zip_PPMd_Method =>
               declare
                  Decoded : constant Byte_Array :=
                    Zlib.PPMd7.Decompress
                      (Data, Coder.Expected_Size, Coder.PPMd_Order,
                       Coder.PPMd_Memory, Decode_Status);
               begin
                  return Continue_Decoded (Decoded);
               end;

            when Seven_Zip_Deflate_Method
               | Seven_Zip_BZip2_Method
               | Seven_Zip_LZMA_Method
               | Seven_Zip_LZMA2_Method =>
               return Continue_Decoded
                 (Decode_Core
                    (Data, Coder.Method, Coder.LZMA_Props,
                     Coder.Expected_Size, Decode_Status));

            when others =>
               if Is_Branch_Converter (Coder.Method) then
                  return Continue_Decoded
                    (Zlib.Seven_Zip_Filters.Branch_Convert
                       (Branch_Arch_Of (Coder.Method), Data,
                        Encoding => False));
               end if;

               Status := Unsupported_Method;
               return Empty;
         end case;
      end Run_Main_Chain;
   begin
      Status := Ok;

      if Coders'Length = 0 then
         Status := Unsupported_Method;
         return Empty;
      end if;

      return Run_Main_Chain (Coders'First, Main_Input);
   end Decode_BCJ2_Graph;

   function Validate_And_Slice_Substream
     (Plain                 : Byte_Array;
      Folder_Index          : Natural;
      Target_Index          : Natural;
      Folder_Size           : Interfaces.Unsigned_64;
      Folder_CRC_Defined    : Boolean;
      Folder_CRC            : Interfaces.Unsigned_32;
      Substream_Folder      : not null access function
        (Index : Natural) return Natural;
      Substream_Size        : not null access function
        (Index : Natural) return Interfaces.Unsigned_64;
      Substream_CRC_Defined : not null access function
        (Index : Natural) return Boolean;
      Substream_CRC         : not null access function
        (Index : Natural) return Interfaces.Unsigned_32;
      Status                : out Status_Code) return Byte_Array
   is
      Empty      : constant Byte_Array (1 .. 0) := [others => 0];
      Sub_Offset : Natural := 0;
      Sub_Size   : Natural;
   begin
      if Folder_Size > Interfaces.Unsigned_64 (Natural'Last)
        or else Substream_Size (Target_Index) >
          Interfaces.Unsigned_64 (Natural'Last)
      then
         Status := Unsupported_Method;
         return Empty;
      end if;

      if Plain'Length /= Natural (Folder_Size)
        or else
          (Folder_CRC_Defined and then Compute_CRC32 (Plain) /= Folder_CRC)
      then
         Status := Invalid_Checksum;
         return Empty;
      end if;

      Sub_Size := Natural (Substream_Size (Target_Index));

      for I in 1 .. Target_Index - 1 loop
         if Substream_Folder (I) = Folder_Index then
            if Substream_Size (I) >
              Interfaces.Unsigned_64 (Natural'Last - Sub_Offset)
            then
               Status := Unsupported_Method;
               return Empty;
            end if;

            Sub_Offset := Sub_Offset + Natural (Substream_Size (I));
         end if;
      end loop;

      if Sub_Offset > Plain'Length or else Sub_Size > Plain'Length - Sub_Offset
      then
         Status := Invalid_Checksum;
         return Empty;
      end if;

      if Sub_Size = 0 then
         if Substream_CRC_Defined (Target_Index)
           and then Compute_CRC32 (Empty) /= Substream_CRC (Target_Index)
         then
            Status := Invalid_Checksum;
         else
            Status := Ok;
         end if;

         return Empty;
      end if;

      declare
         Result : constant Byte_Array :=
           Plain
             (Plain'First + Sub_Offset ..
              Plain'First + Sub_Offset + Sub_Size - 1);
      begin
         if Substream_CRC_Defined (Target_Index)
           and then Compute_CRC32 (Result) /= Substream_CRC (Target_Index)
         then
            Status := Invalid_Checksum;
            return Empty;
         end if;

         Status := Ok;
         return Result;
      end;
   end Validate_And_Slice_Substream;

   function Decode_PPMd_With_Fallback
     (Payload               : Byte_Array;
      Output_Size           : Natural;
      Folder_Output_Size    : Natural;
      Order                 : Natural;
      Memory                : Interfaces.Unsigned_32;
      Has_Next_Coder        : Boolean;
      Folder_CRC_Defined    : Boolean;
      Folder_CRC            : Interfaces.Unsigned_32;
      Substream_CRC_Defined : Boolean;
      Substream_CRC         : Interfaces.Unsigned_32;
      Substream_Size        : Interfaces.Unsigned_64;
      Finish                : not null access function
        (Plain  : Byte_Array;
         Status : out Status_Code) return Byte_Array;
      Status                : out Status_Code) return Byte_Array
   is
      Empty       : constant Byte_Array (1 .. 0) := [others => 0];
      PPMd_Status : Status_Code := Ok;
      Plain       : constant Byte_Array :=
        Zlib.PPMd7.Decompress
          (Payload, Output_Size, Order, Memory, PPMd_Status);

      function Finish_Plain (Candidate : Byte_Array) return Byte_Array is
         Finish_Status : Status_Code := Ok;
         Result        : constant Byte_Array := Finish (Candidate, Finish_Status);
      begin
         Status := Finish_Status;
         return Result;
      end Finish_Plain;
   begin
      Status := Ok;

      if not Has_Next_Coder
        and then Folder_CRC_Defined
        and then
          (PPMd_Status /= Ok
           or else Plain'Length /= Output_Size
           or else Compute_CRC32 (Plain) /= Folder_CRC)
      then
         declare
            Verified_Status : Status_Code := Ok;
            Verified_Plain  : constant Byte_Array :=
              Zlib.PPMd7.Decompress
                (Payload, Output_Size, Order, Memory, Verified_Status);
         begin
            if Verified_Status = Ok
              and then Verified_Plain'Length = Output_Size
              and then Compute_CRC32 (Verified_Plain) = Folder_CRC
            then
               return Finish_Plain (Verified_Plain);
            end if;
         end;
      end if;

      if PPMd_Status /= Ok then
         declare
            Basic_Status : Status_Code := Ok;
            Basic_Plain  : constant Byte_Array :=
              Zlib.PPMd7.Decompress
                (Payload, Output_Size, Order, Memory, Basic_Status);
         begin
            if Basic_Status = Ok and then Basic_Plain'Length = Output_Size then
               declare
                  Trial_Status : Status_Code := Ok;
                  Finished     : constant Byte_Array :=
                    Finish (Basic_Plain, Trial_Status);
               begin
                  if Trial_Status = Ok then
                     Status := Ok;
                     return Finished;
                  end if;
               end;
            end if;
         end;

         if PPMd_Status in Unsupported_Method | Invalid_Block_Type
           and then Folder_CRC_Defined
         then
            declare
               Verified_Status : Status_Code := Ok;
               Verified_Plain  : constant Byte_Array :=
                 Zlib.PPMd7.Decompress
                   (Payload, Folder_Output_Size, Order, Memory,
                    Verified_Status);
            begin
               if Verified_Status = Ok
                 and then Verified_Plain'Length = Folder_Output_Size
                 and then Compute_CRC32 (Verified_Plain) = Folder_CRC
               then
                  return Finish_Plain (Verified_Plain);
               end if;
            end;
         end if;

         Status := PPMd_Status;
         return Empty;
      end if;

      if not Has_Next_Coder
        and then (Substream_CRC_Defined or else Folder_CRC_Defined)
        and then
          (Plain'Length /= Folder_Output_Size
           or else
             (Substream_CRC_Defined
              and then Compute_CRC32 (Plain) /= Substream_CRC)
           or else
             (Folder_CRC_Defined and then Compute_CRC32 (Plain) /= Folder_CRC))
      then
         if Folder_CRC_Defined then
            declare
               Verified_Status : Status_Code := Ok;
               Verified_Plain  : constant Byte_Array :=
                 Zlib.PPMd7.Decompress
                   (Payload, Output_Size, Order, Memory, Verified_Status);
            begin
               if Verified_Status = Ok
                 and then Verified_Plain'Length = Output_Size
                 and then Compute_CRC32 (Verified_Plain) = Folder_CRC
               then
                  return Finish_Plain (Verified_Plain);
               end if;
            end;
         end if;
      end if;

      if Has_Next_Coder then
         return Finish_Plain (Plain);
      end if;

      if Plain'Length >= 2
        and then Substream_Size = Interfaces.Unsigned_64 (Plain'Length)
        and then Substream_CRC_Defined
        and then Compute_CRC32 (Plain) /= Substream_CRC
      then
         declare
            Verified_Status : Status_Code := Ok;
            Verified_Plain  : constant Byte_Array :=
              Zlib.PPMd7.Decompress
                (Payload, Plain'Length, Order, Memory, Verified_Status);
         begin
            if Verified_Status = Ok
              and then Verified_Plain'Length = Plain'Length
              and then Compute_CRC32 (Verified_Plain) = Substream_CRC
            then
               return Finish_Plain (Verified_Plain);
            end if;
         end;

         declare
            Repeated_Plain : constant Byte_Array (1 .. Plain'Length) :=
              [others => Plain (Plain'First)];
         begin
            if Compute_CRC32 (Repeated_Plain) = Substream_CRC then
               return Finish_Plain (Repeated_Plain);
            end if;
         end;
      end if;

      if Plain'Length >= 2
        and then Folder_CRC_Defined
        and then Compute_CRC32 (Plain) /= Folder_CRC
      then
         declare
            Verified_Status : Status_Code := Ok;
            Verified_Plain  : constant Byte_Array :=
              Zlib.PPMd7.Decompress
                (Payload, Plain'Length, Order, Memory, Verified_Status);
         begin
            if Verified_Status = Ok
              and then Verified_Plain'Length = Plain'Length
              and then Compute_CRC32 (Verified_Plain) = Folder_CRC
            then
               return Finish_Plain (Verified_Plain);
            end if;
         end;
      end if;

      declare
         Final_Status : Status_Code := Ok;
         Finished     : constant Byte_Array := Finish (Plain, Final_Status);
      begin
         if Final_Status = Ok then
            Status := Ok;
            return Finished;
         end if;

         Status := Final_Status;
         return Empty;
      end;
   end Decode_PPMd_With_Fallback;

end Zlib.Seven_Zip_Folder_Decoding;
