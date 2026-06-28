with AUnit.Assertions; use AUnit.Assertions;
with Interfaces;
with Zlib;
with Zlib.Checksums;

package body Zlib_Checksums_Tests is
   use type Interfaces.Unsigned_32;

   overriding
   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib.Checksums");
   end Name;

   procedure Test_Adler32_Empty (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Data : constant Zlib.Byte_Array (1 .. 0) := [others => 0];
   begin
      Assert
        (Zlib.Checksums.Adler32 (Data) = 16#0000_0001#,
         "Adler-32 of empty input must be 0x00000001");
   end Test_Adler32_Empty;

   procedure Test_Adler32_Hello (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Data : constant Zlib.Byte_Array :=
        [1 => Zlib.Byte (Character'Pos ('h')),
         2 => Zlib.Byte (Character'Pos ('e')),
         3 => Zlib.Byte (Character'Pos ('l')),
         4 => Zlib.Byte (Character'Pos ('l')),
         5 => Zlib.Byte (Character'Pos ('o'))];
   begin
      Assert
        (Zlib.Checksums.Adler32 (Data) = 16#062C_0215#,
         "Adler-32 of ""hello"" must be 0x062C0215");
   end Test_Adler32_Hello;

   procedure Test_Adler32_Wikipedia
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Data : constant Zlib.Byte_Array :=
        [1 => Zlib.Byte (Character'Pos ('W')),
         2 => Zlib.Byte (Character'Pos ('i')),
         3 => Zlib.Byte (Character'Pos ('k')),
         4 => Zlib.Byte (Character'Pos ('i')),
         5 => Zlib.Byte (Character'Pos ('p')),
         6 => Zlib.Byte (Character'Pos ('e')),
         7 => Zlib.Byte (Character'Pos ('d')),
         8 => Zlib.Byte (Character'Pos ('i')),
         9 => Zlib.Byte (Character'Pos ('a'))];
   begin
      Assert
        (Zlib.Checksums.Adler32 (Data) = 16#11E6_0398#,
         "Adler-32 of ""Wikipedia"" must be 0x11E60398");
   end Test_Adler32_Wikipedia;

   procedure Test_Adler32_Incremental_Matches_One_Shot
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Data : constant Zlib.Byte_Array :=
        [1 => Zlib.Byte (Character'Pos ('s')),
         2 => Zlib.Byte (Character'Pos ('t')),
         3 => Zlib.Byte (Character'Pos ('r')),
         4 => Zlib.Byte (Character'Pos ('e')),
         5 => Zlib.Byte (Character'Pos ('a')),
         6 => Zlib.Byte (Character'Pos ('m'))];
      State : Zlib.Checksums.Adler32_State;
   begin
      Zlib.Checksums.Reset (State);

      for I in Data'Range loop
         Zlib.Checksums.Update (State, Data (I));
      end loop;

      Assert
        (Zlib.Checksums.Value (State) = Zlib.Checksums.Adler32 (Data),
         "incremental Adler-32 must match one-shot Adler-32");
   end Test_Adler32_Incremental_Matches_One_Shot;

   overriding
   procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_Adler32_Empty'Access, "Adler-32 empty input");

      Registration.Register_Routine
        (T, Test_Adler32_Hello'Access, "Adler-32 hello");

      Registration.Register_Routine
        (T, Test_Adler32_Wikipedia'Access, "Adler-32 Wikipedia");

      Registration.Register_Routine
        (T, Test_Adler32_Incremental_Matches_One_Shot'Access,
         "incremental Adler-32 matches one-shot");
   end Register_Tests;
end Zlib_Checksums_Tests;
