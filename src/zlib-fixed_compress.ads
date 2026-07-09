package Zlib.Fixed_Compress is
   --  Support level: private internal implementation.
   --  Fixed-Huffman zlib compressor. This package uses the internal bounded
   --  LZ77 matcher at low effort and emits fixed Deflate length/distance pairs
   --  when profitable.

   procedure Fixed_Code
     (Symbol : Natural; Code : out Natural; Length : out Natural)
     with Pre => Symbol <= 287,
          SPARK_Mode => On;
   --  Return the fixed-Huffman wire code for Symbol. Code is already bit
   --  reversed for Deflate LSB-first emission.
   --  @param Symbol Symbol argument supplied to Fixed_Code
   --  @param Code Code argument supplied to Fixed_Code
   --  @param Length Length argument supplied to Fixed_Code
   function Deflate_Fixed
     (Input : Zlib.Byte_Array; Status : out Zlib.Status_Code)
      return Zlib.Byte_Array;
   --  Return the Deflate Fixed result.
   --  @param Input Input argument supplied to Deflate_Fixed
   --  @param Status Status argument supplied to Deflate_Fixed
   --  @return result produced by Deflate_Fixed

   function Deflate_Fixed_Raw
     (Input : Zlib.Byte_Array; Status : out Zlib.Status_Code)
      return Zlib.Byte_Array;
   --  Return the Deflate Fixed Raw result.
   --  @param Input Input argument supplied to Deflate_Fixed_Raw
   --  @param Status Status argument supplied to Deflate_Fixed_Raw
   --  @return result produced by Deflate_Fixed_Raw

end Zlib.Fixed_Compress;
