with Ada.Containers.Vectors;
with Ada.Streams;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;
with Zlib_Fixture_Data;

package body Zlib_Raw_Cross_Wrapper_Conformance_Tests is
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

   Compression_Headers : constant Header_Array :=
     [Zlib.Zlib_Header, Zlib.GZip, Zlib.Raw_Deflate];
   Strict_Inflate_Headers : constant Header_Array :=
     [Zlib.Zlib_Header, Zlib.GZip, Zlib.Raw_Deflate];
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
      return AUnit.Format ("Zlib raw cross-wrapper compression conformance");
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
         return Empty_Payload;
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

   function Matching_Inflate_Header
     (Header : Zlib.Header_Type)
      return Zlib.Header_Type
   is
   begin
      case Header is
         when Zlib.Default | Zlib.Zlib_Header => return Zlib.Zlib_Header;
         when Zlib.GZip                       => return Zlib.GZip;
         when Zlib.Raw_Deflate                => return Zlib.Raw_Deflate;
      end case;
   end Matching_Inflate_Header;

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
      Input_Chunk_Size  : Positive := 3;
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
              Ada.Streams.Stream_Element_Offset'Min
                (Input_Data'Last,
                 Next_Input + Ada.Streams.Stream_Element_Offset (Input_Chunk_Size) - 1);
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

      Assert (Zlib.Stream_End (Filter), "Stream_End must be true after final block/trailer");
      Zlib.Close (Filter);
      return To_Bytes (Output);
   exception
      when others =>
         if Zlib.Is_Open (Filter) then
            Zlib.Close (Filter, Ignore_Error => True);
         end if;
         raise;
   end Streaming_Inflate;

   function One_Shot_Compress
     (Input  : Zlib.Byte_Array;
      Header : Zlib.Header_Type;
      Mode   : Zlib.Compression_Mode)
      return Zlib.Byte_Array
   is
      Status : Zlib.Status_Code;
   begin
      case Header is
         when Zlib.Default | Zlib.Zlib_Header =>
            case Mode is
               when Zlib.Stored =>
                  declare
                     Output : constant Zlib.Byte_Array := Zlib.Deflate_Stored (Input, Status);
                  begin
                     Assert (Status = Zlib.Ok, "Deflate_Stored status");
                     return Output;
                  end;
               when Zlib.Fixed =>
                  declare
                     Output : constant Zlib.Byte_Array := Zlib.Deflate_Fixed (Input, Status);
                  begin
                     Assert (Status = Zlib.Ok, "Deflate_Fixed status");
                     return Output;
                  end;
               when Zlib.Dynamic =>
                  declare
                     Output : constant Zlib.Byte_Array := Zlib.Deflate_Dynamic (Input, Status);
                  begin
                     Assert (Status = Zlib.Ok, "Deflate_Dynamic status");
                     return Output;
                  end;
               when Zlib.Auto =>
                  declare
                     Output : constant Zlib.Byte_Array := Zlib.Deflate (Input, Zlib.Auto, Status);
                  begin
                     Assert (Status = Zlib.Ok, "Deflate Auto status");
                     return Output;
                  end;
            end case;
         when Zlib.GZip =>
            declare
               Output : constant Zlib.Byte_Array := Zlib.GZip (Input, Mode, Status);
            begin
               Assert (Status = Zlib.Ok, "GZip status");
               return Output;
            end;
         when Zlib.Raw_Deflate =>
            declare
               Output : constant Zlib.Byte_Array := Zlib.Deflate_Raw (Input, Mode, Status);
            begin
               Assert (Status = Zlib.Ok, "Deflate_Raw status");
               return Output;
            end;
      end case;
   end One_Shot_Compress;

   procedure Assert_One_Shot_OK
     (Compressed : Zlib.Byte_Array;
      Header     : Zlib.Header_Type;
      Expected   : Zlib.Byte_Array;
      Label      : String)
   is
      Status : Zlib.Status_Code;
   begin
      if Header = Zlib.Default then
         declare
            Output : constant Zlib.Byte_Array := Zlib.Inflate (Compressed, Status);
         begin
            Assert (Status = Zlib.Ok, Label & ": one-shot status");
            Assert_Same (Output, Expected, Label & ": one-shot payload");
         end;
      else
         declare
            Output : constant Zlib.Byte_Array :=
              Zlib.Inflate_With_Header (Compressed, Header, Status);
         begin
            Assert (Status = Zlib.Ok, Label & ": one-shot status");
            Assert_Same (Output, Expected, Label & ": one-shot payload");
         end;
      end if;
   end Assert_One_Shot_OK;

   function One_Shot_Status
     (Compressed : Zlib.Byte_Array;
      Header     : Zlib.Header_Type)
      return Zlib.Status_Code
   is
      Status : Zlib.Status_Code;
   begin
      if Header = Zlib.Default then
         declare
            Output : constant Zlib.Byte_Array := Zlib.Inflate (Compressed, Status);
            pragma Unreferenced (Output);
         begin
            null;
         end;
      else
         declare
            Output : constant Zlib.Byte_Array :=
              Zlib.Inflate_With_Header (Compressed, Header, Status);
            pragma Unreferenced (Output);
         begin
            null;
         end;
      end if;
      return Status;
   end One_Shot_Status;

   procedure Assert_One_Shot_Fails
     (Compressed : Zlib.Byte_Array;
      Header     : Zlib.Header_Type;
      Label      : String)
   is
      First_Status  : constant Zlib.Status_Code := One_Shot_Status (Compressed, Header);
      Second_Status : constant Zlib.Status_Code := One_Shot_Status (Compressed, Header);
   begin
      Assert (First_Status /= Zlib.Ok, Label & ": one-shot wrong-wrapper status must fail");
      Assert
        (Second_Status = First_Status,
         Label & ": one-shot wrong-wrapper status must be deterministic");
   end Assert_One_Shot_Fails;

   procedure Assert_Streaming_OK
     (Compressed : Zlib.Byte_Array;
      Header     : Zlib.Header_Type;
      Expected   : Zlib.Byte_Array;
      Label      : String)
   is
      Output : constant Zlib.Byte_Array := Streaming_Inflate (Compressed, Header, 2, 3);
   begin
      Assert_Same (Output, Expected, Label & ": streaming payload");
   end Assert_Streaming_OK;

   function Streaming_Raises
     (Compressed : Zlib.Byte_Array;
      Header     : Zlib.Header_Type)
      return Boolean
   is
   begin
      declare
         Output : constant Zlib.Byte_Array := Streaming_Inflate (Compressed, Header, 2, 3);
         pragma Unreferenced (Output);
      begin
         return False;
      end;
   exception
      when Zlib.Zlib_Error =>
         return True;
   end Streaming_Raises;

   procedure Assert_Streaming_Fails
     (Compressed : Zlib.Byte_Array;
      Header     : Zlib.Header_Type;
      Label      : String)
   is
   begin
      Assert
        (Streaming_Raises (Compressed, Header),
         Label & ": streaming wrong-wrapper must raise Zlib_Error");
      Assert
        (Streaming_Raises (Compressed, Header),
         Label & ": streaming wrong-wrapper failure must be repeatable");
   end Assert_Streaming_Fails;

   procedure Assert_Strict_One_Shot
     (Compressed : Zlib.Byte_Array;
      Header     : Zlib.Header_Type;
      Payload    : Zlib.Byte_Array;
      Label      : String)
   is
      Match : constant Zlib.Header_Type := Matching_Inflate_Header (Header);
   begin
      if Header = Zlib.Zlib_Header then
         Assert_One_Shot_OK (Compressed, Zlib.Default, Payload, Label & " as Default");
      else
         Assert_One_Shot_Fails (Compressed, Zlib.Default, Label & " as Default");
      end if;

      for Candidate of Strict_Inflate_Headers loop
         if Candidate = Match then
            Assert_One_Shot_OK (Compressed, Candidate, Payload, Label & " as " & Header_Name (Candidate));
         else
            Assert_One_Shot_Fails (Compressed, Candidate, Label & " as " & Header_Name (Candidate));
         end if;
      end loop;
   end Assert_Strict_One_Shot;

   procedure Assert_Strict_Streaming
     (Compressed : Zlib.Byte_Array;
      Header     : Zlib.Header_Type;
      Payload    : Zlib.Byte_Array;
      Label      : String)
   is
      Match : constant Zlib.Header_Type := Matching_Inflate_Header (Header);
   begin
      for Candidate of Strict_Inflate_Headers loop
         if Candidate = Match then
            Assert_Streaming_OK (Compressed, Candidate, Payload, Label & " streaming as " & Header_Name (Candidate));
         else
            Assert_Streaming_Fails (Compressed, Candidate, Label & " streaming as " & Header_Name (Candidate));
         end if;
      end loop;
   end Assert_Strict_Streaming;

   procedure Assert_Output_Layout
     (Compressed : Zlib.Byte_Array;
      Header     : Zlib.Header_Type;
      Label      : String)
   is
   begin
      if Header = Zlib.Zlib_Header then
         Assert (Compressed'Length >= 6, Label & ": zlib output has header and Adler-32");
         Assert (Compressed (Compressed'First) = 16#78#, Label & ": zlib CMF byte");
      elsif Header = Zlib.GZip then
         Assert (Compressed'Length >= 18, Label & ": gzip output has header and trailer");
         Assert (Compressed (Compressed'First) = 16#1F#, Label & ": gzip ID1");
         Assert (Compressed (Compressed'First + 1) = 16#8B#, Label & ": gzip ID2");
      else
         if Compressed'Length >= 2 then
            Assert
              (not (Compressed (Compressed'First) = 16#78#
                    and then
                    (Compressed (Compressed'First + 1) = 16#01#
                     or else Compressed (Compressed'First + 1) = 16#9C#
                     or else Compressed (Compressed'First + 1) = 16#DA#)),
               Label & ": raw output must not begin with a deterministic zlib header");
            Assert
              (not (Compressed (Compressed'First) = 16#1F#
                    and then Compressed (Compressed'First + 1) = 16#8B#),
               Label & ": raw output must not begin with a gzip header");
         end if;
      end if;
   end Assert_Output_Layout;

   procedure Check_One_Shot_Case
     (Payload : Zlib.Byte_Array;
      Label   : String)
   is
   begin
      for Header of Compression_Headers loop
         for Mode of Supported_Modes loop
            declare
               Case_Label : constant String := Label & " one-shot " & Header_Name (Header) & "+" & Mode_Name (Mode);
               First      : constant Zlib.Byte_Array := One_Shot_Compress (Payload, Header, Mode);
               Second     : constant Zlib.Byte_Array := One_Shot_Compress (Payload, Header, Mode);
            begin
               Assert_Same (Second, First, Case_Label & " deterministic");
               Assert_Strict_One_Shot (First, Header, Payload, Case_Label);
               Assert_Output_Layout (First, Header, Case_Label);
            end;
         end loop;
      end loop;
   end Check_One_Shot_Case;

   procedure Check_Streaming_Case
     (Payload : Zlib.Byte_Array;
      Label   : String)
   is
   begin
      for Header of Compression_Headers loop
         for Mode of Supported_Modes loop
            declare
               Case_Label : constant String := Label & " streaming " & Header_Name (Header) & "+" & Mode_Name (Mode);
               First      : constant Zlib.Byte_Array := Streaming_Compress (Payload, Header, Mode, 7, 5);
               Second     : constant Zlib.Byte_Array := Streaming_Compress (Payload, Header, Mode, 7, 5);
            begin
               Assert_Same (Second, First, Case_Label & " deterministic");
               Assert_Strict_One_Shot (First, Header, Payload, Case_Label);
               Assert_Strict_Streaming (First, Header, Payload, Case_Label);
               Assert_Output_Layout (First, Header, Case_Label);
            end;
         end loop;
      end loop;
   end Check_Streaming_Case;

   procedure Test_One_Shot_Wrapper_Matrix
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Check_One_Shot_Case (Empty_Payload, "empty");
      Check_One_Shot_Case (Hello_Payload, "hello");
      Check_One_Shot_Case (F.Plain_Git_Blob, "git-shaped");
      Check_One_Shot_Case (F.Plain_Binary, "binary");
      Check_One_Shot_Case (F.Plain_Large_Repeated, "repeated");
      Check_One_Shot_Case (Large_Payload, "large");
   end Test_One_Shot_Wrapper_Matrix;

   procedure Test_Streaming_Wrapper_Matrix
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Check_Streaming_Case (Empty_Payload, "empty");
      Check_Streaming_Case (Hello_Payload, "hello");
      Check_Streaming_Case (F.Plain_Git_Blob, "git-shaped");
      Check_Streaming_Case (F.Plain_Binary, "binary");
      Check_Streaming_Case (F.Plain_Large_Repeated, "repeated");
      Check_Streaming_Case (Large_Payload, "large");
   end Test_Streaming_Wrapper_Matrix;

   procedure Test_Raw_Chunk_Boundaries
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Payload : constant Zlib.Byte_Array := F.Plain_Binary;
   begin
      for Mode of Supported_Modes loop
         declare
            Full_Output_Size : constant Positive := Payload'Length + 512;
            C1 : constant Zlib.Byte_Array :=
              Streaming_Compress (Payload, Zlib.Raw_Deflate, Mode, 1, 1);
            D1 : constant Zlib.Byte_Array :=
              Streaming_Inflate (C1, Zlib.Raw_Deflate, 1, 1);
            C2 : constant Zlib.Byte_Array :=
              Streaming_Compress (Payload, Zlib.Raw_Deflate, Mode, 2, 3);
            D2 : constant Zlib.Byte_Array :=
              Streaming_Inflate (C2, Zlib.Raw_Deflate, 2, 3);
            C3 : constant Zlib.Byte_Array :=
              Streaming_Compress (Payload, Zlib.Raw_Deflate, Mode, Payload'Length, Full_Output_Size);
            D3 : constant Zlib.Byte_Array :=
              Streaming_Inflate (C3, Zlib.Raw_Deflate, Payload'Length, Full_Output_Size);
         begin
            Assert_Same (D1, Payload, "raw " & Mode_Name (Mode) & " chunks 1/1");
            Assert_Same (D2, Payload, "raw " & Mode_Name (Mode) & " chunks 2/3");
            Assert_Same (D3, Payload, "raw " & Mode_Name (Mode) & " full chunks");
         end;
      end loop;
   end Test_Raw_Chunk_Boundaries;

   procedure Test_One_Shot_Streaming_Raw_Equivalence
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      for Mode of Supported_Modes loop
         declare
            One_Shot : constant Zlib.Byte_Array :=
              One_Shot_Compress (F.Plain_Git_Blob, Zlib.Raw_Deflate, Mode);
            Streamed : constant Zlib.Byte_Array :=
              Streaming_Compress (F.Plain_Git_Blob, Zlib.Raw_Deflate, Mode, F.Plain_Git_Blob'Length, 257);
         begin
            Assert_Same (Streamed, One_Shot, "raw one-shot/streaming equivalence " & Mode_Name (Mode));
         end;
      end loop;
   end Test_One_Shot_Streaming_Raw_Equivalence;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_One_Shot_Wrapper_Matrix'Access,
         "one-shot raw/zlib/gzip wrapper conformance matrix");
      Registration.Register_Routine
        (T, Test_Streaming_Wrapper_Matrix'Access,
         "streaming raw/zlib/gzip wrapper conformance matrix");
      Registration.Register_Routine
        (T, Test_Raw_Chunk_Boundaries'Access,
         "raw Deflate chunk boundaries drain compression and inflate output");
      Registration.Register_Routine
        (T, Test_One_Shot_Streaming_Raw_Equivalence'Access,
         "one-shot and streaming raw compression are byte-equivalent");
   end Register_Tests;
end Zlib_Raw_Cross_Wrapper_Conformance_Tests;
