with Ada.Containers.Vectors;
with Ada.Streams;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;

package body Zlib_Auto_Block_Selection_Tests is
   use type Ada.Streams.Stream_Element_Offset;
   use type Zlib.Byte;
   use type Zlib.Status_Code;

   package Byte_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Zlib.Byte);

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib Auto block selection");
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
     (Output : in out Byte_Vectors.Vector;
      Buffer : Ada.Streams.Stream_Element_Array;
      Last   : Ada.Streams.Stream_Element_Offset)
   is
      Count : constant Natural := Produced (Buffer, Last);
   begin
      for I in Buffer'First .. Buffer'First + Ada.Streams.Stream_Element_Offset (Count) - 1 loop
         Output.Append (Zlib.Byte (Buffer (I)));
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

   function To_Array
     (Data : Byte_Vectors.Vector)
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
            Result (Index) := B;
            Index := Index + 1;
         end loop;
         return Result;
      end;
   end To_Array;

   procedure Assert_Same
     (Actual   : Zlib.Byte_Array;
      Expected : Zlib.Byte_Array;
      Message  : String)
   is
   begin
      Assert (Actual'Length = Expected'Length, Message & ": length mismatch");
      for I in Expected'Range loop
         Assert (Actual (Actual'First + (I - Expected'First)) = Expected (I),
                 Message & ": byte mismatch");
      end loop;
   end Assert_Same;

   function Same_Bytes
     (Left  : Zlib.Byte_Array;
      Right : Zlib.Byte_Array)
      return Boolean
   is
   begin
      if Left'Length /= Right'Length then
         return False;
      end if;

      for I in Right'Range loop
         if Left (Left'First + (I - Right'First)) /= Right (I) then
            return False;
         end if;
      end loop;

      return True;
   end Same_Bytes;

   procedure Assert_Roundtrip
     (Compressed : Zlib.Byte_Array;
      Header     : Zlib.Header_Type;
      Expected   : Zlib.Byte_Array;
      Message    : String)
   is
      Status : Zlib.Status_Code;
   begin
      declare
         Inflated : constant Zlib.Byte_Array :=
           Zlib.Inflate_With_Header (Compressed, Header, Status);
      begin
         Assert (Status = Zlib.Ok, Message & ": inflate must succeed");
         Assert_Same (Inflated, Expected, Message);
      end;
   end Assert_Roundtrip;

   function Streaming_Auto_With_Flush
     (Input : Zlib.Byte_Array;
      Flush : Zlib.Flush_Mode)
      return Zlib.Byte_Array
   is
      Filter     : Zlib.Compression_Filter_Type;
      Input_Data : constant Ada.Streams.Stream_Element_Array := To_Stream (Input);
      Output     : Byte_Vectors.Vector;
      In_Last    : Ada.Streams.Stream_Element_Offset;
      Out_Last   : Ada.Streams.Stream_Element_Offset;
      Calls      : Natural := 0;
   begin
      Zlib.Deflate_Init (Filter, Header => Zlib.Zlib_Header, Mode => Zlib.Auto);

      if Input_Data'Length > 0 then
         declare
            Out_Buffer : Ada.Streams.Stream_Element_Array (1 .. 4096);
         begin
            Zlib.Compress
              (Filter   => Filter,
               In_Data  => Input_Data,
               In_Last  => In_Last,
               Out_Data => Out_Buffer,
               Out_Last => Out_Last,
               Flush    => Flush);
            Append_Output (Output, Out_Buffer, Out_Last);
            Assert
              (In_Last = Input_Data'Last,
               "streaming Auto flush test must consume the small fixture input");
         end;
      end if;

      while not Zlib.Compress_Stream_End (Filter) loop
         declare
            Out_Buffer : Ada.Streams.Stream_Element_Array (1 .. 31);
         begin
            Zlib.Compress_Flush
              (Filter   => Filter,
               Out_Data => Out_Buffer,
               Out_Last => Out_Last,
               Flush    => Zlib.Finish);
            Append_Output (Output, Out_Buffer, Out_Last);
         end;

         Calls := Calls + 1;
         Assert (Calls < 100_000, "streaming Auto flush test must make progress");
      end loop;

      Zlib.Compress_Close (Filter, Ignore_Error => True);
      return To_Array (Output);
   end Streaming_Auto_With_Flush;

   procedure Test_Auto_Empty_Roundtrips
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input  : constant Zlib.Byte_Array (1 .. 0) := [others => 0];
      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array := Zlib.Deflate (Input, Zlib.Auto, Status);
   begin
      Assert (Status = Zlib.Ok, "Auto empty compression must succeed");
      Assert_Roundtrip (Output, Zlib.Zlib_Header, Input, "Auto empty roundtrip");
   end Test_Auto_Empty_Roundtrips;

   procedure Test_Auto_Hello_Roundtrips
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input  : constant Zlib.Byte_Array :=
        [1 => Zlib.Byte (Character'Pos ('h')),
         2 => Zlib.Byte (Character'Pos ('e')),
         3 => Zlib.Byte (Character'Pos ('l')),
         4 => Zlib.Byte (Character'Pos ('l')),
         5 => Zlib.Byte (Character'Pos ('o'))];
      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array := Zlib.Deflate (Input, Zlib.Auto, Status);
   begin
      Assert (Status = Zlib.Ok, "Auto hello compression must succeed");
      Assert_Roundtrip (Output, Zlib.Zlib_Header, Input, "Auto hello roundtrip");
   end Test_Auto_Hello_Roundtrips;

   procedure Test_Auto_Binary_Payload_Roundtrips
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input  : constant Zlib.Byte_Array := [1 => 0, 2 => 16#FF#, 3 => 16#10#, 4 => 16#80#, 5 => 0];
      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array := Zlib.Deflate (Input, Zlib.Auto, Status);
   begin
      Assert (Status = Zlib.Ok, "Auto binary compression must succeed");
      Assert_Roundtrip (Output, Zlib.Zlib_Header, Input, "Auto binary roundtrip");
   end Test_Auto_Binary_Payload_Roundtrips;

   procedure Test_Auto_Repeated_Payload_Roundtrips
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input  : constant Zlib.Byte_Array (1 .. 512) := [others => Zlib.Byte (Character'Pos ('R'))];
      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array := Zlib.Deflate (Input, Zlib.Auto, Status);
   begin
      Assert (Status = Zlib.Ok, "Auto repeated compression must succeed");
      Assert_Roundtrip (Output, Zlib.Zlib_Header, Input, "Auto repeated roundtrip");
   end Test_Auto_Repeated_Payload_Roundtrips;

   procedure Test_Auto_Large_Payload_Roundtrips
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input  : constant Zlib.Byte_Array (1 .. 70_000) := [others => Zlib.Byte (Character'Pos ('L'))];
      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array := Zlib.Deflate (Input, Zlib.Auto, Status);
   begin
      Assert (Status = Zlib.Ok, "Auto large compression must succeed");
      Assert_Roundtrip (Output, Zlib.Zlib_Header, Input, "Auto large roundtrip");
   end Test_Auto_Large_Payload_Roundtrips;

   procedure Test_Auto_Output_Deterministic
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input   : constant Zlib.Byte_Array (1 .. 256) := [others => Zlib.Byte (Character'Pos ('D'))];
      Status1 : Zlib.Status_Code;
      Status2 : Zlib.Status_Code;
      One     : constant Zlib.Byte_Array := Zlib.Deflate (Input, Zlib.Auto, Status1);
      Two     : constant Zlib.Byte_Array := Zlib.Deflate (Input, Zlib.Auto, Status2);
   begin
      Assert (Status1 = Zlib.Ok and then Status2 = Zlib.Ok,
              "Auto deterministic compression runs must succeed");
      Assert (Same_Bytes (One, Two), "Auto output must be byte-identical across repeated runs");
   end Test_Auto_Output_Deterministic;

   procedure Test_Auto_Zlib_GZip_Raw_Roundtrip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input  : constant Zlib.Byte_Array (1 .. 300) := [others => Zlib.Byte (Character'Pos ('W'))];
      Status : Zlib.Status_Code;
   begin
      declare
         Zlib_Out : constant Zlib.Byte_Array := Zlib.Deflate (Input, Zlib.Auto, Status);
      begin
         Assert (Status = Zlib.Ok, "zlib Auto compression must succeed");
         Assert_Roundtrip (Zlib_Out, Zlib.Zlib_Header, Input, "zlib Auto roundtrip");
      end;

      declare
         GZip_Out : constant Zlib.Byte_Array := Zlib.GZip (Input, Zlib.Auto, Status);
      begin
         Assert (Status = Zlib.Ok, "gzip Auto compression must succeed");
         Assert_Roundtrip (GZip_Out, Zlib.GZip, Input, "gzip Auto roundtrip");
      end;

      declare
         Raw_Out : constant Zlib.Byte_Array := Zlib.Deflate_Raw (Input, Zlib.Auto, Status);
      begin
         Assert (Status = Zlib.Ok, "raw Auto compression must succeed");
         Assert_Roundtrip (Raw_Out, Zlib.Raw_Deflate, Input, "raw Auto roundtrip");
      end;
   end Test_Auto_Zlib_GZip_Raw_Roundtrip;

   procedure Test_Auto_Wrong_Wrapper_Unchanged
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input  : constant Zlib.Byte_Array (1 .. 64) := [others => Zlib.Byte (Character'Pos ('X'))];
      Status : Zlib.Status_Code;
      GZ     : constant Zlib.Byte_Array := Zlib.GZip (Input, Zlib.Auto, Status);
   begin
      Assert (Status = Zlib.Ok, "gzip Auto setup must succeed");
      declare
         Bad : constant Zlib.Byte_Array := Zlib.Inflate_With_Header (GZ, Zlib.Zlib_Header, Status);
         pragma Unreferenced (Bad);
      begin
         Assert (Status /= Zlib.Ok, "gzip Auto output must still be rejected by zlib-wrapper inflate");
      end;
   end Test_Auto_Wrong_Wrapper_Unchanged;

   procedure Test_Level_0_Remains_Stored
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input  : constant Zlib.Byte_Array := [1 => 1, 2 => 2, 3 => 3];
      Status : Zlib.Status_Code;
      Raw    : constant Zlib.Byte_Array := Zlib.Deflate_Raw (Input, Zlib.Compression_Level'(0), Status);
   begin
      Assert (Status = Zlib.Ok, "level 0 raw compression must succeed");
      Assert (Raw'Length >= 1 and then Raw (Raw'First) = 16#01#,
              "level 0 raw output must start with a final stored block header");
      Assert_Roundtrip (Raw, Zlib.Raw_Deflate, Input, "level 0 raw roundtrip");
   end Test_Level_0_Remains_Stored;

   procedure Test_Level_1_Policy_Documented_And_Tested
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input  : constant Zlib.Byte_Array := [1 => 1, 2 => 2, 3 => 3];
      Status : Zlib.Status_Code;
      Raw    : constant Zlib.Byte_Array := Zlib.Deflate_Raw (Input, Zlib.Compression_Level'(1), Status);
   begin
      Assert (Status = Zlib.Ok, "level 1 raw compression must succeed");
      Assert (Raw'Length >= 1 and then (Natural (Raw (Raw'First)) mod 8) = 3,
              "level 1 raw output must start with a final fixed-Huffman block header");
      Assert_Roundtrip (Raw, Zlib.Raw_Deflate, Input, "level 1 raw roundtrip");
   end Test_Level_1_Policy_Documented_And_Tested;

   procedure Test_Level_6_Uses_Chooser_And_Roundtrips
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input  : constant Zlib.Byte_Array (1 .. 512) := [others => Zlib.Byte (Character'Pos ('C'))];
      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array := Zlib.Deflate (Input, Zlib.Compression_Level'(6), Status);
   begin
      Assert (Status = Zlib.Ok, "level 6 Auto compression must succeed");
      Assert_Roundtrip (Output, Zlib.Zlib_Header, Input, "level 6 chooser roundtrip");
   end Test_Level_6_Uses_Chooser_And_Roundtrips;

   procedure Test_Sync_Flush_With_Auto_Emits_Valid_Stream
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input  : constant Zlib.Byte_Array (1 .. 100) := [others => Zlib.Byte (Character'Pos ('S'))];
      Output : constant Zlib.Byte_Array := Streaming_Auto_With_Flush (Input, Zlib.Sync_Flush);
   begin
      Assert_Roundtrip (Output, Zlib.Zlib_Header, Input, "Auto Sync_Flush stream");
   end Test_Sync_Flush_With_Auto_Emits_Valid_Stream;

   procedure Test_Full_Flush_With_Auto_Emits_Valid_Stream
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input  : constant Zlib.Byte_Array (1 .. 100) := [others => Zlib.Byte (Character'Pos ('F'))];
      Output : constant Zlib.Byte_Array := Streaming_Auto_With_Flush (Input, Zlib.Full_Flush);
   begin
      Assert_Roundtrip (Output, Zlib.Zlib_Header, Input, "Auto Full_Flush stream");
   end Test_Full_Flush_With_Auto_Emits_Valid_Stream;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      package R renames AUnit.Test_Cases.Registration;
   begin
      R.Register_Routine (T, Test_Auto_Empty_Roundtrips'Access, "Auto empty roundtrips");
      R.Register_Routine (T, Test_Auto_Hello_Roundtrips'Access, "Auto hello roundtrips");
      R.Register_Routine (T, Test_Auto_Binary_Payload_Roundtrips'Access, "Auto binary payload roundtrips");
      R.Register_Routine (T, Test_Auto_Repeated_Payload_Roundtrips'Access, "Auto repeated payload roundtrips");
      R.Register_Routine (T, Test_Auto_Large_Payload_Roundtrips'Access, "Auto large payload roundtrips");
      R.Register_Routine (T, Test_Auto_Output_Deterministic'Access, "Auto output deterministic across repeated runs");
      R.Register_Routine (T, Test_Auto_Zlib_GZip_Raw_Roundtrip'Access, "Auto zlib/gzip/raw all roundtrip");
      R.Register_Routine (T, Test_Auto_Wrong_Wrapper_Unchanged'Access, "Auto wrong-wrapper behavior unchanged");
      R.Register_Routine (T, Test_Level_0_Remains_Stored'Access, "Level 0 remains stored");
      R.Register_Routine (T, Test_Level_1_Policy_Documented_And_Tested'Access, "Level 1 policy documented and tested");
      R.Register_Routine (T, Test_Level_6_Uses_Chooser_And_Roundtrips'Access, "Level 6 uses chooser and roundtrips");
      R.Register_Routine
        (T, Test_Sync_Flush_With_Auto_Emits_Valid_Stream'Access,
         "Sync_Flush with Auto emits valid stream");
      R.Register_Routine
        (T, Test_Full_Flush_With_Auto_Emits_Valid_Stream'Access,
         "Full_Flush with Auto emits valid stream");
   end Register_Tests;

end Zlib_Auto_Block_Selection_Tests;
