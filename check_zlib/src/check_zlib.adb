with Ada.Command_Line;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Ada.Strings.Unbounded;

with GNAT.OS_Lib;

with Project_Tools.Files;
with Project_Tools.Processes;
with Project_Tools.Text;

procedure Check_Zlib is
   use Ada.Text_IO;
   use GNAT.OS_Lib;

   Build_Args : constant Argument_List := (1 => new String'("build"));
   Test_Args : constant Argument_List := (1 => new String'("test"));
   Gnatprove_Args : constant Argument_List :=
     (1 => new String'("exec"),
      2 => new String'("--"),
      3 => new String'("gnatprove"),
      4 => new String'("-P"),
      5 => new String'("zlib.gpr"),
      6 => new String'("--level=4"));
   Gprbuild_Zlib_Args : constant Argument_List :=
     (1 => new String'("exec"), 2 => new String'("--"), 3 => new String'("gprbuild"),
      4 => new String'("-P"), 5 => new String'("zlib.gpr"));
   Gprbuild_Tests_Args : constant Argument_List :=
     (1 => new String'("exec"), 2 => new String'("--"), 3 => new String'("gprbuild"),
      4 => new String'("-P"), 5 => new String'("tests.gpr"));
   Gprbuild_Examples_Args : constant Argument_List :=
     (1 => new String'("exec"), 2 => new String'("--"), 3 => new String'("gprbuild"),
      4 => new String'("-P"), 5 => new String'("examples/examples.gpr"));
   Gprbuild_Tools_Args : constant Argument_List :=
     (1 => new String'("exec"), 2 => new String'("--"), 3 => new String'("gprbuild"),
      4 => new String'("-P"), 5 => new String'("tools/tools.gpr"));
   Tests_Run_Args : constant Argument_List :=
     (1 => new String'("exec"), 2 => new String'("--"), 3 => new String'("./bin/tests"));
   Smoke_Test_Args : constant Argument_List :=
     (1 => new String'("exec"), 2 => new String'("--"), 3 => new String'("./tools/bin/smoke_test"));

   function Root_Directory return String is
      Root : constant String :=
        Project_Tools.Files.Find_Root_Upward
          (Ada.Directories.Current_Directory, "zlib.gpr");
   begin
      if Root /= "" and then Ada.Directories.Exists (Root & "/docs/API.md") then
         return Root;
      else
         Put_Line
           (Standard_Error,
            "zlib root not found from " & Ada.Directories.Current_Directory);
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         raise Program_Error;
      end if;
   end Root_Directory;

   Root : constant String := Root_Directory;


   function Alr_Path return String is
   begin
      return Project_Tools.Processes.Locate_Command ("alr");
   end Alr_Path;

   procedure Run_Command (Label : String; Dir : String; Args : Argument_List) is
   begin
      Project_Tools.Processes.Run
        (Label   => Label,
         Dir     => Dir,
         Program => Alr_Path,
         Args    => Args);
   end Run_Command;

   procedure Require_Alire_GNAT_15 is
      Output : Ada.Strings.Unbounded.Unbounded_String;
   begin
      Project_Tools.Processes.Run
        (Label   => "GNAT 15 toolchain guard",
         Dir     => Root,
         Program => Alr_Path,
         Args    =>
           [new String'("exec"), new String'("--"), new String'("gnatls"),
            new String'("--version")],
         Output  => Output,
         Quiet   => True);

      if Ada.Strings.Fixed.Index
          (Ada.Strings.Unbounded.To_String (Output), "GNATLS 15.") = 0
      then
         Put_Line
           (Standard_Error,
            "wrong Ada compiler: zlib validation must run through Alire GNAT 15; got:");
         Put_Line (Standard_Error, Ada.Strings.Unbounded.To_String (Output));
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         raise Program_Error;
      end if;
   end Require_Alire_GNAT_15;

   procedure Require_Text (Relative_Path : String; Text : String) is
      Path : constant String := Root & "/" & Relative_Path;
   begin
      Project_Tools.Files.Require_Contains
        (Path,
         Text,
         "missing expected text in " & Relative_Path & ": " & Text,
         Quiet => False);
   end Require_Text;

   procedure Forbid_Text (Relative_Path : String; Text : String) is
      Path : constant String := Root & "/" & Relative_Path;
   begin
      if Project_Tools.Files.File_Contains (Path, Text) then
         Put_Line
           (Standard_Error,
            "forbidden text in " & Relative_Path & ": " & Text);
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         raise Program_Error;
      end if;
   end Forbid_Text;

   procedure Require_Checked_Example (Relative_Path : String) is
   begin
      Require_Text ("README.md", Relative_Path);
      Project_Tools.Files.Require_File
        (Root & "/" & Relative_Path,
         "documented checked example does not exist",
         Quiet => False);
   end Require_Checked_Example;

   procedure Require_All_Checked_Examples_Documented is
      Readme    : constant String := Project_Tools.Files.Read_Raw_File (Root & "/README.md");
      Search    : Ada.Directories.Search_Type;
      Dir_Entry : Ada.Directories.Directory_Entry_Type;
      Filter    : constant Ada.Directories.Filter_Type :=
        (Ada.Directories.Ordinary_File => True,
         Ada.Directories.Directory     => False,
         Ada.Directories.Special_File  => False);
   begin
      Ada.Directories.Start_Search
        (Search    => Search,
         Directory => Root & "/examples",
         Pattern   => "*.adb",
         Filter    => Filter);

      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Dir_Entry);

         declare
            Example_Name : constant String := Ada.Directories.Simple_Name (Dir_Entry);
         begin
            if not Project_Tools.Text.Contains (Readme, Example_Name) then
               Put_Line (Standard_Error, "checked example missing from README.md: " & Example_Name);
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               raise Program_Error;
            end if;
         end;
      end loop;

      Ada.Directories.End_Search (Search);
   exception
      when others =>
         Ada.Directories.End_Search (Search);
         raise;
   end Require_All_Checked_Examples_Documented;

   procedure Require_Support_Level_Markers is
      Search    : Ada.Directories.Search_Type;
      Dir_Entry : Ada.Directories.Directory_Entry_Type;
      Filter    : constant Ada.Directories.Filter_Type :=
        (Ada.Directories.Ordinary_File => True,
         Ada.Directories.Directory     => False,
         Ada.Directories.Special_File  => False);
   begin
      Project_Tools.Files.Require_Contains
        (Root & "/src/zlib.ads",
         "Support level: stable production API.",
         "root public spec must document support level",
         Quiet => False);

      Ada.Directories.Start_Search
        (Search    => Search,
         Directory => Root & "/src",
         Pattern   => "zlib-*.ads",
         Filter    => Filter);

      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Dir_Entry);

         declare
            Path : constant String := Ada.Directories.Full_Name (Dir_Entry);
         begin
            Project_Tools.Files.Require_Contains
              (Path,
               "Support level: private internal implementation.",
               "internal child spec must document support level",
               Quiet => False);
         end;
      end loop;

      Ada.Directories.End_Search (Search);
   exception
      when others =>
         Ada.Directories.End_Search (Search);
         raise;
   end Require_Support_Level_Markers;

begin
   Require_Alire_GNAT_15;

   Project_Tools.Files.Require_Files
     ([Ada.Strings.Unbounded.To_Unbounded_String (Root & "/README.md"),
       Ada.Strings.Unbounded.To_Unbounded_String (Root & "/LICENSE"),
       Ada.Strings.Unbounded.To_Unbounded_String (Root & "/alire.toml"),
       Ada.Strings.Unbounded.To_Unbounded_String (Root & "/zlib.gpr"),
       Ada.Strings.Unbounded.To_Unbounded_String (Root & "/docs/API.md"),
       Ada.Strings.Unbounded.To_Unbounded_String (Root & "/docs/TESTING.md"),
       Ada.Strings.Unbounded.To_Unbounded_String (Root & "/docs/SPARK.md"),
       Ada.Strings.Unbounded.To_Unbounded_String (Root & "/tools/check_all.adb")],
      "required zlib release file missing",
      Quiet => False);

   Require_Text ("README.md", "docs/API.md");
   Require_Text ("README.md", "docs/TESTING.md");
   Require_Text ("README.md", "examples/quickstart.adb");
   Require_Text ("README.md", "tools/bin/check_all");
   Require_Text ("README.md", "docs/SPARK.md");
   Require_Text ("README.md", "alr exec -- gnatprove -P zlib.gpr --level=4");
   Require_Text ("README.md", "alr test");
   Require_Text ("README.md", "check_zlib");
   Require_Text ("README.md", "with Zlib;");
   Require_Text ("README.md", "No runtime fixture generation or system");
   Require_Text ("README.md", "GNAT 15");
   Require_Text ("alire.toml", "gnat_native = ""^15""");
   Require_Text ("tests/alire.toml", "gnat_native = ""^15""");
   Require_Text ("check_zlib/alire.toml", "gnat_native = ""^15""");

   Require_Text ("docs/API.md", "The root package `Zlib` is the public API entry point");
   Require_Text ("docs/API.md", "Inflate_With_Header");
   Require_Text ("docs/API.md", "Deflate_Raw");
   Require_Text ("docs/API.md", "Deflate_Bound");
   Require_Text ("docs/API.md", "GZip_Bound");
   Require_Text ("docs/API.md", "Deflate_Raw_Bound");
   Require_Text ("docs/API.md", "CryptoLib.Checksums");
   Require_Text ("src/zlib.adb", "CryptoLib.Checksums.Adler32_Update");
   Require_Text ("src/zlib.adb", "CryptoLib.Checksums.CRC32_Update");
   Require_Text ("src/zlib-stream_inflate.ads", "CryptoLib.Checksums.Adler32_State");
   Require_Text ("src/zlib-stream_inflate.ads", "CryptoLib.Checksums.CRC32_State");
   Forbid_Text ("src/zlib.ads", "Adler32_Update");
   Forbid_Text ("src/zlib.ads", "function Adler32");
   Forbid_Text ("src/zlib.ads", "CRC32_Update");
   Forbid_Text ("src/zlib.ads", "function CRC32");
   Require_Text ("src/zlib.ads", "Deflate_Bound");
   Require_Text ("src/zlib.ads", "GZip_Bound");
   Require_Text ("src/zlib.ads", "Deflate_Raw_Bound");
   Require_Text ("docs/API.md", "Deflate_Raw_File_To_Stream");
   Require_Text ("docs/API.md", "Deflate_Raw_File_Size");
   Require_Text ("src/zlib.ads", "Deflate_Raw_File_To_Stream");
   Require_Text ("src/zlib.ads", "Deflate_Raw_File_Size");
   Require_Text ("docs/API.md", "Raw_Deflate");
   Require_Text ("docs/API.md", "GZip_Metadata");
   Require_Text ("docs/API.md", "Header => Default` perform lightweight wrapper auto-detection");
   Require_Text ("docs/API.md", "implementation units and may change without a public API bump");

   Require_Text ("docs/TESTING.md", "check_zlib");
   Require_Text ("docs/TESTING.md", "alr exec -- gnatprove -P zlib.gpr --level=4");
   Require_Text ("docs/SPARK.md", "Status_Image");
   Require_Text ("docs/SPARK.md", "Looks_Like_Zlib_Header");
   Require_Text ("docs/TESTING.md", "Documentation is part of the release surface");
   Require_Text ("tools/check_all.adb", "check_zlib");
   Require_Text ("tools/tools.gpr", "project_tools.gpr");
   Require_Text ("tests/alire.toml", "project_tools");
   Require_Text ("alire.toml", "type = ""test""");

   Require_Checked_Example ("examples/quickstart.adb");
   Require_Checked_Example ("examples/streaming_deflate_zlib.adb");
   Require_Checked_Example ("examples/streaming_deflate_raw.adb");
   Require_Checked_Example ("examples/deflate_raw_file_to_stream.adb");
   Require_Checked_Example ("examples/gzip_with_metadata.adb");
   Require_Checked_Example ("examples/dictionary_roundtrip.adb");
   Require_All_Checked_Examples_Documented;
   Require_Support_Level_Markers;

   Project_Tools.Processes.Require_Command ("alr", "alr executable not found on PATH");
   Project_Tools.Processes.Require_Command ("gnatprove", "gnatprove executable not found on PATH");

   Run_Command ("alr build", Root, Build_Args);
   Run_Command ("zlib.gpr", Root, Gprbuild_Zlib_Args);
   Run_Command ("zlib GNATprove", Root, Gnatprove_Args);
   Run_Command ("tests.gpr", Root & "/tests", Gprbuild_Tests_Args);
   Run_Command ("AUnit tests", Root & "/tests", Tests_Run_Args);
   Run_Command ("alr test", Root, Test_Args);
   Run_Command ("examples.gpr", Root, Gprbuild_Examples_Args);
   Run_Command ("tools.gpr", Root, Gprbuild_Tools_Args);
   Run_Command ("smoke test", Root, Smoke_Test_Args);

   Put_Line ("zlib release check passed.");
exception
   when Program_Error =>
      null;
end Check_Zlib;
