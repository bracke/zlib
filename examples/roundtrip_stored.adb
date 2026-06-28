with Ada.Command_Line;
with Ada.Text_IO;
with Zlib; use Zlib;

procedure Roundtrip_Stored is
   Input : constant Zlib.Byte_Array :=
     [1 => Zlib.Byte (Character'Pos ('h')),
      2 => Zlib.Byte (Character'Pos ('e')),
      3 => Zlib.Byte (Character'Pos ('l')),
      4 => Zlib.Byte (Character'Pos ('l')),
      5 => Zlib.Byte (Character'Pos ('o'))];

   Status : Zlib.Status_Code;
begin
   declare
      Compressed : constant Zlib.Byte_Array := Zlib.Deflate_Stored (Input, Status);
   begin
      if Status /= Zlib.Ok then
         Ada.Text_IO.Put_Line ("stored compression failed: " & Zlib.Status_Image (Status));
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;

      declare
         Output : constant Zlib.Byte_Array := Zlib.Inflate (Compressed, Status);
      begin
         if Status = Zlib.Ok and then Output = Input then
            Ada.Text_IO.Put_Line ("roundtrip ok");
         else
            Ada.Text_IO.Put_Line ("stored inflate failed: " & Zlib.Status_Image (Status));
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         end if;
      end;
   end;
end Roundtrip_Stored;
