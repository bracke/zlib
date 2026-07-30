with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Interfaces;
with Zlib;

package body Zlib_Ar_Tests is
   package SIO renames Ada.Streams.Stream_IO;
   package US renames Ada.Strings.Unbounded;

   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_64;
   use type Zlib.Status_Code;

   Fixture_Path : constant String := "zlib_ar_test_fixture.a";

   Name_1    : constant String := "a.txt";
   Content_1 : constant String := "abc";              --  3 bytes (odd)
   Name_2    : constant String := "readme.md";
   Content_2 : constant String := "hello world";      --  11 bytes (odd)

   --  ---------------------------------------------------------------------
   --  A tiny growable byte buffer used to assemble "ar" fixtures on disk.
   --  ---------------------------------------------------------------------
   type Byte_Buffer is record
      Data : Zlib.Byte_Array (0 .. 4_095) := [others => 0];
      Len  : Natural := 0;
   end record;

   procedure Put_Char (B : in out Byte_Buffer; C : Character) is
   begin
      B.Data (B.Len) := Zlib.Byte (Character'Pos (C));
      B.Len := B.Len + 1;
   end Put_Char;

   procedure Put_String (B : in out Byte_Buffer; S : String) is
   begin
      for C of S loop
         Put_Char (B, C);
      end loop;
   end Put_String;

   --  Left-justify Text in a Width-wide space-padded field (the "ar" header
   --  field convention).
   procedure Put_Field
     (B     : in out Byte_Buffer;
      Text  : String;
      Width : Positive) is
   begin
      Put_String (B, Ada.Strings.Fixed.Head (Text, Width));
   end Put_Field;

   function Decimal (Value : Natural) return String is
   begin
      return Ada.Strings.Fixed.Trim
        (Natural'Image (Value), Ada.Strings.Left);
   end Decimal;

   procedure Put_Member
     (B    : in out Byte_Buffer;
      Name : String;
      Data : String) is
   begin
      Put_Field (B, Name & "/", 16);        --  GNU short-name terminator
      Put_Field (B, "0", 12);               --  mtime
      Put_Field (B, "1000", 6);             --  uid
      Put_Field (B, "1000", 6);             --  gid
      Put_Field (B, "100644", 8);           --  mode (octal)
      Put_Field (B, Decimal (Data'Length), 10);
      Put_Char (B, '`');
      Put_Char (B, Character'Val (10));      --  header magic "`\n"
      Put_String (B, Data);
      if Data'Length mod 2 = 1 then
         Put_Char (B, Character'Val (10));   --  even-alignment padding
      end if;
   end Put_Member;

   function Build_Archive return Zlib.Byte_Array is
      B : Byte_Buffer;
   begin
      Put_String (B, "!<arch>" & Character'Val (10));
      Put_Member (B, Name_1, Content_1);
      Put_Member (B, Name_2, Content_2);
      return B.Data (0 .. B.Len - 1);
   end Build_Archive;

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

   --  Collect a streamed member into a String.
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
      Zlib.Extract_Ar_File_Entry (Fixture_Path, Name, Collect'Access, Status);
      return US.To_String (Collected);
   end Extract;

   --  ---------------------------------------------------------------------
   --  Routines.
   --  ---------------------------------------------------------------------
   procedure Test_List (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code := Zlib.Invalid_Header;
   begin
      Write_Fixture (Build_Archive);
      declare
         Entries : constant Zlib.Archive_Entry_Array :=
           Zlib.List_Ar_File_Entries (Fixture_Path, Status);
      begin
         Assert (Status = Zlib.Ok, "List_Ar_File_Entries status not Ok");
         Assert (Entries'Length = 2, "expected two catalogued members");
         Assert (US.To_String (Entries (Entries'First).Name) = Name_1,
                 "first member name mismatch");
         Assert (US.To_String (Entries (Entries'First + 1).Name) = Name_2,
                 "second member name mismatch");
         Assert (Entries (Entries'First).Compression = 0,
                 "ar members are stored uncompressed");
         Assert
           (Entries (Entries'First).Uncompressed_Size =
              Interfaces.Unsigned_64 (Content_1'Length),
            "first member size mismatch");
         Assert
           (Entries (Entries'First + 1).Uncompressed_Size =
              Interfaces.Unsigned_64 (Content_2'Length),
            "second member size mismatch");
      end;
      Delete_Fixture;
   end Test_List;

   procedure Test_Metadata (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code := Zlib.Invalid_Header;
   begin
      Write_Fixture (Build_Archive);
      declare
         Entries : constant Zlib.Archive_Entry_Array :=
           Zlib.List_Ar_File_Entries (Fixture_Path, Status);
         Meta    : constant String :=
           US.To_String (Entries (Entries'First).Metadata);
      begin
         Assert (Status = Zlib.Ok, "status not Ok");
         Assert (Contains (Meta, "ar.size=3"), "ar.size token missing: " & Meta);
         Assert (Contains (Meta, "ar.mode=8#100644#"),
                 "ar.mode token missing: " & Meta);
         Assert (Contains (Meta, "ar.uid=1000"), "ar.uid token missing: " & Meta);
         Assert (Contains (Meta, "ar.header_offset="),
                 "ar.header_offset token missing: " & Meta);
      end;
      Delete_Fixture;
   end Test_Metadata;

   procedure Test_Extract (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      S1, S2 : Zlib.Status_Code := Zlib.Invalid_Header;
   begin
      Write_Fixture (Build_Archive);
      declare
         B1 : constant String := Extract (Name_1, S1);
         B2 : constant String := Extract (Name_2, S2);
      begin
         Assert (S1 = Zlib.Ok, "first extract status not Ok");
         Assert (S2 = Zlib.Ok, "second extract status not Ok");
         Assert (B1 = Content_1, "first member payload mismatch: " & B1);
         Assert (B2 = Content_2, "second member payload mismatch: " & B2);
      end;
      Delete_Fixture;
   end Test_Extract;

   procedure Test_Missing (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code := Zlib.Ok;
   begin
      Write_Fixture (Build_Archive);
      declare
         Absent : constant String := Extract ("no-such-member", Status);
      begin
         Assert (Absent'Length = 0, "absent member should yield no bytes");
         Assert (Status = Zlib.Invalid_Header,
                 "absent member should be Invalid_Header");
      end;
      Delete_Fixture;
   end Test_Missing;

   procedure Test_Bad_Magic (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Image  : Zlib.Byte_Array := Build_Archive;
      Status : Zlib.Status_Code := Zlib.Ok;
   begin
      Image (Image'First) := 16#00#;   --  corrupt the '!' of "!<arch>"
      Write_Fixture (Image);
      declare
         Entries : constant Zlib.Archive_Entry_Array :=
           Zlib.List_Ar_File_Entries (Fixture_Path, Status);
      begin
         Assert (Entries'Length = 0, "bad magic should yield no entries");
         Assert (Status = Zlib.Invalid_Header,
                 "bad magic should be Invalid_Header");
      end;
      Delete_Fixture;
   end Test_Bad_Magic;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib Unix ar reader");
   end Name;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_List'Access,
         "ar catalogue lists members with sizes");
      Register_Routine
        (T, Test_Metadata'Access,
         "ar member metadata preserves size/mode/uid/offset");
      Register_Routine
        (T, Test_Extract'Access,
         "ar member payloads stream out intact");
      Register_Routine
        (T, Test_Missing'Access,
         "extracting an absent ar member fails closed");
      Register_Routine
        (T, Test_Bad_Magic'Access,
         "a non-ar signature is rejected");
   end Register_Tests;

end Zlib_Ar_Tests;
