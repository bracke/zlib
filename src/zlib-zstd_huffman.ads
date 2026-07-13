with Interfaces;

with Zlib.Zstd_Tables;

package Zlib.Zstd_Huffman is
   --  Support level: private internal implementation.
   --  zstd's Huffman coder, used for a block's literals.
   --
   --  It does not describe code lengths directly. Each symbol carries a WEIGHT,
   --  and a symbol's code length is Max_Bits + 1 - weight, where Max_Bits follows
   --  from the weights themselves. The final symbol's weight is never stored: it
   --  is whatever makes the implied Kraft sum a power of two. The weight table is
   --  either written as packed nibbles or, when there are too many symbols for
   --  that, FSE-compressed with two interleaved states.

   Max_Bits   : constant Natural := 11;
   Max_Symbol : constant Natural := 255;

   type Decode_Table is private;
   type Encode_Table is private;

   procedure Read_Table
     (Data   : Byte_Array;
      First  : Natural;
      Table  : out Decode_Table;
      Used   : out Natural;
      Status : out Status_Code);
   --  Parse a Huffman tree description.
   --  @param Data   the payload
   --  @param First  index of the description's first byte
   --  @param Table  the resulting decode table
   --  @param Used   bytes consumed
   --  @param Status Ok, Invalid_Huffman_Code for a malformed description, or
   --                Unexpected_End_Of_Input

   procedure Decode_Stream
     (Table  : Decode_Table;
      Data   : Byte_Array;
      Output : out Byte_Array;
      Status : out Status_Code);
   --  Decode one Huffman bitstream into exactly Output'Length symbols.
   --  @param Table  the decode table
   --  @param Data   the bitstream, whose whole extent is the payload
   --  @param Output receives the literals
   --  @param Status Ok, Invalid_Huffman_Code, or Unexpected_End_Of_Input

   procedure Build_Encode
     (Frequencies : Zlib.Zstd_Tables.Value_Array;
      Table       : out Encode_Table;
      Usable      : out Boolean;
      Status      : out Status_Code);
   --  Build an encode table from literal frequencies.
   --  @param Frequencies count of each byte value, indexed 0 .. 255
   --  @param Table       the resulting encode table
   --  @param Usable      False when fewer than two distinct symbols occur, which
   --                     Huffman cannot code and the caller must send raw
   --  @param Status      Ok, or Invalid_Huffman_Code

   procedure Write_Table
     (Table  : Encode_Table;
      Output : out Byte_Array;
      Length : out Natural;
      Usable : out Boolean;
      Status : out Status_Code);
   --  Emit the tree description for Table.
   --
   --  Usable comes back False when the description cannot be expressed: the
   --  packed form tops out at 128 weights, and the FSE form cannot carry a
   --  degenerate weight alphabet, because a single weight value costs zero bits
   --  per symbol and the decoder recovers the symbol count from where the bits
   --  run out. zstd's own writer gives up in the same places; the caller must
   --  fall back to raw literals.
   --
   --  @param Table  the encode table
   --  @param Output receives the description
   --  @param Length bytes written
   --  @param Usable False when the caller must send raw literals instead
   --  @param Status Ok, or Invalid_Huffman_Code

   procedure Encode_Stream
     (Table  : Encode_Table;
      Plain  : Byte_Array;
      Output : out Byte_Array;
      Length : out Natural;
      Status : out Status_Code);
   --  Huffman-code Plain into a single bitstream.
   --  @param Table  the encode table
   --  @param Plain  the literals
   --  @param Output receives the bitstream
   --  @param Length bytes written
   --  @param Status Ok, or Invalid_Huffman_Code when the output would not fit

   function Coded_Bits
     (Table : Encode_Table;
      Plain : Byte_Array) return Natural;
   --  The bit cost of coding Plain, so the caller can tell whether Huffman is
   --  worth it at all.
   --  @param Table the encode table
   --  @param Plain the literals
   --  @return the total code length in bits

private

   Max_Table : constant Natural := 2 ** Max_Bits;

   type Entry_Record is record
      Symbol : Byte := 0;
      Bits   : Natural := 0;
   end record;

   type Entry_Array is array (0 .. Max_Table - 1) of Entry_Record;

   type Decode_Table is record
      Entries : Entry_Array;
      Log     : Natural := 0;
   end record;

   type Length_Array is array (0 .. Max_Symbol) of Natural;
   type Code_Array is array (0 .. Max_Symbol) of Interfaces.Unsigned_32;

   type Encode_Table is record
      Lengths    : Length_Array := [others => 0];
      Codes      : Code_Array := [others => 0];
      Weights    : Length_Array := [others => 0];
      Log        : Natural := 0;
      Last_Used  : Natural := 0;
   end record;

end Zlib.Zstd_Huffman;
