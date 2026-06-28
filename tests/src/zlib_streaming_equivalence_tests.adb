with Ada.Streams;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;

package body Zlib_Streaming_Equivalence_Tests is
   use type Ada.Streams.Stream_Element_Offset;
   use type Zlib.Byte;
   use type Zlib.Status_Code;

   Zlib_Stored_Text : constant Zlib.Byte_Array :=
     [1 => 16#78#, 2 => 16#01#, 3 => 16#01#, 4 => 16#0D#,
      5 => 16#00#, 6 => 16#F2#, 7 => 16#FF#, 8 => 16#68#,
      9 => 16#65#, 10 => 16#6C#, 11 => 16#6C#, 12 => 16#6F#,
      13 => 16#20#, 14 => 16#73#, 15 => 16#74#, 16 => 16#6F#,
      17 => 16#72#, 18 => 16#65#, 19 => 16#64#, 20 => 16#0A#,
      21 => 16#23#, 22 => 16#A5#, 23 => 16#04#, 24 => 16#D0#];

   Zlib_Fixed_Text : constant Zlib.Byte_Array :=
     [1 => 16#78#, 2 => 16#01#, 3 => 16#4B#, 4 => 16#4C#,
      5 => 16#C4#, 6 => 16#0F#, 7 => 16#00#, 8 => 16#C8#,
      9 => 16#30#, 10 => 16#0C#, 11 => 16#21#];

   Zlib_Dynamic_Git : constant Zlib.Byte_Array :=
     [1 => 16#78#, 2 => 16#9C#, 3 => 16#4B#, 4 => 16#CA#,
      5 => 16#C9#, 6 => 16#4F#, 7 => 16#52#, 8 => 16#30#,
      9 => 16#34#, 10 => 16#62#, 11 => 16#C8#, 12 => 16#48#,
      13 => 16#CD#, 14 => 16#C9#, 15 => 16#C9#, 16 => 16#57#,
      17 => 16#28#, 18 => 16#CF#, 19 => 16#2F#, 20 => 16#CA#,
      21 => 16#49#, 22 => 16#E1#, 23 => 16#02#, 24 => 16#00#,
      25 => 16#44#, 26 => 16#11#, 27 => 16#06#, 28 => 16#89#];

   Zlib_Binary_Payload : constant Zlib.Byte_Array :=
     [1 => 16#78#, 2 => 16#9C#, 3 => 16#63#, 4 => 16#60#,
      5 => 16#64#, 6 => 16#E2#, 7 => 16#E5#, 8 => 16#6A#,
      9 => 16#68#, 10 => 16#FC#, 11 => 16#F7#, 12 => 16#9F#,
      13 => 16#97#, 14 => 16#CB#, 15 => 16#91#, 16 => 16#42#,
      17 => 16#00#, 18 => 16#00#, 19 => 16#E9#, 20 => 16#B1#,
      21 => 16#13#, 22 => 16#70#];

   Expected_Stored_Text : constant Zlib.Byte_Array :=
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

   Expected_Fixed_Text : constant Zlib.Byte_Array (1 .. 32) := [others => 16#61#];

   Expected_Dynamic_Git : constant Zlib.Byte_Array :=
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

   Expected_Binary_Payload : constant Zlib.Byte_Array :=
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
      return AUnit.Format ("Zlib one-shot/streaming equivalence");
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

   procedure Inflate_Streaming
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
      Zlib.Inflate_Init (Filter, Header => Zlib.Zlib_Header);

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

      Assert (Zlib.Stream_End (Filter), "zlib stream must end after trailer validation");
      Zlib.Close (Filter);
   end Inflate_Streaming;

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

   procedure Assert_Equivalent
     (Input       : Zlib.Byte_Array;
      Expected    : Zlib.Byte_Array;
      Chunk_Size  : Positive;
      Output_Size : Positive;
      Message     : String)
   is
      Status   : Zlib.Status_Code;
      One_Shot : constant Zlib.Byte_Array := Zlib.Inflate (Input, Status);
      Streamed : Zlib.Byte_Array (1 .. Expected'Length + 16);
      Last     : Natural;
   begin
      Assert (Status = Zlib.Ok, Message & ": one-shot status must be Ok");
      Assert_Bytes_Equal (One_Shot, Expected, Message & ": one-shot output");

      Inflate_Streaming (Input, Chunk_Size, Output_Size, Streamed, Last);
      Assert (Last = Expected'Length, Message & ": streaming output length");
      for I in Expected'Range loop
         Assert
           (Streamed (Streamed'First + (I - Expected'First)) = Expected (I),
            Message & ": streaming output byte");
      end loop;
      Assert_Bytes_Equal (One_Shot, Streamed (1 .. Last), Message & ": equivalence");
   end Assert_Equivalent;

   procedure Test_Frozen_Fixtures_Equivalent
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_Equivalent (Zlib_Stored_Text, Expected_Stored_Text, 1, 1, "stored fixture");
      Assert_Equivalent (Zlib_Fixed_Text, Expected_Fixed_Text, 2, 1, "fixed-Huffman fixture");
      Assert_Equivalent (Zlib_Dynamic_Git, Expected_Dynamic_Git, 3, 2, "dynamic Git-like fixture");
      Assert_Equivalent (Zlib_Binary_Payload, Expected_Binary_Payload, 1, 1, "binary fixture");
   end Test_Frozen_Fixtures_Equivalent;

   procedure Test_Deflate_Stored_Equivalence
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Plain  : Zlib.Byte_Array (1 .. 512);
      Status : Zlib.Status_Code;
   begin
      for I in Plain'Range loop
         Plain (I) := Zlib.Byte ((I * 37) mod 256);
      end loop;

      declare
         Encoded : constant Zlib.Byte_Array := Zlib.Deflate_Stored (Plain, Status);
      begin
         Assert (Status = Zlib.Ok, "Deflate_Stored release fixture creation");
         Assert_Equivalent (Encoded, Plain, 1, 1, "Deflate_Stored generated fixture");
      end;
   end Test_Deflate_Stored_Equivalence;

   procedure Test_Same_Failure_Outcome_For_Bad_Checksum
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array :=
        [1 => 16#78#, 2 => 16#01#, 3 => 16#01#, 4 => 16#00#,
         5 => 16#00#, 6 => 16#FF#, 7 => 16#FF#, 8 => 16#00#,
         9 => 16#00#, 10 => 16#00#, 11 => 16#02#];
      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array := Zlib.Inflate (Input, Status);
      pragma Unreferenced (Output);
      Filter : Zlib.Filter_Type;
      In_Data : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Input'Length));
      Out_Data : Ada.Streams.Stream_Element_Array (1 .. 1);
      In_Last : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Raised : Boolean := False;
   begin
      Assert (Status = Zlib.Invalid_Checksum, "one-shot bad checksum status");
      for I in Input'Range loop
         In_Data (Ada.Streams.Stream_Element_Offset (I)) := Ada.Streams.Stream_Element (Input (I));
      end loop;
      Zlib.Inflate_Init (Filter, Header => Zlib.Zlib_Header);
      begin
         Zlib.Translate (Filter, In_Data, In_Last, Out_Data, Out_Last, Zlib.Finish);
      exception
         when Zlib.Zlib_Error =>
            Raised := True;
      end;
      Zlib.Close (Filter, Ignore_Error => True);
      Assert (Raised, "streaming bad checksum must raise Zlib_Error");
   end Test_Same_Failure_Outcome_For_Bad_Checksum;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine (T, Test_Frozen_Fixtures_Equivalent'Access,
                                     "frozen zlib fixtures match one-shot and streaming");
      Registration.Register_Routine (T, Test_Deflate_Stored_Equivalence'Access,
                                     "Deflate_Stored output matches one-shot and streaming");
      Registration.Register_Routine (T, Test_Same_Failure_Outcome_For_Bad_Checksum'Access,
                                     "checksum failure outcome follows release contract across APIs");
   end Register_Tests;
end Zlib_Streaming_Equivalence_Tests;
