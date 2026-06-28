with Ada.Command_Line;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;
with Interfaces;
with Zlib;

procedure Deflate_Raw_File_To_Stream is
   use type Zlib.Status_Code;
   package SIO renames Ada.Streams.Stream_IO;

   Output          : SIO.File_Type;
   Status          : Zlib.Status_Code;
   Compressed_Size : Interfaces.Unsigned_64 := 0;
begin
   if Ada.Command_Line.Argument_Count /= 2 then
      Ada.Text_IO.Put_Line ("usage: deflate_raw_file_to_stream INPUT OUTPUT.deflate");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   SIO.Create (Output, SIO.Out_File, Ada.Command_Line.Argument (2));
   Zlib.Deflate_Raw_File_To_Stream
     (Input_Path      => Ada.Command_Line.Argument (1),
      Output          => Output,
      Mode            => Zlib.Auto,
      Compressed_Size => Compressed_Size,
      Status          => Status);
   SIO.Close (Output);

   if Status /= Zlib.Ok then
      Ada.Text_IO.Put_Line (Zlib.Status_Image (Status));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   else
      Ada.Text_IO.Put_Line (Interfaces.Unsigned_64'Image (Compressed_Size));
   end if;
end Deflate_Raw_File_To_Stream;
