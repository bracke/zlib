with Ada.Streams;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;

package body Zlib_Interop_Fixture_Tests is
   use type Ada.Streams.Stream_Element_Offset;
   use type Zlib.Byte;
   use type Zlib.Status_Code;

   Git_Like_Zlib : constant Zlib.Byte_Array :=
     [1 => 16#78#, 2 => 16#9C#, 3 => 16#4B#, 4 => 16#CA#,
      5 => 16#C9#, 6 => 16#4F#, 7 => 16#52#, 8 => 16#30#,
      9 => 16#34#, 10 => 16#62#, 11 => 16#C8#, 12 => 16#48#,
      13 => 16#CD#, 14 => 16#C9#, 15 => 16#C9#, 16 => 16#57#,
      17 => 16#28#, 18 => 16#CF#, 19 => 16#2F#, 20 => 16#CA#,
      21 => 16#49#, 22 => 16#E1#, 23 => 16#02#, 24 => 16#00#,
      25 => 16#44#, 26 => 16#11#, 27 => 16#06#, 28 => 16#89#];

   Http_Deflate_Zlib : constant Zlib.Byte_Array :=
     [1 => 16#78#, 2 => 16#01#, 3 => 16#01#, 4 => 16#0D#,
      5 => 16#00#, 6 => 16#F2#, 7 => 16#FF#, 8 => 16#68#,
      9 => 16#65#, 10 => 16#6C#, 11 => 16#6C#, 12 => 16#6F#,
      13 => 16#20#, 14 => 16#73#, 15 => 16#74#, 16 => 16#6F#,
      17 => 16#72#, 18 => 16#65#, 19 => 16#64#, 20 => 16#0A#,
      21 => 16#23#, 22 => 16#A5#, 23 => 16#04#, 24 => 16#D0#];

   Http_GZip_Hello : constant Zlib.Byte_Array :=
     [1 => 16#1F#, 2 => 16#8B#, 3 => 16#08#, 4 => 16#00#,
      5 => 16#00#, 6 => 16#00#, 7 => 16#00#, 8 => 16#00#,
      9 => 16#00#, 10 => 16#03#, 11 => 16#CB#, 12 => 16#48#,
      13 => 16#CD#, 14 => 16#C9#, 15 => 16#C9#, 16 => 16#07#,
      17 => 16#00#, 18 => 16#86#, 19 => 16#A6#, 20 => 16#10#,
      21 => 16#36#, 22 => 16#05#, 23 => 16#00#, 24 => 16#00#,
      25 => 16#00#];

   GZip_Binary_Payload : constant Zlib.Byte_Array :=
     [1 => 16#1F#, 2 => 16#8B#, 3 => 16#08#, 4 => 16#00#,
      5 => 16#00#, 6 => 16#00#, 7 => 16#00#, 8 => 16#00#,
      9 => 16#00#, 10 => 16#03#, 11 => 16#63#, 12 => 16#60#,
      13 => 16#64#, 14 => 16#E2#, 15 => 16#E5#, 16 => 16#6A#,
      17 => 16#68#, 18 => 16#FC#, 19 => 16#F7#, 20 => 16#9F#,
      21 => 16#97#, 22 => 16#CB#, 23 => 16#91#, 24 => 16#42#,
      25 => 16#00#, 26 => 16#00#, 27 => 16#6C#, 28 => 16#44#,
      29 => 16#22#, 30 => 16#64#, 31 => 16#4B#, 32 => 16#00#,
      33 => 16#00#, 34 => 16#00#];

   Expected_Git_Blob : constant Zlib.Byte_Array :=
     [1 => Zlib.Byte (Character'Pos ('b')),
      2 => Zlib.Byte (Character'Pos ('l')),
      3 => Zlib.Byte (Character'Pos ('o')),
      4 => Zlib.Byte (Character'Pos ('b')),
      5 => Zlib.Byte (Character'Pos (' ')),
      6 => Zlib.Byte (Character'Pos ('1')),
      7 => Zlib.Byte (Character'Pos ('2')),
      8 => 16#00#,
      9 => Zlib.Byte (Character'Pos ('h')),
      10 => Zlib.Byte (Character'Pos ('e')),
      11 => Zlib.Byte (Character'Pos ('l')),
      12 => Zlib.Byte (Character'Pos ('l')),
      13 => Zlib.Byte (Character'Pos ('o')),
      14 => Zlib.Byte (Character'Pos (' ')),
      15 => Zlib.Byte (Character'Pos ('w')),
      16 => Zlib.Byte (Character'Pos ('o')),
      17 => Zlib.Byte (Character'Pos ('r')),
      18 => Zlib.Byte (Character'Pos ('l')),
      19 => Zlib.Byte (Character'Pos ('d')),
      20 => 16#0A#];

   Expected_Http_Deflate : constant Zlib.Byte_Array :=
     [1 => Zlib.Byte (Character'Pos ('h')),
      2 => Zlib.Byte (Character'Pos ('e')),
      3 => Zlib.Byte (Character'Pos ('l')),
      4 => Zlib.Byte (Character'Pos ('l')),
      5 => Zlib.Byte (Character'Pos ('o')),
      6 => Zlib.Byte (Character'Pos (' ')),
      7 => Zlib.Byte (Character'Pos ('s')),
      8 => Zlib.Byte (Character'Pos ('t')),
      9 => Zlib.Byte (Character'Pos ('o')),
      10 => Zlib.Byte (Character'Pos ('r')),
      11 => Zlib.Byte (Character'Pos ('e')),
      12 => Zlib.Byte (Character'Pos ('d')),
      13 => 16#0A#];

   Expected_Hello : constant Zlib.Byte_Array :=
     [1 => Zlib.Byte (Character'Pos ('h')),
      2 => Zlib.Byte (Character'Pos ('e')),
      3 => Zlib.Byte (Character'Pos ('l')),
      4 => Zlib.Byte (Character'Pos ('l')),
      5 => Zlib.Byte (Character'Pos ('o'))];

   Expected_Binary : constant Zlib.Byte_Array :=
     [1 => 16#00#, 2 => 16#01#, 3 => 16#02#, 4 => 16#0D#,
      5 => 16#0A#, 6 => 16#80#, 7 => 16#81#, 8 => 16#FE#,
      9 => 16#FF#, 10 => 16#0D#, 11 => 16#0A#,
      12 .. 75 => 16#41#];

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib interoperability fixtures");
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

   procedure Assert_Bytes_Equal
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
   end Assert_Bytes_Equal;

   procedure Copy_Output
     (Out_Data : Ada.Streams.Stream_Element_Array;
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Result   : in out Zlib.Byte_Array;
      Last     : in out Natural)
   is
   begin
      if Out_Last = Before_First (Out_Data) then
         return;
      end if;
      for I in Out_Data'First .. Out_Last loop
         Last := Last + 1;
         Result (Last) := Zlib.Byte (Out_Data (I));
      end loop;
   end Copy_Output;

   procedure Inflate_Streaming
     (Input       : Zlib.Byte_Array;
      Header      : Zlib.Header_Type;
      Chunk_Size  : Positive;
      Output_Size : Positive;
      Result      : in out Zlib.Byte_Array;
      Result_Last : out Natural)
   is
      Filter : Zlib.Filter_Type;
      Pos    : Natural := Input'First;
   begin
      Result_Last := Result'First - 1;
      Zlib.Inflate_Init (Filter, Header => Header);

      while Pos <= Input'Last loop
         declare
            Count    : constant Natural := Natural'Min (Chunk_Size, Input'Last - Pos + 1);
            In_Data  : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Count));
            Out_Data : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Output_Size));
            In_Last  : Ada.Streams.Stream_Element_Offset;
            Out_Last : Ada.Streams.Stream_Element_Offset;
         begin
            for I in 0 .. Count - 1 loop
               In_Data (Ada.Streams.Stream_Element_Offset (I + 1)) :=
                 Ada.Streams.Stream_Element (Input (Pos + I));
            end loop;
            Zlib.Translate (Filter, In_Data, In_Last, Out_Data, Out_Last);
            Copy_Output (Out_Data, Out_Last, Result, Result_Last);
            if In_Last /= Before_First (In_Data) then
               Pos := Pos + Natural (In_Last - In_Data'First + 1);
            end if;
         end;
      end loop;

      for Guard in 1 .. 10_000 loop
         declare
            Empty_In : constant Ada.Streams.Stream_Element_Array (1 .. 0) := [];
            Out_Data : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Output_Size));
            In_Last  : Ada.Streams.Stream_Element_Offset;
            Out_Last : Ada.Streams.Stream_Element_Offset;
         begin
            Zlib.Translate (Filter, Empty_In, In_Last, Out_Data, Out_Last, Zlib.Finish);
            Copy_Output (Out_Data, Out_Last, Result, Result_Last);
            exit when Out_Last = Before_First (Out_Data);
         end;
      end loop;

      Assert (Zlib.Stream_End (Filter), "stream end after wrapper validation");
      Zlib.Close (Filter);
   end Inflate_Streaming;

   procedure Assert_Streaming_Decodes
     (Input       : Zlib.Byte_Array;
      Header      : Zlib.Header_Type;
      Expected    : Zlib.Byte_Array;
      Chunk_Size  : Positive;
      Output_Size : Positive;
      Message     : String)
   is
      Result : Zlib.Byte_Array (1 .. Expected'Length + 16);
      Last   : Natural;
   begin
      Inflate_Streaming (Input, Header, Chunk_Size, Output_Size, Result, Last);
      Assert (Last = Expected'Length, Message & ": streamed length");
      Assert_Bytes_Equal (Result (1 .. Last), Expected, Message);
   end Assert_Streaming_Decodes;

   procedure Expect_Streaming_Zlib_Error
     (Input  : Zlib.Byte_Array;
      Header : Zlib.Header_Type;
      Name   : String)
   is
      Filter   : Zlib.Filter_Type;
      In_Data  : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Input'Length));
      Out_Data : Ada.Streams.Stream_Element_Array (1 .. 16);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Raised   : Boolean := False;
   begin
      for I in Input'Range loop
         In_Data (Ada.Streams.Stream_Element_Offset (I - Input'First + 1)) :=
           Ada.Streams.Stream_Element (Input (I));
      end loop;
      Zlib.Inflate_Init (Filter, Header => Header);
      begin
         Zlib.Translate (Filter, In_Data, In_Last, Out_Data, Out_Last, Zlib.Finish);
      exception
         when Zlib.Zlib_Error =>
            Raised := True;
      end;
      Zlib.Close (Filter, Ignore_Error => True);
      Assert (Raised, Name & " must raise Zlib_Error");
   end Expect_Streaming_Zlib_Error;

   procedure Expect_One_Shot_Status
     (Input    : Zlib.Byte_Array;
      Expected : Zlib.Status_Code;
      Name     : String)
   is
      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array := Zlib.Inflate (Input, Status);
      pragma Unreferenced (Output);
   begin
      Assert (Status = Expected, Name & " one-shot status");
   end Expect_One_Shot_Status;

   procedure Test_Version_Git_Blob_Fixtures
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array := Zlib.Inflate (Git_Like_Zlib, Status);
   begin
      Assert (Status = Zlib.Ok, "frozen Git-like zlib fixture status");
      Assert_Bytes_Equal (Output, Expected_Git_Blob, "frozen Git-like zlib fixture");

      declare
         Encoded : constant Zlib.Byte_Array := Zlib.Deflate_Stored (Expected_Git_Blob, Status);
      begin
         Assert (Status = Zlib.Ok, "version Deflate_Stored fixture creation");
         declare
            Roundtrip : constant Zlib.Byte_Array := Zlib.Inflate (Encoded, Status);
         begin
            Assert (Status = Zlib.Ok, "version Deflate_Stored roundtrip status");
            Assert_Bytes_Equal (Roundtrip, Expected_Git_Blob, "version roundtrip");
         end;
      end;
   end Test_Version_Git_Blob_Fixtures;

   procedure Test_HttpClient_Content_Encoding_Fixtures
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      type Positive_Vector is array (Positive range <>) of Positive;

      Deflate_Chunks : constant Positive_Vector :=
        [1, 2, 3, Http_Deflate_Zlib'Length];
      Deflate_Output : constant Positive_Vector :=
        [1, 2, Expected_Http_Deflate'Length];
      GZip_Chunks    : constant Positive_Vector :=
        [1, 2, 3, Http_GZip_Hello'Length];
      GZip_Output    : constant Positive_Vector :=
        [1, 2, Expected_Hello'Length];
   begin
      for Chunk of Deflate_Chunks loop
         for Out_Size of Deflate_Output loop
            Assert_Streaming_Decodes
              (Http_Deflate_Zlib, Zlib.Zlib_Header, Expected_Http_Deflate,
               Chunk, Out_Size, "HttpClient deflate fixture");
         end loop;
      end loop;

      for Chunk of GZip_Chunks loop
         for Out_Size of GZip_Output loop
            Assert_Streaming_Decodes
              (Http_GZip_Hello, Zlib.GZip, Expected_Hello,
               Chunk, Out_Size, "HttpClient gzip fixture");
         end loop;
      end loop;
   end Test_HttpClient_Content_Encoding_Fixtures;

   procedure Test_Binary_GZip_Fixture
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_Streaming_Decodes
        (GZip_Binary_Payload, Zlib.GZip, Expected_Binary, 1, 1,
         "gzip binary payload with NUL/high bytes/CRLF/LZ77 copy");
   end Test_Binary_GZip_Fixture;

   procedure Test_Malformed_Streaming_Matrix
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Truncated_Zlib_Header : constant Zlib.Byte_Array := [1 => 16#78#];
      Truncated_Zlib_Body   : constant Zlib.Byte_Array := [1 => 16#78#, 2 => 16#01#, 3 => 16#01#];
      Truncated_Zlib_Trailer : constant Zlib.Byte_Array := Http_Deflate_Zlib (1 .. 20);
      Bad_Zlib_Checksum      : constant Zlib.Byte_Array :=
        [1 => 16#78#, 2 => 16#01#, 3 => 16#01#, 4 => 16#00#,
         5 => 16#00#, 6 => 16#FF#, 7 => 16#FF#, 8 => 16#00#,
         9 => 16#00#, 10 => 16#00#, 11 => 16#02#];
      Invalid_Block_Type     : constant Zlib.Byte_Array :=
        [1 => 16#78#, 2 => 16#01#, 3 => 2#0000_0111#,
         4 => 16#00#, 5 => 16#00#, 6 => 16#00#, 7 => 16#01#];
      Invalid_Huffman_Code   : constant Zlib.Byte_Array :=
        [1 => 16#78#, 2 => 16#01#, 3 => 16#1B#, 4 => 16#03#,
         5 => 16#00#, 6 => 16#00#, 7 => 16#00#, 8 => 16#01#];
      Invalid_Distance       : constant Zlib.Byte_Array :=
        [1 => 16#78#, 2 => 16#01#, 3 => 16#03#, 4 => 16#02#,
         5 => 16#00#, 6 => 16#00#, 7 => 16#00#, 8 => 16#01#];
      Preset_Dictionary      : constant Zlib.Byte_Array :=
        [1 => 16#78#, 2 => 16#20#, 3 => 16#00#, 4 => 16#00#,
         5 => 16#00#, 6 => 16#00#];
      GZip_Reserved_Flags   : constant Zlib.Byte_Array :=
        [1 => 16#1F#, 2 => 16#8B#, 3 => 16#08#, 4 => 16#E0#];
      GZip_Bad_CRC          : constant Zlib.Byte_Array :=
        [1 => 16#1F#, 2 => 16#8B#, 3 => 16#08#, 4 => 16#00#,
         5 => 16#00#, 6 => 16#00#, 7 => 16#00#, 8 => 16#00#,
         9 => 16#00#, 10 => 16#03#, 11 => 16#CB#, 12 => 16#48#,
         13 => 16#CD#, 14 => 16#C9#, 15 => 16#C9#, 16 => 16#07#,
         17 => 16#00#, 18 => 16#87#, 19 => 16#A6#, 20 => 16#10#,
         21 => 16#36#, 22 => 16#05#, 23 => 16#00#, 24 => 16#00#,
         25 => 16#00#];
      GZip_Bad_ISIZE        : constant Zlib.Byte_Array :=
        [1 => 16#1F#, 2 => 16#8B#, 3 => 16#08#, 4 => 16#00#,
         5 => 16#00#, 6 => 16#00#, 7 => 16#00#, 8 => 16#00#,
         9 => 16#00#, 10 => 16#03#, 11 => 16#CB#, 12 => 16#48#,
         13 => 16#CD#, 14 => 16#C9#, 15 => 16#C9#, 16 => 16#07#,
         17 => 16#00#, 18 => 16#86#, 19 => 16#A6#, 20 => 16#10#,
         21 => 16#36#, 22 => 16#04#, 23 => 16#00#, 24 => 16#00#,
         25 => 16#00#];
      GZip_Truncated_Trailer : constant Zlib.Byte_Array := Http_GZip_Hello (1 .. 21);
   begin
      Expect_One_Shot_Status
        (Truncated_Zlib_Header, Zlib.Unexpected_End_Of_Input,
         "truncated zlib header");
      Expect_One_Shot_Status
        (Truncated_Zlib_Body, Zlib.Unexpected_End_Of_Input,
         "truncated zlib body");
      Expect_One_Shot_Status
        (Truncated_Zlib_Trailer, Zlib.Unexpected_End_Of_Input,
         "truncated zlib trailer");
      Expect_One_Shot_Status
        (Bad_Zlib_Checksum, Zlib.Invalid_Checksum, "bad zlib checksum");
      Expect_One_Shot_Status
        (Invalid_Block_Type, Zlib.Invalid_Block_Type, "invalid block type");
      Expect_One_Shot_Status
        (Invalid_Huffman_Code, Zlib.Invalid_Huffman_Code,
         "invalid Huffman code");
      Expect_One_Shot_Status
        (Invalid_Distance, Zlib.Invalid_Distance, "invalid distance");
      Expect_One_Shot_Status
        (Preset_Dictionary, Zlib.Unsupported_Preset_Dictionary,
         "preset dictionary");

      Expect_Streaming_Zlib_Error
        (Truncated_Zlib_Header, Zlib.Zlib_Header, "truncated zlib header");
      Expect_Streaming_Zlib_Error
        (Truncated_Zlib_Body, Zlib.Zlib_Header, "truncated zlib body");
      Expect_Streaming_Zlib_Error
        (Truncated_Zlib_Trailer, Zlib.Zlib_Header, "truncated zlib trailer");
      Expect_Streaming_Zlib_Error
        (Bad_Zlib_Checksum, Zlib.Zlib_Header, "bad zlib checksum");
      Expect_Streaming_Zlib_Error
        (Invalid_Block_Type, Zlib.Zlib_Header, "invalid block type");
      Expect_Streaming_Zlib_Error
        (Invalid_Huffman_Code, Zlib.Zlib_Header, "invalid Huffman code");
      Expect_Streaming_Zlib_Error
        (Invalid_Distance, Zlib.Zlib_Header, "invalid distance");
      Expect_Streaming_Zlib_Error
        (Preset_Dictionary, Zlib.Zlib_Header, "preset dictionary");
      Expect_Streaming_Zlib_Error
        (GZip_Reserved_Flags, Zlib.GZip, "gzip reserved flags");
      Expect_Streaming_Zlib_Error (GZip_Bad_CRC, Zlib.GZip, "gzip bad CRC");
      Expect_Streaming_Zlib_Error
        (GZip_Bad_ISIZE, Zlib.GZip, "gzip bad ISIZE");
      Expect_Streaming_Zlib_Error
        (GZip_Truncated_Trailer, Zlib.GZip, "gzip truncated trailer");
   end Test_Malformed_Streaming_Matrix;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine (T, Test_Version_Git_Blob_Fixtures'Access,
                                     "version Git-shaped payload fixtures");
      Registration.Register_Routine (T, Test_HttpClient_Content_Encoding_Fixtures'Access,
                                     "HttpClient gzip/deflate boundary matrix fixtures");
      Registration.Register_Routine (T, Test_Binary_GZip_Fixture'Access,
                                     "binary gzip fixture preserves bytes exactly");
      Registration.Register_Routine (T, Test_Malformed_Streaming_Matrix'Access,
                                     "malformed/truncated streaming matrix raises Zlib_Error");
   end Register_Tests;
end Zlib_Interop_Fixture_Tests;
