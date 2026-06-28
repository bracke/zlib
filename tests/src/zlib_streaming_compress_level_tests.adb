with Ada.Containers.Vectors;
with Ada.Streams; use Ada.Streams;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;

package body Zlib_Streaming_Compress_Level_Tests is
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
      return AUnit.Format ("Zlib streaming compression level API");
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

   function Payload return Zlib.Byte_Array is
      Result : Zlib.Byte_Array (1 .. 8192);
   begin
      for I in Result'Range loop
         if I mod 17 = 0 then
            Result (I) := Zlib.Byte ((I * 11) mod 256);
         else
            Result (I) := Zlib.Byte (Character'Pos ('a') + (I mod 6));
         end if;
      end loop;
      return Result;
   end Payload;

   function Compress_All
     (Input              : Zlib.Byte_Array;
      Header             : Zlib.Header_Type;
      Level              : Zlib.Compression_Level;
      Input_Chunk_Size   : Positive := 1024;
      Output_Buffer_Size : Positive := 128;
      First_Flush        : Zlib.Flush_Mode := Zlib.No_Flush;
      Metadata           : Zlib.GZip_Metadata := Zlib.No_GZip_Metadata)
      return Zlib.Byte_Array
   is
      Filter     : Zlib.Compression_Filter_Type;
      Input_Data : constant Ada.Streams.Stream_Element_Array := To_Stream (Input);
      Output     : Stream_Vectors.Vector;
      Next_Input : Ada.Streams.Stream_Element_Offset := Input_Data'First;
      In_Last    : Ada.Streams.Stream_Element_Offset;
      Out_Last   : Ada.Streams.Stream_Element_Offset;
      Calls      : Natural := 0;
      Used_First_Flush : Boolean := False;
   begin
      Zlib.Deflate_Init
        (Filter   => Filter,
         Header   => Header,
         Level    => Level,
         Metadata => Metadata);

      while Input_Data'Length > 0 and then Next_Input <= Input_Data'Last loop
         declare
            Chunk_Last : constant Ada.Streams.Stream_Element_Offset :=
              Ada.Streams.Stream_Element_Offset'Min
                (Input_Data'Last,
                 Next_Input + Ada.Streams.Stream_Element_Offset (Input_Chunk_Size) - 1);
            Out_Buffer : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Output_Buffer_Size));
            This_Flush : constant Zlib.Flush_Mode :=
              (if not Used_First_Flush then First_Flush else Zlib.No_Flush);
         begin
            Zlib.Compress
              (Filter   => Filter,
               In_Data  => Input_Data (Next_Input .. Chunk_Last),
               In_Last  => In_Last,
               Out_Data => Out_Buffer,
               Out_Last => Out_Last,
               Flush    => This_Flush);
            Append_Output (Output, Out_Buffer, Out_Last);
            Used_First_Flush := True;

            if In_Last >= Next_Input then
               Next_Input := In_Last + 1;
            end if;

            Calls := Calls + 1;
            Assert (Calls < 1_000_000, "level compression input loop must make progress");
         end;
      end loop;

      while not Zlib.Compress_Stream_End (Filter) loop
         declare
            Out_Buffer : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Output_Buffer_Size));
         begin
            Zlib.Compress_Flush
              (Filter   => Filter,
               Out_Data => Out_Buffer,
               Out_Last => Out_Last,
               Flush    => Zlib.Finish);
            Append_Output (Output, Out_Buffer, Out_Last);

            Calls := Calls + 1;
            Assert (Calls < 1_000_000, "level compression finish loop must make progress");
         end;
      end loop;

      Zlib.Compress_Close (Filter);
      return To_Bytes (Output);
   end Compress_All;

   procedure Assert_Level_Stream_Roundtrip
     (Header : Zlib.Header_Type;
      Level  : Zlib.Compression_Level;
      Input_Chunk_Size   : Positive := 1024;
      Output_Buffer_Size : Positive := 128;
      First_Flush        : Zlib.Flush_Mode := Zlib.No_Flush;
      Metadata           : Zlib.GZip_Metadata := Zlib.No_GZip_Metadata)
   is
      Input     : constant Zlib.Byte_Array := Payload;
      Status    : Zlib.Status_Code := Zlib.Ok;
      Compressed : constant Zlib.Byte_Array :=
        Compress_All
          (Input              => Input,
           Header             => Header,
           Level              => Level,
           Input_Chunk_Size   => Input_Chunk_Size,
           Output_Buffer_Size => Output_Buffer_Size,
           First_Flush        => First_Flush,
           Metadata           => Metadata);
      Inflated : constant Zlib.Byte_Array :=
        (if Header = Zlib.Raw_Deflate or else Header = Zlib.GZip then
            Zlib.Inflate_With_Header (Compressed, Header, Status)
         else
            Zlib.Inflate (Compressed, Status));
   begin
      Assert (Status = Zlib.Ok, "streaming level inflate status");
      Assert_Same (Inflated, Input, "streaming level roundtrip");
   end Assert_Level_Stream_Roundtrip;

   procedure Test_Representative_Levels
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      declare
         Levels : constant array (Positive range 1 .. 3) of Zlib.Compression_Level :=
           [1 => 0, 2 => 1, 3 => 6];
      begin
         for Level of Levels loop
            Assert_Level_Stream_Roundtrip (Zlib.Zlib_Header, Level);
            Assert_Level_Stream_Roundtrip (Zlib.GZip, Level);
            Assert_Level_Stream_Roundtrip (Zlib.Raw_Deflate, Level);
         end loop;
      end;
   end Test_Representative_Levels;

   procedure Test_All_Levels
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      for Level in Zlib.Compression_Level loop
         Assert_Level_Stream_Roundtrip (Zlib.Zlib_Header, Level);
         Assert_Level_Stream_Roundtrip (Zlib.GZip, Level);
         Assert_Level_Stream_Roundtrip (Zlib.Raw_Deflate, Level);
      end loop;
   end Test_All_Levels;

   procedure Test_One_Byte_Buffers
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_Level_Stream_Roundtrip
        (Header             => Zlib.Zlib_Header,
         Level              => Zlib.Default_Level,
         Input_Chunk_Size   => 1,
         Output_Buffer_Size => 1);
   end Test_One_Byte_Buffers;

   procedure Test_Sync_Flush_With_Level
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_Level_Stream_Roundtrip
        (Header      => Zlib.GZip,
         Level       => Zlib.Default_Level,
         First_Flush => Zlib.Sync_Flush);
   end Test_Sync_Flush_With_Level;

   procedure Test_GZip_Metadata_With_Level
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Metadata : Zlib.GZip_Metadata := Zlib.No_GZip_Metadata;
   begin
      Zlib.Set_Name (Metadata, "level-stream.txt");
      Zlib.Set_Comment (Metadata, "streaming compression level metadata");
      Zlib.Set_MTime (Metadata, 123_456);
      Zlib.Set_OS (Metadata, 3);
      Zlib.Set_Header_CRC (Metadata, True);

      Assert_Level_Stream_Roundtrip
        (Header   => Zlib.GZip,
         Level    => Zlib.Default_Level,
         Metadata => Metadata);
   end Test_GZip_Metadata_With_Level;

   procedure Test_Finish_In_Compress_With_Level
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input      : constant Zlib.Byte_Array := Payload;
      Filter     : Zlib.Compression_Filter_Type;
      Input_Data : constant Ada.Streams.Stream_Element_Array := To_Stream (Input);
      Output     : Stream_Vectors.Vector;
      Next_Input : Ada.Streams.Stream_Element_Offset := Input_Data'First;
      In_Last    : Ada.Streams.Stream_Element_Offset;
      Out_Last   : Ada.Streams.Stream_Element_Offset;
      Calls      : Natural := 0;
   begin
      Zlib.Deflate_Init
        (Filter => Filter,
         Header => Zlib.Raw_Deflate,
         Level  => Zlib.Default_Level);

      while not Zlib.Compress_Stream_End (Filter) loop
         declare
            Chunk_Last : constant Ada.Streams.Stream_Element_Offset :=
              (if Next_Input <= Input_Data'Last then
                  Ada.Streams.Stream_Element_Offset'Min
                    (Input_Data'Last, Next_Input + 31)
               else
                  Input_Data'Last);
            Out_Buffer : Ada.Streams.Stream_Element_Array (1 .. 7);
         begin
            if Next_Input <= Input_Data'Last then
               Zlib.Compress
                 (Filter   => Filter,
                  In_Data  => Input_Data (Next_Input .. Chunk_Last),
                  In_Last  => In_Last,
                  Out_Data => Out_Buffer,
                  Out_Last => Out_Last,
                  Flush    => (if Chunk_Last = Input_Data'Last then Zlib.Finish else Zlib.No_Flush));

               if In_Last >= Next_Input then
                  Next_Input := In_Last + 1;
               end if;
            else
               Zlib.Compress_Flush
                 (Filter   => Filter,
                  Out_Data => Out_Buffer,
                  Out_Last => Out_Last,
                  Flush    => Zlib.Finish);
            end if;

            Append_Output (Output, Out_Buffer, Out_Last);
            Calls := Calls + 1;
            Assert (Calls < 1_000_000, "level Finish-in-Compress loop must make progress");
         end;
      end loop;

      declare
         Status   : Zlib.Status_Code := Zlib.Ok;
         Inflated : constant Zlib.Byte_Array :=
           Zlib.Inflate_With_Header (To_Bytes (Output), Zlib.Raw_Deflate, Status);
      begin
         Assert (Status = Zlib.Ok, "level Finish-in-Compress raw inflate status");
         Assert_Same (Inflated, Input, "level Finish-in-Compress roundtrip");
      end;

      Zlib.Compress_Close (Filter);
   end Test_Finish_In_Compress_With_Level;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine (T, Test_Representative_Levels'Access,
                                     "streaming representative levels roundtrip");
      Registration.Register_Routine (T, Test_All_Levels'Access,
                                     "streaming all levels roundtrip");
      Registration.Register_Routine (T, Test_One_Byte_Buffers'Access,
                                     "streaming level input chunk size 1 and output buffer size 1");
      Registration.Register_Routine (T, Test_Sync_Flush_With_Level'Access,
                                     "streaming level Sync_Flush roundtrips");
      Registration.Register_Routine (T, Test_GZip_Metadata_With_Level'Access,
                                     "streaming gzip metadata level roundtrips");
      Registration.Register_Routine (T, Test_Finish_In_Compress_With_Level'Access,
                                     "streaming level Finish works from Compress");
   end Register_Tests;
end Zlib_Streaming_Compress_Level_Tests;
