with AUnit.Assertions; use AUnit.Assertions;
with Zlib;
with Zlib.Block_Chooser;
with Zlib.LZ77_Matcher;

package body Zlib_Block_Chooser_Tests is
   use type Zlib.Block_Chooser.Block_Kind;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib.Block_Chooser");
   end Name;

   procedure Test_Stored_Size_Includes_Header_And_Len
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert (Zlib.Block_Chooser.Stored_Bit_Size (0) = 40,
              "empty stored block must include 3 header bits, padding, LEN, and NLEN");
      Assert (Zlib.Block_Chooser.Stored_Bit_Size (1) = 48,
              "one-byte stored block must include stored header overhead and 8 data bits");
   end Test_Stored_Size_Includes_Header_And_Len;

   procedure Test_Fixed_Size_Includes_EOB
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Empty_Input  : constant Zlib.Byte_Array (1 .. 0) := [others => 0];
      Tokens       : constant Zlib.LZ77_Matcher.Token_Array :=
        Zlib.LZ77_Matcher.Tokenize (Empty_Input, 0);
      Fixed_Score  : constant Zlib.Block_Chooser.Candidate_Score :=
        Zlib.Block_Chooser.Fixed_Bit_Size (Tokens);
   begin
      Assert (Fixed_Score.Valid, "fixed score for empty token stream must be valid");
      Assert (Fixed_Score.Bits = 16,
              "fixed empty block must include 3 header bits, 7-bit EOB, and final padding");
   end Test_Fixed_Size_Includes_EOB;

   procedure Test_Dynamic_Size_Includes_Header_Cost
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Empty_Input   : constant Zlib.Byte_Array (1 .. 0) := [others => 0];
      Tokens        : constant Zlib.LZ77_Matcher.Token_Array :=
        Zlib.LZ77_Matcher.Tokenize (Empty_Input, 0);
      Dynamic_Score : constant Zlib.Block_Chooser.Candidate_Score :=
        Zlib.Block_Chooser.Dynamic_Bit_Size (Tokens);
   begin
      Assert (Dynamic_Score.Valid, "dynamic score for empty token stream must be valid");
      Assert (Dynamic_Score.Bits > 16,
              "dynamic empty block must include dynamic header cost beyond fixed EOB cost");
   end Test_Dynamic_Size_Includes_Header_Cost;

   procedure Test_Tie_Chooses_Documented_Winner
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Best : constant Zlib.Block_Chooser.Candidate_Score :=
        Zlib.Block_Chooser.Choose_From_Scores
          ((Kind => Zlib.Block_Chooser.Stored_Block,  Valid => True, Bits => 64),
           (Kind => Zlib.Block_Chooser.Fixed_Block,   Valid => True, Bits => 64),
           (Kind => Zlib.Block_Chooser.Dynamic_Block, Valid => True, Bits => 64));
   begin
      Assert (Best.Kind = Zlib.Block_Chooser.Stored_Block,
              "equal scores must choose Stored before Fixed before Dynamic");
   end Test_Tie_Chooses_Documented_Winner;

   procedure Test_Invalid_Dynamic_Falls_Back
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Best : constant Zlib.Block_Chooser.Candidate_Score :=
        Zlib.Block_Chooser.Choose_From_Scores
          ((Kind => Zlib.Block_Chooser.Stored_Block,  Valid => True,  Bits => 80),
           (Kind => Zlib.Block_Chooser.Fixed_Block,   Valid => True,  Bits => 40),
           (Kind => Zlib.Block_Chooser.Dynamic_Block, Valid => False, Bits => 1));
   begin
      Assert (Best.Kind = Zlib.Block_Chooser.Fixed_Block,
              "invalid dynamic candidate must not win over a valid fixed candidate");
   end Test_Invalid_Dynamic_Falls_Back;

   procedure Test_Empty_Block_Chooses_Deterministic_Candidate
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array (1 .. 0) := [others => 0];
      Best  : constant Zlib.Block_Chooser.Candidate_Score :=
        Zlib.Block_Chooser.Choose (Input);
   begin
      Assert (Best.Valid, "empty Auto chooser result must be valid");
      Assert (Best.Kind = Zlib.Block_Chooser.Fixed_Block,
              "empty block should deterministically choose the smallest fixed block");
   end Test_Empty_Block_Chooses_Deterministic_Candidate;

   procedure Test_Binary_Block_Chooses_Valid_Candidate
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array := [1 => 0, 2 => 16#FF#, 3 => 16#00#, 4 => 16#7F#];
      Best  : constant Zlib.Block_Chooser.Candidate_Score :=
        Zlib.Block_Chooser.Choose (Input);
   begin
      Assert (Best.Valid, "binary block must produce a valid Auto candidate");
      Assert (Best.Bits > 0, "binary block score must be nonzero");
   end Test_Binary_Block_Chooses_Valid_Candidate;

   procedure Test_Disallowed_Stored_Is_Not_Selected
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array := [1 => Zlib.Byte (Character'Pos ('x'))];
      Best  : constant Zlib.Block_Chooser.Candidate_Score :=
        Zlib.Block_Chooser.Choose
          (Input, Allow_Dynamic => False, Allow_Stored => False);
   begin
      Assert (Best.Valid, "Auto chooser must still find a valid Huffman candidate");
      Assert (Best.Kind = Zlib.Block_Chooser.Fixed_Block,
              "disallowed Stored candidate must not win even when it would be smaller");
   end Test_Disallowed_Stored_Is_Not_Selected;

   procedure Test_Repeated_Block_Chooses_Compressed_Candidate
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array (1 .. 512) := [others => Zlib.Byte (Character'Pos ('A'))];
      Best  : constant Zlib.Block_Chooser.Candidate_Score :=
        Zlib.Block_Chooser.Choose (Input, Level => 6);
   begin
      Assert (Best.Valid, "repeated block must produce a valid Auto candidate");
      Assert (Best.Kind = Zlib.Block_Chooser.Fixed_Block
              or else Best.Kind = Zlib.Block_Chooser.Dynamic_Block,
              "repeated block should choose a Huffman candidate when smaller than stored");
   end Test_Repeated_Block_Chooses_Compressed_Candidate;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      package R renames AUnit.Test_Cases.Registration;
   begin
      R.Register_Routine (T, Test_Stored_Size_Includes_Header_And_Len'Access,
                          "stored size includes header and LEN/NLEN");
      R.Register_Routine (T, Test_Fixed_Size_Includes_EOB'Access,
                          "fixed size includes EOB");
      R.Register_Routine (T, Test_Dynamic_Size_Includes_Header_Cost'Access,
                          "dynamic size includes header cost");
      R.Register_Routine (T, Test_Tie_Chooses_Documented_Winner'Access,
                          "tie chooses documented winner");
      R.Register_Routine (T, Test_Invalid_Dynamic_Falls_Back'Access,
                          "invalid dynamic candidate falls back");
      R.Register_Routine (T, Test_Empty_Block_Chooses_Deterministic_Candidate'Access,
                          "empty block chooses deterministic candidate");
      R.Register_Routine (T, Test_Binary_Block_Chooses_Valid_Candidate'Access,
                          "binary block chooses valid candidate");
      R.Register_Routine (T, Test_Disallowed_Stored_Is_Not_Selected'Access,
                          "disallowed stored candidate is not selected");
      R.Register_Routine (T, Test_Repeated_Block_Chooses_Compressed_Candidate'Access,
                          "repeated block chooses fixed or dynamic when smaller than stored");
   end Register_Tests;

end Zlib_Block_Chooser_Tests;
