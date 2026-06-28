with Ada.Command_Line;
with Ada.Directories;
with Ada.Text_IO;

with GNAT.OS_Lib;

with Project_Tools.Processes;
with Project_Tools.Release_Checks;
with Project_Tools.Tree_Checks;

procedure Check_All is
   Root   : constant String := Ada.Directories.Full_Name (".");
   Alr    : constant String := Project_Tools.Processes.Locate_Command ("alr");
   Checks : constant Project_Tools.Release_Checks.Checker :=
     Project_Tools.Release_Checks.Create (Root);

   procedure Run
     (Label   : String;
      Dir     : String;
      Program : String;
      Args    : GNAT.OS_Lib.Argument_List;
      Quiet   : Boolean := False) renames Project_Tools.Release_Checks.Run;

begin
   Project_Tools.Processes.Require_Command
     ("alr", "alr executable not found on PATH");
   Project_Tools.Processes.Require_Command
     ("gprbuild", "gprbuild executable not found on PATH");
   Project_Tools.Processes.Require_Command
     ("gnatprove", "gnatprove executable not found on PATH");

   Project_Tools.Release_Checks.Require_File (Checks, "zlib.gpr");
   Project_Tools.Release_Checks.Require_File (Checks, "tests/tests.gpr");
   Project_Tools.Release_Checks.Require_File (Checks, "examples/examples.gpr");
   Project_Tools.Release_Checks.Require_File (Checks, "tools/tools.gpr");
   Project_Tools.Release_Checks.Require_File (Checks, "check_zlib/check_zlib.gpr");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "src/zlib.ads", "function Seven_Zip_Stored");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "src/zlib.ads", "function Seven_Zip_Deflate");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "src/zlib.ads", "function Seven_Zip_BZip2");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "src/zlib.ads", "function Seven_Zip_LZMA");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "src/zlib.ads", "function Seven_Zip_LZMA2");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "src/zlib.ads", "procedure Seven_Zip_Stored_File");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "src/zlib.ads", "procedure Seven_Zip_Deflate_File");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "src/zlib.ads", "procedure Seven_Zip_BZip2_File");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "src/zlib.ads", "procedure Seven_Zip_LZMA_File");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "src/zlib.ads", "procedure Seven_Zip_LZMA2_File");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "src/zlib.ads", "procedure Seven_Zip_Stored_Files");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "src/zlib.ads", "procedure Seven_Zip_Deflate_Files");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "src/zlib.ads", "procedure Seven_Zip_BZip2_Files");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "src/zlib.ads", "procedure Seven_Zip_LZMA_Files");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "src/zlib.ads", "procedure Seven_Zip_LZMA2_Files");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "src/zlib.ads", "procedure Seven_Zip_External_File");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "src/zlib.ads", "procedure Extract_Seven_Zip_External_File");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "src/zlib.ads", "Level       : Compression_Level");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "src/zlib.ads", "function Extract_Seven_Zip_Stored");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "src/zlib.ads", "function Extract_Seven_Zip");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "src/zlib.ads", "procedure Extract_Seven_Zip_Stored_File");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "src/zlib.ads", "procedure Extract_Seven_Zip_File");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "src/zlib.ads", "procedure Extract_Seven_Zip_Stored_Files");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "src/zlib.ads", "procedure Extract_Seven_Zip_Files");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "src/zlib.ads", "function Inflate_Auto");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "src/zlib.ads", "function GZip_Members");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "src/zlib.ads", "procedure GZip_File_Members");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "src/zlib.ads", "function ZIP");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "src/zlib.ads", "procedure ZIP_File");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "src/zlib.ads", "procedure ZIP_Files");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "README.md",
      "native stored, Deflate, BZip2, LZMA, and LZMA2 `.7z` output");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "docs/CONSTRAINTS.md",
      "native stored, Deflate, BZip2, LZMA, and LZMA2 `.7z` output");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "docs/API.md", "`Seven_Zip_Stored` emits a native `.7z` archive image");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "docs/API.md", "`Seven_Zip_Deflate` emits a native `.7z` archive image");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "docs/API.md", "`Compression_Mode` or `Compression_Level`");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "docs/API.md", "`Extract_Seven_Zip_Stored` verifies and extracts");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "docs/API.md", "`Seven_Zip_External_File` and");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "docs/API.md", "ZIP_External_Method_Name");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "README.md",
      "in-process BZip2, ZIP-LZMA, and Zstandard member-payload");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "docs/API.md",
      "method 14 ZIP-LZMA streams, and method 20/93 Zstandard");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_zip_external_codec_tests.adb",
      "ZIP Zstd payloads are created in-process");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_zip_external_codec_tests.adb",
      "ZIP Zstd payloads are extracted in-process");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_zip_external_codec_tests.adb",
      "ZIP legacy Zstd payloads are extracted in-process");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "docs/COMPRESSION.md",
      "Broader 7z creation and extraction is available only through");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "README.md", "opt-in external `.7z` creation/extraction");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb", "native stored 7z extracts its own Copy-coder archives");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb", "native Deflate 7z extracts its own Deflate archives");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb", "native Deflate 7z accepts compression levels");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native BZip2 7z extracts its own BZip2 archives");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native LZMA 7z extracts its own LZMA archives");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native LZMA 7z accepts non-default dictionary metadata");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native LZMA2 7z extracts its own LZMA2 archives");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native LZMA2 7z emits and extracts compressed LZMA2 chunks");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native single-entry 7z validates stored, Deflate, BZip2, LZMA, and");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb", "native stored 7z file-list helper extracts selected entries");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb", "native Deflate 7z file helpers roundtrip");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb", "native BZip2 7z file helpers roundtrip");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb", "native LZMA 7z file helpers roundtrip");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native Deflate level 7z file helpers roundtrip");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native compressed 7z file extraction rejects directory output path");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native compressed 7z file creation rejects directory output path");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z file creation prevalidates output paths");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z file creation prevalidates entry names");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z file extraction prevalidates output paths");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z file extraction prevalidates entry names");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb", "native Deflate 7z file-list helper writes multiple entries");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native BZip2 7z file-list helper writes multiple entries");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native LZMA 7z file-list helper writes multiple entries");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native LZMA2 7z file-list helper writes multiple entries");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native Deflate 7z extraction rejects corrupt compressed payloads");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native Deflate 7z extraction rejects trailing packed bytes");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native Deflate 7z extraction rejects bad unpack CRCs");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native Deflate 7z extraction rejects bad unpack sizes");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native BZip2 7z extraction rejects trailing packed bytes");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native BZip2/LZMA/LZMA2 7z extraction rejects bad packed CRCs");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native BZip2/LZMA2 7z extraction rejects corrupt payloads");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native BZip2/LZMA/LZMA2 7z extraction rejects bad unpack CRCs");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native BZip2/LZMA/LZMA2 7z extraction rejects bad unpack sizes");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native stored 7z extraction rejects missing header sections");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction accepts omitted optional CRC sections");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction accepts archive and file metadata");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction accepts SFX-prefixed archives");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction accepts directory entries");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction accepts known encoded header coders");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction accepts Copy encoded headers");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction accepts Deflate encoded headers");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction accepts BZip2 encoded headers");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction accepts LZMA encoded headers");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction accepts LZMA2 encoded headers");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction rejects bad encoded header CRCs");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction accepts solid Copy substreams");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction accepts solid Deflate substreams");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction accepts solid BZip2 substreams");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction accepts solid LZMA substreams");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction accepts solid LZMA2 substreams");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction accepts solid Delta substreams");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction accepts Delta+Deflate filter chains");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction accepts BCJ+Delta+Deflate filter chains");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction accepts Copy+Deflate filter chains");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction accepts solid PPMd substreams");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction accepts BCJ+Copy filter chains");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction accepts BCJ2+Copy filter graphs");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction accepts broader PPMd streams");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "src/zlib.adb", "Use_State_Blocks : Boolean := False");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "src/zlib.adb", "function PPMd_Has_State_Block");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "src/zlib.adb", "function PPMd_Ensure_State_Capacity");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "src/zlib.adb", "Use_State_Blocks => True");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction rejects malformed PPMd properties");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction rejects malformed PPMd range headers");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction recognizes valid PPMd range headers");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction accepts empty PPMd streams");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction accepts repeated PPMd streams");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction accepts short repeated PPMd streams");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction accepts long repeated PPMd streams");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction accepts over-boundary repeated PPMd streams");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction accepts alternating PPMd streams");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction accepts periodic PPMd streams");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction rejects periodic PPMd bad unpack CRCs");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction accepts two-symbol PPMd streams");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction accepts three-symbol PPMd streams");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction accepts six-symbol PPMd streams");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction accepts ten-symbol PPMd streams");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native 7z extraction accepts eleven-symbol PPMd streams");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native PPMd 7z file helper extracts supported streams");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native PPMd 7z file helper extracts eleven-symbol streams");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native PPMd 7z file helper extracts periodic streams");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native PPMd 7z file-list helper extracts supported streams");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native PPMd 7z file-list helper extracts eleven-symbol streams");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native PPMd 7z file-list helper extracts periodic streams");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native PPMd 7z file helpers reject periodic bad unpack CRCs");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native PPMd 7z file helpers reject malformed properties");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native stored 7z extraction rejects overflowing next-header offsets");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native stored 7z extraction rejects short CRC tables");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native stored 7z extraction rejects pack-size overflow");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native stored 7z extraction rejects impossible stream counts");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native stored 7z extraction rejects header count mismatches");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native stored 7z extraction rejects malformed name fields");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native LZMA 7z extraction rejects invalid coder properties");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native LZMA 7z extraction rejects trailing packed bytes");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native LZMA2 7z extraction rejects malformed coder properties");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native LZMA2 7z extraction rejects trailing packed bytes");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native stored 7z file-list helper roundtrips empty entries");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native compressed 7z file-list helper roundtrips empty entries");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native compressed 7z file-list extraction prevalidates output names");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native compressed 7z file-list extraction rejects output dirs");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native stored 7z file-list extraction prevalidates output names");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb", "native stored 7z file-list extraction stages before writing");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native stored 7z file-list extraction preflights output paths");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native stored 7z file-list extraction prevalidates output dir");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb", "native stored 7z file-list extraction rejects file output dir");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb", "native stored 7z file-list extraction rejects empty output dir");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb", "native stored 7z extraction rejects duplicate names");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb", "native stored 7z file-list rejects invalid array shapes");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native level Deflate 7z file-list rejects invalid inputs");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native level Deflate 7z file-list rejects output and prevalidates");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native BZip2/LZMA/LZMA2 7z file-list rejects invalid inputs");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "native stored 7z file-list creation rejects directory output path");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb", "native stored 7z file-list creation prevalidates entry names");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_seven_zip_tests.adb",
      "multi-file stored 7z creation preflights missing input files");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_release_contract_tests.adb", "external-style root 7z file-list API compiles");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_zip_external_codec_tests.adb",
      "external 7z bridge creates and extracts broad archives when available");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_zip_external_codec_tests.adb",
      "external 7z bridge preserves directories when available");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_zip_external_codec_tests.adb",
      "external 7z extraction reports output directory errors");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_zip_external_codec_tests.adb",
      "external 7z creation overwrites archives without stale entries");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_zip_external_codec_tests.adb",
      "external 7z bridge reports missing input method and password errors");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_zip_external_codec_tests.adb",
      "ZIP BZip2 payloads are created in-process");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_zip_external_codec_tests.adb",
      "ZIP BZip2 payloads are extracted in-process");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_zip_external_codec_tests.adb",
      "ZIP LZMA payloads are created in-process");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_zip_external_codec_tests.adb",
      "ZIP LZMA payloads are extracted in-process");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_zip_external_codec_tests.adb",
      "ZIP64 LZMA payloads are extracted in-process");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_zip_external_codec_tests.adb",
      "ZIP64 BZip2 payloads are extracted in-process");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_zip_external_codec_tests.adb",
      "ZIP64 Zstd payloads are extracted in-process");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_zip_external_codec_tests.adb",
      "ZIP64 legacy Zstd payloads are extracted in-process");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_zip_external_codec_tests.adb",
      "Zstandard ZIP method name");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "src/zlib.ads", "BZip2 ZIP creation and unencrypted extraction");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "src/zlib.ads", "ZIP-LZMA normal-distance");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_zip_external_codec_tests.adb",
      "native LZMA repeated payload uses match coding");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_zip_external_codec_tests.adb",
      "native LZMA small-distance payload uses match coding");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_zip_external_codec_tests.adb",
      "native LZMA pos-special payload uses match coding");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_zip_external_codec_tests.adb",
      "native LZMA direct-distance payload uses match coding");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_zip_external_codec_tests.adb",
      "native LZMA rep payload uses repeated-distance match coding");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_release_contract_tests.adb",
      "external-style root ZIP API compiles");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_release_contract_tests.adb",
      "ZIP_Files forced ZIP64 status");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_streaming_compress_dynamic_tests.adb",
      "streaming dynamic uses default lazy LZ77 level policy");
   Project_Tools.Release_Checks.Require_Text
     (Checks, "tests/src/zlib_deflate_dynamic_tests.adb",
      "Deflate_Dynamic large input uses block-local splitting");

   Run ("alr build", Root, Alr, [1 => new String'("build")]);
   Run
     ("zlib.gpr",
      Root,
      Alr,
      [new String'("exec"), new String'("--"), new String'("gprbuild"),
       new String'("-P"), new String'("zlib.gpr")]);
   Run
     ("zlib GNATprove",
      Root,
      Alr,
      [new String'("exec"), new String'("--"), new String'("gnatprove"),
       new String'("-P"), new String'("zlib.gpr"), new String'("--level=4")]);
   Run
     ("tests.gpr",
      Root & "/tests",
      Alr,
      [new String'("exec"), new String'("--"), new String'("gprbuild"),
       new String'("-P"), new String'("tests.gpr")]);
   Run ("AUnit tests", Root & "/tests", "./bin/tests", []);
   Run ("alr test", Root, Alr, [1 => new String'("test")]);
   Run
     ("examples.gpr",
      Root,
      Alr,
      [new String'("exec"), new String'("--"), new String'("gprbuild"),
       new String'("-P"), new String'("examples/examples.gpr")]);
   Run
     ("tools.gpr",
      Root,
      Alr,
      [new String'("exec"), new String'("--"), new String'("gprbuild"),
       new String'("-P"), new String'("tools/tools.gpr")]);
   Run ("check_zlib build", Root & "/check_zlib", Alr, [1 => new String'("build")]);
   Run ("check_zlib", Root & "/check_zlib", "./bin/check_zlib", []);
   Run ("smoke test", Root, "./tools/bin/smoke_test", []);

   Run
     ("fuzz inflate",
      Root,
      "./tools/bin/fuzz_inflate",
      [new String'("64"), new String'("63")]);
   Run
     ("fuzz streaming inflate",
      Root,
      "./tools/bin/fuzz_streaming_inflate",
      [new String'("64"), new String'("64")]);
   Run
     ("fuzz compress roundtrip",
      Root,
      "./tools/bin/fuzz_compress_roundtrip",
      [new String'("64"), new String'("65")]);
   Run
     ("fuzz compress levels",
      Root,
      "./tools/bin/fuzz_compress_levels",
      [new String'("64"), new String'("72")]);
   Run
     ("fuzz wrapper mix",
      Root,
      "./tools/bin/fuzz_wrapper_mix",
      [new String'("12"), new String'("634")]);
   Run
     ("fuzz dictionary",
      Root,
      "./tools/bin/fuzz_dictionary",
      [new String'("32"), new String'("67")]);
   Run
     ("fuzz gzip metadata",
      Root,
      "./tools/bin/fuzz_gzip_metadata",
      [new String'("32"), new String'("68")]);
   Run
     ("fuzz mutation",
      Root,
      "./tools/bin/fuzz_mutation",
      [new String'("64"), new String'("69")]);
   Run
     ("fuzz lifecycle",
      Root,
      "./tools/bin/fuzz_lifecycle",
      [new String'("16"), new String'("70")]);
   Run
     ("fuzz tiny buffers",
      Root,
      "./tools/bin/fuzz_tiny_buffers",
      [new String'("64"), new String'("71")]);

   Project_Tools.Tree_Checks.Require_No_Nonempty_Stderr (Root & "/obj");
   Project_Tools.Tree_Checks.Require_No_Nonempty_Stderr (Root & "/tests/obj");
   Project_Tools.Tree_Checks.Require_No_Nonempty_Stderr (Root & "/examples/obj");
   Project_Tools.Tree_Checks.Require_No_Nonempty_Stderr (Root & "/tools/obj");
   Project_Tools.Tree_Checks.Require_No_Nonempty_Stderr (Root & "/check_zlib/obj");

   Ada.Text_IO.Put_Line ("zlib release checklist passed");
exception
   when Program_Error =>
      Ada.Text_IO.Put_Line ("zlib release checklist failed");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Check_All;
