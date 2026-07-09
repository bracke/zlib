with Ada.Command_Line;
with Ada.Directories;
with Ada.Exceptions;
with Interfaces;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with GNAT.OS_Lib;
with Project_Tools.Processes;
with Zlib;
with Zlib_Tool_Support;

procedure Seven_Zip_Interop_Check is
   use type Zlib.Byte_Array;
   use type Zlib.Status_Code;
   use type Ada.Directories.File_Kind;
   use type Interfaces.Unsigned_64;

   Root       : constant String := Ada.Directories.Full_Name (".");
   Seven_Zip  : constant String := Project_Tools.Processes.Locate_Command ("7z");
   Work_Root  : constant String := Root & "/tools/obj/seven_zip_interop";
   Entry_Name : constant String := "payload.bin";
   Password   : constant String := "interop-secret";

   package US renames Ada.Strings.Unbounded;

   Failures : Natural := 0;
   Checks   : Natural := 0;
   Skips    : Natural := 0;

   type Archive_Method is (Copy_Method, Deflate_Method, BZip2_Method, LZMA_Method, LZMA2_Method, PPMd_Method);
   type Filter_Case is (BCJ_LZMA, Delta_LZMA, RISCV_LZMA);
   type Corpus_Case is (Empty_Corpus, Code_Corpus, Text_Corpus, Large_Corpus);
   type Solid_Method is (Solid_LZMA, Solid_LZMA2, Solid_PPMd);

   function Method_Name (Method : Archive_Method) return String is
   begin
      case Method is
         when Copy_Method =>
            return "Copy";
         when Deflate_Method =>
            return "Deflate";
         when BZip2_Method =>
            return "BZip2";
         when LZMA_Method =>
            return "LZMA";
         when LZMA2_Method =>
            return "LZMA2";
         when PPMd_Method =>
            return "PPMd";
      end case;
   end Method_Name;

   function Filter_Name (Case_Name : Filter_Case) return String is
   begin
      case Case_Name is
         when BCJ_LZMA =>
            return "BCJ_LZMA";
         when Delta_LZMA =>
            return "Delta_LZMA";
         when RISCV_LZMA =>
            return "RISCV_LZMA";
      end case;
   end Filter_Name;

   function Solid_Name (Method : Solid_Method) return String is
   begin
      case Method is
         when Solid_LZMA =>
            return "LZMA";
         when Solid_LZMA2 =>
            return "LZMA2";
         when Solid_PPMd =>
            return "PPMd";
      end case;
   end Solid_Name;

   function Corpus_Name (Case_Name : Corpus_Case) return String is
   begin
      case Case_Name is
         when Empty_Corpus =>
            return "empty";
         when Code_Corpus =>
            return "code";
         when Text_Corpus =>
            return "text";
         when Large_Corpus =>
            return "large";
      end case;
   end Corpus_Name;

   function Corpus_Length (Case_Name : Corpus_Case) return Natural is
   begin
      case Case_Name is
         when Empty_Corpus =>
            return 0;
         when Code_Corpus =>
            return 2048;
         when Text_Corpus =>
            return 8192;
         when Large_Corpus =>
            return 65536;
      end case;
   end Corpus_Length;

   function Payload (Case_Name : Corpus_Case) return Zlib.Byte_Array is
      Result : Zlib.Byte_Array (1 .. Corpus_Length (Case_Name));
   begin
      for Index in Result'Range loop
         case Case_Name is
            when Empty_Corpus =>
               null;
            when Code_Corpus =>
               if Index mod 32 in 1 .. 5 then
                  Result (Index) := Zlib.Byte (16#90# + (Index mod 3));
               elsif Index mod 17 = 0 then
                  Result (Index) := Zlib.Byte (Character'Pos (ASCII.LF));
               else
                  Result (Index) := Zlib.Byte ((Index * 37 + Index / 3) mod 256);
               end if;
            when Text_Corpus =>
               declare
                  Pattern : constant String := "Ada zlib seven zip interop corpus line ";
                  Pos     : constant Positive := ((Index - Result'First) mod Pattern'Length) + Pattern'First;
               begin
                  Result (Index) := Zlib.Byte (Character'Pos (Pattern (Pos)));
               end;
            when Large_Corpus =>
               if Index mod 257 = 0 then
                  Result (Index) := Zlib.Byte (Index mod 251);
               else
                  Result (Index) := Zlib.Byte ((Index * 41 + Index / 3 + (Index mod 29) * 7) mod 256);
               end if;
         end case;
      end loop;

      --  Make the first bytes look like x86 code so BCJ transforms non-trivially.
      if Case_Name = Code_Corpus then
         Result (1) := 16#E8#;
         Result (2) := 16#03#;
         Result (3) := 16#00#;
         Result (4) := 16#00#;
         Result (5) := 16#00#;
         Result (6) := 16#C3#;
      end if;

      return Result;
   end Payload;

   function RISCV_Payload return Zlib.Byte_Array is
      Result : Zlib.Byte_Array := Payload (Code_Corpus);
   begin
      if Result'Length >= 16 then
         --  RISC-V JAL x0, 0 at offset 4; the filter rewrites a non-zero
         --  absolute target during encoding.
         Result (Result'First + 0) := 16#13#;
         Result (Result'First + 1) := 16#00#;
         Result (Result'First + 2) := 16#00#;
         Result (Result'First + 3) := 16#00#;
         Result (Result'First + 4) := 16#6F#;
         Result (Result'First + 5) := 16#00#;
         Result (Result'First + 6) := 16#00#;
         Result (Result'First + 7) := 16#00#;
         Result (Result'First + 8) := 16#13#;
         Result (Result'First + 9) := 16#00#;
         Result (Result'First + 10) := 16#00#;
         Result (Result'First + 11) := 16#00#;
         Result (Result'First + 12) := 16#6F#;
         Result (Result'First + 13) := 16#00#;
         Result (Result'First + 14) := 16#00#;
         Result (Result'First + 15) := 16#00#;
      end if;

      return Result;
   end RISCV_Payload;

   procedure Fail (Message : String) is
   begin
      Ada.Text_IO.Put_Line ("FAIL: " & Message);
      Failures := Failures + 1;
   end Fail;

   procedure Note_Check is
   begin
      Checks := Checks + 1;
   end Note_Check;

   procedure Skip (Message : String) is
   begin
      Ada.Text_IO.Put_Line ("SKIP: " & Message);
      Skips := Skips + 1;
   end Skip;

   procedure Check_Status
     (Status  : Zlib.Status_Code;
      Message : String)
   is
   begin
      if Status /= Zlib.Ok then
         Fail (Message & ": " & Zlib.Status_Image (Status));
      end if;
   end Check_Status;

   procedure Ensure_Clean_Directory (Path : String) is
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_Tree (Path);
      end if;

      Ada.Directories.Create_Path (Path);
   end Ensure_Clean_Directory;

   procedure Write_Payload
     (Path : String;
      Data : Zlib.Byte_Array)
   is
      Status : Zlib.Status_Code;
   begin
      Zlib_Tool_Support.Write_File (Path, Data, Status);
      Check_Status (Status, "write payload " & Path);
   end Write_Payload;

   function Same_File
     (Left_Path  : String;
      Right_Path : String) return Boolean
   is
      Left_Status  : Zlib.Status_Code;
      Right_Status : Zlib.Status_Code;
      Left_Data    : constant Zlib.Byte_Array := Zlib_Tool_Support.Read_File (Left_Path, Left_Status);
      Right_Data   : constant Zlib.Byte_Array := Zlib_Tool_Support.Read_File (Right_Path, Right_Status);
   begin
      Check_Status (Left_Status, "read " & Left_Path);
      Check_Status (Right_Status, "read " & Right_Path);
      return Left_Status = Zlib.Ok and then Right_Status = Zlib.Ok and then Left_Data = Right_Data;
   end Same_File;

   procedure Run_7z
     (Label : String;
      Dir   : String;
      Args  : GNAT.OS_Lib.Argument_List)
   is
      Code : constant Integer := Project_Tools.Processes.Run_Status (Label, Dir, Seven_Zip, Args, Quiet => True);
   begin
      Note_Check;
      if Code /= 0 then
         Fail (Label & " exited with status" & Integer'Image (Code));
      end if;
   end Run_7z;

   function Seven_Zip_Supports_RISCV return Boolean is
      Case_Dir     : constant String := Work_Root & "/probe_RISCV";
      Source_Path  : constant String := Case_Dir & "/" & Entry_Name;
      Archive_Path : constant String := Case_Dir & "/probe.7z";
      Code         : Integer;
   begin
      Ensure_Clean_Directory (Case_Dir);
      Write_Payload (Source_Path, RISCV_Payload);
      Code :=
        Project_Tools.Processes.Run_Status
          ("7z probe RISCV", Case_Dir, Seven_Zip,
           [new String'("a"), new String'("-t7z"), new String'("-m0=RISCV"),
            new String'("-m1=LZMA"), new String'(Archive_Path),
            new String'(Entry_Name)],
           Quiet => True);
      return Code = 0;
   end Seven_Zip_Supports_RISCV;

   procedure Check_Directory
     (Path    : String;
      Message : String)
   is
   begin
      if not Ada.Directories.Exists (Path) then
         Fail (Message & " missing");
      elsif Ada.Directories.Kind (Path) /= Ada.Directories.Directory then
         Fail (Message & " is not a directory");
      end if;
   end Check_Directory;

   procedure Check_Single_Entry_List
     (Archive_Path   : String;
      Password_Value : String;
      Expected_Name  : String;
      Expected_Size  : Natural;
      Message        : String)
   is
      Read_Status : Zlib.Status_Code;
      List_Status : Zlib.Status_Code;
      Archive     : constant Zlib.Byte_Array := Zlib_Tool_Support.Read_File (Archive_Path, Read_Status);
      Entries     : constant Zlib.Archive_Entry_Array :=
        Zlib.List_Archive_Entries (Archive, Password_Value, List_Status);
   begin
      Note_Check;
      Check_Status (Read_Status, "read archive for listing " & Archive_Path);
      Check_Status (List_Status, "list " & Message);
      if Read_Status = Zlib.Ok and then List_Status = Zlib.Ok then
         if Entries'Length /= 1 then
            Fail (Message & " listed" & Integer'Image (Entries'Length) & " entries");
         elsif US.To_String (Entries (Entries'First).Name) /= Expected_Name then
            Fail (Message & " listed unexpected entry name");
         elsif Entries (Entries'First).Is_Directory then
            Fail (Message & " listed payload as directory");
         elsif Entries (Entries'First).Uncompressed_Size /= Interfaces.Unsigned_64 (Expected_Size) then
            Fail (Message & " listed unexpected payload size");
         end if;
      end if;
   end Check_Single_Entry_List;

   procedure Check_List_Fails
     (Archive_Path   : String;
      Password_Value : String;
      Message        : String)
   is
      Read_Status : Zlib.Status_Code;
      List_Status : Zlib.Status_Code;
      Archive     : constant Zlib.Byte_Array := Zlib_Tool_Support.Read_File (Archive_Path, Read_Status);
      Entries     : constant Zlib.Archive_Entry_Array :=
        Zlib.List_Archive_Entries (Archive, Password_Value, List_Status);
   begin
      Note_Check;
      Check_Status (Read_Status, "read archive for negative listing " & Archive_Path);
      if Read_Status = Zlib.Ok and then List_Status = Zlib.Ok then
         Fail (Message & " unexpectedly listed" & Integer'Image (Entries'Length) & " entries");
      end if;
   end Check_List_Fails;

   procedure Check_Extract_Fails
     (Archive_Path   : String;
      Entry_Name_In : String;
      Password_Value : String;
      Message        : String)
   is
      Read_Status    : Zlib.Status_Code;
      Extract_Status : Zlib.Status_Code;
      Archive        : constant Zlib.Byte_Array := Zlib_Tool_Support.Read_File (Archive_Path, Read_Status);
      Output         : constant Zlib.Byte_Array :=
        Zlib.Extract_Seven_Zip (Archive, Entry_Name_In, Password_Value, Extract_Status);
   begin
      Note_Check;
      Check_Status (Read_Status, "read archive for negative extraction " & Archive_Path);
      if Read_Status = Zlib.Ok and then Extract_Status = Zlib.Ok then
         Fail (Message & " unexpectedly extracted" & Integer'Image (Output'Length) & " bytes");
      end if;
   end Check_Extract_Fails;

   procedure Write_Archive
     (Method       : Archive_Method;
      Source_Path  : String;
      Archive_Path : String)
   is
      Status : Zlib.Status_Code;
   begin
      Note_Check;
      case Method is
         when Copy_Method =>
            Zlib.Seven_Zip_Stored_File (Source_Path, Archive_Path, Entry_Name, Status);
         when Deflate_Method =>
            Zlib.Seven_Zip_Deflate_File (Source_Path, Archive_Path, Entry_Name, Status);
         when BZip2_Method =>
            Zlib.Seven_Zip_BZip2_File (Source_Path, Archive_Path, Entry_Name, Status);
         when LZMA_Method =>
            Zlib.Seven_Zip_LZMA_File (Source_Path, Archive_Path, Entry_Name, Status);
         when LZMA2_Method =>
            Zlib.Seven_Zip_LZMA2_File (Source_Path, Archive_Path, Entry_Name, Status);
         when PPMd_Method =>
            Zlib.Seven_Zip_PPMd_File (Source_Path, Archive_Path, Entry_Name, Status);
      end case;

      Check_Status (Status, "write native " & Method_Name (Method) & " archive");
   end Write_Archive;

   procedure Check_Our_To_7z
     (Method : Archive_Method;
      Corpus : Corpus_Case;
      Data   : Zlib.Byte_Array)
   is
      Case_Dir     : constant String := Work_Root & "/our_to_7z_" & Method_Name (Method) & "_" &
        Corpus_Name (Corpus);
      Source_Path  : constant String := Case_Dir & "/" & Entry_Name;
      Archive_Path : constant String := Case_Dir & "/native.7z";
      Extract_Dir  : constant String := Case_Dir & "/extract";
   begin
      Note_Check;
      Ensure_Clean_Directory (Case_Dir);
      Ada.Directories.Create_Path (Extract_Dir);
      Write_Payload (Source_Path, Data);
      Write_Archive (Method, Source_Path, Archive_Path);
      Run_7z
        ("7z extract native " & Method_Name (Method), Extract_Dir,
         [new String'("x"), new String'("-y"), new String'("-aoa"), new String'("-o" & Extract_Dir),
          new String'(Archive_Path)]);

      if not Same_File (Source_Path, Extract_Dir & "/" & Entry_Name) then
         Fail ("native " & Method_Name (Method) & " archive did not match after 7z extraction");
      end if;
   end Check_Our_To_7z;

   procedure Check_7z_To_Our
     (Method : Archive_Method;
      Corpus : Corpus_Case;
      Data   : Zlib.Byte_Array)
   is
      Case_Dir     : constant String := Work_Root & "/seven_to_our_" & Method_Name (Method) & "_" &
        Corpus_Name (Corpus);
      Source_Path  : constant String := Case_Dir & "/" & Entry_Name;
      Archive_Path : constant String := Case_Dir & "/stock.7z";
      Output_Path  : constant String := Case_Dir & "/output.bin";
      Status       : Zlib.Status_Code;
   begin
      Note_Check;
      Ensure_Clean_Directory (Case_Dir);
      Write_Payload (Source_Path, Data);
      Run_7z
        ("7z create " & Method_Name (Method), Case_Dir,
         [new String'("a"), new String'("-t7z"), new String'("-m0=" & Method_Name (Method)),
          new String'(Archive_Path), new String'(Entry_Name)]);

      Zlib.Extract_Seven_Zip_File (Archive_Path, Output_Path, Entry_Name, Status);
      Check_Status (Status, "extract stock " & Method_Name (Method) & " archive");

      if not Same_File (Source_Path, Output_Path) then
         Fail ("stock " & Method_Name (Method) & " archive did not match after native extraction");
      end if;
   end Check_7z_To_Our;

   procedure Write_Filtered_Archive
     (Case_Name    : Filter_Case;
      Data         : Zlib.Byte_Array;
      Archive_Path : String)
   is
      Status       : Zlib.Status_Code;
         Archive_Data : Zlib.Byte_Array :=
        (case Case_Name is
            when BCJ_LZMA =>
               Zlib.Seven_Zip_Filtered
                 (Data, Entry_Name, Zlib.Seven_Zip_Filter_X86_BCJ, Zlib.Seven_Zip_Codec_LZMA, Status),
            when Delta_LZMA =>
               Zlib.Seven_Zip_Filtered
                 (Data, Entry_Name, Zlib.Seven_Zip_Filter_Delta, Zlib.Seven_Zip_Codec_LZMA, Status),
            when RISCV_LZMA =>
               Zlib.Seven_Zip_Filtered
                 (Data, Entry_Name, Zlib.Seven_Zip_Filter_RISCV_BCJ, Zlib.Seven_Zip_Codec_LZMA, Status));
   begin
      Note_Check;
      Check_Status (Status, "write native filtered " & Filter_Name (Case_Name) & " archive");
      if Status = Zlib.Ok then
         Zlib_Tool_Support.Write_File (Archive_Path, Archive_Data, Status);
         Check_Status (Status, "write filtered archive " & Archive_Path);
      end if;
   end Write_Filtered_Archive;

   procedure Check_Filter_Our_To_7z
     (Case_Name : Filter_Case;
      Corpus    : Corpus_Case;
      Data      : Zlib.Byte_Array)
   is
      Case_Dir     : constant String := Work_Root & "/our_to_7z_" & Filter_Name (Case_Name) & "_" &
        Corpus_Name (Corpus);
      Source_Path  : constant String := Case_Dir & "/" & Entry_Name;
      Archive_Path : constant String := Case_Dir & "/native.7z";
      Extract_Dir  : constant String := Case_Dir & "/extract";
   begin
      Note_Check;
      Ensure_Clean_Directory (Case_Dir);
      Ada.Directories.Create_Path (Extract_Dir);
      Write_Payload (Source_Path, Data);
      Write_Filtered_Archive (Case_Name, Data, Archive_Path);
      Run_7z
        ("7z extract native filtered " & Filter_Name (Case_Name), Extract_Dir,
         [new String'("x"), new String'("-y"), new String'("-aoa"), new String'("-o" & Extract_Dir),
          new String'(Archive_Path)]);

      if not Same_File (Source_Path, Extract_Dir & "/" & Entry_Name) then
         Fail ("native filtered " & Filter_Name (Case_Name) & " archive did not match after 7z extraction");
      end if;
   end Check_Filter_Our_To_7z;

   procedure Check_Filter_7z_To_Our
     (Case_Name : Filter_Case;
      Corpus    : Corpus_Case;
      Data      : Zlib.Byte_Array)
   is
      Case_Dir     : constant String := Work_Root & "/seven_to_our_" & Filter_Name (Case_Name) & "_" &
        Corpus_Name (Corpus);
      Source_Path  : constant String := Case_Dir & "/" & Entry_Name;
      Archive_Path : constant String := Case_Dir & "/stock.7z";
      Output_Path  : constant String := Case_Dir & "/output.bin";
      Status       : Zlib.Status_Code;
   begin
      Note_Check;
      Ensure_Clean_Directory (Case_Dir);
      Write_Payload (Source_Path, Data);

      case Case_Name is
         when BCJ_LZMA =>
            Run_7z
              ("7z create BCJ+LZMA", Case_Dir,
               [new String'("a"), new String'("-t7z"), new String'("-m0=BCJ"), new String'("-m1=LZMA"),
                new String'(Archive_Path), new String'(Entry_Name)]);
         when Delta_LZMA =>
            Run_7z
              ("7z create Delta+LZMA", Case_Dir,
               [new String'("a"), new String'("-t7z"), new String'("-m0=Delta"), new String'("-m1=LZMA"),
                new String'(Archive_Path), new String'(Entry_Name)]);
         when RISCV_LZMA =>
            Run_7z
              ("7z create RISCV+LZMA", Case_Dir,
               [new String'("a"), new String'("-t7z"), new String'("-m0=RISCV"), new String'("-m1=LZMA"),
                new String'(Archive_Path), new String'(Entry_Name)]);
      end case;

      Zlib.Extract_Seven_Zip_File (Archive_Path, Output_Path, Entry_Name, Status);
      Check_Status (Status, "extract stock filtered " & Filter_Name (Case_Name) & " archive");

      if not Same_File (Source_Path, Output_Path) then
         Fail ("stock filtered " & Filter_Name (Case_Name) & " archive did not match after native extraction");
      end if;
   end Check_Filter_7z_To_Our;

   procedure Write_Solid_Files
     (Case_Dir    : String;
      First_Path  : out US.Unbounded_String;
      Second_Path : out US.Unbounded_String;
      Third_Path  : out US.Unbounded_String)
   is
      First  : constant String := Case_Dir & "/alpha.bin";
      Second : constant String := Case_Dir & "/beta.txt";
      Third  : constant String := Case_Dir & "/gamma.bin";
   begin
      Write_Payload (First, Payload (Code_Corpus));
      Write_Payload (Second, Payload (Text_Corpus));
      Write_Payload (Third, Payload (Large_Corpus));
      First_Path := US.To_Unbounded_String (First);
      Second_Path := US.To_Unbounded_String (Second);
      Third_Path := US.To_Unbounded_String (Third);
   end Write_Solid_Files;

   procedure Write_File_List_Sources
     (Case_Dir    : String;
      First_Path  : out US.Unbounded_String;
      Second_Path : out US.Unbounded_String;
      Third_Path  : out US.Unbounded_String;
      Dir_Path    : out US.Unbounded_String)
   is
      Nested : constant String := Case_Dir & "/nested";
   begin
      Write_Solid_Files (Case_Dir, First_Path, Second_Path, Third_Path);
      Ada.Directories.Create_Path (Nested);
      Dir_Path := US.To_Unbounded_String (Nested);
   end Write_File_List_Sources;

   procedure Write_File_List_Archive
     (Method       : Archive_Method;
      Input_Paths  : Zlib.Text_Array;
      Entry_Names  : Zlib.Text_Array;
      Archive_Path : String)
   is
      Status : Zlib.Status_Code;
   begin
      Note_Check;
      case Method is
         when Copy_Method =>
            Zlib.Seven_Zip_Stored_Files (Input_Paths, Archive_Path, Entry_Names, Status);
         when Deflate_Method =>
            Zlib.Seven_Zip_Deflate_Files (Input_Paths, Archive_Path, Entry_Names, Status);
         when BZip2_Method =>
            Zlib.Seven_Zip_BZip2_Files (Input_Paths, Archive_Path, Entry_Names, Status);
         when LZMA_Method =>
            Zlib.Seven_Zip_LZMA_Files (Input_Paths, Archive_Path, Entry_Names, Status);
         when LZMA2_Method =>
            Zlib.Seven_Zip_LZMA2_Files (Input_Paths, Archive_Path, Entry_Names, Status);
         when PPMd_Method =>
            Zlib.Seven_Zip_PPMd_Files (Input_Paths, Archive_Path, Entry_Names, Status);
      end case;

      Check_Status (Status, "write native file-list " & Method_Name (Method) & " archive");
   end Write_File_List_Archive;

   procedure Check_File_List_Output
     (Label       : String;
      Source_Dir  : String;
      Extract_Dir : String)
   is
   begin
      Note_Check;
      if not Same_File (Source_Dir & "/alpha.bin", Extract_Dir & "/alpha.bin") then
         Fail (Label & " alpha.bin mismatch after extraction");
      end if;
      if not Same_File (Source_Dir & "/beta.txt", Extract_Dir & "/beta.txt") then
         Fail (Label & " beta.txt mismatch after extraction");
      end if;
      if not Same_File (Source_Dir & "/gamma.bin", Extract_Dir & "/gamma.bin") then
         Fail (Label & " gamma.bin mismatch after extraction");
      end if;
      Check_Directory (Extract_Dir & "/nested", Label & " nested directory");
   end Check_File_List_Output;

   procedure Check_File_List_Our_To_7z (Method : Archive_Method) is
      Case_Dir     : constant String := Work_Root & "/our_to_7z_file_list_" & Method_Name (Method);
      Archive_Path : constant String := Case_Dir & "/native.7z";
      Extract_Dir  : constant String := Case_Dir & "/extract";
      First_Path   : US.Unbounded_String;
      Second_Path  : US.Unbounded_String;
      Third_Path   : US.Unbounded_String;
      Dir_Path     : US.Unbounded_String;
   begin
      Note_Check;
      Ensure_Clean_Directory (Case_Dir);
      Ada.Directories.Create_Path (Extract_Dir);
      Write_File_List_Sources (Case_Dir, First_Path, Second_Path, Third_Path, Dir_Path);

      declare
         Input_Paths : constant Zlib.Text_Array :=
           [1 => First_Path, 2 => Second_Path, 3 => Third_Path, 4 => Dir_Path];
         Entry_Names : constant Zlib.Text_Array :=
           [1 => US.To_Unbounded_String ("alpha.bin"),
            2 => US.To_Unbounded_String ("beta.txt"),
            3 => US.To_Unbounded_String ("gamma.bin"),
            4 => US.To_Unbounded_String ("nested")];
      begin
         Write_File_List_Archive (Method, Input_Paths, Entry_Names, Archive_Path);
      end;

      Run_7z
        ("7z extract native file-list " & Method_Name (Method), Extract_Dir,
         [new String'("x"), new String'("-y"), new String'("-aoa"), new String'("-o" & Extract_Dir),
          new String'(Archive_Path)]);
      Check_File_List_Output ("native file-list " & Method_Name (Method), Case_Dir, Extract_Dir);
   end Check_File_List_Our_To_7z;

   procedure Check_File_List_7z_To_Our (Method : Archive_Method) is
      Case_Dir     : constant String := Work_Root & "/seven_to_our_file_list_" & Method_Name (Method);
      Archive_Path : constant String := Case_Dir & "/stock.7z";
      Extract_Dir  : constant String := Case_Dir & "/extract";
      Status       : Zlib.Status_Code;
      First_Path   : US.Unbounded_String;
      Second_Path  : US.Unbounded_String;
      Third_Path   : US.Unbounded_String;
      Dir_Path     : US.Unbounded_String;
   begin
      Note_Check;
      Ensure_Clean_Directory (Case_Dir);
      Ada.Directories.Create_Path (Extract_Dir);
      Write_File_List_Sources (Case_Dir, First_Path, Second_Path, Third_Path, Dir_Path);
      Run_7z
        ("7z create file-list " & Method_Name (Method), Case_Dir,
         [new String'("a"), new String'("-t7z"), new String'("-ms=off"),
          new String'("-m0=" & Method_Name (Method)), new String'(Archive_Path),
          new String'("alpha.bin"), new String'("beta.txt"), new String'("gamma.bin"),
          new String'("nested")]);

      Zlib.Extract_Archive_File_To_Directory (Archive_Path, Extract_Dir, "", Status);
      Check_Status (Status, "extract stock file-list " & Method_Name (Method) & " archive");
      Check_File_List_Output ("stock file-list " & Method_Name (Method), Case_Dir, Extract_Dir);
   end Check_File_List_7z_To_Our;

   procedure Check_Solid_Our_To_7z (Method : Solid_Method) is
      Case_Dir     : constant String := Work_Root & "/our_to_7z_solid_" & Solid_Name (Method);
      Archive_Path : constant String := Case_Dir & "/native.7z";
      Extract_Dir  : constant String := Case_Dir & "/extract";
      Status       : Zlib.Status_Code;
      First_Path   : US.Unbounded_String;
      Second_Path  : US.Unbounded_String;
      Third_Path   : US.Unbounded_String;
   begin
      Note_Check;
      Ensure_Clean_Directory (Case_Dir);
      Ada.Directories.Create_Path (Extract_Dir);
      Write_Solid_Files (Case_Dir, First_Path, Second_Path, Third_Path);

      declare
         Input_Paths : constant Zlib.Text_Array :=
           [1 => First_Path, 2 => Second_Path, 3 => Third_Path];
         Entry_Names : constant Zlib.Text_Array :=
           [1 => US.To_Unbounded_String ("alpha.bin"),
            2 => US.To_Unbounded_String ("beta.txt"),
            3 => US.To_Unbounded_String ("gamma.bin")];
      begin
         case Method is
            when Solid_LZMA =>
               Zlib.Seven_Zip_LZMA_Solid_Files (Input_Paths, Archive_Path, Entry_Names, Status);
            when Solid_LZMA2 =>
               Zlib.Seven_Zip_LZMA2_Solid_Files (Input_Paths, Archive_Path, Entry_Names, Status);
            when Solid_PPMd =>
               Zlib.Seven_Zip_PPMd_Solid_Files (Input_Paths, Archive_Path, Entry_Names, Status);
         end case;
      end;

      Check_Status (Status, "write native solid " & Solid_Name (Method) & " archive");
      Run_7z
        ("7z extract native solid " & Solid_Name (Method), Extract_Dir,
         [new String'("x"), new String'("-y"), new String'("-aoa"), new String'("-o" & Extract_Dir),
          new String'(Archive_Path)]);

      if not Same_File (US.To_String (First_Path), Extract_Dir & "/alpha.bin") then
         Fail ("native solid " & Solid_Name (Method) & " alpha.bin mismatch after 7z extraction");
      end if;
      if not Same_File (US.To_String (Second_Path), Extract_Dir & "/beta.txt") then
         Fail ("native solid " & Solid_Name (Method) & " beta.txt mismatch after 7z extraction");
      end if;
      if not Same_File (US.To_String (Third_Path), Extract_Dir & "/gamma.bin") then
         Fail ("native solid " & Solid_Name (Method) & " gamma.bin mismatch after 7z extraction");
      end if;
   end Check_Solid_Our_To_7z;

   procedure Check_Solid_7z_To_Our (Method : Solid_Method) is
      Case_Dir     : constant String := Work_Root & "/seven_to_our_solid_" & Solid_Name (Method);
      Archive_Path : constant String := Case_Dir & "/stock.7z";
      Extract_Dir  : constant String := Case_Dir & "/extract";
      Status       : Zlib.Status_Code;
      First_Path   : US.Unbounded_String;
      Second_Path  : US.Unbounded_String;
      Third_Path   : US.Unbounded_String;
   begin
      Note_Check;
      Ensure_Clean_Directory (Case_Dir);
      Ada.Directories.Create_Path (Extract_Dir);
      Write_Solid_Files (Case_Dir, First_Path, Second_Path, Third_Path);
      Run_7z
        ("7z create solid " & Solid_Name (Method), Case_Dir,
         [new String'("a"), new String'("-t7z"), new String'("-ms=on"),
          new String'("-m0=" & Solid_Name (Method)), new String'(Archive_Path),
          new String'("alpha.bin"), new String'("beta.txt"), new String'("gamma.bin")]);

      Zlib.Extract_Archive_File_To_Directory (Archive_Path, Extract_Dir, "", Status);
      Check_Status (Status, "extract stock solid " & Solid_Name (Method) & " archive");

      if not Same_File (US.To_String (First_Path), Extract_Dir & "/alpha.bin") then
         Fail ("stock solid " & Solid_Name (Method) & " alpha.bin mismatch after native extraction");
      end if;
      if not Same_File (US.To_String (Second_Path), Extract_Dir & "/beta.txt") then
         Fail ("stock solid " & Solid_Name (Method) & " beta.txt mismatch after native extraction");
      end if;
      if not Same_File (US.To_String (Third_Path), Extract_Dir & "/gamma.bin") then
         Fail ("stock solid " & Solid_Name (Method) & " gamma.bin mismatch after native extraction");
      end if;
   end Check_Solid_7z_To_Our;

   procedure Check_Encrypted_Our_To_7z is
      Case_Dir     : constant String := Work_Root & "/our_to_7z_encrypted";
      Source_Path  : constant String := Case_Dir & "/" & Entry_Name;
      Archive_Path : constant String := Case_Dir & "/native.7z";
      Header_Path  : constant String := Case_Dir & "/native_mhe.7z";
      Extract_Dir  : constant String := Case_Dir & "/extract";
      Header_Dir   : constant String := Case_Dir & "/extract_mhe";
      Status       : Zlib.Status_Code;
      Archive      : Zlib.Byte_Array :=
        Zlib.Seven_Zip_LZMA_Encrypted (Payload (Text_Corpus), Entry_Name, Password, Status);
   begin
      Note_Check;
      Ensure_Clean_Directory (Case_Dir);
      Ada.Directories.Create_Path (Extract_Dir);
      Ada.Directories.Create_Path (Header_Dir);
      Write_Payload (Source_Path, Payload (Text_Corpus));
      Check_Status (Status, "write native encrypted LZMA archive");
      if Status = Zlib.Ok then
         Zlib_Tool_Support.Write_File (Archive_Path, Archive, Status);
         Check_Status (Status, "write native encrypted archive file");
      end if;

      Run_7z
        ("7z extract native encrypted", Extract_Dir,
         [new String'("x"), new String'("-y"), new String'("-aoa"), new String'("-p" & Password),
          new String'("-o" & Extract_Dir), new String'(Archive_Path)]);

      if not Same_File (Source_Path, Extract_Dir & "/" & Entry_Name) then
         Fail ("native encrypted archive mismatch after 7z extraction");
      end if;
      Check_Single_Entry_List
        (Archive_Path, Password, Entry_Name, Corpus_Length (Text_Corpus), "native encrypted archive");
      Check_Extract_Fails (Archive_Path, Entry_Name, "wrong-" & Password, "native encrypted archive wrong password");

      declare
         Header_Archive : constant Zlib.Byte_Array := Zlib.Encrypt_Seven_Zip_Header (Archive, Password, Status);
      begin
         Check_Status (Status, "write native encrypted-header archive");
         if Status = Zlib.Ok then
            Zlib_Tool_Support.Write_File (Header_Path, Header_Archive, Status);
            Check_Status (Status, "write native encrypted-header archive file");
         end if;
      end;

      Run_7z
        ("7z extract native encrypted header", Header_Dir,
         [new String'("x"), new String'("-y"), new String'("-aoa"), new String'("-p" & Password),
          new String'("-o" & Header_Dir), new String'(Header_Path)]);

      if not Same_File (Source_Path, Header_Dir & "/" & Entry_Name) then
         Fail ("native encrypted-header archive mismatch after 7z extraction");
      end if;
      Check_Single_Entry_List
        (Header_Path, Password, Entry_Name, Corpus_Length (Text_Corpus), "native encrypted-header archive");
      Check_List_Fails (Header_Path, "wrong-" & Password, "native encrypted-header archive wrong password");
      Check_Extract_Fails
        (Header_Path, Entry_Name, "wrong-" & Password, "native encrypted-header archive wrong password");
   end Check_Encrypted_Our_To_7z;

   procedure Check_Encrypted_7z_To_Our is
      Case_Dir     : constant String := Work_Root & "/seven_to_our_encrypted";
      Source_Path  : constant String := Case_Dir & "/" & Entry_Name;
      Archive_Path : constant String := Case_Dir & "/stock.7z";
      Header_Path  : constant String := Case_Dir & "/stock_mhe.7z";
      Status       : Zlib.Status_Code;
   begin
      Note_Check;
      Ensure_Clean_Directory (Case_Dir);
      Write_Payload (Source_Path, Payload (Text_Corpus));
      Run_7z
        ("7z create encrypted", Case_Dir,
         [new String'("a"), new String'("-t7z"), new String'("-m0=LZMA"), new String'("-p" & Password),
          new String'(Archive_Path), new String'(Entry_Name)]);
      Run_7z
        ("7z create encrypted header", Case_Dir,
         [new String'("a"), new String'("-t7z"), new String'("-m0=LZMA"), new String'("-p" & Password),
          new String'("-mhe=on"), new String'(Header_Path), new String'(Entry_Name)]);
      Check_Single_Entry_List
        (Archive_Path, Password, Entry_Name, Corpus_Length (Text_Corpus), "stock encrypted archive");
      Check_Single_Entry_List
        (Header_Path, Password, Entry_Name, Corpus_Length (Text_Corpus), "stock encrypted-header archive");
      Check_List_Fails (Header_Path, "wrong-" & Password, "stock encrypted-header archive wrong password");
      Check_Extract_Fails (Archive_Path, Entry_Name, "wrong-" & Password, "stock encrypted archive wrong password");
      Check_Extract_Fails
        (Header_Path, Entry_Name, "wrong-" & Password, "stock encrypted-header archive wrong password");

      declare
         Archive_Status : Zlib.Status_Code;
         Archive        : constant Zlib.Byte_Array := Zlib_Tool_Support.Read_File (Archive_Path, Archive_Status);
         Out_B          : Zlib.Byte_Array := Zlib.Extract_Seven_Zip (Archive, Entry_Name, Password, Status);
      begin
         Check_Status (Archive_Status, "read stock encrypted archive");
         Check_Status (Status, "extract stock encrypted archive");
         if Archive_Status = Zlib.Ok and then Status = Zlib.Ok and then Out_B /= Payload (Text_Corpus) then
            Fail ("stock encrypted archive mismatch after native extraction");
         end if;
      end;

      declare
         Archive_Status : Zlib.Status_Code;
         Archive        : constant Zlib.Byte_Array := Zlib_Tool_Support.Read_File (Header_Path, Archive_Status);
         Out_B          : Zlib.Byte_Array := Zlib.Extract_Seven_Zip (Archive, Entry_Name, Password, Status);
      begin
         Check_Status (Archive_Status, "read stock encrypted-header archive");
         Check_Status (Status, "extract stock encrypted-header archive");
         if Archive_Status = Zlib.Ok and then Status = Zlib.Ok and then Out_B /= Payload (Text_Corpus) then
            Fail ("stock encrypted-header archive mismatch after native extraction");
         end if;
      end;
   end Check_Encrypted_7z_To_Our;

   procedure Check_Volumes_Our_To_7z is
      Case_Dir    : constant String := Work_Root & "/our_to_7z_volumes";
      Source_Path : constant String := Case_Dir & "/" & Entry_Name;
      Base_Path   : constant String := Case_Dir & "/native.7z";
      Extract_Dir : constant String := Case_Dir & "/extract";
      Status      : Zlib.Status_Code;
      Archive     : constant Zlib.Byte_Array :=
        Zlib.Seven_Zip_Filtered
          (Payload (Large_Corpus), Entry_Name, Zlib.Seven_Zip_Filter_Delta, Zlib.Seven_Zip_Codec_LZMA, Status);
   begin
      Note_Check;
      Ensure_Clean_Directory (Case_Dir);
      Ada.Directories.Create_Path (Extract_Dir);
      Write_Payload (Source_Path, Payload (Large_Corpus));
      Check_Status (Status, "write native volume source archive");
      if Status = Zlib.Ok then
         Zlib.Write_Seven_Zip_Volumes (Archive, Base_Path, 1024, Status);
         Check_Status (Status, "write native archive volumes");
      end if;

      Run_7z
        ("7z extract native volumes", Extract_Dir,
         [new String'("x"), new String'("-y"), new String'("-aoa"), new String'("-o" & Extract_Dir),
          new String'(Base_Path & ".001")]);

      if not Same_File (Source_Path, Extract_Dir & "/" & Entry_Name) then
         Fail ("native volumes mismatch after 7z extraction");
      end if;
   end Check_Volumes_Our_To_7z;

   procedure Check_Volumes_7z_To_Our is
      Case_Dir     : constant String := Work_Root & "/seven_to_our_volumes";
      Source_Path  : constant String := Case_Dir & "/" & Entry_Name;
      Archive_Path : constant String := Case_Dir & "/stock.7z";
      Status       : Zlib.Status_Code;
   begin
      Note_Check;
      Ensure_Clean_Directory (Case_Dir);
      Write_Payload (Source_Path, Payload (Large_Corpus));
      Run_7z
        ("7z create volumes", Case_Dir,
         [new String'("a"), new String'("-t7z"), new String'("-m0=LZMA"), new String'("-v1k"),
          new String'(Archive_Path), new String'(Entry_Name)]);

      declare
         Out_B : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip_Volumes (Archive_Path & ".001", Entry_Name, "", Status);
      begin
         Check_Status (Status, "extract stock archive volumes");
         if Status = Zlib.Ok and then Out_B /= Payload (Large_Corpus) then
            Fail ("stock volumes mismatch after native extraction");
         end if;
      end;
   end Check_Volumes_7z_To_Our;

   procedure Check_BCJ2_Our_To_7z is
      Case_Dir     : constant String := Work_Root & "/our_to_7z_BCJ2";
      Source_Path  : constant String := Case_Dir & "/" & Entry_Name;
      Archive_Path : constant String := Case_Dir & "/native.7z";
      Extract_Dir  : constant String := Case_Dir & "/extract";
      Status       : Zlib.Status_Code;
      Archive      : constant Zlib.Byte_Array := Zlib.Seven_Zip_BCJ2 (Payload (Code_Corpus), Entry_Name, Status);
   begin
      Note_Check;
      Ensure_Clean_Directory (Case_Dir);
      Ada.Directories.Create_Path (Extract_Dir);
      Write_Payload (Source_Path, Payload (Code_Corpus));
      Check_Status (Status, "write native BCJ2 archive");
      if Status = Zlib.Ok then
         Zlib_Tool_Support.Write_File (Archive_Path, Archive, Status);
         Check_Status (Status, "write native BCJ2 archive file");
      end if;

      Run_7z
        ("7z extract native BCJ2", Extract_Dir,
         [new String'("x"), new String'("-y"), new String'("-aoa"), new String'("-o" & Extract_Dir),
          new String'(Archive_Path)]);

      if not Same_File (Source_Path, Extract_Dir & "/" & Entry_Name) then
         Fail ("native BCJ2 archive mismatch after 7z extraction");
      end if;
   end Check_BCJ2_Our_To_7z;

   procedure Check_BCJ2_7z_To_Our is
      Case_Dir     : constant String := Work_Root & "/seven_to_our_BCJ2";
      Source_Path  : constant String := Case_Dir & "/" & Entry_Name;
      Archive_Path : constant String := Case_Dir & "/stock.7z";
      Status       : Zlib.Status_Code;
   begin
      Note_Check;
      Ensure_Clean_Directory (Case_Dir);
      Write_Payload (Source_Path, Payload (Code_Corpus));
      Run_7z
        ("7z create BCJ2", Case_Dir,
         [new String'("a"), new String'("-t7z"), new String'("-m0=BCJ2"),
          new String'(Archive_Path), new String'(Entry_Name)]);

      declare
         Archive_Status : Zlib.Status_Code;
         Archive        : constant Zlib.Byte_Array := Zlib_Tool_Support.Read_File (Archive_Path, Archive_Status);
         Out_B          : constant Zlib.Byte_Array := Zlib.Extract_Seven_Zip (Archive, Entry_Name, Status);
      begin
         Check_Status (Archive_Status, "read stock BCJ2 archive");
         Check_Status (Status, "extract stock BCJ2 archive");
         if Archive_Status = Zlib.Ok and then Status = Zlib.Ok and then Out_B /= Payload (Code_Corpus) then
            Fail ("stock BCJ2 archive mismatch after native extraction");
         end if;
      end;
   end Check_BCJ2_7z_To_Our;
begin
   if Seven_Zip = "" then
      Ada.Text_IO.Put_Line ("SKIP: 7z not found on PATH");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
      return;
   end if;

   Ensure_Clean_Directory (Work_Root);

   declare
      RISCV_Supported : constant Boolean := Seven_Zip_Supports_RISCV;
   begin
      if not RISCV_Supported then
         Skip ("7z RISCV method not available; RISC-V stock interop not run");
      end if;

   for Corpus in Corpus_Case loop
      declare
         Data : constant Zlib.Byte_Array := Payload (Corpus);
      begin
         for Method in Archive_Method loop
            Check_Our_To_7z (Method, Corpus, Data);
            Check_7z_To_Our (Method, Corpus, Data);
         end loop;
      end;
   end loop;

   for Corpus in Corpus_Case loop
      if Corpus /= Empty_Corpus then
         declare
            Data : constant Zlib.Byte_Array :=
              (if Corpus = Code_Corpus then RISCV_Payload else Payload (Corpus));
         begin
            for Case_Name in Filter_Case loop
               if Case_Name /= RISCV_LZMA or else RISCV_Supported then
                  Check_Filter_Our_To_7z (Case_Name, Corpus, Data);
                  Check_Filter_7z_To_Our (Case_Name, Corpus, Data);
               else
                  Skips := Skips + 2;
               end if;
            end loop;
         end;
      end if;
   end loop;

   for Method in Solid_Method loop
      Check_Solid_Our_To_7z (Method);
      Check_Solid_7z_To_Our (Method);
   end loop;

   for Method in Archive_Method loop
      Check_File_List_Our_To_7z (Method);
      Check_File_List_7z_To_Our (Method);
   end loop;

   Check_Encrypted_Our_To_7z;
   Check_Encrypted_7z_To_Our;
   Check_Volumes_Our_To_7z;
   Check_Volumes_7z_To_Our;
   Check_BCJ2_Our_To_7z;
   Check_BCJ2_7z_To_Our;
   end;

   if Failures = 0 then
      Ada.Text_IO.Put_Line
        ("seven_zip_interop_check passed: checks=" & Natural'Image (Checks) &
         " skips=" & Natural'Image (Skips));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
   else
      Ada.Text_IO.Put_Line
        ("seven_zip_interop_check failed:" & Natural'Image (Failures) &
         " failure(s), checks=" & Natural'Image (Checks) &
         " skips=" & Natural'Image (Skips));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
exception
   when Error : others =>
      Ada.Text_IO.Put_Line ("FAIL: unexpected exception in seven_zip_interop_check");
      Ada.Text_IO.Put_Line (Ada.Exceptions.Exception_Information (Error));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Seven_Zip_Interop_Check;
