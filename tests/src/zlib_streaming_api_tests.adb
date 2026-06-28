with Ada.Streams;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;

package body Zlib_Streaming_Api_Tests is
   use type Ada.Streams.Stream_Element_Offset;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib streaming API lifecycle");
   end Name;

   procedure Test_Inflate_Init_Opens_Filter
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter : Zlib.Filter_Type;
   begin
      Assert (not Zlib.Is_Open (Filter), "new filter must start closed");
      Zlib.Inflate_Init (Filter);
      Assert (Zlib.Is_Open (Filter), "Inflate_Init must open filter");
      Zlib.Close (Filter, Ignore_Error => True);
   end Test_Inflate_Init_Opens_Filter;

   procedure Test_Close_Closes_Filter_With_Ignore
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter : Zlib.Filter_Type;
   begin
      Zlib.Inflate_Init (Filter);
      Zlib.Close (Filter, Ignore_Error => True);
      Assert (not Zlib.Is_Open (Filter), "Close Ignore_Error=True must close filter");
   end Test_Close_Closes_Filter_With_Ignore;

   procedure Test_Close_Unopened_Ignore_Is_No_Op
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter : Zlib.Filter_Type;
   begin
      Zlib.Close (Filter, Ignore_Error => True);
      Assert (not Zlib.Is_Open (Filter), "ignored Close on unopened filter must leave filter closed");
   end Test_Close_Unopened_Ignore_Is_No_Op;

   procedure Test_Close_Unopened_Raises_Status_Error
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter : Zlib.Filter_Type;
      Raised : Boolean := False;
   begin
      begin
         Zlib.Close (Filter);
      exception
         when Zlib.Status_Error =>
            Raised := True;
      end;

      Assert (Raised, "Close on unopened filter must raise Status_Error");
   end Test_Close_Unopened_Raises_Status_Error;

   procedure Test_Translate_Before_Init_Raises_Status_Error
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Filter_Type;
      Input    : constant Ada.Streams.Stream_Element_Array (10 .. 12) := [10 => 1, 11 => 2, 12 => 3];
      Output   : Ada.Streams.Stream_Element_Array (20 .. 21);
      In_Last  : Ada.Streams.Stream_Element_Offset := 99;
      Out_Last : Ada.Streams.Stream_Element_Offset := 99;
      Raised   : Boolean := False;
   begin
      begin
         Zlib.Translate (Filter, Input, In_Last, Output, Out_Last);
      exception
         when Zlib.Status_Error =>
            Raised := True;
      end;

      Assert (Raised, "Translate before Inflate_Init must raise Status_Error");
   end Test_Translate_Before_Init_Raises_Status_Error;

   procedure Test_Translate_After_Close_Raises_Status_Error
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Filter_Type;
      Input    : constant Ada.Streams.Stream_Element_Array (1 .. 1) := [1 => 0];
      Output   : Ada.Streams.Stream_Element_Array (1 .. 1);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Raised   : Boolean := False;
   begin
      Zlib.Inflate_Init (Filter);
      Zlib.Close (Filter, Ignore_Error => True);

      begin
         Zlib.Translate (Filter, Input, In_Last, Output, Out_Last);
      exception
         when Zlib.Status_Error =>
            Raised := True;
      end;

      Assert (Raised, "Translate after Close must raise Status_Error");
   end Test_Translate_After_Close_Raises_Status_Error;

   procedure Test_Gzip_Finish_On_Truncated_Header_Fails
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Filter_Type;
      Input    : constant Ada.Streams.Stream_Element_Array (3 .. 4) := [3 => 16#1F#, 4 => 16#8B#];
      Output   : Ada.Streams.Stream_Element_Array (7 .. 8);
      In_Last  : Ada.Streams.Stream_Element_Offset := 99;
      Out_Last : Ada.Streams.Stream_Element_Offset := 99;
      Raised   : Boolean := False;
   begin
      Zlib.Inflate_Init (Filter, Zlib.GZip);

      begin
         Zlib.Translate (Filter, Input, In_Last, Output, Out_Last, Zlib.Finish);
      exception
         when Zlib.Zlib_Error =>
            Raised := True;
      end;

      Assert (Raised, "Finish on truncated gzip header must raise Zlib_Error");
      Assert (Zlib.Is_Open (Filter), "failed filter remains open until explicit Close");
      Zlib.Close (Filter, Ignore_Error => True);
   end Test_Gzip_Finish_On_Truncated_Header_Fails;

   procedure Test_Raw_Deflate_Init_Is_Supported
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Filter_Type;
      Input    : constant Ada.Streams.Stream_Element_Array (1 .. 2) := [1 => 16#03#, 2 => 16#00#];
      Output   : Ada.Streams.Stream_Element_Array (1 .. 1);
      In_Last  : Ada.Streams.Stream_Element_Offset := 99;
      Out_Last : Ada.Streams.Stream_Element_Offset := 99;
   begin
      Zlib.Inflate_Init (Filter, Zlib.Raw_Deflate);
      Zlib.Translate (Filter, Input, In_Last, Output, Out_Last, Zlib.Finish);

      Assert (Zlib.Stream_End (Filter), "empty raw Deflate final block must be supported");
      Assert (In_Last = Input'Last, "supported raw Deflate must consume the empty final block");
      Assert (Out_Last = Output'First - 1, "empty raw Deflate block must produce no output");
      Zlib.Close (Filter);
   end Test_Raw_Deflate_Init_Is_Supported;

   procedure Test_Failed_Filter_Raises_Zlib_Error
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Filter_Type;
      Input    : constant Ada.Streams.Stream_Element_Array (1 .. 1) := [1 => 0];
      Output   : Ada.Streams.Stream_Element_Array (1 .. 1);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Raised   : Boolean := False;
   begin
      Zlib.Inflate_Init (Filter, Zlib.GZip);

      begin
         Zlib.Translate (Filter, Input, In_Last, Output, Out_Last);
      exception
         when Zlib.Zlib_Error =>
            null;
      end;

      begin
         Zlib.Translate (Filter, Input, In_Last, Output, Out_Last);
      exception
         when Zlib.Zlib_Error =>
            Raised := True;
      end;

      Assert (Raised, "Translate on failed filter must raise Zlib_Error");

      Raised := False;
      begin
         Zlib.Close (Filter);
      exception
         when Zlib.Zlib_Error =>
            Raised := True;
      end;

      Assert (Raised, "Close on failed filter must raise Zlib_Error when not ignored");
      Assert (not Zlib.Is_Open (Filter), "Close on failed filter must clear state even when it raises");
   end Test_Failed_Filter_Raises_Zlib_Error;

   procedure Test_Flush_Before_Init_Raises_Status_Error
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Filter_Type;
      Output   : Ada.Streams.Stream_Element_Array (5 .. 6);
      Out_Last : Ada.Streams.Stream_Element_Offset := 99;
      Raised   : Boolean := False;
   begin
      begin
         Zlib.Flush (Filter, Output, Out_Last);
      exception
         when Zlib.Status_Error =>
            Raised := True;
      end;

      Assert (Raised, "Flush before Inflate_Init must raise Status_Error");
   end Test_Flush_Before_Init_Raises_Status_Error;

   procedure Test_Flush_After_Close_Raises_Status_Error
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Filter_Type;
      Output   : Ada.Streams.Stream_Element_Array (9 .. 10);
      Out_Last : Ada.Streams.Stream_Element_Offset := 99;
      Raised   : Boolean := False;
   begin
      Zlib.Inflate_Init (Filter);
      Zlib.Close (Filter, Ignore_Error => True);

      begin
         Zlib.Flush (Filter, Output, Out_Last);
      exception
         when Zlib.Status_Error =>
            Raised := True;
      end;

      Assert (Raised, "Flush after Close must raise Status_Error");
   end Test_Flush_After_Close_Raises_Status_Error;

   procedure Test_Flush_Finish_Before_End_Raises_Zlib_Error
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Filter_Type;
      Output   : Ada.Streams.Stream_Element_Array (2 .. 3);
      Out_Last : Ada.Streams.Stream_Element_Offset := 99;
      Raised   : Boolean := False;
   begin
      Zlib.Inflate_Init (Filter);

      begin
         Zlib.Flush (Filter, Output, Out_Last, Zlib.Finish);
      exception
         when Zlib.Zlib_Error =>
            Raised := True;
      end;

      Assert (Raised, "Flush(Finish) before stream end must raise Zlib_Error");
      Zlib.Close (Filter, Ignore_Error => True);
   end Test_Flush_Finish_Before_End_Raises_Zlib_Error;

   procedure Test_Stream_End_Is_False_Before_Completion
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter : Zlib.Filter_Type;
   begin
      Assert (not Zlib.Stream_End (Filter), "Stream_End on unopened filter must be False");
      Zlib.Inflate_Init (Filter);
      Assert (not Zlib.Stream_End (Filter), "Stream_End before completion must be False");
      Zlib.Close (Filter, Ignore_Error => True);
      Assert (not Zlib.Stream_End (Filter), "Stream_End on closed filter must be False");
   end Test_Stream_End_Is_False_Before_Completion;

   procedure Test_Header_Enum_Values_Are_Accepted
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter : Zlib.Filter_Type;
   begin
      for Header in Zlib.Header_Type loop
         Zlib.Inflate_Init (Filter, Header);
         Assert (Zlib.Is_Open (Filter), "Inflate_Init must accept every Header_Type value");
         Zlib.Close (Filter, Ignore_Error => True);
      end loop;
   end Test_Header_Enum_Values_Are_Accepted;

   procedure Test_Null_Arrays_Use_First_As_No_Element_Marker
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Filter_Type;
      Input    : constant Ada.Streams.Stream_Element_Array (1 .. 0) := [];
      Output   : Ada.Streams.Stream_Element_Array (5 .. 4);
      In_Last  : Ada.Streams.Stream_Element_Offset := 99;
      Out_Last : Ada.Streams.Stream_Element_Offset := 99;
      Raised   : Boolean := False;
   begin
      begin
         Zlib.Translate (Filter, Input, In_Last, Output, Out_Last);
      exception
         when Zlib.Status_Error =>
            Raised := True;
      end;

      Assert (Raised, "Translate with null arrays before init must raise Status_Error");
   end Test_Null_Arrays_Use_First_As_No_Element_Marker;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_Inflate_Init_Opens_Filter'Access,
         "Inflate_Init opens filter");
      Registration.Register_Routine
        (T, Test_Close_Closes_Filter_With_Ignore'Access,
         "Close closes filter with Ignore_Error=True");
      Registration.Register_Routine
        (T, Test_Close_Unopened_Ignore_Is_No_Op'Access,
         "Close unopened with Ignore_Error=True is no-op");
      Registration.Register_Routine
        (T, Test_Close_Unopened_Raises_Status_Error'Access,
         "Close unopened with Ignore_Error=False raises Status_Error");
      Registration.Register_Routine
        (T, Test_Translate_Before_Init_Raises_Status_Error'Access,
         "Streaming API Translate before init raises Status_Error");
      Registration.Register_Routine
        (T, Test_Translate_After_Close_Raises_Status_Error'Access,
         "Translate after close raises Status_Error");
      Registration.Register_Routine
        (T, Test_Gzip_Finish_On_Truncated_Header_Fails'Access,
         "Finish on truncated gzip header raises Zlib_Error");
      Registration.Register_Routine
        (T, Test_Raw_Deflate_Init_Is_Supported'Access,
         "Raw_Deflate mode supports raw empty final block");
      Registration.Register_Routine
        (T, Test_Failed_Filter_Raises_Zlib_Error'Access,
         "failed filter raises Zlib_Error");
      Registration.Register_Routine
        (T, Test_Flush_Before_Init_Raises_Status_Error'Access,
         "Streaming API Flush before init raises Status_Error");
      Registration.Register_Routine
        (T, Test_Flush_After_Close_Raises_Status_Error'Access,
         "Flush after close raises Status_Error");
      Registration.Register_Routine
        (T, Test_Flush_Finish_Before_End_Raises_Zlib_Error'Access,
         "Flush(Finish) before end raises Zlib_Error");
      Registration.Register_Routine
        (T, Test_Stream_End_Is_False_Before_Completion'Access,
         "Stream_End is False before completion");
      Registration.Register_Routine
        (T, Test_Header_Enum_Values_Are_Accepted'Access,
         "Header enum accepts all values");
      Registration.Register_Routine
        (T, Test_Null_Arrays_Use_First_As_No_Element_Marker'Access,
         "Null arrays use First as no-element marker");
   end Register_Tests;

end Zlib_Streaming_Api_Tests;
