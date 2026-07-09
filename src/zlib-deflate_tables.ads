with Zlib.Huffman;

package Zlib.Deflate_Tables
  with SPARK_Mode => On
is
   --  Support level: private internal implementation.
   --  Shared Deflate fixed-Huffman and length/distance tables used by both
   --  one-shot and streaming inflate decoders.

   subtype Length_Symbol is Natural range 257 .. 285;
   --  Deflate literal/length symbols that encode match lengths.

   subtype Distance_Symbol is Natural range 0 .. 29;
   --  Deflate distance symbols.

   Length_Base : constant array (Length_Symbol) of Natural :=
     [257 => 3, 258 => 4, 259 => 5, 260 => 6,
      261 => 7, 262 => 8, 263 => 9, 264 => 10,
      265 => 11, 266 => 13, 267 => 15, 268 => 17,
      269 => 19, 270 => 23, 271 => 27, 272 => 31,
      273 => 35, 274 => 43, 275 => 51, 276 => 59,
      277 => 67, 278 => 83, 279 => 99, 280 => 115,
      281 => 131, 282 => 163, 283 => 195, 284 => 227,
      285 => 258];
   --  Base match length for each length symbol.

   Length_Extra : constant array (Length_Symbol) of Natural :=
     [257 => 0, 258 => 0, 259 => 0, 260 => 0,
      261 => 0, 262 => 0, 263 => 0, 264 => 0,
      265 => 1, 266 => 1, 267 => 1, 268 => 1,
      269 => 2, 270 => 2, 271 => 2, 272 => 2,
      273 => 3, 274 => 3, 275 => 3, 276 => 3,
      277 => 4, 278 => 4, 279 => 4, 280 => 4,
      281 => 5, 282 => 5, 283 => 5, 284 => 5,
      285 => 0];
   --  Extra-bit count for each length symbol.

   Distance_Base : constant array (Distance_Symbol) of Natural :=
     [0 => 1, 1 => 2, 2 => 3, 3 => 4,
      4 => 5, 5 => 7, 6 => 9, 7 => 13,
      8 => 17, 9 => 25, 10 => 33, 11 => 49,
      12 => 65, 13 => 97, 14 => 129, 15 => 193,
      16 => 257, 17 => 385, 18 => 513, 19 => 769,
      20 => 1025, 21 => 1537, 22 => 2049, 23 => 3073,
      24 => 4097, 25 => 6145, 26 => 8193, 27 => 12289,
      28 => 16385, 29 => 24577];
   --  Base match distance for each distance symbol.
   --  Dynamic-Huffman code-length-code storage order from RFC 1951.
   Code_Length_Order : constant array (Natural range 0 .. 18) of Natural :=
     [0  => 16,
      1  => 17,
      2  => 18,
      3  => 0,
      4  => 8,
      5  => 7,
      6  => 9,
      7  => 6,
      8  => 10,
      9  => 5,
      10 => 11,
      11 => 4,
      12 => 12,
      13 => 3,
      14 => 13,
      15 => 2,
      16 => 14,
      17 => 1,
      18 => 15];

   Distance_Extra : constant array (Distance_Symbol) of Natural :=
     [0 => 0, 1 => 0, 2 => 0, 3 => 0,
      4 => 1, 5 => 1, 6 => 2, 7 => 2,
      8 => 3, 9 => 3, 10 => 4, 11 => 4,
      12 => 5, 13 => 5, 14 => 6, 15 => 6,
      16 => 7, 17 => 7, 18 => 8, 19 => 8,
      20 => 9, 21 => 9, 22 => 10, 23 => 10,
      24 => 11, 25 => 11, 26 => 12, 27 => 12,
      28 => 13, 29 => 13];
   --  Extra-bit count for each distance symbol.

   procedure Build_Fixed_Tables
     (Lit_Len_Table : out Zlib.Huffman.Decode_Table;
      Dist_Table    : out Zlib.Huffman.Decode_Table;
      Status        : out Zlib.Status_Code)
     with SPARK_Mode => Off;
   --  Build the standard Deflate fixed-Huffman decode tables.
   --  @param Lit_Len_Table Lit_Len_Table argument supplied to Build_Fixed_Tables
   --  @param Dist_Table Dist_Table argument supplied to Build_Fixed_Tables
   --  @param Status Status argument supplied to Build_Fixed_Tables
end Zlib.Deflate_Tables;
