with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with CryptoLib.Checksums;
with Interfaces;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;
with Zlib_Fixture_Data;

package body Zlib_GZip_Metadata_Tests is
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
      return AUnit.Format ("Zlib gzip metadata output");
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

   function U32_LE
     (Data  : Zlib.Byte_Array;
      Start : Natural)
      return Interfaces.Unsigned_32
   is
   begin
      return Interfaces.Unsigned_32 (Data (Start))
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (Start + 1)), 8)
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (Start + 2)), 16)
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (Start + 3)), 24);
   end U32_LE;

   function CRC32_Of
     (Input : Zlib.Byte_Array)
      return Interfaces.Unsigned_32
   is
      State : CryptoLib.Checksums.CRC32_State;
   begin
      CryptoLib.Checksums.CRC32_Reset (State);
      for B of Input loop
         CryptoLib.Checksums.CRC32_Update (State, Ada.Streams.Stream_Element (B));
      end loop;
      return CryptoLib.Checksums.CRC32_Value (State);
   end CRC32_Of;

   procedure Delete_If_Exists
     (Path : String)
   is
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   end Delete_If_Exists;

   procedure Write_Bytes
     (Path : String;
      Data : Zlib.Byte_Array)
   is
      File : SIO.File_Type;
   begin
      SIO.Create (File, SIO.Out_File, Path);
      if Data'Length > 0 then
         declare
            Buffer : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Data'Length));
         begin
            for I in Data'Range loop
               Buffer (Ada.Streams.Stream_Element_Offset (I - Data'First + 1)) :=
                 Ada.Streams.Stream_Element (Data (I));
            end loop;
            SIO.Write (File, Buffer);
         end;
      end if;
      SIO.Close (File);
   end Write_Bytes;

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
            declare
               Empty : constant Zlib.Byte_Array (1 .. 0) := [others => 0];
            begin
               return Empty;
            end;
         end if;

         declare
            Buffer : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Size));
            Last   : Ada.Streams.Stream_Element_Offset;
         begin
            SIO.Read (File, Buffer, Last);
            SIO.Close (File);
            declare
               Result : Zlib.Byte_Array (1 .. Size);
            begin
               for I in Result'Range loop
                  Result (I) := Zlib.Byte (Buffer (Ada.Streams.Stream_Element_Offset (I)));
               end loop;
               return Result;
            end;
         end;
      end;
   end Read_Bytes;

   procedure Test_Default_Output_Unchanged (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Status   : Zlib.Status_Code;
      Metadata : constant Zlib.GZip_Metadata := Zlib.No_GZip_Metadata;
      Old_GZ   : constant Zlib.Byte_Array := Zlib.GZip (F.Plain_Stored, Zlib.Stored, Status);
      New_GZ   : constant Zlib.Byte_Array := Zlib.GZip (F.Plain_Stored, Zlib.Stored, Metadata, Status);
   begin
      Assert (Status = Zlib.Ok, "metadata overload with empty metadata must succeed");
      Assert_Same (New_GZ, Old_GZ, "empty metadata overload must preserve old gzip bytes");
   end Test_Default_Output_Unchanged;

   procedure Test_MTime_And_OS (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Status   : Zlib.Status_Code;
      Metadata : Zlib.GZip_Metadata := Zlib.No_GZip_Metadata;
   begin
      Zlib.Set_MTime (Metadata, 16#1234_5678#);
      Zlib.Set_OS (Metadata, 3);
      declare
         GZ : constant Zlib.Byte_Array := Zlib.GZip (F.Plain_Stored, Zlib.Stored, Metadata, Status);
      begin
         Assert (Status = Zlib.Ok, "gzip metadata MTIME/OS compression must succeed");
         Assert (GZ (4) = 0, "metadata without optional strings keeps FLG zero");
         Assert (GZ (5) = 16#78#, "MTIME byte 0 must be little-endian");
         Assert (GZ (6) = 16#56#, "MTIME byte 1 must be little-endian");
         Assert (GZ (7) = 16#34#, "MTIME byte 2 must be little-endian");
         Assert (GZ (8) = 16#12#, "MTIME byte 3 must be little-endian");
         Assert (GZ (10) = 3, "OS byte must be caller supplied");
      end;
   end Test_MTime_And_OS;

   procedure Test_Name_Comment_And_FHCRC_Roundtrip (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Status   : Zlib.Status_Code;
      Metadata : Zlib.GZip_Metadata := Zlib.No_GZip_Metadata;
   begin
      Zlib.Set_Name (Metadata, "payload.bin");
      Zlib.Set_Comment (Metadata, "phase40");
      Zlib.Set_Header_CRC (Metadata, True);
      declare
         GZ       : constant Zlib.Byte_Array := Zlib.GZip (F.Plain_Stored, Zlib.Fixed, Metadata, Status);
         Inflated : Zlib.Byte_Array (1 .. F.Plain_Stored'Length);
      begin
         Assert (Status = Zlib.Ok, "gzip metadata FNAME/FCOMMENT/FHCRC compression must succeed");
         Assert (GZ (4) = 16#1A#, "gzip FLG must contain FHCRC, FNAME, and FCOMMENT only");
         Assert (GZ (11) = Character'Pos ('p'), "FNAME must start immediately after base header");
         Assert (GZ (22) = 0, "FNAME must be NUL-terminated");
         Assert (GZ (23) = Character'Pos ('p'), "FCOMMENT must follow FNAME terminator");
         Assert (GZ (30) = 0, "FCOMMENT must be NUL-terminated");
         Inflated := Zlib.Inflate_With_Header (GZ, Zlib.GZip, Status);
         Assert (Status = Zlib.Ok, "gzip metadata with FHCRC must inflate");
         Assert_Same (Inflated, F.Plain_Stored, "gzip metadata roundtrip");
      end;
   end Test_Name_Comment_And_FHCRC_Roundtrip;

   procedure Test_Name_Only_And_Comment_Only_Roundtrip (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Status         : Zlib.Status_Code;
      Name_Metadata  : Zlib.GZip_Metadata := Zlib.No_GZip_Metadata;
      Comm_Metadata  : Zlib.GZip_Metadata := Zlib.No_GZip_Metadata;
   begin
      Zlib.Set_Name (Name_Metadata, "name-only.txt");
      Zlib.Set_Comment (Comm_Metadata, "comment-only");

      declare
         Name_GZ       : constant Zlib.Byte_Array :=
           Zlib.GZip (F.Plain_Stored, Zlib.Stored, Name_Metadata, Status);
         Name_Inflated : Zlib.Byte_Array (1 .. F.Plain_Stored'Length);
      begin
         Assert (Status = Zlib.Ok, "gzip FNAME-only compression must succeed");
         Assert (Name_GZ (4) = 16#08#, "gzip FNAME-only FLG must contain only FNAME");
         Assert (Name_GZ (11) = Character'Pos ('n'), "FNAME-only string starts after base header");
         Assert (Name_GZ (24) = 0, "FNAME-only string is NUL-terminated");
         Name_Inflated := Zlib.Inflate_With_Header (Name_GZ, Zlib.GZip, Status);
         Assert (Status = Zlib.Ok, "gzip FNAME-only output must inflate");
         Assert_Same (Name_Inflated, F.Plain_Stored, "gzip FNAME-only roundtrip");
      end;

      declare
         Comm_GZ       : constant Zlib.Byte_Array :=
           Zlib.GZip (F.Plain_Stored, Zlib.Fixed, Comm_Metadata, Status);
         Comm_Inflated : Zlib.Byte_Array (1 .. F.Plain_Stored'Length);
      begin
         Assert (Status = Zlib.Ok, "gzip FCOMMENT-only compression must succeed");
         Assert (Comm_GZ (4) = 16#10#, "gzip FCOMMENT-only FLG must contain only FCOMMENT");
         Assert (Comm_GZ (11) = Character'Pos ('c'), "FCOMMENT-only string starts after base header");
         Assert (Comm_GZ (23) = 0, "FCOMMENT-only string is NUL-terminated");
         Comm_Inflated := Zlib.Inflate_With_Header (Comm_GZ, Zlib.GZip, Status);
         Assert (Status = Zlib.Ok, "gzip FCOMMENT-only output must inflate");
         Assert_Same (Comm_Inflated, F.Plain_Stored, "gzip FCOMMENT-only roundtrip");
      end;
   end Test_Name_Only_And_Comment_Only_Roundtrip;

   procedure Test_Empty_Name_And_Comment_Are_Explicit_Fields
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status   : Zlib.Status_Code;
      Metadata : Zlib.GZip_Metadata := Zlib.No_GZip_Metadata;
   begin
      Zlib.Set_Name (Metadata, "");
      Zlib.Set_Comment (Metadata, "");
      declare
         GZ       : constant Zlib.Byte_Array := Zlib.GZip (F.Plain_Stored, Zlib.Stored, Metadata, Status);
         Inflated : Zlib.Byte_Array (1 .. F.Plain_Stored'Length);
      begin
         Assert (Status = Zlib.Ok, "gzip empty FNAME/FCOMMENT compression must succeed");
         Assert (GZ (4) = 16#18#, "empty strings still set FNAME and FCOMMENT bits");
         Assert (GZ (11) = 0, "empty FNAME emits immediate NUL terminator");
         Assert (GZ (12) = 0, "empty FCOMMENT emits immediate NUL terminator");
         Inflated := Zlib.Inflate_With_Header (GZ, Zlib.GZip, Status);
         Assert (Status = Zlib.Ok, "gzip empty metadata strings must inflate");
         Assert_Same (Inflated, F.Plain_Stored, "gzip empty metadata string roundtrip");
      end;
   end Test_Empty_Name_And_Comment_Are_Explicit_Fields;

   procedure Test_Auto_With_Metadata_Roundtrip (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Status   : Zlib.Status_Code;
      Metadata : Zlib.GZip_Metadata := Zlib.No_GZip_Metadata;
   begin
      Zlib.Set_Name (Metadata, "auto.bin");
      Zlib.Set_MTime (Metadata, 1);
      declare
         GZ       : constant Zlib.Byte_Array := Zlib.GZip (F.Plain_Stored, Zlib.Auto, Metadata, Status);
         Inflated : Zlib.Byte_Array (1 .. F.Plain_Stored'Length);
      begin
         Assert (Status = Zlib.Ok, "gzip Auto with metadata must succeed");
         Assert (GZ (4) = 16#08#, "gzip Auto metadata FLG must preserve FNAME only");
         Assert (GZ (5) = 1, "gzip Auto metadata MTIME byte 0 must be emitted");
         Inflated := Zlib.Inflate_With_Header (GZ, Zlib.GZip, Status);
         Assert (Status = Zlib.Ok, "gzip Auto with metadata must inflate");
         Assert_Same (Inflated, F.Plain_Stored, "gzip Auto with metadata roundtrip");
      end;
   end Test_Auto_With_Metadata_Roundtrip;

   procedure Test_Invalid_NUL_Metadata_Rejected (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Status   : Zlib.Status_Code;
      Metadata : Zlib.GZip_Metadata := Zlib.No_GZip_Metadata;
   begin
      Zlib.Set_Name (Metadata, "bad" & Character'Val (0) & "name");
      declare
         GZ : constant Zlib.Byte_Array := Zlib.GZip (F.Plain_Stored, Zlib.Stored, Metadata, Status);
      begin
         Assert (Status /= Zlib.Ok, "NUL in FNAME must be rejected");
         Assert (GZ'Length = 0, "invalid metadata must produce empty one-shot result");
      end;
   end Test_Invalid_NUL_Metadata_Rejected;

   procedure Test_Invalid_NUL_Comment_Rejected (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Status   : Zlib.Status_Code;
      Metadata : Zlib.GZip_Metadata := Zlib.No_GZip_Metadata;
   begin
      Zlib.Set_Comment (Metadata, "bad" & Character'Val (0) & "comment");
      declare
         GZ : constant Zlib.Byte_Array := Zlib.GZip (F.Plain_Stored, Zlib.Stored, Metadata, Status);
      begin
         Assert (Status /= Zlib.Ok, "NUL in FCOMMENT must be rejected");
         Assert (GZ'Length = 0, "invalid comment metadata must produce empty result");
      end;
   end Test_Invalid_NUL_Comment_Rejected;

   procedure Test_GZip_File_With_Metadata_Roundtrip (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Plain_Path : constant String := "zlib_gzip_metadata_plain.bin";
      GZip_Path  : constant String := "zlib_gzip_metadata_output.gz";
      Status     : Zlib.Status_Code;
      Metadata   : Zlib.GZip_Metadata := Zlib.No_GZip_Metadata;
   begin
      Delete_If_Exists (Plain_Path);
      Delete_If_Exists (GZip_Path);
      Write_Bytes (Plain_Path, F.Plain_Stored);
      Zlib.Set_Name (Metadata, "fixture.bin");
      Zlib.Set_Comment (Metadata, "file overload");
      Zlib.Set_MTime (Metadata, 42);
      Zlib.Set_OS (Metadata, 255);

      Zlib.GZip_File
        (Input_Path  => Plain_Path,
         Output_Path => GZip_Path,
         Mode        => Zlib.Auto,
         Metadata    => Metadata,
         Status      => Status);
      Assert (Status = Zlib.Ok, "GZip_File metadata overload must succeed");

      declare
         GZ       : constant Zlib.Byte_Array := Read_Bytes (GZip_Path);
         Inflated : Zlib.Byte_Array (1 .. F.Plain_Stored'Length);
      begin
         Assert (GZ (4) = 16#18#, "GZip_File metadata output must set FNAME and FCOMMENT");
         Inflated := Zlib.Inflate_With_Header (GZ, Zlib.GZip, Status);
         Assert (Status = Zlib.Ok, "GZip_File metadata output must inflate");
         Assert_Same (Inflated, F.Plain_Stored, "GZip_File metadata roundtrip");
      end;

      Delete_If_Exists (Plain_Path);
      Delete_If_Exists (GZip_Path);
   end Test_GZip_File_With_Metadata_Roundtrip;

   procedure Test_Metadata_Does_Not_Affect_Trailer (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Status   : Zlib.Status_Code;
      Metadata : Zlib.GZip_Metadata := Zlib.No_GZip_Metadata;
   begin
      Zlib.Set_Name (Metadata, "payload.bin");
      Zlib.Set_Comment (Metadata, "payload comment");
      declare
         GZ        : constant Zlib.Byte_Array := Zlib.GZip (F.Plain_Stored, Zlib.Dynamic, Metadata, Status);
         CRC_Start : constant Natural := GZ'Last - 7;
         ISZ_Start : constant Natural := GZ'Last - 3;
      begin
         Assert (Status = Zlib.Ok, "gzip metadata trailer test compression must succeed");
         Assert (U32_LE (GZ, CRC_Start) = CRC32_Of (F.Plain_Stored), "CRC32 trailer covers payload only");
         Assert
           (U32_LE (GZ, ISZ_Start) = Interfaces.Unsigned_32 (F.Plain_Stored'Length),
            "ISIZE trailer covers payload only");
      end;
   end Test_Metadata_Does_Not_Affect_Trailer;

   procedure Test_Non_GZip_Metadata_Rejected (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Filter   : Zlib.Compression_Filter_Type;
      Metadata : Zlib.GZip_Metadata := Zlib.No_GZip_Metadata;
      Raised   : Boolean := False;
   begin
      Zlib.Set_Name (Metadata, "wrong-wrapper");
      begin
         Zlib.Deflate_Init (Filter, Header => Zlib.Zlib_Header, Mode => Zlib.Stored, Metadata => Metadata);
      exception
         when Zlib.Status_Error =>
            Raised := True;
      end;
      Assert (Raised, "non-gzip wrapper with non-default metadata must raise Status_Error");
   end Test_Non_GZip_Metadata_Rejected;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Default_Output_Unchanged'Access, "default gzip output unchanged");
      Register_Routine (T, Test_MTime_And_OS'Access, "MTIME and OS emitted");
      Register_Routine (T, Test_Name_Comment_And_FHCRC_Roundtrip'Access, "FNAME FCOMMENT FHCRC roundtrip");
      Register_Routine
        (T, Test_Name_Only_And_Comment_Only_Roundtrip'Access,
         "FNAME-only and FCOMMENT-only roundtrip");
      Register_Routine
        (T, Test_Empty_Name_And_Comment_Are_Explicit_Fields'Access,
         "empty FNAME/FCOMMENT fields");
      Register_Routine
        (T, Test_Auto_With_Metadata_Roundtrip'Access,
         "Auto with metadata roundtrip");
      Register_Routine (T, Test_Invalid_NUL_Metadata_Rejected'Access, "invalid NUL metadata rejected");
      Register_Routine
        (T, Test_Invalid_NUL_Comment_Rejected'Access,
         "invalid NUL comment metadata rejected");
      Register_Routine
        (T, Test_GZip_File_With_Metadata_Roundtrip'Access,
         "GZip_File metadata roundtrip");
      Register_Routine (T, Test_Metadata_Does_Not_Affect_Trailer'Access, "metadata does not affect trailer");
      Register_Routine (T, Test_Non_GZip_Metadata_Rejected'Access, "metadata rejected for non-gzip wrappers");
   end Register_Tests;
end Zlib_GZip_Metadata_Tests;
