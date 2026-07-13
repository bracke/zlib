with Interfaces;

package Zlib.BZip2_Lengths is
   --  Support level: private internal implementation.
   --  bzip2 Huffman code-length construction and canonical code assignment.
   --
   --  Zlib.Huffman_Builder cannot be used: by its own admission it is "not
   --  optimal", giving every present symbol one uniform length. bzip2 needs real
   --  Huffman lengths, and needs them bounded (17 bits when encoding), which the
   --  algorithm below achieves the way bzip2 does -- by carrying each node's
   --  depth in the low bits of its weight so that ties break towards shallower
   --  trees, and, if the bound is still exceeded, halving the frequencies and
   --  rebuilding.

   Encode_Max_Length : constant Natural := 17;
   --  The length cap bzip2's encoder works to. The format permits 23.

   type Frequency_Array is array (Natural range <>) of Natural;
   type Length_Array is array (Natural range <>) of Natural;
   type Code_Array is array (Natural range <>) of Interfaces.Unsigned_32;

   procedure Make_Code_Lengths
     (Frequencies : Frequency_Array;
      Lengths     : out Length_Array;
      Max_Length  : Natural := Encode_Max_Length)
     with Pre => Frequencies'Length = Lengths'Length
                 and then Frequencies'Length >= 2;
   --  Build Huffman code lengths, none exceeding Max_Length. Absent symbols
   --  (frequency zero) are treated as frequency one, so every symbol gets a
   --  usable code, as bzip2 requires.
   --  @param Frequencies symbol frequencies, indexed from 0
   --  @param Lengths     the resulting code lengths, same bounds
   --  @param Max_Length  the length cap

   procedure Assign_Codes
     (Lengths : Length_Array;
      Codes   : out Code_Array)
     with Pre => Lengths'Length = Codes'Length;
   --  Assign canonical codes, shortest length first, ascending within a length.
   --  @param Lengths the code lengths
   --  @param Codes   the resulting codes, same bounds

end Zlib.BZip2_Lengths;
