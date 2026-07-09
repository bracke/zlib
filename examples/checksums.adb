with Ada.Command_Line;
with Ada.Text_IO;
with Zlib;

procedure Checksums is
   Input : constant Zlib.Byte_Array :=
     [1 => Zlib.Byte (Character'Pos ('h')),
      2 => Zlib.Byte (Character'Pos ('e')),
      3 => Zlib.Byte (Character'Pos ('l')),
      4 => Zlib.Byte (Character'Pos ('l')),
      5 => Zlib.Byte (Character'Pos ('o'))];

   Zlib_Bound : constant Natural := Zlib.Deflate_Bound (Input'Length);
   GZip_Bound : constant Natural := Zlib.GZip_Bound (Input'Length);
   Raw_Bound  : constant Natural := Zlib.Deflate_Raw_Bound (Input'Length);
begin
   Ada.Text_IO.Put_Line ("zlib bound:" & Natural'Image (Zlib_Bound));
   Ada.Text_IO.Put_Line ("gzip bound:" & Natural'Image (GZip_Bound));
   Ada.Text_IO.Put_Line ("raw bound:" & Natural'Image (Raw_Bound));

   if Zlib_Bound < Input'Length
     or else GZip_Bound < Input'Length
     or else Raw_Bound < Input'Length
   then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Checksums;
