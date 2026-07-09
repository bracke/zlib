with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with AUnit.Assertions; use AUnit.Assertions;
with Interfaces;
with Zlib;

package body Zlib_ZIP_External_Codec_Tests is
   use type Ada.Directories.File_Kind;
   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;
   use type Zlib.Byte;
   use type Zlib.Status_Code;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib ZIP external codec tests");
   end Name;

   procedure Put_U16
     (Data  : in out Zlib.Byte_Array;
      Pos   : Natural;
      Value : Interfaces.Unsigned_16)
   is
   begin
      Data (Pos) := Zlib.Byte (Value and 16#00FF#);
      Data (Pos + 1) := Zlib.Byte (Interfaces.Shift_Right (Value, 8));
   end Put_U16;

   procedure Put_U32
     (Data  : in out Zlib.Byte_Array;
      Pos   : Natural;
      Value : Interfaces.Unsigned_32)
   is
   begin
      for Offset in 0 .. 3 loop
         Data (Pos + Offset) :=
           Zlib.Byte
             (Interfaces.Shift_Right (Value, Offset * 8) and 16#0000_00FF#);
      end loop;
   end Put_U32;

   procedure Put_U64
     (Data  : in out Zlib.Byte_Array;
      Pos   : Natural;
      Value : Interfaces.Unsigned_64)
   is
   begin
      for Offset in 0 .. 7 loop
         Data (Pos + Offset) :=
           Zlib.Byte
             (Interfaces.Shift_Right (Value, Offset * 8) and 16#0000_0000_0000_00FF#);
      end loop;
   end Put_U64;

   procedure Put_Name
     (Data : in out Zlib.Byte_Array;
      Pos  : Natural;
      Name : String)
   is
   begin
      for I in Name'Range loop
         Data (Pos + I - Name'First) := Zlib.Byte (Character'Pos (Name (I)));
      end loop;
   end Put_Name;

   procedure Assert_Bytes_Equal
     (Actual   : Zlib.Byte_Array;
      Expected : Zlib.Byte_Array;
      Message  : String)
   is
   begin
      Assert (Actual'Length = Expected'Length, Message & ": length mismatch");
      for I in Expected'Range loop
         Assert
           (Actual (Actual'First + I - Expected'First) = Expected (I),
            Message & ": byte mismatch");
      end loop;
   end Assert_Bytes_Equal;

   procedure Delete_If_Exists (Path : String) is
   begin
      if Ada.Directories.Exists (Path) then
         if Ada.Directories.Kind (Path) = Ada.Directories.Directory then
            Ada.Directories.Delete_Tree (Path);
         else
            Ada.Directories.Delete_File (Path);
         end if;
      end if;
   exception
      when others =>
         null;
   end Delete_If_Exists;

   procedure Write_File (Path : String; Data : Zlib.Byte_Array) is
      File : Ada.Streams.Stream_IO.File_Type;
      Raw  : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Data'Length));
   begin
      for I in Data'Range loop
         Raw (Ada.Streams.Stream_Element_Offset (I - Data'First + 1)) :=
           Ada.Streams.Stream_Element (Data (I));
      end loop;

      Ada.Streams.Stream_IO.Create
        (File, Ada.Streams.Stream_IO.Out_File, Path);
      Ada.Streams.Stream_IO.Write (File, Raw);
      Ada.Streams.Stream_IO.Close (File);
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         raise;
   end Write_File;

   function Archive_With_External_Payload
     (Payload         : Zlib.Byte_Array;
      Method          : Interfaces.Unsigned_16;
      Crc32           : Interfaces.Unsigned_32;
      Uncompressed    : Interfaces.Unsigned_64;
      Entry_Name      : String;
      Central_ZIP64   : Boolean := False) return Zlib.Byte_Array
   is
      Name_Length      : constant Natural := Entry_Name'Length;
      Extra_Length     : constant Natural := (if Central_ZIP64 then 20 else 0);
      Local_Length     : constant Natural := 30 + Name_Length + Payload'Length;
      Central_Offset   : constant Natural := Local_Length;
      Central_Length   : constant Natural := 46 + Name_Length + Extra_Length;
      EOCD_Offset      : constant Natural := Central_Offset + Central_Length;
      Total_Length     : constant Natural := EOCD_Offset + 22;
      Archive          : Zlib.Byte_Array (1 .. Total_Length) := [others => 0];
      Compressed_32    : constant Interfaces.Unsigned_32 :=
        Interfaces.Unsigned_32 (Payload'Length);
      Uncompressed_32  : constant Interfaces.Unsigned_32 :=
        Interfaces.Unsigned_32 (Uncompressed);
   begin
      Put_U32 (Archive, 1, 16#0403_4B50#);
      Put_U16 (Archive, 5, (if Central_ZIP64 then 45 else 20));
      Put_U16 (Archive, 9, Method);
      Put_U32 (Archive, 15, Crc32);
      Put_U32 (Archive, 19, Compressed_32);
      Put_U32 (Archive, 23, Uncompressed_32);
      Put_U16 (Archive, 27, Interfaces.Unsigned_16 (Name_Length));
      Put_Name (Archive, 31, Entry_Name);
      for I in Payload'Range loop
         Archive (31 + Name_Length + I - Payload'First) := Payload (I);
      end loop;

      Put_U32 (Archive, Central_Offset + 1, 16#0201_4B50#);
      Put_U16 (Archive, Central_Offset + 5, 45);
      Put_U16 (Archive, Central_Offset + 7, (if Central_ZIP64 then 45 else 20));
      Put_U16 (Archive, Central_Offset + 11, Method);
      Put_U32 (Archive, Central_Offset + 17, Crc32);
      Put_U32
        (Archive, Central_Offset + 21,
         (if Central_ZIP64 then 16#FFFF_FFFF# else Compressed_32));
      Put_U32
        (Archive, Central_Offset + 25,
         (if Central_ZIP64 then 16#FFFF_FFFF# else Uncompressed_32));
      Put_U16 (Archive, Central_Offset + 29, Interfaces.Unsigned_16 (Name_Length));
      Put_U16 (Archive, Central_Offset + 31, Interfaces.Unsigned_16 (Extra_Length));
      Put_Name (Archive, Central_Offset + 47, Entry_Name);

      if Central_ZIP64 then
         declare
            Extra_First : constant Natural := Central_Offset + 47 + Name_Length;
         begin
            Put_U16 (Archive, Extra_First, 16#0001#);
            Put_U16 (Archive, Extra_First + 2, 16);
            Put_U64 (Archive, Extra_First + 4, Uncompressed);
            Put_U64 (Archive, Extra_First + 12, Interfaces.Unsigned_64 (Payload'Length));
         end;
      end if;

      Put_U32 (Archive, EOCD_Offset + 1, 16#0605_4B50#);
      Put_U16 (Archive, EOCD_Offset + 9, 1);
      Put_U16 (Archive, EOCD_Offset + 11, 1);
      Put_U32 (Archive, EOCD_Offset + 13, Interfaces.Unsigned_32 (Central_Length));
      Put_U32 (Archive, EOCD_Offset + 17, Interfaces.Unsigned_32 (Central_Offset));
      return Archive;
   end Archive_With_External_Payload;

   function Repeated_Data
     (Length : Positive;
      Step   : Positive) return Zlib.Byte_Array
   is
      Result : Zlib.Byte_Array (1 .. Length);
   begin
      for I in Result'Range loop
         Result (I) := Zlib.Byte (Character'Pos ('A') + ((I * Step) mod 23));
      end loop;
      return Result;
   end Repeated_Data;

   procedure Assert_ZIP_External_Roundtrip
     (Method_Name     : String;
      Expected_Method : Interfaces.Unsigned_16;
      Plain           : Zlib.Byte_Array;
      Message         : String;
      Central_ZIP64   : Boolean := False;
      Archive_Method  : Interfaces.Unsigned_16 := 0)
   is
      Input_Path        : constant String := "zlib-zip-external-input.bin";
      Effective_Method  : Interfaces.Unsigned_16 := Expected_Method;
      Method            : Interfaces.Unsigned_16;
      Crc32             : Interfaces.Unsigned_32;
      Uncompressed_Size : Interfaces.Unsigned_64;
      Status            : Zlib.Status_Code;
   begin
      if Archive_Method /= 0 then
         Effective_Method := Archive_Method;
      end if;

      Write_File (Input_Path, Plain);
      declare
         Payload : constant Zlib.Byte_Array :=
           Zlib.Compress_ZIP_External_File
             (Input_Path, Method_Name, Method, Crc32, Uncompressed_Size,
              Status);
      begin
         Assert (Status = Zlib.Ok, Message & ": compression status");
         Assert (Method = Expected_Method, Message & ": compression method");
         Assert
           (Uncompressed_Size = Interfaces.Unsigned_64 (Plain'Length),
            Message & ": uncompressed size");
         declare
            Archive : constant Zlib.Byte_Array :=
              Archive_With_External_Payload
                (Payload, Effective_Method, Crc32, Uncompressed_Size, "payload.bin",
                 Central_ZIP64);
            Decoded : constant Zlib.Byte_Array :=
              Zlib.Extract_ZIP_External_Entry
                (Archive, "payload.bin", "", Status);
         begin
            Assert (Status = Zlib.Ok, Message & ": extraction status");
            Assert_Bytes_Equal (Decoded, Plain, Message);
         end;
      end;
      Delete_If_Exists (Input_Path);
   exception
      when others =>
         Delete_If_Exists (Input_Path);
         raise;
   end Assert_ZIP_External_Roundtrip;

   procedure Test_ZIP_BZip2_Created
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_ZIP_External_Roundtrip
        ("BZip2", 12, Repeated_Data (192, 3),
         "ZIP BZip2 payloads are created in-process");
   end Test_ZIP_BZip2_Created;

   procedure Test_ZIP_BZip2_Extracted
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_ZIP_External_Roundtrip
        ("BZip2", 12, Repeated_Data (193, 5),
         "ZIP BZip2 payloads are extracted in-process");
   end Test_ZIP_BZip2_Extracted;

   procedure Test_ZIP_LZMA_Created
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_ZIP_External_Roundtrip
        ("LZMA", 14, Repeated_Data (224, 2),
         "ZIP LZMA payloads are created in-process");
   end Test_ZIP_LZMA_Created;

   procedure Test_ZIP_LZMA_Extracted
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_ZIP_External_Roundtrip
        ("LZMA", 14, Repeated_Data (225, 7),
         "ZIP LZMA payloads are extracted in-process");
   end Test_ZIP_LZMA_Extracted;

   procedure Test_ZIP_LZMA_Selects_Non_Default_Properties
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Default_Props : constant Zlib.Byte := 16#5D#;
      Input_Path    : constant String := "zlib-zip-lzma-props-input.bin";
      Status        : Zlib.Status_Code;
      Found         : Boolean := False;

      procedure Check (Plain : Zlib.Byte_Array; Label : String) is
         Method            : Interfaces.Unsigned_16;
         Crc32             : Interfaces.Unsigned_32;
         Uncompressed_Size : Interfaces.Unsigned_64;
      begin
         Write_File (Input_Path, Plain);
         declare
            Payload : constant Zlib.Byte_Array :=
              Zlib.Compress_ZIP_External_File
                (Input_Path, "LZMA", Method, Crc32, Uncompressed_Size,
                 Status);
         begin
            Assert (Status = Zlib.Ok, Label & " compression status");
            Assert (Method = 14, Label & " compression method");
            Assert (Payload'Length > 9, Label & " LZMA payload header");
            Assert (Payload (Payload'First + 2) = 5, Label & " LZMA props size");
            Assert (Payload (Payload'First + 3) = 0, Label & " LZMA props size high");

            if Payload (Payload'First + 4) /= Default_Props then
               Found := True;
            end if;

            declare
               Archive : constant Zlib.Byte_Array :=
                 Archive_With_External_Payload
                   (Payload, 14, Crc32, Uncompressed_Size, "payload.bin");
               Decoded : constant Zlib.Byte_Array :=
                 Zlib.Extract_ZIP_External_Entry
                   (Archive, "payload.bin", "", Status);
            begin
               Assert (Status = Zlib.Ok, Label & " extraction status");
               Assert_Bytes_Equal (Decoded, Plain, Label & " roundtrip");
            end;
         end;
      end Check;

      Binary_Input : Zlib.Byte_Array (1 .. 4096);
      Text_Input   : Zlib.Byte_Array (1 .. 4096);
      Sparse_Input : Zlib.Byte_Array (1 .. 4096);
      Text_Pattern : constant String := "etaoin shrdlu ";
   begin
      for I in Binary_Input'Range loop
         Binary_Input (I) := Zlib.Byte ((I * 37 + I / 7) mod 256);
         Text_Input (I) :=
           Zlib.Byte
             (Character'Pos
                (Text_Pattern ((I - 1) mod Text_Pattern'Length + 1)));
         Sparse_Input (I) := (if I mod 17 = 0 then 16#80# else 0);
      end loop;

      Check (Binary_Input, "ZIP LZMA binary tuned props");
      Check (Text_Input, "ZIP LZMA text tuned props");
      Check (Sparse_Input, "ZIP LZMA sparse tuned props");
      Assert (Found, "ZIP LZMA writer selected a non-default property set");
      Delete_If_Exists (Input_Path);
   exception
      when others =>
         Delete_If_Exists (Input_Path);
         raise;
   end Test_ZIP_LZMA_Selects_Non_Default_Properties;

   procedure Test_ZIP_Zstd_Created
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_ZIP_External_Roundtrip
        ("ZSTD", 93, Repeated_Data (160, 4),
         "ZIP Zstd payloads are created in-process");
   end Test_ZIP_Zstd_Created;

   procedure Test_ZIP_Zstd_Extracted
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_ZIP_External_Roundtrip
        ("ZSTD", 93, Repeated_Data (161, 6),
         "ZIP Zstd payloads are extracted in-process");
   end Test_ZIP_Zstd_Extracted;

   procedure Test_ZIP_Legacy_Zstd_Extracted
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_ZIP_External_Roundtrip
        ("ZSTD", 93, Repeated_Data (162, 8),
         "ZIP legacy Zstd payloads are extracted in-process",
         Archive_Method => 20);
   end Test_ZIP_Legacy_Zstd_Extracted;

   procedure Test_ZIP64_LZMA_Extracted
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_ZIP_External_Roundtrip
        ("LZMA", 14, Repeated_Data (240, 9),
         "ZIP64 LZMA payloads are extracted in-process",
         Central_ZIP64 => True);
   end Test_ZIP64_LZMA_Extracted;

   procedure Test_ZIP64_BZip2_Extracted
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_ZIP_External_Roundtrip
        ("BZip2", 12, Repeated_Data (241, 10),
         "ZIP64 BZip2 payloads are extracted in-process",
         Central_ZIP64 => True);
   end Test_ZIP64_BZip2_Extracted;

   procedure Test_ZIP64_Zstd_Extracted
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_ZIP_External_Roundtrip
        ("ZSTD", 93, Repeated_Data (242, 11),
         "ZIP64 Zstd payloads are extracted in-process",
         Central_ZIP64 => True);
   end Test_ZIP64_Zstd_Extracted;

   procedure Test_ZIP64_Legacy_Zstd_Extracted
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_ZIP_External_Roundtrip
        ("ZSTD", 93, Repeated_Data (243, 12),
         "ZIP64 legacy Zstd payloads are extracted in-process",
         Central_ZIP64 => True,
         Archive_Method => 20);
   end Test_ZIP64_Legacy_Zstd_Extracted;

   procedure Test_Zstandard_ZIP_Method_Name
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert (Zlib.Is_ZIP_External_Method (20), "Zstandard ZIP method name legacy method");
      Assert (Zlib.Is_ZIP_External_Method (93), "Zstandard ZIP method name modern method");
      Assert (Zlib.ZIP_External_Method_Name (20) = "ZSTD", "Zstandard ZIP method name legacy");
      Assert (Zlib.ZIP_External_Method_Name (93) = "ZSTD", "Zstandard ZIP method name modern");
   end Test_Zstandard_ZIP_Method_Name;

   procedure Test_LZMA_Repeated_Match
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_ZIP_External_Roundtrip
        ("LZMA", 14, Repeated_Data (320, 1),
         "native LZMA repeated payload uses match coding");
   end Test_LZMA_Repeated_Match;

   procedure Test_LZMA_Small_Distance_Match
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_ZIP_External_Roundtrip
        ("LZMA", 14, Repeated_Data (321, 2),
         "native LZMA small-distance payload uses match coding");
   end Test_LZMA_Small_Distance_Match;

   procedure Test_LZMA_Pos_Special_Match
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_ZIP_External_Roundtrip
        ("LZMA", 14, Repeated_Data (322, 13),
         "native LZMA pos-special payload uses match coding");
   end Test_LZMA_Pos_Special_Match;

   procedure Test_LZMA_Direct_Distance_Match
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_ZIP_External_Roundtrip
        ("LZMA", 14, Repeated_Data (640, 17),
         "native LZMA direct-distance payload uses match coding");
   end Test_LZMA_Direct_Distance_Match;

   procedure Test_LZMA_Rep_Match
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_ZIP_External_Roundtrip
        ("LZMA", 14, Repeated_Data (384, 4),
         "native LZMA rep payload uses repeated-distance match coding");
   end Test_LZMA_Rep_Match;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_ZIP_BZip2_Created'Access,
         "ZIP BZip2 payloads are created in-process");
      Registration.Register_Routine
        (T, Test_ZIP_BZip2_Extracted'Access,
         "ZIP BZip2 payloads are extracted in-process");
      Registration.Register_Routine
        (T, Test_ZIP_LZMA_Created'Access,
         "ZIP LZMA payloads are created in-process");
      Registration.Register_Routine
        (T, Test_ZIP_LZMA_Extracted'Access,
         "ZIP LZMA payloads are extracted in-process");
      Registration.Register_Routine
        (T, Test_ZIP_LZMA_Selects_Non_Default_Properties'Access,
         "ZIP LZMA payloads select non-default coder properties");
      Registration.Register_Routine
        (T, Test_ZIP_Zstd_Created'Access,
         "ZIP Zstd payloads are created in-process");
      Registration.Register_Routine
        (T, Test_ZIP_Zstd_Extracted'Access,
         "ZIP Zstd payloads are extracted in-process");
      Registration.Register_Routine
        (T, Test_ZIP_Legacy_Zstd_Extracted'Access,
         "ZIP legacy Zstd payloads are extracted in-process");
      Registration.Register_Routine
        (T, Test_ZIP64_LZMA_Extracted'Access,
         "ZIP64 LZMA payloads are extracted in-process");
      Registration.Register_Routine
        (T, Test_ZIP64_BZip2_Extracted'Access,
         "ZIP64 BZip2 payloads are extracted in-process");
      Registration.Register_Routine
        (T, Test_ZIP64_Zstd_Extracted'Access,
         "ZIP64 Zstd payloads are extracted in-process");
      Registration.Register_Routine
        (T, Test_ZIP64_Legacy_Zstd_Extracted'Access,
         "ZIP64 legacy Zstd payloads are extracted in-process");
      Registration.Register_Routine
        (T, Test_Zstandard_ZIP_Method_Name'Access,
         "Zstandard ZIP method name");
      Registration.Register_Routine
        (T, Test_LZMA_Repeated_Match'Access,
         "native LZMA repeated payload uses match coding");
      Registration.Register_Routine
        (T, Test_LZMA_Small_Distance_Match'Access,
         "native LZMA small-distance payload uses match coding");
      Registration.Register_Routine
        (T, Test_LZMA_Pos_Special_Match'Access,
         "native LZMA pos-special payload uses match coding");
      Registration.Register_Routine
        (T, Test_LZMA_Direct_Distance_Match'Access,
         "native LZMA direct-distance payload uses match coding");
      Registration.Register_Routine
        (T, Test_LZMA_Rep_Match'Access,
         "native LZMA rep payload uses repeated-distance match coding");
   end Register_Tests;
end Zlib_ZIP_External_Codec_Tests;
