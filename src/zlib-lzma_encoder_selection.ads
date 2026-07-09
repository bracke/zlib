generic
   with function Encode_Bounded
     (Plain          : Byte_Array;
      Lit_Ctx_Bits   : Natural;
      Lit_Pos_Bits   : Natural;
      Pos_State_Bits : Natural) return Byte_Array;
function Zlib.LZMA_Encoder_Selection
  (Plain : Byte_Array;
   Props : out Byte) return Byte_Array;
--  Support level: private internal implementation.
--  Selects the smallest bounded LZMA encoding across supported property candidates.
