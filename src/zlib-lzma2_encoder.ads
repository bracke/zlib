generic
   with function Encode_Selected
     (Plain : Byte_Array;
      Props : out Byte) return Byte_Array;
function Zlib.LZMA2_Encoder (Plain : Byte_Array) return Byte_Array;
--  Support level: private internal implementation.
--  LZMA2 chunk-level encoder over the selected LZMA payload encoder.
