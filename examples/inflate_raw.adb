with Ada.Command_Line;
with Ada.Text_IO;
with Zlib;

procedure Inflate_Raw is
   use type Zlib.Status_Code;

   Status : Zlib.Status_Code;

   Raw_Hello : constant Zlib.Byte_Array :=
     [1 => 16#01#, 2 => 16#05#, 3 => 16#00#, 4 => 16#FA#, 5 => 16#FF#,
      6 => 16#68#, 7 => 16#65#, 8 => 16#6C#, 9 => 16#6C#, 10 => 16#6F#];

   Output : constant Zlib.Byte_Array := Zlib.Inflate_Raw (Raw_Hello, Status);
   pragma Unreferenced (Output);
begin
   Ada.Text_IO.Put_Line ("raw inflate: " & Zlib.Status_Image (Status));
   if Status /= Zlib.Ok then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Inflate_Raw;
