with Ada.Streams; use Ada.Streams;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib; use Zlib;
with Zlib_Fixture_Data;

package body Zlib_GZip_Multimember_Tests is

   package F renames Zlib_Fixture_Data;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib gzip multi-member inflate");
   end Name;

   function Before_First
     (Data : Ada.Streams.Stream_Element_Array)
      return Ada.Streams.Stream_Element_Offset
   is
   begin
      return Data'First - 1;
   end Before_First;

   function To_Stream_Array
     (Input : Zlib.Byte_Array)
      return Ada.Streams.Stream_Element_Array
   is
      Result : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Input'Length));
      J      : Ada.Streams.Stream_Element_Offset := Result'First;
   begin
      for I in Input'Range loop
         Result (J) := Ada.Streams.Stream_Element (Input (I));
         J := J + 1;
      end loop;

      return Result;
   end To_Stream_Array;

   procedure Copy_Output
     (Out_Data    : Ada.Streams.Stream_Element_Array;
      Out_Last    : Ada.Streams.Stream_Element_Offset;
      Result      : in out Zlib.Byte_Array;
      Result_Last : in out Natural)
   is
   begin
      if Out_Last = Before_First (Out_Data) then
         return;
      end if;

      for I in Out_Data'First .. Out_Last loop
         Result_Last := Result_Last + 1;
         Result (Result_Last) := Zlib.Byte (Out_Data (I));
      end loop;
   end Copy_Output;

   procedure Decode_Streaming
     (Input       : Zlib.Byte_Array;
      GZip_Mode   : Zlib.GZip_Member_Mode;
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
         GZip_Mode => GZip_Mode);

      while Pos <= Input'Last loop
         declare
            Count   : constant Natural := Natural'Min (Chunk_Size, Input'Last - Pos + 1);
            In_Data : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Count));
         begin
            for I in 0 .. Count - 1 loop
               In_Data (Ada.Streams.Stream_Element_Offset (I + 1)) :=
                 Ada.Streams.Stream_Element (Input (Pos + I));
            end loop;

            declare
               Start : Ada.Streams.Stream_Element_Offset := In_Data'First;
            begin
               for Guard in 1 .. 10_000 loop
                  exit when Start > In_Data'Last;

                  declare
                     Out_Data : Ada.Streams.Stream_Element_Array
                       (1 .. Ada.Streams.Stream_Element_Offset (Output_Size));
                     In_Last  : Ada.Streams.Stream_Element_Offset;
                     Out_Last : Ada.Streams.Stream_Element_Offset;
                  begin
                     Zlib.Translate
                       (Filter   => Filter,
                        In_Data  => In_Data (Start .. In_Data'Last),
                        In_Last  => In_Last,
                        Out_Data => Out_Data,
                        Out_Last => Out_Last,
                        Flush    => Zlib.No_Flush);
                     Copy_Output (Out_Data, Out_Last, Result, Result_Last);

                     if In_Last /= Before_First (In_Data (Start .. In_Data'Last)) then
                        Start := In_Last + 1;
                     elsif Out_Last = Before_First (Out_Data) then
                        exit;
                     end if;
                  end;
               end loop;

               Assert (Start > In_Data'Last, "streaming decoder failed to consume chunk");
            end;

            Pos := Pos + Count;
         end;
      end loop;

      for Guard in 1 .. 10_000 loop
         declare
            Out_Data : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Output_Size));
            Out_Last : Ada.Streams.Stream_Element_Offset;
         begin
            Zlib.Flush
              (Filter   => Filter,
               Out_Data => Out_Data,
               Out_Last => Out_Last,
               Flush    => Zlib.Finish);
            Copy_Output (Out_Data, Out_Last, Result, Result_Last);
            exit when Zlib.Stream_End (Filter);
            exit when Out_Last = Before_First (Out_Data);
         end;
      end loop;

      Assert (Zlib.Stream_End (Filter), "streaming gzip must reach logical stream end");
      Zlib.Close (Filter);
   end Decode_Streaming;

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

   procedure Assert_Result_Prefix
     (Result      : Zlib.Byte_Array;
      Result_Last : Natural;
      Expected    : Zlib.Byte_Array;
      Message     : String)
   is
   begin
      Assert (Result_Last = Expected'Length, Message & ": decoded length mismatch");
      for I in Expected'Range loop
         Assert
           (Result (Result'First + (I - Expected'First)) = Expected (I),
            Message & ": byte mismatch");
      end loop;
   end Assert_Result_Prefix;

   function Make_GZip
     (Input : Zlib.Byte_Array;
      Mode  : Zlib.Compression_Mode;
      Label : String)
      return Zlib.Byte_Array
   is
      Status : Zlib.Status_Code;
      Result : constant Zlib.Byte_Array := Zlib.GZip (Input, Mode, Status);
   begin
      Assert (Status = Zlib.Ok, Label & " gzip fixture compression must succeed");
      return Result;
   end Make_GZip;

   procedure Test_Default_GZip_Decodes_Second_Member
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status   : Zlib.Status_Code;
      G1       : constant Zlib.Byte_Array := Make_GZip (F.Plain_Stored, Zlib.Stored, "stored member");
      G2       : constant Zlib.Byte_Array := Make_GZip (F.Plain_Fixed, Zlib.Fixed, "fixed member");
      Both     : constant Zlib.Byte_Array := G1 & G2;
      Expected : constant Zlib.Byte_Array := F.Plain_Stored & F.Plain_Fixed;
      Decoded  : constant Zlib.Byte_Array := Zlib.Inflate_With_Header (Both, Zlib.GZip, Status);
   begin
      Assert (Status = Zlib.Ok,
              "default one-shot gzip inflate must accept a second concatenated member");
      Assert_Same (Decoded, Expected, "default gzip output concatenates payloads");
   end Test_Default_GZip_Decodes_Second_Member;

   procedure Test_Explicit_Single_Member_Rejects_Second_Member
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status  : Zlib.Status_Code;
      G1      : constant Zlib.Byte_Array := Make_GZip (F.Plain_Stored, Zlib.Stored, "stored member");
      G2      : constant Zlib.Byte_Array := Make_GZip (F.Plain_Fixed, Zlib.Fixed, "fixed member");
      Both    : constant Zlib.Byte_Array := G1 & G2;
      Decoded : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Both, Zlib.GZip, Zlib.Single_Member, Status);
   begin
      pragma Unreferenced (Decoded);
      Assert (Status = Zlib.Invalid_Header,
              "explicit single-member gzip inflate must reject a second concatenated member");
   end Test_Explicit_Single_Member_Rejects_Second_Member;

   procedure Test_Single_Member_Rejects_Trailing_Garbage
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status  : Zlib.Status_Code;
      G1      : constant Zlib.Byte_Array := Make_GZip (F.Plain_Stored, Zlib.Stored, "stored member");
      Garbage : constant Zlib.Byte_Array := [1 => 16#00#];
      Input   : constant Zlib.Byte_Array := G1 & Garbage;
      Decoded : constant Zlib.Byte_Array := Zlib.Inflate_With_Header (Input, Zlib.GZip, Status);
   begin
      pragma Unreferenced (Decoded);
      Assert (Status = Zlib.Invalid_Header,
              "default one-shot gzip inflate must reject trailing garbage");
   end Test_Single_Member_Rejects_Trailing_Garbage;

   procedure Test_Multi_Member_Decodes_Concatenated_Members
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status   : Zlib.Status_Code;
      G1       : constant Zlib.Byte_Array := Make_GZip (F.Plain_Stored, Zlib.Stored, "stored member");
      G2       : constant Zlib.Byte_Array := Make_GZip (F.Plain_Fixed, Zlib.Fixed, "fixed member");
      Input    : constant Zlib.Byte_Array := G1 & G2;
      Expected : constant Zlib.Byte_Array := F.Plain_Stored & F.Plain_Fixed;
      Decoded  : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Input, Zlib.GZip, Zlib.Multi_Member, Status);
   begin
      Assert (Status = Zlib.Ok, "explicit multi-member gzip inflate must succeed");
      Assert_Same (Decoded, Expected, "multi-member gzip output concatenates payloads");
   end Test_Multi_Member_Decodes_Concatenated_Members;

   procedure Test_Multi_Member_Rejects_Trailing_Garbage
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status  : Zlib.Status_Code;
      G1      : constant Zlib.Byte_Array := Make_GZip (F.Plain_Stored, Zlib.Stored, "stored member");
      Garbage : constant Zlib.Byte_Array := [1 => 16#00#];
      Input   : constant Zlib.Byte_Array := G1 & Garbage;
      Decoded : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Input, Zlib.GZip, Zlib.Multi_Member, Status);
   begin
      pragma Unreferenced (Decoded);
      Assert (Status = Zlib.Invalid_Header,
              "multi-member gzip inflate must reject non-gzip trailing bytes");
   end Test_Multi_Member_Rejects_Trailing_Garbage;

   procedure Test_Streaming_Multi_Member_No_Flush_Boundary_Returns
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      G1      : constant Zlib.Byte_Array := Make_GZip (F.Plain_Stored, Zlib.Stored, "stored member");
      In_Data : constant Ada.Streams.Stream_Element_Array := To_Stream_Array (G1);
      Filter  : Zlib.Filter_Type;
      In_Last : Ada.Streams.Stream_Element_Offset;
      Out_Data : Ada.Streams.Stream_Element_Array (1 .. 1024);
      Out_Last : Ada.Streams.Stream_Element_Offset;
   begin
      Zlib.Inflate_Init
        (Filter    => Filter,
         Header    => Zlib.GZip,
         GZip_Mode => Zlib.Multi_Member);

      Zlib.Translate
        (Filter   => Filter,
         In_Data  => In_Data,
         In_Last  => In_Last,
         Out_Data => Out_Data,
         Out_Last => Out_Last,
         Flush    => Zlib.No_Flush);

      Assert (In_Last = In_Data'Last,
              "complete first member should be consumed under No_Flush");
      Assert (not Zlib.Stream_End (Filter),
              "multi-member No_Flush member boundary is not logical stream end");

      Zlib.Flush
        (Filter   => Filter,
         Out_Data => Out_Data,
         Out_Last => Out_Last,
         Flush    => Zlib.Finish);
      Assert (Zlib.Stream_End (Filter),
              "later Finish must finalize a completed multi-member stream");
      Zlib.Close (Filter);
   end Test_Streaming_Multi_Member_No_Flush_Boundary_Returns;

   procedure Test_Streaming_Multi_Member_Split_Calls
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      G1       : constant Zlib.Byte_Array := Make_GZip (F.Plain_Stored, Zlib.Stored, "stored member");
      G2       : constant Zlib.Byte_Array := Make_GZip (F.Plain_Fixed, Zlib.Fixed, "fixed member");
      Expected : constant Zlib.Byte_Array := F.Plain_Stored & F.Plain_Fixed;
      Result   : Zlib.Byte_Array (1 .. 4096);
      Last     : Natural;
   begin
      Decode_Streaming (G1 & G2, Zlib.Multi_Member, G1'Length, 1024, Result, Last);
      Assert_Result_Prefix (Result, Last, Expected,
                            "multi-member streaming split by member");
   end Test_Streaming_Multi_Member_Split_Calls;

   procedure Test_Streaming_Default_GZip_Decodes_Second_Member
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      G1       : constant Zlib.Byte_Array := Make_GZip (F.Plain_Stored, Zlib.Stored, "stored member");
      G2       : constant Zlib.Byte_Array := Make_GZip (F.Plain_Fixed, Zlib.Fixed, "fixed member");
      Expected : constant Zlib.Byte_Array := F.Plain_Stored & F.Plain_Fixed;
      Input    : constant Ada.Streams.Stream_Element_Array := To_Stream_Array (G1 & G2);
      Filter   : Zlib.Filter_Type;
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Data : Ada.Streams.Stream_Element_Array (1 .. 4096);
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Result   : Zlib.Byte_Array (1 .. 4096);
      Last     : Natural := 0;
   begin
      Zlib.Inflate_Init (Filter, Header => Zlib.GZip);
      Zlib.Translate
        (Filter   => Filter,
         In_Data  => Input,
         In_Last  => In_Last,
         Out_Data => Out_Data,
         Out_Last => Out_Last,
         Flush    => Zlib.Finish);
      Copy_Output (Out_Data, Out_Last, Result, Last);

      Assert (In_Last = Input'Last, "default streaming gzip must consume both members");
      Assert (Zlib.Stream_End (Filter), "default streaming gzip must finish after both members");
      Assert_Result_Prefix
        (Result, Last, Expected, "default streaming gzip concatenates member payloads");
      Zlib.Close (Filter);
   end Test_Streaming_Default_GZip_Decodes_Second_Member;

   procedure Test_Streaming_Multi_Member_Header_Split_Bytewise
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      G1       : constant Zlib.Byte_Array := Make_GZip (F.Plain_Stored, Zlib.Stored, "stored member");
      G2       : constant Zlib.Byte_Array := Make_GZip (F.Plain_Fixed, Zlib.Fixed, "fixed member");
      Expected : constant Zlib.Byte_Array := F.Plain_Stored & F.Plain_Fixed;
      Result   : Zlib.Byte_Array (1 .. 4096);
      Last     : Natural;
   begin
      Decode_Streaming (G1 & G2, Zlib.Multi_Member, 1, 1024, Result, Last);
      Assert_Result_Prefix (Result, Last, Expected,
                            "multi-member streaming accepts byte-split second header");
   end Test_Streaming_Multi_Member_Header_Split_Bytewise;

   procedure Test_Streaming_Multi_Member_Output_Size_One
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      G1       : constant Zlib.Byte_Array := Make_GZip (F.Plain_Stored, Zlib.Stored, "stored member");
      G2       : constant Zlib.Byte_Array := Make_GZip (F.Plain_Fixed, Zlib.Fixed, "fixed member");
      Expected : constant Zlib.Byte_Array := F.Plain_Stored & F.Plain_Fixed;
      Result   : Zlib.Byte_Array (1 .. 4096);
      Last     : Natural;
   begin
      Decode_Streaming (G1 & G2, Zlib.Multi_Member, G1'Length + G2'Length, 1, Result, Last);
      Assert_Result_Prefix (Result, Last, Expected,
                            "multi-member streaming works with one-byte output buffer");
   end Test_Streaming_Multi_Member_Output_Size_One;

   procedure Test_Streaming_Multi_Member_Trailer_Then_Header_Same_Buffer
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      G1       : constant Zlib.Byte_Array := Make_GZip (F.Plain_Stored, Zlib.Stored, "stored member");
      G2       : constant Zlib.Byte_Array := Make_GZip (F.Plain_Fixed, Zlib.Fixed, "fixed member");
      Expected : constant Zlib.Byte_Array := F.Plain_Stored & F.Plain_Fixed;
      Result   : Zlib.Byte_Array (1 .. 4096);
      Last     : Natural;
   begin
      Decode_Streaming
        (Input       => G1 & G2,
         GZip_Mode   => Zlib.Multi_Member,
         Chunk_Size  => G1'Length + G2'Length,
         Output_Size => 1024,
         Result      => Result,
         Result_Last => Last);
      Assert_Result_Prefix
        (Result, Last, Expected,
         "multi-member streaming accepts first trailer followed by next header in one input buffer");
   end Test_Streaming_Multi_Member_Trailer_Then_Header_Same_Buffer;

   procedure Test_Streaming_Single_Member_Rejects_Trailing_Garbage
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      G1      : constant Zlib.Byte_Array := Make_GZip (F.Plain_Stored, Zlib.Stored, "stored member");
      Garbage : constant Zlib.Byte_Array := [1 => 16#00#];
      Input   : constant Ada.Streams.Stream_Element_Array := To_Stream_Array (G1 & Garbage);
      Filter  : Zlib.Filter_Type;
      In_Last : Ada.Streams.Stream_Element_Offset;
      Out_Data : Ada.Streams.Stream_Element_Array (1 .. 1024);
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Raised  : Boolean := False;
   begin
      Zlib.Inflate_Init
        (Filter    => Filter,
         Header    => Zlib.GZip,
         GZip_Mode => Zlib.Single_Member);

      begin
         Zlib.Translate
           (Filter   => Filter,
            In_Data  => Input,
            In_Last  => In_Last,
            Out_Data => Out_Data,
            Out_Last => Out_Last,
            Flush    => Zlib.Finish);
      exception
         when Zlib.Zlib_Error =>
            Raised := True;
      end;

      Assert (Raised, "single-member streaming Finish must reject trailing garbage");
      Zlib.Close (Filter, Ignore_Error => True);
   end Test_Streaming_Single_Member_Rejects_Trailing_Garbage;

   procedure Test_Streaming_Single_Member_Rejects_Second_Member
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      G1      : constant Zlib.Byte_Array := Make_GZip (F.Plain_Stored, Zlib.Stored, "stored member");
      G2      : constant Zlib.Byte_Array := Make_GZip (F.Plain_Fixed, Zlib.Fixed, "fixed member");
      Input   : constant Ada.Streams.Stream_Element_Array := To_Stream_Array (G1 & G2);
      Filter  : Zlib.Filter_Type;
      In_Last : Ada.Streams.Stream_Element_Offset;
      Out_Data : Ada.Streams.Stream_Element_Array (1 .. 1024);
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Raised  : Boolean := False;
   begin
      Zlib.Inflate_Init
        (Filter    => Filter,
         Header    => Zlib.GZip,
         GZip_Mode => Zlib.Single_Member);

      begin
         Zlib.Translate
           (Filter   => Filter,
            In_Data  => Input,
            In_Last  => In_Last,
            Out_Data => Out_Data,
            Out_Last => Out_Last,
            Flush    => Zlib.Finish);
      exception
         when Zlib.Zlib_Error =>
            Raised := True;
      end;

      Assert (Raised, "single-member streaming Finish must reject a second member");
      Zlib.Close (Filter, Ignore_Error => True);
   end Test_Streaming_Single_Member_Rejects_Second_Member;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Default_GZip_Decodes_Second_Member'Access,
         "one-shot gzip decodes concatenated members by default");
      Register_Routine
        (T, Test_Explicit_Single_Member_Rejects_Second_Member'Access,
         "explicit single-member rejects concatenated gzip member");
      Register_Routine
        (T, Test_Single_Member_Rejects_Trailing_Garbage'Access,
         "single-member rejects trailing garbage");
      Register_Routine
        (T, Test_Multi_Member_Decodes_Concatenated_Members'Access,
         "multi-member decodes concatenated members");
      Register_Routine
        (T, Test_Multi_Member_Rejects_Trailing_Garbage'Access,
         "multi-member rejects trailing garbage");
      Register_Routine
        (T, Test_Streaming_Multi_Member_No_Flush_Boundary_Returns'Access,
         "streaming multi-member member boundary returns under No_Flush");
      Register_Routine
        (T, Test_Streaming_Multi_Member_Split_Calls'Access,
         "streaming multi-member decodes members split across calls");
      Register_Routine
        (T, Test_Streaming_Default_GZip_Decodes_Second_Member'Access,
         "streaming gzip decodes concatenated members by default");
      Register_Routine
        (T, Test_Streaming_Multi_Member_Header_Split_Bytewise'Access,
         "streaming multi-member accepts byte-split header");
      Register_Routine
        (T, Test_Streaming_Multi_Member_Output_Size_One'Access,
         "streaming multi-member handles one-byte output buffer");
      Register_Routine
        (T, Test_Streaming_Multi_Member_Trailer_Then_Header_Same_Buffer'Access,
         "streaming multi-member accepts trailer then next header in same buffer");
      Register_Routine
        (T, Test_Streaming_Single_Member_Rejects_Trailing_Garbage'Access,
         "streaming single-member rejects trailing garbage on Finish");
      Register_Routine
        (T, Test_Streaming_Single_Member_Rejects_Second_Member'Access,
         "streaming single-member rejects second member on Finish");
   end Register_Tests;
end Zlib_GZip_Multimember_Tests;
