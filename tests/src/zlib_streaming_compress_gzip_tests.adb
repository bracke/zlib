with Ada.Containers.Vectors;
with Ada.Streams; use Ada.Streams;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;
with Zlib_Fixture_Data;

package body Zlib_Streaming_Compress_GZip_Tests is

   use type Zlib.Byte;
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
      return AUnit.Format ("Zlib streaming gzip compression");
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
      Zlib.Deflate_Init (Filter, Header => Zlib.GZip, Mode => Mode);

      while Input_Data'Length > 0 and then Next_Input <= Input_Data'Last loop
         declare
            Chunk_Last : constant Ada.Streams.Stream_Element_Offset :=
              Ada.Streams.Stream_Element_Offset'Min
                (Input_Data'Last,
                 Next_Input + Ada.Streams.Stream_Element_Offset (Input_Chunk_Size) - 1);
            Out_Buffer : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Output_Buffer_Size));
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
            Assert (Calls < 1_000_000, "gzip streaming compression input progress");
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
            Assert (Calls < 1_000_000, "gzip streaming compression finish progress");
         end;
      end loop;

      Zlib.Compress_Close (Filter);
      return To_Bytes (Output);
   end Compress_All;

   procedure Expect_Roundtrip
     (Input : Zlib.Byte_Array;
      Mode  : Zlib.Compression_Mode;
      Label : String)
   is
      Status     : Zlib.Status_Code;
      Compressed : constant Zlib.Byte_Array := Compress_All (Input, Mode, 1, 1);
      Inflated   : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Compressed, Zlib.GZip, Status);
   begin
      Assert (Status = Zlib.Ok, Label & " must inflate as gzip");
      Assert_Same (Inflated, Input, Label & " roundtrip");
   end Expect_Roundtrip;

   procedure Test_Mode_Roundtrips (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Expect_Roundtrip ([1 .. 0 => 0], Zlib.Stored, "empty stored gzip");
      Expect_Roundtrip (F.Plain_Stored, Zlib.Fixed, "fixed gzip");
      Expect_Roundtrip (F.Plain_Large_Repeated, Zlib.Dynamic, "dynamic gzip");
      Expect_Roundtrip (F.Plain_Binary, Zlib.Auto, "auto gzip");
   end Test_Mode_Roundtrips;

   procedure Test_Stream_End_And_Header_Trailer_Split (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Filter   : Zlib.Compression_Filter_Type;
      Input    : constant Ada.Streams.Stream_Element_Array := To_Stream (F.Plain_Stored);
      Output   : Stream_Vectors.Vector;
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Calls    : Natural := 0;
   begin
      Zlib.Deflate_Init (Filter, Header => Zlib.GZip, Mode => Zlib.Stored);
      Assert (not Zlib.Compress_Stream_End (Filter), "gzip stream end must be false after init");

      while Input'Length > 0 and then Calls < 5 loop
         declare
            One : Ada.Streams.Stream_Element_Array (1 .. 1);
         begin
            Zlib.Compress (Filter, Input (Input'First .. Input'First), In_Last, One, Out_Last);
            Append_Output (Output, One, Out_Last);
            Calls := Calls + 1;
         end;
      end loop;
      Assert (not Zlib.Compress_Stream_End (Filter), "gzip stream end must be false before Finish");
      Zlib.Compress_Close (Filter, Ignore_Error => True);

      declare
         Compressed : constant Zlib.Byte_Array := Compress_All (F.Plain_Stored, Zlib.Stored, 1, 1);
      begin
         Assert (Compressed'Length >= 18, "gzip output buffer size 1 must produce a full member");
         Assert (Compressed (Compressed'First) = 16#1F#, "split gzip header byte 1");
         Assert (Compressed (Compressed'First + 1) = 16#8B#, "split gzip header byte 2");
      end;
   end Test_Stream_End_And_Header_Trailer_Split;

   procedure Test_Close_Before_Finish_Raises (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Filter : Zlib.Compression_Filter_Type;
      Raised : Boolean := False;
   begin
      Zlib.Deflate_Init (Filter, Header => Zlib.GZip, Mode => Zlib.Stored);
      begin
         Zlib.Compress_Close (Filter);
      exception
         when Zlib.Zlib_Error =>
            Raised := True;
      end;
      Assert (Raised, "gzip Compress_Close before Finish must raise Zlib_Error");
   end Test_Close_Before_Finish_Raises;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine (T, Test_Mode_Roundtrips'Access, "streaming gzip mode roundtrips");
      Registration.Register_Routine
        (T, Test_Stream_End_And_Header_Trailer_Split'Access,
         "streaming gzip one-byte output splitting");
      Registration.Register_Routine
        (T, Test_Close_Before_Finish_Raises'Access,
         "streaming gzip close before Finish raises");
   end Register_Tests;
end Zlib_Streaming_Compress_GZip_Tests;
