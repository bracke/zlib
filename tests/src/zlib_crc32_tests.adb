with Ada.Streams;
with AUnit.Assertions; use AUnit.Assertions;
with Interfaces;
with Zlib.CRC32_Internal;

package body Zlib_CRC32_Tests is
   use type Interfaces.Unsigned_32;

   overriding
   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib.CRC32_Internal");
   end Name;

   function Bytes (S : String) return Ada.Streams.Stream_Element_Array is
      Result : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (S'Length));
   begin
      for I in S'Range loop
         Result (Ada.Streams.Stream_Element_Offset (I - S'First + 1)) :=
           Ada.Streams.Stream_Element (Character'Pos (S (I)));
      end loop;
      return Result;
   end Bytes;

   function CRC32_Of
     (Data : Ada.Streams.Stream_Element_Array)
      return Interfaces.Unsigned_32
   is
      State : Zlib.CRC32_Internal.CRC32_State;
   begin
      Zlib.CRC32_Internal.Reset (State);
      Zlib.CRC32_Internal.Update (State, Data);
      return Zlib.CRC32_Internal.Value (State);
   end CRC32_Of;

   procedure Test_CRC32_Empty (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Data : constant Ada.Streams.Stream_Element_Array (1 .. 0) := [];
   begin
      Assert (CRC32_Of (Data) = 16#0000_0000#,
              "CRC32 of empty input must be 0x00000000");
   end Test_CRC32_Empty;

   procedure Test_CRC32_Hello (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (CRC32_Of (Bytes ("hello")) = 16#3610_A686#,
              "CRC32 of hello must be 0x3610A686");
   end Test_CRC32_Hello;

   procedure Test_CRC32_Digits (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (CRC32_Of (Bytes ("123456789")) = 16#CBF4_3926#,
              "CRC32 of 123456789 must be 0xCBF43926");
   end Test_CRC32_Digits;

   procedure Test_Incremental_Equals_Array
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Data       : constant Ada.Streams.Stream_Element_Array := Bytes ("streaming gzip");
      Whole      : constant Interfaces.Unsigned_32 := CRC32_Of (Data);
      Incremental : Zlib.CRC32_Internal.CRC32_State;
   begin
      Zlib.CRC32_Internal.Reset (Incremental);
      for I in Data'Range loop
         Zlib.CRC32_Internal.Update (Incremental, Data (I));
      end loop;

      Assert (Zlib.CRC32_Internal.Value (Incremental) = Whole,
              "byte-by-byte CRC32 must match whole-array update");
   end Test_Incremental_Equals_Array;

   overriding
   procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine (T, Test_CRC32_Empty'Access, "CRC32 empty");
      Registration.Register_Routine (T, Test_CRC32_Hello'Access, "CRC32 hello");
      Registration.Register_Routine (T, Test_CRC32_Digits'Access, "CRC32 123456789");
      Registration.Register_Routine (T, Test_Incremental_Equals_Array'Access,
                                     "CRC32 incremental equals whole array");
   end Register_Tests;
end Zlib_CRC32_Tests;
