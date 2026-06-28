with Ada.Command_Line;
with Ada.Text_IO;
with Interfaces;
with Zlib;

procedure Smoke_Test is
   use type Zlib.Byte;
   use type Zlib.Byte_Array;
   use type Zlib.Status_Code;

   Plain : constant Zlib.Byte_Array :=
     [1 => 16#68#, 2 => 16#65#, 3 => 16#6C#, 4 => 16#6C#,
      5 => 16#6F#, 6 => 16#20#, 7 => 16#7A#, 8 => 16#6C#,
      9 => 16#69#, 10 => 16#62#, 11 => 16#20#, 12 => 16#73#,
      13 => 16#6D#, 14 => 16#6F#, 15 => 16#6B#, 16 => 16#65#,
      17 => 16#0A#];

   Hello : constant Zlib.Byte_Array :=
     [1 => 16#68#, 2 => 16#65#, 3 => 16#6C#, 4 => 16#6C#, 5 => 16#6F#];

   Hello_Raw : constant Zlib.Byte_Array :=
     [1 => 16#01#, 2 => 16#05#, 3 => 16#00#, 4 => 16#FA#,
      5 => 16#FF#, 6 => 16#68#, 7 => 16#65#, 8 => 16#6C#,
      9 => 16#6C#, 10 => 16#6F#];

   Hello_Gzip : constant Zlib.Byte_Array :=
     [1 => 16#1F#, 2 => 16#8B#, 3 => 16#08#, 4 => 16#00#,
      5 => 16#00#, 6 => 16#00#, 7 => 16#00#, 8 => 16#00#,
      9 => 16#00#, 10 => 16#FF#, 11 => 16#CB#, 12 => 16#48#,
      13 => 16#CD#, 14 => 16#C9#, 15 => 16#C9#, 16 => 16#07#,
      17 => 16#00#, 18 => 16#86#, 19 => 16#A6#, 20 => 16#10#,
      21 => 16#36#, 22 => 16#05#, 23 => 16#00#, 24 => 16#00#,
      25 => 16#00#];

   Failures : Natural := 0;

   procedure Fail (Message : String) is
   begin
      Ada.Text_IO.Put_Line ("FAIL: " & Message);
      Failures := Failures + 1;
   end Fail;

   procedure Check
     (Condition : Boolean;
      Message   : String)
   is
   begin
      if not Condition then
         Fail (Message);
      end if;
   end Check;

   procedure Check_Status
     (Status  : Zlib.Status_Code;
      Message : String)
   is
   begin
      Check (Status = Zlib.Ok, Message & ": " & Zlib.Status_Image (Status));
   end Check_Status;

   procedure Roundtrip_Wrapped
     (Mode : Zlib.Compression_Mode)
   is
      Status    : Zlib.Status_Code;
      Zlib_Data : constant Zlib.Byte_Array := Zlib.Deflate (Plain, Mode, Status);
   begin
      Check_Status (Status, "zlib compression failed");
      declare
         Back : constant Zlib.Byte_Array :=
           Zlib.Inflate_With_Header (Zlib_Data, Zlib.Zlib_Header, Status);
      begin
         Check_Status (Status, "zlib inflate failed");
         Check (Back = Plain, "zlib roundtrip mismatch");
      end;

      declare
         Gzip_Data : constant Zlib.Byte_Array := Zlib.GZip (Plain, Mode, Status);
      begin
         Check_Status (Status, "gzip compression failed");
         declare
            Back : constant Zlib.Byte_Array :=
              Zlib.Inflate_With_Header (Gzip_Data, Zlib.GZip, Status);
         begin
            Check_Status (Status, "gzip inflate failed");
            Check (Back = Plain, "gzip roundtrip mismatch");
         end;
      end;

      declare
         Raw_Data : constant Zlib.Byte_Array := Zlib.Deflate_Raw (Plain, Mode, Status);
      begin
         Check_Status (Status, "raw compression failed");
         declare
            Back : constant Zlib.Byte_Array :=
              Zlib.Inflate_With_Header (Raw_Data, Zlib.Raw_Deflate, Status);
         begin
            Check_Status (Status, "raw inflate failed");
            Check (Back = Plain, "raw roundtrip mismatch");
         end;
      end;
   end Roundtrip_Wrapped;

   procedure Roundtrip_Level
     (Level : Zlib.Compression_Level)
   is
      Status    : Zlib.Status_Code;
      Zlib_Data : constant Zlib.Byte_Array := Zlib.Deflate (Plain, Level, Status);
   begin
      Check_Status (Status, "zlib level compression failed");
      declare
         Back : constant Zlib.Byte_Array :=
           Zlib.Inflate_With_Header (Zlib_Data, Zlib.Zlib_Header, Status);
      begin
         Check_Status (Status, "zlib level inflate failed");
         Check (Back = Plain, "zlib level roundtrip mismatch");
      end;

      declare
         Gz : constant Zlib.Byte_Array := Zlib.GZip (Plain, Level, Status);
      begin
         Check_Status (Status, "gzip level compression failed");
         declare
            Back : constant Zlib.Byte_Array :=
              Zlib.Inflate_With_Header (Gz, Zlib.GZip, Status);
         begin
            Check_Status (Status, "gzip level inflate failed");
            Check (Back = Plain, "gzip level roundtrip mismatch");
         end;
      end;

      declare
         Raw : constant Zlib.Byte_Array := Zlib.Deflate_Raw (Plain, Level, Status);
      begin
         Check_Status (Status, "raw level compression failed");
         declare
            Back : constant Zlib.Byte_Array :=
              Zlib.Inflate_With_Header (Raw, Zlib.Raw_Deflate, Status);
         begin
            Check_Status (Status, "raw level inflate failed");
            Check (Back = Plain, "raw level roundtrip mismatch");
         end;
      end;
   end Roundtrip_Level;

   procedure Check_Wrapper_Strictness is
      Status : Zlib.Status_Code;
      Zdata  : constant Zlib.Byte_Array := Zlib.Deflate (Plain, Zlib.Auto, Status);
   begin
      Check_Status (Status, "zlib strictness compression failed");
      declare
         Raw : constant Zlib.Byte_Array := Zlib.Deflate_Raw (Plain, Zlib.Auto, Status);
      begin
         Check_Status (Status, "raw strictness compression failed");
         declare
            Back : constant Zlib.Byte_Array :=
              Zlib.Inflate_With_Header (Raw, Zlib.Zlib_Header, Status);
         begin
            Check (Status /= Zlib.Ok, "zlib header accepted raw Deflate input");
         end;
         declare
            Back : constant Zlib.Byte_Array :=
              Zlib.Inflate_With_Header (Raw, Zlib.GZip, Status);
         begin
            Check (Status /= Zlib.Ok, "gzip header accepted raw Deflate input");
         end;
      end;

      declare
         Gz : constant Zlib.Byte_Array := Zlib.GZip (Plain, Zlib.Auto, Status);
      begin
         Check_Status (Status, "gzip strictness compression failed");
         declare
            Back : constant Zlib.Byte_Array :=
              Zlib.Inflate_With_Header (Zdata, Zlib.Raw_Deflate, Status);
         begin
            Check (Status /= Zlib.Ok, "raw header accepted zlib-wrapped input");
         end;
         declare
            Back : constant Zlib.Byte_Array :=
              Zlib.Inflate_With_Header (Gz, Zlib.Zlib_Header, Status);
         begin
            Check (Status /= Zlib.Ok, "zlib header accepted gzip-wrapped input");
         end;
      end;
   end Check_Wrapper_Strictness;

   procedure Check_Metadata is
      Status   : Zlib.Status_Code;
      Metadata : Zlib.GZip_Metadata := Zlib.No_GZip_Metadata;
   begin
      Zlib.Set_Name (Metadata, "plain.txt");
      Zlib.Set_Comment (Metadata, "smoke");
      Zlib.Set_MTime (Metadata, 0);
      Zlib.Set_OS (Metadata, 255);
      Zlib.Set_Header_CRC (Metadata, True);
      declare
         Gz : constant Zlib.Byte_Array := Zlib.GZip (Plain, Zlib.Auto, Metadata, Status);
      begin
         Check_Status (Status, "gzip metadata compression failed");
         declare
            Back : constant Zlib.Byte_Array :=
              Zlib.Inflate_With_Header (Gz, Zlib.GZip, Status);
         begin
            Check_Status (Status, "gzip metadata inflate failed");
            Check (Back = Plain, "gzip metadata roundtrip mismatch");
         end;
      end;
   end Check_Metadata;

   Status : Zlib.Status_Code;
begin
   for Mode in Zlib.Compression_Mode loop
      Roundtrip_Wrapped (Mode);
   end loop;

   Roundtrip_Level (0);
   Roundtrip_Level (1);
   Roundtrip_Level (6);
   Check_Metadata;

   declare
      Back : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Hello_Raw, Zlib.Raw_Deflate, Status);
   begin
      Check_Status (Status, "raw fixture inflate failed");
      Check (Back = Hello, "raw fixture mismatch");
   end;

   declare
      Back : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Hello_Gzip, Zlib.GZip, Status);
   begin
      Check_Status (Status, "gzip fixture inflate failed");
      Check (Back = Hello, "gzip fixture mismatch");
   end;

   Check_Wrapper_Strictness;

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("zlib smoke test passed");
   else
      Ada.Text_IO.Put_Line ("zlib smoke test failed:" & Natural'Image (Failures));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Smoke_Test;
