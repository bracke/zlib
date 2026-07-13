package Zlib.BZip2_Decoder is
   --  Support level: private internal implementation.
   --  Pure-Ada bzip2 stream decoder.

   function Decode
     (Payload : Byte_Array;
      Status  : out Status_Code) return Byte_Array;
   --  Decode a complete bzip2 stream: the "BZh" header, one or more blocks, and
   --  the end-of-stream trailer. Concatenated streams are decoded in sequence,
   --  as bzip2(1) itself accepts them.
   --
   --  Every block's CRC and the stream's combined CRC are verified.
   --
   --  Randomised blocks (the deprecated flag that bzip2 has not emitted since
   --  0.9.5) are rejected with Unsupported_Method rather than mis-decoded.
   --
   --  @param Payload the bzip2 stream
   --  @param Status  Ok; Invalid_Header for a bad signature, level or magic;
   --                 Invalid_Huffman_Code for bad Huffman metadata or symbols;
   --                 Invalid_Checksum when a block or stream CRC disagrees;
   --                 Invalid_Block_Type when block contents are inconsistent;
   --                 Unsupported_Method for a randomised block;
   --                 Unexpected_End_Of_Input when the stream is truncated
   --  @return the decompressed bytes, empty unless Status is Ok

end Zlib.BZip2_Decoder;
