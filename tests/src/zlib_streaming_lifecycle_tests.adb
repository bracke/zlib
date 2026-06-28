with Ada.Streams;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib; use Zlib;

package body Zlib_Streaming_Lifecycle_Tests is
   use type Ada.Streams.Stream_Element_Offset;

   Payload : constant Zlib.Byte_Array :=
     [1 => Zlib.Byte (Character'Pos ('o')),
      2 => Zlib.Byte (Character'Pos ('k'))];

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib streaming lifecycle and bounds");
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

   procedure Fill
     (Input : Zlib.Byte_Array;
      Data  : out Ada.Streams.Stream_Element_Array)
   is
   begin
      for I in Input'Range loop
         Data (Data'First + Ada.Streams.Stream_Element_Offset (I - Input'First)) :=
           Ada.Streams.Stream_Element (Input (I));
      end loop;
   end Fill;

   procedure Decode_To_End
     (Input : Zlib.Byte_Array;
      Filter : in out Zlib.Filter_Type)
   is
      Pos : Natural := Input'First;
   begin
      for Guard in 1 .. 10_000 loop
         declare
            Count : constant Natural :=
              (if Pos <= Input'Last then Natural'Min (5, Input'Last - Pos + 1) else 0);
            In_Data : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Count));
            Out_Data : Ada.Streams.Stream_Element_Array (1 .. 2);
            In_Last  : Ada.Streams.Stream_Element_Offset;
            Out_Last : Ada.Streams.Stream_Element_Offset;
         begin
            if Count > 0 then
               for I in 0 .. Count - 1 loop
                  In_Data (Ada.Streams.Stream_Element_Offset (I + 1)) :=
                    Ada.Streams.Stream_Element (Input (Pos + I));
               end loop;
            end if;

            Zlib.Translate
              (Filter,
               In_Data,
               In_Last,
               Out_Data,
               Out_Last,
               (if Count = 0 or else Pos + Count - 1 >= Input'Last
                then Zlib.Finish
                else Zlib.No_Flush));
            if Count > 0 and then In_Last /= Before_First (In_Data) then
               Pos := Pos + Natural (In_Last - In_Data'First + 1);
            end if;
            exit when Zlib.Stream_End (Filter);
         end;
      end loop;
      Assert (Zlib.Stream_End (Filter), "helper must finish complete zlib stream");
   end Decode_To_End;

   procedure Test_Inflate_Init_Resets_Open_Filter
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Filter_Type;
      Partial  : constant Ada.Streams.Stream_Element_Array (1 .. 1) := [1 => 16#78#];
      Out_Data : Ada.Streams.Stream_Element_Array (1 .. 4);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Status   : Zlib.Status_Code;
      Full     : constant Zlib.Byte_Array := Zlib.Deflate_Stored (Payload, Status);
   begin
      Assert (Status = Zlib.Ok, "test zlib stream must be generated successfully");
      Zlib.Inflate_Init (Filter);
      Zlib.Translate (Filter, Partial, In_Last, Out_Data, Out_Last);
      Assert (Zlib.Is_Open (Filter), "filter must be open after partial input");

      Zlib.Inflate_Init (Filter);
      Assert (Zlib.Is_Open (Filter), "Inflate_Init must reinitialize an open filter");
      Assert (not Zlib.Stream_End (Filter), "Inflate_Init must clear Stream_End");
      Decode_To_End (Full, Filter);
      Zlib.Close (Filter);
   end Test_Inflate_Init_Resets_Open_Filter;

   procedure Test_Close_Incomplete_Raises_And_Closes
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter : Zlib.Filter_Type;
      Raised : Boolean := False;
   begin
      Zlib.Inflate_Init (Filter);
      begin
         Zlib.Close (Filter);
      exception
         when Zlib.Zlib_Error =>
            Raised := True;
      end;
      Assert (Raised, "Close incomplete must raise Zlib_Error when not ignored");
      Assert (not Zlib.Is_Open (Filter), "Close incomplete must clear state even when it raises");
   end Test_Close_Incomplete_Raises_And_Closes;

   procedure Test_Close_Incomplete_Ignore_Succeeds
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter : Zlib.Filter_Type;
   begin
      Zlib.Inflate_Init (Filter);
      Zlib.Close (Filter, Ignore_Error => True);
      Assert (not Zlib.Is_Open (Filter), "ignored incomplete close must close filter");
   end Test_Close_Incomplete_Ignore_Succeeds;

   procedure Test_Close_After_Stream_End_Succeeds
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter : Zlib.Filter_Type;
      Status : Zlib.Status_Code;
      Full   : constant Zlib.Byte_Array := Zlib.Deflate_Stored (Payload, Status);
   begin
      Assert (Status = Zlib.Ok, "test zlib stream must be generated successfully");
      Zlib.Inflate_Init (Filter);
      Decode_To_End (Full, Filter);
      Zlib.Close (Filter);
      Assert (not Zlib.Is_Open (Filter), "Close after Stream_End must close filter");
   end Test_Close_After_Stream_End_Succeeds;

   procedure Test_Malformed_Failed_Close_Behavior
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Filter_Type;
      Bad      : constant Ada.Streams.Stream_Element_Array (1 .. 2) := [1 => 0, 2 => 0];
      Out_Data : Ada.Streams.Stream_Element_Array (1 .. 4);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Raised   : Boolean := False;
   begin
      Zlib.Inflate_Init (Filter);
      begin
         Zlib.Translate (Filter, Bad, In_Last, Out_Data, Out_Last, Zlib.Finish);
      exception
         when Zlib.Zlib_Error =>
            Raised := True;
      end;
      Assert (Raised, "malformed compressed data must raise Zlib_Error");
      Assert (Zlib.Is_Open (Filter), "failed filter remains open for explicit cleanup");

      Raised := False;
      begin
         Zlib.Flush (Filter, Out_Data, Out_Last);
      exception
         when Zlib.Zlib_Error =>
            Raised := True;
      end;
      Assert (Raised, "Flush on failed filter must raise Zlib_Error");

      Raised := False;
      begin
         Zlib.Close (Filter);
      exception
         when Zlib.Zlib_Error =>
            Raised := True;
      end;
      Assert (Raised, "Close failed with Ignore_Error=False must raise Zlib_Error");
      Assert (not Zlib.Is_Open (Filter), "Close failed must still clear state");

      Zlib.Inflate_Init (Filter);
      begin
         Zlib.Translate (Filter, Bad, In_Last, Out_Data, Out_Last, Zlib.Finish);
      exception
         when Zlib.Zlib_Error =>
            null;
      end;
      Zlib.Close (Filter, Ignore_Error => True);
      Assert (not Zlib.Is_Open (Filter), "Close failed with Ignore_Error=True must close silently");
   end Test_Malformed_Failed_Close_Behavior;

   procedure Test_Non_One_Based_Bounds
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status   : Zlib.Status_Code;
      Full     : constant Zlib.Byte_Array := Zlib.Deflate_Stored (Payload, Status);
      Filter   : Zlib.Filter_Type;
      In_Data  : Ada.Streams.Stream_Element_Array (10 .. 9 + Ada.Streams.Stream_Element_Offset (Full'Length));
      Out_Data : Ada.Streams.Stream_Element_Array (20 .. 23);
      In_Last  : Ada.Streams.Stream_Element_Offset := 99;
      Out_Last : Ada.Streams.Stream_Element_Offset := 99;
   begin
      Assert (Status = Zlib.Ok, "test zlib stream must be generated successfully");
      Fill (Full, In_Data);
      Zlib.Inflate_Init (Filter);
      Zlib.Translate (Filter, In_Data, In_Last, Out_Data, Out_Last);
      Assert (In_Last >= Before_First (In_Data), "In_Last must use input bounds");
      Assert (Out_Last >= Before_First (Out_Data), "Out_Last must use output bounds");
      Zlib.Close (Filter, Ignore_Error => True);
   end Test_Non_One_Based_Bounds;

   procedure Test_Null_Input_Array
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Filter_Type;
      In_Data  : constant Ada.Streams.Stream_Element_Array (5 .. 4) := [];
      Out_Data : Ada.Streams.Stream_Element_Array (9 .. 10);
      In_Last  : Ada.Streams.Stream_Element_Offset := 99;
      Out_Last : Ada.Streams.Stream_Element_Offset := 99;
   begin
      Zlib.Inflate_Init (Filter);
      Zlib.Translate (Filter, In_Data, In_Last, Out_Data, Out_Last);
      Assert (Out_Last = 8, "no output marker must be Out_Data'First - 1");
      Zlib.Close (Filter, Ignore_Error => True);
   end Test_Null_Input_Array;

   procedure Test_Null_Output_Array
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Filter_Type;
      In_Data  : constant Ada.Streams.Stream_Element_Array (1 .. 0) := [];
      Out_Data : Ada.Streams.Stream_Element_Array (5 .. 4);
      In_Last  : Ada.Streams.Stream_Element_Offset := 99;
      Out_Last : Ada.Streams.Stream_Element_Offset := 99;
   begin
      Zlib.Inflate_Init (Filter);
      Zlib.Translate (Filter, In_Data, In_Last, Out_Data, Out_Last);
      Assert (In_Last = 1, "null input marker must be Data'First");
      Zlib.Close (Filter, Ignore_Error => True);
   end Test_Null_Output_Array;

   procedure Test_Flush_Null_Output_Array
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Filter_Type;
      Out_Data : Ada.Streams.Stream_Element_Array (5 .. 4);
      Out_Last : Ada.Streams.Stream_Element_Offset := 99;
   begin
      Zlib.Inflate_Init (Filter);
      Zlib.Flush (Filter, Out_Data, Out_Last);
      Assert (Out_Last = 5, "Flush null output marker must be Data'First");
      Zlib.Close (Filter, Ignore_Error => True);
   end Test_Flush_Null_Output_Array;

   procedure Test_Translate_Finish_Null_Output_Incomplete_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Filter_Type;
      In_Data  : constant Ada.Streams.Stream_Element_Array (1 .. 0) := [];
      Out_Data : Ada.Streams.Stream_Element_Array (5 .. 4);
      In_Last  : Ada.Streams.Stream_Element_Offset := 99;
      Out_Last : Ada.Streams.Stream_Element_Offset := 99;
      Raised   : Boolean := False;
   begin
      Zlib.Inflate_Init (Filter);

      begin
         Zlib.Translate (Filter, In_Data, In_Last, Out_Data, Out_Last, Zlib.Finish);
      exception
         when Zlib.Zlib_Error =>
            Raised := True;
      end;

      Assert (Raised, "Translate Finish with null output before stream end must raise Zlib_Error");
      Assert (Zlib.Is_Open (Filter), "failed null-output Finish filter remains open until Close");
      Zlib.Close (Filter, Ignore_Error => True);
   end Test_Translate_Finish_Null_Output_Incomplete_Raises;

   procedure Test_Flush_Finish_Null_Output_Incomplete_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Filter_Type;
      Out_Data : Ada.Streams.Stream_Element_Array (5 .. 4);
      Out_Last : Ada.Streams.Stream_Element_Offset := 99;
      Raised   : Boolean := False;
   begin
      Zlib.Inflate_Init (Filter);

      begin
         Zlib.Flush (Filter, Out_Data, Out_Last, Zlib.Finish);
      exception
         when Zlib.Zlib_Error =>
            Raised := True;
      end;

      Assert (Raised, "Flush Finish with null output before stream end must raise Zlib_Error");
      Assert (Zlib.Is_Open (Filter), "failed null-output Flush Finish filter remains open until Close");
      Zlib.Close (Filter, Ignore_Error => True);
   end Test_Flush_Finish_Null_Output_Incomplete_Raises;

   procedure Test_Basic_Open_Close_State
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter : Zlib.Filter_Type;
   begin
      Assert (not Zlib.Is_Open (Filter), "fresh filter must not be open before Inflate_Init");
      Zlib.Inflate_Init (Filter);
      Assert (Zlib.Is_Open (Filter), "Inflate_Init must open the filter");
      Zlib.Close (Filter, Ignore_Error => True);
      Assert (not Zlib.Is_Open (Filter), "Close must leave Is_Open False");
   end Test_Basic_Open_Close_State;

   procedure Test_Translate_Before_Init_Raises_Status_Error
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Filter_Type;
      In_Data  : constant Ada.Streams.Stream_Element_Array (1 .. 1) := [1 => 16#78#];
      Out_Data : Ada.Streams.Stream_Element_Array (1 .. 1);
      In_Last  : Ada.Streams.Stream_Element_Offset := 99;
      Out_Last : Ada.Streams.Stream_Element_Offset := 99;
      Raised   : Boolean := False;
   begin
      begin
         Zlib.Translate (Filter, In_Data, In_Last, Out_Data, Out_Last);
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
      In_Data  : constant Ada.Streams.Stream_Element_Array (1 .. 1) := [1 => 16#78#];
      Out_Data : Ada.Streams.Stream_Element_Array (1 .. 1);
      In_Last  : Ada.Streams.Stream_Element_Offset := 99;
      Out_Last : Ada.Streams.Stream_Element_Offset := 99;
      Raised   : Boolean := False;
   begin
      Zlib.Inflate_Init (Filter);
      Zlib.Close (Filter, Ignore_Error => True);

      begin
         Zlib.Translate (Filter, In_Data, In_Last, Out_Data, Out_Last);
      exception
         when Zlib.Status_Error =>
            Raised := True;
      end;

      Assert (Raised, "Translate after Close must raise Status_Error");
   end Test_Translate_After_Close_Raises_Status_Error;

   procedure Test_Flush_Before_Init_Raises_Status_Error
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Filter_Type;
      Out_Data : Ada.Streams.Stream_Element_Array (5 .. 6);
      Out_Last : Ada.Streams.Stream_Element_Offset := 99;
      Raised   : Boolean := False;
   begin
      begin
         Zlib.Flush (Filter, Out_Data, Out_Last);
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
      Out_Data : Ada.Streams.Stream_Element_Array (5 .. 6);
      Out_Last : Ada.Streams.Stream_Element_Offset := 99;
      Raised   : Boolean := False;
   begin
      Zlib.Inflate_Init (Filter);
      Zlib.Close (Filter, Ignore_Error => True);

      begin
         Zlib.Flush (Filter, Out_Data, Out_Last);
      exception
         when Zlib.Status_Error =>
            Raised := True;
      end;

      Assert (Raised, "Flush after Close must raise Status_Error");
   end Test_Flush_After_Close_Raises_Status_Error;

   procedure Test_Close_Unopened_Behavior
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

      Assert (Raised, "Close unopened Ignore_Error=False must raise Status_Error");
      Zlib.Close (Filter, Ignore_Error => True);
      Assert (not Zlib.Is_Open (Filter), "Close unopened Ignore_Error=True must be a no-op");
   end Test_Close_Unopened_Behavior;

   procedure Test_Translate_On_Failed_Raises_Zlib_Error
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Filter_Type;
      Bad      : constant Ada.Streams.Stream_Element_Array (1 .. 2) := [1 => 0, 2 => 0];
      Out_Data : Ada.Streams.Stream_Element_Array (1 .. 4);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Raised   : Boolean := False;
   begin
      Zlib.Inflate_Init (Filter);
      begin
         Zlib.Translate (Filter, Bad, In_Last, Out_Data, Out_Last, Zlib.Finish);
      exception
         when Zlib.Zlib_Error =>
            null;
      end;

      begin
         Zlib.Translate (Filter, Bad, In_Last, Out_Data, Out_Last);
      exception
         when Zlib.Zlib_Error =>
            Raised := True;
      end;

      Assert (Raised, "Translate on Failed filter must raise Zlib_Error");
      Zlib.Close (Filter, Ignore_Error => True);
   end Test_Translate_On_Failed_Raises_Zlib_Error;

   procedure Test_Output_Full_No_Input_Consumed
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status   : Zlib.Status_Code;
      Full     : constant Zlib.Byte_Array := Zlib.Deflate_Stored (Payload, Status);
      Filter   : Zlib.Filter_Type;
      In_Data  : Ada.Streams.Stream_Element_Array (11 .. 10 + Ada.Streams.Stream_Element_Offset (Full'Length));
      Out_One  : Ada.Streams.Stream_Element_Array (21 .. 21);
      Out_Null : Ada.Streams.Stream_Element_Array (31 .. 30);
      In_Last  : Ada.Streams.Stream_Element_Offset := 99;
      Out_Last : Ada.Streams.Stream_Element_Offset := 99;
   begin
      Assert (Status = Zlib.Ok, "test zlib stream must be generated successfully");
      Fill (Full, In_Data);
      Zlib.Inflate_Init (Filter);

      for Guard in 1 .. 10_000 loop
         Zlib.Translate (Filter, In_Data, In_Last, Out_One, Out_Last);
         exit when Out_Last = Out_One'Last;
      end loop;

      Assert (Out_Last = Out_One'Last, "single-byte output buffer must fill during test setup");

      declare
         Previous_In_Last : constant Ada.Streams.Stream_Element_Offset := In_Last;
      begin
         Zlib.Translate (Filter, In_Data, In_Last, Out_Null, Out_Last);
         Assert (In_Last = Before_First (In_Data),
                 "null output call must report no input consumed for that call");
         Assert (Out_Last = Out_Null'First,
                 "null output call must report no output produced");
         Assert (Previous_In_Last >= Before_First (In_Data),
                 "setup must have consumed zero or more input bytes deterministically");
      end;

      Zlib.Close (Filter, Ignore_Error => True);
   end Test_Output_Full_No_Input_Consumed;
   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine (T, Test_Basic_Open_Close_State'Access,
                                     "Inflate_Init opens and Close clears Is_Open");
      Registration.Register_Routine (T, Test_Translate_Before_Init_Raises_Status_Error'Access,
                                     "Translate before init raises Status_Error");
      Registration.Register_Routine (T, Test_Translate_After_Close_Raises_Status_Error'Access,
                                     "Translate after Close raises Status_Error");
      Registration.Register_Routine (T, Test_Flush_Before_Init_Raises_Status_Error'Access,
                                     "Flush before init raises Status_Error");
      Registration.Register_Routine (T, Test_Flush_After_Close_Raises_Status_Error'Access,
                                     "Flush after Close raises Status_Error");
      Registration.Register_Routine (T, Test_Close_Unopened_Behavior'Access,
                                     "Close unopened honors Ignore_Error");
      Registration.Register_Routine (T, Test_Translate_On_Failed_Raises_Zlib_Error'Access,
                                     "Translate on failed filter raises Zlib_Error");
      Registration.Register_Routine (T, Test_Output_Full_No_Input_Consumed'Access,
                                     "no-capacity Translate reports no input consumed");
      Registration.Register_Routine (T, Test_Inflate_Init_Resets_Open_Filter'Access,
                                     "Inflate_Init resets an already open filter");
      Registration.Register_Routine (T, Test_Close_Incomplete_Raises_And_Closes'Access,
                                     "Close incomplete raises Zlib_Error and closes");
      Registration.Register_Routine (T, Test_Close_Incomplete_Ignore_Succeeds'Access,
                                     "Close incomplete Ignore_Error=True succeeds");
      Registration.Register_Routine (T, Test_Close_After_Stream_End_Succeeds'Access,
                                     "Close after valid Stream_End succeeds");
      Registration.Register_Routine (T, Test_Malformed_Failed_Close_Behavior'Access,
                                     "malformed stream failed-state close behavior");
      Registration.Register_Routine (T, Test_Non_One_Based_Bounds'Access,
                                     "Translate handles non-1-based input/output bounds");
      Registration.Register_Routine (T, Test_Null_Input_Array'Access,
                                     "Translate handles null input array");
      Registration.Register_Routine (T, Test_Null_Output_Array'Access,
                                     "Translate handles null output array");
      Registration.Register_Routine (T, Test_Flush_Null_Output_Array'Access,
                                     "Flush handles null output array");
      Registration.Register_Routine (T, Test_Translate_Finish_Null_Output_Incomplete_Raises'Access,
                                     "Translate Finish null output before end raises Zlib_Error");
      Registration.Register_Routine (T, Test_Flush_Finish_Null_Output_Incomplete_Raises'Access,
                                     "Flush Finish null output before end raises Zlib_Error");
   end Register_Tests;
end Zlib_Streaming_Lifecycle_Tests;
