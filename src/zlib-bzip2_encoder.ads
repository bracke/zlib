package Zlib.BZip2_Encoder is
   --  Support level: private internal implementation.
   --  Pure-Ada bzip2 stream encoder.

   subtype Level_Range is Positive range 1 .. 9;
   --  Block size, in units of 100k, as the "BZh<n>" header records it.

   function Encode
     (Plain  : Byte_Array;
      Level  : Level_Range := 9;
      Status : out Status_Code) return Byte_Array;
   --  Produce a complete bzip2 stream: the "BZh" header, one block per
   --  Level * 100k of run-length-coded input, and the end-of-stream trailer with
   --  the combined CRC.
   --
   --  Blocks are never randomised, so the deprecated randomisation bit is always
   --  clear -- as it is in every stream bzip2 has produced since 0.9.5.
   --
   --  @param Plain  the bytes to compress; an empty input yields a valid stream
   --                with no blocks
   --  @param Level  block size in units of 100k
   --  @param Status Ok, or Invalid_Block_Type if the block state is inconsistent
   --  @return the bzip2 stream

end Zlib.BZip2_Encoder;
