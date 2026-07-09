with Ada.Containers.Vectors;
with Ada.Streams;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;
with Zlib_Fixture_Data;

package body Zlib_Streaming_Compress_Conformance_Tests is
   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Offset;
   use type Zlib.Byte;
   use type Zlib.Header_Type;
   use type Zlib.Status_Code;

   package F renames Zlib_Fixture_Data;

   package Stream_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Ada.Streams.Stream_Element);

   type Header_Array is array (Positive range <>) of Zlib.Header_Type;
   type Mode_Array is array (Positive range <>) of Zlib.Compression_Mode;

   Supported_Headers : constant Header_Array :=
     [Zlib.Zlib_Header, Zlib.Default, Zlib.GZip];
   Supported_Modes : constant Mode_Array :=
     [Zlib.Stored, Zlib.Fixed, Zlib.Dynamic, Zlib.Auto];

   Empty_Payload : constant Zlib.Byte_Array := [1 .. 0 => 0];
   Hello_Payload : constant Zlib.Byte_Array :=
     [1 => 16#68#, 2 => 16#65#, 3 => 16#6C#, 4 => 16#6C#, 5 => 16#6F#];
   Large_Payload : constant Zlib.Byte_Array (1 .. 70_000) := [others => 16#41#];

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib streaming compression conformance matrix");
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

   function Matching_Inflate_Header
     (Header : Zlib.Header_Type)
      return Zlib.Header_Type
   is
   begin
      if Header = Zlib.GZip then
         return Zlib.GZip;
      else
         return Zlib.Zlib_Header;
      end if;
   end Matching_Inflate_Header;

   function Header_Name
     (Header : Zlib.Header_Type)
      return String
   is
   begin
      case Header is
         when Zlib.Default     => return "Default";
         when Zlib.Zlib_Header => return "Zlib_Header";
         when Zlib.GZip        => return "GZip";
         when Zlib.Raw_Deflate => return "Raw_Deflate";
      end case;
   end Header_Name;

   function Mode_Name
     (Mode : Zlib.Compression_Mode)
      return String
   is
   begin
      case Mode is
         when Zlib.Stored  => return "Stored";
         when Zlib.Fixed   => return "Fixed";
         when Zlib.Dynamic => return "Dynamic";
         when Zlib.Auto    => return "Auto";
      end case;
   end Mode_Name;

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
            Message & ": byte mismatch at payload index" & Natural'Image (I));
      end loop;
   end Assert_Same;

   function Streaming_Compress
     (Input  : Zlib.Byte_Array;
      Header : Zlib.Header_Type;
      Mode   : Zlib.Compression_Mode;
      Input_Chunk_Size  : Positive := 7;
      Output_Chunk_Size : Positive := 5)
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
              (1 .. Ada.Streams.Stream_Element_Offset (Output_Chunk_Size));
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
            Assert (Calls < 2_000_000, "streaming compression must make progress");
         end;
      end loop;

      while not Zlib.Compress_Stream_End (Filter) loop
         declare
            Out_Buffer : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Output_Chunk_Size));
         begin
            Zlib.Compress_Flush
              (Filter   => Filter,
               Out_Data => Out_Buffer,
               Out_Last => Out_Last,
               Flush    => Zlib.Finish);
            Append_Output (Output, Out_Buffer, Out_Last);

            Calls := Calls + 1;
            Assert (Calls < 2_000_000, "streaming compression finish must make progress");
         end;
      end loop;

      Assert (Zlib.Compress_Stream_End (Filter), "Compress_Stream_End must be true before close");
      Zlib.Compress_Close (Filter);
      return To_Bytes (Output);
   exception
      when others =>
         if Zlib.Is_Open (Filter) then
            Zlib.Compress_Close (Filter, Ignore_Error => True);
         end if;
         raise;
   end Streaming_Compress;

   function Streaming_Inflate
     (Input  : Zlib.Byte_Array;
      Header : Zlib.Header_Type;
      Output_Chunk_Size : Positive := 3)
      return Zlib.Byte_Array
   is
      Filter     : Zlib.Filter_Type;
      Input_Data : constant Ada.Streams.Stream_Element_Array := To_Stream (Input);
      Output     : Stream_Vectors.Vector;
      Next_Input : Ada.Streams.Stream_Element_Offset := Input_Data'First;
      In_Last    : Ada.Streams.Stream_Element_Offset;
      Out_Last   : Ada.Streams.Stream_Element_Offset;
      Calls      : Natural := 0;
   begin
      Zlib.Inflate_Init (Filter, Header => Header);

      while Input_Data'Length > 0 and then Next_Input <= Input_Data'Last loop
         declare
            Chunk_Last : constant Ada.Streams.Stream_Element_Offset :=
              Ada.Streams.Stream_Element_Offset'Min (Input_Data'Last, Next_Input + 2);
            Out_Buffer : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Output_Chunk_Size));
         begin
            Zlib.Translate
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
            Assert (Calls < 2_000_000, "streaming inflate input must make progress");
         end;
      end loop;

      while not Zlib.Stream_End (Filter) loop
         declare
            Out_Buffer : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Output_Chunk_Size));
         begin
            Zlib.Flush
              (Filter   => Filter,
               Out_Data => Out_Buffer,
               Out_Last => Out_Last,
               Flush    => Zlib.Finish);
            Append_Output (Output, Out_Buffer, Out_Last);

            Calls := Calls + 1;
            Assert (Calls < 2_000_000, "streaming inflate finish must make progress");
         end;
      end loop;

      Assert (Zlib.Stream_End (Filter), "Stream_End must be true after trailer validation");
      Zlib.Close (Filter);
      return To_Bytes (Output);
   exception
      when others =>
         if Zlib.Is_Open (Filter) then
            Zlib.Close (Filter, Ignore_Error => True);
         end if;
         raise;
   end Streaming_Inflate;

   procedure Assert_One_Shot_Roundtrip
     (Compressed : Zlib.Byte_Array;
      Header     : Zlib.Header_Type;
      Expected   : Zlib.Byte_Array;
      Label      : String)
   is
      Status : Zlib.Status_Code;
   begin
      if Header = Zlib.GZip then
         declare
            Decoded : constant Zlib.Byte_Array :=
              Zlib.Inflate_With_Header (Compressed, Zlib.GZip, Status);
         begin
            Assert (Status = Zlib.Ok, Label & ": gzip one-shot status");
            Assert_Same (Decoded, Expected, Label & ": gzip one-shot payload");
         end;
      else
         declare
            Decoded_Default : constant Zlib.Byte_Array := Zlib.Inflate (Compressed, Status);
         begin
            Assert (Status = Zlib.Ok, Label & ": Inflate status");
            Assert_Same (Decoded_Default, Expected, Label & ": Inflate payload");
         end;

         declare
            Decoded_Zlib : constant Zlib.Byte_Array :=
              Zlib.Inflate_With_Header (Compressed, Zlib.Zlib_Header, Status);
         begin
            Assert (Status = Zlib.Ok, Label & ": zlib one-shot status");
            Assert_Same (Decoded_Zlib, Expected, Label & ": zlib one-shot payload");
         end;
      end if;
   end Assert_One_Shot_Roundtrip;

   procedure Assert_Roundtrip
     (Payload : Zlib.Byte_Array;
      Header  : Zlib.Header_Type;
      Mode    : Zlib.Compression_Mode;
      Label   : String)
   is
      Compressed : constant Zlib.Byte_Array := Streaming_Compress (Payload, Header, Mode);
      Decoded    : constant Zlib.Byte_Array :=
        Streaming_Inflate (Compressed, Matching_Inflate_Header (Header));
   begin
      Assert_Same (Decoded, Payload, Label & ": streaming payload");
      Assert_One_Shot_Roundtrip (Compressed, Header, Payload, Label);
   end Assert_Roundtrip;

   procedure Assert_One_Shot_Fails
     (Compressed : Zlib.Byte_Array;
      Header     : Zlib.Header_Type;
      Label      : String)
   is
      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Compressed, Header, Status);
      pragma Unreferenced (Output);
   begin
      Assert (Status /= Zlib.Ok, Label & ": one-shot wrong-wrapper status must fail");
   end Assert_One_Shot_Fails;

   procedure Assert_Inflate_OK
     (Compressed : Zlib.Byte_Array;
      Expected   : Zlib.Byte_Array;
      Label      : String)
   is
      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array := Zlib.Inflate (Compressed, Status);
   begin
      Assert (Status = Zlib.Ok, Label & ": Inflate auto-detect status");
      Assert_Same (Output, Expected, Label & ": Inflate auto-detect output");
   end Assert_Inflate_OK;

   procedure Assert_Streaming_Fails
     (Compressed : Zlib.Byte_Array;
      Header     : Zlib.Header_Type;
      Label      : String)
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Output : constant Zlib.Byte_Array := Streaming_Inflate (Compressed, Header);
            pragma Unreferenced (Output);
         begin
            null;
         end;
      exception
         when Zlib.Zlib_Error =>
            Raised := True;
      end;
      Assert (Raised, Label & ": streaming wrong-wrapper must raise Zlib_Error");
   end Assert_Streaming_Fails;

   procedure Check_Payload_Matrix
     (Payload : Zlib.Byte_Array;
      Label   : String)
   is
   begin
      for Header of Supported_Headers loop
         for Mode of Supported_Modes loop
            Assert_Roundtrip
              (Payload, Header, Mode,
               Label & " " & Header_Name (Header) & "+" & Mode_Name (Mode));
         end loop;
      end loop;
   end Check_Payload_Matrix;

   procedure Test_Supported_Matrix_Roundtrips
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Check_Payload_Matrix (Empty_Payload, "empty");
      Check_Payload_Matrix (Hello_Payload, "hello");
      Check_Payload_Matrix (F.Plain_Git_Blob, "git-shaped");
      Check_Payload_Matrix (F.Plain_Binary, "binary");
      Check_Payload_Matrix (F.Plain_Large_Repeated, "repeated");
      Check_Payload_Matrix (Large_Payload, "large");
   end Test_Supported_Matrix_Roundtrips;

   procedure Test_Wrong_Wrapper_Failures
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Zlib_Output : constant Zlib.Byte_Array :=
        Streaming_Compress (F.Plain_Git_Blob, Zlib.Zlib_Header, Zlib.Auto);
      GZip_Output : constant Zlib.Byte_Array :=
        Streaming_Compress (F.Plain_Git_Blob, Zlib.GZip, Zlib.Auto);
   begin
      Assert_One_Shot_Fails (Zlib_Output, Zlib.GZip, "zlib output as gzip");
      Assert_One_Shot_Fails (Zlib_Output, Zlib.Raw_Deflate, "zlib output as raw");
      Assert_Streaming_Fails (Zlib_Output, Zlib.GZip, "zlib output streaming as gzip");
      Assert_Streaming_Fails (Zlib_Output, Zlib.Raw_Deflate, "zlib output streaming as raw");

      Assert_Inflate_OK (GZip_Output, F.Plain_Git_Blob, "gzip output as Inflate default");
      Assert_One_Shot_Fails (GZip_Output, Zlib.Zlib_Header, "gzip output as zlib");
      Assert_One_Shot_Fails (GZip_Output, Zlib.Raw_Deflate, "gzip output as raw");
      Assert_Streaming_Fails (GZip_Output, Zlib.Zlib_Header, "gzip output streaming as zlib");
      Assert_Streaming_Fails (GZip_Output, Zlib.Raw_Deflate, "gzip output streaming as raw");
   end Test_Wrong_Wrapper_Failures;

   procedure Test_Deterministic_Output
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      for Header of Supported_Headers loop
         for Mode of Supported_Modes loop
            declare
               First : constant Zlib.Byte_Array :=
                 Streaming_Compress (F.Plain_Large_Repeated, Header, Mode, 7, 5);
               Second : constant Zlib.Byte_Array :=
                 Streaming_Compress (F.Plain_Large_Repeated, Header, Mode, 7, 5);
            begin
               Assert_Same
                 (Second, First,
                  Header_Name (Header) & "+" & Mode_Name (Mode) & " deterministic output");
            end;
         end loop;
      end loop;
   end Test_Deterministic_Output;

   procedure Test_Chunk_Boundaries
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      for Header of Supported_Headers loop
         for Mode of Supported_Modes loop
            declare
               Payload : constant Zlib.Byte_Array := F.Plain_Binary;
               Full_Output_Size : constant Positive := Payload'Length + 512;
               C1 : constant Zlib.Byte_Array :=
                 Streaming_Compress (Payload, Header, Mode, 1, 1);
               D1 : constant Zlib.Byte_Array :=
                 Streaming_Inflate (C1, Matching_Inflate_Header (Header), 1);
               C2 : constant Zlib.Byte_Array :=
                 Streaming_Compress (Payload, Header, Mode, 2, 3);
               D2 : constant Zlib.Byte_Array :=
                 Streaming_Inflate (C2, Matching_Inflate_Header (Header), 3);
               C3 : constant Zlib.Byte_Array :=
                 Streaming_Compress (Payload, Header, Mode, Payload'Length, Full_Output_Size);
               D3 : constant Zlib.Byte_Array :=
                 Streaming_Inflate (C3, Matching_Inflate_Header (Header), Full_Output_Size);
            begin
               Assert_Same (D1, Payload, Header_Name (Header) & "+" & Mode_Name (Mode) & " chunks 1/1");
               Assert_Same (D2, Payload, Header_Name (Header) & "+" & Mode_Name (Mode) & " chunks 2/3");
               Assert_Same (D3, Payload, Header_Name (Header) & "+" & Mode_Name (Mode) & " full chunks");
            end;
         end loop;
      end loop;
   end Test_Chunk_Boundaries;

   procedure Test_Header_And_Trailer_Sanity
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Zlib_Output : constant Zlib.Byte_Array :=
        Streaming_Compress (F.Plain_Git_Blob, Zlib.Zlib_Header, Zlib.Stored, 1, 1);
      GZip_Output : constant Zlib.Byte_Array :=
        Streaming_Compress (F.Plain_Git_Blob, Zlib.GZip, Zlib.Stored, 1, 1);
      Zlib_Decoded : constant Zlib.Byte_Array := Streaming_Inflate (Zlib_Output, Zlib.Zlib_Header, 1);
      GZip_Decoded : constant Zlib.Byte_Array := Streaming_Inflate (GZip_Output, Zlib.GZip, 1);
   begin
      Assert (Zlib_Output'Length >= 6, "zlib output must include header and Adler-32 trailer");
      Assert (Zlib_Output (Zlib_Output'First) = 16#78#, "zlib deterministic CMF byte");
      Assert (Zlib_Output (Zlib_Output'First + 1) = 16#01#, "zlib deterministic FLG byte");
      Assert_Same (Zlib_Decoded, F.Plain_Git_Blob, "zlib Adler-32 trailer validates through inflate");

      Assert (GZip_Output'Length >= 18, "gzip output must include header and CRC/ISIZE trailer");
      Assert (GZip_Output (GZip_Output'First) = 16#1F#, "gzip ID1");
      Assert (GZip_Output (GZip_Output'First + 1) = 16#8B#, "gzip ID2");
      Assert (GZip_Output (GZip_Output'First + 2) = 16#08#, "gzip compression method");
      Assert (GZip_Output (GZip_Output'First + 3) = 16#00#, "gzip flags");
      Assert (GZip_Output (GZip_Output'First + 4) = 16#00#, "gzip MTIME 0");
      Assert (GZip_Output (GZip_Output'First + 5) = 16#00#, "gzip MTIME 1");
      Assert (GZip_Output (GZip_Output'First + 6) = 16#00#, "gzip MTIME 2");
      Assert (GZip_Output (GZip_Output'First + 7) = 16#00#, "gzip MTIME 3");
      Assert (GZip_Output (GZip_Output'First + 8) = 16#00#, "gzip XFL");
      Assert (GZip_Output (GZip_Output'First + 9) = 16#FF#, "gzip OS");
      Assert_Same (GZip_Decoded, F.Plain_Git_Blob, "gzip CRC32/ISIZE trailer validates through inflate");
   end Test_Header_And_Trailer_Sanity;

   procedure Test_Raw_Deflate_Compression_Matrix
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      for Mode of Supported_Modes loop
         declare
            Raised : Boolean := False;
         begin
            begin
               declare
                  Output : constant Zlib.Byte_Array :=
                    Streaming_Compress (Hello_Payload, Zlib.Raw_Deflate, Mode, 1, 1);
                  pragma Unreferenced (Output);
               begin
                  null;
               end;
            exception
               when Zlib.Zlib_Error =>
                  Raised := True;
            end;
            Assert
              (not Raised,
               "Raw_Deflate+" & Mode_Name (Mode) & " compression must be supported");
         end;
      end loop;
   end Test_Raw_Deflate_Compression_Matrix;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_Supported_Matrix_Roundtrips'Access,
         "supported wrapper/mode/payload matrix roundtrips");
      Registration.Register_Routine
        (T, Test_Wrong_Wrapper_Failures'Access,
         "wrong-wrapper inputs fail deterministically");
      Registration.Register_Routine
        (T, Test_Deterministic_Output'Access,
         "streaming compression output is deterministic");
      Registration.Register_Routine
        (T, Test_Chunk_Boundaries'Access,
         "tiny and full chunk boundaries preserve behavior");
      Registration.Register_Routine
        (T, Test_Header_And_Trailer_Sanity'Access,
         "wrapper headers and trailers validate");
      Registration.Register_Routine
        (T, Test_Raw_Deflate_Compression_Matrix'Access,
         "raw Deflate compression matrix supports all modes");
   end Register_Tests;
end Zlib_Streaming_Compress_Conformance_Tests;
