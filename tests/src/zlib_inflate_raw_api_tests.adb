with Ada.Directories;
with Ada.Streams; use Ada.Streams;
with Ada.Streams.Stream_IO; use Ada.Streams.Stream_IO;
with AUnit.Assertions; use AUnit.Assertions;
with Project_Tools.Files;
with Zlib;

package body Zlib_Inflate_Raw_Api_Tests is
   use type Zlib.Byte;
   use type Zlib.Status_Code;

   package SIO renames Ada.Streams.Stream_IO;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib raw Deflate one-shot inflate API");
   end Name;

   function Empty return Zlib.Byte_Array is
      Result : constant Zlib.Byte_Array (1 .. 0) := [others => 0];
   begin
      return Result;
   end Empty;

   function Sample_Text return Zlib.Byte_Array is
   begin
      return
        [1  => Zlib.Byte (Character'Pos ('r')),
         2  => Zlib.Byte (Character'Pos ('a')),
         3  => Zlib.Byte (Character'Pos ('w')),
         4  => Zlib.Byte (Character'Pos (' ')),
         5  => Zlib.Byte (Character'Pos ('d')),
         6  => Zlib.Byte (Character'Pos ('e')),
         7  => Zlib.Byte (Character'Pos ('f')),
         8  => Zlib.Byte (Character'Pos ('l')),
         9  => Zlib.Byte (Character'Pos ('a')),
         10 => Zlib.Byte (Character'Pos ('t')),
         11 => Zlib.Byte (Character'Pos ('e')),
         12 => Zlib.Byte (Character'Pos (' ')),
         13 => Zlib.Byte (Character'Pos ('a')),
         14 => Zlib.Byte (Character'Pos ('p')),
         15 => Zlib.Byte (Character'Pos ('i'))];
   end Sample_Text;

   function Binary_Sample return Zlib.Byte_Array is
      Result : Zlib.Byte_Array (1 .. 768);
   begin
      for I in Result'Range loop
         Result (I) := Zlib.Byte ((I * 73 + 19) mod 256);
      end loop;
      return Result;
   end Binary_Sample;

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
            Message & ": byte mismatch at" & Integer'Image (I));
      end loop;
   end Assert_Same;

   procedure Delete_If_Exists (Path : String) is
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   end Delete_If_Exists;

   procedure Write_File
     (Path : String;
      Data : Zlib.Byte_Array)
   is
      Content : String (1 .. Data'Length);
   begin
      for I in Data'Range loop
         Content (Content'First + (I - Data'First)) :=
           Character'Val (Data (I));
      end loop;
      Project_Tools.Files.Write_Raw_File (Path, Content);
   end Write_File;

   function Read_File (Path : String) return Zlib.Byte_Array is
      File : SIO.File_Type;
   begin
      SIO.Open (File, SIO.In_File, Path);
      declare
         Size : constant Natural := Natural (SIO.Size (File));
      begin
         if Size = 0 then
            SIO.Close (File);
            return Empty;
         end if;

         declare
            Buffer : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Size));
            Last   : Ada.Streams.Stream_Element_Offset;
            Result : Zlib.Byte_Array (1 .. Size);
         begin
            SIO.Read (File, Buffer, Last);
            SIO.Close (File);
            for I in Result'Range loop
               Result (I) := Zlib.Byte (Buffer (Ada.Streams.Stream_Element_Offset (I)));
            end loop;
            return Result;
         end;
      end;
   exception
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         raise;
   end Read_File;

   procedure Assert_Inflate_Raw_Roundtrip
     (Input : Zlib.Byte_Array;
      Mode  : Zlib.Compression_Mode;
      Label : String)
   is
      Compress_Status : Zlib.Status_Code := Zlib.Ok;
      Inflate_Status  : Zlib.Status_Code := Zlib.Ok;
      Compressed      : constant Zlib.Byte_Array :=
        Zlib.Deflate_Raw (Input, Mode => Mode, Status => Compress_Status);
      Output          : constant Zlib.Byte_Array :=
        Zlib.Inflate_Raw (Compressed, Inflate_Status);
   begin
      Assert (Compress_Status = Zlib.Ok, Label & ": Deflate_Raw must succeed");
      Assert (Inflate_Status = Zlib.Ok, Label & ": Inflate_Raw must succeed");
      Assert_Same (Output, Input, Label);
   end Assert_Inflate_Raw_Roundtrip;

   procedure Test_Inflate_Raw_Stored_Payload
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_Inflate_Raw_Roundtrip (Sample_Text, Zlib.Stored, "stored raw payload");
   end Test_Inflate_Raw_Stored_Payload;

   procedure Test_Inflate_Raw_Fixed_Payload
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_Inflate_Raw_Roundtrip (Sample_Text, Zlib.Fixed, "fixed raw payload");
   end Test_Inflate_Raw_Fixed_Payload;

   procedure Test_Inflate_Raw_Dynamic_Payload
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_Inflate_Raw_Roundtrip (Sample_Text, Zlib.Dynamic, "dynamic raw payload");
   end Test_Inflate_Raw_Dynamic_Payload;

   procedure Test_Inflate_Raw_Binary_Payload
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_Inflate_Raw_Roundtrip (Binary_Sample, Zlib.Auto, "binary raw payload");
   end Test_Inflate_Raw_Binary_Payload;

   procedure Test_Inflate_Raw_Rejects_Zlib_Wrapped
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Compress_Status : Zlib.Status_Code := Zlib.Ok;
      Inflate_Status  : Zlib.Status_Code := Zlib.Ok;
      Input           : constant Zlib.Byte_Array := Sample_Text;
      Wrapped         : constant Zlib.Byte_Array :=
        Zlib.Deflate (Input, Mode => Zlib.Dynamic, Status => Compress_Status);
      Output          : constant Zlib.Byte_Array := Zlib.Inflate_Raw (Wrapped, Inflate_Status);
      pragma Unreferenced (Output);
   begin
      Assert (Compress_Status = Zlib.Ok, "zlib-wrapped fixture must compress");
      Assert (Inflate_Status /= Zlib.Ok, "Inflate_Raw must reject zlib-wrapped input");
   end Test_Inflate_Raw_Rejects_Zlib_Wrapped;

   procedure Test_Inflate_Raw_Rejects_Gzip_Wrapped
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Compress_Status : Zlib.Status_Code := Zlib.Ok;
      Inflate_Status  : Zlib.Status_Code := Zlib.Ok;
      Input           : constant Zlib.Byte_Array := Sample_Text;
      Wrapped         : constant Zlib.Byte_Array :=
        Zlib.GZip (Input, Mode => Zlib.Dynamic, Status => Compress_Status);
      Output          : constant Zlib.Byte_Array := Zlib.Inflate_Raw (Wrapped, Inflate_Status);
      pragma Unreferenced (Output);
   begin
      Assert (Compress_Status = Zlib.Ok, "gzip-wrapped fixture must compress");
      Assert (Inflate_Status /= Zlib.Ok, "Inflate_Raw must reject gzip-wrapped input");
   end Test_Inflate_Raw_Rejects_Gzip_Wrapped;

   procedure Test_Inflate_Raw_Equals_Explicit_Header
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Compress_Status : Zlib.Status_Code := Zlib.Ok;
      Raw_Status      : Zlib.Status_Code := Zlib.Ok;
      Explicit_Status : Zlib.Status_Code := Zlib.Ok;
      Input           : constant Zlib.Byte_Array := Binary_Sample;
      Compressed      : constant Zlib.Byte_Array :=
        Zlib.Deflate_Raw (Input, Mode => Zlib.Dynamic, Status => Compress_Status);
      Raw_Output      : constant Zlib.Byte_Array := Zlib.Inflate_Raw (Compressed, Raw_Status);
      Explicit_Output : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Compressed, Zlib.Raw_Deflate, Explicit_Status);
   begin
      Assert (Compress_Status = Zlib.Ok, "raw fixture must compress");
      Assert (Raw_Status = Zlib.Ok, "Inflate_Raw must succeed");
      Assert (Explicit_Status = Zlib.Ok, "explicit raw inflate must succeed");
      Assert_Same (Raw_Output, Explicit_Output, "Inflate_Raw equals explicit raw header");
   end Test_Inflate_Raw_Equals_Explicit_Header;

   procedure Test_Inflate_Raw_File_Roundtrips_Raw_File
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input_Path      : constant String := "inflate_raw_api_input.bin";
      Compressed_Path : constant String := "inflate_raw_api_input.deflate";
      Output_Path     : constant String := "inflate_raw_api_output.bin";
      Status          : Zlib.Status_Code := Zlib.Ok;
      Input           : constant Zlib.Byte_Array := Binary_Sample;
   begin
      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Compressed_Path);
      Delete_If_Exists (Output_Path);
      Write_File (Input_Path, Input);

      Zlib.Deflate_Raw_File (Input_Path, Compressed_Path, Mode => Zlib.Dynamic, Status => Status);
      Assert (Status = Zlib.Ok, "Deflate_Raw_File fixture must succeed");
      Zlib.Inflate_Raw_File (Compressed_Path, Output_Path, Status);
      Assert (Status = Zlib.Ok, "Inflate_Raw_File must succeed");
      Assert_Same (Read_File (Output_Path), Input, "Inflate_Raw_File roundtrip");

      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Compressed_Path);
      Delete_If_Exists (Output_Path);
   end Test_Inflate_Raw_File_Roundtrips_Raw_File;

   procedure Test_Inflate_Raw_File_Streaming_Roundtrips_Raw_File
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input_Path      : constant String := "inflate_raw_api_stream_input.bin";
      Compressed_Path : constant String := "inflate_raw_api_stream_input.deflate";
      Output_Path     : constant String := "inflate_raw_api_stream_output.bin";
      Status          : Zlib.Status_Code := Zlib.Ok;
      Input           : constant Zlib.Byte_Array := Binary_Sample;
   begin
      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Compressed_Path);
      Delete_If_Exists (Output_Path);
      Write_File (Input_Path, Input);

      Zlib.Deflate_Raw_File (Input_Path, Compressed_Path, Mode => Zlib.Auto, Status => Status);
      Assert (Status = Zlib.Ok, "Deflate_Raw_File fixture must succeed");
      Zlib.Inflate_Raw_File_Streaming (Compressed_Path, Output_Path, Status);
      Assert (Status = Zlib.Ok, "Inflate_Raw_File_Streaming must succeed");
      Assert_Same (Read_File (Output_Path), Input, "Inflate_Raw_File_Streaming roundtrip");

      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Compressed_Path);
      Delete_If_Exists (Output_Path);
   end Test_Inflate_Raw_File_Streaming_Roundtrips_Raw_File;

   procedure Test_Missing_Input_File_Returns_Input_File_Error
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code := Zlib.Ok;
   begin
      Delete_If_Exists ("inflate_raw_api_missing_output.bin");
      Zlib.Inflate_Raw_File
        ("inflate_raw_api_missing_input.deflate",
         "inflate_raw_api_missing_output.bin",
         Status);
      Assert (Status = Zlib.Input_File_Error, "Inflate_Raw_File missing input status");

      Zlib.Inflate_Raw_File_Streaming
        ("inflate_raw_api_missing_input.deflate",
         "inflate_raw_api_missing_output.bin",
         Status);
      Assert (Status = Zlib.Input_File_Error, "Inflate_Raw_File_Streaming missing input status");
   end Test_Missing_Input_File_Returns_Input_File_Error;

   procedure Test_Wrapper_Strictness_Matrix
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input        : constant Zlib.Byte_Array := Sample_Text;
      Status       : Zlib.Status_Code := Zlib.Ok;
      Zlib_Status  : Zlib.Status_Code := Zlib.Ok;
      GZip_Status  : Zlib.Status_Code := Zlib.Ok;
      Raw_Status   : Zlib.Status_Code := Zlib.Ok;
      Zlib_Stream  : constant Zlib.Byte_Array :=
        Zlib.Deflate (Input, Mode => Zlib.Dynamic, Status => Zlib_Status);
      GZip_Stream  : constant Zlib.Byte_Array :=
        Zlib.GZip (Input, Mode => Zlib.Dynamic, Status => GZip_Status);
      Raw_Stream   : constant Zlib.Byte_Array :=
        Zlib.Deflate_Raw (Input, Mode => Zlib.Dynamic, Status => Raw_Status);
   begin
      Assert (Zlib_Status = Zlib.Ok, "zlib fixture must compress");
      Assert (GZip_Status = Zlib.Ok, "gzip fixture must compress");
      Assert (Raw_Status = Zlib.Ok, "raw fixture must compress");

      declare
         Output : constant Zlib.Byte_Array := Zlib.Inflate_Raw (Raw_Stream, Status);
      begin
         Assert (Status = Zlib.Ok, "Inflate_Raw(raw payload) must succeed");
         Assert_Same (Output, Input, "Inflate_Raw(raw payload)");
      end;

      declare
         Output : constant Zlib.Byte_Array := Zlib.Inflate_Raw (Zlib_Stream, Status);
         pragma Unreferenced (Output);
      begin
         Assert (Status /= Zlib.Ok, "Inflate_Raw(zlib stream) must fail");
      end;

      declare
         Output : constant Zlib.Byte_Array := Zlib.Inflate_Raw (GZip_Stream, Status);
         pragma Unreferenced (Output);
      begin
         Assert (Status /= Zlib.Ok, "Inflate_Raw(gzip stream) must fail");
      end;

      declare
         Output : constant Zlib.Byte_Array := Zlib.Inflate (Zlib_Stream, Status);
      begin
         Assert (Status = Zlib.Ok, "Inflate(zlib stream) must succeed");
         Assert_Same (Output, Input, "Inflate(zlib stream)");
      end;

      declare
         Output : constant Zlib.Byte_Array := Zlib.Inflate (GZip_Stream, Status);
      begin
         Assert (Status = Zlib.Ok, "Inflate(gzip stream) must auto-detect");
         Assert_Same (Output, Input, "Inflate(gzip stream)");
      end;

      declare
         Output : constant Zlib.Byte_Array := Zlib.Inflate (Raw_Stream, Status);
      begin
         Assert (Status = Zlib.Ok, "Inflate(raw payload) must auto-detect");
         Assert_Same (Output, Input, "Inflate(raw payload)");
      end;
   end Test_Wrapper_Strictness_Matrix;

   procedure Test_Invalid_Raw_Input_Returns_Non_Ok_Status
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status  : Zlib.Status_Code := Zlib.Ok;
      Invalid : constant Zlib.Byte_Array := [1 => 16#07#];
      Output  : constant Zlib.Byte_Array := Zlib.Inflate_Raw (Invalid, Status);
      pragma Unreferenced (Output);
   begin
      Assert
        (Status = Zlib.Invalid_Block_Type,
         "invalid raw input must fail with deterministic Invalid_Block_Type status");
   end Test_Invalid_Raw_Input_Returns_Non_Ok_Status;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_Inflate_Raw_Stored_Payload'Access,
         "Inflate_Raw accepts stored raw Deflate payloads");
      Registration.Register_Routine
        (T, Test_Inflate_Raw_Fixed_Payload'Access,
         "Inflate_Raw accepts fixed-Huffman raw Deflate payloads");
      Registration.Register_Routine
        (T, Test_Inflate_Raw_Dynamic_Payload'Access,
         "Inflate_Raw accepts dynamic-Huffman raw Deflate payloads");
      Registration.Register_Routine
        (T, Test_Inflate_Raw_Binary_Payload'Access,
         "Inflate_Raw preserves binary output exactly");
      Registration.Register_Routine
        (T, Test_Inflate_Raw_Rejects_Zlib_Wrapped'Access,
         "Inflate_Raw rejects zlib-wrapped payloads");
      Registration.Register_Routine
        (T, Test_Inflate_Raw_Rejects_Gzip_Wrapped'Access,
         "Inflate_Raw rejects gzip-wrapped payloads");
      Registration.Register_Routine
        (T, Test_Inflate_Raw_Equals_Explicit_Header'Access,
         "Inflate_Raw is equivalent to Inflate_With_Header Raw_Deflate");
      Registration.Register_Routine
        (T, Test_Inflate_Raw_File_Roundtrips_Raw_File'Access,
         "Inflate_Raw_File roundtrips Deflate_Raw_File output");
      Registration.Register_Routine
        (T, Test_Inflate_Raw_File_Streaming_Roundtrips_Raw_File'Access,
         "Inflate_Raw_File_Streaming roundtrips Deflate_Raw_File output");
      Registration.Register_Routine
        (T, Test_Missing_Input_File_Returns_Input_File_Error'Access,
         "Inflate_Raw file APIs return Input_File_Error for missing input");
      Registration.Register_Routine
        (T, Test_Wrapper_Strictness_Matrix'Access,
         "Inflate_Raw and Inflate preserve strict wrapper boundaries");
      Registration.Register_Routine
        (T, Test_Invalid_Raw_Input_Returns_Non_Ok_Status'Access,
         "Inflate_Raw invalid input returns deterministic Invalid_Block_Type status");
   end Register_Tests;
end Zlib_Inflate_Raw_Api_Tests;
