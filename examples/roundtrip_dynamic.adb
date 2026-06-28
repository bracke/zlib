with Ada.Command_Line;
with Ada.Text_IO;
with Zlib; use Zlib;

procedure Roundtrip_Dynamic is
   Input : constant Zlib.Byte_Array :=
     [1  => Zlib.Byte (Character'Pos ('d')),
      2  => Zlib.Byte (Character'Pos ('y')),
      3  => Zlib.Byte (Character'Pos ('n')),
      4  => Zlib.Byte (Character'Pos ('a')),
      5  => Zlib.Byte (Character'Pos ('m')),
      6  => Zlib.Byte (Character'Pos ('i')),
      7  => Zlib.Byte (Character'Pos ('c')),
      8  => Zlib.Byte (Character'Pos (' ')),
      9  => Zlib.Byte (Character'Pos ('z')),
      10 => Zlib.Byte (Character'Pos ('l')),
      11 => Zlib.Byte (Character'Pos ('i')),
      12 => Zlib.Byte (Character'Pos ('b'))];

   Status : Zlib.Status_Code;
begin
   declare
      Compressed : constant Zlib.Byte_Array := Zlib.Deflate_Dynamic (Input, Status);
   begin
      if Status /= Zlib.Ok then
         Ada.Text_IO.Put_Line ("dynamic compression failed: " & Zlib.Status_Image (Status));
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;

      declare
         Output : constant Zlib.Byte_Array := Zlib.Inflate (Compressed, Status);
      begin
         if Status = Zlib.Ok and then Output = Input then
            Ada.Text_IO.Put_Line ("dynamic roundtrip ok");
         else
            Ada.Text_IO.Put_Line ("dynamic inflate failed: " & Zlib.Status_Image (Status));
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         end if;
      end;
   end;
end Roundtrip_Dynamic;
