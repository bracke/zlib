private with Ada.Containers.Vectors;

with Interfaces;

package Zlib.Zstd_Bits is
   --  Support level: private internal implementation.
   --  zstd's two bit orders.
   --
   --  zstd reads an FSE table description FORWARD, least-significant bit first,
   --  but reads the FSE and Huffman payloads BACKWARD: starting at the last byte,
   --  most-significant bit first, working towards the first byte. The last byte
   --  carries a set "end mark" bit above the payload, and the padding above that
   --  is discarded. Both orders are needed, so both live here.

   ----------------------------------------------------------------------------
   --  Forward, LSB-first: FSE table descriptions.
   ----------------------------------------------------------------------------

   type Forward_Reader is private;

   procedure Reset (R : out Forward_Reader; First : Natural);
   --  Position R at the first bit of the byte at index First.
   --  @param R     the reader
   --  @param First index of the first payload byte

   function Read
     (R      : in out Forward_Reader;
      Data   : Byte_Array;
      Count  : Natural;
      Status : out Status_Code) return Interfaces.Unsigned_32
     with Pre => Count <= 32;
   --  Read Count bits, least significant first.
   --  @param R      the reader, advanced by Count bits
   --  @param Data   the payload
   --  @param Count  number of bits, at most 32
   --  @param Status Ok, or Unexpected_End_Of_Input
   --  @return the field value

   function Peek
     (R      : Forward_Reader;
      Data   : Byte_Array;
      Count  : Natural) return Interfaces.Unsigned_32
     with Pre => Count <= 32;
   --  Read Count bits without advancing; bits past the end read as zero, which
   --  is what the table-description decoder expects at the tail.
   --  @param R     the reader
   --  @param Data  the payload
   --  @param Count number of bits, at most 32
   --  @return the field value

   procedure Skip (R : in out Forward_Reader; Count : Natural);
   --  Advance by Count bits without reading.
   --  @param R     the reader
   --  @param Count number of bits

   function Bytes_Used (R : Forward_Reader; First : Natural) return Natural;
   --  Number of whole bytes the reader has entered, rounding a partial byte up.
   --  @param R     the reader
   --  @param First the index passed to Reset
   --  @return the byte count consumed

   ----------------------------------------------------------------------------
   --  Backward, MSB-first: FSE and Huffman payloads.
   ----------------------------------------------------------------------------

   type Backward_Reader is private;

   procedure Start
     (R      : out Backward_Reader;
      Data   : Byte_Array;
      Status : out Status_Code);
   --  Position R just below the end mark in Data's last byte.
   --  @param R      the reader
   --  @param Data   the payload; the whole array is the bitstream
   --  @param Status Ok, Unexpected_End_Of_Input for an empty payload, or
   --                Invalid_Block_Type when the last byte has no end mark

   function Read
     (R      : in out Backward_Reader;
      Data   : Byte_Array;
      Count  : Natural;
      Status : out Status_Code) return Interfaces.Unsigned_32
     with Pre => Count <= 32;
   --  Read Count bits; the first bit read is the most significant of the result.
   --  @param R      the reader, advanced by Count bits
   --  @param Data   the payload
   --  @param Count  number of bits, at most 32
   --  @param Status Ok, or Unexpected_End_Of_Input
   --  @return the field value

   function Exhausted (R : Backward_Reader) return Boolean;
   --  True once every payload bit has been consumed.
   --  @param R the reader
   --  @return whether the stream is spent

   ----------------------------------------------------------------------------
   --  Backward writer: produces a stream the backward reader accepts.
   ----------------------------------------------------------------------------

   type Backward_Writer is private;

   procedure Reset (W : out Backward_Writer);
   --  Empty W.
   --  @param W the writer

   procedure Write
     (W     : in out Backward_Writer;
      Value : Interfaces.Unsigned_32;
      Count : Natural)
     with Pre => Count <= 32;
   --  Append one field, in ENCODER order. Finish lays the fields out back to
   --  front, so the LAST field written is the FIRST a Backward_Reader returns --
   --  the convention zstd's entropy coders rely on, since an FSE state depends
   --  on the symbols that follow it and so must be encoded in reverse.
   --  @param W     the writer
   --  @param Value the field value
   --  @param Count number of bits, at most 32

   function Finish (W : Backward_Writer) return Byte_Array;
   --  Add the end mark and pad, then lay the bits out back to front.
   --  @param W the writer
   --  @return the bitstream bytes, indexed from 1

private

   type Field is record
      Value : Interfaces.Unsigned_32 := 0;
      Count : Natural := 0;
   end record;

   package Field_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Field);

   type Forward_Reader is record
      Next_Byte : Natural := 0;
      Bit_Index : Natural range 0 .. 7 := 0;
   end record;

   type Backward_Reader is record
      --  Position in the virtual bit sequence: byte order reversed, and within
      --  each byte most-significant bit first.
      Position : Natural := 0;
      Total    : Natural := 0;
   end record;

   type Backward_Writer is record
      Fields : Field_Vectors.Vector;
      Length : Natural := 0;
      --  Total bit count across Fields.
   end record;

end Zlib.Zstd_Bits;
