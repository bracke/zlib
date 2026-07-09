with Zlib.LZMA_Core;

package Zlib.LZMA_Parser is
   --  Support level: private internal implementation.
   --  Optimal-parser operation records and backtracking helpers.

   type Opt_Kind is (Op_Lit, Op_Match, Op_Rep, Op_Short_Rep);

   type Opt_Entry is record
      Price   : Natural := Natural'Last;
      From    : Natural := 0;
      Kind    : Opt_Kind := Op_Lit;
      Dist    : Natural := 0;
      Len     : Natural := 1;
      Rep_Idx : Natural := 0;
      St      : Natural := 0;
      Reps    : Zlib.LZMA_Core.Rep_Quad := [others => 0];
   end record;

   type Opt_Array is array (Natural range <>) of Opt_Entry;

   type Op_Rec is record
      Kind            : Opt_Kind;
      Dist, Len, Ridx : Natural;
   end record;

   type Op_Array is array (Positive range <>) of Op_Rec;

   procedure Backtrack
     (Opt   : Opt_Array;
      Span  : Natural;
      Ops   : out Op_Array;
      Count : out Natural);

end Zlib.LZMA_Parser;
