with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Interfaces;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;

package body Zlib_Deflate_Raw_Stored_Tests is
   use type Interfaces.Unsigned_64;
   use type Zlib.Byte;
   use type Zlib.Status_Code;

   package SIO renames Ada.Streams.Stream_IO;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib one-shot raw stored Deflate compression");
   end Name;

   function Empty return Zlib.Byte_Array is
      Result : constant Zlib.Byte_Array (1 .. 0) := [others => 0];
   begin
      return Result;
   end Empty;

   function Hello return Zlib.Byte_Array is
   begin
      return
        [1 => Zlib.Byte (Character'Pos ('h')),
         2 => Zlib.Byte (Character'Pos ('e')),
         3 => Zlib.Byte (Character'Pos ('l')),
         4 => Zlib.Byte (Character'Pos ('l')),
         5 => Zlib.Byte (Character'Pos ('o'))];
   end Hello;

   procedure Delete_If_Exists (Path : String) is
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   end Delete_If_Exists;

   procedure Write_Bytes (Path : String; Data : Zlib.Byte_Array) is
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

   function Read_Bytes (Path : String) return Zlib.Byte_Array is
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
               Result (I) :=
                 Zlib.Byte (Buffer (Ada.Streams.Stream_Element_Offset (I)));
            end loop;
            return Result;
         end;
      end;
   end Read_Bytes;

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

   procedure Assert_Roundtrip
     (Input   : Zlib.Byte_Array;
      Message : String)
   is
      Status     : Zlib.Status_Code := Zlib.Ok;
      Compressed : constant Zlib.Byte_Array :=
        Zlib.Deflate_Raw (Input, Zlib.Stored, Status);
      Inflated_Status : Zlib.Status_Code := Zlib.Ok;
      Inflated : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Compressed, Zlib.Raw_Deflate, Inflated_Status);
      Zlib_Status : Zlib.Status_Code := Zlib.Ok;
      GZip_Status : Zlib.Status_Code := Zlib.Ok;
      Zlib_Attempt : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Compressed, Zlib.Zlib_Header, Zlib_Status);
      GZip_Attempt : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Compressed, Zlib.GZip, GZip_Status);
      pragma Unreferenced (Zlib_Attempt, GZip_Attempt);
   begin
      Assert (Status = Zlib.Ok, Message & ": Deflate_Raw Stored status");
      Assert (Inflated_Status = Zlib.Ok, Message & ": raw inflate status");
      Assert_Same (Inflated, Input, Message & ": roundtrip");
      Assert (Zlib_Status /= Zlib.Ok, Message & ": rejected as zlib");
      Assert (GZip_Status /= Zlib.Ok, Message & ": rejected as gzip");
   end Assert_Roundtrip;

   procedure Test_Empty
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_Roundtrip (Empty, "empty raw stored");
   end Test_Empty;

   procedure Test_Hello
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_Roundtrip (Hello, "hello raw stored");
   end Test_Hello;

   procedure Test_Binary
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input : Zlib.Byte_Array (1 .. 512);
   begin
      for I in Input'Range loop
         Input (I) := Zlib.Byte ((I * 37) mod 256);
      end loop;
      Assert_Roundtrip (Input, "binary raw stored");
   end Test_Binary;

   procedure Test_Stored_Size_Predictor
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      procedure Check_Size
        (Uncompressed : Interfaces.Unsigned_64;
         Expected     : Interfaces.Unsigned_64;
         Message      : String)
      is
         Size : Interfaces.Unsigned_64 := 0;
         Ok   : constant Boolean :=
           Zlib.Stored_Raw_Deflate_Size (Uncompressed, Size);
      begin
         Assert (Ok, Message & ": prediction succeeds");
         Assert (Size = Expected, Message & ": predicted size");
      end Check_Size;
   begin
      Check_Size (0, 5, "empty stored raw deflate has one empty block");
      Check_Size (1, 6, "one byte stored raw deflate has one header");
      Check_Size (65_535, 65_540, "maximum stored block has one header");
      Check_Size (65_536, 65_546, "stored size accounts for second block");
   end Test_Stored_Size_Predictor;

   procedure Test_Stored_File_To_Stream_Roundtrip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input_Path      : constant String := "raw_stored_stream_input.tmp";
      Compressed_Path : constant String := "raw_stored_stream.deflate";
      Output          : SIO.File_Type;
      Status          : Zlib.Status_Code := Zlib.Ok;
      Written_Size    : Interfaces.Unsigned_64 := 0;
      Expected_Size   : Interfaces.Unsigned_64 := 0;
      Input           : Zlib.Byte_Array (1 .. 257);
   begin
      for I in Input'Range loop
         Input (I) := Zlib.Byte ((I * 19) mod 256);
      end loop;

      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Compressed_Path);
      Write_Bytes (Input_Path, Input);

      SIO.Create (Output, SIO.Out_File, Compressed_Path);
      Zlib.Deflate_Raw_Stored_File_To_Stream
        (Input_Path      => Input_Path,
         Output          => Output,
         Compressed_Size => Written_Size,
         Status          => Status);
      SIO.Close (Output);

      Assert (Status = Zlib.Ok, "stream raw stored deflate status");
      Assert
        (Zlib.Stored_Raw_Deflate_Size
           (Interfaces.Unsigned_64 (Input'Length), Expected_Size),
         "stream raw stored deflate size can be predicted");
      Assert (Written_Size = Expected_Size, "stream writer reports exact size");

      declare
         Compressed      : constant Zlib.Byte_Array := Read_Bytes (Compressed_Path);
         Inflated_Status : Zlib.Status_Code := Zlib.Ok;
         Inflated        : constant Zlib.Byte_Array :=
           Zlib.Inflate_Raw (Compressed, Inflated_Status);
      begin
         Assert (Inflated_Status = Zlib.Ok, "stream raw stored deflate inflates");
         Assert_Same (Inflated, Input, "stream raw stored deflate roundtrip");
      end;

      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Compressed_Path);
   end Test_Stored_File_To_Stream_Roundtrip;

   procedure Test_Raw_File_To_Stream_Auto_Roundtrip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input_Path      : constant String := "raw_auto_stream_input.tmp";
      Compressed_Path : constant String := "raw_auto_stream.deflate";
      Output          : SIO.File_Type;
      Status          : Zlib.Status_Code := Zlib.Ok;
      Written_Size    : Interfaces.Unsigned_64 := 0;
      Expected_Size   : Interfaces.Unsigned_64 := 0;
      Input           : Zlib.Byte_Array (1 .. 1024);
   begin
      for I in Input'Range loop
         Input (I) := Zlib.Byte (Character'Pos ('A') + (I mod 4));
      end loop;

      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Compressed_Path);
      Write_Bytes (Input_Path, Input);

      Zlib.Deflate_Raw_File_Size
        (Input_Path      => Input_Path,
         Mode            => Zlib.Auto,
         Compressed_Size => Expected_Size,
         Status          => Status);
      Assert (Status = Zlib.Ok, "raw auto file size status");

      SIO.Create (Output, SIO.Out_File, Compressed_Path);
      Zlib.Deflate_Raw_File_To_Stream
        (Input_Path      => Input_Path,
         Output          => Output,
         Mode            => Zlib.Auto,
         Compressed_Size => Written_Size,
         Status          => Status);
      SIO.Close (Output);

      Assert (Status = Zlib.Ok, "raw auto file-to-stream status");
      Assert (Written_Size = Expected_Size, "raw auto file size matches stream count");
      Assert (Written_Size < Interfaces.Unsigned_64 (Input'Length), "raw auto compresses repetitive input");

      declare
         Compressed      : constant Zlib.Byte_Array := Read_Bytes (Compressed_Path);
         Inflated_Status : Zlib.Status_Code := Zlib.Ok;
         Inflated        : constant Zlib.Byte_Array :=
           Zlib.Inflate_Raw (Compressed, Inflated_Status);
      begin
         Assert (Inflated_Status = Zlib.Ok, "raw auto stream output inflates");
         Assert_Same (Inflated, Input, "raw auto stream roundtrip");
      end;

      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Compressed_Path);
   end Test_Raw_File_To_Stream_Auto_Roundtrip;

   procedure Test_Raw_File_To_Stream_Mode_Matrix
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input_Path : constant String := "raw_mode_matrix_input.tmp";
      Input      : Zlib.Byte_Array (1 .. 1536);
   begin
      for I in Input'Range loop
         Input (I) := Zlib.Byte (Character'Pos ('A') + (I mod 7));
      end loop;

      Delete_If_Exists (Input_Path);
      Write_Bytes (Input_Path, Input);

      for Mode in Zlib.Compression_Mode loop
         declare
            Compressed_Path : constant String :=
              "raw_mode_matrix_" & Zlib.Compression_Mode'Image (Mode) & ".deflate";
            Output        : SIO.File_Type;
            Status        : Zlib.Status_Code := Zlib.Ok;
            Written_Size  : Interfaces.Unsigned_64 := 0;
            Expected_Size : Interfaces.Unsigned_64 := 0;
         begin
            Delete_If_Exists (Compressed_Path);
            Zlib.Deflate_Raw_File_Size
              (Input_Path      => Input_Path,
               Mode            => Mode,
               Compressed_Size => Expected_Size,
               Status          => Status);
            Assert (Status = Zlib.Ok, "raw mode size status " & Zlib.Compression_Mode'Image (Mode));

            SIO.Create (Output, SIO.Out_File, Compressed_Path);
            Zlib.Deflate_Raw_File_To_Stream
              (Input_Path      => Input_Path,
               Output          => Output,
               Mode            => Mode,
               Compressed_Size => Written_Size,
               Status          => Status);
            SIO.Close (Output);

            Assert (Status = Zlib.Ok, "raw mode stream status " & Zlib.Compression_Mode'Image (Mode));
            Assert (Written_Size = Expected_Size, "raw mode size match " & Zlib.Compression_Mode'Image (Mode));

            declare
               Compressed      : constant Zlib.Byte_Array := Read_Bytes (Compressed_Path);
               Inflated_Status : Zlib.Status_Code := Zlib.Ok;
               Inflated        : constant Zlib.Byte_Array :=
                 Zlib.Inflate_Raw (Compressed, Inflated_Status);
            begin
               Assert (Inflated_Status = Zlib.Ok, "raw mode inflates " & Zlib.Compression_Mode'Image (Mode));
               Assert_Same (Inflated, Input, "raw mode roundtrip " & Zlib.Compression_Mode'Image (Mode));
            end;

            Delete_If_Exists (Compressed_Path);
         end;
      end loop;

      Delete_If_Exists (Input_Path);
   end Test_Raw_File_To_Stream_Mode_Matrix;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine (T, Test_Empty'Access, "Deflate_Raw Stored empty roundtrips");
      Registration.Register_Routine (T, Test_Hello'Access, "Deflate_Raw Stored hello roundtrips");
      Registration.Register_Routine (T, Test_Binary'Access, "Deflate_Raw Stored binary roundtrips");
      Registration.Register_Routine
        (T, Test_Stored_Size_Predictor'Access,
         "Stored raw Deflate size predictor tracks block headers");
      Registration.Register_Routine
        (T, Test_Stored_File_To_Stream_Roundtrip'Access,
         "Stored raw Deflate file-to-stream helper roundtrips");
      Registration.Register_Routine
        (T, Test_Raw_File_To_Stream_Auto_Roundtrip'Access,
         "Raw Deflate file-to-stream Auto helper roundtrips");
      Registration.Register_Routine
        (T, Test_Raw_File_To_Stream_Mode_Matrix'Access,
         "Raw Deflate file-to-stream helper covers every mode");
   end Register_Tests;
end Zlib_Deflate_Raw_Stored_Tests;
