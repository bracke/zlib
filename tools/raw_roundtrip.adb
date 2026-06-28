with Ada.Command_Line;
with Ada.Text_IO;
with Zlib;
with Zlib_Tool_Support;

procedure Raw_Roundtrip is
   use type Zlib.Byte;
   use type Zlib.Status_Code;

   Status : Zlib.Status_Code;

   function Same
     (Left  : Zlib.Byte_Array;
      Right : Zlib.Byte_Array)
      return Boolean
   is
   begin
      if Left'Length /= Right'Length then
         return False;
      end if;

      for I in Left'Range loop
         if Left (I) /= Right (Right'First + (I - Left'First)) then
            return False;
         end if;
      end loop;

      return True;
   end Same;

   procedure Usage is
   begin
      Ada.Text_IO.Put_Line ("usage: raw_roundtrip INPUT");
   end Usage;
begin
   if Ada.Command_Line.Argument_Count /= 1 then
      Usage;
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   declare
      Input : constant Zlib.Byte_Array :=
        Zlib_Tool_Support.Read_File (Ada.Command_Line.Argument (1), Status);
   begin
      if Status /= Zlib.Ok then
         Ada.Text_IO.Put_Line (Zlib.Status_Image (Status));
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;

      for Mode in Zlib.Compression_Mode loop
         declare
            Compressed : constant Zlib.Byte_Array :=
              Zlib_Tool_Support.Streaming_Compress (Input, Zlib.Raw_Deflate, Mode);
            Decoded    : constant Zlib.Byte_Array :=
              Zlib.Inflate_With_Header (Compressed, Zlib.Raw_Deflate, Status);
         begin
            if Status /= Zlib.Ok or else not Same (Input, Decoded) then
               Ada.Text_IO.Put_Line
                 ("raw roundtrip failed for " & Zlib.Compression_Mode'Image (Mode));
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               return;
            end if;
         end;
      end loop;
   end;

   Ada.Text_IO.Put_Line ("raw roundtrip ok");
exception
   when Zlib.Zlib_Error =>
      Ada.Text_IO.Put_Line ("raw roundtrip zlib error");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   when Zlib.Status_Error =>
      Ada.Text_IO.Put_Line ("raw roundtrip lifecycle error");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   when others =>
      Ada.Text_IO.Put_Line ("raw_roundtrip failed");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Raw_Roundtrip;
