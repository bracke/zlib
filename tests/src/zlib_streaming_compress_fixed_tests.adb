with Ada.Containers.Vectors;
with Ada.Streams;
with Interfaces;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;

package body Zlib_Streaming_Compress_Fixed_Tests is
   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Offset;
   use type Interfaces.Unsigned_32;
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
      return AUnit.Format ("Zlib streaming fixed compression");
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
         declare
            Empty : constant Zlib.Byte_Array (1 .. 0) := [others => 0];
         begin
            return Empty;
         end;
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
      Mode               : Zlib.Compression_Mode := Zlib.Fixed;
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
            Assert (Calls < 1_000_000, "fixed compression input loop must make progress");
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
            Assert (Calls < 1_000_000, "fixed compression finish loop must make progress");
         end;
      end loop;

      Zlib.Compress_Close (Filter);
      return To_Bytes (Output);
   end Compress_All;

   function Hello return Zlib.Byte_Array is
   begin
      return
        [1 => Zlib.Byte (Character'Pos ('h')),
         2 => Zlib.Byte (Character'Pos ('e')),
         3 => Zlib.Byte (Character'Pos ('l')),
         4 => Zlib.Byte (Character'Pos ('l')),
         5 => Zlib.Byte (Character'Pos ('o'))];
   end Hello;

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

   function Expected_Adler
     (Input : Zlib.Byte_Array)
      return Interfaces.Unsigned_32
   is
      A : Interfaces.Unsigned_32 := 1;
      B : Interfaces.Unsigned_32 := 0;
      Mod_Adler : constant Interfaces.Unsigned_32 := 65_521;
   begin
      for Byte of Input loop
         A := (A + Interfaces.Unsigned_32 (Byte)) mod Mod_Adler;
         B := (B + A) mod Mod_Adler;
      end loop;
      return Interfaces.Shift_Left (B, 16) or A;
   end Expected_Adler;

   procedure Assert_Adler_Footer
     (Compressed : Zlib.Byte_Array;
      Input      : Zlib.Byte_Array;
      Message    : String)
   is
      Actual : constant Interfaces.Unsigned_32 :=
        Interfaces.Shift_Left
          (Interfaces.Unsigned_32 (Compressed (Compressed'Last - 3)), 24)
        or Interfaces.Shift_Left
          (Interfaces.Unsigned_32 (Compressed (Compressed'Last - 2)), 16)
        or Interfaces.Shift_Left
          (Interfaces.Unsigned_32 (Compressed (Compressed'Last - 1)), 8)
        or Interfaces.Unsigned_32 (Compressed (Compressed'Last));
   begin
      Assert (Actual = Expected_Adler (Input), Message & ": Adler footer mismatch");
   end Assert_Adler_Footer;

   procedure Assert_Inflates_To
     (Compressed : Zlib.Byte_Array;
      Expected   : Zlib.Byte_Array;
      Message    : String)
   is
      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array := Zlib.Inflate (Compressed, Status);
   begin
      Assert (Status = Zlib.Ok, Message & ": one-shot Inflate status must be Ok");
      Assert_Same (Output, Expected, Message);
   end Assert_Inflates_To;

   procedure Assert_Streaming_Inflates_To
     (Compressed : Zlib.Byte_Array;
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
      Zlib.Inflate_Init (Filter, Header => Zlib.Zlib_Header);
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
      Assert_Same (To_Bytes (Output), Expected, Message);
   end Assert_Streaming_Inflates_To;

   procedure Assert_One_Shot_Fixed_Equivalent
     (Input   : Zlib.Byte_Array;
      Message : String)
   is
      Status    : Zlib.Status_Code;
      One_Shot  : constant Zlib.Byte_Array := Zlib.Deflate_Fixed (Input, Status);
      Streaming : constant Zlib.Byte_Array :=
        Compress_All
          (Input,
           Header             => Zlib.Zlib_Header,
           Mode               => Zlib.Fixed,
           Input_Chunk_Size   => 1024,
           Output_Buffer_Size => 128);
   begin
      Assert (Status = Zlib.Ok, Message & ": one-shot fixed status must be Ok");
      Assert_Same (Streaming, One_Shot, Message & ": streaming fixed equals one-shot");
   end Assert_One_Shot_Fixed_Equivalent;

   procedure Test_Empty_Input (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Input      : constant Zlib.Byte_Array (1 .. 0) := [others => 0];
      Compressed : constant Zlib.Byte_Array := Compress_All (Input);
   begin
      Assert (Compressed (Compressed'First) = 16#78#, "fixed empty zlib CMF");
      Assert (Compressed (Compressed'First + 1) = 16#01#, "fixed empty zlib FLG");
      Assert ((Compressed (Compressed'First + 2) and 2#111#) = 2#011#,
              "empty fixed stream must start final fixed block");
      Assert (Compressed'Length = 8, "empty fixed stream exact length");
      Assert (Compressed (Compressed'First + 2) = 16#03#,
              "empty fixed stream first Deflate byte");
      Assert (Compressed (Compressed'First + 3) = 16#00#,
              "empty fixed stream flushed EOB byte");
      Assert_Adler_Footer (Compressed, Input, "empty fixed stream");
      Assert_Inflates_To (Compressed, Input, "empty fixed stream");
      Assert_Streaming_Inflates_To (Compressed, Input, "empty fixed streaming inflate");
   end Test_Empty_Input;

   procedure Test_Hello_Input (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Input      : constant Zlib.Byte_Array := Hello;
      Compressed : constant Zlib.Byte_Array := Compress_All (Input);
   begin
      Assert_Adler_Footer (Compressed, Input, "hello fixed stream");
      Assert_One_Shot_Fixed_Equivalent (Input, "hello fixed stream");
      Assert_Inflates_To (Compressed, Input, "hello fixed stream");
      Assert_Streaming_Inflates_To (Compressed, Input, "hello fixed streaming inflate");
   end Test_Hello_Input;

   procedure Test_Binary_Payload (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Input : Zlib.Byte_Array (1 .. 512);
   begin
      for I in Input'Range loop
         Input (I) := Zlib.Byte ((I * 37) mod 256);
      end loop;
      Assert_Inflates_To
        (Compress_All (Input, Input_Chunk_Size => 5, Output_Buffer_Size => 2),
         Input,
         "binary fixed stream");
   end Test_Binary_Payload;

   procedure Test_Git_Shaped_Payload (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array := Git_Shaped;
   begin
      Assert_Inflates_To
        (Compress_All (Input, Input_Chunk_Size => 1, Output_Buffer_Size => 1),
         Input,
         "Git-shaped byte-by-byte fixed stream");
   end Test_Git_Shaped_Payload;

   procedure Test_Output_Buffer_Size_One (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array := Hello;
   begin
      Assert_Inflates_To
        (Compress_All
           (Input,
            Input_Chunk_Size   => 1,
            Output_Buffer_Size => 1,
            Finish_In_Compress => True),
         Input,
         "fixed stream with one-byte input/output chunks");
   end Test_Output_Buffer_Size_One;

   procedure Test_Repeated_Input_Uses_Streaming_Matcher
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input : Zlib.Byte_Array (1 .. 768);
   begin
      for I in Input'Range loop
         case I mod 6 is
            when 0 => Input (I) := Zlib.Byte (Character'Pos ('a'));
            when 1 => Input (I) := Zlib.Byte (Character'Pos ('b'));
            when 2 => Input (I) := Zlib.Byte (Character'Pos ('c'));
            when 3 => Input (I) := Zlib.Byte (Character'Pos ('a'));
            when 4 => Input (I) := Zlib.Byte (Character'Pos ('b'));
            when others => Input (I) := Zlib.Byte (Character'Pos ('c'));
         end case;
      end loop;

      Assert_One_Shot_Fixed_Equivalent
        (Input,
         "repeated fixed stream should use the same LZ77 tokenization as one-shot fixed");
      Assert_Inflates_To
        (Compress_All (Input, Input_Chunk_Size => 1024, Output_Buffer_Size => 1),
         Input,
         "repeated fixed stream with one-byte output buffer");
   end Test_Repeated_Input_Uses_Streaming_Matcher;

   procedure Test_Finish_State_And_Close (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Filter   : Zlib.Compression_Filter_Type;
      Input    : constant Ada.Streams.Stream_Element_Array (1 .. 1) := [1 => 42];
      Out_Data : Ada.Streams.Stream_Element_Array (1 .. 1);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Raised   : Boolean := False;
   begin
      Zlib.Deflate_Init (Filter, Header => Zlib.Zlib_Header, Mode => Zlib.Fixed);
      Zlib.Compress (Filter, Input, In_Last, Out_Data, Out_Last, Flush => Zlib.No_Flush);
      Assert (not Zlib.Compress_Stream_End (Filter), "fixed stream end false before Finish");

      while not Zlib.Compress_Stream_End (Filter) loop
         Zlib.Compress_Flush (Filter, Out_Data, Out_Last, Flush => Zlib.Finish);
      end loop;

      Assert (Zlib.Compress_Stream_End (Filter), "fixed stream end true after footer");
      Zlib.Compress_Close (Filter);

      Zlib.Deflate_Init (Filter, Header => Zlib.Zlib_Header, Mode => Zlib.Fixed);
      begin
         Zlib.Compress_Close (Filter, Ignore_Error => False);
      exception
         when Zlib.Zlib_Error =>
            Raised := True;
      end;
      Assert (Raised, "fixed Compress_Close before Finish must raise Zlib_Error");
      Zlib.Deflate_Init (Filter, Header => Zlib.Zlib_Header, Mode => Zlib.Fixed);
      Zlib.Compress_Close (Filter, Ignore_Error => True);
   end Test_Finish_State_And_Close;

   procedure Test_Auto_Uses_Scored_Block_Selection (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Input      : constant Zlib.Byte_Array := Hello;
      Compressed : constant Zlib.Byte_Array :=
        Compress_All (Input, Header => Zlib.Default, Mode => Zlib.Auto);
   begin
      Assert_Inflates_To
        (Compressed, Input,
         "Auto streaming compression uses a valid scored block policy");
   end Test_Auto_Uses_Scored_Block_Selection;

   procedure Test_Large_Input_Emits_Non_Final_Block
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input : Zlib.Byte_Array (1 .. 70_000);
   begin
      for I in Input'Range loop
         Input (I) := Zlib.Byte ((I * 13 + I / 17) mod 256);
      end loop;

      Assert_Inflates_To
        (Compress_All
           (Input,
            Input_Chunk_Size   => 257,
            Output_Buffer_Size => 7),
         Input,
         "large fixed stream with non-final block");
   end Test_Large_Input_Emits_Non_Final_Block;

   procedure Test_No_Flush_Does_Not_Finalise_Partial_Block
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Compression_Filter_Type;
      Input    : constant Ada.Streams.Stream_Element_Array (1 .. 3) :=
        [1 => 1, 2 => 2, 3 => 3];
      Out_Data : Ada.Streams.Stream_Element_Array (1 .. 64);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
   begin
      Zlib.Deflate_Init (Filter, Header => Zlib.Zlib_Header, Mode => Zlib.Fixed);
      Zlib.Compress
        (Filter, Input, In_Last, Out_Data, Out_Last, Flush => Zlib.No_Flush);

      Assert (In_Last = Input'Last, "fixed No_Flush should consume available input");
      Assert
        (not Zlib.Compress_Stream_End (Filter),
         "fixed No_Flush must not finalise a partial block");

      Zlib.Compress_Close (Filter, Ignore_Error => True);
   end Test_No_Flush_Does_Not_Finalise_Partial_Block;

   procedure Expect_Unsupported
     (Header : Zlib.Header_Type;
      Mode   : Zlib.Compression_Mode;
      Label  : String)
   is
      Filter   : Zlib.Compression_Filter_Type;
      Input    : constant Ada.Streams.Stream_Element_Array (1 .. 1) := [1 => 1];
      Output   : Ada.Streams.Stream_Element_Array (1 .. 8);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Raised   : Boolean := False;
   begin
      Zlib.Deflate_Init (Filter, Header => Header, Mode => Mode);
      begin
         Zlib.Compress (Filter, Input, In_Last, Output, Out_Last);
      exception
         when Zlib.Zlib_Error =>
            Raised := True;
      end;
      Assert (Raised, Label & " must raise Zlib_Error");
      Zlib.Compress_Close (Filter, Ignore_Error => True);
   end Expect_Unsupported;
   pragma Unreferenced (Expect_Unsupported);

   procedure Expect_Unsupported_Flush
     (Header : Zlib.Header_Type;
      Mode   : Zlib.Compression_Mode;
      Label  : String)
   is
      Filter   : Zlib.Compression_Filter_Type;
      Output   : Ada.Streams.Stream_Element_Array (1 .. 8);
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Raised   : Boolean := False;
   begin
      Zlib.Deflate_Init (Filter, Header => Header, Mode => Mode);
      begin
         Zlib.Compress_Flush (Filter, Output, Out_Last, Flush => Zlib.Finish);
      exception
         when Zlib.Zlib_Error =>
            Raised := True;
      end;
      Assert (Raised, Label & " Compress_Flush must raise Zlib_Error");
      Zlib.Compress_Close (Filter, Ignore_Error => True);
   end Expect_Unsupported_Flush;
   pragma Unreferenced (Expect_Unsupported_Flush);

   procedure Test_Raw_Fixed_And_Auto_Roundtrip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input      : constant Zlib.Byte_Array := Git_Shaped;
      Fixed_Raw  : constant Zlib.Byte_Array :=
        Compress_All
          (Input,
           Header             => Zlib.Raw_Deflate,
           Mode               => Zlib.Fixed,
           Input_Chunk_Size   => 1,
           Output_Buffer_Size => 1);
      Auto_Raw   : constant Zlib.Byte_Array :=
        Compress_All
          (Input,
           Header             => Zlib.Raw_Deflate,
           Mode               => Zlib.Auto,
           Input_Chunk_Size   => 3,
           Output_Buffer_Size => 2);
      Status        : Zlib.Status_Code;
      Mismatch      : Zlib.Status_Code;
      Inflated      : Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Fixed_Raw, Zlib.Raw_Deflate, Status);
      Wrong_Wrapper : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Fixed_Raw, Zlib.Zlib_Header, Mismatch);
      pragma Unreferenced (Wrong_Wrapper);
   begin
      Assert (Fixed_Raw'Length > 0, "raw fixed stream should produce bytes");
      Assert (Mismatch /= Zlib.Ok, "raw fixed stream must not decode as zlib");
      Assert (Status = Zlib.Ok, "raw fixed stream should inflate successfully");
      Assert_Same (Inflated, Input, "raw fixed stream roundtrip");

      Inflated := Zlib.Inflate_With_Header (Auto_Raw, Zlib.Raw_Deflate, Status);
      Assert (Auto_Raw'Length > 0, "raw Auto stream should produce bytes");
      Assert (Status = Zlib.Ok, "raw Auto stream should inflate successfully");
      Assert_Same (Inflated, Input, "raw Auto stream roundtrip");
   end Test_Raw_Fixed_And_Auto_Roundtrip;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine (T, Test_Empty_Input'Access, "streaming fixed compression empty input");
      Registration.Register_Routine (T, Test_Hello_Input'Access, "streaming fixed compression hello");
      Registration.Register_Routine (T, Test_Binary_Payload'Access, "streaming fixed compression binary payload");
      Registration.Register_Routine
        (T, Test_Git_Shaped_Payload'Access,
         "streaming fixed compression Git-shaped payload");
      Registration.Register_Routine
        (T, Test_Output_Buffer_Size_One'Access,
         "fixed input chunk size 1 and output buffer size 1");
      Registration.Register_Routine
        (T, Test_Repeated_Input_Uses_Streaming_Matcher'Access,
         "streaming fixed compression uses LZ77 matcher on repeated input");
      Registration.Register_Routine
        (T, Test_Finish_State_And_Close'Access,
         "fixed Finish state and Compress_Close rules");
      Registration.Register_Routine
        (T, Test_Auto_Uses_Scored_Block_Selection'Access,
         "Fixed suite: Auto uses scored block selection");
      Registration.Register_Routine
        (T, Test_Large_Input_Emits_Non_Final_Block'Access,
         "large fixed input emits non-final block and roundtrips");
      Registration.Register_Routine
        (T, Test_No_Flush_Does_Not_Finalise_Partial_Block'Access,
         "fixed No_Flush does not finalise a partial block");
      Registration.Register_Routine
        (T, Test_Raw_Fixed_And_Auto_Roundtrip'Access,
         "raw fixed and raw Auto streaming compression roundtrip");
   end Register_Tests;
end Zlib_Streaming_Compress_Fixed_Tests;
