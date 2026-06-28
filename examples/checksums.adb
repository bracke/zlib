with Ada.Text_IO;
with Interfaces;
with Zlib;

procedure Checksums is
   Input : constant Zlib.Byte_Array :=
     [1 => Zlib.Byte (Character'Pos ('h')),
      2 => Zlib.Byte (Character'Pos ('e')),
      3 => Zlib.Byte (Character'Pos ('l')),
      4 => Zlib.Byte (Character'Pos ('l')),
      5 => Zlib.Byte (Character'Pos ('o'))];

   Adler : constant Interfaces.Unsigned_32 := Zlib.Adler32 (Input);
   CRC   : constant Interfaces.Unsigned_32 := Zlib.CRC32 (Input);
begin
   Ada.Text_IO.Put_Line ("Adler-32:" & Interfaces.Unsigned_32'Image (Adler));
   Ada.Text_IO.Put_Line ("CRC-32:" & Interfaces.Unsigned_32'Image (CRC));
end Checksums;
