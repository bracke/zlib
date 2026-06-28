with Ada.Command_Line;
with Ada.Text_IO;
with Zlib; use Zlib;

procedure Dictionary_Roundtrip is
   use type Zlib.Status_Code;

   Dictionary : constant Zlib.Byte_Array :=
     [1  => Zlib.Byte (Character'Pos ('p')),
      2  => Zlib.Byte (Character'Pos ('r')),
      3  => Zlib.Byte (Character'Pos ('e')),
      4  => Zlib.Byte (Character'Pos ('f')),
      5  => Zlib.Byte (Character'Pos ('i')),
      6  => Zlib.Byte (Character'Pos ('x')),
      7  => Zlib.Byte (Character'Pos ('-')),
      8  => Zlib.Byte (Character'Pos ('d')),
      9  => Zlib.Byte (Character'Pos ('a')),
      10 => Zlib.Byte (Character'Pos ('t')),
      11 => Zlib.Byte (Character'Pos ('a'))];

   Input : constant Zlib.Byte_Array :=
     [1 => Zlib.Byte (Character'Pos ('p')),
      2 => Zlib.Byte (Character'Pos ('r')),
      3 => Zlib.Byte (Character'Pos ('e')),
      4 => Zlib.Byte (Character'Pos ('f')),
      5 => Zlib.Byte (Character'Pos ('i')),
      6 => Zlib.Byte (Character'Pos ('x')),
      7 => Zlib.Byte (Character'Pos ('-')),
      8 => Zlib.Byte (Character'Pos ('d')),
      9 => Zlib.Byte (Character'Pos ('a')),
      10 => Zlib.Byte (Character'Pos ('t')),
      11 => Zlib.Byte (Character'Pos ('a')),
      12 => Zlib.Byte (Character'Pos ('-')),
      13 => Zlib.Byte (Character'Pos ('r')),
      14 => Zlib.Byte (Character'Pos ('e')),
      15 => Zlib.Byte (Character'Pos ('p')),
      16 => Zlib.Byte (Character'Pos ('e')),
      17 => Zlib.Byte (Character'Pos ('a')),
      18 => Zlib.Byte (Character'Pos ('t'))];

   Status : Zlib.Status_Code;
begin
   declare
      Compressed : constant Zlib.Byte_Array :=
        Zlib.Deflate_With_Dictionary (Input, Dictionary, Zlib.Auto, Status);
   begin
      if Status /= Zlib.Ok then
         Ada.Text_IO.Put_Line ("dictionary compression failed: " & Zlib.Status_Image (Status));
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;

      declare
         Decoded : constant Zlib.Byte_Array :=
           Zlib.Inflate_With_Dictionary (Compressed, Dictionary, Status);
      begin
         if Status /= Zlib.Ok or else Decoded /= Input then
            Ada.Text_IO.Put_Line ("dictionary roundtrip failed: " & Zlib.Status_Image (Status));
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
         end if;
      end;

      Ada.Text_IO.Put_Line
        ("dictionary roundtrip ok, output bytes:" & Natural'Image (Compressed'Length));
   end;
end Dictionary_Roundtrip;
