with Ada.Containers.Vectors;
with Ada.Streams; use Ada.Streams;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;

package body Zlib_Streaming_Compress_Bounds_Tests is
   use type Zlib.Header_Type;
   use type Zlib.Compression_Mode;
   use type Zlib.Byte;
   use type Zlib.Status_Code;

   package Stream_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Ada.Streams.Stream_Element);

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib streaming compression bounds hardening");
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
      if Count = 0 then
         return;
      end if;

      for I in Buffer'First .. Buffer'First + Ada.Streams.Stream_Element_Offset (Count) - 1 loop
         Output.Append (Buffer (I));
      end loop;
   end Append_Output;

   function To_Stream
     (Input : Zlib.Byte_Array)
      return Ada.Streams.Stream_Element_Array
   is
      Result : Ada.Streams.Stream_Element_Array
        (11 .. 10 + Ada.Streams.Stream_Element_Offset (Input'Length));
   begin
      for I in Input'Range loop
         Result (11 + Ada.Streams.Stream_Element_Offset (I - Input'First)) :=
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

   function Compress_All
     (Input              : Zlib.Byte_Array;
      Header             : Zlib.Header_Type;
      Mode               : Zlib.Compression_Mode;
      Input_Chunk_Size   : Positive;
      Output_Buffer_Size : Positive)
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
              (101 .. 100 + Ada.Streams.Stream_Element_Offset (Output_Buffer_Size));
         begin
            Zlib.Compress
              (Filter   => Filter,
               In_Data  => Input_Data (Next_Input .. Chunk_Last),
               In_Last  => In_Last,
               Out_Data => Out_Buffer,
               Out_Last => Out_Last,
               Flush    => Zlib.No_Flush);
            Append_Output (Output, Out_Buffer, Out_Last);

            if In_Last >= Next_Input then
               Next_Input := In_Last + 1;
            end if;

            Calls := Calls + 1;
            Assert (Calls < 1_000_000, "streaming compression input loop must make progress");
         end;
      end loop;

      while not Zlib.Compress_Stream_End (Filter) loop
         declare
            Out_Buffer : Ada.Streams.Stream_Element_Array
              (201 .. 200 + Ada.Streams.Stream_Element_Offset (Output_Buffer_Size));
         begin
            Zlib.Compress_Flush
              (Filter   => Filter,
               Out_Data => Out_Buffer,
               Out_Last => Out_Last,
               Flush    => Zlib.Finish);
            Append_Output (Output, Out_Buffer, Out_Last);
            Calls := Calls + 1;
            Assert (Calls < 1_000_000, "streaming compression finish loop must make progress");
         end;
      end loop;

      Zlib.Compress_Close (Filter);
      return To_Bytes (Output);
   end Compress_All;

   procedure Assert_Roundtrip
     (Input              : Zlib.Byte_Array;
      Header             : Zlib.Header_Type;
      Mode               : Zlib.Compression_Mode;
      Input_Chunk_Size   : Positive;
      Output_Buffer_Size : Positive;
      Label              : String)
   is
      Encoded : constant Zlib.Byte_Array :=
        Compress_All (Input, Header, Mode, Input_Chunk_Size, Output_Buffer_Size);
      Status  : Zlib.Status_Code;
      Decoded : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header
          (Encoded,
           (if Header = Zlib.GZip then Zlib.GZip else Zlib.Zlib_Header),
           Status);
   begin
      Assert (Status = Zlib.Ok, Label & " must inflate successfully");
      Assert (Decoded'Length = Input'Length, Label & " decoded length mismatch");
      for I in Input'Range loop
         Assert
           (Decoded (Decoded'First + (I - Input'First)) = Input (I),
            Label & " decoded payload mismatch");
      end loop;
   end Assert_Roundtrip;

   procedure Test_Non_One_Based_Bounds
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Compression_Filter_Type;
      Input    : constant Ada.Streams.Stream_Element_Array (42 .. 44) := [42 => 1, 43 => 2, 44 => 3];
      Output   : Ada.Streams.Stream_Element_Array (90 .. 120);
      In_Last  : Ada.Streams.Stream_Element_Offset := -1;
      Out_Last : Ada.Streams.Stream_Element_Offset := -1;
   begin
      Zlib.Deflate_Init (Filter, Header => Zlib.Zlib_Header, Mode => Zlib.Stored);
      Zlib.Compress (Filter, Input, In_Last, Output, Out_Last, Flush => Zlib.No_Flush);
      Assert
        (In_Last >= Input'First - 1 and then In_Last <= Input'Last,
         "non-1-based input marker stays within valid convention");
      Assert
        (Out_Last >= Output'First - 1 and then Out_Last <= Output'Last,
         "non-1-based output marker stays within valid convention");
      Zlib.Compress_Close (Filter, Ignore_Error => True);
   end Test_Non_One_Based_Bounds;

   procedure Test_Null_Input
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Compression_Filter_Type;
      Input    : constant Ada.Streams.Stream_Element_Array (7 .. 6) := [];
      Output   : Ada.Streams.Stream_Element_Array (9 .. 32);
      In_Last  : Ada.Streams.Stream_Element_Offset := 99;
      Out_Last : Ada.Streams.Stream_Element_Offset;
   begin
      Zlib.Deflate_Init (Filter);
      Zlib.Compress (Filter, Input, In_Last, Output, Out_Last);
      Assert (In_Last = Input'First, "null input uses Data'First as no-consumption marker");
      Zlib.Compress_Close (Filter, Ignore_Error => True);
   end Test_Null_Input;

   procedure Test_Null_Output
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Compression_Filter_Type;
      Input    : constant Ada.Streams.Stream_Element_Array (1 .. 1) := [1 => 1];
      Output   : Ada.Streams.Stream_Element_Array (12 .. 11);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset := 99;
   begin
      Zlib.Deflate_Init (Filter);
      Zlib.Compress (Filter, Input, In_Last, Output, Out_Last);
      Assert (Out_Last = Output'First, "null output uses Data'First as no-output marker");
      Assert (In_Last = Before_First (Input), "null output does not lose input when header is pending");
      Zlib.Compress_Close (Filter, Ignore_Error => True);
   end Test_Null_Output;

   procedure Test_Output_Buffer_Size_One
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array :=
        [1 => 1, 2 => 2, 3 => 3, 4 => 4,
         5 => 5, 6 => 6, 7 => 7, 8 => 8];
   begin
      Assert_Roundtrip (Input, Zlib.Zlib_Header, Zlib.Stored, 4, 1, "zlib stored output size 1");
      Assert_Roundtrip (Input, Zlib.GZip, Zlib.Fixed, 4, 1, "gzip fixed output size 1");
   end Test_Output_Buffer_Size_One;

   procedure Test_Input_Chunk_Size_One
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array :=
        [1 => 10, 2 => 20, 3 => 30, 4 => 40,
         5 => 50, 6 => 60, 7 => 70, 8 => 80];
   begin
      Assert_Roundtrip (Input, Zlib.Zlib_Header, Zlib.Dynamic, 1, 17, "zlib dynamic input size 1");
      Assert_Roundtrip (Input, Zlib.GZip, Zlib.Stored, 1, 17, "gzip stored input size 1");
   end Test_Input_Chunk_Size_One;

   procedure Test_Finish_Output_Size_One
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array := [1 => 101, 2 => 102, 3 => 103, 4 => 104];
   begin
      Assert_Roundtrip (Input, Zlib.Zlib_Header, Zlib.Fixed, 2, 1, "zlib finish output size 1");
      Assert_Roundtrip (Input, Zlib.GZip, Zlib.Dynamic, 2, 1, "gzip finish output size 1");
   end Test_Finish_Output_Size_One;

   procedure Test_Repeated_Empty_No_Flush
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Compression_Filter_Type;
      Empty    : constant Ada.Streams.Stream_Element_Array (1 .. 0) := [];
      Output   : Ada.Streams.Stream_Element_Array (1 .. 8);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
   begin
      Zlib.Deflate_Init (Filter);
      for I in 1 .. 10 loop
         Zlib.Compress (Filter, Empty, In_Last, Output, Out_Last, Flush => Zlib.No_Flush);
         Assert (In_Last = Empty'First, "empty No_Flush Compress initializes In_Last consistently");
      end loop;
      for I in 1 .. 10 loop
         Zlib.Compress_Flush (Filter, Output, Out_Last, Flush => Zlib.No_Flush);
         Assert (not Zlib.Compress_Stream_End (Filter), "No_Flush Compress_Flush must not finalize stream");
      end loop;
      Zlib.Compress_Close (Filter, Ignore_Error => True);
   end Test_Repeated_Empty_No_Flush;

   procedure Test_Header_And_Trailer_Split_Size_One
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Empty : constant Zlib.Byte_Array (1 .. 0) := [];
   begin
      Assert_Roundtrip (Empty, Zlib.GZip, Zlib.Stored, 1, 1, "gzip header/trailer split across size 1 output");
      Assert_Roundtrip (Empty, Zlib.Zlib_Header, Zlib.Stored, 1, 1, "zlib Adler footer split across size 1 output");
   end Test_Header_And_Trailer_Split_Size_One;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine (T, Test_Non_One_Based_Bounds'Access, "non-1-based input and output bounds");
      Registration.Register_Routine (T, Test_Null_Input'Access, "null input array");
      Registration.Register_Routine (T, Test_Null_Output'Access, "null output array");
      Registration.Register_Routine (T, Test_Output_Buffer_Size_One'Access, "output buffer size 1");
      Registration.Register_Routine (T, Test_Input_Chunk_Size_One'Access, "input chunk size 1");
      Registration.Register_Routine (T, Test_Finish_Output_Size_One'Access, "Finish with output buffer size 1");
      Registration.Register_Routine
        (T, Test_Repeated_Empty_No_Flush'Access,
         "repeated empty No_Flush calls do not finalize");
      Registration.Register_Routine
        (T, Test_Header_And_Trailer_Split_Size_One'Access,
         "gzip header/trailer and zlib Adler footer split across size 1 output");
   end Register_Tests;

end Zlib_Streaming_Compress_Bounds_Tests;
