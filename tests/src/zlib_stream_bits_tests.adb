with Ada.Streams; use Ada.Streams;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib.Stream_Bits;

package body Zlib_Stream_Bits_Tests is
   use type Zlib.Stream_Bits.Read_Status;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib.Stream_Bits");
   end Name;

   procedure Test_Reset_Clears_Source
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Source : Zlib.Stream_Bits.Bit_Source;
      Status : Zlib.Stream_Bits.Read_Status;
      Value  : Boolean;
   begin
      Zlib.Stream_Bits.Append (Source, [1 => 16#FF#]);
      Value := Zlib.Stream_Bits.Read_Bit (Source, Status);
      pragma Unreferenced (Value);
      Zlib.Stream_Bits.Reset (Source);

      Assert (Zlib.Stream_Bits.Buffered_Bytes (Source) = 0, "Reset must clear buffered bytes");
      Assert (Zlib.Stream_Bits.Input_Consumed (Source) = 0, "Reset must clear input-consumed accounting");
      Value := Zlib.Stream_Bits.Read_Bit (Source, Status);
      Assert (Status = Zlib.Stream_Bits.Need_Input, "Read_Bit after Reset must need input");
   end Test_Reset_Clears_Source;

   procedure Test_Append_Null_Input_Is_No_Op
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Source : Zlib.Stream_Bits.Bit_Source;
      Empty  : constant Ada.Streams.Stream_Element_Array (1 .. 0) := [];
   begin
      Zlib.Stream_Bits.Append (Source, Empty);
      Assert (Zlib.Stream_Bits.Buffered_Bytes (Source) = 0, "null Append must not buffer bytes");
      Assert (Zlib.Stream_Bits.Input_Consumed (Source) = 0, "null Append must not alter consumed count");
   end Test_Append_Null_Input_Is_No_Op;

   procedure Test_Read_Bit_Empty_Needs_Input
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Source : Zlib.Stream_Bits.Bit_Source;
      Status : Zlib.Stream_Bits.Read_Status;
      Value  : Boolean;
   begin
      Value := Zlib.Stream_Bits.Read_Bit (Source, Status);
      Assert (not Value, "Read_Bit on empty source returns False as dummy value");
      Assert (Status = Zlib.Stream_Bits.Need_Input, "Read_Bit on empty source must return Need_Input");
   end Test_Read_Bit_Empty_Needs_Input;

   procedure Test_Read_Bit_Lsb_First
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Source : Zlib.Stream_Bits.Bit_Source;
      Status : Zlib.Stream_Bits.Read_Status;
   begin
      Zlib.Stream_Bits.Append (Source, [1 => 2#1010_0101#]);

      Assert (Zlib.Stream_Bits.Read_Bit (Source, Status), "bit 0 must be 1");
      Assert (Status = Zlib.Stream_Bits.Ok, "bit 0 status must be Ok");
      Assert (not Zlib.Stream_Bits.Read_Bit (Source, Status), "bit 1 must be 0");
      Assert (Zlib.Stream_Bits.Read_Bit (Source, Status), "bit 2 must be 1");
      Assert (not Zlib.Stream_Bits.Read_Bit (Source, Status), "bit 3 must be 0");
   end Test_Read_Bit_Lsb_First;

   procedure Test_Read_Bits_Crosses_Byte_Boundary
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Source : Zlib.Stream_Bits.Bit_Source;
      Status : Zlib.Stream_Bits.Read_Status;
      Value  : Natural;
   begin
      Zlib.Stream_Bits.Append (Source, [1 => 16#F0#, 2 => 16#0A#]);
      Value := Zlib.Stream_Bits.Read_Bits (Source, 12, Status);
      Assert (Status = Zlib.Stream_Bits.Ok, "12-bit read across byte boundary must succeed");
      Assert (Value = 16#AF0#, "12 LSB-first bits from F0 0A must produce 0xAF0");
   end Test_Read_Bits_Crosses_Byte_Boundary;

   procedure Test_Read_Bits_Resumes_After_Appending_Input
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Source : Zlib.Stream_Bits.Bit_Source;
      Status : Zlib.Stream_Bits.Read_Status;
      Value  : Natural;
   begin
      Zlib.Stream_Bits.Append (Source, [1 => 16#F0#]);
      Value := Zlib.Stream_Bits.Read_Bits (Source, 12, Status);
      Assert (Status = Zlib.Stream_Bits.Need_Input, "insufficient atomic multi-bit read must return Need_Input");
      Assert (Value = 0, "failed multi-bit read must return dummy zero");

      Zlib.Stream_Bits.Append (Source, [1 => 16#0A#]);
      Value := Zlib.Stream_Bits.Read_Bits (Source, 12, Status);
      Assert (Status = Zlib.Stream_Bits.Ok, "12-bit read must succeed after more input arrives");
      Assert (Value = 16#AF0#, "stream must resume after append without losing first byte");
   end Test_Read_Bits_Resumes_After_Appending_Input;

   procedure Test_Partial_Byte_State_Survives_Append
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Source : Zlib.Stream_Bits.Bit_Source;
      Status : Zlib.Stream_Bits.Read_Status;
      Value  : Natural;
   begin
      Zlib.Stream_Bits.Append (Source, [1 => 2#1010_0101#]);
      Value := Zlib.Stream_Bits.Read_Bits (Source, 3, Status);
      Assert (Value = 5, "first three LSB-first bits of 0xA5 must be 5");

      Zlib.Stream_Bits.Append (Source, [1 => 16#FF#]);
      Value := Zlib.Stream_Bits.Read_Bits (Source, 5, Status);
      Assert (Status = Zlib.Stream_Bits.Ok, "remaining current-byte bits must still be readable after append");
      Assert (Value = 20, "next five bits from bit index 3 of 0xA5 must be 20");
      Assert
        (Zlib.Stream_Bits.Buffered_Bytes (Source) = 1,
         "fully consumed prefix must be discarded after completing partial byte");
   end Test_Partial_Byte_State_Survives_Append;

   procedure Test_Align_To_Byte_Skips_Remaining_Bits
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Source : Zlib.Stream_Bits.Bit_Source;
      Status : Zlib.Stream_Bits.Read_Status;
      Value  : Natural;
      Byte   : Ada.Streams.Stream_Element;
   begin
      Zlib.Stream_Bits.Append (Source, [1 => 16#FF#, 2 => 16#12#]);
      Value := Zlib.Stream_Bits.Read_Bits (Source, 3, Status);
      Assert (Value = 7, "initial three one bits must read as 7");
      Zlib.Stream_Bits.Align_To_Byte (Source);
      Byte := Zlib.Stream_Bits.Read_Byte_Aligned (Source, Status);
      Assert (Status = Zlib.Stream_Bits.Ok, "byte-aligned read after Align_To_Byte must succeed");
      Assert (Byte = 16#12#, "Align_To_Byte must skip the rest of the current byte");
   end Test_Align_To_Byte_Skips_Remaining_Bits;

   procedure Test_Read_Byte_Aligned_Requires_Alignment
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Source : Zlib.Stream_Bits.Bit_Source;
      Status : Zlib.Stream_Bits.Read_Status;
      Bit    : Boolean;
      Byte   : Ada.Streams.Stream_Element;
   begin
      Zlib.Stream_Bits.Append (Source, [1 => 16#AA#]);
      Bit := Zlib.Stream_Bits.Read_Bit (Source, Status);
      pragma Unreferenced (Bit);
      Byte := Zlib.Stream_Bits.Read_Byte_Aligned (Source, Status);
      pragma Unreferenced (Byte);
      Assert (Status = Zlib.Stream_Bits.Invalid_State, "Read_Byte_Aligned must reject partial-byte state");
   end Test_Read_Byte_Aligned_Requires_Alignment;

   procedure Test_Consumed_Bytes_Are_Tracked
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Source : Zlib.Stream_Bits.Bit_Source;
      Status : Zlib.Stream_Bits.Read_Status;
      Value  : Natural;
   begin
      Zlib.Stream_Bits.Append (Source, [1 => 16#01#, 2 => 16#02#]);
      Value := Zlib.Stream_Bits.Read_Bits (Source, 4, Status);
      pragma Unreferenced (Value);
      Assert (Zlib.Stream_Bits.Input_Consumed (Source) = 0, "partial byte must not count as consumed input");
      Value := Zlib.Stream_Bits.Read_Bits (Source, 4, Status);
      Assert (Zlib.Stream_Bits.Input_Consumed (Source) = 1, "completed first byte must count as consumed input");
      Value := Zlib.Stream_Bits.Read_Bits (Source, 8, Status);
      Assert (Zlib.Stream_Bits.Input_Consumed (Source) = 2, "second completed byte must count as consumed input");
   end Test_Consumed_Bytes_Are_Tracked;

   procedure Test_Consumed_Prefix_Is_Discarded
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Source : Zlib.Stream_Bits.Bit_Source;
      Status : Zlib.Stream_Bits.Read_Status;
      Byte   : Ada.Streams.Stream_Element;
   begin
      Zlib.Stream_Bits.Append (Source, [1 => 1, 2 => 2, 3 => 3]);
      Byte := Zlib.Stream_Bits.Read_Byte_Aligned (Source, Status);
      Assert (Status = Zlib.Stream_Bits.Ok and then Byte = 1,
              "first byte-aligned read should consume first byte");
      Byte := Zlib.Stream_Bits.Read_Byte_Aligned (Source, Status);
      Assert (Status = Zlib.Stream_Bits.Ok and then Byte = 2,
              "second byte-aligned read should consume second byte");
      Assert (Zlib.Stream_Bits.Buffered_Bytes (Source) = 1,
              "consumed prefix must be discarded/compacted");
      Zlib.Stream_Bits.Append (Source, [1 => 4]);
      Assert
        (Zlib.Stream_Bits.Buffered_Bytes (Source) = 2,
         "append after compaction must preserve remaining bytes only");
   end Test_Consumed_Prefix_Is_Discarded;

   procedure Test_Buffer_Reuses_Capacity_After_Consumption
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Source : Zlib.Stream_Bits.Bit_Source;
      Status : Zlib.Stream_Bits.Read_Status;
      Data   : Ada.Streams.Stream_Element_Array (1 .. 32_768);
      Byte   : Ada.Streams.Stream_Element;
   begin
      for I in Data'Range loop
         Data (I) := Ada.Streams.Stream_Element (Natural (I mod 251));
      end loop;

      Zlib.Stream_Bits.Append (Source, Data);

      for I in 1 .. 20_000 loop
         pragma Unreferenced (I);
         Byte := Zlib.Stream_Bits.Read_Byte_Aligned (Source, Status);
         Assert (Status = Zlib.Stream_Bits.Ok,
                 "buffer-capacity setup read must succeed");
      end loop;

      Zlib.Stream_Bits.Append (Source, [1 => 99]);
      Assert
        (Zlib.Stream_Bits.Buffered_Bytes (Source) = 12_769,
         "append after deferred consumption must reuse bounded storage");

      for I in 1 .. 12_768 loop
         pragma Unreferenced (I);
         Byte := Zlib.Stream_Bits.Read_Byte_Aligned (Source, Status);
         Assert (Status = Zlib.Stream_Bits.Ok,
                 "remaining original bytes must still be readable");
      end loop;

      Byte := Zlib.Stream_Bits.Read_Byte_Aligned (Source, Status);
      Assert (Status = Zlib.Stream_Bits.Ok,
              "appended byte after deferred compaction must be readable");
      Assert (Byte = 99,
              "appended byte must appear after preserved original suffix");
   end Test_Buffer_Reuses_Capacity_After_Consumption;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_Reset_Clears_Source'Access, "Reset clears source");
      Registration.Register_Routine
        (T, Test_Append_Null_Input_Is_No_Op'Access, "Append null input is no-op");
      Registration.Register_Routine
        (T, Test_Read_Bit_Empty_Needs_Input'Access, "Read_Bit needs input when empty");
      Registration.Register_Routine
        (T, Test_Read_Bit_Lsb_First'Access, "Read_Bit reads LSB-first");
      Registration.Register_Routine
        (T, Test_Read_Bits_Crosses_Byte_Boundary'Access, "Read_Bits crosses byte boundary");
      Registration.Register_Routine
        (T,
         Test_Read_Bits_Resumes_After_Appending_Input'Access,
         "Read_Bits resumes after append");
      Registration.Register_Routine
        (T,
         Test_Partial_Byte_State_Survives_Append'Access,
         "Partial byte state survives append");
      Registration.Register_Routine
        (T,
         Test_Align_To_Byte_Skips_Remaining_Bits'Access,
         "Align_To_Byte skips remaining bits");
      Registration.Register_Routine
        (T,
         Test_Read_Byte_Aligned_Requires_Alignment'Access,
         "Read_Byte_Aligned requires alignment");
      Registration.Register_Routine
        (T, Test_Consumed_Bytes_Are_Tracked'Access, "Consumed bytes are tracked");
      Registration.Register_Routine
        (T,
         Test_Consumed_Prefix_Is_Discarded'Access,
         "Consumed prefix can be discarded");
      Registration.Register_Routine
        (T,
         Test_Buffer_Reuses_Capacity_After_Consumption'Access,
         "Consumed prefix reuses bounded input storage");
   end Register_Tests;

end Zlib_Stream_Bits_Tests;
