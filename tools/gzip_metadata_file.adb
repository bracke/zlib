with Ada.Command_Line;
with Ada.Text_IO;
with Interfaces;
with Zlib;
with Zlib_Tool_Support;

procedure Gzip_Metadata_File is
   use type Zlib.Status_Code;

   Status   : Zlib.Status_Code;
   Mode     : Zlib.Compression_Mode;
   Metadata : Zlib.GZip_Metadata := Zlib.No_GZip_Metadata;

   procedure Usage is
   begin
      Ada.Text_IO.Put_Line
        ("usage: gzip_metadata_file --mode=stored|fixed|dynamic|auto "
         & "--name=NAME --comment=COMMENT --mtime=U32 --os=BYTE INPUT OUTPUT");
   end Usage;

   function Value_After
     (Text   : String;
      Prefix : String)
      return String
   is
   begin
      if Text'Length <= Prefix'Length
        or else Text (Text'First .. Text'First + Prefix'Length - 1) /= Prefix
      then
         return "";
      end if;

      return Text (Text'First + Prefix'Length .. Text'Last);
   end Value_After;

   function U32_From_Option
     (Text   : String;
      Prefix : String;
      OK     : out Boolean)
      return Interfaces.Unsigned_32
   is
      Value_Text : constant String := Value_After (Text, Prefix);
   begin
      OK := Value_Text'Length > 0;
      if not OK then
         return 0;
      end if;
      return Interfaces.Unsigned_32'Value (Value_Text);
   exception
      when others =>
         OK := False;
         return 0;
   end U32_From_Option;

   function Byte_From_Option
     (Text   : String;
      Prefix : String;
      OK     : out Boolean)
      return Zlib.Byte
   is
      Value_Text : constant String := Value_After (Text, Prefix);
      N          : Integer;
   begin
      OK := Value_Text'Length > 0;
      if not OK then
         return 0;
      end if;
      N := Integer'Value (Value_Text);
      OK := N >= 0 and then N <= 255;
      if OK then
         return Zlib.Byte (N);
      else
         return 0;
      end if;
   exception
      when others =>
         OK := False;
         return 0;
   end Byte_From_Option;

   OK : Boolean;
begin
   if Ada.Command_Line.Argument_Count /= 7 then
      Usage;
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   Mode := Zlib_Tool_Support.Mode_From_Option (Ada.Command_Line.Argument (1), Status);
   if Status /= Zlib.Ok then
      Usage;
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   declare
      Name : constant String := Value_After (Ada.Command_Line.Argument (2), "--name=");
   begin
      if Name'Length = 0 and then Ada.Command_Line.Argument (2) /= "--name=" then
         Usage;
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;
      Zlib.Set_Name (Metadata, Name);
   end;

   declare
      Comment : constant String := Value_After (Ada.Command_Line.Argument (3), "--comment=");
   begin
      if Comment'Length = 0 and then Ada.Command_Line.Argument (3) /= "--comment=" then
         Usage;
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;
      Zlib.Set_Comment (Metadata, Comment);
   end;

   Zlib.Set_MTime
     (Metadata,
      U32_From_Option (Ada.Command_Line.Argument (4), "--mtime=", OK));
   if not OK then
      Usage;
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   Zlib.Set_OS
     (Metadata,
      Byte_From_Option (Ada.Command_Line.Argument (5), "--os=", OK));
   if not OK then
      Usage;
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   Zlib.Set_Header_CRC (Metadata, True);
   Zlib.GZip_File
     (Input_Path  => Ada.Command_Line.Argument (6),
      Output_Path => Ada.Command_Line.Argument (7),
      Mode        => Mode,
      Metadata    => Metadata,
      Status      => Status);

   if Status /= Zlib.Ok then
      Ada.Text_IO.Put_Line (Zlib.Status_Image (Status));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
exception
   when others =>
      Ada.Text_IO.Put_Line ("gzip_metadata_file failed");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Gzip_Metadata_File;
