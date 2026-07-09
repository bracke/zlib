with Interfaces;
with Zlib.Bit_Writer;
with Zlib.LZMA_Core;

package Zlib.LZMA_Range_Encoder is
   --  Support level: private internal implementation.
   --  Range-encoder emission helpers shared by LZMA and LZMA2 writers.

   type Encoder is record
      Low        : Interfaces.Unsigned_64 := 0;
      Range_Code : Interfaces.Unsigned_32 := Interfaces.Unsigned_32'Last;
      Cache      : Interfaces.Unsigned_32 := 0;
      Cache_Size : Natural := 1;
      Writer     : Zlib.Bit_Writer.Writer;
   end record;

   procedure Shift_Low (E : in out Encoder);

   function Finish (E : in out Encoder) return Byte_Array;

   procedure Encode_Bit
     (E    : in out Encoder;
      Prob : in out Interfaces.Unsigned_32;
      Bit  : Natural);

   procedure Encode_Bit_Tree
     (E      : in out Encoder;
      Probs  : in out Zlib.LZMA_Core.Prob_Array;
      Offset : Natural;
      Bits   : Natural;
      Symbol : Natural);

   procedure Encode_Reverse_Bit_Tree
     (E      : in out Encoder;
      Probs  : in out Zlib.LZMA_Core.Prob_Array;
      Offset : Integer;
      Bits   : Natural;
      Symbol : Natural);

   procedure Encode_Direct_Bits
     (E     : in out Encoder;
      Value : Natural;
      Bits  : Natural);

   procedure Encode_Distance
     (E           : in out Encoder;
      Pos_Slot    : in out Zlib.LZMA_Core.Prob_Array;
      Pos_Special : in out Zlib.LZMA_Core.Prob_Array;
      Pos_Align   : in out Zlib.LZMA_Core.Prob_Array;
      Len         : Natural;
      Distance    : Natural);

   procedure Encode_Len
     (E         : in out Encoder;
      Len       : in out Zlib.LZMA_Core.Len_Encoder;
      Pos_State : Natural;
      Symbol    : Natural);

   function Tree_Price
     (Probs  : Zlib.LZMA_Core.Prob_Array;
      Offset : Natural;
      Bits   : Natural;
      Symbol : Natural) return Natural;

   function Reverse_Tree_Price
     (Probs  : Zlib.LZMA_Core.Prob_Array;
      Offset : Integer;
      Bits   : Natural;
      Symbol : Natural) return Natural;

   function Len_Price
     (Len       : Zlib.LZMA_Core.Len_Encoder;
      Pos_State : Natural;
      Symbol    : Natural) return Natural;

   function Distance_Price
     (Pos_Slot    : Zlib.LZMA_Core.Prob_Array;
      Pos_Special : Zlib.LZMA_Core.Prob_Array;
      Pos_Align   : Zlib.LZMA_Core.Prob_Array;
      Len         : Natural;
      Distance    : Natural) return Natural;

end Zlib.LZMA_Range_Encoder;
