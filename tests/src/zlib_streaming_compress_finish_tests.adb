with Ada.Containers.Vectors;
with Ada.Streams; use Ada.Streams;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;

package body Zlib_Streaming_Compress_Finish_Tests is
   use type Zlib.Header_Type;
   use type Zlib.Compression_Mode;
   use type Zlib.Byte;
   use type Zlib.Status_Code;

   package Stream_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Ada.Streams.Stream_Element);

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib streaming compression finish hardening");
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

   procedure Append_Output
     (Output : in out Stream_Vectors.Vector;
      Buffer : Ada.Streams.Stream_Element_Array;
      Last   : Ada.Streams.Stream_Element_Offset)
   is
      Count : constant Natural := Produced (Buffer, Last);
   begin
      if Count = 0 then
         return;
      end if;

      for I in Buffer'First .. Buffer'First + Ada.Streams.Stream_Element_Offset (Count) - 1 loop
         Output.Append (Buffer (I));
      end loop;
   end Append_Output;

   function To_Bytes
     (Data : Stream_Vectors.Vector)
      return Zlib.Byte_Array
   is
   begin
      if Data.Is_Empty then
         return [1 .. 0 => 0];
      end if;

      declare
         Result : Zlib.Byte_Array (1 .. Natural (Data.Length));
         Index  : Natural := Result'First;
      begin
         for B of Data loop
            Result (Index) := Zlib.Byte (B);
            Index := Index + 1;
         end loop;
         return Result;
      end;
   end To_Bytes;

   procedure Assert_Empty_Roundtrip
     (Header : Zlib.Header_Type;
      Mode   : Zlib.Compression_Mode;
      Label  : String)
   is
      Filter   : Zlib.Compression_Filter_Type;
      Output   : Stream_Vectors.Vector;
      Buffer   : Ada.Streams.Stream_Element_Array (1 .. 3);
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Calls    : Natural := 0;
      Status   : Zlib.Status_Code;
   begin
      Zlib.Deflate_Init (Filter, Header => Header, Mode => Mode);

      while not Zlib.Compress_Stream_End (Filter) loop
         Zlib.Compress_Flush (Filter, Buffer, Out_Last, Flush => Zlib.Finish);
         Append_Output (Output, Buffer, Out_Last);
         Calls := Calls + 1;
         Assert (Calls < 10_000, Label & " finish must not loop forever");
      end loop;

      declare
         Encoded : constant Zlib.Byte_Array := To_Bytes (Output);
         Decoded : constant Zlib.Byte_Array :=
           Zlib.Inflate_With_Header
             (Encoded,
              (if Header = Zlib.GZip then Zlib.GZip else Zlib.Zlib_Header),
              Status);
      begin
         Assert (Status = Zlib.Ok, Label & " empty stream must inflate");
         Assert (Decoded'Length = 0, Label & " empty stream must decode to empty payload");
      end;

      Zlib.Compress_Close (Filter);
   end Assert_Empty_Roundtrip;

   procedure Test_Finish_Empty_Zlib_Stored
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Empty_Roundtrip (Zlib.Zlib_Header, Zlib.Stored, "zlib stored");
   end Test_Finish_Empty_Zlib_Stored;

   procedure Test_Finish_Empty_Zlib_Fixed
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Empty_Roundtrip (Zlib.Zlib_Header, Zlib.Fixed, "zlib fixed");
   end Test_Finish_Empty_Zlib_Fixed;

   procedure Test_Finish_Empty_Zlib_Dynamic
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Empty_Roundtrip (Zlib.Zlib_Header, Zlib.Dynamic, "zlib dynamic");
   end Test_Finish_Empty_Zlib_Dynamic;

   procedure Test_Finish_Empty_Gzip_Stored
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Empty_Roundtrip (Zlib.GZip, Zlib.Stored, "gzip stored");
   end Test_Finish_Empty_Gzip_Stored;

   procedure Test_Finish_Empty_Gzip_Fixed
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Empty_Roundtrip (Zlib.GZip, Zlib.Fixed, "gzip fixed");
   end Test_Finish_Empty_Gzip_Fixed;

   procedure Test_Finish_Empty_Gzip_Dynamic
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Empty_Roundtrip (Zlib.GZip, Zlib.Dynamic, "gzip dynamic");
   end Test_Finish_Empty_Gzip_Dynamic;

   procedure Test_Stream_End_After_Trailer_Drained
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Compression_Filter_Type;
      Buffer   : Ada.Streams.Stream_Element_Array (1 .. 1);
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Calls    : Natural := 0;
   begin
      Zlib.Deflate_Init (Filter, Header => Zlib.GZip, Mode => Zlib.Stored);
      Zlib.Compress_Flush (Filter, Buffer, Out_Last, Flush => Zlib.Finish);
      Assert
        (not Zlib.Compress_Stream_End (Filter),
         "Compress_Stream_End false while gzip header/body/trailer remains pending");

      while not Zlib.Compress_Stream_End (Filter) loop
         Zlib.Compress_Flush (Filter, Buffer, Out_Last, Flush => Zlib.Finish);
         Calls := Calls + 1;
         Assert (Calls < 10_000, "gzip one-byte finish must complete");
      end loop;

      Assert (Zlib.Compress_Stream_End (Filter), "Compress_Stream_End true after final trailer byte is drained");
      Zlib.Compress_Close (Filter);
   end Test_Stream_End_After_Trailer_Drained;

   procedure Test_Double_Finish_After_End
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Compression_Filter_Type;
      Output   : Ada.Streams.Stream_Element_Array (1 .. 8);
      Out_Last : Ada.Streams.Stream_Element_Offset;
   begin
      Zlib.Deflate_Init (Filter, Header => Zlib.Zlib_Header, Mode => Zlib.Stored);
      while not Zlib.Compress_Stream_End (Filter) loop
         Zlib.Compress_Flush (Filter, Output, Out_Last, Flush => Zlib.Finish);
      end loop;

      Zlib.Compress_Flush (Filter, Output, Out_Last, Flush => Zlib.Finish);
      Assert (Produced (Output, Out_Last) = 0, "double Finish after end must emit no output");
      Zlib.Compress_Close (Filter);
   end Test_Double_Finish_After_End;

   procedure Test_Compress_Input_After_End_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Compression_Filter_Type;
      Input    : constant Ada.Streams.Stream_Element_Array (1 .. 1) := [1 => 1];
      Output   : Ada.Streams.Stream_Element_Array (1 .. 8);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Hit      : Boolean := False;
   begin
      Zlib.Deflate_Init (Filter, Header => Zlib.Zlib_Header, Mode => Zlib.Stored);
      while not Zlib.Compress_Stream_End (Filter) loop
         Zlib.Compress_Flush (Filter, Output, Out_Last, Flush => Zlib.Finish);
      end loop;

      begin
         Zlib.Compress (Filter, Input, In_Last, Output, Out_Last, Flush => Zlib.No_Flush);
      exception
         when Zlib.Status_Error =>
            Hit := True;
      end;
      Assert (Hit, "Compress with input after stream end must raise Status_Error");
      Zlib.Compress_Close (Filter);
   end Test_Compress_Input_After_End_Raises;

   procedure Test_Compress_Finish_Empty_Input
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Compression_Filter_Type;
      Empty    : constant Ada.Streams.Stream_Element_Array (1 .. 0) := [];
      Output   : Stream_Vectors.Vector;
      Buffer   : Ada.Streams.Stream_Element_Array (17 .. 18);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Calls    : Natural := 0;
      Status   : Zlib.Status_Code;
   begin
      Zlib.Deflate_Init (Filter, Header => Zlib.Zlib_Header, Mode => Zlib.Fixed);

      while not Zlib.Compress_Stream_End (Filter) loop
         Zlib.Compress
           (Filter   => Filter,
            In_Data  => Empty,
            In_Last  => In_Last,
            Out_Data => Buffer,
            Out_Last => Out_Last,
            Flush    => Zlib.Finish);
         Append_Output (Output, Buffer, Out_Last);
         Assert (In_Last = Empty'First, "Compress Finish with empty input reports null-array marker");
         Calls := Calls + 1;
         Assert (Calls < 10_000, "Compress Finish with empty input must complete");
      end loop;

      declare
         Encoded : constant Zlib.Byte_Array := To_Bytes (Output);
         Decoded : constant Zlib.Byte_Array :=
           Zlib.Inflate_With_Header (Encoded, Zlib.Zlib_Header, Status);
      begin
         Assert (Status = Zlib.Ok, "Compress Finish empty input must produce valid zlib output");
         Assert (Decoded'Length = 0, "Compress Finish empty input must decode to empty data");
      end;

      Zlib.Compress_Close (Filter);
   end Test_Compress_Finish_Empty_Input;

   procedure Test_Compress_Finish_With_Pending_Input
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter     : Zlib.Compression_Filter_Type;
      Input      : constant Ada.Streams.Stream_Element_Array (41 .. 45) :=
        [41 => 10, 42 => 20, 43 => 30, 44 => 40, 45 => 50];
      Output     : Stream_Vectors.Vector;
      Next_Input : Ada.Streams.Stream_Element_Offset := Input'First;
      Buffer     : Ada.Streams.Stream_Element_Array (101 .. 101);
      In_Last    : Ada.Streams.Stream_Element_Offset;
      Out_Last   : Ada.Streams.Stream_Element_Offset;
      Calls      : Natural := 0;
      Status     : Zlib.Status_Code;
   begin
      Zlib.Deflate_Init (Filter, Header => Zlib.GZip, Mode => Zlib.Dynamic);

      while not Zlib.Compress_Stream_End (Filter) loop
         if Next_Input <= Input'Last then
            Zlib.Compress
              (Filter   => Filter,
               In_Data  => Input (Next_Input .. Input'Last),
               In_Last  => In_Last,
               Out_Data => Buffer,
               Out_Last => Out_Last,
               Flush    => Zlib.Finish);
            if In_Last >= Next_Input then
               Next_Input := In_Last + 1;
            end if;
         else
            Zlib.Compress_Flush
              (Filter   => Filter,
               Out_Data => Buffer,
               Out_Last => Out_Last,
               Flush    => Zlib.Finish);
         end if;

         Append_Output (Output, Buffer, Out_Last);
         Calls := Calls + 1;
         Assert (Calls < 100_000, "Compress Finish with pending input must make bounded progress");
      end loop;

      declare
         Encoded : constant Zlib.Byte_Array := To_Bytes (Output);
         Decoded : constant Zlib.Byte_Array :=
           Zlib.Inflate_With_Header (Encoded, Zlib.GZip, Status);
      begin
         Assert (Status = Zlib.Ok, "Compress Finish pending input must produce valid gzip output");
         Assert (Decoded'Length = Input'Length, "Compress Finish pending input decoded length mismatch");
         for I in Input'Range loop
            Assert
              (Decoded (Decoded'First + Natural (I - Input'First)) = Zlib.Byte (Input (I)),
               "Compress Finish pending input decoded payload mismatch");
         end loop;
      end;

      Zlib.Compress_Close (Filter);
   end Test_Compress_Finish_With_Pending_Input;

   procedure Test_Compress_Flush_Finish_After_End_No_Output
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Compression_Filter_Type;
      Output   : Ada.Streams.Stream_Element_Array (1 .. 8);
      Out_Last : Ada.Streams.Stream_Element_Offset;
   begin
      Zlib.Deflate_Init (Filter, Header => Zlib.GZip, Mode => Zlib.Fixed);
      while not Zlib.Compress_Stream_End (Filter) loop
         Zlib.Compress_Flush (Filter, Output, Out_Last, Flush => Zlib.Finish);
      end loop;

      Zlib.Compress_Flush (Filter, Output, Out_Last, Flush => Zlib.Finish);
      Assert (Produced (Output, Out_Last) = 0, "Compress_Flush Finish after end returns no output");
      Zlib.Compress_Close (Filter);
   end Test_Compress_Flush_Finish_After_End_No_Output;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_Finish_Empty_Zlib_Stored'Access,
         "Finish empty zlib stored stream succeeds");
      Registration.Register_Routine (T, Test_Finish_Empty_Zlib_Fixed'Access, "Finish empty zlib fixed stream succeeds");
      Registration.Register_Routine
        (T, Test_Finish_Empty_Zlib_Dynamic'Access,
         "Finish empty zlib dynamic stream succeeds");
      Registration.Register_Routine
        (T, Test_Finish_Empty_Gzip_Stored'Access,
         "Finish empty gzip stored stream succeeds");
      Registration.Register_Routine (T, Test_Finish_Empty_Gzip_Fixed'Access, "Finish empty gzip fixed stream succeeds");
      Registration.Register_Routine
        (T, Test_Finish_Empty_Gzip_Dynamic'Access,
         "Finish empty gzip dynamic stream succeeds");
      Registration.Register_Routine
        (T, Test_Stream_End_After_Trailer_Drained'Access,
         "Compress_Stream_End true only after trailer drained");
      Registration.Register_Routine
        (T, Test_Compress_Finish_Empty_Input'Access,
         "Compress Finish with empty input succeeds");
      Registration.Register_Routine
        (T, Test_Compress_Finish_With_Pending_Input'Access,
         "Compress Finish with pending input succeeds");
      Registration.Register_Routine
        (T, Test_Double_Finish_After_End'Access,
         "double Finish after end returns no output");
      Registration.Register_Routine
        (T, Test_Compress_Input_After_End_Raises'Access,
         "Compress with input after end raises Status_Error");
      Registration.Register_Routine
        (T, Test_Compress_Flush_Finish_After_End_No_Output'Access,
         "Compress_Flush Finish after end returns no output");
   end Register_Tests;

end Zlib_Streaming_Compress_Finish_Tests;
