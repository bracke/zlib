with Ada.Command_Line;
with Ada.Text_IO;
with Zlib;

procedure Raw_Inflate_File is
   use type Zlib.Status_Code;

   Status : Zlib.Status_Code;

   procedure Usage is
   begin
      Ada.Text_IO.Put_Line ("usage: raw_inflate_file INPUT OUTPUT");
   end Usage;
begin
   if Ada.Command_Line.Argument_Count /= 2 then
      Usage;
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   Zlib.Inflate_Raw_File_Streaming
     (Input_Path  => Ada.Command_Line.Argument (1),
      Output_Path => Ada.Command_Line.Argument (2),
      Status      => Status);

   if Status /= Zlib.Ok then
      Ada.Text_IO.Put_Line (Zlib.Status_Image (Status));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
exception
   when others =>
      Ada.Text_IO.Put_Line ("raw_inflate_file failed");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Raw_Inflate_File;
