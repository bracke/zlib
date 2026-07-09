with Ada.Streams;

package Zlib.Stream_Bits is
   --  Support level: private internal implementation.
   --  Incremental Deflate bit input source used by the streaming inflate
   --  implementation. Bits are read least-significant-bit first.

   type Bit_Source is private;
   --  Buffered incremental input source with Deflate bit ordering.

   type Read_Status is
     (Ok,
      Need_Input,
      Invalid_State);
   --  Result of attempting to read bits from the incremental source.

   procedure Reset
     (Source : in out Bit_Source);
   --  Clear all buffered input and reset bit alignment.
   --  @param Source Source argument supplied to Reset
   procedure Append
     (Source : in out Bit_Source;
      Data   : Ada.Streams.Stream_Element_Array);
   --  Append new compressed bytes after the current buffered suffix.
   --  @param Source Source argument supplied to Append
   --  @param Data Data argument supplied to Append
   function Buffered_Bytes
     (Source : Bit_Source)
      return Natural;
   --  Return the number of complete bytes currently buffered.
   --  @param Source Source argument supplied to Buffered_Bytes
   --  @return result produced by Buffered_Bytes
   function Has_Bits
     (Source : Bit_Source;
      Count  : Natural)
      return Boolean;
   --  Return True when Count bits can be read without additional input.
   --  @param Source Source argument supplied to Has_Bits
   --  @param Count Count argument supplied to Has_Bits
   --  @return result produced by Has_Bits
   function Read_Bit
     (Source : in out Bit_Source;
      Status : out Read_Status)
      return Boolean;
   --  Read one Deflate-ordered bit.
   --  @param Source Source argument supplied to Read_Bit
   --  @param Status Status argument supplied to Read_Bit
   --  @return result produced by Read_Bit
   function Read_Bits
     (Source : in out Bit_Source;
      Count  : Natural;
      Status : out Read_Status)
      return Natural;
   --  Read Count Deflate-ordered bits as a little-endian integer field.
   --  @param Source Source argument supplied to Read_Bits
   --  @param Count Count argument supplied to Read_Bits
   --  @param Status Status argument supplied to Read_Bits
   --  @return result produced by Read_Bits
   procedure Align_To_Byte
     (Source : in out Bit_Source);
   --  Discard any partial byte bits and advance to the next byte boundary.
   --  @param Source Source argument supplied to Align_To_Byte
   function Read_Byte_Aligned
     (Source : in out Bit_Source;
      Status : out Read_Status)
      return Ada.Streams.Stream_Element;
   --  Read one byte from an already byte-aligned source.
   --  @param Source Source argument supplied to Read_Byte_Aligned
   --  @param Status Status argument supplied to Read_Byte_Aligned
   --  @return result produced by Read_Byte_Aligned
   function Peek_Byte_Aligned
     (Source : Bit_Source;
      Offset : Natural;
      Status : out Read_Status)
      return Ada.Streams.Stream_Element;
   --  Return a byte from an already byte-aligned source without consuming it.
   --  Offset is zero-based from the next byte that would be read.
   --  @param Source Source argument supplied to Peek_Byte_Aligned
   --  @param Offset Offset argument supplied to Peek_Byte_Aligned
   --  @param Status Status argument supplied to Peek_Byte_Aligned
   --  @return result produced by Peek_Byte_Aligned
   function Input_Consumed
     (Source : Bit_Source)
      return Natural;
   --  Return how many bytes from the most recent append have been consumed.
   --  @param Source Source argument supplied to Input_Consumed
   --  @return result produced by Input_Consumed
private
   Max_Buffered_Bytes : constant Natural := 32 * 1024;

   subtype Buffer_Index is Natural range 1 .. Max_Buffered_Bytes;
   type Byte_Buffer is array (Buffer_Index) of Ada.Streams.Stream_Element;

   type Bit_Source is record
      --  Fixed storage avoids hot-path heap allocation across repeated
      --  Translate calls. First/Last describe the live inclusive range;
   --  First > Last means empty.
      Buffer : Byte_Buffer := [others => 0];
      First  : Natural := 1;
      Last   : Natural := 0;
      Bit    : Natural range 0 .. 7 := 0;

      Absolute_Consumed : Natural := 0;
      Absolute_Appended : Natural := 0;
      Last_Append_First : Natural := 0;
      Last_Append_Last  : Natural := 0;
   end record;
end Zlib.Stream_Bits;
