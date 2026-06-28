with Ada.Containers.Vectors;
with Ada.Streams;
with Interfaces;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;

package body Zlib_Streaming_Compress_Stored_Tests is
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
      return AUnit.Format ("Zlib streaming stored compression");
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
     (Input             : Zlib.Byte_Array;
      Header            : Zlib.Header_Type := Zlib.Zlib_Header;
      Mode              : Zlib.Compression_Mode := Zlib.Stored;
      Input_Chunk_Size  : Positive := 1024;
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
            Out_Buffer : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Output_Buffer_Size));
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
            Assert (Calls < 1_000_000, "streaming compression input loop must make progress");
         end;
      end loop;

      while not Zlib.Compress_Stream_End (Filter) loop
         declare
            Out_Buffer : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Output_Buffer_Size));
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
      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Compressed, Zlib.Zlib_Header, Status);
   begin
      Assert (Status = Zlib.Ok, Message & ": explicit zlib inflate status must be Ok");
      Assert_Same (Output, Expected, Message);
   end Assert_Streaming_Inflates_To;

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
      Assert
        (Actual = Expected_Adler (Input),
         Message & ": zlib Adler-32 footer must be big-endian and valid");
   end Assert_Adler_Footer;

   function Hello return Zlib.Byte_Array is
   begin
      return
        [1 => Zlib.Byte (Character'Pos ('h')),
         2 => Zlib.Byte (Character'Pos ('e')),
         3 => Zlib.Byte (Character'Pos ('l')),
         4 => Zlib.Byte (Character'Pos ('l')),
         5 => Zlib.Byte (Character'Pos ('o'))];
   end Hello;

   procedure Test_Empty_Input (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Input      : constant Zlib.Byte_Array (1 .. 0) := [others => 0];
      Compressed : constant Zlib.Byte_Array := Compress_All (Input);
   begin
      Assert (Compressed'Length = 11, "empty stored stream length must be deterministic");
      Assert (Compressed (Compressed'First) = 16#78#, "zlib CMF must be 0x78");
      Assert (Compressed (Compressed'First + 1) = 16#01#, "zlib FLG must be 0x01");
      Assert_Adler_Footer (Compressed, Input, "empty streaming stored roundtrip");
      Assert_Inflates_To (Compressed, Input, "empty streaming stored roundtrip");
   end Test_Empty_Input;

   procedure Test_Hello_Input (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Input      : constant Zlib.Byte_Array := Hello;
      Compressed : constant Zlib.Byte_Array := Compress_All (Input);
   begin
      Assert (Compressed (Compressed'First) = 16#78#, "zlib CMF must be deterministic");
      Assert (Compressed (Compressed'First + 1) = 16#01#, "zlib FLG must be deterministic");
      Assert_Adler_Footer (Compressed, Input, "hello streaming stored roundtrip");
      Assert_Inflates_To (Compressed, Input, "hello streaming stored roundtrip");
      Assert_Streaming_Inflates_To (Compressed, Input, "hello streaming inflate roundtrip");
   end Test_Hello_Input;

   procedure Test_Auto_Mode_Uses_Scored_Block_Selection
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input      : constant Zlib.Byte_Array := Hello;
      Compressed : constant Zlib.Byte_Array :=
        Compress_All (Input, Header => Zlib.Default, Mode => Zlib.Auto);
   begin
      Assert (Compressed (Compressed'First) = 16#78#, "Auto streaming compression must use zlib header");
      Assert (Compressed (Compressed'First + 1) = 16#01#, "Auto streaming compression must keep zlib FLG");
      Assert_Adler_Footer (Compressed, Input, "Auto streaming roundtrip");
      Assert_Inflates_To (Compressed, Input, "Auto mode must roundtrip after scored block selection");
   end Test_Auto_Mode_Uses_Scored_Block_Selection;

   procedure Test_Binary_Payload (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Input : Zlib.Byte_Array (1 .. 512);
   begin
      for I in Input'Range loop
         Input (I) := Zlib.Byte ((I * 37) mod 256);
      end loop;
      Assert_Inflates_To
        (Compress_All (Input, Input_Chunk_Size => 7, Output_Buffer_Size => 3),
         Input,
         "binary streaming stored roundtrip");
   end Test_Binary_Payload;

   procedure Test_Git_Shaped_Payload (T : in out AUnit.Test_Cases.Test_Case'Class) is
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
      Assert_Inflates_To
        (Compress_All (Input, Input_Chunk_Size => 1, Output_Buffer_Size => 1),
         Input,
         "Git-shaped byte-by-byte streaming stored roundtrip");
   end Test_Git_Shaped_Payload;

   procedure Test_Large_Input_Splits_Blocks (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Input : Zlib.Byte_Array (1 .. 70_000);
   begin
      for I in Input'Range loop
         Input (I) := Zlib.Byte (I mod 251);
      end loop;

      declare
         Compressed : constant Zlib.Byte_Array :=
           Compress_All (Input, Input_Chunk_Size => 4096, Output_Buffer_Size => 17);
         Pos         : Natural := Compressed'First + 2;
         Blocks      : Natural := 0;
         Final_Seen  : Boolean := False;
      begin
         while not Final_Seen loop
            declare
               Header : constant Zlib.Byte := Compressed (Pos);
               Len    : constant Natural :=
                 Natural (Compressed (Pos + 1)) + 256 * Natural (Compressed (Pos + 2));
               NLen   : constant Natural :=
                 Natural (Compressed (Pos + 3)) + 256 * Natural (Compressed (Pos + 4));
            begin
               Assert ((Header and 16#FE#) = 0, "stored block BTYPE must be 00");
               Assert ((Len + NLen) = 65_535, "stored block NLEN must complement LEN");
               Blocks := Blocks + 1;
               Final_Seen := (Header and 1) = 1;
               Pos := Pos + 5 + Len;
            end;
         end loop;

         Assert (Blocks >= 2, "large streaming compression must split stored blocks");
         Assert_Inflates_To (Compressed, Input, "large streaming stored roundtrip");
      end;
   end Test_Large_Input_Splits_Blocks;

   procedure Test_Finish_State_And_Close (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Filter   : Zlib.Compression_Filter_Type;
      Input    : constant Ada.Streams.Stream_Element_Array (1 .. 1) := [1 => 42];
      Out_Data : Ada.Streams.Stream_Element_Array (1 .. 1);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Raised   : Boolean := False;
   begin
      Zlib.Deflate_Init (Filter, Header => Zlib.Default, Mode => Zlib.Auto);
      Zlib.Compress (Filter, Input, In_Last, Out_Data, Out_Last, Flush => Zlib.No_Flush);
      Assert (not Zlib.Compress_Stream_End (Filter), "stream end must be false before Finish");

      while not Zlib.Compress_Stream_End (Filter) loop
         Zlib.Compress_Flush (Filter, Out_Data, Out_Last, Flush => Zlib.Finish);
      end loop;

      Assert (Zlib.Compress_Stream_End (Filter), "stream end must be true after footer");
      Zlib.Compress_Close (Filter);

      Zlib.Deflate_Init (Filter, Header => Zlib.Zlib_Header, Mode => Zlib.Stored);
      begin
         Zlib.Compress_Close (Filter, Ignore_Error => False);
      exception
         when Zlib.Zlib_Error =>
            Raised := True;
      end;
      Assert (Raised, "Compress_Close before Finish must raise Zlib_Error");

      Zlib.Deflate_Init (Filter, Header => Zlib.Zlib_Header, Mode => Zlib.Stored);
      Zlib.Compress_Close (Filter, Ignore_Error => True);
   end Test_Finish_State_And_Close;

   procedure Test_No_Flush_Does_Not_End_Partial_Block
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Compression_Filter_Type;
      Input    : constant Ada.Streams.Stream_Element_Array (1 .. 3) := [1 => 10, 2 => 20, 3 => 30];
      Out_Data : Ada.Streams.Stream_Element_Array (1 .. 32);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
   begin
      Zlib.Deflate_Init (Filter, Header => Zlib.Zlib_Header, Mode => Zlib.Stored);
      Zlib.Compress
        (Filter   => Filter,
         In_Data  => Input,
         In_Last  => In_Last,
         Out_Data => Out_Data,
         Out_Last => Out_Last,
         Flush    => Zlib.No_Flush);
      Assert (In_Last = Input'Last, "No_Flush may consume all input");
      Assert
        (not Zlib.Compress_Stream_End (Filter),
         "No_Flush must not emit a final block for a partial stored block");

      Zlib.Compress_Flush
        (Filter   => Filter,
         Out_Data => Out_Data,
         Out_Last => Out_Last,
         Flush    => Zlib.No_Flush);
      Assert
        (not Zlib.Compress_Stream_End (Filter),
         "Compress_Flush No_Flush must not finish a partial stored block");

      Zlib.Compress_Close (Filter, Ignore_Error => True);
   end Test_No_Flush_Does_Not_End_Partial_Block;

   procedure Test_Finish_In_Compress (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array := Hello;
   begin
      Assert_Inflates_To
        (Compress_All
           (Input,
            Input_Chunk_Size   => 2,
            Output_Buffer_Size => 1,
            Finish_In_Compress => True),
         Input,
         "Finish passed to Compress must emit final block and Adler footer");
   end Test_Finish_In_Compress;

   procedure Test_Raw_Stored_Roundtrip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input         : constant Zlib.Byte_Array := Hello;
      Compressed    : constant Zlib.Byte_Array :=
        Compress_All
          (Input,
           Header             => Zlib.Raw_Deflate,
           Mode               => Zlib.Stored,
           Input_Chunk_Size   => 1,
           Output_Buffer_Size => 1);
      Status        : Zlib.Status_Code;
      Mismatch      : Zlib.Status_Code;
      Inflated      : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Compressed, Zlib.Raw_Deflate, Status);
      Wrong_Wrapper : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Compressed, Zlib.Zlib_Header, Mismatch);
      pragma Unreferenced (Wrong_Wrapper);
   begin
      Assert (Compressed'Length > 0, "raw stored stream should produce bytes");
      Assert (Mismatch /= Zlib.Ok, "raw stored stream must not decode as zlib");
      Assert (Status = Zlib.Ok, "raw stored stream should inflate successfully");
      Assert_Same (Inflated, Input, "raw stored stream roundtrip");
   end Test_Raw_Stored_Roundtrip;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine (T, Test_Empty_Input'Access, "streaming stored compression empty input");
      Registration.Register_Routine (T, Test_Hello_Input'Access, "streaming stored compression hello");
      Registration.Register_Routine
        (T, Test_Auto_Mode_Uses_Scored_Block_Selection'Access,
         "Auto mode uses scored block selection");
      Registration.Register_Routine (T, Test_Binary_Payload'Access, "streaming stored compression binary payload");
      Registration.Register_Routine
        (T, Test_Git_Shaped_Payload'Access,
         "streaming stored compression Git-shaped payload");
      Registration.Register_Routine (T, Test_Large_Input_Splits_Blocks'Access, "large input splits stored blocks");
      Registration.Register_Routine (T, Test_Finish_State_And_Close'Access, "Finish state and Compress_Close rules");
      Registration.Register_Routine
        (T, Test_No_Flush_Does_Not_End_Partial_Block'Access,
         "No_Flush does not end partial stored block");
      Registration.Register_Routine (T, Test_Finish_In_Compress'Access, "Finish emits final block from Compress");
      Registration.Register_Routine
        (T, Test_Raw_Stored_Roundtrip'Access,
         "raw stored streaming compression roundtrip");
   end Register_Tests;
end Zlib_Streaming_Compress_Stored_Tests;
