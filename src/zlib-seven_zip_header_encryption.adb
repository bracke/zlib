with Interfaces;
with Zlib.Seven_Zip_AES;
with Zlib.Seven_Zip_Container;

package body Zlib.Seven_Zip_Header_Encryption is

   use type Interfaces.Unsigned_64;

   function Encrypt_Header
     (Archive       : Byte_Array;
      Password      : String;
      Encode_Header : not null access function
        (Input : Byte_Array; LZMA_Props : in out Byte) return Byte_Array;
      Status        : out Status_Code) return Byte_Array
   is
      Empty : constant Byte_Array (1 .. 0) := [others => 0];

      function U64_At (Off : Natural) return Interfaces.Unsigned_64 is
         R : Interfaces.Unsigned_64 := 0;
      begin
         for I in 0 .. 7 loop
            R := R + Interfaces.Shift_Left
              (Interfaces.Unsigned_64 (Archive (Archive'First + Off + I)),
               8 * I);
         end loop;
         return R;
      end U64_At;
   begin
      Status := Unsupported_Method;
      if Archive'Length < 32
        or else Archive (Archive'First) /= 16#37#
        or else Archive (Archive'First + 1) /= 16#7A#
      then
         return Empty;
      end if;

      declare
         NHO  : constant Natural := Natural (U64_At (12));
         NHS  : constant Natural := Natural (U64_At (20));
         Base : constant Natural := Archive'First + 32;
      begin
         if NHS = 0 or else Base + NHO + NHS - 1 > Archive'Last then
            return Empty;
         end if;

         declare
            Main_Pack  : constant Byte_Array :=
              Archive (Base .. Base + NHO - 1);
            Plain_Hdr  : constant Byte_Array :=
              Archive (Base + NHO .. Base + NHO + NHS - 1);
            LZMA_Props : Byte := 16#5D#;
            HC         : constant Byte_Array :=
              Encode_Header (Plain_Hdr, LZMA_Props);
            IV         : constant Byte_Array := Zlib.Seven_Zip_AES.Random_IV;
            Key        : constant Byte_Array :=
              Zlib.Seven_Zip_AES.Derive_Key (Password, Empty, 19);
            HE         : constant Byte_Array :=
              Zlib.Seven_Zip_AES.Encrypt_CBC
                (Key, IV, Zlib.Seven_Zip_AES.Pad_To_Block (HC));
         begin
            if HE'Length = 0 then
               return Empty;
            end if;

            return
              Zlib.Seven_Zip_Container.Encrypted_Header_Archive
                (Main_Pack, HE, HC'Length, Plain_Hdr'Length, IV, LZMA_Props,
                 Status);
         end;
      end;
   exception
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end Encrypt_Header;

end Zlib.Seven_Zip_Header_Encryption;
