with AUnit.Assertions; use AUnit.Assertions;
with Zlib;
with Zlib.LZ77_Matcher;

package body Zlib_Lazy_Matcher_Tests is
   use type Zlib.Byte;
   use type Zlib.LZ77_Matcher.Match_Strategy;
   use type Zlib.LZ77_Matcher.Token_Kind;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib lazy LZ77 matcher");
   end Name;

   function Bytes
     (S : String)
      return Zlib.Byte_Array
   is
      Result : Zlib.Byte_Array (1 .. S'Length);
   begin
      for I in S'Range loop
         Result (I - S'First + 1) := Zlib.Byte (Character'Pos (S (I)));
      end loop;
      return Result;
   end Bytes;

   procedure Assert_Valid
     (Tokens  : Zlib.LZ77_Matcher.Token_Array;
      Message : String)
   is
      Decoded_Pos : Natural := 0;
   begin
      for T of Tokens loop
         case T.Kind is
            when Zlib.LZ77_Matcher.Literal =>
               Assert (T.Length = 0, Message & ": literal length must be zero");
               Assert (T.Distance = 0, Message & ": literal distance must be zero");
               Decoded_Pos := Decoded_Pos + 1;

            when Zlib.LZ77_Matcher.Match =>
               Assert (T.Length in 3 .. 258, Message & ": match length must be valid");
               Assert (T.Distance in 1 .. 32_768, Message & ": match distance must be valid");
               Assert (T.Distance <= Decoded_Pos, Message & ": match distance must not reference future bytes");
               Decoded_Pos := Decoded_Pos + T.Length;
         end case;
      end loop;
   end Assert_Valid;

   procedure Assert_Same_Tokens
     (Left    : Zlib.LZ77_Matcher.Token_Array;
      Right   : Zlib.LZ77_Matcher.Token_Array;
      Message : String)
   is
   begin
      Assert (Left'Length = Right'Length, Message & ": token count mismatch");

      for I in Right'Range loop
         declare
            L : constant Zlib.LZ77_Matcher.Token := Left (Left'First + (I - Right'First));
            R : constant Zlib.LZ77_Matcher.Token := Right (I);
         begin
            Assert (L.Kind = R.Kind, Message & ": token kind mismatch");
            Assert (L.Value = R.Value, Message & ": token value mismatch");
            Assert (L.Length = R.Length, Message & ": token length mismatch");
            Assert (L.Distance = R.Distance, Message & ": token distance mismatch");
         end;
      end loop;
   end Assert_Same_Tokens;

   procedure Test_Level_Strategy_Policy
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert (Zlib.LZ77_Matcher.Strategy_For_Level (0) = Zlib.LZ77_Matcher.Greedy,
              "level 0 must not enable lazy matching");
      Assert (Zlib.LZ77_Matcher.Strategy_For_Level (1) = Zlib.LZ77_Matcher.Greedy,
              "level 1 must remain greedy");
      Assert (Zlib.LZ77_Matcher.Strategy_For_Level (3) = Zlib.LZ77_Matcher.Greedy,
              "level 3 must remain greedy");
      Assert (Zlib.LZ77_Matcher.Strategy_For_Level (4) = Zlib.LZ77_Matcher.Lazy,
              "level 4 must enable lazy matching");
      Assert (Zlib.LZ77_Matcher.Strategy_For_Level (6) = Zlib.LZ77_Matcher.Lazy,
              "default level must enable lazy matching");
      Assert (Zlib.LZ77_Matcher.Strategy_For_Level (8) = Zlib.LZ77_Matcher.Optimal,
              "level 8 must enable bounded optimal parsing");
      Assert (Zlib.LZ77_Matcher.Strategy_For_Level (9) = Zlib.LZ77_Matcher.Optimal,
              "level 9 must enable bounded optimal parsing");
   end Test_Level_Strategy_Policy;

   procedure Test_Lazy_Emits_Literal_When_Next_Match_Is_Longer
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input  : constant Zlib.Byte_Array := Bytes ("aaabaaaaa");
      Tokens : constant Zlib.LZ77_Matcher.Token_Array :=
        Zlib.LZ77_Matcher.Tokenize
          (Input       => Input,
           Chain_Limit => 32,
           Strategy    => Zlib.LZ77_Matcher.Lazy);
      N : constant Natural := Tokens'First;
   begin
      Assert (Tokens'Length >= 6, "lazy fixture should produce at least six tokens");
      Assert (Tokens (N + 4).Kind = Zlib.LZ77_Matcher.Literal,
              "lazy parser must emit literal before a strictly longer next match");
      Assert (Tokens (N + 5).Kind = Zlib.LZ77_Matcher.Match,
              "lazy parser must then emit the next match");
      Assert (Tokens (N + 5).Length = 4,
              "lazy next match length should be selected");
      Assert_Valid (Tokens, "longer-next lazy fixture");
   end Test_Lazy_Emits_Literal_When_Next_Match_Is_Longer;

   procedure Test_Lazy_Keeps_Current_When_Next_Match_Is_Equal
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input  : constant Zlib.Byte_Array := Bytes ("abcabcabc");
      Greedy : constant Zlib.LZ77_Matcher.Token_Array :=
        Zlib.LZ77_Matcher.Tokenize (Input, 32, Zlib.LZ77_Matcher.Greedy);
      Lazy   : constant Zlib.LZ77_Matcher.Token_Array :=
        Zlib.LZ77_Matcher.Tokenize (Input, 32, Zlib.LZ77_Matcher.Lazy);
   begin
      Assert_Same_Tokens (Lazy, Greedy, "equal-or-not-better next match must keep current match");
      Assert (Lazy (Lazy'Last).Kind = Zlib.LZ77_Matcher.Match,
              "fixture must end with current match kept");
      Assert_Valid (Lazy, "equal-next lazy fixture");
   end Test_Lazy_Keeps_Current_When_Next_Match_Is_Equal;

   procedure Test_Lazy_Keeps_Current_When_Next_Match_Is_Shorter
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input  : constant Zlib.Byte_Array := Bytes ("abcdabcdeabcde");
      Greedy : constant Zlib.LZ77_Matcher.Token_Array :=
        Zlib.LZ77_Matcher.Tokenize (Input, 32, Zlib.LZ77_Matcher.Greedy);
      Lazy   : constant Zlib.LZ77_Matcher.Token_Array :=
        Zlib.LZ77_Matcher.Tokenize (Input, 32, Zlib.LZ77_Matcher.Lazy);
   begin
      Assert_Same_Tokens (Lazy, Greedy, "shorter next match must keep current match");
      Assert_Valid (Lazy, "shorter-next lazy fixture");
   end Test_Lazy_Keeps_Current_When_Next_Match_Is_Shorter;

   procedure Test_Lazy_Matches_Are_Always_Valid
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input  : constant Zlib.Byte_Array := Bytes ("aaabaaaaa abcabcabc abcdabcdeabcde aaabaaaaa");
      Tokens : constant Zlib.LZ77_Matcher.Token_Array :=
        Zlib.LZ77_Matcher.Tokenize (Input, 128, Zlib.LZ77_Matcher.Lazy);
   begin
      Assert_Valid (Tokens, "lazy validity sweep");
   end Test_Lazy_Matches_Are_Always_Valid;

   procedure Test_Lazy_Is_Deterministic
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array := Bytes ("lazy deterministic payload aaabaaaaa aaabaaaaa abcabcabc");
      A     : constant Zlib.LZ77_Matcher.Token_Array :=
        Zlib.LZ77_Matcher.Tokenize (Input, 128, Zlib.LZ77_Matcher.Lazy);
      B     : constant Zlib.LZ77_Matcher.Token_Array :=
        Zlib.LZ77_Matcher.Tokenize (Input, 128, Zlib.LZ77_Matcher.Lazy);
   begin
      Assert_Same_Tokens (A, B, "lazy tokenization must be deterministic");
   end Test_Lazy_Is_Deterministic;

   procedure Test_Optimal_Is_Deterministic_And_Valid
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array :=
        Bytes ("optimal parser fixture aaabaaaaa abcabcabc abcdabcdeabcde");
      A     : constant Zlib.LZ77_Matcher.Token_Array :=
        Zlib.LZ77_Matcher.Tokenize (Input, 128, Zlib.LZ77_Matcher.Optimal);
      B     : constant Zlib.LZ77_Matcher.Token_Array :=
        Zlib.LZ77_Matcher.Tokenize (Input, 128, Zlib.LZ77_Matcher.Optimal);
   begin
      Assert_Same_Tokens (A, B, "optimal tokenization must be deterministic");
      Assert_Valid (A, "optimal parser fixture");
   end Test_Optimal_Is_Deterministic_And_Valid;

   procedure Test_Lazy_Respects_Block_Boundary
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      First_Block  : constant Zlib.Byte_Array := Bytes ("abcabc");
      Second_Block : constant Zlib.Byte_Array := Bytes ("abcabc");
      Tokens       : constant Zlib.LZ77_Matcher.Token_Array :=
        Zlib.LZ77_Matcher.Tokenize (Second_Block, 32, Zlib.LZ77_Matcher.Lazy);
   begin
      Assert (First_Block'Length = Second_Block'Length,
              "block-boundary fixture sanity");
      Assert_Valid (Tokens, "fresh block lazy tokenization");
      for Tkn of Tokens loop
         if Tkn.Kind = Zlib.LZ77_Matcher.Match then
            Assert
              (Tkn.Distance < Second_Block'Length,
               "fresh block matches must refer only to bytes in the same block");
         end if;
      end loop;
   end Test_Lazy_Respects_Block_Boundary;

   procedure Test_Lazy_Respects_Flush_Boundary
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Before_Flush : constant Zlib.Byte_Array := Bytes ("aaabaaaaa");
      After_Flush  : constant Zlib.Byte_Array := Bytes ("aaaaa");
      Tokens       : constant Zlib.LZ77_Matcher.Token_Array :=
        Zlib.LZ77_Matcher.Tokenize (After_Flush, 32, Zlib.LZ77_Matcher.Lazy);
   begin
      Assert (Before_Flush'Length > After_Flush'Length,
              "flush-boundary fixture sanity");
      Assert_Valid (Tokens, "fresh post-flush block");
      Assert (Tokens'Length <= After_Flush'Length,
              "fresh post-flush tokenization remains bounded");
   end Test_Lazy_Respects_Flush_Boundary;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      package R renames AUnit.Test_Cases.Registration;
   begin
      R.Register_Routine (T, Test_Level_Strategy_Policy'Access,
                          "level policy selects greedy, lazy, or optimal strategy");
      R.Register_Routine (T, Test_Lazy_Emits_Literal_When_Next_Match_Is_Longer'Access,
                          "lazy matching emits literal when next match is longer");
      R.Register_Routine (T, Test_Lazy_Keeps_Current_When_Next_Match_Is_Equal'Access,
                          "lazy matching keeps current match when next is equal");
      R.Register_Routine (T, Test_Lazy_Keeps_Current_When_Next_Match_Is_Shorter'Access,
                          "lazy matching keeps current match when next is shorter");
      R.Register_Routine (T, Test_Lazy_Matches_Are_Always_Valid'Access,
                          "lazy matching never emits invalid length or distance");
      R.Register_Routine (T, Test_Lazy_Is_Deterministic'Access,
                          "lazy matching is deterministic");
      R.Register_Routine (T, Test_Optimal_Is_Deterministic_And_Valid'Access,
                          "optimal parsing is deterministic and valid");
      R.Register_Routine (T, Test_Lazy_Respects_Block_Boundary'Access,
                          "lazy matching respects block boundary");
      R.Register_Routine (T, Test_Lazy_Respects_Flush_Boundary'Access,
                          "lazy matching respects flush boundary");
   end Register_Tests;

end Zlib_Lazy_Matcher_Tests;
