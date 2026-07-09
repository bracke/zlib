with Zlib.Bits;
with Zlib.Stream_Bits;

package Zlib.Huffman is
   --  Support level: private internal implementation.
   --  Canonical Huffman table builder and decoder for Deflate.

   Max_Symbols : constant Natural := 320;

   subtype Symbol_Value is Natural range 0 .. Max_Symbols - 1;
   subtype Code_Length is Natural range 0 .. 15;

   type Code_Length_Array is array (Natural range <>) of Code_Length;
   --  Deflate Huffman code lengths by symbol index.

   type Decode_Table is private;
   --  Decode table built from canonical Deflate code lengths.

   procedure Clear
     (Table : out Decode_Table)
     with SPARK_Mode => On;
   --  Reset Table to contain no codes.
   --  @param Table decode table to clear

   procedure Build
     (Lengths : Code_Length_Array;
      Table   : out Decode_Table;
      Status  : out Zlib.Status_Code);
   --  Build a canonical Huffman decode table.
   --  @param Lengths code lengths by symbol
   --  @param Table resulting decode table
   --  @param Status set to Ok or Invalid_Huffman_Code

   function Decode
     (R      : in out Zlib.Bits.Bit_Reader;
      Table  : Decode_Table;
      Status : out Zlib.Status_Code)
      return Symbol_Value;
   --  Decode one symbol from R using Table.
   --  @param R bit reader
   --  @param Table decode table
   --  @param Status set to Ok or a decode failure
   --  @return decoded symbol when Status is Ok

   function Decode_Streaming
     (Source      : in out Zlib.Stream_Bits.Bit_Source;
      Table       : Decode_Table;
      Code        : in out Natural;
      Length      : in out Code_Length;
      Read_Status : out Zlib.Stream_Bits.Read_Status;
      Status      : out Zlib.Status_Code)
      return Symbol_Value;
   --  Incrementally decode one symbol from Source using Table. Code and
   --  Length hold the partially-read LSB-first code between calls and are
   --  reset to zero when a symbol is completed or a malformed code is found.
   --  @param Source Source argument supplied to Decode_Streaming
   --  @param Table Table argument supplied to Decode_Streaming
   --  @param Code Code argument supplied to Decode_Streaming
   --  @param Length Length argument supplied to Decode_Streaming
   --  @param Read_Status Read_Status argument supplied to Decode_Streaming
   --  @param Status Status argument supplied to Decode_Streaming
   --  @return result produced by Decode_Streaming
private
   Max_Code_Bits : constant Natural := 15;
   Table_Size    : constant Natural := 2 ** Max_Code_Bits;

   type Decode_E is record
      Used   : Boolean := False;
      Symbol : Symbol_Value := 0;
      Length : Code_Length := 0;
   end record;

   type Lookup_Array is array (Natural range 0 .. Table_Size - 1) of Decode_E;

   type Decode_Table is record
      Lookup     : Lookup_Array;
      Min_Length : Code_Length := 0;
      Max_Length : Code_Length := 0;
      Used_Count : Natural := 0;
   end record;
end Zlib.Huffman;
