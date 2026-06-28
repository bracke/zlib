with AUnit.Assertions; use AUnit.Assertions;
with Zlib;

package body Zlib_Inflate_Dynamic_Tests is
   use type Zlib.Byte;
   use type Zlib.Status_Code;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib.Inflate dynamic Huffman");
   end Name;

   procedure Test_Inflate_Dynamic_Git_Like_Blob (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);

      Input : constant Zlib.Byte_Array :=
         [1  => 16#78#,
            2  => 16#9C#,
            3  => 16#4B#,
            4  => 16#CA#,
            5  => 16#C9#,
            6  => 16#4F#,
            7  => 16#52#,
            8  => 16#30#,
            9  => 16#34#,
            10 => 16#62#,
            11 => 16#C8#,
            12 => 16#48#,
            13 => 16#CD#,
            14 => 16#C9#,
            15 => 16#C9#,
            16 => 16#57#,
            17 => 16#28#,
            18 => 16#CF#,
            19 => 16#2F#,
            20 => 16#CA#,
            21 => 16#49#,
            22 => 16#E1#,
            23 => 16#02#,
            24 => 16#00#,
            25 => 16#44#,
            26 => 16#11#,
            27 => 16#06#,
            28 => 16#89#];

      Expected : constant Zlib.Byte_Array :=
        [1  => Zlib.Byte (Character'Pos ('b')),
         2  => Zlib.Byte (Character'Pos ('l')),
         3  => Zlib.Byte (Character'Pos ('o')),
         4  => Zlib.Byte (Character'Pos ('b')),
         5  => Zlib.Byte (Character'Pos (' ')),
         6  => Zlib.Byte (Character'Pos ('1')),
         7  => Zlib.Byte (Character'Pos ('2')),
         8  => 16#00#,
         9  => Zlib.Byte (Character'Pos ('h')),
         10 => Zlib.Byte (Character'Pos ('e')),
         11 => Zlib.Byte (Character'Pos ('l')),
         12 => Zlib.Byte (Character'Pos ('l')),
         13 => Zlib.Byte (Character'Pos ('o')),
         14 => Zlib.Byte (Character'Pos (' ')),
         15 => Zlib.Byte (Character'Pos ('w')),
         16 => Zlib.Byte (Character'Pos ('o')),
         17 => Zlib.Byte (Character'Pos ('r')),
         18 => Zlib.Byte (Character'Pos ('l')),
         19 => Zlib.Byte (Character'Pos ('d')),
         20 => 16#0A#];

      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array := Zlib.Inflate (Input, Status);
   begin
      Assert
        (Status = Zlib.Ok,
         "dynamic-Huffman Git-like zlib stream must inflate successfully");

      Assert
        (Output'Length = Expected'Length,
         "dynamic-Huffman output length must match expected length");

      for I in Expected'Range loop
         Assert
           (Output (I) = Expected (I),
            "dynamic-Huffman output byte mismatch");
      end loop;
   end Test_Inflate_Dynamic_Git_Like_Blob;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T,
         Test_Inflate_Dynamic_Git_Like_Blob'Access,
         "Inflate Git loose-object-shaped zlib data");
   end Register_Tests;
end Zlib_Inflate_Dynamic_Tests;
