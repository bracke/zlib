with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib; use Zlib;

package body Zlib_ZIP_Entry_Count_Tests is

   Work_Dir : constant String := "zip-entry-count-work";

   function Byte_Char (Value : Natural) return String is
     [1 => Character'Val (Value)];

   --  Little-endian fields.
   function U16 (Value : Natural) return String is
     (Byte_Char (Value mod 256) & Byte_Char (Value / 256 mod 256));
   function U32 (Value : Natural) return String is
     (U16 (Value mod 65_536) & U16 (Value / 65_536));
   function U64 (Value : Long_Long_Integer) return String is
     (Byte_Char (Natural (Value mod 256)) & Byte_Char (Natural (Value / 2 ** 8 mod 256))
      & Byte_Char (Natural (Value / 2 ** 16 mod 256)) & Byte_Char (Natural (Value / 2 ** 24 mod 256))
      & Byte_Char (Natural (Value / 2 ** 32 mod 256)) & Byte_Char (Natural (Value / 2 ** 40 mod 256))
      & Byte_Char (Natural (Value / 2 ** 48 mod 256)) & Byte_Char (Natural (Value / 2 ** 56 mod 256)));
   All_Ones_16 : constant String := Byte_Char (255) & Byte_Char (255);
   All_Ones_32 : constant String := All_Ones_16 & All_Ones_16;

   type Member is record
      Name : Unbounded_String;
      Data : Unbounded_String;
   end record;
   type Member_List is array (Positive range <>) of Member;

   function Stored (Name, Data : String) return Member is
     ((To_Unbounded_String (Name), To_Unbounded_String (Data)));

   --  Members stored (method 0): their local headers and data, and the
   --  central directory; the caller ends the archive.
   procedure Build
     (Members : Member_List;
      Locals  : out Unbounded_String;
      Central : out Unbounded_String) is
   begin
      Locals := Null_Unbounded_String;
      Central := Null_Unbounded_String;
      for Item of Members loop
         declare
            Name   : constant String := To_String (Item.Name);
            Data   : constant String := To_String (Item.Data);
            Offset : constant Natural := Length (Locals);
         begin
            Append
              (Locals,
               "PK" & Byte_Char (3) & Byte_Char (4) & U16 (10) & U16 (0) & U16 (0) & U16 (0) & U16 (0)
               & U32 (0) & U32 (Data'Length) & U32 (Data'Length) & U16 (Name'Length) & U16 (0)
               & Name & Data);
            Append
              (Central,
               "PK" & Byte_Char (1) & Byte_Char (2) & U16 (20) & U16 (10) & U16 (0) & U16 (0) & U16 (0)
               & U16 (0) & U32 (0) & U32 (Data'Length) & U32 (Data'Length) & U16 (Name'Length) & U16 (0)
               & U16 (0) & U16 (0) & U16 (0) & U32 (0) & U32 (Offset) & Name);
         end;
      end loop;
   end Build;

   function Zip_Of (Members : Member_List; Comment : String := "") return String is
      Locals  : Unbounded_String;
      Central : Unbounded_String;
   begin
      Build (Members, Locals, Central);
      return To_String (Locals) & To_String (Central)
        & "PK" & Byte_Char (5) & Byte_Char (6) & U16 (0) & U16 (0) & U16 (Members'Length)
        & U16 (Members'Length) & U32 (Length (Central)) & U32 (Length (Locals)) & U16 (Comment'Length)
        & Comment;
   end Zip_Of;

   --  A ZIP64 archive whose ZIP64 record states Total entries; the end
   --  record's fields all say "see ZIP64".
   function Zip64_Of (Members : Member_List; Total : Long_Long_Integer) return String is
      Locals  : Unbounded_String;
      Central : Unbounded_String;
   begin
      Build (Members, Locals, Central);
      declare
         Record_At : constant Natural := Length (Locals) + Length (Central);
      begin
         return To_String (Locals) & To_String (Central)
           & "PK" & Byte_Char (6) & Byte_Char (6) & U64 (44) & U16 (45) & U16 (45) & U32 (0) & U32 (0)
           & U64 (Total) & U64 (Total) & U64 (Long_Long_Integer (Length (Central)))
           & U64 (Long_Long_Integer (Length (Locals)))
           & "PK" & Byte_Char (6) & Byte_Char (7) & U32 (0) & U64 (Long_Long_Integer (Record_At)) & U32 (1)
           & "PK" & Byte_Char (5) & Byte_Char (6) & All_Ones_16 & All_Ones_16 & All_Ones_16 & All_Ones_16
           & All_Ones_32 & All_Ones_32 & U16 (0);
      end;
   end Zip64_Of;

   procedure Write (Path : String; Content : String) is
      File : Ada.Streams.Stream_IO.File_Type;
   begin
      Ada.Streams.Stream_IO.Create (File, Ada.Streams.Stream_IO.Out_File, Path);
      String'Write (Ada.Streams.Stream_IO.Stream (File), Content);
      Ada.Streams.Stream_IO.Close (File);
   end Write;

   procedure Expect
     (Name     : String;
      Content  : String;
      Count    : Natural;
      Capped   : Boolean;
      Status   : Status_Code;
      Message  : String)
   is
      Path       : constant String := Work_Dir & "/" & Name;
      Got        : Natural;
      Got_Capped : Boolean;
      Got_Status : Status_Code;
   begin
      Write (Path, Content);
      Count_ZIP_File_Entries (Path, Got, Got_Capped, Got_Status);
      Assert (Got_Status = Status, Message & ": status " & Status_Code'Image (Got_Status));
      Assert (Got = Count, Message & ": count" & Natural'Image (Got));
      Assert (Got_Capped = Capped, Message & ": capped");
   end Expect;

   procedure Test_Counts_From_End_Record (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Three : constant Member_List :=
        [Stored ("a.txt", "one"), Stored ("b.txt", "two"), Stored ("c.txt", "three")];
      Inner : constant String := Zip_Of (Three);
   begin
      if Ada.Directories.Exists (Work_Dir) then
         Ada.Directories.Delete_Tree (Work_Dir);
      end if;
      Ada.Directories.Create_Path (Work_Dir);

      Expect ("plain.zip", Zip_Of (Three), 3, False, Ok, "a plain archive");
      Expect ("comment.zip", Zip_Of (Three, "PK" & Byte_Char (5) & Byte_Char (6) & " in a comment"),
              3, False, Ok, "an end signature in the comment is passed over");
      Expect
        ("nested.zip",
         Zip_Of
           ([Stored ("inner.zip", Inner),
             Stored ("chance.bin", "PK" & Byte_Char (1) & Byte_Char (2) & "PK" & Byte_Char (5) & Byte_Char (6))]),
         2, False, Ok, "a stored inner archive's records are the outer one's data");
      Expect ("zip64.zip", Zip64_Of (Three, 3), 3, False, Ok, "a ZIP64 count comes from the ZIP64 record");
      Expect ("stub.zip", String'(1 .. 100 => 'x') & Zip64_Of (Three, 3), 3, False, Ok,
              "a ZIP64 record right before its locator is found behind a stub");
      Expect ("huge.zip", Zip64_Of (Three, 2 ** 40), Natural'Last, True, Ok,
              "a count beyond Natural saturates and is capped");
      Expect ("broken.zip", "PK" & Byte_Char (3) & Byte_Char (4) & "no end record", 0, False, Invalid_Header,
              "no end record");

      declare
         Got        : Natural;
         Got_Capped : Boolean;
         Got_Status : Status_Code;
      begin
         Count_ZIP_File_Entries (Work_Dir & "/missing.zip", Got, Got_Capped, Got_Status);
         Assert (Got_Status = Input_File_Error and then Got = 0, "a missing file is Input_File_Error");
         Count_ZIP_File_Entries (Work_Dir, Got, Got_Capped, Got_Status);
         Assert (Got_Status = Input_File_Error, "a directory is Input_File_Error");
      end;
   end Test_Counts_From_End_Record;

   --  The extractor's listing recognises the same archives, and one whose
   --  ZIP64 count overflows Natural no longer raises.
   procedure Test_Listing_Uses_Same_Record (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Three  : constant Member_List :=
        [Stored ("a.txt", "one"), Stored ("b.txt", "two"), Stored ("c.txt", "three")];
      Path   : constant String := Work_Dir & "/listed.zip";
      Status : Status_Code;
   begin
      Ada.Directories.Create_Path (Work_Dir);
      Write (Path, Zip_Of (Three, "PK" & Byte_Char (5) & Byte_Char (6) & " in a comment"));
      declare
         Listed : constant Archive_Entry_Array := List_Archive_File_Entries (Path, "", Status);
      begin
         Assert (Status = Ok, "listing status " & Status_Code'Image (Status));
         Assert (Listed'Length = 3, "listing found" & Natural'Image (Listed'Length) & " members");
      end;
      Write (Path, Zip64_Of (Three, 2 ** 40));
      declare
         Listed : constant Archive_Entry_Array := List_Archive_File_Entries (Path, "", Status);
      begin
         Assert (Status /= Ok or else Listed'Length <= 3, "an overflowing ZIP64 count is not trusted");
      end;
   end Test_Listing_Uses_Same_Record;

   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("ZIP entry count");
   end Name;

   overriding procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Counts_From_End_Record'Access, "counts members from the end record");
      Register_Routine (T, Test_Listing_Uses_Same_Record'Access, "listing locates the same end record");
   end Register_Tests;

end Zlib_ZIP_Entry_Count_Tests;
