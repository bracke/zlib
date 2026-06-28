with Ada.Containers.Vectors;

package Zlib.Bits is
   --  Support level: private internal implementation.
   --  Legacy complete-buffer LSB-first bit reader for Deflate payloads.
   --  Streaming decode uses Zlib.Stream_Bits; this package remains internal
   --  test and maintenance support.

   type Bit_Reader is private;
   --  Cursor over a byte buffer with Deflate bit ordering.

   procedure Init
     (R    : out Bit_Reader;
      Data : Zlib.Byte_Array);
   --  Initialize R to read from Data.
   --  @param R reader to initialize
   --  @param Data byte buffer to read

   function Read_Bit
     (R      : in out Bit_Reader;
      Status : out Zlib.Status_Code)
      return Boolean;
   --  Read one bit in Deflate LSB-first order.
   --  @param R reader cursor
   --  @param Status set to Ok or Unexpected_End_Of_Input
   --  @return bit value when Status is Ok

   function Read_Bits
     (R      : in out Bit_Reader;
      Count  : Natural;
      Status : out Zlib.Status_Code)
      return Natural;
   --  Read Count bits as a little-endian bit-field.
   --  @param R reader cursor
   --  @param Count number of bits to read
   --  @param Status set to Ok or Unexpected_End_Of_Input
   --  @return decoded integer when Status is Ok

   procedure Align_To_Byte
     (R : in out Bit_Reader);
   --  Advance R to the next byte boundary.
   --  @param R reader cursor

   function Read_Byte_Aligned
     (R      : in out Bit_Reader;
      Status : out Zlib.Status_Code)
      return Zlib.Byte;
   --  Read a full byte from an already byte-aligned cursor.
   --  @param R reader cursor
   --  @param Status set to Ok, Invalid_Stored_Block, or Unexpected_End_Of_Input
   --  @return byte value when Status is Ok

private
   package Byte_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Zlib.Byte);

   type Bit_Reader is record
      Data       : Byte_Vectors.Vector;
      Byte_Index : Natural := 0;
      Bit_Index  : Natural range 0 .. 7 := 0;
   end record;
end Zlib.Bits;
