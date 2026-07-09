package body Zlib_Public_Checksum_Client is
   Hello : constant Zlib.Byte_Array :=
     [1 => Zlib.Byte (Character'Pos ('h')),
      2 => Zlib.Byte (Character'Pos ('e')),
      3 => Zlib.Byte (Character'Pos ('l')),
      4 => Zlib.Byte (Character'Pos ('l')),
      5 => Zlib.Byte (Character'Pos ('o'))];

   function Checksums_Are_Available return Boolean is
   begin
      return Zlib.Deflate_Bound (Hello'Length) >= Hello'Length
        and then Zlib.GZip_Bound (Hello'Length) >= Hello'Length
        and then Zlib.Deflate_Raw_Bound (Hello'Length) >= Hello'Length;
   end Checksums_Are_Available;
end Zlib_Public_Checksum_Client;
