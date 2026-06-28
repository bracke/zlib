with Ada.Command_Line;
with Ada.Text_IO;
with Zlib;
with Zlib_Tool_Support;

procedure Gzip_Streaming_Roundtrip is
   use type Zlib.Byte;
   use type Zlib.Status_Code;

   Status : Zlib.Status_Code;
   Mode   : Zlib.Compression_Mode;

   procedure Usage is
   begin
      Ada.Text_IO.Put_Line
        ("usage: gzip_streaming_roundtrip --mode=stored|fixed|dynamic|auto INPUT");
   end Usage;
begin
   if Ada.Command_Line.Argument_Count /= 2 then
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
      Input : constant Zlib.Byte_Array :=
        Zlib_Tool_Support.Read_File (Ada.Command_Line.Argument (2), Status);
   begin
      if Status /= Zlib.Ok then
         Ada.Text_IO.Put_Line (Zlib.Status_Image (Status));
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;

      declare
         Compressed : constant Zlib.Byte_Array :=
           Zlib_Tool_Support.Streaming_Compress (Input, Zlib.GZip, Mode);
         Decoded    : constant Zlib.Byte_Array :=
           Zlib.Inflate_With_Header (Compressed, Zlib.GZip, Status);
      begin
         if Status /= Zlib.Ok then
            Ada.Text_IO.Put_Line (Zlib.Status_Image (Status));
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
         end if;

         if Decoded'Length /= Input'Length then
            Ada.Text_IO.Put_Line ("gzip roundtrip length mismatch");
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
         end if;

         for I in Input'Range loop
            if Decoded (Decoded'First + (I - Input'First)) /= Input (I) then
               Ada.Text_IO.Put_Line ("gzip roundtrip payload mismatch");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               return;
            end if;
         end loop;
      end;
   end;

   Ada.Text_IO.Put_Line ("gzip streaming roundtrip ok");
exception
   when Zlib.Zlib_Error =>
      Ada.Text_IO.Put_Line ("gzip streaming roundtrip zlib error");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   when Zlib.Status_Error =>
      Ada.Text_IO.Put_Line ("gzip streaming roundtrip lifecycle error");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   when others =>
      Ada.Text_IO.Put_Line ("gzip_streaming_roundtrip failed");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Gzip_Streaming_Roundtrip;
