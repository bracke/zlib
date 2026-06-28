with Ada.Command_Line;
with Ada.Text_IO;
with Example_Raw_Support;
with Zlib;

procedure Raw_Roundtrip is
   use type Zlib.Status_Code;

   Input  : constant Zlib.Byte_Array := Example_Raw_Support.Plain;
   Status : Zlib.Status_Code;
   Raw    : constant Zlib.Byte_Array := Zlib.Deflate_Raw (Input, Zlib.Dynamic, Status);
begin
   if Status /= Zlib.Ok then
      Ada.Text_IO.Put_Line ("raw compression failed: " & Zlib.Status_Image (Status));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   declare
      Decoded_One_Shot : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Raw, Zlib.Raw_Deflate, Status);
   begin
      if Status /= Zlib.Ok or else not Example_Raw_Support.Equal (Input, Decoded_One_Shot) then
         Ada.Text_IO.Put_Line ("one-shot raw inflate roundtrip failed");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;
   end;

   declare
      Decoded_Streaming : constant Zlib.Byte_Array :=
        Example_Raw_Support.Streaming_Inflate (Raw, Zlib.Raw_Deflate);
   begin
      if not Example_Raw_Support.Equal (Input, Decoded_Streaming) then
         Ada.Text_IO.Put_Line ("streaming raw inflate roundtrip failed");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;
   end;

   Ada.Text_IO.Put_Line ("raw one-shot/streaming roundtrip ok");
exception
   when Zlib.Zlib_Error | Zlib.Status_Error =>
      Ada.Text_IO.Put_Line ("raw roundtrip example raised Zlib error");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Raw_Roundtrip;
