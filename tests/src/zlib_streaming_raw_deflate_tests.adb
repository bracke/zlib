with Ada.Streams;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;

package body Zlib_Streaming_Raw_Deflate_Tests is
   use type Ada.Streams.Stream_Element_Offset;
   use type Zlib.Byte;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib streaming raw Deflate");
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

   procedure Inflate_Raw
     (Input       : Zlib.Byte_Array;
      Chunk_Size  : Positive;
      Output_Size : Positive;
      Result      : in out Zlib.Byte_Array;
      Result_Last : out Natural)
   is
      Filter : Zlib.Filter_Type;
      Pos    : Natural := Input'First;
   begin
      Result_Last := Result'First - 1;
      Zlib.Inflate_Init (Filter, Zlib.Raw_Deflate);

      while Pos <= Input'Last loop
         declare
            Count : constant Natural := Natural'Min (Chunk_Size, Input'Last - Pos + 1);
            In_Data : Ada.Streams.Stream_Element_Array
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

         for Guard in 1 .. 10_000 loop
            declare
               Empty_In : constant Ada.Streams.Stream_Element_Array (1 .. 0) := [];
               Out_Data : Ada.Streams.Stream_Element_Array
                 (1 .. Ada.Streams.Stream_Element_Offset (Output_Size));
               In_Last  : Ada.Streams.Stream_Element_Offset;
               Out_Last : Ada.Streams.Stream_Element_Offset;
            begin
               Zlib.Translate (Filter, Empty_In, In_Last, Out_Data, Out_Last);
               Copy_Output (Out_Data, Out_Last, Result, Result_Last);
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
            Copy_Output (Out_Data, Out_Last, Result, Result_Last);
            exit when Out_Last = Before_First (Out_Data);
         end;
      end loop;

      Assert (Zlib.Stream_End (Filter), "raw Stream_End must be true after final block and drained output");
      Zlib.Close (Filter);
   end Inflate_Raw;

   procedure Assert_Decodes
     (Input       : Zlib.Byte_Array;
      Expected    : Zlib.Byte_Array;
      Chunk_Size  : Positive;
      Output_Size : Positive;
      Message     : String)
   is
      Result : Zlib.Byte_Array (1 .. Natural'Max (Expected'Length, 1));
      Last   : Natural;
   begin
      Inflate_Raw (Input, Chunk_Size, Output_Size, Result, Last);
      Assert (Last = Expected'Length, Message & ": decoded length mismatch");
      for I in Expected'Range loop
         Assert
           (Result (I - Expected'First + 1) = Expected (I),
            Message & ": decoded byte mismatch");
      end loop;
   end Assert_Decodes;

   procedure Expect_Raw_Zlib_Error
     (Input : Zlib.Byte_Array;
      Message : String)
   is
      Filter   : Zlib.Filter_Type;
      In_Data  : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Input'Length));
      Out_Data : Ada.Streams.Stream_Element_Array (1 .. 8);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Raised   : Boolean := False;
   begin
      for I in Input'Range loop
         In_Data (Ada.Streams.Stream_Element_Offset (I - Input'First + 1)) :=
           Ada.Streams.Stream_Element (Input (I));
      end loop;

      Zlib.Inflate_Init (Filter, Zlib.Raw_Deflate);
      begin
         Zlib.Translate (Filter, In_Data, In_Last, Out_Data, Out_Last, Zlib.Finish);
      exception
         when Zlib.Zlib_Error =>
            Raised := True;
      end;

      Assert (Raised, Message);
      Zlib.Close (Filter, Ignore_Error => True);
   end Expect_Raw_Zlib_Error;

   Hello : constant Zlib.Byte_Array :=
     [1 => 16#68#, 2 => 16#65#, 3 => 16#6C#, 4 => 16#6C#, 5 => 16#6F#];

   Raw_Stored_Hello : constant Zlib.Byte_Array :=
     [1 => 16#01#, 2 => 16#05#, 3 => 16#00#, 4 => 16#FA#, 5 => 16#FF#,
      6 => 16#68#, 7 => 16#65#, 8 => 16#6C#, 9 => 16#6C#, 10 => 16#6F#];

   Fixed_Text : constant Zlib.Byte_Array :=
     [1 => 16#68#, 2 => 16#65#, 3 => 16#6C#, 4 => 16#6C#, 5 => 16#6F#,
      6 => 16#20#, 7 => 16#68#, 8 => 16#65#, 9 => 16#6C#, 10 => 16#6C#,
      11 => 16#6F#, 12 => 16#20#, 13 => 16#68#, 14 => 16#65#, 15 => 16#6C#,
      16 => 16#6C#, 17 => 16#6F#];

   Raw_Fixed_Text : constant Zlib.Byte_Array :=
     [1 => 16#CB#, 2 => 16#48#, 3 => 16#CD#, 4 => 16#C9#, 5 => 16#C9#,
      6 => 16#57#, 7 => 16#C8#, 8 => 16#40#, 9 => 16#90#, 10 => 16#00#];

   Dynamic_Text : constant Zlib.Byte_Array :=
     [1 => 16#4C#, 2 => 16#6F#, 3 => 16#72#, 4 => 16#65#, 5 => 16#6D#,
      6 => 16#20#, 7 => 16#69#, 8 => 16#70#, 9 => 16#73#, 10 => 16#75#,
      11 => 16#6D#, 12 => 16#20#, 13 => 16#64#, 14 => 16#6F#, 15 => 16#6C#,
      16 => 16#6F#, 17 => 16#72#, 18 => 16#20#, 19 => 16#73#, 20 => 16#69#,
      21 => 16#74#, 22 => 16#20#, 23 => 16#61#, 24 => 16#6D#, 25 => 16#65#,
      26 => 16#74#, 27 => 16#2C#, 28 => 16#20#, 29 => 16#63#, 30 => 16#6F#,
      31 => 16#6E#, 32 => 16#73#, 33 => 16#65#, 34 => 16#63#, 35 => 16#74#,
      36 => 16#65#, 37 => 16#74#, 38 => 16#75#, 39 => 16#72#, 40 => 16#20#,
      41 => 16#61#, 42 => 16#64#, 43 => 16#69#, 44 => 16#70#, 45 => 16#69#,
      46 => 16#73#, 47 => 16#63#, 48 => 16#69#, 49 => 16#6E#, 50 => 16#67#,
      51 => 16#20#, 52 => 16#65#, 53 => 16#6C#, 54 => 16#69#, 55 => 16#74#,
      56 => 16#2E#, 57 => 16#20#,
      58 => 16#4C#, 59 => 16#6F#, 60 => 16#72#, 61 => 16#65#, 62 => 16#6D#,
      63 => 16#20#, 64 => 16#69#, 65 => 16#70#, 66 => 16#73#, 67 => 16#75#,
      68 => 16#6D#, 69 => 16#20#, 70 => 16#64#, 71 => 16#6F#, 72 => 16#6C#,
      73 => 16#6F#, 74 => 16#72#, 75 => 16#20#, 76 => 16#73#, 77 => 16#69#,
      78 => 16#74#, 79 => 16#20#, 80 => 16#61#, 81 => 16#6D#, 82 => 16#65#,
      83 => 16#74#, 84 => 16#2C#, 85 => 16#20#, 86 => 16#63#, 87 => 16#6F#,
      88 => 16#6E#, 89 => 16#73#, 90 => 16#65#, 91 => 16#63#, 92 => 16#74#,
      93 => 16#65#, 94 => 16#74#, 95 => 16#75#, 96 => 16#72#, 97 => 16#20#,
      98 => 16#61#, 99 => 16#64#, 100 => 16#69#, 101 => 16#70#, 102 => 16#69#,
      103 => 16#73#, 104 => 16#63#, 105 => 16#69#, 106 => 16#6E#, 107 => 16#67#,
      108 => 16#20#, 109 => 16#65#, 110 => 16#6C#, 111 => 16#69#, 112 => 16#74#,
      113 => 16#2E#, 114 => 16#20#];

   Raw_Dynamic_Text : constant Zlib.Byte_Array :=
     [1 => 16#9D#, 2 => 16#CB#, 3 => 16#D1#, 4 => 16#09#, 5 => 16#C0#,
      6 => 16#20#, 7 => 16#0C#, 8 => 16#05#, 9 => 16#C0#, 10 => 16#55#,
      11 => 16#DE#, 12 => 16#00#, 13 => 16#A5#, 14 => 16#93#, 15 => 16#B8#,
      16 => 16#84#, 17 => 16#C4#, 18 => 16#20#, 19 => 16#0F#, 20 => 16#8C#,
      21 => 16#91#, 22 => 16#24#, 23 => 16#EE#, 24 => 16#DF#, 25 => 16#1D#,
      26 => 16#7A#, 27 => 16#FF#, 28 => 16#D7#, 29 => 16#3C#, 30 => 16#D4#,
      31 => 16#C0#, 32 => 16#93#, 33 => 16#D7#, 34 => 16#30#, 35 => 16#7C#,
      36 => 16#79#, 37 => 16#20#, 38 => 16#59#, 39 => 16#E8#, 40 => 16#A6#,
      41 => 16#F5#, 42 => 16#40#, 43 => 16#7C#, 44 => 16#A7#, 45 => 16#4A#,
      46 => 16#69#, 47 => 16#DD#, 48 => 16#40#, 49 => 16#1F#, 50 => 16#3C#,
      51 => 16#4C#, 52 => 16#E1#, 53 => 16#9E#, 54 => 16#D0#, 55 => 16#C5#,
      56 => 16#7A#, 57 => 16#D1#, 58 => 16#FE#, 59 => 16#C6#, 60 => 16#0F#];

   procedure Test_Raw_Stored_Block
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Decodes (Raw_Stored_Hello, Hello, 64, 16, "raw stored block");
   end Test_Raw_Stored_Block;

   procedure Test_Raw_Fixed_Block
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Decodes (Raw_Fixed_Text, Fixed_Text, 64, 32, "raw fixed block");
   end Test_Raw_Fixed_Block;

   procedure Test_Raw_Dynamic_Block
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Decodes (Raw_Dynamic_Text, Dynamic_Text, 64, 128, "raw dynamic block");
   end Test_Raw_Dynamic_Block;

   procedure Test_Raw_Input_Split_Byte_By_Byte
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Decodes (Raw_Fixed_Text, Fixed_Text, 1, 32, "raw input split byte-by-byte");
   end Test_Raw_Input_Split_Byte_By_Byte;

   procedure Test_Raw_Output_Buffer_Size_One
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Decodes (Raw_Stored_Hello, Hello, 64, 1, "raw output buffer size 1");
   end Test_Raw_Output_Buffer_Size_One;

   procedure Test_Raw_Stream_End_After_Output_Drained
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Filter_Type;
      In_Data  : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Raw_Stored_Hello'Length));
      Out_Data : Ada.Streams.Stream_Element_Array (1 .. 1);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
   begin
      for I in Raw_Stored_Hello'Range loop
         In_Data (Ada.Streams.Stream_Element_Offset (I)) :=
           Ada.Streams.Stream_Element (Raw_Stored_Hello (I));
      end loop;

      Zlib.Inflate_Init (Filter, Zlib.Raw_Deflate);
      Zlib.Translate (Filter, In_Data, In_Last, Out_Data, Out_Last);
      Assert (Out_Last = Out_Data'Last, "one byte must be produced first");
      Assert (not Zlib.Stream_End (Filter), "raw Stream_End must be false while output remains pending");

      for Guard in 1 .. 20 loop
         declare
            Next_First : constant Ada.Streams.Stream_Element_Offset :=
              (if In_Last < In_Data'Last then In_Last + 1 else In_Data'Last + 1);
            Count      : constant Natural :=
              (if Next_First <= In_Data'Last
               then Natural (In_Data'Last - Next_First + 1)
               else 0);
         begin
            if Count = 0 then
               declare
                  No_Input : Ada.Streams.Stream_Element_Array (In_Data'Last + 1 .. In_Data'Last);
               begin
                  Zlib.Translate
                    (Filter,
                     No_Input,
                     In_Last,
                     Out_Data,
                     Out_Last,
                     Zlib.Finish);
               end;
            else
               declare
                  More_In : constant Ada.Streams.Stream_Element_Array := In_Data (Next_First .. In_Data'Last);
               begin
                  Zlib.Translate
                    (Filter,
                     More_In,
                     In_Last,
                     Out_Data,
                     Out_Last,
                     Zlib.No_Flush);
               end;
            end if;
            exit when Zlib.Stream_End (Filter);
         end;
      end loop;

      Assert (Zlib.Stream_End (Filter), "raw Stream_End must become true after output is drained");
      Zlib.Close (Filter);
   end Test_Raw_Stream_End_After_Output_Drained;

   procedure Test_Raw_Stream_End_False_Before_Final_Block
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Filter_Type;
      In_Data  : constant Ada.Streams.Stream_Element_Array (1 .. 4) :=
        [1 => 16#00#, 2 => 16#00#, 3 => 16#00#, 4 => 16#FF#];
      Out_Data : Ada.Streams.Stream_Element_Array (1 .. 8);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
   begin
      Zlib.Inflate_Init (Filter, Zlib.Raw_Deflate);
      Zlib.Translate (Filter, In_Data, In_Last, Out_Data, Out_Last);
      Assert (not Zlib.Stream_End (Filter), "raw Stream_End must be false before final block completion");
      Zlib.Close (Filter, Ignore_Error => True);
   end Test_Raw_Stream_End_False_Before_Final_Block;

   procedure Test_Raw_Truncated_Stored_Finish_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Bad : constant Zlib.Byte_Array := [1 => 16#01#, 2 => 16#05#, 3 => 16#00#];
   begin
      Expect_Raw_Zlib_Error (Bad, "raw Finish on truncated stored block must raise Zlib_Error");
   end Test_Raw_Truncated_Stored_Finish_Raises;

   procedure Test_Raw_Truncated_Fixed_Finish_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Bad : constant Zlib.Byte_Array := [1 => 16#CB#, 2 => 16#48#];
   begin
      Expect_Raw_Zlib_Error (Bad, "raw Finish on truncated fixed stream must raise Zlib_Error");
   end Test_Raw_Truncated_Fixed_Finish_Raises;

   procedure Test_Raw_Truncated_Dynamic_Finish_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Bad : constant Zlib.Byte_Array := [1 => 16#ED#, 2 => 16#CB#, 3 => 16#D1#];
   begin
      Expect_Raw_Zlib_Error (Bad, "raw Finish on truncated dynamic stream must raise Zlib_Error");
   end Test_Raw_Truncated_Dynamic_Finish_Raises;

   procedure Test_Raw_Invalid_Block_Type_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Bad : constant Zlib.Byte_Array := [1 => 16#07#];
   begin
      Expect_Raw_Zlib_Error (Bad, "raw invalid block type must raise Zlib_Error");
   end Test_Raw_Invalid_Block_Type_Raises;

   procedure Test_Raw_Invalid_Distance_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Bad : constant Zlib.Byte_Array := [1 => 16#03#, 2 => 16#02#];
   begin
      Expect_Raw_Zlib_Error (Bad, "raw invalid distance must raise Zlib_Error");
   end Test_Raw_Invalid_Distance_Raises;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_Raw_Stored_Block'Access,
         "raw stored block inflates successfully");
      Registration.Register_Routine
        (T, Test_Raw_Fixed_Block'Access,
         "raw fixed-Huffman block inflates successfully");
      Registration.Register_Routine
        (T, Test_Raw_Dynamic_Block'Access,
         "raw dynamic-Huffman block inflates successfully");
      Registration.Register_Routine
        (T, Test_Raw_Input_Split_Byte_By_Byte'Access,
         "raw input split byte-by-byte");
      Registration.Register_Routine
        (T, Test_Raw_Output_Buffer_Size_One'Access,
         "raw output buffer size 1");
      Registration.Register_Routine
        (T, Test_Raw_Stream_End_After_Output_Drained'Access,
         "raw final block sets Stream_End after output drained");
      Registration.Register_Routine
        (T, Test_Raw_Stream_End_False_Before_Final_Block'Access,
         "raw Stream_End false before final block completion");
      Registration.Register_Routine
        (T, Test_Raw_Truncated_Stored_Finish_Raises'Access,
         "raw Finish on truncated stored block raises Zlib_Error");
      Registration.Register_Routine
        (T, Test_Raw_Truncated_Fixed_Finish_Raises'Access,
         "raw Finish on truncated fixed stream raises Zlib_Error");
      Registration.Register_Routine
        (T, Test_Raw_Truncated_Dynamic_Finish_Raises'Access,
         "raw Finish on truncated dynamic stream raises Zlib_Error");
      Registration.Register_Routine
        (T, Test_Raw_Invalid_Block_Type_Raises'Access,
         "raw invalid block type raises Zlib_Error");
      Registration.Register_Routine
        (T, Test_Raw_Invalid_Distance_Raises'Access,
         "raw invalid distance raises Zlib_Error");
   end Register_Tests;

end Zlib_Streaming_Raw_Deflate_Tests;
