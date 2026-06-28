with Ada.Command_Line;
with Ada.Text_IO;
with Zlib; use Zlib;

procedure Compress_With_Level is
   use type Zlib.Status_Code;

   Input : constant Zlib.Byte_Array :=
     [1  => Zlib.Byte (Character'Pos ('l')),
      2  => Zlib.Byte (Character'Pos ('e')),
      3  => Zlib.Byte (Character'Pos ('v')),
      4  => Zlib.Byte (Character'Pos ('e')),
      5  => Zlib.Byte (Character'Pos ('l')),
      6  => Zlib.Byte (Character'Pos (' ')),
      7  => Zlib.Byte (Character'Pos ('a')),
      8  => Zlib.Byte (Character'Pos ('p')),
      9  => Zlib.Byte (Character'Pos ('i')),
      10 => Zlib.Byte (Character'Pos (' ')),
      11 => Zlib.Byte (Character'Pos ('p')),
      12 => Zlib.Byte (Character'Pos ('a')),
      13 => Zlib.Byte (Character'Pos ('y')),
      14 => Zlib.Byte (Character'Pos ('l')),
      15 => Zlib.Byte (Character'Pos ('o')),
      16 => Zlib.Byte (Character'Pos ('a')),
      17 => Zlib.Byte (Character'Pos ('d'))];

   procedure Check
     (Label      : String;
      Compressed : Zlib.Byte_Array;
      Header     : Zlib.Header_Type;
      Status     : in out Zlib.Status_Code)
   is
   begin
      if Status /= Zlib.Ok then
         Ada.Text_IO.Put_Line (Label & " compression failed: " & Zlib.Status_Image (Status));
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;

      declare
         Decoded : constant Zlib.Byte_Array :=
           Zlib.Inflate_With_Header (Compressed, Header, Status);
      begin
         if Status /= Zlib.Ok or else Decoded /= Input then
            Ada.Text_IO.Put_Line (Label & " roundtrip failed: " & Zlib.Status_Image (Status));
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
         end if;
      end;

      Ada.Text_IO.Put_Line
        (Label & " compressed" & Natural'Image (Input'Length) & " bytes to" &
         Natural'Image (Compressed'Length) & " bytes using Default_Level");
   end Check;

   Status : Zlib.Status_Code := Zlib.Ok;
begin
   declare
      Compressed : constant Zlib.Byte_Array :=
        Zlib.Deflate (Input, Zlib.Default_Level, Status);
   begin
      Check ("zlib", Compressed, Zlib.Zlib_Header, Status);
      if Status /= Zlib.Ok then
         return;
      end if;
   end;

   declare
      Compressed : constant Zlib.Byte_Array :=
        Zlib.GZip (Input, Zlib.Default_Level, Status);
   begin
      Check ("gzip", Compressed, Zlib.GZip, Status);
      if Status /= Zlib.Ok then
         return;
      end if;
   end;

   declare
      Compressed : constant Zlib.Byte_Array :=
        Zlib.Deflate_Raw (Input, Zlib.Default_Level, Status);
   begin
      Check ("raw", Compressed, Zlib.Raw_Deflate, Status);
   end;
end Compress_With_Level;
