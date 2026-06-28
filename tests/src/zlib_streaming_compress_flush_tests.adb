with Ada.Containers.Vectors;
with Ada.Streams; use Ada.Streams;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;

package body Zlib_Streaming_Compress_Flush_Tests is
   use type Zlib.Byte;
   use type Zlib.Header_Type;
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
      return AUnit.Format ("Zlib streaming compression flush modes");
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

   function Inflate_Header
     (Header : Zlib.Header_Type)
      return Zlib.Header_Type
   is
   begin
      if Header = Zlib.Default then
         return Zlib.Zlib_Header;
      else
         return Header;
      end if;
   end Inflate_Header;

   procedure Assert_Decodes
     (Encoded  : Stream_Vectors.Vector;
      Expected : Zlib.Byte_Array;
      Header   : Zlib.Header_Type;
      Label    : String)
   is
      Status  : Zlib.Status_Code;
      Decoded : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (To_Bytes (Encoded), Inflate_Header (Header), Status);
   begin
      Assert (Status = Zlib.Ok, Label & ": inflate status");
      Assert (Decoded'Length = Expected'Length, Label & ": decoded length");
      for I in Expected'Range loop
         Assert (Decoded (I) = Expected (I), Label & ": decoded byte");
      end loop;
   end Assert_Decodes;

   procedure Drain_Quiet
     (Filter : in out Zlib.Compression_Filter_Type;
      Output : in out Stream_Vectors.Vector;
      Label  : String)
   is
      Buffer   : Ada.Streams.Stream_Element_Array (1 .. 64);
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Calls    : Natural := 0;
      Count    : Natural;
   begin
      loop
         Zlib.Compress_Flush (Filter, Buffer, Out_Last, Flush => Zlib.No_Flush);
         Count := Produced (Buffer, Out_Last);
         Append_Output (Output, Buffer, Out_Last);
         Calls := Calls + 1;
         Assert (Calls < 10_000, Label & ": drain loop bound");
         exit when Count = 0;
      end loop;
   end Drain_Quiet;

   procedure Finish_Stream
     (Filter : in out Zlib.Compression_Filter_Type;
      Output : in out Stream_Vectors.Vector;
      Label  : String)
   is
      Buffer   : Ada.Streams.Stream_Element_Array (1 .. 7);
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Calls    : Natural := 0;
   begin
      while not Zlib.Compress_Stream_End (Filter) loop
         Zlib.Compress_Flush (Filter, Buffer, Out_Last, Flush => Zlib.Finish);
         Append_Output (Output, Buffer, Out_Last);
         Calls := Calls + 1;
         Assert (Calls < 10_000, Label & ": finish loop bound");
      end loop;
   end Finish_Stream;

   procedure Assert_Flush_Then_Continue
     (Header : Zlib.Header_Type;
      Mode   : Zlib.Compression_Mode;
      Flush  : Zlib.Flush_Mode;
      Label  : String)
   is
      Filter   : Zlib.Compression_Filter_Type;
      Output   : Stream_Vectors.Vector;
      Part_1   : constant Ada.Streams.Stream_Element_Array := [1 => 65, 2 => 66, 3 => 67];
      Part_2   : constant Ada.Streams.Stream_Element_Array := [1 => 68, 2 => 69, 3 => 70];
      Expected : constant Zlib.Byte_Array := [1 => 65, 2 => 66, 3 => 67, 4 => 68, 5 => 69, 6 => 70];
      Buffer   : Ada.Streams.Stream_Element_Array (1 .. 256);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
   begin
      Zlib.Deflate_Init (Filter, Header => Header, Mode => Mode);
      Zlib.Compress (Filter, Part_1, In_Last, Buffer, Out_Last, Flush => Flush);
      Append_Output (Output, Buffer, Out_Last);
      Assert (In_Last = Part_1'Last, Label & ": first chunk consumed");
      Drain_Quiet (Filter, Output, Label & " drain after flush");
      Assert (not Zlib.Compress_Stream_End (Filter), Label & ": stream remains open");

      Zlib.Compress (Filter, Part_2, In_Last, Buffer, Out_Last, Flush => Zlib.No_Flush);
      Append_Output (Output, Buffer, Out_Last);
      Assert (In_Last = Part_2'Last, Label & ": second chunk consumed");
      Finish_Stream (Filter, Output, Label);
      Assert_Decodes (Output, Expected, Header, Label);
      Zlib.Compress_Close (Filter);
   end Assert_Flush_Then_Continue;

   procedure Test_Sync_Flush_Matrix
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Headers : constant array (Positive range 1 .. 3) of Zlib.Header_Type :=
        [Zlib.Zlib_Header, Zlib.GZip, Zlib.Raw_Deflate];
      Modes : constant array (Positive range 1 .. 4) of Zlib.Compression_Mode :=
        [Zlib.Stored, Zlib.Fixed, Zlib.Dynamic, Zlib.Auto];
   begin
      for Header of Headers loop
         for Mode of Modes loop
            Assert_Flush_Then_Continue (Header, Mode, Zlib.Sync_Flush, "Sync_Flush");
         end loop;
      end loop;
   end Test_Sync_Flush_Matrix;

   procedure Test_Full_Flush_Matrix
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Headers : constant array (Positive range 1 .. 3) of Zlib.Header_Type :=
        [Zlib.Zlib_Header, Zlib.GZip, Zlib.Raw_Deflate];
      Modes : constant array (Positive range 1 .. 4) of Zlib.Compression_Mode :=
        [Zlib.Stored, Zlib.Fixed, Zlib.Dynamic, Zlib.Auto];
   begin
      for Header of Headers loop
         for Mode of Modes loop
            Assert_Flush_Then_Continue (Header, Mode, Zlib.Full_Flush, "Full_Flush");
         end loop;
      end loop;
   end Test_Full_Flush_Matrix;

   procedure Test_Size_One_And_Finish_After_Pending
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Compression_Filter_Type;
      Output   : Stream_Vectors.Vector;
      Input    : constant Ada.Streams.Stream_Element_Array := [1 => 81, 2 => 82, 3 => 83];
      Expected : constant Zlib.Byte_Array := [1 => 81, 2 => 82, 3 => 83];
      Buffer   : Ada.Streams.Stream_Element_Array (1 .. 1);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
   begin
      Zlib.Deflate_Init (Filter, Header => Zlib.GZip, Mode => Zlib.Dynamic);
      In_Last := Input'First - 1;
      while In_Last < Input'Last loop
         declare
            Next_First : constant Ada.Streams.Stream_Element_Offset := In_Last + 1;
         begin
            Zlib.Compress
              (Filter,
               Input (Next_First .. Input'Last),
               In_Last,
               Buffer,
               Out_Last,
               Flush => Zlib.Sync_Flush);
            Append_Output (Output, Buffer, Out_Last);
         end;
      end loop;
      Assert (not Zlib.Compress_Stream_End (Filter), "Sync_Flush does not end stream");
      Finish_Stream (Filter, Output, "Finish after pending Sync_Flush");
      Assert_Decodes (Output, Expected, Zlib.GZip, "Finish after pending Sync_Flush");
      Zlib.Compress_Close (Filter);
   end Test_Size_One_And_Finish_After_Pending;

   procedure Test_One_Byte_Input_And_Multiple_Flushes
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Compression_Filter_Type;
      Output   : Stream_Vectors.Vector;
      Expected : constant Zlib.Byte_Array := [1 => 65, 2 => 66, 3 => 67, 4 => 68];
      Buffer   : Ada.Streams.Stream_Element_Array (1 .. 1);
      Out_Last : Ada.Streams.Stream_Element_Offset;
      In_Last  : Ada.Streams.Stream_Element_Offset;

      procedure Feed_One
        (B     : Ada.Streams.Stream_Element;
         Flush : Zlib.Flush_Mode;
         Label : String)
      is
         Input : constant Ada.Streams.Stream_Element_Array := [1 => B];
         Calls : Natural := 0;
      begin
         Zlib.Compress (Filter, Input, In_Last, Buffer, Out_Last, Flush => Flush);
         Append_Output (Output, Buffer, Out_Last);
         Assert (In_Last = Input'Last, Label & ": one-byte input consumed");
         while Produced (Buffer, Out_Last) /= 0 loop
            Zlib.Compress_Flush (Filter, Buffer, Out_Last, Flush => Zlib.No_Flush);
            Append_Output (Output, Buffer, Out_Last);
            Calls := Calls + 1;
            Assert (Calls < 10_000, Label & ": one-byte flush drain bound");
         end loop;
         Assert (not Zlib.Compress_Stream_End (Filter), Label & ": stream remains open");
      end Feed_One;
   begin
      Zlib.Deflate_Init (Filter, Header => Zlib.Raw_Deflate, Mode => Zlib.Auto);
      Feed_One (65, Zlib.Sync_Flush, "first Sync_Flush");
      Feed_One (66, Zlib.Sync_Flush, "second Sync_Flush");
      Feed_One (67, Zlib.Full_Flush, "first Full_Flush");
      Feed_One (68, Zlib.Full_Flush, "second Full_Flush");
      Finish_Stream (Filter, Output, "multiple flush finish");
      Assert (Zlib.Compress_Stream_End (Filter), "stream ends only after Finish");
      Assert_Decodes (Output, Expected, Zlib.Raw_Deflate, "multiple one-byte flushes");
      Zlib.Compress_Close (Filter);
   end Test_One_Byte_Input_And_Multiple_Flushes;

   procedure Test_Lifecycle_Errors
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Compression_Filter_Type;
      Output   : Stream_Vectors.Vector;
      Buffer   : Ada.Streams.Stream_Element_Array (1 .. 8);
      Out_Last : Ada.Streams.Stream_Element_Offset;
   begin
      begin
         Zlib.Compress_Flush (Filter, Buffer, Out_Last, Flush => Zlib.Sync_Flush);
         Assert (False, "Sync_Flush before init must raise Status_Error");
      exception
         when Zlib.Status_Error => null;
      end;

      begin
         Zlib.Compress_Flush (Filter, Buffer, Out_Last, Flush => Zlib.Full_Flush);
         Assert (False, "Full_Flush before init must raise Status_Error");
      exception
         when Zlib.Status_Error => null;
      end;

      Zlib.Deflate_Init (Filter, Header => Zlib.Raw_Deflate, Mode => Zlib.Stored);
      Finish_Stream (Filter, Output, "lifecycle finish");
      begin
         Zlib.Compress_Flush (Filter, Buffer, Out_Last, Flush => Zlib.Sync_Flush);
         Assert (False, "Sync_Flush after stream end must raise Status_Error");
      exception
         when Zlib.Status_Error => null;
      end;

      begin
         Zlib.Compress_Flush (Filter, Buffer, Out_Last, Flush => Zlib.Full_Flush);
         Assert (False, "Full_Flush after stream end must raise Status_Error");
      exception
         when Zlib.Status_Error => null;
      end;

      Zlib.Compress_Close (Filter);
      begin
         Zlib.Compress_Flush (Filter, Buffer, Out_Last, Flush => Zlib.Sync_Flush);
         Assert (False, "Sync_Flush after close must raise Status_Error");
      exception
         when Zlib.Status_Error => null;
      end;

      begin
         Zlib.Compress_Flush (Filter, Buffer, Out_Last, Flush => Zlib.Full_Flush);
         Assert (False, "Full_Flush after close must raise Status_Error");
      exception
         when Zlib.Status_Error => null;
      end;
   end Test_Lifecycle_Errors;

   procedure Test_Inflate_Decodes_Sync_Flush_Before_Finish
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Compressor : Zlib.Compression_Filter_Type;
      Inflater   : Zlib.Filter_Type;
      Input      : constant Ada.Streams.Stream_Element_Array := [1 => 97, 2 => 98, 3 => 99];
      C_Buffer   : Ada.Streams.Stream_Element_Array (1 .. 128);
      I_Buffer   : Ada.Streams.Stream_Element_Array (1 .. 16);
      In_Last    : Ada.Streams.Stream_Element_Offset;
      C_Last     : Ada.Streams.Stream_Element_Offset;
      I_In_Last  : Ada.Streams.Stream_Element_Offset;
      I_Out_Last : Ada.Streams.Stream_Element_Offset;
   begin
      Zlib.Deflate_Init (Compressor, Header => Zlib.Zlib_Header, Mode => Zlib.Fixed);
      Zlib.Compress (Compressor, Input, In_Last, C_Buffer, C_Last, Flush => Zlib.Sync_Flush);
      Assert (Produced (C_Buffer, C_Last) > 0, "Sync_Flush produces bytes");
      Zlib.Inflate_Init (Inflater, Header => Zlib.Zlib_Header);
      Zlib.Translate
        (Inflater,
         C_Buffer (C_Buffer'First .. C_Last),
         I_In_Last,
         I_Buffer,
         I_Out_Last,
         Flush => Zlib.No_Flush);
      Assert (Produced (I_Buffer, I_Out_Last) = Input'Length, "inflated flushed bytes");
      Assert (not Zlib.Stream_End (Inflater), "inflate stream end remains false");
      Zlib.Close (Inflater, Ignore_Error => True);
      Zlib.Compress_Close (Compressor, Ignore_Error => True);
   end Test_Inflate_Decodes_Sync_Flush_Before_Finish;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine (T, Test_Sync_Flush_Matrix'Access, "Sync_Flush matrix");
      Registration.Register_Routine (T, Test_Full_Flush_Matrix'Access, "Full_Flush matrix");
      Registration.Register_Routine
        (T, Test_Size_One_And_Finish_After_Pending'Access,
         "one-byte output and Finish after pending flush");
      Registration.Register_Routine
        (T, Test_One_Byte_Input_And_Multiple_Flushes'Access,
         "one-byte input and multiple flushes before Finish");
      Registration.Register_Routine (T, Test_Lifecycle_Errors'Access, "flush lifecycle errors");
      Registration.Register_Routine
        (T, Test_Inflate_Decodes_Sync_Flush_Before_Finish'Access,
         "streaming inflate decodes through sync flush");
   end Register_Tests;
end Zlib_Streaming_Compress_Flush_Tests;
