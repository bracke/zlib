package Zlib.Zstd_Encoder is
   --  Support level: private internal implementation.
   --  Pure-Ada zstd frame encoder.

   function Encode
     (Plain  : Byte_Array;
      Status : out Status_Code) return Byte_Array;
   --  Produce a single zstd frame: LZ77 matches coded as sequences with
   --  per-block FSE tables, and literals coded with Huffman where that pays.
   --
   --  Unlike bzip2, the output is NOT bit-identical with the reference. zstd's
   --  encoder is a pile of heuristics -- match search, block splitting, table
   --  estimation -- that libzstd is free to change between versions. What is
   --  guaranteed is that the output is valid zstd: the reference decoder reads
   --  it, and so does Zlib.Zstd_Decoder.
   --
   --  Offsets are always emitted as real distances, never as one of the three
   --  repeat-offset codes. That is legal, costs a little ratio, and keeps the
   --  encoder clear of the format's most error-prone rule.
   --
   --  A block whose compressed form would not be smaller is stored raw.
   --
   --  @param Plain  the bytes to compress
   --  @param Status Ok, or Invalid_Block_Type if the block state is inconsistent
   --  @return the zstd frame

end Zlib.Zstd_Encoder;
