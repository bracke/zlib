with AUnit.Assertions; use AUnit.Assertions;
with Zlib;

package body Zlib_Deflate_Stored_Tests is
   use type Zlib.Byte;
   use type Zlib.Status_Code;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib.Deflate_Stored");
   end Name;

   procedure Assert_Same
     (Actual   : Zlib.Byte_Array;
      Expected : Zlib.Byte_Array;
      Message  : String)
   is
   begin
      Assert
        (Actual'Length = Expected'Length,
         Message & ": length mismatch");

      for I in Expected'Range loop
         Assert
           (Actual (Actual'First + (I - Expected'First)) = Expected (I),
            Message & ": byte mismatch");
      end loop;
   end Assert_Same;

   procedure Test_Roundtrip_Empty (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array (1 .. 0) := [others => 0];

      Deflate_Status : Zlib.Status_Code;
      Inflate_Status : Zlib.Status_Code;

      Compressed : constant Zlib.Byte_Array :=
        Zlib.Deflate_Stored (Input, Deflate_Status);

      Output : constant Zlib.Byte_Array :=
        Zlib.Inflate (Compressed, Inflate_Status);
   begin
      Assert
        (Deflate_Status = Zlib.Ok,
         "Deflate_Stored must accept empty input");

      Assert
        (Inflate_Status = Zlib.Ok,
         "Inflate must accept stored empty stream");

      Assert
        (Output'Length = 0,
         "empty roundtrip output must be empty");
   end Test_Roundtrip_Empty;

   procedure Test_Roundtrip_Hello (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array :=
        [1 => Zlib.Byte (Character'Pos ('h')),
         2 => Zlib.Byte (Character'Pos ('e')),
         3 => Zlib.Byte (Character'Pos ('l')),
         4 => Zlib.Byte (Character'Pos ('l')),
         5 => Zlib.Byte (Character'Pos ('o'))];

      Deflate_Status : Zlib.Status_Code;
      Inflate_Status : Zlib.Status_Code;

      Compressed : constant Zlib.Byte_Array :=
        Zlib.Deflate_Stored (Input, Deflate_Status);

      Output : constant Zlib.Byte_Array :=
        Zlib.Inflate (Compressed, Inflate_Status);
   begin
      Assert
        (Deflate_Status = Zlib.Ok,
         "Deflate_Stored must accept hello input");

      Assert
        (Inflate_Status = Zlib.Ok,
         "Inflate must accept stored hello stream");

      Assert_Same
        (Actual   => Output,
         Expected => Input,
         Message  => "stored hello roundtrip");
   end Test_Roundtrip_Hello;

   procedure Test_Roundtrip_Large_Input (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Input : Zlib.Byte_Array (1 .. 70_000);

      Deflate_Status : Zlib.Status_Code;
      Inflate_Status : Zlib.Status_Code;
   begin
      for I in Input'Range loop
         Input (I) := Zlib.Byte (I mod 251);
      end loop;

      declare
         Compressed : constant Zlib.Byte_Array :=
           Zlib.Deflate_Stored (Input, Deflate_Status);

         Output : constant Zlib.Byte_Array :=
           Zlib.Inflate (Compressed, Inflate_Status);
      begin
         Assert
           (Deflate_Status = Zlib.Ok,
            "Deflate_Stored must accept input larger than one stored block");

         Assert
           (Inflate_Status = Zlib.Ok,
            "Inflate must accept multi-block stored stream");

         Assert_Same
           (Actual   => Output,
            Expected => Input,
            Message  => "large stored roundtrip");
      end;
   end Test_Roundtrip_Large_Input;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_Roundtrip_Empty'Access,
         "Deflate_Stored roundtrip empty");

      Registration.Register_Routine
        (T, Test_Roundtrip_Hello'Access,
         "Deflate_Stored roundtrip hello");

      Registration.Register_Routine
        (T, Test_Roundtrip_Large_Input'Access,
         "Deflate_Stored roundtrip large input");
   end Register_Tests;

end Zlib_Deflate_Stored_Tests;
