with Ada.Containers.Vectors;
with Ada.Streams;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;
with Zlib_Fixture_Data;

package body Zlib_Streaming_Compress_Auto_Tests is
   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Offset;
   use type Zlib.Byte;
   use type Zlib.Header_Type;
   use type Zlib.Status_Code;

   package F renames Zlib_Fixture_Data;

   package Stream_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Ada.Streams.Stream_Element);

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib streaming Auto compression");
   end Name;

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

   procedure Append_Output
     (Output : in out Stream_Vectors.Vector;
      Buffer : Ada.Streams.Stream_Element_Array;
      Last   : Ada.Streams.Stream_Element_Offset)
   is
      Count : constant Natural := Produced (Buffer, Last);
   begin
      for I in Buffer'First .. Buffer'First + Ada.Streams.Stream_Element_Offset (Count) - 1 loop
         Output.Append (Buffer (I));
      end loop;
   end Append_Output;

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

   function To_Bytes
     (Data : Stream_Vectors.Vector)
      return Zlib.Byte_Array
   is
   begin
      if Data.Is_Empty then
         return [1 .. 0 => 0];
      end if;

      declare
         Result : Zlib.Byte_Array (1 .. Natural (Data.Length));
         Index  : Natural := Result'First;
      begin
         for B of Data loop
            Result (Index) := Zlib.Byte (B);
            Index := Index + 1;
         end loop;
         return Result;
      end;
   end To_Bytes;

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

   function Compress_All
     (Input              : Zlib.Byte_Array;
      Header             : Zlib.Header_Type := Zlib.Zlib_Header;
      Mode               : Zlib.Compression_Mode := Zlib.Auto;
      Input_Chunk_Size   : Positive := 1024;
      Output_Buffer_Size : Positive := 128;
      Finish_In_Compress : Boolean := False)
      return Zlib.Byte_Array
   is
      Filter     : Zlib.Compression_Filter_Type;
      Input_Data : constant Ada.Streams.Stream_Element_Array := To_Stream (Input);
      Output     : Stream_Vectors.Vector;
      Next_Input : Ada.Streams.Stream_Element_Offset := Input_Data'First;
      In_Last    : Ada.Streams.Stream_Element_Offset;
      Out_Last   : Ada.Streams.Stream_Element_Offset;
      Calls      : Natural := 0;
   begin
      Zlib.Deflate_Init (Filter, Header => Header, Mode => Mode);

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
            Append_Output (Output, Out_Buffer, Out_Last);

            if In_Last >= Next_Input then
               Next_Input := In_Last + 1;
            end if;

            Calls := Calls + 1;
            Assert (Calls < 1_000_000, "Auto compression input loop must make progress");
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
            Append_Output (Output, Out_Buffer, Out_Last);

            Calls := Calls + 1;
            Assert (Calls < 1_000_000, "Auto compression finish loop must make progress");
         end;
      end loop;

      Zlib.Compress_Close (Filter);
      return To_Bytes (Output);
   end Compress_All;

   function Large_Input return Zlib.Byte_Array is
      Result : Zlib.Byte_Array (1 .. 140_000);
   begin
      for I in Result'Range loop
         Result (I) := Zlib.Byte ((I * 29 + I / 31) mod 256);
      end loop;
      return Result;
   end Large_Input;

   procedure Assert_One_Shot_Inflates
     (Compressed : Zlib.Byte_Array;
      Header     : Zlib.Header_Type;
      Expected   : Zlib.Byte_Array;
      Message    : String)
   is
      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Compressed, Header, Status);
   begin
      Assert (Status = Zlib.Ok, Message & ": one-shot inflate status");
      Assert_Same (Output, Expected, Message & ": one-shot inflate payload");
   end Assert_One_Shot_Inflates;

   procedure Assert_Streaming_Inflates
     (Compressed : Zlib.Byte_Array;
      Header     : Zlib.Header_Type;
      Expected   : Zlib.Byte_Array;
      Message    : String)
   is
      Filter      : Zlib.Filter_Type;
      Input_Data  : constant Ada.Streams.Stream_Element_Array := To_Stream (Compressed);
      Output      : Stream_Vectors.Vector;
      Next_Input  : Ada.Streams.Stream_Element_Offset := Input_Data'First;
      In_Last     : Ada.Streams.Stream_Element_Offset;
      Out_Last    : Ada.Streams.Stream_Element_Offset;
      Calls       : Natural := 0;
   begin
      Zlib.Inflate_Init (Filter, Header => Header);
      while Input_Data'Length > 0 and then Next_Input <= Input_Data'Last loop
         declare
            Chunk_Last : constant Ada.Streams.Stream_Element_Offset :=
              Ada.Streams.Stream_Element_Offset'Min (Input_Data'Last, Next_Input + 2);
            Out_Buffer : Ada.Streams.Stream_Element_Array (1 .. 3);
         begin
            Zlib.Translate
              (Filter, Input_Data (Next_Input .. Chunk_Last), In_Last,
               Out_Buffer, Out_Last,
               Flush => (if Chunk_Last = Input_Data'Last then Zlib.Finish else Zlib.No_Flush));
            Append_Output (Output, Out_Buffer, Out_Last);
            if In_Last >= Next_Input then
               Next_Input := In_Last + 1;
            end if;
            Calls := Calls + 1;
            Assert (Calls < 1_000_000, Message & ": streaming inflate must progress");
         end;
      end loop;
      while not Zlib.Stream_End (Filter) loop
         declare
            Out_Buffer : Ada.Streams.Stream_Element_Array (1 .. 3);
         begin
            Zlib.Flush (Filter, Out_Buffer, Out_Last, Flush => Zlib.Finish);
            Append_Output (Output, Out_Buffer, Out_Last);
            Calls := Calls + 1;
            Assert (Calls < 1_000_000, Message & ": streaming flush must progress");
         end;
      end loop;
      Zlib.Close (Filter);
      Assert_Same (To_Bytes (Output), Expected, Message & ": streaming inflate payload");
   end Assert_Streaming_Inflates;

   procedure Expect_Roundtrip
     (Input              : Zlib.Byte_Array;
      Header             : Zlib.Header_Type;
      Label              : String;
      Input_Chunk_Size   : Positive := 3;
      Output_Buffer_Size : Positive := 5;
      Finish_In_Compress : Boolean := False)
   is
      Compressed : constant Zlib.Byte_Array :=
        Compress_All
          (Input,
           Header             => Header,
           Mode               => Zlib.Auto,
           Input_Chunk_Size   => Input_Chunk_Size,
           Output_Buffer_Size => Output_Buffer_Size,
           Finish_In_Compress => Finish_In_Compress);
   begin
      if Header = Zlib.GZip then
         Assert (Compressed (Compressed'First) = 16#1F#, Label & ": gzip ID1");
         Assert (Compressed (Compressed'First + 1) = 16#8B#, Label & ": gzip ID2");
      else
         Assert (Compressed (Compressed'First) = 16#78#, Label & ": zlib CMF");
      end if;
      Assert_One_Shot_Inflates (Compressed, Header, Input, Label);
      Assert_Streaming_Inflates (Compressed, Header, Input, Label);
   end Expect_Roundtrip;

   procedure Test_Zlib_Empty (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Expect_Roundtrip ([1 .. 0 => 0], Zlib.Zlib_Header, "Auto zlib empty input");
   end Test_Zlib_Empty;

   procedure Test_Zlib_Hello (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Expect_Roundtrip (F.Plain_Stored, Zlib.Zlib_Header, "Auto zlib hello");
   end Test_Zlib_Hello;

   procedure Test_Zlib_Binary (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Expect_Roundtrip (F.Plain_Binary, Zlib.Zlib_Header, "Auto zlib binary payload");
   end Test_Zlib_Binary;

   procedure Test_Zlib_Git_Shaped (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Expect_Roundtrip (F.Plain_Git_Blob, Zlib.Default, "Auto zlib Git-shaped payload");
   end Test_Zlib_Git_Shaped;

   procedure Test_GZip_Empty (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Expect_Roundtrip ([1 .. 0 => 0], Zlib.GZip, "Auto gzip empty input");
   end Test_GZip_Empty;

   procedure Test_GZip_Hello (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Expect_Roundtrip (F.Plain_Stored, Zlib.GZip, "Auto gzip hello");
   end Test_GZip_Hello;

   procedure Test_GZip_Binary (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Expect_Roundtrip (F.Plain_Binary, Zlib.GZip, "Auto gzip binary payload");
   end Test_GZip_Binary;

   procedure Test_One_Byte_Buffers (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Expect_Roundtrip
        (F.Plain_Git_Blob,
         Zlib.Zlib_Header,
         "Auto one-byte input and output buffers",
         Input_Chunk_Size   => 1,
         Output_Buffer_Size => 1,
         Finish_In_Compress => True);
   end Test_One_Byte_Buffers;

   procedure Test_Large_Input_Multiple_Blocks (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array := Large_Input;
   begin
      Expect_Roundtrip
        (Input,
         Zlib.Zlib_Header,
         "Auto large input multiple blocks",
         Input_Chunk_Size   => 257,
         Output_Buffer_Size => 7);
   end Test_Large_Input_Multiple_Blocks;

   procedure Test_Deterministic_Repeated_Runs (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      A : constant Zlib.Byte_Array :=
        Compress_All
          (F.Plain_Large_Repeated,
           Header             => Zlib.Zlib_Header,
           Input_Chunk_Size   => 11,
           Output_Buffer_Size => 13);
      B : constant Zlib.Byte_Array :=
        Compress_All
          (F.Plain_Large_Repeated,
           Header             => Zlib.Zlib_Header,
           Input_Chunk_Size   => 11,
           Output_Buffer_Size => 13);
      C : constant Zlib.Byte_Array :=
        Compress_All
          (F.Plain_Large_Repeated,
           Header             => Zlib.GZip,
           Input_Chunk_Size   => 11,
           Output_Buffer_Size => 13);
      D : constant Zlib.Byte_Array :=
        Compress_All
          (F.Plain_Large_Repeated,
           Header             => Zlib.GZip,
           Input_Chunk_Size   => 11,
           Output_Buffer_Size => 13);
   begin
      Assert_Same (A, B, "Auto zlib deterministic repeated runs");
      Assert_Same (C, D, "Auto gzip deterministic repeated runs");
   end Test_Deterministic_Repeated_Runs;

   procedure Test_Default_Header_Roundtrip (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Expect_Roundtrip
        (F.Plain_Git_Blob,
         Zlib.Default,
         "Auto default header aliases zlib header",
         Input_Chunk_Size   => 2,
         Output_Buffer_Size => 3);
   end Test_Default_Header_Roundtrip;

   procedure Test_Auto_Uses_Scored_Block_Selection (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Z_Auto : constant Zlib.Byte_Array :=
        Compress_All
          (F.Plain_Binary,
           Header             => Zlib.Zlib_Header,
           Mode               => Zlib.Auto,
           Input_Chunk_Size   => 17,
           Output_Buffer_Size => 5);
      G_Auto : constant Zlib.Byte_Array :=
        Compress_All
          (F.Plain_Binary,
           Header             => Zlib.GZip,
           Mode               => Zlib.Auto,
           Input_Chunk_Size   => 17,
           Output_Buffer_Size => 5);
   begin
      Assert_One_Shot_Inflates
        (Z_Auto, Zlib.Zlib_Header, F.Plain_Binary,
         "Auto zlib uses a valid scored block choice");
      Assert_One_Shot_Inflates
        (G_Auto, Zlib.GZip, F.Plain_Binary,
         "Auto gzip uses a valid scored block choice");
   end Test_Auto_Uses_Scored_Block_Selection;

   procedure Test_Empty_Input_Finish_In_Compress
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Compression_Filter_Type;
      Input    : constant Ada.Streams.Stream_Element_Array (1 .. 0) := [1 .. 0 => 0];
      Output   : Stream_Vectors.Vector;
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Calls    : Natural := 0;
   begin
      Zlib.Deflate_Init (Filter, Header => Zlib.Zlib_Header, Mode => Zlib.Auto);
      while not Zlib.Compress_Stream_End (Filter) loop
         declare
            Out_Buffer : Ada.Streams.Stream_Element_Array (1 .. 1);
         begin
            Zlib.Compress
              (Filter, Input, In_Last, Out_Buffer, Out_Last, Flush => Zlib.Finish);
            Append_Output (Output, Out_Buffer, Out_Last);
            Calls := Calls + 1;
            Assert (Calls < 1_000_000, "empty Auto Finish-in-Compress must progress");
         end;
      end loop;
      Zlib.Compress_Close (Filter);
      Assert_One_Shot_Inflates
        (To_Bytes (Output), Zlib.Zlib_Header, [1 .. 0 => 0],
         "empty Auto Finish-in-Compress");
   end Test_Empty_Input_Finish_In_Compress;

   procedure Test_Raw_Deflate_Auto_Roundtrips
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Compressed : constant Zlib.Byte_Array :=
        Compress_All
          (F.Plain_Binary,
           Header             => Zlib.Raw_Deflate,
           Mode               => Zlib.Auto,
           Input_Chunk_Size   => 1,
           Output_Buffer_Size => 1);
   begin
      Assert_One_Shot_Inflates
        (Compressed, Zlib.Raw_Deflate, F.Plain_Binary,
         "Auto Raw_Deflate compression");
      Assert_Streaming_Inflates
        (Compressed, Zlib.Raw_Deflate, F.Plain_Binary,
         "Auto Raw_Deflate streaming compression");
   end Test_Raw_Deflate_Auto_Roundtrips;

   procedure Test_Stream_End_Semantics (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Filter   : Zlib.Compression_Filter_Type;
      Input    : constant Ada.Streams.Stream_Element_Array (1 .. 1) := [1 => 42];
      Out_Data : Ada.Streams.Stream_Element_Array (1 .. 1);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Raised   : Boolean := False;
   begin
      Zlib.Deflate_Init (Filter, Header => Zlib.Zlib_Header, Mode => Zlib.Auto);
      Zlib.Compress (Filter, Input, In_Last, Out_Data, Out_Last, Flush => Zlib.No_Flush);
      Assert (not Zlib.Compress_Stream_End (Filter), "Auto stream end false before Finish");

      while not Zlib.Compress_Stream_End (Filter) loop
         Zlib.Compress_Flush (Filter, Out_Data, Out_Last, Flush => Zlib.Finish);
      end loop;
      Assert (Zlib.Compress_Stream_End (Filter), "Auto stream end true after Finish");
      Zlib.Compress_Close (Filter);

      Zlib.Deflate_Init (Filter, Header => Zlib.Zlib_Header, Mode => Zlib.Auto);
      begin
         Zlib.Compress_Close (Filter, Ignore_Error => False);
      exception
         when Zlib.Zlib_Error =>
            Raised := True;
      end;
      Assert (Raised, "Auto close before Finish must raise Zlib_Error");
      Zlib.Deflate_Init (Filter, Header => Zlib.Zlib_Header, Mode => Zlib.Auto);
      Zlib.Compress_Close (Filter, Ignore_Error => True);
   end Test_Stream_End_Semantics;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_Zlib_Empty'Access,
         "streaming Auto zlib empty input roundtrips");
      Registration.Register_Routine
        (T, Test_Zlib_Hello'Access,
         "streaming Auto zlib hello roundtrips");
      Registration.Register_Routine
        (T, Test_Zlib_Binary'Access,
         "streaming Auto zlib binary payload roundtrips");
      Registration.Register_Routine
        (T, Test_Zlib_Git_Shaped'Access,
         "streaming Auto zlib Git-shaped payload roundtrips");
      Registration.Register_Routine
        (T, Test_GZip_Empty'Access,
         "streaming Auto gzip empty input roundtrips");
      Registration.Register_Routine
        (T, Test_GZip_Hello'Access,
         "streaming Auto gzip hello roundtrips");
      Registration.Register_Routine
        (T, Test_GZip_Binary'Access,
         "streaming Auto gzip binary payload roundtrips");
      Registration.Register_Routine
        (T, Test_One_Byte_Buffers'Access,
         "Auto input chunk size 1 and output buffer size 1");
      Registration.Register_Routine
        (T, Test_Large_Input_Multiple_Blocks'Access,
         "large Auto input emits multiple valid blocks");
      Registration.Register_Routine
        (T, Test_Deterministic_Repeated_Runs'Access,
         "Auto output deterministic across repeated runs");
      Registration.Register_Routine
        (T, Test_Default_Header_Roundtrip'Access,
         "streaming Auto default header roundtrips");
      Registration.Register_Routine
        (T, Test_Auto_Uses_Scored_Block_Selection'Access,
         "Auto uses scored block selection for zlib and gzip");
      Registration.Register_Routine
        (T, Test_Empty_Input_Finish_In_Compress'Access,
         "Auto empty input can finish from Compress");
      Registration.Register_Routine
        (T, Test_Raw_Deflate_Auto_Roundtrips'Access,
         "Auto Raw_Deflate compression roundtrips");
      Registration.Register_Routine
        (T, Test_Stream_End_Semantics'Access,
         "Auto Compress_Stream_End semantics remain correct");
   end Register_Tests;
end Zlib_Streaming_Compress_Auto_Tests;
