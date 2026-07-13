private with Ada.Containers.Vectors;

with Interfaces;

package Zlib.BZip2_Bit_Writer is
   --  Support level: private internal implementation.
   --  MSB-first bit writer, the counterpart of Zlib.BZip2_Bits.
   --
   --  Zlib.Bit_Writer is LSB-first, because that is how Deflate packs bits.
   --  bzip2 packs them the other way, so it needs its own writer.

   type Writer is private;

   procedure Reset (W : out Writer);
   --  Empty W.
   --  @param W the writer to reset

   procedure Write_Bit (W : in out Writer; Bit : Boolean);
   --  Append one bit.
   --  @param W   the writer
   --  @param Bit the bit to append

   procedure Write_Bits
     (W     : in out Writer;
      Value : Interfaces.Unsigned_32;
      Count : Natural)
     with Pre => Count <= 32;
   --  Append the Count low bits of Value, most significant first.
   --  @param W     the writer
   --  @param Value the field value
   --  @param Count number of bits to take from Value, at most 32

   procedure Flush (W : in out Writer);
   --  Pad the final byte with zero bits. bzip2 pads the end of a stream this way.
   --  @param W the writer

   function To_Array (W : Writer) return Byte_Array;
   --  The bytes written so far. Call Flush first, or a partial byte is dropped.
   --  @param W the writer
   --  @return the written bytes, indexed from 1

private

   package Byte_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Byte);

   type Writer is record
      Data      : Byte_Vectors.Vector;
      Current   : Byte := 0;
      Bit_Index : Natural range 0 .. 7 := 0;
      --  Bits already placed in Current, from the most significant end.
   end record;

end Zlib.BZip2_Bit_Writer;
