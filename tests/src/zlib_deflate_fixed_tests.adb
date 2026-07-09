with Ada.Streams;
with CryptoLib.Checksums;
with Interfaces;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;

package body Zlib_Deflate_Fixed_Tests is
   use type Ada.Streams.Stream_Element_Offset;
   use type Interfaces.Unsigned_32;
   use type Zlib.Byte;
   use type Zlib.Status_Code;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib.Deflate_Fixed");
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
     (Input   : Zlib.Byte_Array;
      Message : String)
   is
      Deflate_Status : Zlib.Status_Code;
      Inflate_Status : Zlib.Status_Code;
      Compressed     : constant Zlib.Byte_Array :=
        Zlib.Deflate_Fixed (Input, Deflate_Status);
      Output         : constant Zlib.Byte_Array :=
        Zlib.Inflate (Compressed, Inflate_Status);
   begin
      Assert (Deflate_Status = Zlib.Ok, Message & ": Deflate_Fixed status");
      Assert (Inflate_Status = Zlib.Ok, Message & ": Inflate status");
      Assert_Same (Output, Input, Message & ": roundtrip");

      Assert
        (Compressed'Length >= 7,
         Message & ": fixed zlib stream must contain header, block, and footer");

      Assert
        (Compressed (Compressed'First) = 16#78#
         and then Compressed (Compressed'First + 1) = 16#01#,
         Message & ": fixed stream must use the conservative zlib wrapper");

      Assert
        ((Compressed (Compressed'First + 2) and 2#0000_0111#) = 2#0000_0011#,
         Message & ": first Deflate block must be final fixed-Huffman block");
   end Assert_Roundtrip;

   procedure Inflate_Stream
     (Input       : Zlib.Byte_Array;
      Expected    : Zlib.Byte_Array;
      Chunk_Size  : Positive;
      Output_Size : Positive;
      Message     : String)
   is
      Filter : Zlib.Filter_Type;
      Pos    : Natural := Input'First;
      Result : Zlib.Byte_Array (1 .. Natural'Max (Expected'Length, 1));
      Last   : Natural := 0;

      procedure Copy_Output
        (Out_Data : Ada.Streams.Stream_Element_Array;
         Out_Last : Ada.Streams.Stream_Element_Offset)
      is
      begin
         if Out_Last = Before_First (Out_Data) then
            return;
         end if;

         for I in Out_Data'First .. Out_Last loop
            Last := Last + 1;
            Assert
              (Last <= Expected'Length,
               Message & ": streaming inflate produced too many bytes");
            Result (Last) := Zlib.Byte (Out_Data (I));
         end loop;
      end Copy_Output;
   begin
      Zlib.Inflate_Init (Filter);

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
            Copy_Output (Out_Data, Out_Last);

            if In_Last /= Before_First (In_Data) then
               Pos := Pos + Natural (In_Last - In_Data'First + 1);
            end if;
         end;

         for Guard in 1 .. 10_000 loop
            declare
               Empty_In : constant Ada.Streams.Stream_Element_Array (1 .. 0) := [];
               Out_Data : Ada.Streams.Stream_Element_Array
                 (1 .. Ada.Streams.Stream_Element_Offset (Output_Size));
               In_Last  : Ada.Streams.Stream_Element_Offset;
               Out_Last : Ada.Streams.Stream_Element_Offset;
            begin
               Zlib.Translate (Filter, Empty_In, In_Last, Out_Data, Out_Last);
               Copy_Output (Out_Data, Out_Last);
               exit when Out_Last = Before_First (Out_Data);
            end;
         end loop;
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
            Copy_Output (Out_Data, Out_Last);
            exit when Out_Last = Before_First (Out_Data);
         end;
      end loop;

      Assert (Zlib.Stream_End (Filter), Message & ": stream end");
      Zlib.Close (Filter);
      Assert (Last = Expected'Length, Message & ": streaming decoded length");

      for I in Expected'Range loop
         Assert
           (Result (I - Expected'First + 1) = Expected (I),
            Message & ": streaming decoded byte mismatch");
      end loop;
   end Inflate_Stream;

   function Footer_Value
     (Data : Zlib.Byte_Array)
      return Interfaces.Unsigned_32
   is
      First : constant Natural := Data'Last - 3;
   begin
      return Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (First)), 24)
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (First + 1)), 16)
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (First + 2)), 8)
        or Interfaces.Unsigned_32 (Data (First + 3));
   end Footer_Value;

   function Expected_Adler
     (Input : Zlib.Byte_Array)
      return Interfaces.Unsigned_32
   is
      State : CryptoLib.Checksums.Adler32_State;
   begin
      CryptoLib.Checksums.Adler32_Reset (State);
      for B of Input loop
         CryptoLib.Checksums.Adler32_Update (State, Ada.Streams.Stream_Element (B));
      end loop;
      return CryptoLib.Checksums.Adler32_Value (State);
   end Expected_Adler;

   procedure Test_Roundtrip_Empty
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array (1 .. 0) := [others => 0];
   begin
      Assert_Roundtrip (Input, "empty fixed-Huffman input");
   end Test_Roundtrip_Empty;

   procedure Test_Roundtrip_Hello
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array :=
        [1 => Zlib.Byte (Character'Pos ('h')),
         2 => Zlib.Byte (Character'Pos ('e')),
         3 => Zlib.Byte (Character'Pos ('l')),
         4 => Zlib.Byte (Character'Pos ('l')),
         5 => Zlib.Byte (Character'Pos ('o'))];
   begin
      Assert_Roundtrip (Input, "hello fixed-Huffman input");
   end Test_Roundtrip_Hello;

   procedure Test_Roundtrip_Binary
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input : Zlib.Byte_Array (1 .. 256);
   begin
      for I in Input'Range loop
         Input (I) := Zlib.Byte (I - 1);
      end loop;

      Assert_Roundtrip (Input, "binary fixed-Huffman input");
   end Test_Roundtrip_Binary;

   procedure Test_Roundtrip_Git_Shaped_Payload
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
         14 => Zlib.Byte (Character'Pos (' ')),
         15 => Zlib.Byte (Character'Pos ('w')),
         16 => Zlib.Byte (Character'Pos ('o')),
         17 => Zlib.Byte (Character'Pos ('r')),
         18 => Zlib.Byte (Character'Pos ('l')),
         19 => Zlib.Byte (Character'Pos ('d')),
         20 => Zlib.Byte (Character'Pos (ASCII.LF))];
   begin
      Assert_Roundtrip (Input, "Git-shaped fixed-Huffman payload");
   end Test_Roundtrip_Git_Shaped_Payload;

   procedure Test_Streaming_Inflate_Accepts_Fixed_Output
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array :=
        [1  => Zlib.Byte (Character'Pos ('s')),
         2  => Zlib.Byte (Character'Pos ('t')),
         3  => Zlib.Byte (Character'Pos ('r')),
         4  => Zlib.Byte (Character'Pos ('e')),
         5  => Zlib.Byte (Character'Pos ('a')),
         6  => Zlib.Byte (Character'Pos ('m')),
         7  => Zlib.Byte (Character'Pos ('i')),
         8  => Zlib.Byte (Character'Pos ('n')),
         9  => Zlib.Byte (Character'Pos ('g')),
         10 => Zlib.Byte (Character'Pos ('-')),
         11 => Zlib.Byte (Character'Pos ('f')),
         12 => Zlib.Byte (Character'Pos ('i')),
         13 => Zlib.Byte (Character'Pos ('x')),
         14 => Zlib.Byte (Character'Pos ('e')),
         15 => Zlib.Byte (Character'Pos ('d'))];
      Deflate_Status : Zlib.Status_Code;
      Compressed     : constant Zlib.Byte_Array :=
        Zlib.Deflate_Fixed (Input, Deflate_Status);
   begin
      Assert
        (Deflate_Status = Zlib.Ok,
         "Deflate_Fixed must succeed before streaming roundtrip");

      Inflate_Stream
        (Input       => Compressed,
         Expected    => Input,
         Chunk_Size  => 2,
         Output_Size => 3,
         Message     => "fixed output accepted by streaming Inflate");
   end Test_Streaming_Inflate_Accepts_Fixed_Output;

   procedure Test_Empty_Output_Exact_Form
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input      : constant Zlib.Byte_Array (1 .. 0) := [others => 0];
      Expected   : constant Zlib.Byte_Array :=
        [1 => 16#78#,
         2 => 16#01#,
         3 => 16#03#,
         4 => 16#00#,
         5 => 16#00#,
         6 => 16#00#,
         7 => 16#00#,
         8 => 16#01#];
      Status     : Zlib.Status_Code;
      Compressed : constant Zlib.Byte_Array := Zlib.Deflate_Fixed (Input, Status);
   begin
      Assert
        (Status = Zlib.Ok,
         "Deflate_Fixed must succeed for empty exact-form test");
      Assert_Same
        (Actual   => Compressed,
         Expected => Expected,
         Message  => "empty fixed-Huffman stream exact bytes");
   end Test_Empty_Output_Exact_Form;

   procedure Test_Adler_Footer_Is_Correct
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array :=
        [1 => 1, 2 => 2, 3 => 3, 4 => 4, 5 => 5, 6 => 250];
      Status     : Zlib.Status_Code;
      Compressed : constant Zlib.Byte_Array := Zlib.Deflate_Fixed (Input, Status);
   begin
      Assert (Status = Zlib.Ok, "Deflate_Fixed must succeed for Adler test");
      Assert
        (Footer_Value (Compressed) = Expected_Adler (Input),
         "Deflate_Fixed Adler-32 footer must match input checksum");
   end Test_Adler_Footer_Is_Correct;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_Roundtrip_Empty'Access,
         "Deflate_Fixed empty input roundtrips");

      Registration.Register_Routine
        (T, Test_Roundtrip_Hello'Access,
         "Deflate_Fixed hello input roundtrips");

      Registration.Register_Routine
        (T, Test_Roundtrip_Binary'Access,
         "Deflate_Fixed binary input roundtrips");

      Registration.Register_Routine
        (T, Test_Roundtrip_Git_Shaped_Payload'Access,
         "Deflate_Fixed Git-shaped payload roundtrips");

      Registration.Register_Routine
        (T, Test_Streaming_Inflate_Accepts_Fixed_Output'Access,
         "Deflate_Fixed output streams through Inflate");

      Registration.Register_Routine
        (T, Test_Empty_Output_Exact_Form'Access,
         "Deflate_Fixed empty output has exact fixed-block form");

      Registration.Register_Routine
        (T, Test_Adler_Footer_Is_Correct'Access,
         "Deflate_Fixed Adler footer is correct");
   end Register_Tests;

end Zlib_Deflate_Fixed_Tests;
