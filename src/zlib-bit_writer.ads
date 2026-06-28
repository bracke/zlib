with Ada.Containers.Vectors;

package Zlib.Bit_Writer is
   --  Support level: private internal implementation.
   --  LSB-first bit writer for Deflate payload generation.

   type Writer is private;

   procedure Reset
     (W : out Writer);
   --  Reset W to an empty output buffer.
   --  @param W W argument supplied to Reset
   procedure Write_Bits
     (W     : in out Writer;
      Value : Natural;
      Count : Natural);
   --  Write Count low bits from Value, least-significant bit first.
   --  @param W W argument supplied to Write_Bits
   --  @param Value Value argument supplied to Write_Bits
   --  @param Count Count argument supplied to Write_Bits
   procedure Write_Byte_Aligned
     (W : in out Writer;
      B : Zlib.Byte);
   --  Append one byte. W must already be byte-aligned.
   --  @param W W argument supplied to Write_Byte_Aligned
   --  @param B B argument supplied to Write_Byte_Aligned
   procedure Flush_Byte
     (W : in out Writer);
   --  Pad the current partial byte with zero bits and append it.
   --  @param W W argument supplied to Flush_Byte
   function Is_Byte_Aligned
     (W : Writer)
      return Boolean;
   --  Return True when W has no partially-filled byte.
   --  @param W W argument supplied to Is_Byte_Aligned
   --  @return result produced by Is_Byte_Aligned
   function To_Array
     (W : Writer)
      return Zlib.Byte_Array;
   --  Return the completed byte buffer. Any partial byte is not implicitly
   --  flushed; callers must call Flush_Byte first when padding is required.
   --  @param W W argument supplied to To_Array
   --  @return result produced by To_Array
private
   package Byte_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Zlib.Byte);

   type Writer is record
      Data         : Byte_Vectors.Vector;
      Current_Byte : Zlib.Byte := 0;
      Bit_Index    : Natural range 0 .. 7 := 0;
   end record;
end Zlib.Bit_Writer;
