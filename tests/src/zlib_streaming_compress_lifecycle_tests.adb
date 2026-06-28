with Ada.Streams;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;

package body Zlib_Streaming_Compress_Lifecycle_Tests is
   use type Ada.Streams.Stream_Element_Offset;
   use type Zlib.Header_Type;
   use type Zlib.Compression_Mode;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib streaming compression lifecycle hardening");
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

   procedure Expect_Status_Error
     (Label : String;
      Test  : not null access procedure)
   is
      Hit : Boolean := False;
   begin
      begin
         Test.all;
      exception
         when Zlib.Status_Error =>
            Hit := True;
      end;
      Assert (Hit, Label & " must raise Status_Error");
   end Expect_Status_Error;

   procedure Expect_Zlib_Error
     (Label : String;
      Test  : not null access procedure)
   is
      Hit : Boolean := False;
   begin
      begin
         Test.all;
      exception
         when Zlib.Zlib_Error =>
            Hit := True;
      end;
      Assert (Hit, Label & " must raise Zlib_Error");
   end Expect_Zlib_Error;

   procedure Make_Incomplete
     (Filter : in out Zlib.Compression_Filter_Type)
   is
      Input    : constant Ada.Streams.Stream_Element_Array (10 .. 10) := [10 => 1];
      Output   : Ada.Streams.Stream_Element_Array (20 .. 20);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
   begin
      Zlib.Deflate_Init (Filter, Header => Zlib.Raw_Deflate, Mode => Zlib.Auto);
      Zlib.Compress (Filter, Input, In_Last, Output, Out_Last);
      Assert (Zlib.Is_Open (Filter), "incomplete compression filter must remain open");
   end Make_Incomplete;

   procedure Finish_Filter
     (Filter : in out Zlib.Compression_Filter_Type)
   is
      Output   : Ada.Streams.Stream_Element_Array (1 .. 2);
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Calls    : Natural := 0;
   begin
      while not Zlib.Compress_Stream_End (Filter) loop
         Zlib.Compress_Flush (Filter, Output, Out_Last, Flush => Zlib.Finish);
         Calls := Calls + 1;
         Assert (Calls < 10_000, "streaming compression finish must make bounded progress");
      end loop;
   end Finish_Filter;

   procedure Test_Deflate_Init_Reset_States
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter : Zlib.Compression_Filter_Type;
   begin
      Zlib.Deflate_Init (Filter, Header => Zlib.GZip, Mode => Zlib.Fixed);
      Assert (Zlib.Is_Open (Filter), "Deflate_Init opens unopened filter");
      Zlib.Compress_Close (Filter, Ignore_Error => True);

      Zlib.Deflate_Init (Filter, Header => Zlib.GZip, Mode => Zlib.Fixed);
      Zlib.Deflate_Init (Filter, Header => Zlib.Zlib_Header, Mode => Zlib.Stored);
      Assert (Zlib.Is_Open (Filter), "Deflate_Init resets already-open filter");
      Zlib.Compress_Close (Filter, Ignore_Error => True);

      Make_Incomplete (Filter);
      Zlib.Deflate_Init (Filter, Header => Zlib.Zlib_Header, Mode => Zlib.Fixed);
      Assert (Zlib.Is_Open (Filter), "Deflate_Init resets incomplete filter");
      Zlib.Compress_Close (Filter, Ignore_Error => True);

      Zlib.Deflate_Init (Filter, Header => Zlib.GZip, Mode => Zlib.Stored);
      Finish_Filter (Filter);
      Assert (Zlib.Compress_Stream_End (Filter), "test setup must complete filter");
      Zlib.Deflate_Init (Filter, Header => Zlib.Zlib_Header, Mode => Zlib.Dynamic);
      Assert (Zlib.Is_Open (Filter), "Deflate_Init resets completed filter");
      Zlib.Compress_Close (Filter, Ignore_Error => True);

      Zlib.Deflate_Init (Filter, Header => Zlib.Zlib_Header, Mode => Zlib.Stored);
      Assert (Zlib.Is_Open (Filter), "Deflate_Init opens closed filter");
      Zlib.Compress_Close (Filter, Ignore_Error => True);
   end Test_Deflate_Init_Reset_States;

   procedure Test_Is_Open_Incomplete_Until_Close
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter : Zlib.Compression_Filter_Type;
   begin
      Assert (not Zlib.Is_Open (Filter), "Is_Open false before Deflate_Init");
      Zlib.Deflate_Init (Filter);
      Assert (Zlib.Is_Open (Filter), "Is_Open true after Deflate_Init");
      Zlib.Compress_Close (Filter, Ignore_Error => True);
      Assert (not Zlib.Is_Open (Filter), "Is_Open false after Compress_Close");

      Make_Incomplete (Filter);
      Assert (Zlib.Is_Open (Filter), "Is_Open true for incomplete filter until close");
      Zlib.Compress_Close (Filter, Ignore_Error => True);
      Assert (not Zlib.Is_Open (Filter), "Is_Open false after closing incomplete filter");
   end Test_Is_Open_Incomplete_Until_Close;

   procedure Test_Lifecycle_Misuse_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Compression_Filter_Type;
      Input    : constant Ada.Streams.Stream_Element_Array (5 .. 5) := [5 => 9];
      Output   : Ada.Streams.Stream_Element_Array (9 .. 9);
      In_Last  : Ada.Streams.Stream_Element_Offset := 99;
      Out_Last : Ada.Streams.Stream_Element_Offset := 99;
      procedure Compress_Call is
      begin
         Zlib.Compress (Filter, Input, In_Last, Output, Out_Last);
      end Compress_Call;
      procedure Flush_Call is
      begin
         Zlib.Compress_Flush (Filter, Output, Out_Last);
      end Flush_Call;
   begin
      Expect_Status_Error ("Compress before init", Compress_Call'Access);

      Out_Last := 99;
      Expect_Status_Error ("Compress_Flush before init", Flush_Call'Access);

      Zlib.Deflate_Init (Filter);
      Zlib.Compress_Close (Filter, Ignore_Error => True);
      Expect_Status_Error ("Compress after close", Compress_Call'Access);
      Expect_Status_Error ("Compress_Flush after close", Flush_Call'Access);
   end Test_Lifecycle_Misuse_Raises;

   procedure Test_Incomplete_State_Behavior
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter : Zlib.Compression_Filter_Type;
      procedure Close_Call is
      begin
         Zlib.Compress_Close (Filter);
      end Close_Call;
   begin
      Make_Incomplete (Filter);
      Expect_Zlib_Error ("Compress_Close incomplete Ignore_Error=False", Close_Call'Access);
      Assert (not Zlib.Is_Open (Filter), "Compress_Close incomplete Ignore_Error=False still closes");

      Make_Incomplete (Filter);
      Zlib.Compress_Close (Filter, Ignore_Error => True);
      Assert (not Zlib.Is_Open (Filter), "Compress_Close incomplete Ignore_Error=True closes silently");
   end Test_Incomplete_State_Behavior;

   procedure Test_Close_Rules
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter : Zlib.Compression_Filter_Type;
      procedure Close_Call is
      begin
         Zlib.Compress_Close (Filter);
      end Close_Call;
   begin
      Expect_Status_Error ("Compress_Close unopened Ignore_Error=False", Close_Call'Access);
      Zlib.Compress_Close (Filter, Ignore_Error => True);

      Zlib.Deflate_Init (Filter);
      Expect_Zlib_Error ("Compress_Close incomplete Ignore_Error=False", Close_Call'Access);
      Assert (not Zlib.Is_Open (Filter), "incomplete close with error still clears state");

      Zlib.Deflate_Init (Filter);
      Zlib.Compress_Close (Filter, Ignore_Error => True);
      Assert (not Zlib.Is_Open (Filter), "Compress_Close incomplete Ignore_Error=True closes");

      Zlib.Deflate_Init (Filter);
      Finish_Filter (Filter);
      Zlib.Compress_Close (Filter);
      Assert (not Zlib.Is_Open (Filter), "Compress_Close completed closes normally");

      Expect_Status_Error ("Compress_Close already closed Ignore_Error=False", Close_Call'Access);
      Zlib.Compress_Close (Filter, Ignore_Error => True);
      Assert (not Zlib.Is_Open (Filter), "Compress_Close already closed Ignore_Error=True is no-op");
   end Test_Close_Rules;

   procedure Test_Header_Mode_Matrix
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Headers : constant array (Positive range <>) of Zlib.Header_Type :=
        [Zlib.Default, Zlib.Zlib_Header, Zlib.GZip, Zlib.Raw_Deflate];
      Modes : constant array (Positive range <>) of Zlib.Compression_Mode :=
        [Zlib.Stored, Zlib.Fixed, Zlib.Dynamic, Zlib.Auto];
   begin
      for Header of Headers loop
         for Mode of Modes loop
            declare
               Filter   : Zlib.Compression_Filter_Type;
               Input    : constant Ada.Streams.Stream_Element_Array (1 .. 0) := [];
               Output   : Ada.Streams.Stream_Element_Array (1 .. 16);
               In_Last  : Ada.Streams.Stream_Element_Offset;
               Out_Last : Ada.Streams.Stream_Element_Offset;
               Hit      : Boolean := False;
            begin
               Zlib.Deflate_Init (Filter, Header => Header, Mode => Mode);
               begin
                  Zlib.Compress (Filter, Input, In_Last, Output, Out_Last, Flush => Zlib.Finish);
               exception
                  when Zlib.Zlib_Error =>
                     Hit := True;
               end;

               Assert (not Hit, "supported compression matrix entry must not fail on use");

               Zlib.Compress_Close (Filter, Ignore_Error => True);
            end;
         end loop;
      end loop;
   end Test_Header_Mode_Matrix;

   procedure Test_Ended_Compress_Rules
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Compression_Filter_Type;
      Empty    : constant Ada.Streams.Stream_Element_Array (1 .. 0) := [];
      Input    : constant Ada.Streams.Stream_Element_Array (1 .. 1) := [1 => 1];
      Output   : Ada.Streams.Stream_Element_Array (1 .. 4);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
      procedure Input_After_End is
      begin
         Zlib.Compress (Filter, Input, In_Last, Output, Out_Last);
      end Input_After_End;
   begin
      Zlib.Deflate_Init (Filter);
      Finish_Filter (Filter);
      Zlib.Compress (Filter, Empty, In_Last, Output, Out_Last);
      Assert (In_Last = Before_First (Empty), "Compress after end with no input reports no consumption");
      Assert (Produced (Output, Out_Last) = 0, "Compress after end with no input emits no output");

      Expect_Status_Error ("Compress with input after stream end", Input_After_End'Access);
      Zlib.Compress_Close (Filter);
   end Test_Ended_Compress_Rules;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_Deflate_Init_Reset_States'Access,
         "Deflate_Init resets unopened/open/incomplete/completed/closed states");
      Registration.Register_Routine
        (T, Test_Is_Open_Incomplete_Until_Close'Access,
         "Is_Open remains true until incomplete filters are closed");
      Registration.Register_Routine
        (T, Test_Lifecycle_Misuse_Raises'Access,
         "Compress and Compress_Flush lifecycle misuse raises Status_Error");
      Registration.Register_Routine
        (T, Test_Incomplete_State_Behavior'Access,
         "incomplete compression filters close with deterministic errors");
      Registration.Register_Routine (T, Test_Close_Rules'Access, "Compress_Close open/closed/failed/completed rules");
      Registration.Register_Routine
        (T, Test_Header_Mode_Matrix'Access,
         "Header_Type x Compression_Mode compression support matrix");
      Registration.Register_Routine (T, Test_Ended_Compress_Rules'Access, "Compress after stream end is deterministic");
   end Register_Tests;

end Zlib_Streaming_Compress_Lifecycle_Tests;
