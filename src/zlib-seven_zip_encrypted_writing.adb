with Ada.Streams;
with CryptoLib.Checksums;
with Interfaces;
with Zlib.Seven_Zip_AES;
with Zlib.Seven_Zip_Container;
with Zlib.Seven_Zip_Paths;

package body Zlib.Seven_Zip_Encrypted_Writing is

   function Compute_CRC32 (Data : Byte_Array) return Interfaces.Unsigned_32 is
      State : CryptoLib.Checksums.CRC32_State;
   begin
      CryptoLib.Checksums.CRC32_Reset (State);
      for B of Data loop
         CryptoLib.Checksums.CRC32_Update (State, Ada.Streams.Stream_Element (B));
      end loop;
      return CryptoLib.Checksums.CRC32_Value (State);
   end Compute_CRC32;

   function Build_AES_LZMA
     (Input       : Byte_Array;
      Entry_Name  : String;
      Password    : String;
      Encode_LZMA : not null access function
        (Input : Byte_Array; LZMA_Props : in out Byte) return Byte_Array;
      Status      : out Status_Code) return Byte_Array
   is
      Empty            : constant Byte_Array (1 .. 0) := [others => 0];
      Num_Cycles_Power : constant := 19;
   begin
      Status := Unsupported_Method;
      if not Zlib.Seven_Zip_Paths.Entry_Name_Valid (Entry_Name) then
         return Empty;
      end if;

      declare
         LZMA_Props : Byte := 16#5D#;
         Compressed : constant Byte_Array := Encode_LZMA (Input, LZMA_Props);
         Padded     : constant Byte_Array :=
           Zlib.Seven_Zip_AES.Pad_To_Block (Compressed);
         Key        : constant Byte_Array :=
           Zlib.Seven_Zip_AES.Derive_Key (Password, Empty, Num_Cycles_Power);
         IV         : constant Byte_Array := Zlib.Seven_Zip_AES.Random_IV;
         Pack_V     : constant Byte_Array :=
           Zlib.Seven_Zip_AES.Encrypt_CBC (Key, IV, Padded);
      begin
         return
           Zlib.Seven_Zip_Container.AES_LZMA_Archive
             (Pack_V, Entry_Name, Compressed'Length, Input'Length,
              Compute_CRC32 (Input), IV, LZMA_Props, Status);
      end;
   exception
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end Build_AES_LZMA;

end Zlib.Seven_Zip_Encrypted_Writing;
