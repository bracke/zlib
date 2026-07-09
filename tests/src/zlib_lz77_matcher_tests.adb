with AUnit.Assertions; use AUnit.Assertions;
with Zlib; use Zlib;
with Zlib.LZ77_Matcher;

package body Zlib_LZ77_Matcher_Tests is
   use type Zlib.LZ77_Matcher.Token_Kind;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib.LZ77_Matcher");
   end Name;

   procedure Test_Level_Chain_Limits
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert (Zlib.LZ77_Matcher.Chain_Limit_For_Level (0) = 0,
              "level 0 must disable matching");
      Assert (Zlib.LZ77_Matcher.Chain_Limit_For_Level (1) = 4,
              "level 1 must use low bounded effort");
      Assert (Zlib.LZ77_Matcher.Chain_Limit_For_Level (2) = 8,
              "level 2 must use low Auto effort");
      Assert (Zlib.LZ77_Matcher.Chain_Limit_For_Level (3) = 16,
              "level 3 must use higher greedy Auto effort");
      Assert (Zlib.LZ77_Matcher.Chain_Limit_For_Level (6) = 256,
              "level 6 must use default lazy effort");
      Assert (Zlib.LZ77_Matcher.Chain_Limit_For_Level (7) = 1_024,
              "level 7 must use expanded high effort");
      Assert (Zlib.LZ77_Matcher.Chain_Limit_For_Level (8) = 2_048,
              "level 8 must use expanded very high effort");
      Assert (Zlib.LZ77_Matcher.Chain_Limit_For_Level (9) = 8_192,
              "level 9 must use highest bounded effort");
      Assert (not Zlib.LZ77_Matcher.Matching_Enabled_For_Level (0),
              "level 0 must report matching disabled");
      for Level in Zlib.Compression_Level range 1 .. 9 loop
         Assert (Zlib.LZ77_Matcher.Matching_Enabled_For_Level (Level),
                 "non-stored level must report matching enabled");
      end loop;
   end Test_Level_Chain_Limits;

   procedure Test_Repeated_Data_Produces_Match
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input  : constant Zlib.Byte_Array :=
        [1 => Zlib.Byte (Character'Pos ('a')),
         2 => Zlib.Byte (Character'Pos ('b')),
         3 => Zlib.Byte (Character'Pos ('c')),
         4 => Zlib.Byte (Character'Pos ('a')),
         5 => Zlib.Byte (Character'Pos ('b')),
         6 => Zlib.Byte (Character'Pos ('c')),
         7 => Zlib.Byte (Character'Pos ('a')),
         8 => Zlib.Byte (Character'Pos ('b')),
         9 => Zlib.Byte (Character'Pos ('c'))];
      Tokens : constant Zlib.LZ77_Matcher.Token_Array :=
        Zlib.LZ77_Matcher.Tokenize (Input, 32);
      Saw_Match : Boolean := False;
   begin
      for Tok of Tokens loop
         if Tok.Kind = Zlib.LZ77_Matcher.Match then
            Saw_Match := True;
            Assert (Tok.Length in 3 .. 258,
                    "match length must stay inside Deflate limits");
            Assert (Tok.Distance in 1 .. 32_768,
                    "match distance must stay inside Deflate limits");
         end if;
      end loop;

      Assert (Saw_Match, "repeated data should produce at least one LZ77 match");
   end Test_Repeated_Data_Produces_Match;

   procedure Test_Dynamic_Roundtrips_With_Matches
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input  : constant Zlib.Byte_Array :=
        [1 .. 256 => Zlib.Byte (Character'Pos ('A')),
         257 .. 512 => Zlib.Byte (Character'Pos ('B'))];
      Status : Zlib.Status_Code;
   begin
      declare
         Deflated : constant Zlib.Byte_Array := Zlib.Deflate_Dynamic (Input, Status);
      begin
         Assert (Status = Zlib.Ok, "dynamic compression with matches must succeed");

         declare
            Inflated : constant Zlib.Byte_Array := Zlib.Inflate (Deflated, Status);
         begin
            Assert (Status = Zlib.Ok, "dynamic output with matches must inflate");
            Assert (Inflated = Input, "inflated dynamic matched output must equal input");
         end;
      end;
   end Test_Dynamic_Roundtrips_With_Matches;

   procedure Test_Fixed_Roundtrips_With_Matches
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input  : constant Zlib.Byte_Array :=
        [1 .. 128 => Zlib.Byte (Character'Pos ('x')),
         129 .. 256 => Zlib.Byte (Character'Pos ('y'))];
      Status : Zlib.Status_Code;
   begin
      declare
         Deflated : constant Zlib.Byte_Array := Zlib.Deflate_Fixed (Input, Status);
      begin
         Assert (Status = Zlib.Ok, "fixed compression with matches must succeed");

         declare
            Inflated : constant Zlib.Byte_Array := Zlib.Inflate (Deflated, Status);
         begin
            Assert (Status = Zlib.Ok, "fixed output with matches must inflate");
            Assert (Inflated = Input, "inflated fixed matched output must equal input");
         end;
      end;
   end Test_Fixed_Roundtrips_With_Matches;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      package R renames AUnit.Test_Cases.Registration;
   begin
      R.Register_Routine (T, Test_Level_Chain_Limits'Access,
                          "level mapping is bounded and deterministic");
      R.Register_Routine (T, Test_Repeated_Data_Produces_Match'Access,
                          "repeated data produces a bounded match");
      R.Register_Routine (T, Test_Dynamic_Roundtrips_With_Matches'Access,
                          "dynamic compression emits valid match output");
      R.Register_Routine (T, Test_Fixed_Roundtrips_With_Matches'Access,
                          "fixed compression emits valid match output");
   end Register_Tests;

end Zlib_LZ77_Matcher_Tests;
