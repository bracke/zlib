with Ada.Streams;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;

package body Zlib_Streaming_Inflate_Stored_Tests is
   use type Ada.Streams.Stream_Element_Offset;
   use type Zlib.Byte;
   use type Zlib.Status_Code;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib streaming stored inflate");
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
      Result_Last : out Natural;
      Header      : Zlib.Header_Type := Zlib.Default)
   is
      Filter : Zlib.Filter_Type;
      Pos    : Natural := Input'First;
   begin
      Result_Last := Result'First - 1;
      Zlib.Inflate_Init (Filter, Header);

      while Pos <= Input'Last loop
         declare
            Count : constant Natural := Natural'Min (Chunk_Size, Input'Last - Pos + 1);
            In_Data : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Count));
            Out_Data : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Output_Size));
            In_Last  : Ada.Streams.Stream_Element_Offset;
            Out_Last : Ada.Streams.Stream_Element_Offset;
         begin
            for I in 0 .. Count - 1 loop
               In_Data (Ada.Streams.Stream_Element_Offset (I + 1)) := Ada.Streams.Stream_Element (Input (Pos + I));
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
               Out_Data : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Output_Size));
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
            Out_Data : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Output_Size));
            In_Last  : Ada.Streams.Stream_Element_Offset;
            Out_Last : Ada.Streams.Stream_Element_Offset;
         begin
            Zlib.Translate (Filter, Empty_In, In_Last, Out_Data, Out_Last, Zlib.Finish);
            Copy_Output (Out_Data, Out_Last, Result, Result_Last);
            exit when Out_Last = Before_First (Out_Data);
         end;
      end loop;

      Assert (Zlib.Stream_End (Filter), "stream end must be true after valid stored stream");
      Zlib.Close (Filter);
   end Inflate_Stream;

   procedure Assert_Roundtrip
     (Payload     : Zlib.Byte_Array;
      Chunk_Size  : Positive;
      Output_Size : Positive;
      Message     : String)
   is
      Status     : Zlib.Status_Code;
      Compressed : constant Zlib.Byte_Array := Zlib.Deflate_Stored (Payload, Status);
      Result     : Zlib.Byte_Array (1 .. Natural'Max (Payload'Length, 1));
      Last       : Natural;
   begin
      Assert (Status = Zlib.Ok, Message & ": Deflate_Stored must succeed");
      Inflate_Stream (Compressed, Chunk_Size, Output_Size, Result, Last);
      Assert (Last = Payload'Length, Message & ": decoded length mismatch");

      for I in Payload'Range loop
         Assert (Result (I - Payload'First + 1) = Payload (I), Message & ": decoded byte mismatch");
      end loop;
   end Assert_Roundtrip;

   procedure Expect_Zlib_Error_On_Input
     (Input  : Zlib.Byte_Array;
      Finish : Boolean)
   is
      Filter   : Zlib.Filter_Type;
      In_Data  : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Input'Length));
      Out_Data : Ada.Streams.Stream_Element_Array (1 .. 1);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Raised   : Boolean := False;
   begin
      for I in Input'Range loop
         In_Data (Ada.Streams.Stream_Element_Offset (I - Input'First + 1)) := Ada.Streams.Stream_Element (Input (I));
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

         if not Raised and then Finish then
            for Guard in 1 .. 32 loop
               declare
                  Empty_In : constant Ada.Streams.Stream_Element_Array (1 .. 0) := [];
               begin
                  Zlib.Translate
                    (Filter, Empty_In, In_Last, Out_Data, Out_Last, Zlib.Finish);
               end;
               exit when Zlib.Stream_End (Filter);
            end loop;
         end if;
      exception
         when Zlib.Zlib_Error =>
            Raised := True;
      end;

      Assert (Raised, "invalid or truncated stream must raise Zlib_Error");
      Zlib.Close (Filter, Ignore_Error => True);
   end Expect_Zlib_Error_On_Input;

   procedure Test_Empty_Zlib_Stream
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Payload : constant Zlib.Byte_Array (1 .. 0) := [];
   begin
      Assert_Roundtrip (Payload, 64, 8, "empty stored stream");
   end Test_Empty_Zlib_Stream;

   procedure Test_Hello_Zlib_Stream
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Payload : constant Zlib.Byte_Array :=
        [1 => Zlib.Byte (Character'Pos ('h')),
         2 => Zlib.Byte (Character'Pos ('e')),
         3 => Zlib.Byte (Character'Pos ('l')),
         4 => Zlib.Byte (Character'Pos ('l')),
         5 => Zlib.Byte (Character'Pos ('o'))];
   begin
      Assert_Roundtrip (Payload, 64, 16, "hello stored stream");
   end Test_Hello_Zlib_Stream;

   procedure Test_Header_And_Lengths_Split
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Payload : constant Zlib.Byte_Array := [1 => 1, 2 => 2, 3 => 3, 4 => 4];
   begin
      Assert_Roundtrip (Payload, 1, 8, "byte-split header and LEN/NLEN");
   end Test_Header_And_Lengths_Split;

   procedure Test_Payload_And_Output_Byte_By_Byte
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Payload : constant Zlib.Byte_Array :=
        [1 => 10, 2 => 20, 3 => 30, 4 => 40, 5 => 50, 6 => 60, 7 => 70];
   begin
      Assert_Roundtrip (Payload, 1, 1, "input and output byte-by-byte");
   end Test_Payload_And_Output_Byte_By_Byte;

   procedure Test_Stream_End_False_Before_Footer
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Payload    : constant Zlib.Byte_Array (1 .. 0) := [];
      Status     : Zlib.Status_Code;
      Compressed : constant Zlib.Byte_Array := Zlib.Deflate_Stored (Payload, Status);
      Filter     : Zlib.Filter_Type;
      In_Data    : Ada.Streams.Stream_Element_Array (1 .. 7);
      Out_Data   : Ada.Streams.Stream_Element_Array (1 .. 1);
      In_Last    : Ada.Streams.Stream_Element_Offset;
      Out_Last   : Ada.Streams.Stream_Element_Offset;
   begin
      Assert (Status = Zlib.Ok, "Deflate_Stored empty must succeed");
      for I in 1 .. 7 loop
         In_Data (Ada.Streams.Stream_Element_Offset (I)) := Ada.Streams.Stream_Element (Compressed (I));
      end loop;

      Zlib.Inflate_Init (Filter);
      Zlib.Translate (Filter, In_Data, In_Last, Out_Data, Out_Last);
      Assert (not Zlib.Stream_End (Filter), "Stream_End must remain false before Adler footer");
      Zlib.Close (Filter, Ignore_Error => True);
   end Test_Stream_End_False_Before_Footer;

   procedure Test_Invalid_Header_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Bad : constant Zlib.Byte_Array := [1 => 16#78#, 2 => 16#02#];
   begin
      Expect_Zlib_Error_On_Input (Bad, Finish => False);
   end Test_Invalid_Header_Raises;

   procedure Test_Invalid_Len_Nlen_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Bad : constant Zlib.Byte_Array :=
        [1 => 16#78#, 2 => 16#01#, 3 => 16#01#, 4 => 16#01#,
         5 => 16#00#, 6 => 16#00#, 7 => 16#00#];
   begin
      Expect_Zlib_Error_On_Input (Bad, Finish => False);
   end Test_Invalid_Len_Nlen_Raises;

   procedure Test_Invalid_Adler_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Payload    : constant Zlib.Byte_Array := [1 => 42];
      Status     : Zlib.Status_Code;
      Compressed : Zlib.Byte_Array := Zlib.Deflate_Stored (Payload, Status);
   begin
      Assert (Status = Zlib.Ok, "Deflate_Stored single byte must succeed");
      Compressed (Compressed'Last) := Compressed (Compressed'Last) xor 16#FF#;
      Expect_Zlib_Error_On_Input (Compressed, Finish => True);
   end Test_Invalid_Adler_Raises;

   procedure Test_Finish_On_Truncated_Stream_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Payload    : constant Zlib.Byte_Array := [1 => 42, 2 => 43];
      Status     : Zlib.Status_Code;
      Full       : constant Zlib.Byte_Array := Zlib.Deflate_Stored (Payload, Status);
      Truncated  : Zlib.Byte_Array (1 .. Full'Length - 1);
   begin
      Assert (Status = Zlib.Ok, "Deflate_Stored two bytes must succeed");
      for I in Truncated'Range loop
         Truncated (I) := Full (I);
      end loop;
      Expect_Zlib_Error_On_Input (Truncated, Finish => True);
   end Test_Finish_On_Truncated_Stream_Raises;

   procedure Test_Invalid_Block_Type_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Invalid : constant Zlib.Byte_Array := [1 => 16#78#, 2 => 16#01#, 3 => 16#07#];
   begin
      Expect_Zlib_Error_On_Input (Invalid, Finish => False);
   end Test_Invalid_Block_Type_Raises;

   procedure Test_Zlib_Header_Mode_Roundtrip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Payload    : constant Zlib.Byte_Array := [1 => 65, 2 => 66, 3 => 67];
      Status     : Zlib.Status_Code;
      Compressed : constant Zlib.Byte_Array := Zlib.Deflate_Stored (Payload, Status);
      Result     : Zlib.Byte_Array (1 .. Payload'Length);
      Last       : Natural;
   begin
      Assert (Status = Zlib.Ok, "Deflate_Stored must produce a zlib stream");
      Inflate_Stream
        (Compressed,
         Chunk_Size  => 1,
         Output_Size => 1,
         Result      => Result,
         Result_Last => Last,
         Header      => Zlib.Zlib_Header);
      Assert (Last = Payload'Length, "Zlib_Header mode decoded length mismatch");

      for I in Payload'Range loop
         Assert
           (Result (I - Payload'First + 1) = Payload (I),
            "Zlib_Header mode decoded byte mismatch");
      end loop;
   end Test_Zlib_Header_Mode_Roundtrip;

   procedure Test_Adler_Footer_Split
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Payload    : constant Zlib.Byte_Array := [1 => 1, 2 => 2];
      Status     : Zlib.Status_Code;
      Compressed : constant Zlib.Byte_Array := Zlib.Deflate_Stored (Payload, Status);
      Filter     : Zlib.Filter_Type;
      Out_Data   : Ada.Streams.Stream_Element_Array (1 .. 4);
      In_Last    : Ada.Streams.Stream_Element_Offset;
      Out_Last   : Ada.Streams.Stream_Element_Offset;
   begin
      Assert (Status = Zlib.Ok, "Deflate_Stored must produce footer-split fixture");
      Zlib.Inflate_Init (Filter);

      for I in Compressed'First .. Compressed'Last loop
         declare
            In_Data : constant Ada.Streams.Stream_Element_Array (1 .. 1) :=
              [1 => Ada.Streams.Stream_Element (Compressed (I))];
         begin
            Zlib.Translate (Filter, In_Data, In_Last, Out_Data, Out_Last);
            if I < Compressed'Last then
               Assert (not Zlib.Stream_End (Filter), "Stream_End must remain false until final Adler byte");
            end if;
         end;
      end loop;

      Assert (Zlib.Stream_End (Filter), "Stream_End must become true after final Adler byte");
      Zlib.Close (Filter);
   end Test_Adler_Footer_Split;

   procedure Test_Partial_Input_When_Output_Fills
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Payload    : constant Zlib.Byte_Array (1 .. 80) := [others => 16#41#];
      Status     : Zlib.Status_Code;
      Compressed : constant Zlib.Byte_Array := Zlib.Deflate_Stored (Payload, Status);
      Filter     : Zlib.Filter_Type;
      In_Data    : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Compressed'Length));
      Out_Data   : Ada.Streams.Stream_Element_Array (1 .. 1);
      In_Last    : Ada.Streams.Stream_Element_Offset;
      Out_Last   : Ada.Streams.Stream_Element_Offset;
   begin
      Assert (Status = Zlib.Ok, "Deflate_Stored must produce partial-consumption fixture");
      for I in Compressed'Range loop
         In_Data (Ada.Streams.Stream_Element_Offset (I - Compressed'First + 1)) :=
           Ada.Streams.Stream_Element (Compressed (I));
      end loop;

      Zlib.Inflate_Init (Filter);
      Zlib.Translate (Filter, In_Data, In_Last, Out_Data, Out_Last);

      Assert (Out_Last = Out_Data'Last, "one-byte output buffer must be filled");
      Assert
        (In_Last /= Before_First (In_Data) and then In_Last < In_Data'Last,
         "Translate must not report unprocessed input as consumed when output fills");

      Zlib.Close (Filter, Ignore_Error => True);
   end Test_Partial_Input_When_Output_Fills;

   procedure Test_Close_Before_End_Policy
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter : Zlib.Filter_Type;
      Raised : Boolean := False;
   begin
      Zlib.Inflate_Init (Filter);
      begin
         Zlib.Close (Filter, Ignore_Error => False);
      exception
         when Zlib.Zlib_Error =>
            Raised := True;
      end;
      Assert (Raised, "Close before end with Ignore_Error=False must raise Zlib_Error");
      Zlib.Close (Filter, Ignore_Error => True);

      Zlib.Inflate_Init (Filter);
      Zlib.Close (Filter, Ignore_Error => True);
      Assert (not Zlib.Is_Open (Filter), "Close before end with Ignore_Error=True must close silently");
   end Test_Close_Before_End_Policy;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_Empty_Zlib_Stream'Access,
         "streaming stored empty zlib stream");
      Registration.Register_Routine
        (T, Test_Hello_Zlib_Stream'Access,
         "streaming stored hello zlib stream");
      Registration.Register_Routine
        (T, Test_Header_And_Lengths_Split'Access,
         "zlib header and stored LEN/NLEN split");
      Registration.Register_Routine
        (T, Test_Zlib_Header_Mode_Roundtrip'Access,
         "Zlib_Header mode decodes stored stream");
      Registration.Register_Routine
        (T, Test_Adler_Footer_Split'Access,
         "Adler footer split across Translate calls");
      Registration.Register_Routine
        (T, Test_Payload_And_Output_Byte_By_Byte'Access,
         "payload and output byte by byte");
      Registration.Register_Routine
        (T, Test_Partial_Input_When_Output_Fills'Access,
         "Translate reports partial input consumption when output fills");
      Registration.Register_Routine
        (T, Test_Stream_End_False_Before_Footer'Access,
         "Stream_End false before footer");
      Registration.Register_Routine
        (T, Test_Invalid_Header_Raises'Access,
         "invalid zlib header raises Zlib_Error");
      Registration.Register_Routine
        (T, Test_Invalid_Len_Nlen_Raises'Access,
         "invalid stored LEN/NLEN raises Zlib_Error");
      Registration.Register_Routine
        (T, Test_Invalid_Adler_Raises'Access,
         "invalid Adler raises Zlib_Error");
      Registration.Register_Routine
        (T, Test_Finish_On_Truncated_Stream_Raises'Access,
         "Finish on truncated stream raises Zlib_Error");
      Registration.Register_Routine
        (T, Test_Invalid_Block_Type_Raises'Access,
         "invalid Deflate block type raises Zlib_Error");
      Registration.Register_Routine
        (T, Test_Close_Before_End_Policy'Access,
         "Close before end policy");
   end Register_Tests;

end Zlib_Streaming_Inflate_Stored_Tests;
