with Zlib.LZMA_Core;

package Zlib.LZMA2_Decoder is
   --  Support level: private internal implementation.
   --  Stateful LZMA payload decoder used inside LZMA2 chunk streams.

   type Context is private;

   procedure Reset_State (Ctx : in out Context);

   function Set_Properties
     (Ctx   : in out Context;
      Props : Byte) return Boolean;

   function Properties_Seen (Ctx : Context) return Boolean
     with SPARK_Mode => On;

   procedure Reset_Dictionary
     (Ctx     : in out Context;
      Out_Pos : Natural)
     with SPARK_Mode => On;

   procedure Decode_Compressed_Chunk
     (Ctx       : in out Context;
      Stream    : Byte_Array;
      Plain     : in out Byte_Array;
      Out_Pos   : in out Natural;
      Chunk_Len : Natural;
      Status    : in out Status_Code);

   function Decode
     (Payload   : Byte_Array;
      Plain_Len : Natural;
      Status    : out Status_Code) return Byte_Array;

private
   type Context is record
      LC           : Natural := Zlib.LZMA_Core.Default_LC;
      LP           : Natural := Zlib.LZMA_Core.Default_LP;
      PB           : Natural := Zlib.LZMA_Core.Default_PB;
      Props_Seen   : Boolean := False;
      Dict_Base    : Natural := 0;
      State        : Natural := 0;
      Prev         : Byte := 0;
      Rep0         : Natural := 0;
      Rep1         : Natural := 0;
      Rep2         : Natural := 0;
      Rep3         : Natural := 0;
      Is_Match     : Zlib.LZMA_Core.Prob_Array
        (0 .. Zlib.LZMA_Core.Num_States * Zlib.LZMA_Core.Num_Pos_States_Max - 1);
      Is_Rep       : Zlib.LZMA_Core.Prob_Array (0 .. Zlib.LZMA_Core.Num_States - 1);
      Is_Rep_G0    : Zlib.LZMA_Core.Prob_Array (0 .. Zlib.LZMA_Core.Num_States - 1);
      Is_Rep_G1    : Zlib.LZMA_Core.Prob_Array (0 .. Zlib.LZMA_Core.Num_States - 1);
      Is_Rep_G2    : Zlib.LZMA_Core.Prob_Array (0 .. Zlib.LZMA_Core.Num_States - 1);
      Is_Rep0_Long : Zlib.LZMA_Core.Prob_Array
        (0 .. Zlib.LZMA_Core.Num_States * Zlib.LZMA_Core.Num_Pos_States_Max - 1);
      Match_Len    : Zlib.LZMA_Core.Len_Encoder;
      Rep_Len      : Zlib.LZMA_Core.Len_Encoder;
      Pos_Slot     : Zlib.LZMA_Core.Prob_Array
        (0 .. Zlib.LZMA_Core.Num_Len_To_Pos_States * 64 - 1);
      Pos_Special  : Zlib.LZMA_Core.Prob_Array
        (0 .. Zlib.LZMA_Core.Num_Full_Distances - Zlib.LZMA_Core.End_Pos_Model_Index - 1);
      Pos_Align    : Zlib.LZMA_Core.Prob_Array (0 .. Zlib.LZMA_Core.Align_Table_Size - 1);
      Literals     : Zlib.LZMA_Core.Prob_Array
        (0 .. (2 ** 4) * Zlib.LZMA_Core.Literal_Probs - 1);
   end record;
end Zlib.LZMA2_Decoder;
