with Zlib.LZMA_Core;
with Zlib.LZMA_Range_Encoder;

package Zlib.LZMA_Literals is
   --  Support level: private internal implementation.
   --  Literal encoder and literal pricing helpers shared by LZMA writers.

   procedure Encode
     (E            : in out Zlib.LZMA_Range_Encoder.Encoder;
      Literals     : in out Zlib.LZMA_Core.Prob_Array;
      Plain        : Byte_Array;
      Index        : Natural;
      State        : Natural;
      Rep0         : Natural;
      Position     : Natural;
      Lit_Ctx_Bits : Natural;
      Lit_Pos_Bits : Natural;
      Prev         : Byte);

   function Price
     (Literals     : Zlib.LZMA_Core.Prob_Array;
      Plain        : Byte_Array;
      Index        : Natural;
      State        : Natural;
      Rep0         : Natural;
      Position     : Natural;
      Lit_Ctx_Bits : Natural;
      Lit_Pos_Bits : Natural) return Natural;

end Zlib.LZMA_Literals;
