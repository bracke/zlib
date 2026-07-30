with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Interfaces;
with Zlib;

package body Zlib_Iso_Tests is
   package SIO renames Ada.Streams.Stream_IO;
   package US renames Ada.Strings.Unbounded;

   use type Interfaces.Unsigned_64;
   use type Zlib.Status_Code;

   Fixture_Path : constant String := "zlib_iso_test_fixture.iso";

   Sector       : constant := 2_048;
   PVD_Sector   : constant := 16;
   Root_Sector  : constant := 18;
   File_Sector  : constant := 19;
   Image_Bytes  : constant := 20 * Sector;

   File_Name    : constant String := "HELLO.TXT";
   Content      : constant String := "Hello, ISO!";      --  11 bytes

   --  ---------------------------------------------------------------------
   --  A minimal ISO 9660 image built by absolute offset in a fixed buffer.
   --  ---------------------------------------------------------------------
   type Image is array (Natural range 0 .. Image_Bytes - 1) of Zlib.Byte;

   procedure Put_U8 (Img : in out Image; Off : Natural; Value : Natural) is
   begin
      Img (Off) := Zlib.Byte (Value mod 256);
   end Put_U8;

   procedure Put_Str (Img : in out Image; Off : Natural; S : String) is
   begin
      for I in S'Range loop
         Img (Off + (I - S'First)) := Zlib.Byte (Character'Pos (S (I)));
      end loop;
   end Put_Str;

   --  ISO stores 32-bit fields both-endian: little then big (8 bytes).
   procedure Put_Both_U32 (Img : in out Image; Off : Natural; Value : Natural) is
   begin
      Put_U8 (Img, Off,     Value mod 256);
      Put_U8 (Img, Off + 1, (Value / 256) mod 256);
      Put_U8 (Img, Off + 2, (Value / 65_536) mod 256);
      Put_U8 (Img, Off + 3, (Value / 16_777_216) mod 256);
      Put_U8 (Img, Off + 4, (Value / 16_777_216) mod 256);
      Put_U8 (Img, Off + 5, (Value / 65_536) mod 256);
      Put_U8 (Img, Off + 6, (Value / 256) mod 256);
      Put_U8 (Img, Off + 7, Value mod 256);
   end Put_Both_U32;

   --  16-bit both-endian field (4 bytes).
   procedure Put_Both_U16 (Img : in out Image; Off : Natural; Value : Natural) is
   begin
      Put_U8 (Img, Off,     Value mod 256);
      Put_U8 (Img, Off + 1, (Value / 256) mod 256);
      Put_U8 (Img, Off + 2, (Value / 256) mod 256);
      Put_U8 (Img, Off + 3, Value mod 256);
   end Put_Both_U16;

   --  Write one directory record at Off; return its (even) byte length.
   function Put_Record
     (Img    : in out Image;
      Off    : Natural;
      Extent : Natural;
      Size   : Natural;
      Is_Dir : Boolean;
      Ident  : String)
      return Natural
   is
      Rec_Len : Natural := 33 + Ident'Length;
   begin
      if Rec_Len mod 2 = 1 then
         Rec_Len := Rec_Len + 1;
      end if;
      Put_U8 (Img, Off, Rec_Len);
      Put_U8 (Img, Off + 1, 0);                --  extended attribute length
      Put_Both_U32 (Img, Off + 2, Extent);
      Put_Both_U32 (Img, Off + 10, Size);
      --  bytes 18 .. 24: recording timestamp, left zero
      Put_U8 (Img, Off + 25, (if Is_Dir then 2 else 0));   --  file flags
      Put_Both_U16 (Img, Off + 28, 1);         --  volume sequence number
      Put_U8 (Img, Off + 32, Ident'Length);
      Put_Str (Img, Off + 33, Ident);
      return Rec_Len;
   end Put_Record;

   Dot     : constant String := [1 => Character'Val (0)];
   Dot_Dot : constant String := [1 => Character'Val (1)];

   function Build_Image return Zlib.Byte_Array is
      Img     : Image := [others => 0];
      PVD     : constant Natural := PVD_Sector * Sector;
      Root    : constant Natural := Root_Sector * Sector;
      Pos     : Natural := Root;
      Ignored : Natural;
   begin
      --  Primary volume descriptor.
      Put_U8 (Img, PVD, 1);                     --  descriptor type
      Put_Str (Img, PVD + 1, "CD001");          --  standard identifier
      Put_U8 (Img, PVD + 6, 1);                 --  version
      Ignored := Put_Record (Img, PVD + 156, Root_Sector, Sector, True, Dot);

      --  Root directory contents: "." , ".." , then the file.
      Pos := Pos + Put_Record (Img, Pos, Root_Sector, Sector, True, Dot);
      Pos := Pos + Put_Record (Img, Pos, Root_Sector, Sector, True, Dot_Dot);
      Ignored :=
        Put_Record (Img, Pos, File_Sector, Content'Length, False,
                    File_Name & ";1");
      pragma Assert (Ignored > 0);

      --  File payload.
      Put_Str (Img, File_Sector * Sector, Content);

      declare
         Result : Zlib.Byte_Array (0 .. Image_Bytes - 1);
      begin
         for I in Result'Range loop
            Result (I) := Img (I);
         end loop;
         return Result;
      end;
   end Build_Image;

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
      Zlib.Extract_Iso_File_Entry (Fixture_Path, Name, Collect'Access, Status);
      return US.To_String (Collected);
   end Extract;

   --  ---------------------------------------------------------------------
   --  Routines.
   --  ---------------------------------------------------------------------
   procedure Test_List (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code := Zlib.Invalid_Header;
   begin
      Write_Fixture (Build_Image);
      declare
         Entries : constant Zlib.Archive_Entry_Array :=
           Zlib.List_Iso_File_Entries (Fixture_Path, Status);
      begin
         Assert (Status = Zlib.Ok, "List_Iso_File_Entries status not Ok");
         Assert (Entries'Length = 1,
                 "expected one member (. and .. are skipped)");
         Assert (US.To_String (Entries (Entries'First).Name) = File_Name,
                 "member name should be the cleaned ISO name");
         Assert (not Entries (Entries'First).Is_Directory,
                 "member should be a regular file");
         Assert
           (Entries (Entries'First).Uncompressed_Size =
              Interfaces.Unsigned_64 (Content'Length),
            "member size mismatch");
         Assert (US.To_String (Entries (Entries'First).Metadata) = "iso9660",
                 "metadata should tag the format");
      end;
      Delete_Fixture;
   end Test_List;

   procedure Test_Extract (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code := Zlib.Invalid_Header;
   begin
      Write_Fixture (Build_Image);
      declare
         Bytes : constant String := Extract (File_Name, Status);
      begin
         Assert (Status = Zlib.Ok, "extract status not Ok");
         Assert (Bytes = Content, "member payload mismatch: " & Bytes);
      end;
      Delete_Fixture;
   end Test_Extract;

   procedure Test_Missing (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code := Zlib.Ok;
   begin
      Write_Fixture (Build_Image);
      declare
         Absent : constant String := Extract ("NOPE.TXT", Status);
      begin
         Assert (Absent'Length = 0, "absent member should yield no bytes");
         Assert (Status = Zlib.Invalid_Header,
                 "absent member should be Invalid_Header");
      end;
      Delete_Fixture;
   end Test_Missing;

   procedure Test_Bad_Magic (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Data   : Zlib.Byte_Array := Build_Image;
      Status : Zlib.Status_Code := Zlib.Ok;
   begin
      --  Corrupt the 'C' of "CD001" in the primary volume descriptor.
      Data (Data'First + PVD_Sector * Sector + 1) := 16#00#;
      Write_Fixture (Data);
      declare
         Entries : constant Zlib.Archive_Entry_Array :=
           Zlib.List_Iso_File_Entries (Fixture_Path, Status);
      begin
         Assert (Entries'Length = 0, "bad descriptor should yield no entries");
         Assert (Status = Zlib.Invalid_Header,
                 "bad descriptor should be Invalid_Header");
      end;
      Delete_Fixture;
   end Test_Bad_Magic;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib ISO 9660 reader");
   end Name;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_List'Access,
         "ISO 9660 catalogue lists files with cleaned names");
      Register_Routine
        (T, Test_Extract'Access,
         "ISO 9660 file payload streams out intact");
      Register_Routine
        (T, Test_Missing'Access,
         "extracting an absent ISO member fails closed");
      Register_Routine
        (T, Test_Bad_Magic'Access,
         "a non-CD001 volume descriptor is rejected");
   end Register_Tests;

end Zlib_Iso_Tests;
