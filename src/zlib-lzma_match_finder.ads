package Zlib.LZMA_Match_Finder is
   --  Support level: private internal implementation.
   --  Hash-chain match finder helpers used by the LZMA optimal parser.

   Max_Match    : constant Natural := 273;
   Nice_Len     : constant Natural := 128;
   Base_Seg_Len : constant Natural := 8192;
   Max_Seg_Len  : constant Natural := 32768;
   Max_Chain    : constant Natural := 128;
   Hash_Bits    : constant Natural := 16;
   Max_Pairs    : constant Natural := 64;

   type Pos_Table is array (Natural range <>) of Natural;
   type Len_Array is array (1 .. Max_Pairs) of Natural;

   function Hash3 (Plain : Byte_Array; I : Natural) return Natural
     with Pre => I in Plain'Range and then I + 2 <= Plain'Last;

   procedure Insert
     (Plain : Byte_Array;
      Head  : in out Pos_Table;
      Chain : in out Pos_Table;
      I     : Natural);

   function Match_Length
     (Plain : Byte_Array;
      I     : Natural;
      D     : Natural) return Natural;

   procedure Find_All_Matches
     (Plain   : Byte_Array;
      Head    : Pos_Table;
      Chain   : Pos_Table;
      I       : Natural;
      Dict_Sz : Natural;
      Count   : out Natural;
      Lens    : out Len_Array;
      Dists   : out Len_Array);

   function Longest_Match_From
     (Plain   : Byte_Array;
      Head    : Pos_Table;
      Chain   : Pos_Table;
      I       : Natural;
      Dict_Sz : Natural) return Natural;

   procedure Insert_Range
     (Plain     : Byte_Array;
      Head      : in out Pos_Table;
      Chain     : in out Pos_Table;
      First_Pos : Natural;
      Count     : Natural);

   procedure Prepare_Adaptive_Segment
     (Plain   : Byte_Array;
      Head    : in out Pos_Table;
      Chain   : in out Pos_Table;
      Cur     : Natural;
      Dict_Sz : Natural;
      Span    : in out Natural);

end Zlib.LZMA_Match_Finder;
