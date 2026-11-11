with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;
with Zlib.Native_Files;
with Zlib.Windows_Paths;

--  Archives written and extracted more than 300 characters deep. GNAT's
--  Windows runtime refuses any path past 260 characters before Windows is
--  asked, so these run the crate's own file layer (Zlib.Native_Files) on every
--  host: on Windows through the \\?\ long form, elsewhere through the Ada
--  libraries, which must answer the same.
package body Zlib_Long_Path_Tests is
   package SIO renames Ada.Streams.Stream_IO;
   package US renames Ada.Strings.Unbounded;
   package NF renames Zlib.Native_Files;
   package WP renames Zlib.Windows_Paths;

   use type Zlib.Status_Code;
   use type NF.File_Kind;
   use type NF.File_Size;

   Content : constant String := "a member that lives more than 300 characters deep";

   Long_A : constant String := Ada.Strings.Fixed."*" (150, 'a');
   Long_B : constant String := Ada.Strings.Fixed."*" (150, 'b');

   --  Absolute, so that on Windows the long form applies: a relative path is
   --  never given the \\?\ prefix.
   function Work_Root return String is
     (Ada.Directories.Current_Directory & "/zlib_long_path_work");

   procedure Remove_Work is
   begin
      if NF.Exists (Work_Root) then
         NF.Delete_Tree (Work_Root);
      end if;
   end Remove_Work;

   procedure Write_Text (Path : String; Text : String) is
      File : SIO.File_Type;
   begin
      NF.Create (File, SIO.Out_File, Path);
      String'Write (SIO.Stream (File), Text);
      SIO.Close (File);
   end Write_Text;

   function Read_Text (Path : String) return String is
      File : SIO.File_Type;
   begin
      NF.Open (File, SIO.In_File, Path);
      declare
         Result : String (1 .. Natural (SIO.Size (File)));
      begin
         String'Read (SIO.Stream (File), Result);
         SIO.Close (File);
         return Result;
      end;
   end Read_Text;

   procedure Test_Long_Path_Form (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Tail : constant String := Ada.Strings.Fixed."*" (300, 'x');
   begin
      Assert (WP.Long_Path_Form ("C:\short") = "C:\short", "a short path must stay as given");
      Assert (WP.Long_Path_Form ("C:\" & Ada.Strings.Fixed."*" (244, 'x')) = "C:\" & Ada.Strings.Fixed."*" (244, 'x'),
              "a path of 247 characters must stay as given");
      Assert (WP.Long_Path_Form ("C:\" & Ada.Strings.Fixed."*" (245, 'x'))
                = "\\?\C:\" & Ada.Strings.Fixed."*" (245, 'x'),
              "a drive path of 248 characters must take the long form");
      Assert (WP.Long_Path_Form ("C:/dir/" & Tail) = "\\?\C:\dir\" & Tail,
              "a long drive path must take the long form with backslashes");
      Assert (WP.Long_Path_Form ("\\server\share\" & Tail) = "\\?\UNC\server\share\" & Tail,
              "a long share path must take the UNC long form");
      Assert (WP.Long_Path_Form ("relative\" & Tail) = "relative\" & Tail,
              "a long relative path must stay as given");
      Assert (WP.Long_Path_Form ("C:\dir\..\" & Tail) = "C:\dir\..\" & Tail,
              "a long path with a dot-dot component must stay as given");
      Assert (WP.Long_Path_Form ("\\?\C:\" & Tail) = "\\?\C:\" & Tail,
              "an already prefixed path must stay as given");
      Assert (WP.Long_Path_Form ("/home/" & Tail) = "/home/" & Tail,
              "a long POSIX path must stay as given");
   end Test_Long_Path_Form;

   procedure Test_Round_Trip (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Work   : constant String := Work_Root;
      Deep   : constant String := Work & "/" & Long_A & "/" & Long_B;
      Input  : constant String := Deep & "/input.txt";
      Member : constant String := "dir/input.txt";
      Status : Zlib.Status_Code := Zlib.Invalid_Header;
   begin
      Remove_Work;

      --  Short directories first, then renamed to 150-character names, so the
      --  deep directory exists before anything under test has to reach it.
      NF.Create_Path (Work & "/a/b");
      NF.Rename (Work & "/a", Work & "/" & Long_A);
      NF.Rename (Work & "/" & Long_A & "/b", Deep);
      Assert (Deep'Length > 300, "the work directory must lie more than 300 characters deep");
      Assert (NF.Kind (Deep) = NF.Directory, "the renamed deep directory is missing");

      Write_Text (Input, Content);
      Assert (NF.Kind (Input) = NF.Ordinary_File, "the deep input file is missing");
      Assert (NF.Size (Input) = NF.File_Size (Content'Length), "the deep input file has the wrong size");

      --  ZIP: written by ZIP_Files, streamed back out by the directory extractor.
      Zlib.ZIP_Files
        (Input_Paths => [US.To_Unbounded_String (Input)],
         Output_Path => Deep & "/archive.zip",
         Entry_Names => [US.To_Unbounded_String (Member)],
         Status      => Status);
      Assert (Status = Zlib.Ok, "ZIP_Files at a long path: " & Status'Image);
      Zlib.Extract_Archive_File_To_Directory (Deep & "/archive.zip", Deep & "/zip_out", "", Status);
      Assert (Status = Zlib.Ok, "ZIP extraction at a long path: " & Status'Image);
      Assert (Read_Text (Deep & "/zip_out/" & Member) = Content, "the ZIP member came back changed");

      declare
         Listed : constant NF.Directory_Entries := NF.List_Directory (Deep & "/zip_out/dir");
      begin
         Assert (Listed'Length = 1, "the extracted ZIP directory should hold one entry");
         Assert (US.To_String (Listed (Listed'First).Name) = "input.txt"
                   and then Listed (Listed'First).Kind = NF.Ordinary_File,
                 "the extracted ZIP directory should list input.txt as a file");
      end;

      --  7z: written by Seven_Zip_Deflate_Files, catalogued, then extracted.
      Zlib.Seven_Zip_Deflate_Files
        (Input_Paths => [US.To_Unbounded_String (Input)],
         Output_Path => Deep & "/archive.7z",
         Entry_Names => [US.To_Unbounded_String (Member)],
         Status      => Status);
      Assert (Status = Zlib.Ok, "Seven_Zip_Deflate_Files at a long path: " & Status'Image);

      declare
         Entries : constant Zlib.Archive_Entry_Array :=
           Zlib.List_Archive_File_Entries (Deep & "/archive.7z", "", Status);
      begin
         Assert (Status = Zlib.Ok, "listing a 7z at a long path: " & Status'Image);
         Assert (Entries'Length = 1 and then US.To_String (Entries (Entries'First).Name) = Member,
                 "the 7z at a long path should list its one member");
      end;

      Zlib.Extract_Archive_File_To_Directory (Deep & "/archive.7z", Deep & "/seven_zip_out", "", Status);
      Assert (Status = Zlib.Ok, "7z extraction at a long path: " & Status'Image);
      Assert (Read_Text (Deep & "/seven_zip_out/" & Member) = Content, "the 7z member came back changed");

      NF.Delete_File (Deep & "/archive.zip");
      Assert (not NF.Exists (Deep & "/archive.zip"), "a deep file should be deletable");

      Remove_Work;
      Assert (not NF.Exists (Work), "the deep work tree should be removable");
   exception
      when others =>
         Remove_Work;
         raise;
   end Test_Round_Trip;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib long paths");
   end Name;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Long_Path_Form'Access,
         "Windows long-path form prefixes only long absolute paths");
      Register_Routine
        (T, Test_Round_Trip'Access,
         "zip and 7z archives round-trip more than 300 characters deep");
   end Register_Tests;

end Zlib_Long_Path_Tests;
