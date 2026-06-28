with Ada.Streams;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib; use Zlib;

package body Zlib_Streaming_Dictionary_Tests is
   use type Ada.Streams.Stream_Element_Offset;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib preset dictionary streaming API");
   end Name;

   function Dictionary return Zlib.Byte_Array is
   begin
      return [104, 101, 108, 108, 111, 32, 119, 111, 114, 108, 100, 32,
              112, 114, 101, 102, 105, 120, 45, 115, 117, 102, 102, 105, 120];
   end Dictionary;

   function Payload return Zlib.Byte_Array is
   begin
      return [104, 101, 108, 108, 111];
   end Payload;

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

   function To_Stream
     (Input : Zlib.Byte_Array)
      return Ada.Streams.Stream_Element_Array
   is
      Result : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Input'Length));
   begin
      for I in Input'Range loop
         Result (Ada.Streams.Stream_Element_Offset (I - Input'First + 1)) :=
           Ada.Streams.Stream_Element (Input (I));
      end loop;
      return Result;
   end To_Stream;

   procedure Append
     (Out_Data    : Ada.Streams.Stream_Element_Array;
      Out_Last    : Ada.Streams.Stream_Element_Offset;
      Result      : in out Zlib.Byte_Array;
      Result_Last : in out Natural)
   is
      Count : constant Natural := Produced (Out_Data, Out_Last);
   begin
      for I in Out_Data'First .. Out_Data'First + Ada.Streams.Stream_Element_Offset (Count) - 1 loop
         Result_Last := Result_Last + 1;
         Result (Result_Last) := Zlib.Byte (Out_Data (I));
      end loop;
   end Append;

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

   function Streaming_Compress_With_Dictionary
     (Input : Zlib.Byte_Array;
      Dict  : Zlib.Byte_Array)
      return Zlib.Byte_Array
   is
      Filter     : Zlib.Compression_Filter_Type;
      Input_Data : constant Ada.Streams.Stream_Element_Array := To_Stream (Input);
      Output     : Zlib.Byte_Array (1 .. Input'Length * 2 + 4096);
      Out_Count  : Natural := 0;
      Next_Input : Ada.Streams.Stream_Element_Offset := Input_Data'First;
      In_Last    : Ada.Streams.Stream_Element_Offset;
      Out_Last   : Ada.Streams.Stream_Element_Offset;
   begin
      Zlib.Deflate_Init (Filter, Header => Zlib.Zlib_Header, Mode => Zlib.Auto);
      Zlib.Deflate_Set_Dictionary (Filter, Dict);

      while Input_Data'Length > 0 and then Next_Input <= Input_Data'Last loop
         declare
            Out_Buffer : Ada.Streams.Stream_Element_Array (1 .. 7);
         begin
            Zlib.Compress
              (Filter, Input_Data (Next_Input .. Input_Data'Last), In_Last,
               Out_Buffer, Out_Last, Zlib.No_Flush);
            Append (Out_Buffer, Out_Last, Output, Out_Count);
            if In_Last >= Next_Input then
               Next_Input := In_Last + 1;
            end if;
         end;
      end loop;

      while not Zlib.Compress_Stream_End (Filter) loop
         declare
            Out_Buffer : Ada.Streams.Stream_Element_Array (1 .. 7);
         begin
            Zlib.Compress_Flush (Filter, Out_Buffer, Out_Last, Zlib.Finish);
            Append (Out_Buffer, Out_Last, Output, Out_Count);
         end;
      end loop;

      Zlib.Compress_Close (Filter);
      return Output (1 .. Out_Count);
   end Streaming_Compress_With_Dictionary;

   function Streaming_Inflate_With_Dictionary
     (Compressed : Zlib.Byte_Array;
      Dict       : Zlib.Byte_Array)
      return Zlib.Byte_Array
   is
      Filter     : Zlib.Filter_Type;
      Input_Data : constant Ada.Streams.Stream_Element_Array := To_Stream (Compressed);
      Output     : Zlib.Byte_Array (1 .. 4096);
      Out_Count  : Natural := 0;
      Next_Input : Ada.Streams.Stream_Element_Offset := Input_Data'First;
      In_Last    : Ada.Streams.Stream_Element_Offset;
      Out_Last   : Ada.Streams.Stream_Element_Offset;
   begin
      Zlib.Inflate_Init (Filter, Header => Zlib.Zlib_Header);
      Zlib.Inflate_Set_Dictionary (Filter, Dict);

      while Input_Data'Length > 0 and then Next_Input <= Input_Data'Last loop
         declare
            Out_Buffer : Ada.Streams.Stream_Element_Array (1 .. 3);
         begin
            Zlib.Translate
              (Filter, Input_Data (Next_Input .. Input_Data'Last), In_Last,
               Out_Buffer, Out_Last, Zlib.No_Flush);
            Append (Out_Buffer, Out_Last, Output, Out_Count);
            if In_Last >= Next_Input then
               Next_Input := In_Last + 1;
            end if;
         end;
      end loop;

      while not Zlib.Stream_End (Filter) loop
         declare
            Out_Buffer : Ada.Streams.Stream_Element_Array (1 .. 3);
         begin
            Zlib.Flush (Filter, Out_Buffer, Out_Last, Zlib.Finish);
            Append (Out_Buffer, Out_Last, Output, Out_Count);
         end;
      end loop;

      Zlib.Close (Filter);
      return Output (1 .. Out_Count);
   end Streaming_Inflate_With_Dictionary;

   procedure Test_Streaming_Compression_Roundtrip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Dict       : constant Zlib.Byte_Array := Dictionary;
      Compressed : constant Zlib.Byte_Array :=
        Streaming_Compress_With_Dictionary (Payload, Dict);
      Decoded    : constant Zlib.Byte_Array :=
        Streaming_Inflate_With_Dictionary (Compressed, Dict);
   begin
      Assert_Same (Decoded, Payload, "streaming dictionary roundtrip");
   end Test_Streaming_Compression_Roundtrip;

   procedure Test_Set_Dictionary_Before_Init_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter : Zlib.Filter_Type;
   begin
      Zlib.Inflate_Set_Dictionary (Filter, Dictionary);
      Assert (False, "Inflate_Set_Dictionary before init must raise Status_Error");
   exception
      when Zlib.Status_Error =>
         null;
   end Test_Set_Dictionary_Before_Init_Raises;

   procedure Test_Set_Dictionary_After_Data_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter  : Zlib.Compression_Filter_Type;
      In_Last : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Input   : constant Ada.Streams.Stream_Element_Array := To_Stream (Payload);
      Output  : Ada.Streams.Stream_Element_Array (1 .. 16);
   begin
      Zlib.Deflate_Init (Filter, Header => Zlib.Zlib_Header, Mode => Zlib.Stored);
      Zlib.Compress (Filter, Input, In_Last, Output, Out_Last, Zlib.No_Flush);
      Zlib.Deflate_Set_Dictionary (Filter, Dictionary);
      Assert (False, "Deflate_Set_Dictionary after data/header started must raise Status_Error");
   exception
      when Zlib.Status_Error =>
         null;
   end Test_Set_Dictionary_After_Data_Raises;

   procedure Test_Set_Dictionary_Rejected_For_GZip_And_Raw
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C : Zlib.Compression_Filter_Type;
      I : Zlib.Filter_Type;
   begin
      Zlib.Deflate_Init (C, Header => Zlib.GZip, Mode => Zlib.Stored);
      begin
         Zlib.Deflate_Set_Dictionary (C, Dictionary);
         Assert (False, "gzip compression dictionary must raise Status_Error");
      exception
         when Zlib.Status_Error => null;
      end;

      Zlib.Inflate_Init (I, Header => Zlib.Raw_Deflate);
      begin
         Zlib.Inflate_Set_Dictionary (I, Dictionary);
         Assert (False, "raw inflate dictionary must raise Status_Error");
      exception
         when Zlib.Status_Error => null;
      end;
   end Test_Set_Dictionary_Rejected_For_GZip_And_Raw;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Streaming_Compression_Roundtrip'Access, "streaming dictionary compression roundtrip");
      Register_Routine (T, Test_Set_Dictionary_Before_Init_Raises'Access, "inflate dictionary before init raises");
      Register_Routine (T, Test_Set_Dictionary_After_Data_Raises'Access, "deflate dictionary after data raises");
      Register_Routine (T, Test_Set_Dictionary_Rejected_For_GZip_And_Raw'Access, "gzip/raw reject dictionary APIs");
   end Register_Tests;
end Zlib_Streaming_Dictionary_Tests;
