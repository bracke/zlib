package Zlib.LZ77_Matcher is
   --  Support level: private internal implementation.
   --  Internal bounded LZ77 match finder for Deflate compression.
   --  The matcher is deterministic, uses a 32 KiB history window, and emits
   --  literal/match tokens with either greedy or conservative lazy parsing.

   Min_Match_Length : constant Natural := 3;
   Max_Match_Length : constant Natural := 258;
   Max_Distance     : constant Natural := 32_768;

   type Match_Strategy is
     (Greedy,
      Lazy,
      Optimal);
   --  Greedy emits the current best match immediately. Lazy emits a literal
   --  at the current position when the next position has a strictly longer
   --  valid match or an equal-length match that is cheaper after paying for
   --  the literal. Optimal computes a deterministic block-local parse over the
   --  bounded match candidates found by the same hash-chain search.

   type Token_Kind is (Literal, Match);

   type Token is record
      Kind     : Token_Kind := Literal;
      Value    : Byte := 0;
      Length   : Natural range 0 .. Max_Match_Length := 0;
      Distance : Natural range 0 .. Max_Distance := 0;
   end record;

   type Token_Array is array (Natural range <>) of Token;

   function Chain_Limit_For_Level
     (Level : Compression_Level)
      return Natural
     with SPARK_Mode => On;
   --  Return the bounded hash-chain probe limit for Level.
   --  @param Level Level argument supplied to Chain_Limit_For_Level
   --  @return result produced by Chain_Limit_For_Level

   function Matching_Enabled_For_Level
     (Level : Compression_Level)
      return Boolean
     with SPARK_Mode => On;
   --  Return True when Level uses LZ77 matching instead of stored-only output.
   --  @param Level Level argument supplied to Matching_Enabled_For_Level
   --  @return result produced by Matching_Enabled_For_Level

   function Strategy_For_Level
     (Level : Compression_Level)
      return Match_Strategy
     with SPARK_Mode => On;
   --  Return the documented token-selection strategy for Level.
   --  Levels 0 .. 3 remain non-lazy, levels 4 .. 7 use conservative lazy
   --  matching, and levels 8 .. 9 use bounded optimal parsing. Stored output
   --  remains outside the matcher.
   --  @param Level Level argument supplied to Strategy_For_Level
   --  @return result produced by Strategy_For_Level
   function Tokenize
     (Input       : Byte_Array;
      Chain_Limit : Natural)
      return Token_Array;
   --  Convert Input into greedy LZ77 tokens. Chain_Limit = 0 disables matching
   --  and returns one literal token per byte.
   --  @param Input Input argument supplied to Tokenize
   --  @param Chain_Limit Chain_Limit argument supplied to Tokenize
   --  @return result produced by Tokenize
   function Tokenize
     (Input       : Byte_Array;
      Chain_Limit : Natural;
      Strategy    : Match_Strategy)
      return Token_Array;
   --  Convert Input into LZ77 tokens using Strategy. Chain_Limit = 0 disables
   --  matching and returns one literal token per byte regardless of Strategy.
   --  @param Input Input argument supplied to Tokenize
   --  @param Chain_Limit Chain_Limit argument supplied to Tokenize
   --  @param Strategy Strategy argument supplied to Tokenize
   --  @return result produced by Tokenize
   function Tokenize_For_Level
     (Input : Byte_Array;
      Level : Compression_Level)
      return Token_Array;
   --  Convert Input into LZ77 tokens using the bounded effort and parsing
   --  strategy documented for Level.
   --  @param Input Input argument supplied to Tokenize_For_Level
   --  @param Level Level argument supplied to Tokenize_For_Level
   --  @return result produced by Tokenize_For_Level
end Zlib.LZ77_Matcher;
