with Ada.Command_Line;
with Ada.Text_IO;
with Zlib; use Zlib;
with Zlib_Tool_Support;

procedure Zlib_Compress_File is
   use type Zlib.Status_Code;

   Status    : Zlib.Status_Code;
   Mode      : Zlib.Compression_Mode := Zlib.Auto;
   Level     : Zlib.Compression_Level := Zlib.Default_Level;
   Use_Level : Boolean := False;

   function Mode_For_Level
     (Value : Zlib.Compression_Level)
      return Zlib.Compression_Mode
   is
   begin
      if Value = 0 then
         return Zlib.Stored;
      elsif Value = 1 then
         return Zlib.Fixed;
      else
         return Zlib.Auto;
      end if;
   end Mode_For_Level;

   procedure Usage is
   begin
      Ada.Text_IO.Put_Line
        ("usage: zlib_compress_file (--mode=stored|fixed|dynamic|auto | --level=0..9) INPUT OUTPUT");
   end Usage;
begin
   if Ada.Command_Line.Argument_Count /= 3 then
      Usage;
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   if Ada.Command_Line.Argument (1)'Length >= 7
     and then Ada.Command_Line.Argument (1)
       (Ada.Command_Line.Argument (1)'First .. Ada.Command_Line.Argument (1)'First + 6) = "--mode="
   then
      Mode := Zlib_Tool_Support.Mode_From_Option (Ada.Command_Line.Argument (1), Status);
   else
      Level := Zlib_Tool_Support.Level_From_Option (Ada.Command_Line.Argument (1), Status);
      Mode := Mode_For_Level (Level);
      Use_Level := True;
   end if;

   if Status /= Zlib.Ok then
      Usage;
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   Zlib.Deflate_File_Streaming
     (Input_Path  => Ada.Command_Line.Argument (2),
      Output_Path => Ada.Command_Line.Argument (3),
      Header      => Zlib.Zlib_Header,
      Mode        => Mode,
      Status      => Status);

   if Status /= Zlib.Ok then
      Ada.Text_IO.Put_Line (Zlib.Status_Image (Status));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
exception
   when others =>
      if Use_Level then
         Ada.Text_IO.Put_Line ("zlib_compress_file failed for requested level");
      else
         Ada.Text_IO.Put_Line ("zlib_compress_file failed");
      end if;
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Zlib_Compress_File;
