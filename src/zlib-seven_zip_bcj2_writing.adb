with Ada.Streams;
with CryptoLib.Checksums;
with Interfaces;
with Zlib.Seven_Zip_Container;
with Zlib.Seven_Zip_Filters;
with Zlib.Seven_Zip_Paths;

package body Zlib.Seven_Zip_BCJ2_Writing is

   function Compute_CRC32 (Data : Byte_Array) return Interfaces.Unsigned_32 is
      State : CryptoLib.Checksums.CRC32_State;
   begin
      CryptoLib.Checksums.CRC32_Reset (State);
      for B of Data loop
         CryptoLib.Checksums.CRC32_Update (State, Ada.Streams.Stream_Element (B));
      end loop;
      return CryptoLib.Checksums.CRC32_Value (State);
   end Compute_CRC32;

   function Build_BCJ2
     (Input      : Byte_Array;
      Entry_Name : String;
      Status     : out Status_Code) return Byte_Array
   is
      Empty : constant Byte_Array (1 .. 0) := [others => 0];
   begin
      Status := Unsupported_Method;
      if not Zlib.Seven_Zip_Paths.Entry_Name_Valid (Entry_Name) then
         return Empty;
      end if;

      declare
         Streams : constant Zlib.Seven_Zip_Filters.BCJ2_Encoded_Streams :=
           Zlib.Seven_Zip_Filters.BCJ2_Encode (Input);
      begin
         return
           Zlib.Seven_Zip_Container.BCJ2_Archive
             (Streams, Entry_Name, Input'Length, Compute_CRC32 (Input), Status);
      end;
   exception
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end Build_BCJ2;

end Zlib.Seven_Zip_BCJ2_Writing;
