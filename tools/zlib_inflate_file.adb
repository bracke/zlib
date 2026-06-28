with Ada.Command_Line;
with Ada.Text_IO;
with Zlib;

procedure Zlib_Inflate_File is
   use type Zlib.Status_Code;

   Status : Zlib.Status_Code;

   function Header_From_Option
     (Option : String)
      return Zlib.Header_Type
   is
   begin
      if Option = "--header=zlib" then
         return Zlib.Zlib_Header;
      elsif Option = "--header=gzip" then
         return Zlib.GZip;
      elsif Option = "--header=raw" then
         return Zlib.Raw_Deflate;
      else
         Status := Zlib.Invalid_Header;
         return Zlib.Zlib_Header;
      end if;
   end Header_From_Option;

   procedure Usage is
   begin
      Ada.Text_IO.Put_Line
        ("usage: zlib_inflate_file [--header=zlib|gzip|raw] INPUT OUTPUT");
   end Usage;

   Header     : Zlib.Header_Type := Zlib.Zlib_Header;
   Input_Arg  : Positive := 1;
   Output_Arg : Positive := 2;
begin
   Status := Zlib.Ok;

   if Ada.Command_Line.Argument_Count = 3 then
      Header := Header_From_Option (Ada.Command_Line.Argument (1));
      Input_Arg := 2;
      Output_Arg := 3;
   elsif Ada.Command_Line.Argument_Count /= 2 then
      Usage;
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   if Status /= Zlib.Ok then
      Usage;
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   Zlib.Inflate_File_Streaming
     (Input_Path  => Ada.Command_Line.Argument (Input_Arg),
      Output_Path => Ada.Command_Line.Argument (Output_Arg),
      Header      => Header,
      Status      => Status);

   if Status /= Zlib.Ok then
      Ada.Text_IO.Put_Line (Zlib.Status_Image (Status));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Zlib_Inflate_File;
