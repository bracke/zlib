package body Zlib_Public_Checksum_Client is
   Hello : constant Zlib.Byte_Array :=
     [1 => Zlib.Byte (Character'Pos ('h')),
      2 => Zlib.Byte (Character'Pos ('e')),
      3 => Zlib.Byte (Character'Pos ('l')),
      4 => Zlib.Byte (Character'Pos ('l')),
      5 => Zlib.Byte (Character'Pos ('o'))];

   function Checksums_Are_Available return Boolean is
   begin
      declare
         State : Zlib.CRC32_State;
      begin
         Zlib.CRC32_Reset (State);
         return Zlib.Adler32 (Hello)'Image'Length > 0
           and then Zlib.CRC32 (Hello)'Image'Length > 0
           and then Zlib.CRC32_Value (State)'Image'Length > 0;
      end;
   end Checksums_Are_Available;
end Zlib_Public_Checksum_Client;
