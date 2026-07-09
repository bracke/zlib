with Ada.Streams;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;

package body Zlib_Streaming_GZip_Tests is
   use type Ada.Streams.Stream_Element_Offset;
   use type Zlib.Byte;

   GZip_Hello : constant Zlib.Byte_Array :=
     [1 => 16#1F#, 2 => 16#8B#, 3 => 16#08#, 4 => 16#00#,
      5 => 16#00#, 6 => 16#00#, 7 => 16#00#, 8 => 16#00#,
      9 => 16#00#, 10 => 16#FF#, 11 => 16#CB#, 12 => 16#48#,
      13 => 16#CD#, 14 => 16#C9#, 15 => 16#C9#, 16 => 16#07#,
      17 => 16#00#, 18 => 16#86#, 19 => 16#A6#, 20 => 16#10#,
      21 => 16#36#, 22 => 16#05#, 23 => 16#00#, 24 => 16#00#,
      25 => 16#00#];

   GZip_FName : constant Zlib.Byte_Array :=
     [1 => 16#1F#, 2 => 16#8B#, 3 => 16#08#, 4 => 16#08#,
      5 => 16#00#, 6 => 16#00#, 7 => 16#00#, 8 => 16#00#,
      9 => 16#00#, 10 => 16#FF#, 11 => 16#68#, 12 => 16#65#,
      13 => 16#6C#, 14 => 16#6C#, 15 => 16#6F#, 16 => 16#2E#,
      17 => 16#74#, 18 => 16#78#, 19 => 16#74#, 20 => 16#00#,
      21 => 16#CB#, 22 => 16#48#, 23 => 16#CD#, 24 => 16#C9#,
      25 => 16#C9#, 26 => 16#07#, 27 => 16#00#, 28 => 16#86#,
      29 => 16#A6#, 30 => 16#10#, 31 => 16#36#, 32 => 16#05#,
      33 => 16#00#, 34 => 16#00#, 35 => 16#00#];

   GZip_Comment : constant Zlib.Byte_Array :=
     [1 => 16#1F#, 2 => 16#8B#, 3 => 16#08#, 4 => 16#10#,
      5 => 16#00#, 6 => 16#00#, 7 => 16#00#, 8 => 16#00#,
      9 => 16#00#, 10 => 16#FF#, 11 => 16#6E#, 12 => 16#6F#,
      13 => 16#74#, 14 => 16#65#, 15 => 16#00#, 16 => 16#CB#,
      17 => 16#48#, 18 => 16#CD#, 19 => 16#C9#, 20 => 16#C9#,
      21 => 16#07#, 22 => 16#00#, 23 => 16#86#, 24 => 16#A6#,
      25 => 16#10#, 26 => 16#36#, 27 => 16#05#, 28 => 16#00#,
      29 => 16#00#, 30 => 16#00#];

   GZip_Extra : constant Zlib.Byte_Array :=
     [1 => 16#1F#, 2 => 16#8B#, 3 => 16#08#, 4 => 16#04#,
      5 => 16#00#, 6 => 16#00#, 7 => 16#00#, 8 => 16#00#,
      9 => 16#00#, 10 => 16#FF#, 11 => 16#04#, 12 => 16#00#,
      13 => 16#61#, 14 => 16#62#, 15 => 16#63#, 16 => 16#64#,
      17 => 16#CB#, 18 => 16#48#, 19 => 16#CD#, 20 => 16#C9#,
      21 => 16#C9#, 22 => 16#07#, 23 => 16#00#, 24 => 16#86#,
      25 => 16#A6#, 26 => 16#10#, 27 => 16#36#, 28 => 16#05#,
      29 => 16#00#, 30 => 16#00#, 31 => 16#00#];

   GZip_FHCRC : constant Zlib.Byte_Array :=
     [1 => 16#1F#, 2 => 16#8B#, 3 => 16#08#, 4 => 16#02#,
      5 => 16#00#, 6 => 16#00#, 7 => 16#00#, 8 => 16#00#,
      9 => 16#00#, 10 => 16#FF#, 11 => 16#90#, 12 => 16#C9#,
      13 => 16#CB#, 14 => 16#48#, 15 => 16#CD#, 16 => 16#C9#,
      17 => 16#C9#, 18 => 16#07#, 19 => 16#00#, 20 => 16#86#,
      21 => 16#A6#, 22 => 16#10#, 23 => 16#36#, 24 => 16#05#,
      25 => 16#00#, 26 => 16#00#, 27 => 16#00#];

   GZip_FText : constant Zlib.Byte_Array :=
     [1 => 16#1F#, 2 => 16#8B#, 3 => 16#08#, 4 => 16#01#,
      5 => 16#00#, 6 => 16#00#, 7 => 16#00#, 8 => 16#00#,
      9 => 16#00#, 10 => 16#FF#, 11 => 16#CB#, 12 => 16#48#,
      13 => 16#CD#, 14 => 16#C9#, 15 => 16#C9#, 16 => 16#07#,
      17 => 16#00#, 18 => 16#86#, 19 => 16#A6#, 20 => 16#10#,
      21 => 16#36#, 22 => 16#05#, 23 => 16#00#, 24 => 16#00#,
      25 => 16#00#];

   GZip_All_Optional : constant Zlib.Byte_Array :=
     [1 => 16#1F#, 2 => 16#8B#, 3 => 16#08#, 4 => 16#1E#,
      5 => 16#00#, 6 => 16#00#, 7 => 16#00#, 8 => 16#00#,
      9 => 16#00#, 10 => 16#FF#, 11 => 16#02#, 12 => 16#00#,
      13 => 16#AB#, 14 => 16#CD#, 15 => 16#61#, 16 => 16#00#,
      17 => 16#62#, 18 => 16#00#, 19 => 16#88#, 20 => 16#AF#,
      21 => 16#CB#, 22 => 16#48#, 23 => 16#CD#, 24 => 16#C9#,
      25 => 16#C9#, 26 => 16#07#, 27 => 16#00#, 28 => 16#86#,
      29 => 16#A6#, 30 => 16#10#, 31 => 16#36#, 32 => 16#05#,
      33 => 16#00#, 34 => 16#00#, 35 => 16#00#];

   Bad_FHCRC : constant Zlib.Byte_Array :=
     [1 => 16#1F#, 2 => 16#8B#, 3 => 16#08#, 4 => 16#02#,
      5 => 16#00#, 6 => 16#00#, 7 => 16#00#, 8 => 16#00#,
      9 => 16#00#, 10 => 16#FF#, 11 => 16#91#, 12 => 16#C9#,
      13 => 16#CB#, 14 => 16#48#, 15 => 16#CD#, 16 => 16#C9#,
      17 => 16#C9#, 18 => 16#07#, 19 => 16#00#, 20 => 16#86#,
      21 => 16#A6#, 22 => 16#10#, 23 => 16#36#, 24 => 16#05#,
      25 => 16#00#, 26 => 16#00#, 27 => 16#00#];

   Bad_CRC : constant Zlib.Byte_Array :=
     [1 => 16#1F#, 2 => 16#8B#, 3 => 16#08#, 4 => 16#00#,
      5 => 16#00#, 6 => 16#00#, 7 => 16#00#, 8 => 16#00#,
      9 => 16#00#, 10 => 16#FF#, 11 => 16#CB#, 12 => 16#48#,
      13 => 16#CD#, 14 => 16#C9#, 15 => 16#C9#, 16 => 16#07#,
      17 => 16#00#, 18 => 16#87#, 19 => 16#A6#, 20 => 16#10#,
      21 => 16#36#, 22 => 16#05#, 23 => 16#00#, 24 => 16#00#,
      25 => 16#00#];

   Bad_ISIZE : constant Zlib.Byte_Array :=
     [1 => 16#1F#, 2 => 16#8B#, 3 => 16#08#, 4 => 16#00#,
      5 => 16#00#, 6 => 16#00#, 7 => 16#00#, 8 => 16#00#,
      9 => 16#00#, 10 => 16#FF#, 11 => 16#CB#, 12 => 16#48#,
      13 => 16#CD#, 14 => 16#C9#, 15 => 16#C9#, 16 => 16#07#,
      17 => 16#00#, 18 => 16#86#, 19 => 16#A6#, 20 => 16#10#,
      21 => 16#36#, 22 => 16#04#, 23 => 16#00#, 24 => 16#00#,
      25 => 16#00#];

   Expected_Hello : constant Zlib.Byte_Array :=
     [1 => Zlib.Byte (Character'Pos ('h')),
      2 => Zlib.Byte (Character'Pos ('e')),
      3 => Zlib.Byte (Character'Pos ('l')),
      4 => Zlib.Byte (Character'Pos ('l')),
      5 => Zlib.Byte (Character'Pos ('o'))];

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib streaming gzip inflate");
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

   procedure Inflate_GZip
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
      Zlib.Inflate_Init
        (Filter    => Filter,
         Header    => Zlib.GZip,
         GZip_Mode => Zlib.Single_Member);

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

      Assert (Zlib.Stream_End (Filter), "gzip stream end must be true after valid trailer");
      Zlib.Close (Filter);
   end Inflate_GZip;

   procedure Assert_Decodes
     (Input       : Zlib.Byte_Array;
      Chunk_Size  : Positive;
      Output_Size : Positive;
      Message     : String)
   is
      Result : Zlib.Byte_Array (1 .. 32);
      Last   : Natural;
   begin
      Inflate_GZip (Input, Chunk_Size, Output_Size, Result, Last);
      Assert (Last = Expected_Hello'Length, Message & ": decoded length mismatch");
      for I in Expected_Hello'Range loop
         Assert (Result (I) = Expected_Hello (I), Message & ": byte mismatch");
      end loop;
   end Assert_Decodes;

   procedure Expect_Zlib_Error
     (Input  : Zlib.Byte_Array;
      Finish : Boolean := True)
   is
      Filter   : Zlib.Filter_Type;
      In_Data  : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Input'Length));
      Out_Data : Ada.Streams.Stream_Element_Array (1 .. 16);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Raised   : Boolean := False;
   begin
      for I in Input'Range loop
         In_Data (Ada.Streams.Stream_Element_Offset (I - Input'First + 1)) :=
           Ada.Streams.Stream_Element (Input (I));
      end loop;

      Zlib.Inflate_Init (Filter, Header => Zlib.GZip);
      begin
         Zlib.Translate
           (Filter, In_Data, In_Last, Out_Data, Out_Last,
            (if Finish then Zlib.Finish else Zlib.No_Flush));
      exception
         when Zlib.Zlib_Error =>
            Raised := True;
      end;

      Assert (Raised, "malformed or truncated gzip stream must raise Zlib_Error");
      Zlib.Close (Filter, Ignore_Error => True);
   end Expect_Zlib_Error;

   procedure Test_GZip_Hello (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Decodes (GZip_Hello, 25, 16, "gzip hello");
   end Test_GZip_Hello;

   procedure Test_GZip_Byte_By_Byte (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Decodes (GZip_Hello, 1, 16, "gzip byte-by-byte input");
   end Test_GZip_Byte_By_Byte;

   procedure Test_GZip_Output_Size_One (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Decodes (GZip_Hello, 25, 1, "gzip output buffer size 1");
   end Test_GZip_Output_Size_One;

   procedure Test_GZip_Header_Split (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Decodes (GZip_Hello, 3, 16, "gzip split header");
   end Test_GZip_Header_Split;

   procedure Test_GZip_Trailer_Split (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Decodes (GZip_Hello, 17, 16, "gzip split trailer");
   end Test_GZip_Trailer_Split;

   procedure Test_GZip_FName (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Decodes (GZip_FName, 4, 16, "gzip FNAME");
   end Test_GZip_FName;

   procedure Test_GZip_Comment (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Decodes (GZip_Comment, 4, 16, "gzip FCOMMENT");
   end Test_GZip_Comment;

   procedure Test_GZip_Extra (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Decodes (GZip_Extra, 4, 16, "gzip FEXTRA");
   end Test_GZip_Extra;

   procedure Test_GZip_FHCRC (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Decodes (GZip_FHCRC, 4, 16, "gzip FHCRC");
   end Test_GZip_FHCRC;

   procedure Test_GZip_FText (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Decodes (GZip_FText, 4, 16, "gzip FTEXT");
   end Test_GZip_FText;

   procedure Test_GZip_All_Optional
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_Decodes (GZip_All_Optional, 3, 1, "gzip combined optional fields");
   end Test_GZip_All_Optional;

   procedure Test_Invalid_ID (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array := [1 => 16#00#, 2 => 16#8B#];
   begin
      Expect_Zlib_Error (Input);
   end Test_Invalid_ID;

   procedure Test_Unsupported_CM (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array :=
        [1 => 16#1F#, 2 => 16#8B#, 3 => 16#09#, 4 => 16#00#];
   begin
      Expect_Zlib_Error (Input);
   end Test_Unsupported_CM;

   procedure Test_Reserved_FLG (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array :=
        [1 => 16#1F#, 2 => 16#8B#, 3 => 16#08#, 4 => 16#E0#];
   begin
      Expect_Zlib_Error (Input);
   end Test_Reserved_FLG;

   procedure Test_Bad_CRC (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Expect_Zlib_Error (Bad_CRC);
   end Test_Bad_CRC;

   procedure Test_Bad_ISIZE (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Expect_Zlib_Error (Bad_ISIZE);
   end Test_Bad_ISIZE;

   procedure Test_Bad_FHCRC (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Expect_Zlib_Error (Bad_FHCRC);
   end Test_Bad_FHCRC;

   procedure Test_Truncated_FExtra (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array := GZip_Extra (1 .. 14);
   begin
      Expect_Zlib_Error (Input);
   end Test_Truncated_FExtra;

   procedure Test_Truncated_FName (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array := GZip_FName (1 .. 15);
   begin
      Expect_Zlib_Error (Input);
   end Test_Truncated_FName;

   procedure Test_Truncated_FComment (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array := GZip_Comment (1 .. 13);
   begin
      Expect_Zlib_Error (Input);
   end Test_Truncated_FComment;

   procedure Test_Truncated_FHCRC (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array := GZip_FHCRC (1 .. 11);
   begin
      Expect_Zlib_Error (Input);
   end Test_Truncated_FHCRC;

   procedure Test_Truncated_Header (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array :=
        [1 => 16#1F#, 2 => 16#8B#, 3 => 16#08#, 4 => 16#00#, 5 => 16#00#];
   begin
      Expect_Zlib_Error (Input);
   end Test_Truncated_Header;

   procedure Test_Truncated_Trailer (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array := GZip_Hello (1 .. 21);
   begin
      Expect_Zlib_Error (Input);
   end Test_Truncated_Trailer;

   procedure Test_Stream_End_Waits_For_Trailer
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Filter_Type;
      Compressed_Body     : Ada.Streams.Stream_Element_Array (1 .. 17);
      Trailer  : Ada.Streams.Stream_Element_Array (1 .. 8);
      Out_Data : Ada.Streams.Stream_Element_Array (1 .. 16);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
   begin
      for I in 1 .. 17 loop
         Compressed_Body (Ada.Streams.Stream_Element_Offset (I)) :=
           Ada.Streams.Stream_Element (GZip_Hello (I));
      end loop;
      for I in 1 .. 8 loop
         Trailer (Ada.Streams.Stream_Element_Offset (I)) :=
           Ada.Streams.Stream_Element (GZip_Hello (17 + I));
      end loop;

      Zlib.Inflate_Init (Filter, Header => Zlib.GZip);
      Zlib.Translate (Filter, Compressed_Body, In_Last, Out_Data, Out_Last);
      Assert (not Zlib.Stream_End (Filter),
              "gzip Stream_End must remain false before trailer validation");
      Zlib.Translate (Filter, Trailer, In_Last, Out_Data, Out_Last, Zlib.Finish);
      Assert (Zlib.Stream_End (Filter),
              "gzip Stream_End must become true after valid trailer");
      Zlib.Close (Filter);
   end Test_Stream_End_Waits_For_Trailer;

   procedure Test_Explicit_Single_Member_Leaves_Extra_Bytes
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Filter_Type;
      In_Data  : Ada.Streams.Stream_Element_Array (1 .. 26);
      Out_Data : Ada.Streams.Stream_Element_Array (1 .. 16);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
   begin
      for I in GZip_Hello'Range loop
         In_Data (Ada.Streams.Stream_Element_Offset (I)) :=
           Ada.Streams.Stream_Element (GZip_Hello (I));
      end loop;
      In_Data (26) := 16#00#;

      Zlib.Inflate_Init
        (Filter    => Filter,
         Header    => Zlib.GZip,
         GZip_Mode => Zlib.Single_Member);

      Zlib.Translate (Filter, In_Data, In_Last, Out_Data, Out_Last);

      Assert (Zlib.Stream_End (Filter),
              "explicit single-member gzip must complete before extra byte");
      Assert (In_Last = 25,
              "explicit single-member gzip must leave post-member input unconsumed");
      Zlib.Close (Filter);
   end Test_Explicit_Single_Member_Leaves_Extra_Bytes;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine (T, Test_GZip_Hello'Access, "gzip hello stream");
      Registration.Register_Routine (T, Test_GZip_Byte_By_Byte'Access,
                                     "gzip stream split byte-by-byte");
      Registration.Register_Routine (T, Test_GZip_Output_Size_One'Access,
                                     "gzip output buffer size 1");
      Registration.Register_Routine (T, Test_GZip_Header_Split'Access,
                                     "gzip header split across calls");
      Registration.Register_Routine (T, Test_GZip_Trailer_Split'Access,
                                     "gzip trailer split across calls");
      Registration.Register_Routine (T, Test_GZip_FName'Access, "gzip with FNAME");
      Registration.Register_Routine (T, Test_GZip_Comment'Access, "gzip with FCOMMENT");
      Registration.Register_Routine (T, Test_GZip_Extra'Access, "gzip with FEXTRA");
      Registration.Register_Routine (T, Test_GZip_FHCRC'Access, "gzip with FHCRC");
      Registration.Register_Routine (T, Test_GZip_FText'Access, "gzip with FTEXT");
      Registration.Register_Routine (T, Test_GZip_All_Optional'Access,
                                     "gzip with combined optional fields");
      Registration.Register_Routine (T, Test_Invalid_ID'Access, "invalid ID raises Zlib_Error");
      Registration.Register_Routine (T, Test_Unsupported_CM'Access, "unsupported CM raises Zlib_Error");
      Registration.Register_Routine (T, Test_Reserved_FLG'Access, "reserved FLG raises Zlib_Error");
      Registration.Register_Routine (T, Test_Bad_CRC'Access, "bad CRC32 trailer raises Zlib_Error");
      Registration.Register_Routine (T, Test_Bad_ISIZE'Access, "bad ISIZE trailer raises Zlib_Error");
      Registration.Register_Routine (T, Test_Bad_FHCRC'Access, "bad FHCRC raises Zlib_Error");
      Registration.Register_Routine (T, Test_Truncated_FExtra'Access, "Finish on truncated FEXTRA raises");
      Registration.Register_Routine (T, Test_Truncated_FName'Access, "Finish on truncated FNAME raises");
      Registration.Register_Routine (T, Test_Truncated_FComment'Access, "Finish on truncated FCOMMENT raises");
      Registration.Register_Routine (T, Test_Truncated_FHCRC'Access, "Finish on truncated FHCRC raises");
      Registration.Register_Routine (T, Test_Truncated_Header'Access, "Finish on truncated header raises");
      Registration.Register_Routine (T, Test_Truncated_Trailer'Access, "Finish on truncated trailer raises");
      Registration.Register_Routine (T, Test_Stream_End_Waits_For_Trailer'Access,
                                     "Stream_End waits for valid gzip trailer");
      Registration.Register_Routine (T, Test_Explicit_Single_Member_Leaves_Extra_Bytes'Access,
                                     "explicit single-member gzip leaves extra bytes unconsumed");
   end Register_Tests;
end Zlib_Streaming_GZip_Tests;
