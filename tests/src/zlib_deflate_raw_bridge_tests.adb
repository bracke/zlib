with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;

package body Zlib_Deflate_Raw_Bridge_Tests is
   use type Ada.Streams.Stream_Element_Offset;
   use type Zlib.Byte;
   use type Zlib.Status_Code;

   package SIO renames Ada.Streams.Stream_IO;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib one-shot raw Deflate bridge");
   end Name;

   function Empty return Zlib.Byte_Array is
      Result : constant Zlib.Byte_Array (1 .. 0) := [others => 0];
   begin
      return Result;
   end Empty;

   function Git_Shaped return Zlib.Byte_Array is
   begin
      return
        [1  => Zlib.Byte (Character'Pos ('b')),
         2  => Zlib.Byte (Character'Pos ('l')),
         3  => Zlib.Byte (Character'Pos ('o')),
         4  => Zlib.Byte (Character'Pos ('b')),
         5  => Zlib.Byte (Character'Pos (' ')),
         6  => Zlib.Byte (Character'Pos ('1')),
         7  => Zlib.Byte (Character'Pos ('2')),
         8  => 0,
         9  => Zlib.Byte (Character'Pos ('h')),
         10 => Zlib.Byte (Character'Pos ('e')),
         11 => Zlib.Byte (Character'Pos ('l')),
         12 => Zlib.Byte (Character'Pos ('l')),
         13 => Zlib.Byte (Character'Pos ('o')),
         14 => 10,
         15 => Zlib.Byte (Character'Pos ('w')),
         16 => Zlib.Byte (Character'Pos ('o')),
         17 => Zlib.Byte (Character'Pos ('r')),
         18 => Zlib.Byte (Character'Pos ('l')),
         19 => Zlib.Byte (Character'Pos ('d')),
         20 => 10];
   end Git_Shaped;

   function Binary_Payload return Zlib.Byte_Array is
      Result : Zlib.Byte_Array (1 .. 512);
   begin
      for I in Result'Range loop
         Result (I) := Zlib.Byte ((I * 37) mod 256);
      end loop;
      Result (1) := 0;
      Result (2) := 16#80#;
      Result (3) := 16#FF#;
      Result (4) := 10;
      Result (5) := 13;
      return Result;
   end Binary_Payload;

   function Repeated_Payload return Zlib.Byte_Array is
      Result : Zlib.Byte_Array (1 .. 4096);
   begin
      for I in Result'Range loop
         case I mod 4 is
            when 0 => Result (I) := Zlib.Byte (Character'Pos ('A'));
            when 1 => Result (I) := Zlib.Byte (Character'Pos ('B'));
            when 2 => Result (I) := Zlib.Byte (Character'Pos ('C'));
            when others => Result (I) := 10;
         end case;
      end loop;
      return Result;
   end Repeated_Payload;

   function Large_Payload return Zlib.Byte_Array is
      Result : Zlib.Byte_Array (1 .. 70_000);
   begin
      for I in Result'Range loop
         Result (I) := Zlib.Byte ((I * 91) mod 251);
      end loop;
      return Result;
   end Large_Payload;

   procedure Assert_Same
     (Actual   : Zlib.Byte_Array;
      Expected : Zlib.Byte_Array;
      Message  : String)
   is
   begin
      Assert (Actual'Length = Expected'Length, Message & ": length mismatch");
      for I in Expected'Range loop
         Assert
           (Actual (Actual'First + (I - Expected'First)) = Expected (I),
            Message & ": byte mismatch at" & Natural'Image (I));
      end loop;
   end Assert_Same;

   function Before_First
     (Data : Ada.Streams.Stream_Element_Array)
      return Ada.Streams.Stream_Element_Offset
   is
   begin
      if Data'Length = 0 then
         return Data'First;
      elsif Data'First = Ada.Streams.Stream_Element_Offset'First then
         return Data'First;
      else
         return Data'First - 1;
      end if;
   end Before_First;

   function Produced
     (Data : Ada.Streams.Stream_Element_Array;
      Last : Ada.Streams.Stream_Element_Offset)
      return Natural
   is
   begin
      if Data'Length = 0 or else Last = Before_First (Data) then
         return 0;
      else
         return Natural (Last - Data'First + 1);
      end if;
   end Produced;

   function To_Stream
     (Input : Zlib.Byte_Array)
      return Ada.Streams.Stream_Element_Array
   is
      Result : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Input'Length));
   begin
      for I in Input'Range loop
         Result (Ada.Streams.Stream_Element_Offset (I - Input'First + 1)) :=
           Ada.Streams.Stream_Element (Input (I));
      end loop;
      return Result;
   end To_Stream;

   function Streaming_Raw
     (Input : Zlib.Byte_Array;
      Mode  : Zlib.Compression_Mode)
      return Zlib.Byte_Array
   is
      Filter     : Zlib.Compression_Filter_Type;
      In_Data    : constant Ada.Streams.Stream_Element_Array := To_Stream (Input);
      Output     : Zlib.Byte_Array
        (1 .. Natural'Max (1, Input'Length * 4 + 20_000 + ((Input'Length / 65_535) + 3) * 5));
      Out_Count  : Natural := 0;
      Next_Input : Ada.Streams.Stream_Element_Offset := In_Data'First;
      In_Last    : Ada.Streams.Stream_Element_Offset;
      Out_Last   : Ada.Streams.Stream_Element_Offset;
      Calls      : Natural := 0;

      procedure Append
        (Buffer : Ada.Streams.Stream_Element_Array;
         Last   : Ada.Streams.Stream_Element_Offset)
      is
         Count : constant Natural := Produced (Buffer, Last);
      begin
         for I in Buffer'First .. Buffer'First + Ada.Streams.Stream_Element_Offset (Count) - 1 loop
            Out_Count := Out_Count + 1;
            Assert (Out_Count <= Output'Last, "streaming raw bridge fixture output capacity");
            Output (Out_Count) := Zlib.Byte (Buffer (I));
         end loop;
      end Append;
   begin
      Zlib.Deflate_Init (Filter, Header => Zlib.Raw_Deflate, Mode => Mode);

      while In_Data'Length > 0 and then Next_Input <= In_Data'Last loop
         declare
            Out_Buffer : Ada.Streams.Stream_Element_Array (1 .. 257);
         begin
            Zlib.Compress
              (Filter   => Filter,
               In_Data  => In_Data (Next_Input .. In_Data'Last),
               In_Last  => In_Last,
               Out_Data => Out_Buffer,
               Out_Last => Out_Last,
               Flush    => Zlib.No_Flush);
            Append (Out_Buffer, Out_Last);

            if In_Last >= Next_Input then
               Next_Input := In_Last + 1;
            elsif Produced (Out_Buffer, Out_Last) = 0 then
               Assert (False, "streaming raw bridge fixture must make progress");
            end if;

            Calls := Calls + 1;
            Assert (Calls < 1_000_000, "streaming raw bridge input loop bound");
         end;
      end loop;

      while not Zlib.Compress_Stream_End (Filter) loop
         declare
            Out_Buffer : Ada.Streams.Stream_Element_Array (1 .. 257);
         begin
            Zlib.Compress_Flush
              (Filter   => Filter,
               Out_Data => Out_Buffer,
               Out_Last => Out_Last,
               Flush    => Zlib.Finish);
            Append (Out_Buffer, Out_Last);

            Calls := Calls + 1;
            Assert (Calls < 1_000_000, "streaming raw bridge finish loop bound");
         end;
      end loop;

      Zlib.Compress_Close (Filter);
      if Out_Count = 0 then
         return Empty;
      else
         return Output (1 .. Out_Count);
      end if;
   end Streaming_Raw;

   procedure Assert_Raw_Roundtrip
     (Compressed : Zlib.Byte_Array;
      Expected   : Zlib.Byte_Array;
      Message    : String)
   is
      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Compressed, Zlib.Raw_Deflate, Status);
   begin
      Assert (Status = Zlib.Ok, Message & ": raw inflate status");
      Assert_Same (Output, Expected, Message);
   end Assert_Raw_Roundtrip;

   procedure Assert_Rejected
     (Compressed : Zlib.Byte_Array;
      Header     : Zlib.Header_Type;
      Message    : String)
   is
      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array := Zlib.Inflate_With_Header (Compressed, Header, Status);
      pragma Unreferenced (Output);
   begin
      Assert (Status /= Zlib.Ok, Message);
   end Assert_Rejected;

   procedure Assert_Default_Inflate_Accepts_Raw
     (Compressed : Zlib.Byte_Array;
      Expected   : Zlib.Byte_Array;
      Message    : String)
   is
      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array := Zlib.Inflate (Compressed, Status);
   begin
      Assert (Status = Zlib.Ok, Message & ": status");
      Assert_Same (Output, Expected, Message);
   end Assert_Default_Inflate_Accepts_Raw;

   procedure Assert_Raw_Mode
     (Mode    : Zlib.Compression_Mode;
      Payload : Zlib.Byte_Array;
      Label   : String)
   is
      Status : Zlib.Status_Code := Zlib.Ok;
      Output : constant Zlib.Byte_Array := Zlib.Deflate_Raw (Payload, Mode, Status);
   begin
      Assert (Status = Zlib.Ok, Label & ": Deflate_Raw status");
      Assert_Raw_Roundtrip (Output, Payload, Label & ": raw roundtrip");
      Assert_Default_Inflate_Accepts_Raw
        (Output, Payload, Label & ": default Inflate auto-detects raw output");
      Assert_Rejected (Output, Zlib.Zlib_Header, Label & ": zlib inflate rejects raw output");
      Assert_Rejected (Output, Zlib.GZip, Label & ": gzip inflate rejects raw output");
   end Assert_Raw_Mode;

   procedure Assert_Bridge_Matches_Streaming
     (Mode    : Zlib.Compression_Mode;
      Payload : Zlib.Byte_Array;
      Label   : String)
   is
      Status    : Zlib.Status_Code := Zlib.Ok;
      One_Shot  : constant Zlib.Byte_Array := Zlib.Deflate_Raw (Payload, Mode, Status);
      Streaming : constant Zlib.Byte_Array := Streaming_Raw (Payload, Mode);
   begin
      Assert (Status = Zlib.Ok, Label & ": one-shot status");
      Assert_Same
        (One_Shot,
         Streaming,
         Label & ": one-shot raw bridge equals streaming raw output");
      Assert_Raw_Roundtrip (One_Shot, Payload, Label & ": one-shot roundtrip");
      Assert_Raw_Roundtrip (Streaming, Payload, Label & ": streaming roundtrip");
   end Assert_Bridge_Matches_Streaming;

   procedure Assert_Deterministic
     (Mode    : Zlib.Compression_Mode;
      Payload : Zlib.Byte_Array;
      Label   : String)
   is
      Status_A : Zlib.Status_Code := Zlib.Ok;
      Status_B : Zlib.Status_Code := Zlib.Ok;
      A        : constant Zlib.Byte_Array := Zlib.Deflate_Raw (Payload, Mode, Status_A);
      B        : constant Zlib.Byte_Array := Zlib.Deflate_Raw (Payload, Mode, Status_B);
   begin
      Assert (Status_A = Zlib.Ok and then Status_B = Zlib.Ok, Label & ": status");
      Assert_Same (A, B, Label & ": deterministic output");
   end Assert_Deterministic;

   procedure Write_File
     (Path : String;
      Data : Zlib.Byte_Array)
   is
      File : SIO.File_Type;
   begin
      SIO.Create (File, SIO.Out_File, Path);
      if Data'Length > 0 then
         declare
            Buffer : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Data'Length));
         begin
            for I in Data'Range loop
               Buffer (Ada.Streams.Stream_Element_Offset (I - Data'First + 1)) :=
                 Ada.Streams.Stream_Element (Data (I));
            end loop;
            SIO.Write (File, Buffer);
         end;
      end if;
      SIO.Close (File);
   exception
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         raise;
   end Write_File;

   function Read_File (Path : String) return Zlib.Byte_Array is
      File : SIO.File_Type;
   begin
      SIO.Open (File, SIO.In_File, Path);
      declare
         Size : constant Natural := Natural (SIO.Size (File));
      begin
         if Size = 0 then
            SIO.Close (File);
            return Empty;
         end if;

         declare
            Buffer : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Size));
            Last   : Ada.Streams.Stream_Element_Offset;
            Result : Zlib.Byte_Array (1 .. Size);
         begin
            SIO.Read (File, Buffer, Last);
            SIO.Close (File);
            for I in Result'Range loop
               Result (I) := Zlib.Byte (Buffer (Ada.Streams.Stream_Element_Offset (I)));
            end loop;
            return Result;
         end;
      end;
   exception
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         raise;
   end Read_File;

   procedure Delete_If_Exists (Path : String) is
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   end Delete_If_Exists;

   procedure Assert_File_Mode
     (Mode    : Zlib.Compression_Mode;
      Payload : Zlib.Byte_Array;
      Label   : String)
   is
      Input_Path  : constant String := "raw_bridge_" & Label & ".in";
      Output_Path : constant String := "raw_bridge_" & Label & ".deflate";
      Status      : Zlib.Status_Code := Zlib.Ok;
   begin
      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Output_Path);
      Write_File (Input_Path, Payload);

      Zlib.Deflate_Raw_File
        (Input_Path  => Input_Path,
         Output_Path => Output_Path,
         Mode        => Mode,
         Status      => Status);

      Assert (Status = Zlib.Ok, Label & ": Deflate_Raw_File status");
      Assert_Raw_Roundtrip (Read_File (Output_Path), Payload, Label & ": file roundtrip");

      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Output_Path);
   end Assert_File_Mode;

   procedure Test_Stored_Roundtrip (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Raw_Mode (Zlib.Stored, Git_Shaped, "Stored");
   end Test_Stored_Roundtrip;

   procedure Test_Fixed_Roundtrip (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Raw_Mode (Zlib.Fixed, Git_Shaped, "Fixed");
   end Test_Fixed_Roundtrip;

   procedure Test_Dynamic_Roundtrip (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Raw_Mode (Zlib.Dynamic, Git_Shaped, "Dynamic");
   end Test_Dynamic_Roundtrip;

   procedure Test_Auto_Roundtrip (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Raw_Mode (Zlib.Auto, Git_Shaped, "Auto");
   end Test_Auto_Roundtrip;

   procedure Test_Stored_Matches_Streaming (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Bridge_Matches_Streaming (Zlib.Stored, Repeated_Payload, "Stored streaming bridge");
   end Test_Stored_Matches_Streaming;

   procedure Test_Fixed_Matches_Streaming (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Bridge_Matches_Streaming (Zlib.Fixed, Repeated_Payload, "Fixed streaming bridge");
   end Test_Fixed_Matches_Streaming;

   procedure Test_Dynamic_Matches_Streaming (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Bridge_Matches_Streaming (Zlib.Dynamic, Repeated_Payload, "Dynamic streaming bridge");
   end Test_Dynamic_Matches_Streaming;

   procedure Test_Auto_Matches_Streaming (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Bridge_Matches_Streaming (Zlib.Auto, Repeated_Payload, "Auto streaming bridge");
   end Test_Auto_Matches_Streaming;

   procedure Test_Empty_Payload (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Raw_Mode (Zlib.Stored, Empty, "empty Stored payload");
      Assert_Raw_Mode (Zlib.Fixed, Empty, "empty Fixed payload");
      Assert_Raw_Mode (Zlib.Dynamic, Empty, "empty Dynamic payload");
      Assert_Raw_Mode (Zlib.Auto, Empty, "empty Auto payload");
   end Test_Empty_Payload;

   procedure Test_Binary_Payload (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Raw_Mode
        (Zlib.Auto,
         Binary_Payload,
         "binary payload with NUL and high bytes");
   end Test_Binary_Payload;

   procedure Test_Git_Shaped_Payload (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Raw_Mode (Zlib.Dynamic, Git_Shaped, "Git-shaped payload");
   end Test_Git_Shaped_Payload;

   procedure Test_Repeated_Payload (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Raw_Mode (Zlib.Auto, Repeated_Payload, "repeated payload");
   end Test_Repeated_Payload;

   procedure Test_Large_Payload (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Raw_Mode (Zlib.Auto, Large_Payload, "large payload");
   end Test_Large_Payload;

   procedure Test_Deterministic (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Deterministic (Zlib.Stored, Repeated_Payload, "Stored deterministic");
      Assert_Deterministic (Zlib.Fixed, Repeated_Payload, "Fixed deterministic");
      Assert_Deterministic (Zlib.Dynamic, Repeated_Payload, "Dynamic deterministic");
      Assert_Deterministic (Zlib.Auto, Repeated_Payload, "Auto deterministic");
   end Test_Deterministic;

   procedure Test_File_Stored (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_File_Mode (Zlib.Stored, Git_Shaped, "stored");
   end Test_File_Stored;

   procedure Test_File_Fixed (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_File_Mode (Zlib.Fixed, Git_Shaped, "fixed");
   end Test_File_Fixed;

   procedure Test_File_Dynamic (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_File_Mode (Zlib.Dynamic, Git_Shaped, "dynamic");
   end Test_File_Dynamic;

   procedure Test_File_Auto (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_File_Mode (Zlib.Auto, Git_Shaped, "auto");
   end Test_File_Auto;

   procedure Test_File_Missing_Input (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Status      : Zlib.Status_Code := Zlib.Ok;
      Input_Path  : constant String := "raw_bridge_missing_input.bin";
      Output_Path : constant String := "raw_bridge_missing_output.deflate";
   begin
      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Output_Path);
      Zlib.Deflate_Raw_File (Input_Path, Output_Path, Zlib.Auto, Status);
      Assert (Status = Zlib.Input_File_Error, "missing raw input file status");
      Assert
        (not Ada.Directories.Exists (Output_Path),
         "missing raw input must not create output");
   end Test_File_Missing_Input;

   procedure Test_File_Output_Failure
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status     : Zlib.Status_Code := Zlib.Ok;
      Input_Path : constant String := "raw_bridge_output_failure.in";
   begin
      Delete_If_Exists (Input_Path);
      Write_File (Input_Path, Git_Shaped);

      Zlib.Deflate_Raw_File
        (Input_Path  => Input_Path,
         Output_Path => ".",
         Mode        => Zlib.Auto,
         Status      => Status);

      Assert
        (Status = Zlib.Output_File_Error,
         "raw file write failure must map to Output_File_Error");

      Delete_If_Exists (Input_Path);
   end Test_File_Output_Failure;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_Stored_Roundtrip'Access,
         "Deflate_Raw Stored roundtrips raw only");
      Registration.Register_Routine
        (T, Test_Fixed_Roundtrip'Access,
         "Deflate_Raw Fixed roundtrips raw only");
      Registration.Register_Routine
        (T, Test_Dynamic_Roundtrip'Access,
         "Deflate_Raw Dynamic roundtrips raw only");
      Registration.Register_Routine
        (T, Test_Auto_Roundtrip'Access,
         "Deflate_Raw Auto roundtrips raw only");
      Registration.Register_Routine
        (T, Test_Stored_Matches_Streaming'Access,
         "Stored bridge equals streaming raw");
      Registration.Register_Routine
        (T, Test_Fixed_Matches_Streaming'Access,
         "Fixed bridge equals streaming raw");
      Registration.Register_Routine
        (T, Test_Dynamic_Matches_Streaming'Access,
         "Dynamic bridge equals streaming raw");
      Registration.Register_Routine
        (T, Test_Auto_Matches_Streaming'Access,
         "Auto bridge equals streaming raw");
      Registration.Register_Routine
        (T, Test_Empty_Payload'Access,
         "Deflate_Raw handles empty payloads");
      Registration.Register_Routine
        (T, Test_Binary_Payload'Access,
         "Deflate_Raw preserves binary payloads");
      Registration.Register_Routine
        (T, Test_Git_Shaped_Payload'Access,
         "Deflate_Raw handles Git-shaped payloads");
      Registration.Register_Routine
        (T, Test_Repeated_Payload'Access,
         "Deflate_Raw handles repeated payloads");
      Registration.Register_Routine
        (T, Test_Large_Payload'Access,
         "Deflate_Raw handles large payloads");
      Registration.Register_Routine
        (T, Test_Deterministic'Access,
         "Deflate_Raw is deterministic");
      Registration.Register_Routine
        (T, Test_File_Stored'Access,
         "Deflate_Raw bridge file Stored roundtrips");
      Registration.Register_Routine
        (T, Test_File_Fixed'Access,
         "Deflate_Raw bridge file Fixed roundtrips");
      Registration.Register_Routine
        (T, Test_File_Dynamic'Access,
         "Deflate_Raw bridge file Dynamic roundtrips");
      Registration.Register_Routine
        (T, Test_File_Auto'Access,
         "Deflate_Raw bridge file Auto roundtrips");
      Registration.Register_Routine
        (T, Test_File_Missing_Input'Access,
         "Deflate_Raw_File missing input status");
      Registration.Register_Routine
        (T, Test_File_Output_Failure'Access,
         "Deflate_Raw_File output failure status");
   end Register_Tests;
end Zlib_Deflate_Raw_Bridge_Tests;
