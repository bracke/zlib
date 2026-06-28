with AUnit.Assertions; use AUnit.Assertions;
with Zlib;

package body Zlib_Git_Fixture_Tests is
   use type Zlib.Byte;
   use type Zlib.Status_Code;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib Git fixture");
   end Name;

   Payload : constant Zlib.Byte_Array :=
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

   procedure Assert_Payload
     (Actual : Zlib.Byte_Array;
      Label  : String)
   is
   begin
      Assert
        (Actual'Length = Payload'Length,
         Label & " payload length must match");

      for I in Payload'Range loop
         Assert
           (Actual (I) = Payload (I),
            Label & " payload byte mismatch");
      end loop;
   end Assert_Payload;

   procedure Test_Git_Shaped_Frozen_Dynamic_Fixture
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
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

      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array := Zlib.Inflate (Input, Status);
   begin
      Assert
        (Status = Zlib.Ok,
         "frozen Git-shaped zlib fixture must inflate successfully");

      Assert_Payload (Output, "frozen Git-shaped fixture");
   end Test_Git_Shaped_Frozen_Dynamic_Fixture;

   procedure Test_Git_Blob_Roundtrip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Def_Status : Zlib.Status_Code;
      Inf_Status : Zlib.Status_Code;

      Compressed : constant Zlib.Byte_Array :=
        Zlib.Deflate_Stored (Payload, Def_Status);

      Output : constant Zlib.Byte_Array :=
        Zlib.Inflate (Compressed, Inf_Status);
   begin
      Assert
        (Def_Status = Zlib.Ok,
         "Deflate_Stored must succeed for Git payload");

      Assert
        (Inf_Status = Zlib.Ok,
         "Inflate must succeed for Git payload");

      Assert_Payload (Output, "stored Git roundtrip");
   end Test_Git_Blob_Roundtrip;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T,
         Test_Git_Shaped_Frozen_Dynamic_Fixture'Access,
         "Inflate frozen Git-shaped zlib fixture");

      Registration.Register_Routine
        (T,
         Test_Git_Blob_Roundtrip'Access,
         "Roundtrip Git-style blob payload");
   end Register_Tests;

end Zlib_Git_Fixture_Tests;
