with Ada.Streams;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;

package body Zlib_Streaming_Compression_Api_Tests is
   use type Ada.Streams.Stream_Element_Offset;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib streaming compression API lifecycle");
   end Name;

   procedure Expect_Status_Error
     (Label : String;
      Test  : not null access procedure;
      Hit   : out Boolean)
   is
   begin
      Hit := False;
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
      Test  : not null access procedure;
      Hit   : out Boolean)
   is
   begin
      Hit := False;
      begin
         Test.all;
      exception
         when Zlib.Zlib_Error =>
            Hit := True;
      end;
      Assert (Hit, Label & " must raise Zlib_Error");
   end Expect_Zlib_Error;

   procedure Test_Deflate_Init_Opens_Filter
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter : Zlib.Compression_Filter_Type;
   begin
      Zlib.Deflate_Init (Filter);
      Assert (Zlib.Is_Open (Filter), "Deflate_Init must open compression filter");
      Zlib.Compress_Close (Filter, Ignore_Error => True);
   end Test_Deflate_Init_Opens_Filter;

   procedure Test_Deflate_Init_Resets_Filter
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Compression_Filter_Type;
      Input    : constant Ada.Streams.Stream_Element_Array (1 .. 1) := [1 => 42];
      Output   : Ada.Streams.Stream_Element_Array (1 .. 1);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
   begin
      Zlib.Deflate_Init (Filter, Header => Zlib.GZip, Mode => Zlib.Fixed);
      begin
         Zlib.Compress (Filter, Input, In_Last, Output, Out_Last);
      exception
         when Zlib.Zlib_Error =>
            null;
      end;

      Assert (Zlib.Is_Open (Filter), "failed compression filter must remain open");
      Zlib.Deflate_Init (Filter, Header => Zlib.Raw_Deflate, Mode => Zlib.Dynamic);
      Assert (Zlib.Is_Open (Filter), "Deflate_Init must reset an already-open compression filter");
      Zlib.Compress_Close (Filter, Ignore_Error => True);
   end Test_Deflate_Init_Resets_Filter;

   procedure Test_Deflate_Init_Resets_Open_Filter
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter : Zlib.Compression_Filter_Type;
   begin
      Zlib.Deflate_Init (Filter, Header => Zlib.GZip, Mode => Zlib.Fixed);
      Assert (Zlib.Is_Open (Filter), "first Deflate_Init must open filter");

      Zlib.Deflate_Init (Filter, Header => Zlib.Raw_Deflate, Mode => Zlib.Dynamic);
      Assert (Zlib.Is_Open (Filter), "second Deflate_Init must reset open filter");
      Zlib.Compress_Close (Filter, Ignore_Error => True);
   end Test_Deflate_Init_Resets_Open_Filter;

   procedure Test_Is_Open_Lifecycle
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter : Zlib.Compression_Filter_Type;
   begin
      Assert (not Zlib.Is_Open (Filter), "compression Is_Open must be false before init");
      Zlib.Deflate_Init (Filter);
      Assert (Zlib.Is_Open (Filter), "compression Is_Open must be true after init");
      Zlib.Compress_Close (Filter, Ignore_Error => True);
      Assert (not Zlib.Is_Open (Filter), "compression Is_Open must be false after close");
   end Test_Is_Open_Lifecycle;

   procedure Test_Compress_Before_Init_Raises_Status_Error
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Compression_Filter_Type;
      Input    : constant Ada.Streams.Stream_Element_Array (10 .. 12) := [10 => 1, 11 => 2, 12 => 3];
      Output   : Ada.Streams.Stream_Element_Array (20 .. 21);
      In_Last  : Ada.Streams.Stream_Element_Offset := 99;
      Out_Last : Ada.Streams.Stream_Element_Offset := 99;
      Raised   : Boolean;
      procedure Call is
      begin
         Zlib.Compress (Filter, Input, In_Last, Output, Out_Last);
      end Call;
   begin
      Expect_Status_Error ("Compress before Deflate_Init", Call'Access, Raised);
   end Test_Compress_Before_Init_Raises_Status_Error;

   procedure Test_Compress_After_Close_Raises_Status_Error
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Compression_Filter_Type;
      Input    : constant Ada.Streams.Stream_Element_Array (10 .. 12) := [10 => 1, 11 => 2, 12 => 3];
      Output   : Ada.Streams.Stream_Element_Array (1 .. 1);
      In_Last  : Ada.Streams.Stream_Element_Offset := 99;
      Out_Last : Ada.Streams.Stream_Element_Offset := 99;
      Raised   : Boolean;
      procedure Call is
      begin
         Zlib.Compress (Filter, Input, In_Last, Output, Out_Last);
      end Call;
   begin
      Zlib.Deflate_Init (Filter);
      Zlib.Compress_Close (Filter, Ignore_Error => True);
      Expect_Status_Error ("Compress after Compress_Close", Call'Access, Raised);
   end Test_Compress_After_Close_Raises_Status_Error;

   procedure Test_Compress_Failed_State_Raises_Zlib_Error
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Compression_Filter_Type;
      Input    : constant Ada.Streams.Stream_Element_Array (1 .. 1) := [1 => 0];
      Output   : Ada.Streams.Stream_Element_Array (1 .. 1);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Raised   : Boolean;
      procedure Call is
      begin
         Zlib.Compress (Filter, Input, In_Last, Output, Out_Last);
      end Call;
   begin
      declare
         Metadata : Zlib.GZip_Metadata := Zlib.No_GZip_Metadata;
      begin
         Zlib.Set_Name (Metadata, Character'Val (0) & "bad");
         begin
            Zlib.Deflate_Init
              (Filter, Header => Zlib.GZip, Mode => Zlib.Auto, Metadata => Metadata);
         exception
            when Zlib.Status_Error =>
               null;
         end;
      end;
      Expect_Zlib_Error ("Compress after failed state", Call'Access, Raised);
      Zlib.Compress_Close (Filter, Ignore_Error => True);
   end Test_Compress_Failed_State_Raises_Zlib_Error;

   procedure Test_Compress_Flush_Failed_State_Raises_Zlib_Error
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Compression_Filter_Type;
      Output   : Ada.Streams.Stream_Element_Array (1 .. 1);
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Raised   : Boolean;
      procedure Call is
      begin
         Zlib.Compress_Flush (Filter, Output, Out_Last);
      end Call;
   begin
      declare
         Metadata : Zlib.GZip_Metadata := Zlib.No_GZip_Metadata;
      begin
         Zlib.Set_Name (Metadata, Character'Val (0) & "bad");
         begin
            Zlib.Deflate_Init
              (Filter, Header => Zlib.GZip, Mode => Zlib.Auto, Metadata => Metadata);
         exception
            when Zlib.Status_Error =>
               null;
         end;
      end;
      Expect_Zlib_Error ("Compress_Flush after failed state", Call'Access, Raised);
      Zlib.Compress_Close (Filter, Ignore_Error => True);
   end Test_Compress_Flush_Failed_State_Raises_Zlib_Error;

   procedure Test_Compress_Flush_Before_Init_Raises_Status_Error
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Compression_Filter_Type;
      Output   : Ada.Streams.Stream_Element_Array (5 .. 6);
      Out_Last : Ada.Streams.Stream_Element_Offset := 99;
      Raised   : Boolean;
      procedure Call is
      begin
         Zlib.Compress_Flush (Filter, Output, Out_Last);
      end Call;
   begin
      Expect_Status_Error ("Compress_Flush before Deflate_Init", Call'Access, Raised);
   end Test_Compress_Flush_Before_Init_Raises_Status_Error;

   procedure Test_Compress_Flush_After_Close_Raises_Status_Error
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Compression_Filter_Type;
      Output   : Ada.Streams.Stream_Element_Array (8 .. 9);
      Out_Last : Ada.Streams.Stream_Element_Offset := 99;
      Raised   : Boolean;
      procedure Call is
      begin
         Zlib.Compress_Flush (Filter, Output, Out_Last);
      end Call;
   begin
      Zlib.Deflate_Init (Filter);
      Zlib.Compress_Close (Filter, Ignore_Error => True);
      Expect_Status_Error ("Compress_Flush after Compress_Close", Call'Access, Raised);
   end Test_Compress_Flush_After_Close_Raises_Status_Error;

   procedure Test_Compress_Stream_End_Is_False
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter : Zlib.Compression_Filter_Type;
   begin
      Assert (not Zlib.Compress_Stream_End (Filter), "Compress_Stream_End must be false before init");
      Zlib.Deflate_Init (Filter);
      Assert (not Zlib.Compress_Stream_End (Filter), "Compress_Stream_End must be false after init");
      Zlib.Compress_Close (Filter, Ignore_Error => True);
      Assert (not Zlib.Compress_Stream_End (Filter), "Compress_Stream_End must be false after close");
   end Test_Compress_Stream_End_Is_False;

   procedure Test_Compress_Close_Unopened_Rules
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter : Zlib.Compression_Filter_Type;
      Raised : Boolean;
      procedure Call is
      begin
         Zlib.Compress_Close (Filter);
      end Call;
   begin
      Expect_Status_Error ("Compress_Close unopened Ignore_Error=False", Call'Access, Raised);
      Zlib.Compress_Close (Filter, Ignore_Error => True);
      Assert (not Zlib.Is_Open (Filter), "ignored Compress_Close on unopened filter must leave it closed");
   end Test_Compress_Close_Unopened_Rules;

   procedure Test_Compress_Close_Open_Incomplete_Rules
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter : Zlib.Compression_Filter_Type;
      Raised : Boolean;
      procedure Call is
      begin
         Zlib.Compress_Close (Filter);
      end Call;
   begin
      Zlib.Deflate_Init (Filter);
      Expect_Zlib_Error ("Compress_Close open incomplete Ignore_Error=False", Call'Access, Raised);
      Assert (not Zlib.Is_Open (Filter), "failing Compress_Close must still close the filter");

      Zlib.Deflate_Init (Filter);
      Zlib.Compress_Close (Filter, Ignore_Error => True);
      Assert (not Zlib.Is_Open (Filter), "Compress_Close open incomplete Ignore_Error=True must close");
   end Test_Compress_Close_Open_Incomplete_Rules;

   procedure Expect_Deflate_Init_Accepts_Header
     (Header : Zlib.Header_Type;
      Label  : String)
   is
      Filter : Zlib.Compression_Filter_Type;
   begin
      Zlib.Deflate_Init (Filter, Header => Header);
      Assert (Zlib.Is_Open (Filter), "Deflate_Init must accept Header => " & Label);
      Zlib.Compress_Close (Filter, Ignore_Error => True);
   end Expect_Deflate_Init_Accepts_Header;

   procedure Expect_Deflate_Init_Accepts_Mode
     (Mode  : Zlib.Compression_Mode;
      Label : String)
   is
      Filter : Zlib.Compression_Filter_Type;
   begin
      Zlib.Deflate_Init (Filter, Mode => Mode);
      Assert (Zlib.Is_Open (Filter), "Deflate_Init must accept Mode => " & Label);
      Zlib.Compress_Close (Filter, Ignore_Error => True);
   end Expect_Deflate_Init_Accepts_Mode;

   procedure Test_Deflate_Init_Accepts_Header_Default
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Expect_Deflate_Init_Accepts_Header (Zlib.Default, "Default");
   end Test_Deflate_Init_Accepts_Header_Default;

   procedure Test_Deflate_Init_Accepts_Header_Zlib
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Expect_Deflate_Init_Accepts_Header (Zlib.Zlib_Header, "Zlib_Header");
   end Test_Deflate_Init_Accepts_Header_Zlib;

   procedure Test_Deflate_Init_Accepts_Header_GZip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Expect_Deflate_Init_Accepts_Header (Zlib.GZip, "GZip");
   end Test_Deflate_Init_Accepts_Header_GZip;

   procedure Test_Deflate_Init_Accepts_Header_Raw_Deflate
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Expect_Deflate_Init_Accepts_Header (Zlib.Raw_Deflate, "Raw_Deflate");
   end Test_Deflate_Init_Accepts_Header_Raw_Deflate;

   procedure Test_Deflate_Init_Accepts_Mode_Stored
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Expect_Deflate_Init_Accepts_Mode (Zlib.Stored, "Stored");
   end Test_Deflate_Init_Accepts_Mode_Stored;

   procedure Test_Deflate_Init_Accepts_Mode_Fixed
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Expect_Deflate_Init_Accepts_Mode (Zlib.Fixed, "Fixed");
   end Test_Deflate_Init_Accepts_Mode_Fixed;

   procedure Test_Deflate_Init_Accepts_Mode_Dynamic
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Expect_Deflate_Init_Accepts_Mode (Zlib.Dynamic, "Dynamic");
   end Test_Deflate_Init_Accepts_Mode_Dynamic;

   procedure Test_Deflate_Init_Accepts_Mode_Auto
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Expect_Deflate_Init_Accepts_Mode (Zlib.Auto, "Auto");
   end Test_Deflate_Init_Accepts_Mode_Auto;

   procedure Test_Null_Array_Markers
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Compression_Filter_Type;
      Input    : constant Ada.Streams.Stream_Element_Array (1 .. 0) := [];
      Output   : Ada.Streams.Stream_Element_Array (5 .. 4);
      In_Last  : Ada.Streams.Stream_Element_Offset := 99;
      Out_Last : Ada.Streams.Stream_Element_Offset := 99;
   begin
      Zlib.Deflate_Init (Filter);
      Zlib.Compress (Filter, Input, In_Last, Output, Out_Last);
      Assert (not Zlib.Compress_Stream_End (Filter), "null arrays without Finish must not end stream");
      Zlib.Compress_Close (Filter, Ignore_Error => True);
   end Test_Null_Array_Markers;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine (T, Test_Deflate_Init_Opens_Filter'Access, "Deflate_Init opens compression filter");
      Registration.Register_Routine
        (T, Test_Deflate_Init_Resets_Filter'Access,
         "Deflate_Init resets failed compression filter");
      Registration.Register_Routine
        (T, Test_Deflate_Init_Resets_Open_Filter'Access,
         "Deflate_Init resets already-open compression filter");
      Registration.Register_Routine (T, Test_Is_Open_Lifecycle'Access, "compression Is_Open lifecycle");
      Registration.Register_Routine
        (T, Test_Compress_Before_Init_Raises_Status_Error'Access,
         "Compress before init raises Status_Error");
      Registration.Register_Routine
        (T, Test_Compress_After_Close_Raises_Status_Error'Access,
         "Compress after close raises Status_Error");
      Registration.Register_Routine
        (T, Test_Compress_Failed_State_Raises_Zlib_Error'Access,
         "Compress after failed state raises Zlib_Error");
      Registration.Register_Routine
        (T, Test_Compress_Flush_Failed_State_Raises_Zlib_Error'Access,
         "Compress_Flush after failed state raises Zlib_Error");
      Registration.Register_Routine
        (T, Test_Compress_Flush_Before_Init_Raises_Status_Error'Access,
         "Compress_Flush before init raises Status_Error");
      Registration.Register_Routine
        (T, Test_Compress_Flush_After_Close_Raises_Status_Error'Access,
         "Compress_Flush after close raises Status_Error");
      Registration.Register_Routine
        (T, Test_Compress_Stream_End_Is_False'Access,
         "Compress_Stream_End false before init, after init, and after close");
      Registration.Register_Routine (T, Test_Compress_Close_Unopened_Rules'Access, "Compress_Close unopened rules");
      Registration.Register_Routine
        (T, Test_Compress_Close_Open_Incomplete_Rules'Access,
         "Compress_Close open incomplete rules");
      Registration.Register_Routine
        (T, Test_Deflate_Init_Accepts_Header_Default'Access,
         "Deflate_Init accepts Header => Default");
      Registration.Register_Routine
        (T, Test_Deflate_Init_Accepts_Header_Zlib'Access,
         "Deflate_Init accepts Header => Zlib_Header");
      Registration.Register_Routine
        (T, Test_Deflate_Init_Accepts_Header_GZip'Access,
         "Deflate_Init accepts Header => GZip");
      Registration.Register_Routine
        (T, Test_Deflate_Init_Accepts_Header_Raw_Deflate'Access,
         "Deflate_Init accepts Header => Raw_Deflate");
      Registration.Register_Routine
        (T, Test_Deflate_Init_Accepts_Mode_Stored'Access,
         "Deflate_Init accepts Mode => Stored");
      Registration.Register_Routine
        (T, Test_Deflate_Init_Accepts_Mode_Fixed'Access,
         "Deflate_Init accepts Mode => Fixed");
      Registration.Register_Routine
        (T, Test_Deflate_Init_Accepts_Mode_Dynamic'Access,
         "Deflate_Init accepts Mode => Dynamic");
      Registration.Register_Routine
        (T, Test_Deflate_Init_Accepts_Mode_Auto'Access,
         "Deflate_Init accepts Mode => Auto");
      Registration.Register_Routine
        (T, Test_Null_Array_Markers'Access,
         "Compress null arrays use First as no-element marker");
   end Register_Tests;

end Zlib_Streaming_Compression_Api_Tests;
