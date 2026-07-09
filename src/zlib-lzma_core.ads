with Interfaces;
use type Interfaces.Unsigned_32;
with Zlib.LZMA_Properties;

package Zlib.LZMA_Core
  with SPARK_Mode => On
is
   --  Support level: private internal implementation.
   --  Shared LZMA constants, property candidates, probability helpers, and state transitions.

   Bit_Model_Total        : constant Interfaces.Unsigned_32 := 2 ** 11;
   Move_Bits              : constant Natural := 5;
   Top_Value              : constant Interfaces.Unsigned_32 := 2 ** 24;
   Num_States             : constant Natural := 12;
   Literal_Probs          : constant Natural := 16#300#;
   Num_Pos_States_Max     : constant Natural := 16;
   Num_Len_To_Pos_States  : constant Natural := 4;
   Len_Low_Symbols        : constant Natural := 8;
   Len_Mid_Symbols        : constant Natural := 8;
   Len_High_Symbols       : constant Natural := 256;
   Min_Match_Length       : constant Natural := 2;
   Default_LC             : constant Natural := Zlib.LZMA_Properties.Default_LC;
   Default_LP             : constant Natural := Zlib.LZMA_Properties.Default_LP;
   Default_PB             : constant Natural := Zlib.LZMA_Properties.Default_PB;
   Default_Props          : constant Byte := Zlib.LZMA_Properties.Default_Props;
   Default_Dict           : constant Interfaces.Unsigned_32 := Zlib.LZMA_Properties.Default_Dict;
   Start_Pos_Model_Index  : constant Natural := 4;
   End_Pos_Model_Index    : constant Natural := 14;
   Num_Full_Distances     : constant Natural := 2 ** (End_Pos_Model_Index / 2);
   Num_Align_Bits         : constant Natural := 4;
   Align_Table_Size       : constant Natural := 2 ** Num_Align_Bits;

   type Prob_Array is array (Natural range <>) of Interfaces.Unsigned_32;

   type Len_Encoder is record
      Choice : Prob_Array (0 .. 1);
      Low    : Prob_Array (0 .. Num_Pos_States_Max * Len_Low_Symbols - 1);
      Mid    : Prob_Array (0 .. Num_Pos_States_Max * Len_Mid_Symbols - 1);
      High   : Prob_Array (0 .. Len_High_Symbols - 1);
   end record;

   type Property_Settings is record
      LC : Natural := Default_LC;
      LP : Natural := Default_LP;
      PB : Natural := Default_PB;
   end record;

   type Property_Decode_Result is record
      Valid    : Boolean := False;
      Settings : Property_Settings;
   end record;

   type Property_Candidate is record
      LC : Natural;
      LP : Natural;
      PB : Natural;
   end record;

   type Property_Candidate_Array is array (Positive range <>) of Property_Candidate;

   Encode_Candidates : constant Property_Candidate_Array :=
     [(LC => 3, LP => 0, PB => 2),
      (LC => 0, LP => 0, PB => 2),
      (LC => 1, LP => 0, PB => 2),
      (LC => 2, LP => 0, PB => 2),
      (LC => 4, LP => 0, PB => 2),
      (LC => 3, LP => 1, PB => 2),
      (LC => 3, LP => 0, PB => 1)];

   function Decode_Properties (Props : Byte) return Property_Decode_Result
     with Post =>
       (if Decode_Properties'Result.Valid then
          Decode_Properties'Result.Settings.LC <= 8
          and then Decode_Properties'Result.Settings.LP <= 4
          and then Decode_Properties'Result.Settings.PB <= 4
          and then Decode_Properties'Result.Settings.LC + Decode_Properties'Result.Settings.LP <= 8);

   type Price_Table is array (0 .. 127) of Natural;

   type Rep_Quad is array (0 .. 3) of Natural;

   function Compute_Prob_Prices return Price_Table
     with Post => (for all Price of Compute_Prob_Prices'Result => Price <= 161);

   function Bit_Price (Prob : Interfaces.Unsigned_32; Bit : Natural) return Natural
     with Pre => Prob < Bit_Model_Total and then Bit <= 1,
          Post => Bit_Price'Result <= 161;

   procedure Init_Probs (Probs : out Prob_Array);

   function Literal_Context
     (LC        : Natural;
      LP        : Natural;
      Position  : Natural;
      Prev_Byte : Byte) return Natural
     with Pre => LC <= 8 and then LP <= 4 and then LC + LP <= 8;

   function Literal_State_After (State : Natural) return Natural
     with Pre  => State < Num_States,
          Post => Literal_State_After'Result < Num_States;

   function Match_State_After (State : Natural) return Natural
     with Pre  => State < Num_States,
          Post => Match_State_After'Result < Num_States;

   function Rep_State_After (State : Natural) return Natural
     with Pre  => State < Num_States,
          Post => Rep_State_After'Result < Num_States;

   function Short_Rep_State_After (State : Natural) return Natural
     with Pre  => State < Num_States,
          Post => Short_Rep_State_After'Result < Num_States;

   function Pos_Slot (Distance_Code : Natural) return Natural
     with Post => Pos_Slot'Result <= 63;

   function Reorder_Reps (R : Rep_Quad; Idx : Natural) return Rep_Quad;

   function Shift_Reps (R : Rep_Quad; Dist : Natural) return Rep_Quad;

   procedure Init_Len (Len : out Len_Encoder);

end Zlib.LZMA_Core;
