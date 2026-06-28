with Ada.Streams;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;

package body Zlib_Streaming_Inflate_Fixed_Tests is
   use type Ada.Streams.Stream_Element_Offset;
   use type Zlib.Byte;

   Fixed_Hello : constant Zlib.Byte_Array :=
     [1 => 16#78#, 2 => 16#01#, 3 => 16#CB#, 4 => 16#48#,
      5 => 16#CD#, 6 => 16#C9#, 7 => 16#C9#, 8 => 16#07#,
      9 => 16#00#, 10 => 16#06#, 11 => 16#2C#, 12 => 16#02#,
      13 => 16#15#];

   Fixed_Overlap : constant Zlib.Byte_Array :=
     [1 => 16#78#, 2 => 16#01#, 3 => 16#4B#, 4 => 16#4C#,
      5 => 16#4A#, 6 => 16#C6#, 7 => 16#44#, 8 => 16#00#,
      9 => 16#58#, 10 => 16#75#, 11 => 16#08#, 12 => 16#0B#];

   Fixed_Long_Copy : constant Zlib.Byte_Array :=
     [1 => 16#78#, 2 => 16#01#, 3 => 16#4B#, 4 => 16#4C#,
      5 => 16#1C#, 6 => 16#05#, 7 => 16#C4#, 8 => 16#02#,
      9 => 16#00#, 10 => 16#D8#, 11 => 16#A8#, 12 => 16#71#,
      13 => 16#AD#];

   Fixed_Then_Stored : constant Zlib.Byte_Array :=
     [1 => 16#78#, 2 => 16#01#, 3 => 16#CA#, 4 => 16#C8#,
      5 => 16#04#, 6 => 16#04#, 7 => 16#01#, 8 => 16#00#,
      9 => 16#FE#, 10 => 16#FF#, 11 => 16#21#, 12 => 16#02#,
      13 => 16#2E#, 14 => 16#00#, 15 => 16#F3#];

   Stored_Then_Fixed : constant Zlib.Byte_Array :=
     [1 => 16#78#, 2 => 16#01#, 3 => 16#00#, 4 => 16#01#,
      5 => 16#00#, 6 => 16#FE#, 7 => 16#FF#, 8 => 16#3F#,
      9 => 16#CB#, 10 => 16#CF#, 11 => 16#06#, 12 => 16#00#,
      13 => 16#02#, 14 => 16#09#, 15 => 16#01#, 16 => 16#1A#];

   Fixed_No_Footer : constant Zlib.Byte_Array :=
     [1 => 16#78#, 2 => 16#01#, 3 => 16#CB#, 4 => 16#48#,
      5 => 16#CD#, 6 => 16#C9#, 7 => 16#C9#, 8 => 16#07#,
      9 => 16#00#];

   Invalid_Distance : constant Zlib.Byte_Array :=
     [1 => 16#78#, 2 => 16#01#, 3 => 16#03#, 4 => 16#02#,
      5 => 16#00#, 6 => 16#00#, 7 => 16#00#, 8 => 16#00#,
      9 => 16#01#];

   Dynamic_Header_Only : constant Zlib.Byte_Array :=
     [1 => 16#78#, 2 => 16#01#, 3 => 16#05#];

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib streaming fixed-Huffman inflate");
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

   procedure Inflate_Stream
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

      Assert (Zlib.Stream_End (Filter), "stream end must be true after valid fixed stream");
      Zlib.Close (Filter);
   end Inflate_Stream;

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
      Inflate_Stream (Input, Chunk_Size, Output_Size, Result, Last);
      Assert (Last = Expected'Length, Message & ": decoded length mismatch");

      for I in Expected'Range loop
         Assert
           (Result (I - Expected'First + 1) = Expected (I),
            Message & ": decoded byte mismatch");
      end loop;
   end Assert_Decodes;

   procedure Expect_Zlib_Error
     (Input  : Zlib.Byte_Array;
      Finish : Boolean)
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

      Zlib.Inflate_Init (Filter);
      begin
         Zlib.Translate
           (Filter,
            In_Data,
            In_Last,
            Out_Data,
            Out_Last,
            (if Finish then Zlib.Finish else Zlib.No_Flush));
      exception
         when Zlib.Zlib_Error =>
            Raised := True;
      end;

      Assert (Raised, "fixed-Huffman invalid/truncated stream must raise Zlib_Error");
      Zlib.Close (Filter, Ignore_Error => True);
   end Expect_Zlib_Error;

   procedure Test_Fixed_Hello
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Expected : constant Zlib.Byte_Array := [1 => 104, 2 => 101, 3 => 108, 4 => 108, 5 => 111];
   begin
      Assert_Decodes (Fixed_Hello, Expected, 64, 16, "fixed hello");
   end Test_Fixed_Hello;

   procedure Test_Fixed_Input_Byte_By_Byte
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Expected : constant Zlib.Byte_Array := [1 => 104, 2 => 101, 3 => 108, 4 => 108, 5 => 111];
   begin
      Assert_Decodes (Fixed_Hello, Expected, 1, 16, "fixed input byte-by-byte");
   end Test_Fixed_Input_Byte_By_Byte;

   procedure Test_Fixed_Bit_Sensitive_Boundaries
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Expected : constant Zlib.Byte_Array := [1 => 104, 2 => 101, 3 => 108, 4 => 108, 5 => 111];
   begin
      for Chunk in 1 .. Fixed_Hello'Length loop
         Assert_Decodes
           (Fixed_Hello,
            Expected,
            Chunk,
            2,
            "fixed bit-sensitive boundary chunk" & Natural'Image (Chunk));
      end loop;
   end Test_Fixed_Bit_Sensitive_Boundaries;

   procedure Test_Fixed_Output_Buffer_Size_One
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Expected : constant Zlib.Byte_Array := [1 => 104, 2 => 101, 3 => 108, 4 => 108, 5 => 111];
   begin
      Assert_Decodes (Fixed_Hello, Expected, 64, 1, "fixed output buffer size one");
   end Test_Fixed_Output_Buffer_Size_One;

   procedure Test_Fixed_Overlapping_Copy
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Expected : constant Zlib.Byte_Array :=
        [1 => 97, 2 => 98, 3 => 99, 4 => 97, 5 => 98, 6 => 99,
         7 => 97, 8 => 98, 9 => 99, 10 => 97, 11 => 98, 12 => 99,
         13 => 97, 14 => 98, 15 => 99, 16 => 97, 17 => 98, 18 => 99,
         19 => 97, 20 => 98, 21 => 99];
   begin
      Assert_Decodes (Fixed_Overlap, Expected, 64, 64, "fixed overlapping LZ77 copy");
   end Test_Fixed_Overlapping_Copy;

   procedure Test_Copy_Resumes_After_Output_Fills
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Expected : constant Zlib.Byte_Array :=
        [1 => 97, 2 => 98, 3 => 99, 4 => 97, 5 => 98, 6 => 99,
         7 => 97, 8 => 98, 9 => 99, 10 => 97, 11 => 98, 12 => 99,
         13 => 97, 14 => 98, 15 => 99, 16 => 97, 17 => 98, 18 => 99,
         19 => 97, 20 => 98, 21 => 99];
   begin
      Assert_Decodes (Fixed_Overlap, Expected, 64, 1, "LZ77 copy resumed after output fills");
   end Test_Copy_Resumes_After_Output_Fills;

   procedure Test_Flush_Continues_Copy_After_Output_Fills
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Filter_Type;
      Out_Data : Ada.Streams.Stream_Element_Array (1 .. 1);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Produced : Natural := 0;
      Pos      : Natural := Fixed_Long_Copy'First;
   begin
      Zlib.Inflate_Init (Filter);

      for Guard in 1 .. 512 loop
         declare
            Count   : constant Natural :=
              (if Pos <= Fixed_Long_Copy'Last
               then Natural'Min (2, Fixed_Long_Copy'Last - Pos + 1)
               else 0);
            In_Data : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Count));
         begin
            if Count > 0 then
               for I in 0 .. Count - 1 loop
                  In_Data (Ada.Streams.Stream_Element_Offset (I + 1)) :=
                    Ada.Streams.Stream_Element (Fixed_Long_Copy (Pos + I));
               end loop;

               Zlib.Translate (Filter, In_Data, In_Last, Out_Data, Out_Last);
               if In_Last /= Before_First (In_Data) then
                  Pos := Pos + Natural (In_Last - In_Data'First + 1);
               end if;
            else
               Zlib.Flush (Filter, Out_Data, Out_Last);
            end if;

            if Out_Last /= Before_First (Out_Data) then
               Produced := Produced + 1;
            end if;

            exit when Produced > 64;
         end;
      end loop;

      Assert
        (Produced > 64,
         "Flush must resume LZ77 copy generation after pending output drains");
      Zlib.Close (Filter, Ignore_Error => True);
   end Test_Flush_Continues_Copy_After_Output_Fills;

   procedure Test_Fixed_Followed_By_Stored
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Expected : constant Zlib.Byte_Array := [1 => 104, 2 => 105, 3 => 33];
   begin
      Assert_Decodes (Fixed_Then_Stored, Expected, 1, 1, "fixed block followed by stored block");
   end Test_Fixed_Followed_By_Stored;

   procedure Test_Stored_Followed_By_Fixed
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Expected : constant Zlib.Byte_Array := [1 => 63, 2 => 111, 3 => 107];
   begin
      Assert_Decodes (Stored_Then_Fixed, Expected, 1, 1, "stored block followed by fixed block");
   end Test_Stored_Followed_By_Fixed;

   procedure Test_Stream_End_False_Before_Adler
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Filter_Type;
      In_Data  : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Fixed_No_Footer'Length));
      Out_Data : Ada.Streams.Stream_Element_Array (1 .. 16);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
   begin
      for I in Fixed_No_Footer'Range loop
         In_Data (Ada.Streams.Stream_Element_Offset (I - Fixed_No_Footer'First + 1)) :=
           Ada.Streams.Stream_Element (Fixed_No_Footer (I));
      end loop;

      Zlib.Inflate_Init (Filter);
      Zlib.Translate (Filter, In_Data, In_Last, Out_Data, Out_Last);
      Assert (not Zlib.Stream_End (Filter), "Stream_End must remain false before Adler footer");
      Zlib.Close (Filter, Ignore_Error => True);
   end Test_Stream_End_False_Before_Adler;

   procedure Test_Stream_End_True_After_Adler
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Expected : constant Zlib.Byte_Array := [1 => 104, 2 => 101, 3 => 108, 4 => 108, 5 => 111];
      Result   : Zlib.Byte_Array (1 .. Expected'Length);
      Last     : Natural;
   begin
      Inflate_Stream (Fixed_Hello, 1, 1, Result, Last);
      Assert (Last = Expected'Length, "valid Adler footer must complete stream");
   end Test_Stream_End_True_After_Adler;

   procedure Test_Finish_On_Truncated_Fixed_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Expect_Zlib_Error (Fixed_No_Footer, Finish => True);
   end Test_Finish_On_Truncated_Fixed_Raises;

   procedure Test_Invalid_Fixed_Distance_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Expect_Zlib_Error (Invalid_Distance, Finish => False);
   end Test_Invalid_Fixed_Distance_Raises;

   procedure Test_Dynamic_Header_Truncated_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Expect_Zlib_Error (Dynamic_Header_Only, Finish => True);
   end Test_Dynamic_Header_Truncated_Raises;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_Fixed_Hello'Access,
         "streaming fixed-Huffman hello");
      Registration.Register_Routine
        (T, Test_Fixed_Input_Byte_By_Byte'Access,
         "fixed-Huffman input split byte-by-byte");
      Registration.Register_Routine
        (T, Test_Fixed_Bit_Sensitive_Boundaries'Access,
         "fixed-Huffman input split at bit-sensitive boundaries");
      Registration.Register_Routine
        (T, Test_Fixed_Output_Buffer_Size_One'Access,
         "fixed-Huffman output buffer size 1");
      Registration.Register_Routine
        (T, Test_Fixed_Overlapping_Copy'Access,
         "fixed-Huffman overlapping LZ77 copy");
      Registration.Register_Routine
        (T, Test_Copy_Resumes_After_Output_Fills'Access,
         "LZ77 copy resumed after output buffer fills");
      Registration.Register_Routine
        (T, Test_Flush_Continues_Copy_After_Output_Fills'Access,
         "Flush resumes LZ77 copy after output buffer fills");
      Registration.Register_Routine
        (T, Test_Fixed_Followed_By_Stored'Access,
         "fixed-Huffman block followed by stored block");
      Registration.Register_Routine
        (T, Test_Stored_Followed_By_Fixed'Access,
         "stored block followed by fixed-Huffman block");
      Registration.Register_Routine
        (T, Test_Stream_End_False_Before_Adler'Access,
         "Fixed inflate Stream_End false before Adler footer");
      Registration.Register_Routine
        (T, Test_Stream_End_True_After_Adler'Access,
         "Fixed inflate Stream_End true after valid Adler footer");
      Registration.Register_Routine
        (T, Test_Finish_On_Truncated_Fixed_Raises'Access,
         "Finish on truncated fixed-Huffman stream raises Zlib_Error");
      Registration.Register_Routine
        (T, Test_Invalid_Fixed_Distance_Raises'Access,
         "invalid fixed-Huffman distance raises Zlib_Error");
      Registration.Register_Routine
        (T, Test_Dynamic_Header_Truncated_Raises'Access,
         "truncated dynamic-Huffman header raises Zlib_Error");
   end Register_Tests;

end Zlib_Streaming_Inflate_Fixed_Tests;
