with Interfaces;

package Zlib.BZip2_Bits is
   --  Support level: private internal implementation.
   --  MSB-first bit reader over a Byte_Array, for bzip2 payloads.
   --
   --  The crate's existing readers (Zlib.Bits, Zlib.Stream_Bits) are LSB-first,
   --  because that is how Deflate packs bits. bzip2 packs them the other way --
   --  the first bit of a byte is bit 7, and a multi-bit field is big-endian --
   --  so it needs its own reader rather than a flag on the existing one.
   --
   --  The reader holds only a position; the payload is passed to each call, so
   --  no copy of the input is made.

   type Reader is private;

   procedure Reset (R : out Reader; First : Natural);
   --  Position R at the first bit of the byte at index First.
   --  @param R     the reader to initialise
   --  @param First index of the first payload byte, i.e. Data'First

   function Read_Bit
     (R      : in out Reader;
      Data   : Byte_Array;
      Status : out Status_Code) return Boolean;
   --  Read one bit, most-significant bit of the current byte first.
   --  @param R      reader, advanced by one bit
   --  @param Data   the payload
   --  @param Status Ok, or Unexpected_End_Of_Input when the payload is exhausted
   --  @return the bit value

   function Read_Bits
     (R      : in out Reader;
      Data   : Byte_Array;
      Count  : Natural;
      Status : out Status_Code) return Interfaces.Unsigned_32
     with Pre => Count <= 32;
   --  Read Count bits as a big-endian bit-field: the first bit read is the most
   --  significant bit of the result.
   --  @param R      reader, advanced by Count bits
   --  @param Data   the payload
   --  @param Count  number of bits, at most 32
   --  @param Status Ok, or Unexpected_End_Of_Input when the payload is exhausted
   --  @return the field value, zero-extended

   procedure Align_To_Byte (R : in out Reader);
   --  Discard bits up to the next byte boundary. bzip2 pads the final byte of a
   --  stream, so a concatenated stream starts here.
   --  @param R the reader to align

   function Byte_Position (R : Reader) return Natural;
   --  Index of the byte holding the next bit.
   --  @param R the reader
   --  @return the byte index

   function Is_Byte_Aligned (R : Reader) return Boolean;
   --  True when the next bit is the most-significant bit of a byte.
   --  @param R the reader
   --  @return whether R sits on a byte boundary

private

   type Reader is record
      Next_Byte : Natural := 0;
      --  Index of the byte holding the next bit.
      Bit_Index : Natural range 0 .. 7 := 0;
      --  Bits already consumed from Next_Byte; 0 selects bit 7, the MSB.
   end record;

end Zlib.BZip2_Bits;
