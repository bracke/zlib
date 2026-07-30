with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Interfaces;
with Zlib;

package body Zlib_Cpio_Tests is
   package SIO renames Ada.Streams.Stream_IO;
   package US renames Ada.Strings.Unbounded;

   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_64;
   use type Zlib.Status_Code;

   Fixture_Path : constant String := "zlib_cpio_test_fixture.cpio";

   Dir_Name  : constant String := "dir";
   File_Name : constant String := "dir/file.txt";
   Content   : constant String := "cpio!";           --  5 bytes

   Mode_Dir  : constant := 16#41ED#;                  --  directory 0755
   Mode_Reg  : constant := 16#81A4#;                  --  regular 0644

   --  ---------------------------------------------------------------------
   --  A tiny growable byte buffer used to assemble a cpio fixture on disk.
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

   --  Eight uppercase hex digits, the cpio newc field width.
   procedure Put_Hex8 (B : in out Byte_Buffer; Value : Natural) is
      Digits_Set : constant String := "0123456789ABCDEF";
      Text       : String (1 .. 8);
      Rest       : Natural := Value;
   begin
      for I in reverse Text'Range loop
         Text (I) := Digits_Set (Rest mod 16 + 1);
         Rest := Rest / 16;
      end loop;
      Put_String (B, Text);
   end Put_Hex8;

   procedure Pad_To_4 (B : in out Byte_Buffer) is
   begin
      while B.Len mod 4 /= 0 loop
         Put_Char (B, Character'Val (0));
      end loop;
   end Pad_To_4;

   procedure Put_Entry
     (B    : in out Byte_Buffer;
      Mode : Natural;
      Name : String;
      Data : String) is
   begin
      Put_String (B, "070701");            --  magic (newc)
      Put_Hex8 (B, 1);                      --  ino
      Put_Hex8 (B, Mode);                   --  mode
      Put_Hex8 (B, 1000);                   --  uid
      Put_Hex8 (B, 1000);                   --  gid
      Put_Hex8 (B, 1);                      --  nlink
      Put_Hex8 (B, 0);                      --  mtime
      Put_Hex8 (B, Data'Length);            --  filesize
      Put_Hex8 (B, 0);                      --  devmajor
      Put_Hex8 (B, 0);                      --  devminor
      Put_Hex8 (B, 0);                      --  rdevmajor
      Put_Hex8 (B, 0);                      --  rdevminor
      Put_Hex8 (B, Name'Length + 1);        --  namesize (incl. NUL)
      Put_Hex8 (B, 0);                      --  check
      Put_String (B, Name);
      Put_Char (B, Character'Val (0));       --  name NUL terminator
      Pad_To_4 (B);                          --  header+name to 4-byte boundary
      Put_String (B, Data);
      Pad_To_4 (B);                          --  payload to 4-byte boundary
   end Put_Entry;

   function Build_Archive return Zlib.Byte_Array is
      B : Byte_Buffer;
   begin
      Put_Entry (B, Mode_Dir, Dir_Name, "");
      Put_Entry (B, Mode_Reg, File_Name, Content);
      Put_Entry (B, 0, "TRAILER!!!", "");
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
      Zlib.Extract_Cpio_File_Entry (Fixture_Path, Name, Collect'Access, Status);
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
           Zlib.List_Cpio_File_Entries (Fixture_Path, Status);
      begin
         Assert (Status = Zlib.Ok, "List_Cpio_File_Entries status not Ok");
         Assert (Entries'Length = 2,
                 "expected two members (TRAILER ends the walk)");
         Assert (US.To_String (Entries (Entries'First).Name) = Dir_Name,
                 "first member name mismatch");
         Assert (Entries (Entries'First).Is_Directory,
                 "first member should be a directory");
         Assert (US.To_String (Entries (Entries'First + 1).Name) = File_Name,
                 "second member name mismatch");
         Assert (not Entries (Entries'First + 1).Is_Directory,
                 "second member should be a regular file");
         Assert (Entries (Entries'First + 1).Compression = 0,
                 "cpio members are stored uncompressed");
         Assert
           (Entries (Entries'First + 1).Uncompressed_Size =
              Interfaces.Unsigned_64 (Content'Length),
            "regular member size mismatch");
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
           Zlib.List_Cpio_File_Entries (Fixture_Path, Status);
         Meta    : constant String :=
           US.To_String (Entries (Entries'First + 1).Metadata);
      begin
         Assert (Status = Zlib.Ok, "status not Ok");
         Assert (Contains (Meta, "cpio.mode=16#000081A4#"),
                 "cpio.mode token missing: " & Meta);
         Assert (Contains (Meta, "cpio.uid=1000"),
                 "cpio.uid token missing: " & Meta);
         Assert (Contains (Meta, "cpio.header_offset="),
                 "cpio.header_offset token missing: " & Meta);
      end;
      Delete_Fixture;
   end Test_Metadata;

   procedure Test_Extract (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code := Zlib.Invalid_Header;
   begin
      Write_Fixture (Build_Archive);
      declare
         Bytes : constant String := Extract (File_Name, Status);
      begin
         Assert (Status = Zlib.Ok, "extract status not Ok");
         Assert (Bytes = Content, "regular member payload mismatch: " & Bytes);
      end;
      Delete_Fixture;
   end Test_Extract;

   procedure Test_Directory_Not_Streamable
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code := Zlib.Ok;
   begin
      Write_Fixture (Build_Archive);
      declare
         Bytes : constant String := Extract (Dir_Name, Status);
      begin
         Assert (Bytes'Length = 0, "a directory has no payload");
         Assert (Status = Zlib.Unsupported_Method,
                 "a directory should be Unsupported_Method");
      end;
      Delete_Fixture;
   end Test_Directory_Not_Streamable;

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
      Image (Image'First) := 16#00#;   --  corrupt the '0' of "070701"
      Write_Fixture (Image);
      declare
         Entries : constant Zlib.Archive_Entry_Array :=
           Zlib.List_Cpio_File_Entries (Fixture_Path, Status);
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
      return AUnit.Format ("Zlib cpio reader");
   end Name;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_List'Access,
         "cpio catalogue lists members and directory flag");
      Register_Routine
        (T, Test_Metadata'Access,
         "cpio member metadata preserves mode/uid/offset");
      Register_Routine
        (T, Test_Extract'Access,
         "cpio regular member payload streams out intact");
      Register_Routine
        (T, Test_Directory_Not_Streamable'Access,
         "extracting a cpio directory reports Unsupported_Method");
      Register_Routine
        (T, Test_Missing'Access,
         "extracting an absent cpio member fails closed");
      Register_Routine
        (T, Test_Bad_Magic'Access,
         "a non-cpio signature is rejected");
   end Register_Tests;

end Zlib_Cpio_Tests;
