with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with CryptoLib.Checksums;
with Interfaces;
with Zlib;

package body Zlib_Rar_Tests is
   package SIO renames Ada.Streams.Stream_IO;
   package US renames Ada.Strings.Unbounded;

   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;
   use type Zlib.Status_Code;

   Fixture_Path : constant String := "zlib_rar_test_fixture.rar";

   File_Name : constant String := "hi.txt";
   Content   : constant String := "RAR data!";       --  9 bytes

   Method_Store : constant := 16#30#;

   --  ---------------------------------------------------------------------
   --  A tiny growable byte buffer used to assemble a RAR4 fixture on disk.
   --  ---------------------------------------------------------------------
   type Byte_Buffer is record
      Data : Zlib.Byte_Array (0 .. 1_023) := [others => 0];
      Len  : Natural := 0;
   end record;

   procedure Put_U8 (B : in out Byte_Buffer; Value : Natural) is
   begin
      B.Data (B.Len) := Zlib.Byte (Value mod 256);
      B.Len := B.Len + 1;
   end Put_U8;

   procedure Put_U16_LE (B : in out Byte_Buffer; Value : Natural) is
   begin
      Put_U8 (B, Value mod 256);
      Put_U8 (B, (Value / 256) mod 256);
   end Put_U16_LE;

   procedure Put_U32_LE (B : in out Byte_Buffer; Value : Interfaces.Unsigned_32)
   is
      V : constant Interfaces.Unsigned_64 := Interfaces.Unsigned_64 (Value);
   begin
      Put_U8 (B, Natural (V mod 256));
      Put_U8 (B, Natural ((V / 256) mod 256));
      Put_U8 (B, Natural ((V / 65_536) mod 256));
      Put_U8 (B, Natural ((V / 16_777_216) mod 256));
   end Put_U32_LE;

   procedure Put_String (B : in out Byte_Buffer; S : String) is
   begin
      for C of S loop
         Put_U8 (B, Character'Pos (C));
      end loop;
   end Put_String;

   function CRC_Of (S : String) return Interfaces.Unsigned_32 is
      Data : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (S'Length));
   begin
      for I in S'Range loop
         Data (Ada.Streams.Stream_Element_Offset (I - S'First + 1)) :=
           Ada.Streams.Stream_Element (Character'Pos (S (I)));
      end loop;
      return CryptoLib.Checksums.CRC32 (Data);
   end CRC_Of;

   --  Build a single-file RAR4 archive: marker, one file header, its data, and
   --  an End_Of_Archive block.
   function Build_Rar
     (Method   : Natural := Method_Store;
      Good_CRC : Boolean := True)
      return Zlib.Byte_Array
   is
      B         : Byte_Buffer;
      Name_Len  : constant Natural := File_Name'Length;
      Body_Size : constant Natural := 25 + Name_Len;
      Head_Size : constant Natural := 7 + Body_Size;
      CRC       : constant Interfaces.Unsigned_32 :=
        (if Good_CRC then CRC_Of (Content) else CRC_Of (Content) + 1);
   begin
      --  Marker: "Rar!" 1A 07 00
      Put_U8 (B, 16#52#); Put_U8 (B, 16#61#); Put_U8 (B, 16#72#);
      Put_U8 (B, 16#21#); Put_U8 (B, 16#1A#); Put_U8 (B, 16#07#);
      Put_U8 (B, 16#00#);

      --  File header (type 0x74), flags 0 (stored, not large/dir/encrypted).
      Put_U16_LE (B, 0);                    --  HEAD_CRC (unchecked)
      Put_U8 (B, 16#74#);                   --  HEAD_TYPE
      Put_U16_LE (B, 0);                    --  HEAD_FLAGS
      Put_U16_LE (B, Head_Size);            --  HEAD_SIZE
      --  file header body (relative offsets the reader expects)
      Put_U32_LE (B, Interfaces.Unsigned_32 (Content'Length));   --  PACK_SIZE
      Put_U32_LE (B, Interfaces.Unsigned_32 (Content'Length));   --  UNP_SIZE
      Put_U8 (B, 0);                        --  HOST_OS
      Put_U32_LE (B, CRC);                  --  FILE_CRC
      Put_U32_LE (B, 0);                    --  FTIME
      Put_U8 (B, 20);                       --  UNP_VER
      Put_U8 (B, Method);                   --  METHOD
      Put_U16_LE (B, Name_Len);             --  NAME_SIZE
      Put_U32_LE (B, 0);                    --  ATTR
      Put_String (B, File_Name);            --  NAME
      Put_String (B, Content);              --  packed data (stored)

      --  End_Of_Archive block (type 0x7B).
      Put_U16_LE (B, 0);                    --  HEAD_CRC
      Put_U8 (B, 16#7B#);                   --  HEAD_TYPE
      Put_U16_LE (B, 0);                    --  HEAD_FLAGS
      Put_U16_LE (B, 7);                    --  HEAD_SIZE

      return B.Data (0 .. B.Len - 1);
   end Build_Rar;

   procedure Write_Fixture (Data : Zlib.Byte_Array) is
      File   : SIO.File_Type;
      Buffer : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Data'Length));
   begin
      for I in Data'Range loop
         Buffer (Ada.Streams.Stream_Element_Offset (I - Data'First + 1)) :=
           Ada.Streams.Stream_Element (Data (I));
      end loop;
      SIO.Create (File, SIO.Out_File, Fixture_Path);
      SIO.Write (File, Buffer);
      SIO.Close (File);
   end Write_Fixture;

   procedure Delete_Fixture is
   begin
      if Ada.Directories.Exists (Fixture_Path) then
         Ada.Directories.Delete_File (Fixture_Path);
      end if;
   end Delete_Fixture;

   function Contains (Haystack, Needle : String) return Boolean is
     (Ada.Strings.Fixed.Index (Haystack, Needle) /= 0);

   Collected : US.Unbounded_String;

   procedure Collect (Bytes : Zlib.Byte_Array; Continue : in out Boolean) is
   begin
      Continue := True;
      for B of Bytes loop
         US.Append (Collected, Character'Val (Natural (B)));
      end loop;
   end Collect;

   function Extract (Name : String; Status : out Zlib.Status_Code) return String is
   begin
      Collected := US.Null_Unbounded_String;
      Zlib.Extract_Rar_File_Entry (Fixture_Path, Name, Collect'Access, Status);
      return US.To_String (Collected);
   end Extract;

   --  ---------------------------------------------------------------------
   --  Routines.
   --  ---------------------------------------------------------------------
   procedure Test_List (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code := Zlib.Invalid_Header;
   begin
      Write_Fixture (Build_Rar);
      declare
         Entries : constant Zlib.Archive_Entry_Array :=
           Zlib.List_Rar_File_Entries (Fixture_Path, Status);
      begin
         Assert (Status = Zlib.Ok, "List_Rar_File_Entries status not Ok");
         Assert (Entries'Length = 1, "expected one file header");
         Assert (US.To_String (Entries (Entries'First).Name) = File_Name,
                 "member name mismatch");
         Assert (Entries (Entries'First).Compression = 0,
                 "stored member should report Compression 0");
         Assert
           (Entries (Entries'First).Uncompressed_Size =
              Interfaces.Unsigned_64 (Content'Length),
            "member size mismatch");
         Assert (Entries (Entries'First).CRC_32 = CRC_Of (Content),
                 "member CRC mismatch");
         Assert
           (Contains (US.To_String (Entries (Entries'First).Metadata),
                      "rar.method=0x30"),
            "rar.method token missing");
      end;
      Delete_Fixture;
   end Test_List;

   procedure Test_Extract (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code := Zlib.Invalid_Header;
   begin
      Write_Fixture (Build_Rar);
      declare
         Bytes : constant String := Extract (File_Name, Status);
      begin
         Assert (Status = Zlib.Ok, "extract status not Ok");
         Assert (Bytes = Content, "member payload mismatch: " & Bytes);
      end;
      Delete_Fixture;
   end Test_Extract;

   procedure Test_CRC_Mismatch (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code := Zlib.Ok;
   begin
      Write_Fixture (Build_Rar (Good_CRC => False));
      declare
         Bytes : constant String := Extract (File_Name, Status);
      begin
         Assert (Bytes = Content,
                 "payload still streams before the checksum is checked");
         Assert (Status = Zlib.Invalid_Checksum,
                 "a wrong header CRC should be Invalid_Checksum");
      end;
      Delete_Fixture;
   end Test_CRC_Mismatch;

   procedure Test_Compressed_Not_Streamable
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code := Zlib.Ok;
   begin
      Write_Fixture (Build_Rar (Method => 16#33#));
      declare
         Bytes : constant String := Extract (File_Name, Status);
      begin
         Assert (Bytes'Length = 0, "a compressed member yields no bytes");
         Assert (Status = Zlib.Unsupported_Method,
                 "a compressed member should be Unsupported_Method");
      end;
      Delete_Fixture;
   end Test_Compressed_Not_Streamable;

   procedure Test_Missing (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code := Zlib.Ok;
   begin
      Write_Fixture (Build_Rar);
      declare
         Absent : constant String := Extract ("no-such-member", Status);
      begin
         Assert (Absent'Length = 0, "absent member should yield no bytes");
         Assert (Status = Zlib.Invalid_Header,
                 "absent member should be Invalid_Header");
      end;
      Delete_Fixture;
   end Test_Missing;

   procedure Test_Bad_Marker (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Image  : Zlib.Byte_Array := Build_Rar;
      Status : Zlib.Status_Code := Zlib.Ok;
   begin
      Image (Image'First) := 16#00#;   --  corrupt the 'R' of the marker
      Write_Fixture (Image);
      declare
         Entries : constant Zlib.Archive_Entry_Array :=
           Zlib.List_Rar_File_Entries (Fixture_Path, Status);
      begin
         Assert (Entries'Length = 0, "bad marker should yield no entries");
         Assert (Status = Zlib.Unsupported_Method,
                 "a non-RAR4 marker should be Unsupported_Method");
      end;
      Delete_Fixture;
   end Test_Bad_Marker;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib RAR 4.x reader");
   end Name;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_List'Access,
         "RAR catalogue lists a stored file with its CRC");
      Register_Routine
        (T, Test_Extract'Access,
         "RAR stored member payload streams out and verifies");
      Register_Routine
        (T, Test_CRC_Mismatch'Access,
         "a wrong RAR header CRC reports Invalid_Checksum");
      Register_Routine
        (T, Test_Compressed_Not_Streamable'Access,
         "a compressed RAR member reports Unsupported_Method");
      Register_Routine
        (T, Test_Missing'Access,
         "extracting an absent RAR member fails closed");
      Register_Routine
        (T, Test_Bad_Marker'Access,
         "a non-RAR4 marker is rejected as unsupported");
   end Register_Tests;

end Zlib_Rar_Tests;
