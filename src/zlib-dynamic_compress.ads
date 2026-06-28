package Zlib.Dynamic_Compress is
   --  Support level: private internal implementation.
   --  Dynamic-Huffman zlib compressor.  This package uses the internal
   --  bounded LZ77 matcher at the default compression effort, including
   --  conservative lazy matching. It does not expose gzip output, ZIP output,
   --  or optimal parsing.

   function Deflate_Dynamic
     (Input : Zlib.Byte_Array; Status : out Zlib.Status_Code)
      return Zlib.Byte_Array;
   --  Return the Deflate Dynamic result.
   --  @param Input Input argument supplied to Deflate_Dynamic
   --  @param Status Status argument supplied to Deflate_Dynamic
   --  @return result produced by Deflate_Dynamic

end Zlib.Dynamic_Compress;
