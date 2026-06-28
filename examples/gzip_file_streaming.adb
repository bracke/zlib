with Ada.Command_Line;
with Ada.Text_IO;
with Zlib; use Zlib;

procedure GZip_File_Streaming is
   Status : Zlib.Status_Code;
begin
   if Ada.Command_Line.Argument_Count /= 2 then
      Ada.Text_IO.Put_Line ("usage: gzip_file_streaming INPUT OUTPUT.gz");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   Zlib.GZip_File_Streaming
     (Input_Path  => Ada.Command_Line.Argument (1),
      Output_Path => Ada.Command_Line.Argument (2),
      Mode        => Zlib.Auto,
      Status      => Status);

   if Status /= Zlib.Ok then
      Ada.Text_IO.Put_Line (Zlib.Status_Image (Status));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end GZip_File_Streaming;
