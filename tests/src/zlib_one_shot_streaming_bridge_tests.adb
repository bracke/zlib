with AUnit.Assertions; use AUnit.Assertions;
with Zlib;

package body Zlib_One_Shot_Streaming_Bridge_Tests is
   use type Zlib.Byte;
   use type Zlib.Status_Code;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib one-shot streaming bridge");
   end Name;

   procedure Assert_Bytes_Equal
     (Actual   : Zlib.Byte_Array;
      Expected : Zlib.Byte_Array;
      Message  : String)
   is
   begin
      Assert
        (Actual'Length = Expected'Length,
         Message & ": output length mismatch");

      for I in Expected'Range loop
         Assert
           (Actual (Actual'First + (I - Expected'First)) = Expected (I),
            Message & ": output byte mismatch");
      end loop;
   end Assert_Bytes_Equal;

   procedure Test_Multiple_Output_Buffer_Drains
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Input  : Zlib.Byte_Array (1 .. 70_000);
      Status : Zlib.Status_Code;
   begin
      for I in Input'Range loop
         Input (I) := Zlib.Byte (I mod 251);
      end loop;

      declare
         Encoded : constant Zlib.Byte_Array := Zlib.Deflate_Stored (Input, Status);
      begin
         Assert (Status = Zlib.Ok, "stored deflate fixture creation must succeed");

         declare
            Output : constant Zlib.Byte_Array := Zlib.Inflate (Encoded, Status);
         begin
            Assert
              (Status = Zlib.Ok,
               "one-shot bridge must inflate data larger than one drain buffer");
            Assert_Bytes_Equal
              (Output,
               Input,
               "one-shot bridge must preserve large stored payload");
         end;
      end;
   end Test_Multiple_Output_Buffer_Drains;

   procedure Test_Invalid_Header_Status
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Input : constant Zlib.Byte_Array :=
        [1 => 16#78#,
         2 => 16#02#,
         3 => 16#00#,
         4 => 16#00#,
         5 => 16#00#,
         6 => 16#00#];

      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Input, Zlib.Zlib_Header, Status);
      pragma Unreferenced (Output);
   begin
      Assert
        (Status = Zlib.Invalid_Header,
         "one-shot bridge must map bad zlib header to Invalid_Header");
   end Test_Invalid_Header_Status;

   procedure Test_Invalid_Checksum_Status
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Input : constant Zlib.Byte_Array :=
        [1  => 16#78#,
         2  => 16#01#,
         3  => 16#01#,
         4  => 16#05#,
         5  => 16#00#,
         6  => 16#FA#,
         7  => 16#FF#,
         8  => Zlib.Byte (Character'Pos ('h')),
         9  => Zlib.Byte (Character'Pos ('e')),
         10 => Zlib.Byte (Character'Pos ('l')),
         11 => Zlib.Byte (Character'Pos ('l')),
         12 => Zlib.Byte (Character'Pos ('o')),
         13 => 16#00#,
         14 => 16#00#,
         15 => 16#00#,
         16 => 16#01#];

      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array := Zlib.Inflate (Input, Status);
      pragma Unreferenced (Output);
   begin
      Assert
        (Status = Zlib.Invalid_Checksum,
         "one-shot bridge must map bad Adler-32 to Invalid_Checksum");
   end Test_Invalid_Checksum_Status;

   procedure Test_Truncated_Status
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Input  : constant Zlib.Byte_Array := [1 => 16#78#, 2 => 16#01#, 3 => 16#01#];
      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array := Zlib.Inflate (Input, Status);
      pragma Unreferenced (Output);
   begin
      Assert
        (Status = Zlib.Unexpected_End_Of_Input,
         "one-shot bridge must map Finish truncation to Unexpected_End_Of_Input");
   end Test_Truncated_Status;

   procedure Test_Dynamic_Git_Like_Fixture
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Input : constant Zlib.Byte_Array :=
        [1  => 16#78#, 2  => 16#9C#, 3  => 16#4B#, 4  => 16#CA#,
         5  => 16#C9#, 6  => 16#4F#, 7  => 16#52#, 8  => 16#30#,
         9  => 16#34#, 10 => 16#62#, 11 => 16#C8#, 12 => 16#48#,
         13 => 16#CD#, 14 => 16#C9#, 15 => 16#C9#, 16 => 16#57#,
         17 => 16#28#, 18 => 16#CF#, 19 => 16#2F#, 20 => 16#CA#,
         21 => 16#49#, 22 => 16#E1#, 23 => 16#02#, 24 => 16#00#,
         25 => 16#44#, 26 => 16#11#, 27 => 16#06#, 28 => 16#89#];

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
      Assert (Status = Zlib.Ok, "dynamic Git-like fixture must inflate through bridge");
      Assert_Bytes_Equal (Output, Expected, "dynamic Git-like fixture");
   end Test_Dynamic_Git_Like_Fixture;

   procedure Test_Fixed_Overlapping_LZ77_Fixture
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Input : constant Zlib.Byte_Array :=
        [1  => 16#78#, 2  => 16#9C#, 3  => 16#4B#, 4  => 16#4C#,
         5  => 16#C4#, 6  => 16#0F#, 7  => 16#00#, 8  => 16#C8#,
         9  => 16#30#, 10 => 16#0C#, 11 => 16#21#];

      Expected : Zlib.Byte_Array (1 .. 32);
      Status   : Zlib.Status_Code;
      Output   : constant Zlib.Byte_Array := Zlib.Inflate (Input, Status);
   begin
      for I in Expected'Range loop
         Expected (I) := Zlib.Byte (Character'Pos ('a'));
      end loop;

      Assert (Status = Zlib.Ok, "fixed overlapping fixture must inflate through bridge");
      Assert_Bytes_Equal (Output, Expected, "fixed overlapping fixture");
   end Test_Fixed_Overlapping_LZ77_Fixture;

   procedure Test_Binary_Bytes_Preserved
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Input : constant Zlib.Byte_Array :=
        [1 => 16#00#, 2 => 16#80#, 3 => 16#FF#, 4 => 16#0D#,
         5 => 16#0A#, 6 => 16#41#, 7 => 16#00#, 8 => 16#FE#];
      Status : Zlib.Status_Code;
   begin
      declare
         Encoded : constant Zlib.Byte_Array := Zlib.Deflate_Stored (Input, Status);
      begin
         Assert (Status = Zlib.Ok, "stored binary fixture creation must succeed");

         declare
            Output : constant Zlib.Byte_Array := Zlib.Inflate (Encoded, Status);
         begin
            Assert (Status = Zlib.Ok, "binary fixture must inflate through bridge");
            Assert_Bytes_Equal (Output, Input, "binary fixture");
         end;
      end;
   end Test_Binary_Bytes_Preserved;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_Multiple_Output_Buffer_Drains'Access,
         "Inflate drains multiple output buffers through streaming bridge");
      Registration.Register_Routine
        (T, Test_Invalid_Header_Status'Access,
         "Inflate maps invalid zlib header through streaming bridge");
      Registration.Register_Routine
        (T, Test_Invalid_Checksum_Status'Access,
         "Inflate maps bad Adler through streaming bridge");
      Registration.Register_Routine
        (T, Test_Truncated_Status'Access,
         "Inflate maps truncation through streaming bridge");
      Registration.Register_Routine
        (T, Test_Dynamic_Git_Like_Fixture'Access,
         "Inflate dynamic Git-like fixture through streaming bridge");
      Registration.Register_Routine
        (T, Test_Fixed_Overlapping_LZ77_Fixture'Access,
         "Inflate fixed overlapping LZ77 fixture through streaming bridge");
      Registration.Register_Routine
        (T, Test_Binary_Bytes_Preserved'Access,
         "Inflate preserves binary bytes through streaming bridge");
   end Register_Tests;

end Zlib_One_Shot_Streaming_Bridge_Tests;
