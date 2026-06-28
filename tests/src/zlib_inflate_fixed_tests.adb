with AUnit.Assertions; use AUnit.Assertions;
with Zlib;

package body Zlib_Inflate_Fixed_Tests is
   use type Zlib.Byte;
   use type Zlib.Status_Code;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib.Inflate fixed Huffman");
   end Name;

   procedure Test_Inflate_Fixed_Hello (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);

      Input : constant Zlib.Byte_Array :=
        [1  => 16#78#,
         2  => 16#9C#,
         3  => 16#CB#,
         4  => 16#48#,
         5  => 16#CD#,
         6  => 16#C9#,
         7  => 16#C9#,
         8  => 16#07#,
         9  => 16#00#,
         10 => 16#06#,
         11 => 16#2C#,
         12 => 16#02#,
         13 => 16#15#];

      Expected : constant Zlib.Byte_Array :=
        [1 => Zlib.Byte (Character'Pos ('h')),
         2 => Zlib.Byte (Character'Pos ('e')),
         3 => Zlib.Byte (Character'Pos ('l')),
         4 => Zlib.Byte (Character'Pos ('l')),
         5 => Zlib.Byte (Character'Pos ('o'))];

      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array := Zlib.Inflate (Input, Status);
   begin
      Assert
        (Status = Zlib.Ok,
         "fixed-Huffman zlib stream must inflate successfully");

      Assert
        (Output'Length = Expected'Length,
         "fixed-Huffman output length must match expected length");

      for I in Expected'Range loop
         Assert
           (Output (I) = Expected (I),
            "fixed-Huffman output byte mismatch");
      end loop;
   end Test_Inflate_Fixed_Hello;

   procedure Test_Inflate_Fixed_Overlapping_Copy (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);

      Input : constant Zlib.Byte_Array :=
      [1  => 16#78#,
         2  => 16#9C#,
         3  => 16#4B#,
         4  => 16#4C#,
         5  => 16#C4#,
         6  => 16#0F#,
         7  => 16#00#,
         8  => 16#C8#,
         9  => 16#30#,
         10 => 16#0C#,
         11 => 16#21#];

      Expected : Zlib.Byte_Array (1 .. 32);

      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array := Zlib.Inflate (Input, Status);
   begin
      for I in Expected'Range loop
         Expected (I) := Zlib.Byte (Character'Pos ('a'));
      end loop;

      Assert
        (Status = Zlib.Ok,
         "fixed-Huffman overlapping-copy stream must inflate successfully");

      Assert
        (Output'Length = Expected'Length,
         "overlapping-copy output length must be 32");

      for I in Expected'Range loop
         Assert
           (Output (I) = Expected (I),
            "overlapping-copy output byte mismatch");
      end loop;
   end Test_Inflate_Fixed_Overlapping_Copy;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T,
         Test_Inflate_Fixed_Hello'Access,
         "Inflate fixed-Huffman hello");

      Registration.Register_Routine
        (T,
         Test_Inflate_Fixed_Overlapping_Copy'Access,
         "Inflate fixed-Huffman overlapping LZ77 copy");
   end Register_Tests;

end Zlib_Inflate_Fixed_Tests;
