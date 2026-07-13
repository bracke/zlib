package Zlib.BZip2_BWT is
   --  Support level: private internal implementation.
   --  Forward Burrows-Wheeler transform.
   --
   --  The rotations are sorted by prefix doubling with counting sorts, which is
   --  O(n log n) whatever the input. A naive comparison sort of the rotations
   --  degrades badly on long repeats -- precisely the data bzip2 is pointed at --
   --  so the guarantee matters more than the constant factor here.

   procedure Transform
     (Block    : Byte_Array;
      Last     : out Byte_Array;
      Orig_Ptr : out Natural)
     with Pre => Block'Length > 0 and then Last'Length = Block'Length;
   --  Sort the rotations of Block and take the last column.
   --  @param Block    the block to transform
   --  @param Last     the last column of the sorted rotation matrix, same bounds
   --  @param Orig_Ptr the row holding the original block, as the header stores it

end Zlib.BZip2_BWT;
