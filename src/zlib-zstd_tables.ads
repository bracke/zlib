package Zlib.Zstd_Tables is
   --  Support level: private internal implementation.
   --  The fixed tables of the zstd format: the predefined FSE distributions, and
   --  the baselines and extra-bit counts that turn a length code back into a
   --  length. These are format constants, not tuning choices.

   type Count_Array is array (Natural range <>) of Integer;
   type Value_Array is array (Natural range <>) of Natural;

   --  A normalized count of -1 marks a "less than one probability" symbol, which
   --  the table builder gives a single low-probability slot.

   Max_Literal_Code : constant Natural := 35;
   Max_Match_Code   : constant Natural := 52;
   Max_Offset_Code  : constant Natural := 28;

   Literal_Log : constant Natural := 6;
   Match_Log   : constant Natural := 6;
   Offset_Log  : constant Natural := 5;

   Literal_Default : constant Count_Array (0 .. Max_Literal_Code) :=
     [4, 3, 2, 2, 2, 2, 2, 2,
      2, 2, 2, 2, 2, 1, 1, 1,
      2, 2, 2, 2, 2, 2, 2, 2,
      2, 3, 2, 1, 1, 1, 1, 1,
      -1, -1, -1, -1];

   --  Note the tail: SEVEN low-probability codes, 46 .. 52, not five. They are
   --  laid down from the top of the table, so one too few or too many shifts
   --  every high match-length code onto the wrong state -- which decodes long
   --  matches as short ones and quietly truncates the output.
   Match_Default : constant Count_Array (0 .. Max_Match_Code) :=
     [1, 4, 3, 2, 2, 2, 2, 2,
      2, 1, 1, 1, 1, 1, 1, 1,
      1, 1, 1, 1, 1, 1, 1, 1,
      1, 1, 1, 1, 1, 1, 1, 1,
      1, 1, 1, 1, 1, 1, 1, 1,
      1, 1, 1, 1, 1, 1, -1, -1,
      -1, -1, -1, -1, -1];

   Offset_Default : constant Count_Array (0 .. Max_Offset_Code) :=
     [1, 1, 1, 1, 1, 1, 2, 2,
      2, 1, 1, 1, 1, 1, 1, 1,
      1, 1, 1, 1, 1, 1, 1, 1,
      -1, -1, -1, -1, -1];

   Literal_Extra_Bits : constant Value_Array (0 .. Max_Literal_Code) :=
     [0, 0, 0, 0, 0, 0, 0, 0,
      0, 0, 0, 0, 0, 0, 0, 0,
      1, 1, 1, 1, 2, 2, 3, 3,
      4, 6, 7, 8, 9, 10, 11, 12,
      13, 14, 15, 16];

   Literal_Baseline : constant Value_Array (0 .. Max_Literal_Code) :=
     [0, 1, 2, 3, 4, 5, 6, 7,
      8, 9, 10, 11, 12, 13, 14, 15,
      16, 18, 20, 22, 24, 28, 32, 40,
      48, 64, 128, 256, 512, 1_024, 2_048, 4_096,
      8_192, 16_384, 32_768, 65_536];

   Match_Extra_Bits : constant Value_Array (0 .. Max_Match_Code) :=
     [0, 0, 0, 0, 0, 0, 0, 0,
      0, 0, 0, 0, 0, 0, 0, 0,
      0, 0, 0, 0, 0, 0, 0, 0,
      0, 0, 0, 0, 0, 0, 0, 0,
      1, 1, 1, 1, 2, 2, 3, 3,
      4, 4, 5, 7, 8, 9, 10, 11,
      12, 13, 14, 15, 16];

   Match_Baseline : constant Value_Array (0 .. Max_Match_Code) :=
     [3, 4, 5, 6, 7, 8, 9, 10,
      11, 12, 13, 14, 15, 16, 17, 18,
      19, 20, 21, 22, 23, 24, 25, 26,
      27, 28, 29, 30, 31, 32, 33, 34,
      35, 37, 39, 41, 43, 47, 51, 59,
      67, 83, 99, 131, 259, 515, 1_027, 2_051,
      4_099, 8_195, 16_387, 32_771, 65_539];

   function Literal_Code (Length : Natural) return Natural;
   --  The literal-length code covering Length.
   --  @param Length a literal run length
   --  @return its code

   function Match_Code (Length : Natural) return Natural
     with Pre => Length >= 3;
   --  The match-length code covering Length.
   --  @param Length a match length, at least 3
   --  @return its code

   function Highest_Bit (Value : Natural) return Natural
     with Pre => Value > 0;
   --  Position of the most significant set bit, counting the low bit as zero.
   --  @param Value a positive value
   --  @return the bit position

end Zlib.Zstd_Tables;
