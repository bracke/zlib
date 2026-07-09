with Zlib.LZMA_Core;

package Zlib.LZMA_Encoder is
   --  Support level: private internal implementation.
   --  Bounded LZMA encoder and optimal-parser orchestration.

   function Encode_Bounded
     (Plain          : Byte_Array;
      Lit_Ctx_Bits   : Natural := Zlib.LZMA_Core.Default_LC;
      Lit_Pos_Bits   : Natural := Zlib.LZMA_Core.Default_LP;
      Pos_State_Bits : Natural := Zlib.LZMA_Core.Default_PB) return Byte_Array;

end Zlib.LZMA_Encoder;
