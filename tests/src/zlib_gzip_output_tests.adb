with Ada.Directories;
with Ada.Streams; use Ada.Streams;
with Ada.Streams.Stream_IO; use Ada.Streams.Stream_IO;
with Interfaces;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;
with Zlib.CRC32_Internal;
with Zlib_Fixture_Data;

package body Zlib_GZip_Output_Tests is
   use type Interfaces.Unsigned_32;
   use type Zlib.Byte;
   use type Zlib.Status_Code;

   package F renames Zlib_Fixture_Data;
   package SIO renames Ada.Streams.Stream_IO;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib gzip output");
   end Name;

   procedure Assert_Same
     (Actual   : Zlib.Byte_Array;
      Expected : Zlib.Byte_Array;
      Message  : String)
   is
   begin
      Assert (Actual'Length = Expected'Length, Message & ": length mismatch");
      for I in Expected'Range loop
         Assert
           (Actual (Actual'First + (I - Expected'First)) = Expected (I),
            Message & ": byte mismatch");
      end loop;
   end Assert_Same;

   function Read_Bytes
     (Path : String)
      return Zlib.Byte_Array
   is
      File : SIO.File_Type;
   begin
      SIO.Open (File, SIO.In_File, Path);
      declare
         Size : constant Natural := Natural (SIO.Size (File));
      begin
         if Size = 0 then
            SIO.Close (File);
            return [1 .. 0 => 0];
         end if;

         declare
            Buffer : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Size));
            Last   : Ada.Streams.Stream_Element_Offset;
            Result : Zlib.Byte_Array (1 .. Size);
         begin
            SIO.Read (File, Buffer, Last);
            SIO.Close (File);
            Assert (Last = Buffer'Last, "read helper must read complete file");
            for I in Result'Range loop
               Result (I) := Zlib.Byte (Buffer (Ada.Streams.Stream_Element_Offset (I)));
            end loop;
            return Result;
         end;
      end;
   end Read_Bytes;

   function Trailer_U32_LE
     (Data  : Zlib.Byte_Array;
      Start : Natural)
      return Interfaces.Unsigned_32
   is
   begin
      return Interfaces.Unsigned_32 (Data (Start))
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (Start + 1)), 8)
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (Start + 2)), 16)
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (Start + 3)), 24);
   end Trailer_U32_LE;

   function CRC32_Of
     (Input : Zlib.Byte_Array)
      return Interfaces.Unsigned_32
   is
      State : Zlib.CRC32_Internal.CRC32_State;
   begin
      Zlib.CRC32_Internal.Reset (State);
      for B of Input loop
         Zlib.CRC32_Internal.Update (State, Ada.Streams.Stream_Element (B));
      end loop;
      return Zlib.CRC32_Internal.Value (State);
   end CRC32_Of;

   function ISIZE_Of
     (Input : Zlib.Byte_Array)
      return Interfaces.Unsigned_32
   is
   begin
      return Interfaces.Unsigned_32 (Input'Length);
   end ISIZE_Of;

   procedure Expect_GZip_Roundtrip
     (Input : Zlib.Byte_Array;
      Mode  : Zlib.Compression_Mode;
      Label : String)
   is
      Status     : Zlib.Status_Code;
      Compressed : constant Zlib.Byte_Array := Zlib.GZip (Input, Mode, Status);
   begin
      Assert (Status = Zlib.Ok, Label & " gzip compression must succeed");
      Assert (Compressed'Length >= 18, Label & " gzip stream must contain header and trailer");
      declare
         Inflated : constant Zlib.Byte_Array :=
           Zlib.Inflate_With_Header (Compressed, Zlib.GZip, Status);
      begin
         Assert (Status = Zlib.Ok, Label & " gzip output must inflate");
         Assert_Same (Inflated, Input, Label & " gzip roundtrip");
      end;
   end Expect_GZip_Roundtrip;

   procedure Test_GZip_Roundtrips (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Binary : constant Zlib.Byte_Array :=
        [1 => 0, 2 => 1, 3 => 2, 4 => 16#7F#, 5 => 16#80#, 6 => 16#FF#];
   begin
      Expect_GZip_Roundtrip ([1 .. 0 => 0], Zlib.Auto, "empty Auto");
      Expect_GZip_Roundtrip (F.Plain_Stored, Zlib.Auto, "hello Auto");
      Expect_GZip_Roundtrip (Binary, Zlib.Auto, "binary Auto");
      Expect_GZip_Roundtrip (F.Plain_Git_Blob, Zlib.Auto, "Git-shaped Auto");
      Expect_GZip_Roundtrip (F.Plain_Stored, Zlib.Stored, "Stored");
      Expect_GZip_Roundtrip (F.Plain_Stored, Zlib.Fixed, "Fixed");
      Expect_GZip_Roundtrip (F.Plain_Large_Repeated, Zlib.Dynamic, "Dynamic");
      Expect_GZip_Roundtrip (F.Plain_Large_Repeated, Zlib.Auto, "Auto");
   end Test_GZip_Roundtrips;

   procedure Test_Minimal_Header_And_Trailer (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Status     : Zlib.Status_Code;
      Compressed : constant Zlib.Byte_Array := Zlib.GZip (F.Plain_Stored, Zlib.Stored, Status);
      Header     : constant Zlib.Byte_Array :=
        [1 => 16#1F#, 2 => 16#8B#, 3 => 16#08#, 4 => 16#00#,
         5 => 16#00#, 6 => 16#00#, 7 => 16#00#, 8 => 16#00#,
         9 => 16#00#, 10 => 16#FF#];
      CRC_Start  : constant Natural := Compressed'Last - 7;
      ISZ_Start  : constant Natural := Compressed'Last - 3;
   begin
      Assert (Status = Zlib.Ok, "gzip compression must succeed for header/trailer test");
      for I in Header'Range loop
         Assert (Compressed (I) = Header (I), "gzip header byte mismatch");
      end loop;
      Assert
        (Trailer_U32_LE (Compressed, CRC_Start) = CRC32_Of (F.Plain_Stored),
         "gzip trailer CRC32 must match uncompressed input");
      Assert
        (Trailer_U32_LE (Compressed, ISZ_Start) = ISIZE_Of (F.Plain_Stored),
         "gzip trailer ISIZE must match uncompressed input length");
   end Test_Minimal_Header_And_Trailer;

   procedure Test_Wrong_Wrappers_Rejected (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      GZip_Status    : Zlib.Status_Code;
      Deflate_Status : Zlib.Status_Code;
      Status         : Zlib.Status_Code;
      GZ             : constant Zlib.Byte_Array :=
        Zlib.GZip (F.Plain_Stored, Zlib.Stored, GZip_Status);
      ZL             : constant Zlib.Byte_Array :=
        Zlib.Deflate_Stored (F.Plain_Stored, Deflate_Status);
   begin
      Assert (GZip_Status = Zlib.Ok, "gzip fixture compression must succeed");
      Assert (Deflate_Status = Zlib.Ok, "zlib fixture compression must succeed");
      declare
         Dummy : constant Zlib.Byte_Array := Zlib.Inflate (GZ, Status);
      begin
         pragma Unreferenced (Dummy);
      end;
      Assert (Status /= Zlib.Ok, "gzip output must not be accepted as zlib");
      declare
         Dummy : constant Zlib.Byte_Array :=
           Zlib.Inflate_With_Header (ZL, Zlib.GZip, Status);
      begin
         pragma Unreferenced (Dummy);
      end;
      Assert (Status /= Zlib.Ok, "zlib output must not be accepted as gzip");
      declare
         Dummy : constant Zlib.Byte_Array :=
           Zlib.Inflate_With_Header (GZ, Zlib.Raw_Deflate, Status);
      begin
         pragma Unreferenced (Dummy);
      end;
      Assert (Status /= Zlib.Ok, "gzip output must not be accepted as raw Deflate");
   end Test_Wrong_Wrappers_Rejected;

   procedure Test_GZip_File_Roundtrip (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Input_Path  : constant String := "gzip_output_input.tmp";
      GZip_Path   : constant String := "gzip_output_payload.gz";
      Output_Path : constant String := "gzip_output_roundtrip.tmp";
      Status      : Zlib.Status_Code;
      File        : SIO.File_Type;
      Buffer      : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (F.Plain_Stored'Length));
   begin
      SIO.Create (File, SIO.Out_File, Input_Path);
      for I in F.Plain_Stored'Range loop
         Buffer (Ada.Streams.Stream_Element_Offset (I - F.Plain_Stored'First + 1)) :=
           Ada.Streams.Stream_Element (F.Plain_Stored (I));
      end loop;
      SIO.Write (File, Buffer);
      SIO.Close (File);

      Zlib.GZip_File (Input_Path, GZip_Path, Zlib.Dynamic, Status);
      Assert (Status = Zlib.Ok, "GZip_File must succeed");
      Zlib.Inflate_File (GZip_Path, Output_Path, Status);
      Assert (Status /= Zlib.Ok, "Inflate_File remains zlib-only and must reject gzip");

      declare
         GZ       : constant Zlib.Byte_Array := Read_Bytes (GZip_Path);
         Inflated : constant Zlib.Byte_Array :=
           Zlib.Inflate_With_Header (GZ, Zlib.GZip, Status);
      begin
         Assert (Status = Zlib.Ok, "GZip_File output must inflate");
         Assert_Same (Inflated, F.Plain_Stored, "GZip_File roundtrip");
      end;

      if Ada.Directories.Exists (Input_Path) then
         Ada.Directories.Delete_File (Input_Path);
      end if;
      if Ada.Directories.Exists (GZip_Path) then
         Ada.Directories.Delete_File (GZip_Path);
      end if;
      if Ada.Directories.Exists (Output_Path) then
         Ada.Directories.Delete_File (Output_Path);
      end if;
   end Test_GZip_File_Roundtrip;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine (T, Test_GZip_Roundtrips'Access, "gzip one-shot roundtrips");
      Registration.Register_Routine
        (T, Test_Minimal_Header_And_Trailer'Access,
         "gzip deterministic header and trailer");
      Registration.Register_Routine (T, Test_Wrong_Wrappers_Rejected'Access, "gzip wrong-wrapper rejection");
      Registration.Register_Routine (T, Test_GZip_File_Roundtrip'Access, "GZip_File roundtrip helper");
   end Register_Tests;
end Zlib_GZip_Output_Tests;
