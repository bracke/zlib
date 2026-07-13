with Interfaces;

with Zlib.BZip2_Bits;

package Zlib.BZip2_Huffman is
   --  Support level: private internal implementation.
   --  bzip2 canonical Huffman decoding by the limit/base/perm method.
   --
   --  Zlib.Huffman is not reusable here. It caps code lengths at 15 and decodes
   --  through a 2**15 lookup table, while bzip2 allows lengths up to 23 -- a
   --  direct table would need 2**23 entries. It also reverses each code, because
   --  Deflate reads codes LSB-first, whereas bzip2 reads them MSB-first.
   --
   --  The limit/base/perm method walks the code length instead: read Min_Length
   --  bits, and while the value exceeds the longest code of that length (Limit),
   --  shift in one more bit. No table larger than the alphabet is built.

   Max_Alphabet    : constant Natural := 258;
   --  Largest bzip2 alphabet: 256 byte symbols, RUNA/RUNB, and EOB, minus the
   --  symbols absent from the block's symbol map.

   Max_Code_Length : constant Natural := 23;
   --  bzip2's hard ceiling on a code length.

   type Length_Array is array (Natural range <>) of Natural;
   --  Code length per symbol, indexed from 0.

   type Decode_Table is private;

   procedure Build
     (Lengths : Length_Array;
      Table   : out Decode_Table;
      Status  : out Status_Code);
   --  Build the decode tables for one Huffman group.
   --  @param Lengths code length of every symbol in the alphabet, each 1 .. 23
   --  @param Table   the resulting tables
   --  @param Status  Ok, or Invalid_Huffman_Code when a length is out of range
   --                 or the alphabet is empty

   function Decode
     (R      : in out Zlib.BZip2_Bits.Reader;
      Data   : Byte_Array;
      Table  : Decode_Table;
      Status : out Status_Code) return Natural;
   --  Decode one symbol.
   --  @param R      reader, advanced past the code
   --  @param Data   the payload
   --  @param Table  the group's decode tables
   --  @param Status Ok, Invalid_Huffman_Code when the code is not in the table,
   --                or Unexpected_End_Of_Input
   --  @return the symbol index

private

   type Limit_Array is array (0 .. Max_Code_Length + 1) of Interfaces.Integer_32;
   type Base_Array is array (0 .. Max_Code_Length + 1) of Interfaces.Integer_32;
   type Perm_Array is array (0 .. Max_Alphabet - 1) of Natural;

   type Decode_Table is record
      Limit       : Limit_Array := [others => 0];
      Base        : Base_Array := [others => 0];
      Perm        : Perm_Array := [others => 0];
      Min_Length  : Natural := 0;
      Max_Length  : Natural := 0;
      Alpha_Size  : Natural := 0;
   end record;

end Zlib.BZip2_Huffman;
