with AUnit.Assertions; use AUnit.Assertions;
with Zlib.Huffman_Builder;

package body Zlib_Huffman_Builder_Tests is

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib.Huffman_Builder");
   end Name;

   procedure Assert_Max_15
     (Lengths : Zlib.Huffman_Builder.Length_Array;
      Message : String)
   is
   begin
      for Symbol in Lengths'Range loop
         pragma Warnings (Off, "condition can only be False*");
         Assert (Lengths (Symbol) <= 15, Message & ": length exceeds 15");
         pragma Warnings (On, "condition can only be False*");
      end loop;
   end Assert_Max_15;

   procedure Test_Single_Symbol_Plus_EOB
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Frequencies : Zlib.Huffman_Builder.Frequency_Array (0 .. 256) := [others => 0];
      Lengths     : Zlib.Huffman_Builder.Length_Array (0 .. 256) := [others => 0];
      Present     : Natural := 0;
   begin
      Frequencies (65) := 10;
      Zlib.Huffman_Builder.Build_Lengths (Frequencies, Lengths, 256);

      Assert (Lengths (65) /= 0, "literal symbol must be present");
      Assert (Lengths (256) /= 0, "EOB symbol must be present");
      for Symbol in Lengths'Range loop
         if Lengths (Symbol) /= 0 then
            Present := Present + 1;
         end if;
      end loop;
      Assert (Present >= 2, "builder must produce at least two symbols when possible");
      Assert_Max_15 (Lengths, "single-symbol builder result");
   end Test_Single_Symbol_Plus_EOB;

   procedure Test_All_Zero_Except_EOB
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Frequencies : constant Zlib.Huffman_Builder.Frequency_Array (0 .. 256) := [others => 0];
      Lengths     : Zlib.Huffman_Builder.Length_Array (0 .. 256) := [others => 0];
      Present     : Natural := 0;
   begin
      Zlib.Huffman_Builder.Build_Lengths (Frequencies, Lengths, 256);
      Assert (Lengths (256) /= 0, "EOB must be inserted when frequencies are zero");

      for Symbol in Lengths'Range loop
         if Lengths (Symbol) /= 0 then
            Present := Present + 1;
         end if;
      end loop;

      Assert (Present = 2, "zero-frequency alphabet should receive one EOB and one dummy symbol");
      Assert_Max_15 (Lengths, "zero-frequency builder result");
   end Test_All_Zero_Except_EOB;

   procedure Test_Deterministic_Common_Frequencies
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Frequencies : Zlib.Huffman_Builder.Frequency_Array (0 .. 256) := [others => 0];
      A           : Zlib.Huffman_Builder.Length_Array (0 .. 256) := [others => 0];
      B           : Zlib.Huffman_Builder.Length_Array (0 .. 256) := [others => 0];
   begin
      Frequencies (Natural (Character'Pos ('e'))) := 50;
      Frequencies (Natural (Character'Pos ('t'))) := 40;
      Frequencies (Natural (Character'Pos ('a'))) := 30;
      Frequencies (Natural (Character'Pos ('o'))) := 20;
      Frequencies (Natural (Character'Pos ('n'))) := 10;

      Zlib.Huffman_Builder.Build_Lengths (Frequencies, A, 256);
      Zlib.Huffman_Builder.Build_Lengths (Frequencies, B, 256);

      for Symbol in A'Range loop
         Assert (A (Symbol) = B (Symbol), "builder output must be deterministic");
      end loop;
      Assert (A (256) /= 0, "EOB must be present in deterministic result");
      Assert_Max_15 (A, "deterministic builder result");
   end Test_Deterministic_Common_Frequencies;

   procedure Test_Lengths_Never_Exceed_15
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Frequencies : Zlib.Huffman_Builder.Frequency_Array (0 .. 285) := [others => 0];
      Lengths     : Zlib.Huffman_Builder.Length_Array (0 .. 285) := [others => 0];
   begin
      for Symbol in Frequencies'Range loop
         Frequencies (Symbol) := Symbol + 1;
      end loop;

      Zlib.Huffman_Builder.Build_Lengths (Frequencies, Lengths, 256);
      Assert_Max_15 (Lengths, "full literal/length builder result");
   end Test_Lengths_Never_Exceed_15;

   procedure Test_Required_Symbol_Is_Inserted
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Frequencies : Zlib.Huffman_Builder.Frequency_Array (0 .. 18) := [others => 0];
      Lengths     : Zlib.Huffman_Builder.Length_Array (0 .. 18) := [others => 0];
   begin
      Frequencies (8) := 12;
      Zlib.Huffman_Builder.Build_Lengths (Frequencies, Lengths, 0);
      Assert (Lengths (0) /= 0, "required symbol must be inserted deterministically");
      Assert (Lengths (8) /= 0, "nonzero-frequency symbol must remain present");
      Assert_Max_15 (Lengths, "required-symbol insertion result");
   end Test_Required_Symbol_Is_Inserted;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_Single_Symbol_Plus_EOB'Access,
         "single symbol plus EOB builds valid lengths");
      Registration.Register_Routine
        (T, Test_All_Zero_Except_EOB'Access,
         "all zero frequencies except EOB builds valid lengths");
      Registration.Register_Routine
        (T, Test_Deterministic_Common_Frequencies'Access,
         "common literal frequencies produce deterministic lengths");
      Registration.Register_Routine
        (T, Test_Lengths_Never_Exceed_15'Access,
         "lengths never exceed 15");
      Registration.Register_Routine
        (T, Test_Required_Symbol_Is_Inserted'Access,
         "missing required symbol is inserted deterministically");
   end Register_Tests;

end Zlib_Huffman_Builder_Tests;
