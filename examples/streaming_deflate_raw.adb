with Ada.Command_Line;
with Ada.Text_IO;
with Example_Raw_Support;
with Zlib;

procedure Streaming_Deflate_Raw is
   use type Zlib.Status_Code;

   Input  : constant Zlib.Byte_Array := Example_Raw_Support.Plain;
   Raw    : Zlib.Byte_Array :=
     Example_Raw_Support.Streaming_Compress (Input, Zlib.Raw_Deflate, Zlib.Auto);
   Status : Zlib.Status_Code;
   Check  : constant Zlib.Byte_Array :=
     Zlib.Inflate_With_Header (Raw, Zlib.Raw_Deflate, Status);
begin
   if Status /= Zlib.Ok or else not Example_Raw_Support.Equal (Input, Check) then
      Ada.Text_IO.Put_Line ("streaming raw Deflate example failed");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   Ada.Text_IO.Put_Line
     ("streaming raw Deflate bytes:" & Natural'Image (Raw'Length));
exception
   when Zlib.Zlib_Error | Zlib.Status_Error =>
      Ada.Text_IO.Put_Line ("streaming raw Deflate example raised Zlib error");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Streaming_Deflate_Raw;
