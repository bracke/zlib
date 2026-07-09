with Interfaces;
with Zlib.LZMA_Core;
use type Interfaces.Unsigned_32;

package Zlib.LZMA_Repetitions is
   --  Support level: private internal implementation.
   --  Repeated-distance choice pricing helpers for the LZMA parser.

   function Choice_Price
     (Is_Rep_G0    : Zlib.LZMA_Core.Prob_Array;
      Is_Rep_G1    : Zlib.LZMA_Core.Prob_Array;
      Is_Rep_G2    : Zlib.LZMA_Core.Prob_Array;
      Is_Rep0_Long : Zlib.LZMA_Core.Prob_Array;
      State        : Natural;
      Rep_Index    : Natural;
      Pos_State    : Natural) return Natural
     with
       Pre =>
         State < Zlib.LZMA_Core.Num_States
         and then Pos_State < Zlib.LZMA_Core.Num_Pos_States_Max
         and then Is_Rep_G0'First <= 0
         and then Is_Rep_G0'Last >= Zlib.LZMA_Core.Num_States - 1
         and then Is_Rep_G1'First <= 0
         and then Is_Rep_G1'Last >= Zlib.LZMA_Core.Num_States - 1
         and then Is_Rep_G2'First <= 0
         and then Is_Rep_G2'Last >= Zlib.LZMA_Core.Num_States - 1
         and then Is_Rep0_Long'First <= 0
         and then Is_Rep0_Long'Last >=
           Zlib.LZMA_Core.Num_States * Zlib.LZMA_Core.Num_Pos_States_Max - 1
         and then
           (for all I in 0 .. Zlib.LZMA_Core.Num_States - 1 =>
              Is_Rep_G0 (I) < Zlib.LZMA_Core.Bit_Model_Total
              and then Is_Rep_G1 (I) < Zlib.LZMA_Core.Bit_Model_Total
              and then Is_Rep_G2 (I) < Zlib.LZMA_Core.Bit_Model_Total)
         and then
           (for all I in
              0 .. Zlib.LZMA_Core.Num_States * Zlib.LZMA_Core.Num_Pos_States_Max - 1 =>
              Is_Rep0_Long (I) < Zlib.LZMA_Core.Bit_Model_Total),
       Post => Choice_Price'Result <= 4 * 161,
       SPARK_Mode => On;

end Zlib.LZMA_Repetitions;
