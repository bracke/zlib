with Ada.Streams;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;

package body Zlib_Streaming_Compress_Raw_Stored_Tests is
   use type Ada.Streams.Stream_Element_Offset;
   use type Zlib.Byte;
   use type Zlib.Status_Code;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib streaming raw stored Deflate compression");
   end Name;

   function Empty return Zlib.Byte_Array is
      Result : constant Zlib.Byte_Array (1 .. 0) := [others => 0];
   begin
      return Result;
   end Empty;

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

   function Compress_Raw_Stored
     (Input              : Zlib.Byte_Array;
      Input_Chunk_Size   : Positive := 1024;
      Output_Buffer_Size : Positive := 64;
      Finish_In_Compress : Boolean := False)
      return Zlib.Byte_Array
   is
      Filter     : Zlib.Compression_Filter_Type;
      Input_Data : constant Ada.Streams.Stream_Element_Array := To_Stream (Input);
      Output     : Zlib.Byte_Array (1 .. Input'Length * 2 + 4096);
      Out_Count  : Natural := 0;
      Next_Input : Ada.Streams.Stream_Element_Offset := Input_Data'First;
      In_Last    : Ada.Streams.Stream_Element_Offset;
      Out_Last   : Ada.Streams.Stream_Element_Offset;
      Calls      : Natural := 0;
   begin
      Zlib.Deflate_Init (Filter, Header => Zlib.Raw_Deflate, Mode => Zlib.Stored);

      while Input_Data'Length > 0 and then Next_Input <= Input_Data'Last loop
         declare
            Chunk_Last : constant Ada.Streams.Stream_Element_Offset :=
              Ada.Streams.Stream_Element_Offset'Min
                (Input_Data'Last,
                 Next_Input + Ada.Streams.Stream_Element_Offset (Input_Chunk_Size) - 1);
            Out_Buffer : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Output_Buffer_Size));
            Flush_Mode : constant Zlib.Flush_Mode :=
              (if Finish_In_Compress and then Chunk_Last = Input_Data'Last
               then Zlib.Finish
               else Zlib.No_Flush);
         begin
            Zlib.Compress (Filter, Input_Data (Next_Input .. Chunk_Last), In_Last, Out_Buffer, Out_Last, Flush_Mode);
            Append (Out_Buffer, Out_Last, Output, Out_Count);
            if In_Last >= Next_Input then
               Next_Input := In_Last + 1;
            end if;
            Calls := Calls + 1;
            Assert (Calls < 1_000_000, "raw stored input loop must make progress");
         end;
      end loop;

      while not Zlib.Compress_Stream_End (Filter) loop
         declare
            Out_Buffer : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Output_Buffer_Size));
         begin
            Zlib.Compress_Flush (Filter, Out_Buffer, Out_Last, Zlib.Finish);
            Append (Out_Buffer, Out_Last, Output, Out_Count);
            Calls := Calls + 1;
            Assert (Calls < 1_000_000, "raw stored finish loop must make progress");
         end;
      end loop;

      Zlib.Compress_Close (Filter);
      if Out_Count = 0 then
         return Empty;
      else
         return Output (1 .. Out_Count);
      end if;
   end Compress_Raw_Stored;

   procedure Assert_Raw_Inflates
     (Compressed : Zlib.Byte_Array;
      Expected   : Zlib.Byte_Array;
      Message    : String)
   is
      Status : Zlib.Status_Code := Zlib.Ok;
      Output : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Compressed, Zlib.Raw_Deflate, Status);
   begin
      Assert (Status = Zlib.Ok, Message & ": inflate status");
      Assert_Same (Output, Expected, Message);
   end Assert_Raw_Inflates;

   function Hello return Zlib.Byte_Array is
   begin
      return [1 => 104, 2 => 101, 3 => 108, 4 => 108, 5 => 111];
   end Hello;

   procedure Test_Empty
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Output : constant Zlib.Byte_Array := Compress_Raw_Stored (Empty, Output_Buffer_Size => 1);
   begin
      Assert_Raw_Inflates (Output, Empty, "streaming raw stored empty");
   end Test_Empty;

   procedure Test_Hello_One_Byte_Buffers
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array := Hello;
   begin
      Assert_Raw_Inflates
        (Compress_Raw_Stored (Input, Input_Chunk_Size => 1, Output_Buffer_Size => 1),
         Input,
         "streaming raw stored hello one-byte buffers");
   end Test_Hello_One_Byte_Buffers;

   procedure Test_Binary
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input : Zlib.Byte_Array (1 .. 512);
   begin
      for I in Input'Range loop
         Input (I) := Zlib.Byte ((I * 91) mod 256);
      end loop;
      Assert_Raw_Inflates
        (Compress_Raw_Stored (Input, Input_Chunk_Size => 1, Output_Buffer_Size => 1),
         Input,
         "streaming raw stored binary");
   end Test_Binary;

   procedure Test_Large_Multiple_Blocks
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input : Zlib.Byte_Array (1 .. 70_000);
   begin
      for I in Input'Range loop
         Input (I) := Zlib.Byte (I mod 251);
      end loop;
      Assert_Raw_Inflates
        (Compress_Raw_Stored (Input, Input_Chunk_Size => 4096, Output_Buffer_Size => 1),
         Input,
         "streaming raw stored large");
   end Test_Large_Multiple_Blocks;

   procedure Test_Stream_End_And_Close
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Compression_Filter_Type;
      Input    : constant Ada.Streams.Stream_Element_Array (1 .. 1) := [1 => 42];
      Output   : Ada.Streams.Stream_Element_Array (1 .. 1);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Raised   : Boolean := False;
   begin
      Zlib.Deflate_Init (Filter, Header => Zlib.Raw_Deflate, Mode => Zlib.Stored);
      Zlib.Compress (Filter, Input, In_Last, Output, Out_Last, Zlib.Finish);
      Assert (not Zlib.Compress_Stream_End (Filter), "raw stored stream end false before drain");
      while not Zlib.Compress_Stream_End (Filter) loop
         Zlib.Compress_Flush (Filter, Output, Out_Last, Zlib.Finish);
      end loop;
      Assert (Zlib.Compress_Stream_End (Filter), "raw stored stream end true after drain");
      Zlib.Compress_Close (Filter);

      Zlib.Deflate_Init (Filter, Header => Zlib.Raw_Deflate, Mode => Zlib.Stored);
      begin
         Zlib.Compress_Close (Filter, Ignore_Error => False);
      exception
         when Zlib.Zlib_Error =>
            Raised := True;
      end;
      Assert (Raised, "raw stored close before Finish raises");
   end Test_Stream_End_And_Close;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine (T, Test_Empty'Access, "streaming raw stored empty input");
      Registration.Register_Routine
        (T, Test_Hello_One_Byte_Buffers'Access,
         "streaming raw stored hello one-byte buffers");
      Registration.Register_Routine (T, Test_Binary'Access, "streaming raw stored binary payload");
      Registration.Register_Routine
        (T, Test_Large_Multiple_Blocks'Access,
         "streaming raw stored large multiple blocks");
      Registration.Register_Routine (T, Test_Stream_End_And_Close'Access, "streaming raw stored stream end and close");
   end Register_Tests;
end Zlib_Streaming_Compress_Raw_Stored_Tests;
