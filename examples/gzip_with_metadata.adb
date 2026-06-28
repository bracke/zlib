with Ada.Command_Line;
with Ada.Text_IO;
with Zlib; use Zlib;

procedure GZip_With_Metadata is
   use type Zlib.Status_Code;

   Input : constant Zlib.Byte_Array :=
     [1 => Zlib.Byte (Character'Pos ('h')),
      2 => Zlib.Byte (Character'Pos ('e')),
      3 => Zlib.Byte (Character'Pos ('l')),
      4 => Zlib.Byte (Character'Pos ('l')),
      5 => Zlib.Byte (Character'Pos ('o'))];

   Metadata : Zlib.GZip_Metadata := Zlib.No_GZip_Metadata;
   Status   : Zlib.Status_Code;
begin
   Zlib.Set_Name (Metadata, "hello.txt");
   Zlib.Set_Comment (Metadata, "example gzip metadata");
   Zlib.Set_MTime (Metadata, 0);
   Zlib.Set_OS (Metadata, 255);
   Zlib.Set_XFL (Metadata, 0);
   Zlib.Set_Extra (Metadata, [1 => 16#41#, 2 => 16#42#]);
   Zlib.Set_Header_CRC (Metadata, True);

   declare
      Compressed : constant Zlib.Byte_Array :=
        Zlib.GZip (Input, Zlib.Auto, Metadata, Status);
   begin
      if Status /= Zlib.Ok then
         Ada.Text_IO.Put_Line ("gzip failed: " & Zlib.Status_Image (Status));
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;

      declare
         Decoded : constant Zlib.Byte_Array :=
           Zlib.Inflate_With_Header (Compressed, Zlib.GZip, Status);
      begin
         if Status /= Zlib.Ok or else Decoded /= Input then
            Ada.Text_IO.Put_Line ("gzip metadata roundtrip failed: " & Zlib.Status_Image (Status));
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
         end if;
      end;

      Ada.Text_IO.Put_Line
        ("gzip metadata roundtrip ok, output bytes:" & Natural'Image (Compressed'Length));
   end;
end GZip_With_Metadata;
