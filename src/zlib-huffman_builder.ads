package Zlib.Huffman_Builder is
   --  Support level: private internal implementation.
   --  Deterministic Deflate-oriented Huffman length builder.
   --
   --  This is a conservative compressor-side foundation.  It
   --  produces valid, bounded code lengths for a caller-provided frequency
   --  table.  The result is intentionally simple rather than optimal: all
   --  present symbols receive one uniform length large enough to represent the
   --  present alphabet.  This keeps dynamic blocks deterministic and valid
   --  while keeping optimal length generation out of the current scope.

   Max_Deflate_Code_Length : constant Natural := 15;

   type Frequency_Array is array (Natural range <>) of Natural;
   type Length_Array is array (Natural range <>) of Natural range 0 .. Max_Deflate_Code_Length;

   procedure Build_Lengths
     (Frequencies     : Frequency_Array;
      Lengths         : out Length_Array;
      Required_Symbol : Natural);
   --  Build deterministic code lengths from Frequencies.
   --  Required_Symbol is forced present even when its frequency is zero.  The
   --  output range must match Frequencies'Range.  At least two symbols are
   --  made present when possible because one-symbol dynamic alphabets are less
   --  portable across Deflate implementations.
   --  @param Frequencies Frequencies argument supplied to Build_Lengths
   --  @param Lengths Lengths argument supplied to Build_Lengths
   --  @param Required_Symbol Required_Symbol argument supplied to Build_Lengths
end Zlib.Huffman_Builder;
