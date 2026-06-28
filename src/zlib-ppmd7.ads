--  Support level: private internal implementation.
--
--  Real PPMd variant H codec (the "PPMd7" model used by 7-Zip), a faithful
--  clean-room port of the LZMA SDK Ppmd7.c / Ppmd7Enc.c / Ppmd7Dec.c. This
--  replaces the previous pattern/canned PPMd placeholder with a general
--  encoder and decoder that interoperate with stock 7z: our output decodes in
--  7z, and stock 7z PPMd streams decode here.
--
--  The model is a faithful transcription, including the byte-pool sub-allocator
--  (units, free lists, glue, restart), the suffix-context tree, SEE, and binary
--  contexts, so the range-coder output is bit-identical to 7-Zip.

with Interfaces;

package Zlib.PPMd7 is

   function Compress
     (Data     : Byte_Array;
      Order    : Positive;
      Mem_Size : Interfaces.Unsigned_32) return Byte_Array;
   --  Encode Data as a stock-7z PPMd var.H stream.
   --  @param Data the bytes to compress
   --  @param Order PPMd model order (2 .. 64)
   --  @param Mem_Size sub-allocator size in bytes

   function Decompress
     (Data     : Byte_Array;
      Out_Size : Natural;
      Order    : Positive;
      Mem_Size : Interfaces.Unsigned_32;
      Status   : out Status_Code) return Byte_Array;
   --  Decode Out_Size bytes from a stock-7z PPMd var.H stream.
   --  @param Data the compressed PPMd stream
   --  @param Out_Size number of decoded bytes expected
   --  @param Order PPMd model order (2 .. 64), from the coder properties
   --  @param Mem_Size sub-allocator size in bytes, from the coder properties
   --  @param Status Ok on success, otherwise a decode error

end Zlib.PPMd7;
