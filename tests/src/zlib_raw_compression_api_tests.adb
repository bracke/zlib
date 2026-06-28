with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;

package body Zlib_Raw_Compression_Api_Tests is
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
      return AUnit.Format ("Zlib raw Deflate stored compression");
   end Name;

   function Empty return Zlib.Byte_Array is
      Result : constant Zlib.Byte_Array (1 .. 0) := [others => 0];
   begin
      return Result;
   end Empty;

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
            Message & ": byte mismatch");
      end loop;
   end Assert_Same;

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
               Buffer
                 (Ada.Streams.Stream_Element_Offset (I - Data'First) + 1) :=
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
            Last : Ada.Streams.Stream_Element_Offset;
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

   function Compress_Raw_Stored
     (Input              : Zlib.Byte_Array;
      Mode               : Zlib.Compression_Mode := Zlib.Stored;
      Input_Chunk_Size   : Positive := 1024;
      Output_Buffer_Size : Positive := 64;
      Finish_In_Compress : Boolean := False)
      return Zlib.Byte_Array
   is
      Filter     : Zlib.Compression_Filter_Type;
      Input_Data : constant Ada.Streams.Stream_Element_Array := To_Stream (Input);
      Output     : Zlib.Byte_Array (1 .. Input'Length * 2 + 2_048 + ((Input'Length / 65_535) + 2) * 5);
      Out_Count  : Natural := 0;
      Next_Input : Ada.Streams.Stream_Element_Offset := Input_Data'First;
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
            Output (Out_Count) := Zlib.Byte (Buffer (I));
         end loop;
      end Append;
   begin
      Zlib.Deflate_Init (Filter, Header => Zlib.Raw_Deflate, Mode => Mode);

      while Input_Data'Length > 0 and then Next_Input <= Input_Data'Last loop
         declare
            Chunk_Last : constant Ada.Streams.Stream_Element_Offset :=
              Ada.Streams.Stream_Element_Offset'Min
                (Input_Data'Last,
                 Next_Input + Ada.Streams.Stream_Element_Offset (Input_Chunk_Size) - 1);
            Out_Buffer : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Output_Buffer_Size));
            Flush_Mode : constant Zlib.Flush_Mode :=
              (if Finish_In_Compress and then Chunk_Last = Input_Data'Last
               then Zlib.Finish
               else Zlib.No_Flush);
         begin
            Zlib.Compress
              (Filter   => Filter,
               In_Data  => Input_Data (Next_Input .. Chunk_Last),
               In_Last  => In_Last,
               Out_Data => Out_Buffer,
               Out_Last => Out_Last,
               Flush    => Flush_Mode);
            Append (Out_Buffer, Out_Last);

            if In_Last >= Next_Input then
               Next_Input := In_Last + 1;
            end if;

            Calls := Calls + 1;
            Assert (Calls < 1_000_000, "raw stored input loop must make progress");
         end;
      end loop;

      while not Zlib.Compress_Stream_End (Filter) loop
         declare
            Out_Buffer : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Output_Buffer_Size));
         begin
            Zlib.Compress_Flush
              (Filter   => Filter,
               Out_Data => Out_Buffer,
               Out_Last => Out_Last,
               Flush    => Zlib.Finish);
            Append (Out_Buffer, Out_Last);

            Calls := Calls + 1;
            Assert (Calls < 1_000_000, "raw stored finish loop must make progress");
         end;
      end loop;

      Zlib.Compress_Close (Filter);
      if Out_Count = 0 then
         return Empty;
      else
         return Output (1 .. Out_Count);
      end if;
   end Compress_Raw_Stored;

   procedure Assert_Raw_Inflates_To
     (Compressed : Zlib.Byte_Array;
      Expected   : Zlib.Byte_Array;
      Message    : String)
   is
      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Compressed, Zlib.Raw_Deflate, Status);
   begin
      Assert (Status = Zlib.Ok, Message & ": raw inflate status must be Ok");
      Assert_Same (Output, Expected, Message);
   end Assert_Raw_Inflates_To;

   procedure Copy_Output
     (Out_Data    : Ada.Streams.Stream_Element_Array;
      Out_Last    : Ada.Streams.Stream_Element_Offset;
      Result      : in out Zlib.Byte_Array;
      Result_Last : in out Natural)
   is
      Count : constant Natural := Produced (Out_Data, Out_Last);
   begin
      for I in Out_Data'First .. Out_Data'First + Ada.Streams.Stream_Element_Offset (Count) - 1 loop
         Result_Last := Result_Last + 1;
         Result (Result_Last) := Zlib.Byte (Out_Data (I));
      end loop;
   end Copy_Output;

   procedure Assert_Streaming_Raw_Inflates_To
     (Compressed : Zlib.Byte_Array;
      Expected   : Zlib.Byte_Array;
      Message    : String)
   is
      Filter      : Zlib.Filter_Type;
      Result      : Zlib.Byte_Array (1 .. Expected'Length + 32);
      Result_Last : Natural := 0;
      Pos         : Natural := Compressed'First;
   begin
      Zlib.Inflate_Init (Filter, Zlib.Raw_Deflate);

      while Pos <= Compressed'Last loop
         declare
            In_Data : constant Ada.Streams.Stream_Element_Array (1 .. 1) :=
              [1 => Ada.Streams.Stream_Element (Compressed (Pos))];
            Out_Data : Ada.Streams.Stream_Element_Array (1 .. 1);
            In_Last  : Ada.Streams.Stream_Element_Offset;
            Out_Last : Ada.Streams.Stream_Element_Offset;
         begin
            Zlib.Translate (Filter, In_Data, In_Last, Out_Data, Out_Last);
            Copy_Output (Out_Data, Out_Last, Result, Result_Last);
            if In_Last /= Before_First (In_Data) then
               Pos := Pos + 1;
            end if;
         end;
      end loop;

      while not Zlib.Stream_End (Filter) loop
         declare
            Empty_In : constant Ada.Streams.Stream_Element_Array (1 .. 0) := [];
            Out_Data : Ada.Streams.Stream_Element_Array (1 .. 1);
            In_Last  : Ada.Streams.Stream_Element_Offset;
            Out_Last : Ada.Streams.Stream_Element_Offset;
         begin
            Zlib.Translate (Filter, Empty_In, In_Last, Out_Data, Out_Last, Zlib.Finish);
            Copy_Output (Out_Data, Out_Last, Result, Result_Last);
         end;
      end loop;

      Zlib.Close (Filter);
      if Result_Last = 0 then
         Assert_Same (Empty, Expected, Message);
      else
         Assert_Same (Result (1 .. Result_Last), Expected, Message);
      end if;
   end Assert_Streaming_Raw_Inflates_To;

   procedure Assert_Rejected_By
     (Compressed : Zlib.Byte_Array;
      Header     : Zlib.Header_Type;
      Message    : String)
   is
      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Compressed, Header, Status);
      pragma Unreferenced (Output);
   begin
      Assert (Status /= Zlib.Ok, Message);
   end Assert_Rejected_By;

   function Hello return Zlib.Byte_Array is
   begin
      return
        [1 => Zlib.Byte (Character'Pos ('h')),
         2 => Zlib.Byte (Character'Pos ('e')),
         3 => Zlib.Byte (Character'Pos ('l')),
         4 => Zlib.Byte (Character'Pos ('l')),
         5 => Zlib.Byte (Character'Pos ('o'))];
   end Hello;

   procedure Test_Deflate_Raw_Stored_Empty
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code := Zlib.Ok;
      Output : constant Zlib.Byte_Array :=
        Zlib.Deflate_Raw (Empty, Mode => Zlib.Stored, Status => Status);
      Expected : constant Zlib.Byte_Array := [1 => 16#01#, 2 => 0, 3 => 0, 4 => 16#FF#, 5 => 16#FF#];
   begin
      Assert (Status = Zlib.Ok, "Deflate_Raw Stored empty must succeed");
      Assert_Same (Output, Expected, "empty raw stored output");
      Assert_Raw_Inflates_To (Output, Empty, "empty raw stored roundtrip");
      Assert_Streaming_Raw_Inflates_To (Output, Empty, "empty raw stored streaming inflate roundtrip");
   end Test_Deflate_Raw_Stored_Empty;

   procedure Test_Deflate_Raw_Stored_Hello
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code := Zlib.Ok;
      Input  : constant Zlib.Byte_Array := Hello;
      Output : constant Zlib.Byte_Array :=
        Zlib.Deflate_Raw (Input, Mode => Zlib.Stored, Status => Status);
   begin
      Assert (Status = Zlib.Ok, "Deflate_Raw Stored hello must succeed");
      Assert (Output (Output'First) = 16#01#, "raw stored hello must start with final stored block");
      Assert_Raw_Inflates_To (Output, Input, "hello raw stored roundtrip");
      Assert_Streaming_Raw_Inflates_To (Output, Input, "hello raw stored streaming inflate roundtrip");
   end Test_Deflate_Raw_Stored_Hello;

   procedure Test_Deflate_Raw_Stored_Binary
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code := Zlib.Ok;
      Input  : Zlib.Byte_Array (1 .. 512);
   begin
      for I in Input'Range loop
         Input (I) := Zlib.Byte ((I * 37) mod 256);
      end loop;
      declare
         Output : constant Zlib.Byte_Array :=
           Zlib.Deflate_Raw (Input, Mode => Zlib.Stored, Status => Status);
      begin
         Assert (Status = Zlib.Ok, "Deflate_Raw Stored binary must succeed");
         Assert_Raw_Inflates_To (Output, Input, "binary raw stored roundtrip");
      end;
   end Test_Deflate_Raw_Stored_Binary;

   procedure Test_Deflate_Raw_Fixed_Empty
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code := Zlib.Ok;
      Output : constant Zlib.Byte_Array :=
        Zlib.Deflate_Raw (Empty, Mode => Zlib.Fixed, Status => Status);
   begin
      Assert (Status = Zlib.Ok, "Deflate_Raw Fixed empty must succeed");
      Assert_Raw_Inflates_To (Output, Empty, "empty raw fixed roundtrip");
      Assert_Streaming_Raw_Inflates_To (Output, Empty, "empty raw fixed streaming inflate roundtrip");
      Assert_Rejected_By (Output, Zlib.Zlib_Header, "empty raw fixed must not be zlib-wrapped");
      Assert_Rejected_By (Output, Zlib.GZip, "empty raw fixed must not be gzip-wrapped");
   end Test_Deflate_Raw_Fixed_Empty;

   procedure Test_Deflate_Raw_Fixed_Hello
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code := Zlib.Ok;
      Input  : constant Zlib.Byte_Array := Hello;
      Output : constant Zlib.Byte_Array :=
        Zlib.Deflate_Raw (Input, Mode => Zlib.Fixed, Status => Status);
   begin
      Assert (Status = Zlib.Ok, "Deflate_Raw Fixed hello must succeed");
      Assert_Raw_Inflates_To (Output, Input, "hello raw fixed roundtrip");
      Assert_Streaming_Raw_Inflates_To (Output, Input, "hello raw fixed streaming inflate roundtrip");
   end Test_Deflate_Raw_Fixed_Hello;

   procedure Test_Deflate_Raw_Fixed_Binary
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code := Zlib.Ok;
      Input  : Zlib.Byte_Array (1 .. 512);
   begin
      for I in Input'Range loop
         Input (I) := Zlib.Byte ((I * 37) mod 256);
      end loop;
      declare
         Output : constant Zlib.Byte_Array :=
           Zlib.Deflate_Raw (Input, Mode => Zlib.Fixed, Status => Status);
      begin
         Assert (Status = Zlib.Ok, "Deflate_Raw Fixed binary must succeed");
         Assert_Raw_Inflates_To (Output, Input, "binary raw fixed roundtrip");
      end;
   end Test_Deflate_Raw_Fixed_Binary;

   procedure Test_Deflate_Raw_File_Stored
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input_Path  : constant String := "raw_compression_api_input.bin";
      Output_Path : constant String := "raw_compression_api_output.deflate";
      Status      : Zlib.Status_Code := Zlib.Ok;
      Input       : constant Zlib.Byte_Array := Hello;
   begin
      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Output_Path);
      Write_File (Input_Path, Input);

      Zlib.Deflate_Raw_File
        (Input_Path  => Input_Path,
         Output_Path => Output_Path,
         Mode        => Zlib.Stored,
         Status      => Status);

      Assert (Status = Zlib.Ok, "Deflate_Raw_File Stored must succeed");
      Assert_Raw_Inflates_To (Read_File (Output_Path), Input, "raw stored file roundtrip");

      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Output_Path);
   end Test_Deflate_Raw_File_Stored;

   procedure Test_Deflate_Raw_File_Fixed
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input_Path  : constant String := "raw_compression_api_input_fixed.bin";
      Output_Path : constant String := "raw_compression_api_output_fixed.deflate";
      Status      : Zlib.Status_Code := Zlib.Ok;
      Input       : constant Zlib.Byte_Array := Hello;
   begin
      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Output_Path);
      Write_File (Input_Path, Input);

      Zlib.Deflate_Raw_File
        (Input_Path  => Input_Path,
         Output_Path => Output_Path,
         Mode        => Zlib.Fixed,
         Status      => Status);

      Assert (Status = Zlib.Ok, "Deflate_Raw_File Fixed must succeed");
      Assert_Raw_Inflates_To (Read_File (Output_Path), Input, "raw fixed file roundtrip");

      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Output_Path);
   end Test_Deflate_Raw_File_Fixed;

   procedure Test_Deflate_Init_Raw_Accepted
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter : Zlib.Compression_Filter_Type;
   begin
      Zlib.Deflate_Init (Filter, Header => Zlib.Raw_Deflate, Mode => Zlib.Stored);
      Assert (Zlib.Is_Open (Filter), "Deflate_Init must accept Raw_Deflate Stored");
      Zlib.Compress_Close (Filter, Ignore_Error => True);
      Zlib.Deflate_Init (Filter, Header => Zlib.Raw_Deflate, Mode => Zlib.Fixed);
      Assert (Zlib.Is_Open (Filter), "Deflate_Init must accept Raw_Deflate Fixed");
      Zlib.Compress_Close (Filter, Ignore_Error => True);
      Zlib.Deflate_Init (Filter, Header => Zlib.Raw_Deflate, Mode => Zlib.Dynamic);
      Assert (Zlib.Is_Open (Filter), "Deflate_Init must accept Raw_Deflate Dynamic");
      Zlib.Compress_Close (Filter, Ignore_Error => True);
      Zlib.Deflate_Init (Filter, Header => Zlib.Raw_Deflate, Mode => Zlib.Auto);
      Assert (Zlib.Is_Open (Filter), "Deflate_Init must accept Raw_Deflate Auto");
      Zlib.Compress_Close (Filter, Ignore_Error => True);
   end Test_Deflate_Init_Raw_Accepted;

   procedure Test_Raw_Streaming_Stored_Empty
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Output : constant Zlib.Byte_Array :=
        Compress_Raw_Stored (Empty, Output_Buffer_Size => 1);
      Expected : constant Zlib.Byte_Array := [1 => 16#01#, 2 => 0, 3 => 0, 4 => 16#FF#, 5 => 16#FF#];
   begin
      Assert_Same (Output, Expected, "streaming raw stored empty output");
      Assert_Raw_Inflates_To (Output, Empty, "streaming raw stored empty roundtrip");
      Assert_Streaming_Raw_Inflates_To (Output, Empty, "streaming raw stored empty streaming inflate roundtrip");
   end Test_Raw_Streaming_Stored_Empty;

   procedure Test_Raw_Streaming_Stored_Hello
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input  : constant Zlib.Byte_Array := Hello;
      Output : constant Zlib.Byte_Array :=
        Compress_Raw_Stored (Input, Input_Chunk_Size => 1, Output_Buffer_Size => 1);
   begin
      Assert_Raw_Inflates_To (Output, Input, "streaming raw stored hello roundtrip");
      Assert_Streaming_Raw_Inflates_To (Output, Input, "streaming raw stored hello streaming inflate roundtrip");
   end Test_Raw_Streaming_Stored_Hello;

   procedure Test_Raw_Streaming_Stored_Git_Shaped
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array :=
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
   begin
      Assert_Raw_Inflates_To
        (Compress_Raw_Stored (Input, Input_Chunk_Size => 1, Output_Buffer_Size => 1),
         Input,
         "Git-shaped raw stored roundtrip");
   end Test_Raw_Streaming_Stored_Git_Shaped;

   procedure Test_Raw_Streaming_Fixed_Empty
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Output : constant Zlib.Byte_Array :=
        Compress_Raw_Stored (Empty, Mode => Zlib.Fixed, Output_Buffer_Size => 1);
   begin
      Assert_Raw_Inflates_To (Output, Empty, "streaming raw fixed empty roundtrip");
      Assert_Streaming_Raw_Inflates_To (Output, Empty, "streaming raw fixed empty streaming inflate roundtrip");
      Assert_Rejected_By (Output, Zlib.Zlib_Header, "streaming raw fixed empty must not be zlib-wrapped");
      Assert_Rejected_By (Output, Zlib.GZip, "streaming raw fixed empty must not be gzip-wrapped");
   end Test_Raw_Streaming_Fixed_Empty;

   procedure Test_Raw_Streaming_Fixed_Hello
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input  : constant Zlib.Byte_Array := Hello;
      Output : constant Zlib.Byte_Array :=
        Compress_Raw_Stored (Input, Mode => Zlib.Fixed, Input_Chunk_Size => 1, Output_Buffer_Size => 1);
   begin
      Assert_Raw_Inflates_To (Output, Input, "streaming raw fixed hello roundtrip");
      Assert_Streaming_Raw_Inflates_To (Output, Input, "streaming raw fixed hello streaming inflate roundtrip");
   end Test_Raw_Streaming_Fixed_Hello;

   procedure Test_Raw_Streaming_Fixed_Binary
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input : Zlib.Byte_Array (1 .. 512);
   begin
      for I in Input'Range loop
         Input (I) := Zlib.Byte ((I * 91) mod 256);
      end loop;
      Assert_Raw_Inflates_To
        (Compress_Raw_Stored (Input, Mode => Zlib.Fixed, Input_Chunk_Size => 1, Output_Buffer_Size => 1),
         Input,
         "streaming raw fixed binary roundtrip");
   end Test_Raw_Streaming_Fixed_Binary;

   procedure Test_Raw_Streaming_Fixed_Git_Shaped
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array :=
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
   begin
      Assert_Raw_Inflates_To
        (Compress_Raw_Stored (Input, Mode => Zlib.Fixed, Input_Chunk_Size => 1, Output_Buffer_Size => 1),
         Input,
         "Git-shaped raw fixed roundtrip");
   end Test_Raw_Streaming_Fixed_Git_Shaped;

   procedure Test_Raw_Streaming_Fixed_Large_Splits
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input : Zlib.Byte_Array (1 .. 70_000);
   begin
      for I in Input'Range loop
         Input (I) := Zlib.Byte (I mod 251);
      end loop;
      Assert_Raw_Inflates_To
        (Compress_Raw_Stored (Input, Mode => Zlib.Fixed, Input_Chunk_Size => 4096, Output_Buffer_Size => 1),
         Input,
         "large raw fixed roundtrip");
   end Test_Raw_Streaming_Fixed_Large_Splits;

   procedure Test_Raw_Streaming_Large_Splits
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input : Zlib.Byte_Array (1 .. 70_000);
   begin
      for I in Input'Range loop
         Input (I) := Zlib.Byte (I mod 251);
      end loop;

      declare
         Output     : constant Zlib.Byte_Array :=
           Compress_Raw_Stored (Input, Input_Chunk_Size => 4096, Output_Buffer_Size => 1);
         Pos        : Natural := Output'First;
         Blocks     : Natural := 0;
         Final_Seen : Boolean := False;
      begin
         while not Final_Seen loop
            declare
               Header : constant Zlib.Byte := Output (Pos);
               Len    : constant Natural :=
                 Natural (Output (Pos + 1)) + 256 * Natural (Output (Pos + 2));
               NLen   : constant Natural :=
                 Natural (Output (Pos + 3)) + 256 * Natural (Output (Pos + 4));
            begin
               Assert ((Header and 16#FE#) = 0, "raw stored block BTYPE must be 00");
               Assert ((Len + NLen) = 65_535, "raw stored NLEN must complement LEN");
               Blocks := Blocks + 1;
               Final_Seen := (Header and 1) = 1;
               Pos := Pos + 5 + Len;
            end;
         end loop;
         Assert (Blocks >= 2, "large raw stored output must split blocks");
         Assert_Raw_Inflates_To (Output, Input, "large raw stored roundtrip");
      end;
   end Test_Raw_Streaming_Large_Splits;

   procedure Test_Raw_Stream_End_Drain_And_Close
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Compression_Filter_Type;
      Input    : constant Ada.Streams.Stream_Element_Array (1 .. 1) := [1 => 42];
      Out_Data : Ada.Streams.Stream_Element_Array (1 .. 1);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Raised   : Boolean := False;
   begin
      Zlib.Deflate_Init (Filter, Header => Zlib.Raw_Deflate, Mode => Zlib.Stored);
      Zlib.Compress (Filter, Input, In_Last, Out_Data, Out_Last, Flush => Zlib.Finish);
      Assert (not Zlib.Compress_Stream_End (Filter), "raw stream end must be false before final block drains");
      while not Zlib.Compress_Stream_End (Filter) loop
         Zlib.Compress_Flush (Filter, Out_Data, Out_Last, Flush => Zlib.Finish);
      end loop;
      Assert (Zlib.Compress_Stream_End (Filter), "raw stream end must be true after final block drains");
      Zlib.Compress_Close (Filter);

      Zlib.Deflate_Init (Filter, Header => Zlib.Raw_Deflate, Mode => Zlib.Stored);
      begin
         Zlib.Compress_Close (Filter, Ignore_Error => False);
      exception
         when Zlib.Zlib_Error =>
            Raised := True;
      end;
      Assert (Raised, "raw Compress_Close before Finish must raise Zlib_Error");
   end Test_Raw_Stream_End_Drain_And_Close;

   procedure Test_Wrapper_Strictness
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code;
      Input  : constant Zlib.Byte_Array := Hello;
      Raw    : constant Zlib.Byte_Array := Zlib.Deflate_Raw (Input, Zlib.Fixed, Status);
   begin
      Assert (Status = Zlib.Ok, "raw wrapper strictness fixture must compress");
      Assert_Raw_Inflates_To (Raw, Input, "raw output accepted by raw inflate");
      declare
         Zlib_Out : constant Zlib.Byte_Array := Zlib.Deflate_Fixed (Input, Status);
      begin
         Assert (Status = Zlib.Ok, "zlib wrapper strictness fixture must compress");
         Assert_Rejected_By (Raw, Zlib.Zlib_Header, "raw output must be rejected as zlib");
         Assert_Rejected_By (Raw, Zlib.GZip, "raw output must be rejected as gzip");
         Assert_Rejected_By (Zlib_Out, Zlib.Raw_Deflate, "zlib output must be rejected as raw");
      end;
      declare
         GZip_Out : constant Zlib.Byte_Array := Zlib.GZip (Input, Zlib.Fixed, Status);
      begin
         Assert (Status = Zlib.Ok, "gzip wrapper strictness fixture must compress");
         Assert_Rejected_By (GZip_Out, Zlib.Raw_Deflate, "gzip output must be rejected as raw");
      end;
   end Test_Wrapper_Strictness;

   procedure Test_Deflate_Stored_And_GZip_Remain_Wrapped
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code;
      Zlib_Out : constant Zlib.Byte_Array := Zlib.Deflate_Stored (Hello, Status);
   begin
      Assert (Status = Zlib.Ok, "Deflate_Stored must still succeed");
      Assert (Zlib_Out (Zlib_Out'First) = 16#78#, "Deflate_Stored must remain zlib-wrapped");
      declare
         GZip_Out : constant Zlib.Byte_Array := Zlib.GZip (Hello, Zlib.Stored, Status);
      begin
         Assert (Status = Zlib.Ok, "GZip must still succeed");
         Assert (GZip_Out (GZip_Out'First) = 16#1F# and then GZip_Out (GZip_Out'First + 1) = 16#8B#,
                 "GZip must remain gzip-wrapped");
      end;
   end Test_Deflate_Stored_And_GZip_Remain_Wrapped;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_Deflate_Raw_Stored_Empty'Access,
         "Deflate_Raw Stored empty emits final empty stored block");
      Registration.Register_Routine
        (T, Test_Deflate_Raw_Stored_Hello'Access,
         "Deflate_Raw Stored hello roundtrips through raw inflate");
      Registration.Register_Routine
        (T, Test_Deflate_Raw_Stored_Binary'Access,
         "Deflate_Raw Stored binary payload roundtrips");
      Registration.Register_Routine
        (T, Test_Deflate_Raw_File_Stored'Access,
         "Deflate_Raw_File Stored roundtrips");
      Registration.Register_Routine
        (T, Test_Deflate_Raw_Fixed_Empty'Access,
         "Deflate_Raw Fixed empty roundtrips through raw inflate");
      Registration.Register_Routine
        (T, Test_Deflate_Raw_Fixed_Hello'Access,
         "Deflate_Raw Fixed hello roundtrips through raw inflate");
      Registration.Register_Routine
        (T, Test_Deflate_Raw_Fixed_Binary'Access,
         "Deflate_Raw Fixed binary payload roundtrips");
      Registration.Register_Routine
        (T, Test_Deflate_Raw_File_Fixed'Access,
         "Deflate_Raw_File Fixed roundtrips");
      Registration.Register_Routine
        (T, Test_Deflate_Init_Raw_Accepted'Access,
         "Deflate_Init Raw_Deflate modes are accepted");
      Registration.Register_Routine
        (T, Test_Raw_Streaming_Stored_Empty'Access,
         "Raw_Deflate Stored streaming empty emits final empty block");
      Registration.Register_Routine
        (T, Test_Raw_Streaming_Stored_Hello'Access,
         "Raw_Deflate Stored streaming hello supports one-byte buffers");
      Registration.Register_Routine
        (T, Test_Raw_Streaming_Stored_Git_Shaped'Access,
         "Raw_Deflate Stored streaming Git-shaped payload roundtrips");
      Registration.Register_Routine
        (T, Test_Raw_Streaming_Fixed_Empty'Access,
         "Raw_Deflate Fixed streaming empty emits final EOB block");
      Registration.Register_Routine
        (T, Test_Raw_Streaming_Fixed_Hello'Access,
         "Raw_Deflate Fixed streaming hello supports one-byte buffers");
      Registration.Register_Routine
        (T, Test_Raw_Streaming_Fixed_Binary'Access,
         "Raw_Deflate Fixed streaming binary payload roundtrips");
      Registration.Register_Routine
        (T, Test_Raw_Streaming_Fixed_Git_Shaped'Access,
         "Raw_Deflate Fixed streaming Git-shaped payload roundtrips");
      Registration.Register_Routine
        (T, Test_Raw_Streaming_Fixed_Large_Splits'Access,
         "Raw_Deflate Fixed streaming large input emits multiple blocks");
      Registration.Register_Routine
        (T, Test_Raw_Streaming_Large_Splits'Access,
         "Raw_Deflate Stored streaming large input splits blocks");
      Registration.Register_Routine
        (T, Test_Raw_Stream_End_Drain_And_Close'Access,
         "Raw_Deflate Stored streaming end and close semantics");
      Registration.Register_Routine
        (T, Test_Wrapper_Strictness'Access,
         "raw zlib gzip wrapper strictness is preserved");
      Registration.Register_Routine
        (T, Test_Deflate_Stored_And_GZip_Remain_Wrapped'Access,
         "Deflate_Stored and GZip remain wrapped");
   end Register_Tests;
end Zlib_Raw_Compression_Api_Tests;
