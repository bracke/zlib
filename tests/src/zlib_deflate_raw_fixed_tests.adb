with AUnit.Assertions; use AUnit.Assertions;
with Zlib;

package body Zlib_Deflate_Raw_Fixed_Tests is
   use type Zlib.Byte;
   use type Zlib.Status_Code;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib one-shot raw fixed Deflate compression");
   end Name;

   function Empty return Zlib.Byte_Array is
      Result : constant Zlib.Byte_Array (1 .. 0) := [others => 0];
   begin
      return Result;
   end Empty;

   function Hello return Zlib.Byte_Array is
   begin
      return
        [1 => Zlib.Byte (Character'Pos ('h')),
         2 => Zlib.Byte (Character'Pos ('e')),
         3 => Zlib.Byte (Character'Pos ('l')),
         4 => Zlib.Byte (Character'Pos ('l')),
         5 => Zlib.Byte (Character'Pos ('o'))];
   end Hello;

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

   procedure Assert_Roundtrip
     (Input   : Zlib.Byte_Array;
      Message : String)
   is
      Status     : Zlib.Status_Code := Zlib.Ok;
      Compressed : constant Zlib.Byte_Array :=
        Zlib.Deflate_Raw (Input, Zlib.Fixed, Status);
      Inflated_Status : Zlib.Status_Code := Zlib.Ok;
      Inflated : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Compressed, Zlib.Raw_Deflate, Inflated_Status);
      Zlib_Status : Zlib.Status_Code := Zlib.Ok;
      GZip_Status : Zlib.Status_Code := Zlib.Ok;
      Zlib_Attempt : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Compressed, Zlib.Zlib_Header, Zlib_Status);
      GZip_Attempt : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Compressed, Zlib.GZip, GZip_Status);
      pragma Unreferenced (Zlib_Attempt, GZip_Attempt);
   begin
      Assert (Status = Zlib.Ok, Message & ": Deflate_Raw Fixed status");
      Assert (Inflated_Status = Zlib.Ok, Message & ": raw inflate status");
      Assert_Same (Inflated, Input, Message & ": roundtrip");
      Assert (Zlib_Status /= Zlib.Ok, Message & ": rejected as zlib");
      Assert (GZip_Status /= Zlib.Ok, Message & ": rejected as gzip");
   end Assert_Roundtrip;

   procedure Test_Empty
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_Roundtrip (Empty, "empty raw fixed");
   end Test_Empty;

   procedure Test_Hello
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_Roundtrip (Hello, "hello raw fixed");
   end Test_Hello;

   procedure Test_Binary
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input : Zlib.Byte_Array (1 .. 512);
   begin
      for I in Input'Range loop
         Input (I) := Zlib.Byte ((I * 37) mod 256);
      end loop;
      Assert_Roundtrip (Input, "binary raw fixed");
   end Test_Binary;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine (T, Test_Empty'Access, "Deflate_Raw Fixed empty roundtrips");
      Registration.Register_Routine (T, Test_Hello'Access, "Deflate_Raw Fixed hello roundtrips");
      Registration.Register_Routine (T, Test_Binary'Access, "Deflate_Raw Fixed binary roundtrips");
   end Register_Tests;
end Zlib_Deflate_Raw_Fixed_Tests;
