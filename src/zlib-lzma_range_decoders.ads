with Interfaces;
with Zlib.LZMA_Core;

package Zlib.LZMA_Range_Decoders is
   --  Support level: private internal implementation.
   --  Range-decoder helpers shared by LZMA and LZMA2 payload readers.

   type Decoder is record
      Code       : Interfaces.Unsigned_32 := 0;
      Range_Code : Interfaces.Unsigned_32 := Interfaces.Unsigned_32'Last;
      Pos        : Natural := 0;
   end record;

   function Read_Stream_Byte
     (D      : in out Decoder;
      Stream : Byte_Array;
      Status : in out Status_Code) return Interfaces.Unsigned_32;

   procedure Init
     (D      : in out Decoder;
      Stream : Byte_Array;
      Status : in out Status_Code);

   function Decode_Bit
     (D      : in out Decoder;
      Stream : Byte_Array;
      Prob   : in out Interfaces.Unsigned_32;
      Status : in out Status_Code) return Natural;

   function Decode_Bit_Tree
     (D      : in out Decoder;
      Stream : Byte_Array;
      Probs  : in out Zlib.LZMA_Core.Prob_Array;
      Offset : Natural;
      Bits   : Natural;
      Status : in out Status_Code) return Natural;

   function Decode_Reverse_Bit_Tree
     (D      : in out Decoder;
      Stream : Byte_Array;
      Probs  : in out Zlib.LZMA_Core.Prob_Array;
      Offset : Integer;
      Bits   : Natural;
      Status : in out Status_Code) return Natural;

   function Decode_Direct_Bits
     (D      : in out Decoder;
      Stream : Byte_Array;
      Bits   : Natural;
      Status : in out Status_Code) return Natural;

   function Decode_Distance
     (D           : in out Decoder;
      Stream      : Byte_Array;
      Pos_Slot    : in out Zlib.LZMA_Core.Prob_Array;
      Pos_Special : in out Zlib.LZMA_Core.Prob_Array;
      Pos_Align   : in out Zlib.LZMA_Core.Prob_Array;
      Len         : Natural;
      Status      : in out Status_Code) return Natural;

   function Decode_Len
     (D         : in out Decoder;
      Stream    : Byte_Array;
      Len       : in out Zlib.LZMA_Core.Len_Encoder;
      Pos_State : Natural;
      Status    : in out Status_Code) return Natural;

end Zlib.LZMA_Range_Decoders;
