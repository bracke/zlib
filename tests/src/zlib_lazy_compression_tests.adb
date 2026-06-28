with Ada.Containers.Vectors;
with Ada.Streams;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;
with Zlib.LZ77_Matcher;

package body Zlib_Lazy_Compression_Tests is
   use type Ada.Streams.Stream_Element_Offset;
   use type Zlib.Byte;
   use type Zlib.Header_Type;
   use type Zlib.LZ77_Matcher.Match_Strategy;
   use type Zlib.Status_Code;

   package Byte_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Zlib.Byte);

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib lazy compression policy");
   end Name;

   function Bytes
     (S : String)
      return Zlib.Byte_Array
   is
      Result : Zlib.Byte_Array (1 .. S'Length);
   begin
      for I in S'Range loop
         Result (I - S'First + 1) := Zlib.Byte (Character'Pos (S (I)));
      end loop;
      return Result;
   end Bytes;

   function Payload return Zlib.Byte_Array is
      Result : Zlib.Byte_Array (1 .. 4096);
   begin
      for I in Result'Range loop
         if I mod 29 = 0 then
            Result (I) := Zlib.Byte ((I * 17) mod 256);
         elsif I mod 11 = 0 then
            Result (I) := Zlib.Byte (Character'Pos ('A') + (I mod 3));
         else
            Result (I) := Zlib.Byte (Character'Pos ('a') + (I mod 5));
         end if;
      end loop;
      return Result;
   end Payload;

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

   procedure Assert_Roundtrip
     (Input      : Zlib.Byte_Array;
      Compressed : Zlib.Byte_Array;
      Header     : Zlib.Header_Type;
      Message    : String)
   is
      Status   : Zlib.Status_Code := Zlib.Ok;
      Inflated : constant Zlib.Byte_Array :=
        (if Header = Zlib.Raw_Deflate or else Header = Zlib.GZip then
            Zlib.Inflate_With_Header (Compressed, Header, Status)
         else
            Zlib.Inflate (Compressed, Status));
   begin
      Assert (Status = Zlib.Ok, Message & ": inflate status");
      Assert_Same (Inflated, Input, Message & ": roundtrip");
   end Assert_Roundtrip;

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
     (Data : Byte_Vectors.Vector)
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
            Result (Index) := B;
            Index := Index + 1;
         end loop;
         return Result;
      end;
   end To_Bytes;

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

   procedure Append_Output
     (Output : in out Byte_Vectors.Vector;
      Buffer : Ada.Streams.Stream_Element_Array;
      Last   : Ada.Streams.Stream_Element_Offset)
   is
   begin
      if Last = Before_First (Buffer) then
         return;
      end if;

      for I in Buffer'First .. Last loop
         Output.Append (Zlib.Byte (Buffer (I)));
      end loop;
   end Append_Output;

   function Streaming_Compress
     (Input : Zlib.Byte_Array;
      Flush : Zlib.Flush_Mode)
      return Zlib.Byte_Array
   is
      Filter     : Zlib.Compression_Filter_Type;
      Input_Data : constant Ada.Streams.Stream_Element_Array := To_Stream (Input);
      Output     : Byte_Vectors.Vector;
      In_Last    : Ada.Streams.Stream_Element_Offset;
      Out_Last   : Ada.Streams.Stream_Element_Offset;
      Calls      : Natural := 0;
   begin
      Zlib.Deflate_Init
        (Filter => Filter,
         Header => Zlib.Zlib_Header,
         Level  => Zlib.Compression_Level'(6));

      declare
         Out_Data : Ada.Streams.Stream_Element_Array (1 .. 8192);
      begin
         Zlib.Compress
           (Filter   => Filter,
            In_Data  => Input_Data,
            In_Last  => In_Last,
            Out_Data => Out_Data,
            Out_Last => Out_Last,
            Flush    => Flush);
         Append_Output (Output, Out_Data, Out_Last);
         Assert (In_Last = Input_Data'Last, "lazy streaming flush must consume whole fixture");
      end;

      while not Zlib.Compress_Stream_End (Filter) loop
         declare
            Out_Data : Ada.Streams.Stream_Element_Array (1 .. 8192);
         begin
            Zlib.Compress_Flush
              (Filter   => Filter,
               Out_Data => Out_Data,
               Out_Last => Out_Last,
               Flush    => Zlib.Finish);
            Append_Output (Output, Out_Data, Out_Last);
            Calls := Calls + 1;
            Assert (Calls < 1000, "lazy streaming finish must make progress");
         end;
      end loop;

      Zlib.Compress_Close (Filter);
      return To_Bytes (Output);
   end Streaming_Compress;

   procedure Test_Dynamic_With_Lazy_Roundtrips
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input  : constant Zlib.Byte_Array := Payload;
      Status : Zlib.Status_Code := Zlib.Ok;
      Output : constant Zlib.Byte_Array := Zlib.Deflate_Dynamic (Input, Status);
   begin
      Assert (Status = Zlib.Ok, "dynamic lazy compression status");
      Assert_Roundtrip (Input, Output, Zlib.Zlib_Header, "dynamic lazy");
   end Test_Dynamic_With_Lazy_Roundtrips;

   procedure Test_Auto_With_Lazy_Roundtrips
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input  : constant Zlib.Byte_Array := Payload;
      Status : Zlib.Status_Code := Zlib.Ok;
      Output : constant Zlib.Byte_Array :=
        Zlib.Deflate (Input, Zlib.Compression_Level'(6), Status);
   begin
      Assert (Status = Zlib.Ok, "auto level 6 lazy compression status");
      Assert_Roundtrip (Input, Output, Zlib.Zlib_Header, "auto level 6 lazy");
   end Test_Auto_With_Lazy_Roundtrips;

   procedure Test_GZip_Auto_With_Lazy_Roundtrips
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input  : constant Zlib.Byte_Array := Payload;
      Status : Zlib.Status_Code := Zlib.Ok;
      Output : constant Zlib.Byte_Array :=
        Zlib.GZip (Input, Zlib.Compression_Level'(6), Status);
   begin
      Assert (Status = Zlib.Ok, "gzip auto level 6 lazy compression status");
      Assert_Roundtrip (Input, Output, Zlib.GZip, "gzip auto level 6 lazy");
   end Test_GZip_Auto_With_Lazy_Roundtrips;

   procedure Test_Raw_Auto_With_Lazy_Roundtrips
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input  : constant Zlib.Byte_Array := Payload;
      Status : Zlib.Status_Code := Zlib.Ok;
      Output : constant Zlib.Byte_Array :=
        Zlib.Deflate_Raw (Input, Zlib.Compression_Level'(6), Status);
   begin
      Assert (Status = Zlib.Ok, "raw auto level 6 lazy compression status");
      Assert_Roundtrip (Input, Output, Zlib.Raw_Deflate, "raw auto level 6 lazy");
   end Test_Raw_Auto_With_Lazy_Roundtrips;

   procedure Test_Level_Zero_Remains_Stored
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input    : constant Zlib.Byte_Array := Payload;
      Status_A : Zlib.Status_Code := Zlib.Ok;
      Status_B : Zlib.Status_Code := Zlib.Ok;
      A        : constant Zlib.Byte_Array :=
        Zlib.Deflate (Input, Zlib.Compression_Level'(0), Status_A);
      B        : constant Zlib.Byte_Array := Zlib.Deflate_Stored (Input, Status_B);
   begin
      Assert (Status_A = Zlib.Ok, "level 0 status");
      Assert (Status_B = Zlib.Ok, "stored status");
      Assert_Same (A, B, "level 0 must remain stored");
   end Test_Level_Zero_Remains_Stored;

   procedure Test_Level_Strategy_Documentation
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert (Zlib.LZ77_Matcher.Strategy_For_Level (2) = Zlib.LZ77_Matcher.Greedy,
              "level 2 remains greedy");
      Assert (Zlib.LZ77_Matcher.Strategy_For_Level (3) = Zlib.LZ77_Matcher.Greedy,
              "level 3 remains greedy");
      Assert (Zlib.LZ77_Matcher.Strategy_For_Level (6) = Zlib.LZ77_Matcher.Lazy,
              "level 6 uses lazy matching");
      Assert (Zlib.LZ77_Matcher.Strategy_For_Level (8) = Zlib.LZ77_Matcher.Optimal,
              "level 8 uses bounded optimal parsing");
      Assert (Zlib.LZ77_Matcher.Strategy_For_Level (9) = Zlib.LZ77_Matcher.Optimal,
              "level 9 uses bounded optimal parsing");
   end Test_Level_Strategy_Documentation;

   procedure Test_Level_Probe_Limits_Are_Granular
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert (Zlib.LZ77_Matcher.Chain_Limit_For_Level (0) = 0,
              "level 0 disables matching");
      Assert (Zlib.LZ77_Matcher.Chain_Limit_For_Level (1) = 4,
              "level 1 fixed effort");
      Assert (Zlib.LZ77_Matcher.Chain_Limit_For_Level (2) = 8,
              "level 2 auto effort");
      Assert (Zlib.LZ77_Matcher.Chain_Limit_For_Level (3) = 16,
              "level 3 auto effort");
      Assert (Zlib.LZ77_Matcher.Chain_Limit_For_Level (4) = 32,
              "level 4 lazy effort");
      Assert (Zlib.LZ77_Matcher.Chain_Limit_For_Level (5) = 64,
              "level 5 lazy effort");
      Assert (Zlib.LZ77_Matcher.Chain_Limit_For_Level (6) = 128,
              "level 6 lazy effort");
      Assert (Zlib.LZ77_Matcher.Chain_Limit_For_Level (7) = 512,
              "level 7 lazy effort");
      Assert (Zlib.LZ77_Matcher.Chain_Limit_For_Level (8) = 1_024,
              "level 8 optimal effort");
      Assert (Zlib.LZ77_Matcher.Chain_Limit_For_Level (9) = 4_096,
              "level 9 optimal effort");
   end Test_Level_Probe_Limits_Are_Granular;

   procedure Test_Higher_Level_Representative_Size_No_Worse
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input    : constant Zlib.Byte_Array := Payload;
      Status_2 : Zlib.Status_Code := Zlib.Ok;
      Status_6 : Zlib.Status_Code := Zlib.Ok;
      Status_9 : Zlib.Status_Code := Zlib.Ok;
      Level_2  : constant Zlib.Byte_Array :=
        Zlib.Deflate (Input, Zlib.Compression_Level'(2), Status_2);
      Level_6  : constant Zlib.Byte_Array :=
        Zlib.Deflate (Input, Zlib.Compression_Level'(6), Status_6);
      Level_9  : constant Zlib.Byte_Array :=
        Zlib.Deflate (Input, Zlib.Compression_Level'(9), Status_9);
   begin
      Assert (Status_2 = Zlib.Ok, "level 2 compression status");
      Assert (Status_6 = Zlib.Ok, "level 6 compression status");
      Assert (Status_9 = Zlib.Ok, "level 9 compression status");
      Assert_Roundtrip (Input, Level_2, Zlib.Zlib_Header, "level 2 representative");
      Assert_Roundtrip (Input, Level_6, Zlib.Zlib_Header, "level 6 representative");
      Assert_Roundtrip (Input, Level_9, Zlib.Zlib_Header, "level 9 representative");
      Assert (Level_6'Length <= Level_2'Length,
              "default lazy level should not exceed low Auto size");
      Assert (Level_9'Length <= Level_6'Length,
              "highest lazy level should not exceed default level size");
   end Test_Higher_Level_Representative_Size_No_Worse;

   procedure Test_Lazy_Compresses_Representative_No_Worse_Than_Greedy_Tokens
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input       : constant Zlib.Byte_Array := Bytes ("aaabaaaaa aaabaaaaa aaabaaaaa aaabaaaaa");
      Greedy      : constant Zlib.LZ77_Matcher.Token_Array :=
        Zlib.LZ77_Matcher.Tokenize (Input, 32, Zlib.LZ77_Matcher.Greedy);
      Lazy        : constant Zlib.LZ77_Matcher.Token_Array :=
        Zlib.LZ77_Matcher.Tokenize (Input, 32, Zlib.LZ77_Matcher.Lazy);
   begin
      Assert (Lazy'Length <= Greedy'Length,
              "representative lazy token stream should be no longer than greedy token stream");
   end Test_Lazy_Compresses_Representative_No_Worse_Than_Greedy_Tokens;

   procedure Test_Sync_Flush_With_Lazy_Roundtrips
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input      : constant Zlib.Byte_Array := Payload;
      Compressed : constant Zlib.Byte_Array := Streaming_Compress (Input, Zlib.Sync_Flush);
   begin
      Assert_Roundtrip (Input, Compressed, Zlib.Zlib_Header, "sync flush lazy streaming");
   end Test_Sync_Flush_With_Lazy_Roundtrips;

   procedure Test_Full_Flush_With_Lazy_Roundtrips
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input      : constant Zlib.Byte_Array := Payload;
      Compressed : constant Zlib.Byte_Array := Streaming_Compress (Input, Zlib.Full_Flush);
   begin
      Assert_Roundtrip (Input, Compressed, Zlib.Zlib_Header, "full flush lazy streaming");
   end Test_Full_Flush_With_Lazy_Roundtrips;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      package R renames AUnit.Test_Cases.Registration;
   begin
      R.Register_Routine (T, Test_Dynamic_With_Lazy_Roundtrips'Access,
                          "Dynamic with lazy matching roundtrips");
      R.Register_Routine (T, Test_Auto_With_Lazy_Roundtrips'Access,
                          "Auto with lazy matching roundtrips");
      R.Register_Routine (T, Test_GZip_Auto_With_Lazy_Roundtrips'Access,
                          "GZip Auto with lazy matching roundtrips");
      R.Register_Routine (T, Test_Raw_Auto_With_Lazy_Roundtrips'Access,
                          "Raw Auto with lazy matching roundtrips");
      R.Register_Routine (T, Test_Level_Zero_Remains_Stored'Access,
                          "Level 0 remains stored");
      R.Register_Routine (T, Test_Level_Strategy_Documentation'Access,
                          "documented level policy selects greedy/lazy");
      R.Register_Routine (T, Test_Level_Probe_Limits_Are_Granular'Access,
                          "documented level policy uses granular probe limits");
      R.Register_Routine (T, Test_Higher_Level_Representative_Size_No_Worse'Access,
                          "higher level representative output is no worse");
      R.Register_Routine (T, Test_Lazy_Compresses_Representative_No_Worse_Than_Greedy_Tokens'Access,
                          "representative lazy token stream is no worse than greedy");
      R.Register_Routine (T, Test_Sync_Flush_With_Lazy_Roundtrips'Access,
                          "Sync_Flush with lazy matching roundtrips");
      R.Register_Routine (T, Test_Full_Flush_With_Lazy_Roundtrips'Access,
                          "Full_Flush with lazy matching roundtrips");
   end Register_Tests;

end Zlib_Lazy_Compression_Tests;
