with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;

package body Zlib_Streaming_File_Tests is
   use type Zlib.Byte;
   use type Zlib.Status_Code;

   package SIO renames Ada.Streams.Stream_IO;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib streaming file API");
   end Name;

   procedure Delete_If_Exists
     (Path : String)
   is
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   end Delete_If_Exists;

   procedure Delete_Directory_If_Exists
     (Path : String)
   is
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_Directory (Path);
      end if;
   exception
      when others =>
         null;
   end Delete_Directory_If_Exists;

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
               Buffer
                 (Ada.Streams.Stream_Element_Offset (I - Data'First + 1)) :=
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
                  Result (I) :=
                    Zlib.Byte (Buffer (Ada.Streams.Stream_Element_Offset (I)));
               end loop;

               return Result;
            end;
         end;
      end;
   end Read_Bytes;

   function Pattern_Data
     (Length : Positive)
      return Zlib.Byte_Array
   is
      Result : Zlib.Byte_Array (1 .. Length);
   begin
      for I in Result'Range loop
         Result (I) := Zlib.Byte ((I * 37 + I / 3) mod 256);
      end loop;

      return Result;
   end Pattern_Data;

   function Binary_Data
      return Zlib.Byte_Array
   is
   begin
      return Zlib.Byte_Array'
        (1  => 0,
         2  => 1,
         3  => 2,
         4  => 127,
         5  => 128,
         6  => 200,
         7  => 255,
         8  => 0,
         9  => 42,
         10 => 254,
         11 => 16#80#,
         12 => 16#FF#);
   end Binary_Data;

   procedure Assert_Equal
     (Actual   : Zlib.Byte_Array;
      Expected : Zlib.Byte_Array;
      Message  : String)
   is
   begin
      Assert
        (Actual'Length = Expected'Length,
         Message & ": byte length mismatch");

      for I in Expected'Range loop
         Assert
           (Actual (Actual'First + I - Expected'First) = Expected (I),
            Message & ": byte mismatch");
      end loop;
   end Assert_Equal;

   procedure Test_Zlib_Streaming_File_Roundtrip (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Plain_Path      : constant String := "zlib_streaming_file_plain.bin";
      Compressed_Path : constant String := "zlib_streaming_file_plain.z";
      Inflated_Path   : constant String := "zlib_streaming_file_plain.out";
      Input           : constant Zlib.Byte_Array := Pattern_Data (70_000);
      Status          : Zlib.Status_Code;
   begin
      Delete_If_Exists (Plain_Path);
      Delete_If_Exists (Compressed_Path);
      Delete_If_Exists (Inflated_Path);
      Write_Bytes (Plain_Path, Input);

      Zlib.Deflate_File_Streaming
        (Input_Path  => Plain_Path,
         Output_Path => Compressed_Path,
         Header      => Zlib.Zlib_Header,
         Mode        => Zlib.Auto,
         Status      => Status);
      Assert (Status = Zlib.Ok, "Deflate_File_Streaming zlib must succeed");

      Zlib.Inflate_File_Streaming
        (Input_Path  => Compressed_Path,
         Output_Path => Inflated_Path,
         Header      => Zlib.Zlib_Header,
         Status      => Status);
      Assert (Status = Zlib.Ok, "Inflate_File_Streaming zlib must succeed");

      Assert_Equal (Read_Bytes (Inflated_Path), Input, "zlib streaming file roundtrip");
      Delete_If_Exists (Plain_Path);
      Delete_If_Exists (Compressed_Path);
      Delete_If_Exists (Inflated_Path);
   end Test_Zlib_Streaming_File_Roundtrip;

   procedure Test_GZip_Streaming_File_Roundtrip (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Plain_Path      : constant String := "zlib_streaming_file_gzip_plain.bin";
      Compressed_Path : constant String := "zlib_streaming_file_plain.gz";
      Inflated_Path   : constant String := "zlib_streaming_file_gzip_plain.out";
      Input           : constant Zlib.Byte_Array := Binary_Data;
      Status          : Zlib.Status_Code;
   begin
      Delete_If_Exists (Plain_Path);
      Delete_If_Exists (Compressed_Path);
      Delete_If_Exists (Inflated_Path);
      Write_Bytes (Plain_Path, Input);

      Zlib.GZip_File_Streaming
        (Input_Path  => Plain_Path,
         Output_Path => Compressed_Path,
         Mode        => Zlib.Fixed,
         Status      => Status);
      Assert (Status = Zlib.Ok, "GZip_File_Streaming must succeed");

      Zlib.Inflate_File_Streaming
        (Input_Path  => Compressed_Path,
         Output_Path => Inflated_Path,
         Header      => Zlib.GZip,
         Status      => Status);
      Assert (Status = Zlib.Ok, "Inflate_File_Streaming gzip must succeed");

      Assert_Equal (Read_Bytes (Inflated_Path), Input, "gzip streaming file roundtrip");
      Delete_If_Exists (Plain_Path);
      Delete_If_Exists (Compressed_Path);
      Delete_If_Exists (Inflated_Path);
   end Test_GZip_Streaming_File_Roundtrip;

   procedure Test_Raw_Streaming_File_Roundtrip (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Plain_Path      : constant String := "zlib_streaming_file_raw_plain.bin";
      Compressed_Path : constant String := "zlib_streaming_file_plain.raw";
      Inflated_Path   : constant String := "zlib_streaming_file_raw_plain.out";
      Input           : constant Zlib.Byte_Array := Pattern_Data (4_096);
      Status          : Zlib.Status_Code;
   begin
      Delete_If_Exists (Plain_Path);
      Delete_If_Exists (Compressed_Path);
      Delete_If_Exists (Inflated_Path);
      Write_Bytes (Plain_Path, Input);

      Zlib.Deflate_Raw_File_Streaming
        (Input_Path  => Plain_Path,
         Output_Path => Compressed_Path,
         Mode        => Zlib.Dynamic,
         Status      => Status);
      Assert (Status = Zlib.Ok, "Deflate_Raw_File_Streaming must succeed");

      Zlib.Inflate_File_Streaming
        (Input_Path  => Compressed_Path,
         Output_Path => Inflated_Path,
         Header      => Zlib.Raw_Deflate,
         Status      => Status);
      Assert (Status = Zlib.Ok, "Inflate_File_Streaming raw must succeed");

      Assert_Equal (Read_Bytes (Inflated_Path), Input, "raw streaming file roundtrip");
      Delete_If_Exists (Plain_Path);
      Delete_If_Exists (Compressed_Path);
      Delete_If_Exists (Inflated_Path);
   end Test_Raw_Streaming_File_Roundtrip;

   function Dictionary_Data
      return Zlib.Byte_Array
   is
   begin
      return [104, 101, 108, 108, 111, 32, 119, 111, 114, 108, 100,
              32, 112, 114, 101, 102, 105, 120, 45, 115, 117, 102,
              102, 105, 120];
   end Dictionary_Data;

   function Dictionary_Payload
      return Zlib.Byte_Array
   is
   begin
      return [104, 101, 108, 108, 111, 45, 104, 101, 108, 108, 111,
              45, 119, 111, 114, 108, 100];
   end Dictionary_Payload;

   procedure Test_Dictionary_Streaming_File_Roundtrip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Plain_Path      : constant String := "zlib_streaming_dict_plain.bin";
      Compressed_Path : constant String := "zlib_streaming_dict.z";
      Inflated_Path   : constant String := "zlib_streaming_dict.out";
      Input           : constant Zlib.Byte_Array := Dictionary_Payload;
      Dict            : constant Zlib.Byte_Array := Dictionary_Data;
      Status          : Zlib.Status_Code;
   begin
      Delete_If_Exists (Plain_Path);
      Delete_If_Exists (Compressed_Path);
      Delete_If_Exists (Inflated_Path);
      Write_Bytes (Plain_Path, Input);

      Zlib.Deflate_File_With_Dictionary_Streaming
        (Input_Path  => Plain_Path,
         Output_Path => Compressed_Path,
         Dictionary  => Dict,
         Mode        => Zlib.Auto,
         Status      => Status);
      Assert
        (Status = Zlib.Ok,
         "Deflate_File_With_Dictionary_Streaming must succeed");

      Zlib.Inflate_File_With_Dictionary_Streaming
        (Input_Path  => Compressed_Path,
         Output_Path => Inflated_Path,
         Dictionary  => Dict,
         Status      => Status);
      Assert
        (Status = Zlib.Ok,
         "Inflate_File_With_Dictionary_Streaming must succeed");

      Assert_Equal
        (Read_Bytes (Inflated_Path), Input,
         "dictionary streaming file roundtrip");
      Delete_If_Exists (Plain_Path);
      Delete_If_Exists (Compressed_Path);
      Delete_If_Exists (Inflated_Path);
   end Test_Dictionary_Streaming_File_Roundtrip;

   procedure Test_Dictionary_Streaming_File_Wrong_Dictionary
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Plain_Path      : constant String := "zlib_streaming_dict_wrong_plain.bin";
      Compressed_Path : constant String := "zlib_streaming_dict_wrong.z";
      Inflated_Path   : constant String := "zlib_streaming_dict_wrong.out";
      Input           : constant Zlib.Byte_Array := Dictionary_Payload;
      Dict            : constant Zlib.Byte_Array := Dictionary_Data;
      Wrong           : constant Zlib.Byte_Array := [1 => 1, 2 => 2, 3 => 3];
      Status          : Zlib.Status_Code;
   begin
      Delete_If_Exists (Plain_Path);
      Delete_If_Exists (Compressed_Path);
      Delete_If_Exists (Inflated_Path);
      Write_Bytes (Plain_Path, Input);

      Zlib.Deflate_File_With_Dictionary_Streaming
        (Input_Path  => Plain_Path,
         Output_Path => Compressed_Path,
         Dictionary  => Dict,
         Mode        => Zlib.Fixed,
         Status      => Status);
      Assert
        (Status = Zlib.Ok,
         "dictionary streaming compression fixture must succeed");

      Zlib.Inflate_File_With_Dictionary_Streaming
        (Input_Path  => Compressed_Path,
         Output_Path => Inflated_Path,
         Dictionary  => Wrong,
         Status      => Status);
      Assert
        (Status = Zlib.Invalid_Checksum,
         "wrong streaming file dictionary must fail deterministically");

      Delete_If_Exists (Plain_Path);
      Delete_If_Exists (Compressed_Path);
      Delete_If_Exists (Inflated_Path);
   end Test_Dictionary_Streaming_File_Wrong_Dictionary;

   procedure Test_Inflate_Streaming_Zlib_Fixture (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Compressed_Path : constant String := "zlib_streaming_file_fixture.z";
      Inflated_Path   : constant String := "zlib_streaming_file_fixture_zlib.out";
      Input           : constant Zlib.Byte_Array := Pattern_Data (333);
      Status          : Zlib.Status_Code;
      Compressed      : constant Zlib.Byte_Array := Zlib.Deflate (Input, Zlib.Dynamic, Status);
   begin
      Assert (Status = Zlib.Ok, "one-shot zlib fixture creation must succeed");
      Delete_If_Exists (Compressed_Path);
      Delete_If_Exists (Inflated_Path);
      Write_Bytes (Compressed_Path, Compressed);

      Zlib.Inflate_File_Streaming
        (Input_Path  => Compressed_Path,
         Output_Path => Inflated_Path,
         Header      => Zlib.Zlib_Header,
         Status      => Status);
      Assert (Status = Zlib.Ok, "Inflate_File_Streaming zlib fixture must succeed");
      Assert_Equal (Read_Bytes (Inflated_Path), Input, "zlib streaming fixture inflate");
      Delete_If_Exists (Compressed_Path);
      Delete_If_Exists (Inflated_Path);
   end Test_Inflate_Streaming_Zlib_Fixture;

   procedure Test_Inflate_Streaming_Raw_Fixture (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Compressed_Path : constant String := "zlib_streaming_file_fixture.raw";
      Inflated_Path   : constant String := "zlib_streaming_file_fixture_raw.out";
      Input           : constant Zlib.Byte_Array := Pattern_Data (333);
      Status          : Zlib.Status_Code;
      Compressed      : constant Zlib.Byte_Array := Zlib.Deflate_Raw (Input, Zlib.Fixed, Status);
   begin
      Assert (Status = Zlib.Ok, "one-shot raw fixture creation must succeed");
      Delete_If_Exists (Compressed_Path);
      Delete_If_Exists (Inflated_Path);
      Write_Bytes (Compressed_Path, Compressed);

      Zlib.Inflate_File_Streaming
        (Input_Path  => Compressed_Path,
         Output_Path => Inflated_Path,
         Header      => Zlib.Raw_Deflate,
         Status      => Status);
      Assert (Status = Zlib.Ok, "Inflate_File_Streaming raw fixture must succeed");
      Assert_Equal (Read_Bytes (Inflated_Path), Input, "raw streaming fixture inflate");
      Delete_If_Exists (Compressed_Path);
      Delete_If_Exists (Inflated_Path);
   end Test_Inflate_Streaming_Raw_Fixture;

   procedure Test_Inflate_Streaming_GZip_Fixture (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Compressed_Path : constant String := "zlib_streaming_file_fixture.gz";
      Inflated_Path   : constant String := "zlib_streaming_file_fixture.out";
      Input           : constant Zlib.Byte_Array := Pattern_Data (257);
      Status          : Zlib.Status_Code;
      Compressed      : constant Zlib.Byte_Array := Zlib.GZip (Input, Zlib.Stored, Status);
   begin
      Assert (Status = Zlib.Ok, "one-shot gzip fixture creation must succeed");
      Delete_If_Exists (Compressed_Path);
      Delete_If_Exists (Inflated_Path);
      Write_Bytes (Compressed_Path, Compressed);

      Zlib.Inflate_File_Streaming
        (Input_Path  => Compressed_Path,
         Output_Path => Inflated_Path,
         Header      => Zlib.GZip,
         Status      => Status);
      Assert (Status = Zlib.Ok, "Inflate_File_Streaming gzip fixture must succeed");
      Assert_Equal (Read_Bytes (Inflated_Path), Input, "gzip streaming fixture inflate");
      Delete_If_Exists (Compressed_Path);
      Delete_If_Exists (Inflated_Path);
   end Test_Inflate_Streaming_GZip_Fixture;

   procedure Test_Streaming_File_Missing_Input (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code;
   begin
      Delete_If_Exists ("zlib_streaming_missing_input.z");
      Delete_If_Exists ("zlib_streaming_missing_output.bin");

      Zlib.Inflate_File_Streaming
        (Input_Path  => "zlib_streaming_missing_input.z",
         Output_Path => "zlib_streaming_missing_output.bin",
         Header      => Zlib.Zlib_Header,
         Status      => Status);
      Assert (Status = Zlib.Input_File_Error, "missing streaming inflate input must map to Input_File_Error");

      Zlib.Deflate_File_Streaming
        (Input_Path  => "zlib_streaming_missing_input.z",
         Output_Path => "zlib_streaming_missing_output.bin",
         Header      => Zlib.Zlib_Header,
         Status      => Status);
      Assert (Status = Zlib.Input_File_Error, "missing streaming compression input must map to Input_File_Error");
   end Test_Streaming_File_Missing_Input;

   procedure Test_Streaming_File_Output_Create_Failure (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Plain_Path      : constant String := "zlib_streaming_output_failure_plain.bin";
      Compressed_Path : constant String := "zlib_streaming_output_failure.z";
      Output_Dir      : constant String := "zlib_streaming_output_failure_dir";
      Input           : constant Zlib.Byte_Array := Binary_Data;
      Status          : Zlib.Status_Code;
      Compressed      : constant Zlib.Byte_Array := Zlib.Deflate (Input, Zlib.Stored, Status);
   begin
      Assert (Status = Zlib.Ok, "output failure fixture compression must succeed");
      Delete_If_Exists (Plain_Path);
      Delete_If_Exists (Compressed_Path);
      Delete_Directory_If_Exists (Output_Dir);

      Write_Bytes (Plain_Path, Input);
      Write_Bytes (Compressed_Path, Compressed);
      Ada.Directories.Create_Directory (Output_Dir);

      Zlib.Deflate_File_Streaming
        (Input_Path  => Plain_Path,
         Output_Path => Output_Dir,
         Header      => Zlib.Zlib_Header,
         Status      => Status);
      Assert (Status = Zlib.Output_File_Error, "streaming compression output directory must map to Output_File_Error");

      Zlib.Inflate_File_Streaming
        (Input_Path  => Compressed_Path,
         Output_Path => Output_Dir,
         Header      => Zlib.Zlib_Header,
         Status      => Status);
      Assert (Status = Zlib.Output_File_Error, "streaming inflate output directory must map to Output_File_Error");

      Delete_Directory_If_Exists (Output_Dir);
      Delete_If_Exists (Plain_Path);
      Delete_If_Exists (Compressed_Path);
   end Test_Streaming_File_Output_Create_Failure;

   procedure Test_Streaming_File_Invalid_Input (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Bad_Path : constant String := "zlib_streaming_invalid.z";
      Out_Path : constant String := "zlib_streaming_invalid.out";
      Bad      : constant Zlib.Byte_Array := [1 => 1, 2 => 2, 3 => 3, 4 => 4];
      Status   : Zlib.Status_Code;
   begin
      Delete_If_Exists (Bad_Path);
      Delete_If_Exists (Out_Path);
      Write_Bytes (Bad_Path, Bad);

      Zlib.Inflate_File_Streaming
        (Input_Path  => Bad_Path,
         Output_Path => Out_Path,
         Header      => Zlib.Zlib_Header,
         Status      => Status);
      Assert (Status /= Zlib.Ok, "invalid streaming compressed input must not return Ok");
      Delete_If_Exists (Bad_Path);
      Delete_If_Exists (Out_Path);
   end Test_Streaming_File_Invalid_Input;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T,
         Test_Zlib_Streaming_File_Roundtrip'Access,
         "Deflate_File_Streaming zlib roundtrip larger than chunk size");

      Registration.Register_Routine
        (T,
         Test_GZip_Streaming_File_Roundtrip'Access,
         "GZip_File_Streaming binary roundtrip");

      Registration.Register_Routine
        (T,
         Test_Raw_Streaming_File_Roundtrip'Access,
         "Deflate_Raw_File_Streaming raw roundtrip");

      Registration.Register_Routine
        (T,
         Test_Dictionary_Streaming_File_Roundtrip'Access,
         "dictionary streaming file roundtrip");

      Registration.Register_Routine
        (T,
         Test_Dictionary_Streaming_File_Wrong_Dictionary'Access,
         "dictionary streaming file wrong dictionary fails");

      Registration.Register_Routine
        (T,
         Test_Inflate_Streaming_Zlib_Fixture'Access,
         "Inflate_File_Streaming zlib fixture");

      Registration.Register_Routine
        (T,
         Test_Inflate_Streaming_Raw_Fixture'Access,
         "Inflate_File_Streaming raw fixture");

      Registration.Register_Routine
        (T,
         Test_Inflate_Streaming_GZip_Fixture'Access,
         "Inflate_File_Streaming gzip fixture");

      Registration.Register_Routine
        (T,
         Test_Streaming_File_Missing_Input'Access,
         "streaming file APIs missing input returns Input_File_Error");

      Registration.Register_Routine
        (T,
         Test_Streaming_File_Output_Create_Failure'Access,
         "streaming file APIs output create failure returns Output_File_Error");

      Registration.Register_Routine
        (T,
         Test_Streaming_File_Invalid_Input'Access,
         "Inflate_File_Streaming invalid input returns non-Ok status");
   end Register_Tests;

end Zlib_Streaming_File_Tests;
