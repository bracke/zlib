package body Zlib.LZMA_Repetitions is

   function Choice_Price
     (Is_Rep_G0    : Zlib.LZMA_Core.Prob_Array;
      Is_Rep_G1    : Zlib.LZMA_Core.Prob_Array;
      Is_Rep_G2    : Zlib.LZMA_Core.Prob_Array;
      Is_Rep0_Long : Zlib.LZMA_Core.Prob_Array;
      State        : Natural;
      Rep_Index    : Natural;
      Pos_State    : Natural) return Natural
     with SPARK_Mode => On
   is
      Long_Index : constant Natural :=
        State * Zlib.LZMA_Core.Num_Pos_States_Max + Pos_State;
   begin
      case Rep_Index is
         when 0 =>
            return Zlib.LZMA_Core.Bit_Price (Is_Rep_G0 (State), 0)
              + Zlib.LZMA_Core.Bit_Price (Is_Rep0_Long (Long_Index), 1);
         when 1 =>
            return Zlib.LZMA_Core.Bit_Price (Is_Rep_G0 (State), 1)
              + Zlib.LZMA_Core.Bit_Price (Is_Rep_G1 (State), 0);
         when 2 =>
            return Zlib.LZMA_Core.Bit_Price (Is_Rep_G0 (State), 1)
              + Zlib.LZMA_Core.Bit_Price (Is_Rep_G1 (State), 1)
              + Zlib.LZMA_Core.Bit_Price (Is_Rep_G2 (State), 0);
         when others =>
            return Zlib.LZMA_Core.Bit_Price (Is_Rep_G0 (State), 1)
              + Zlib.LZMA_Core.Bit_Price (Is_Rep_G1 (State), 1)
              + Zlib.LZMA_Core.Bit_Price (Is_Rep_G2 (State), 1);
      end case;
   end Choice_Price;

end Zlib.LZMA_Repetitions;
