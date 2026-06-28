with Ada.Command_Line;
with Ada.Text_IO;
with Zlib; use Zlib;

procedure Zlib_Deflate_Dynamic_File is
   Status : Zlib.Status_Code;
begin
   if Ada.Command_Line.Argument_Count /= 2 then
      Ada.Text_IO.Put_Line ("usage: zlib_deflate_dynamic_file INPUT OUTPUT.z");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   Zlib.Deflate_Dynamic_File
     (Input_Path  => Ada.Command_Line.Argument (1),
      Output_Path => Ada.Command_Line.Argument (2),
      Status      => Status);

   if Status /= Zlib.Ok then
      Ada.Text_IO.Put_Line (Zlib.Status_Image (Status));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Zlib_Deflate_Dynamic_File;
