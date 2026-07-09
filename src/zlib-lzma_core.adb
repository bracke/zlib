package body Zlib.LZMA_Core
  with SPARK_Mode => On
is

   procedure Init_Probs (Probs : out Prob_Array)
     with SPARK_Mode => Off
   is
   begin
      for I in Probs'Range loop
         Probs (I) := Bit_Model_Total / 2;
      end loop;
   end Init_Probs;

   function Decode_Properties (Props : Byte) return Property_Decode_Result
   is
      Props_Value : constant Natural := Natural (Props);
      LCLP        : constant Natural := Props_Value mod 9;
      Rest        : constant Natural := Props_Value / 9;
      LC          : constant Natural := LCLP;
      LP          : constant Natural := Rest mod 5;
      PB          : constant Natural := Rest / 5;
   begin
      if PB > 4 or else LC + LP > 8 then
         return (Valid => False,
                 Settings => (LC => Default_LC, LP => Default_LP, PB => Default_PB));
      end if;

      return (Valid => True, Settings => (LC => LC, LP => LP, PB => PB));
   end Decode_Properties;

   function Compute_Prob_Prices return Price_Table
     with SPARK_Mode => Off
   is
      T : Price_Table;
   begin
      for I in 0 .. 127 loop
         declare
            W         : Interfaces.Unsigned_32 := Interfaces.Unsigned_32 (I) * 16;
            Bit_Count : Natural := 0;
         begin
            for J in 1 .. 4 loop
               pragma Unreferenced (J);
               W := W * W;
               Bit_Count := Bit_Count * 2;
               while W >= 2 ** 16 loop
                  W := Interfaces.Shift_Right (W, 1);
                  Bit_Count := Bit_Count + 1;
               end loop;
            end loop;
            T (I) := 176 - 15 - Bit_Count;
         end;
      end loop;
      return T;
   end Compute_Prob_Prices;

   Prob_Prices : constant Price_Table := Compute_Prob_Prices;

   function Bit_Price (Prob : Interfaces.Unsigned_32; Bit : Natural) return Natural
   is
     (Prob_Prices
        (Natural
           (Interfaces.Shift_Right
              ((if Bit = 0 then Prob else Prob xor 2047), 4))));

   function Literal_Context
     (LC        : Natural;
      LP        : Natural;
      Position  : Natural;
      Prev_Byte : Byte) return Natural
     with SPARK_Mode => Off
   is
      Pos_Part : constant Natural :=
        (if LP = 0 then 0 else (Position mod (2 ** LP)) * (2 ** LC));
      Prev_Part : constant Natural :=
        (if LC = 0 then 0 else Natural (Prev_Byte) / (2 ** (8 - LC)));
   begin
      return Pos_Part + Prev_Part;
   end Literal_Context;

   function Literal_State_After (State : Natural) return Natural is
   begin
      if State < 4 then
         return 0;
      elsif State < 10 then
         return State - 3;
      else
         return State - 6;
      end if;
   end Literal_State_After;

   function Match_State_After (State : Natural) return Natural is
   begin
      if State < 7 then
         return 7;
      else
         return 10;
      end if;
   end Match_State_After;

   function Rep_State_After (State : Natural) return Natural is
   begin
      if State < 7 then
         return 8;
      else
         return 11;
      end if;
   end Rep_State_After;

   function Short_Rep_State_After (State : Natural) return Natural is
   begin
      if State < 7 then
         return 9;
      else
         return 11;
      end if;
   end Short_Rep_State_After;

   function Pos_Slot (Distance_Code : Natural) return Natural is
   begin
      case Distance_Code is
         when 0 .. 3 => return Distance_Code;
         when 4 .. 5 => return 4;
         when 6 .. 7 => return 5;
         when 8 .. 11 => return 6;
         when 12 .. 15 => return 7;
         when 16 .. 23 => return 8;
         when 24 .. 31 => return 9;
         when 32 .. 47 => return 10;
         when 48 .. 63 => return 11;
         when 64 .. 95 => return 12;
         when 96 .. 127 => return 13;
         when 128 .. 191 => return 14;
         when 192 .. 255 => return 15;
         when 256 .. 383 => return 16;
         when 384 .. 511 => return 17;
         when 512 .. 767 => return 18;
         when 768 .. 1023 => return 19;
         when 1024 .. 1535 => return 20;
         when 1536 .. 2047 => return 21;
         when 2048 .. 3071 => return 22;
         when 3072 .. 4095 => return 23;
         when 4096 .. 6143 => return 24;
         when 6144 .. 8191 => return 25;
         when 8192 .. 12287 => return 26;
         when 12288 .. 16383 => return 27;
         when 16384 .. 24575 => return 28;
         when 24576 .. 32767 => return 29;
         when 32768 .. 49151 => return 30;
         when 49152 .. 65535 => return 31;
         when 65536 .. 98303 => return 32;
         when 98304 .. 131071 => return 33;
         when 131072 .. 196607 => return 34;
         when 196608 .. 262143 => return 35;
         when 262144 .. 393215 => return 36;
         when 393216 .. 524287 => return 37;
         when 524288 .. 786431 => return 38;
         when 786432 .. 1048575 => return 39;
         when 1048576 .. 1572863 => return 40;
         when 1572864 .. 2097151 => return 41;
         when 2097152 .. 3145727 => return 42;
         when 3145728 .. 4194303 => return 43;
         when 4194304 .. 6291455 => return 44;
         when 6291456 .. 8388607 => return 45;
         when 8388608 .. 12582911 => return 46;
         when 12582912 .. 16777215 => return 47;
         when 16777216 .. 25165823 => return 48;
         when 25165824 .. 33554431 => return 49;
         when 33554432 .. 50331647 => return 50;
         when 50331648 .. 67108863 => return 51;
         when 67108864 .. 100663295 => return 52;
         when 100663296 .. 134217727 => return 53;
         when 134217728 .. 201326591 => return 54;
         when 201326592 .. 268435455 => return 55;
         when 268435456 .. 402653183 => return 56;
         when 402653184 .. 536870911 => return 57;
         when 536870912 .. 805306367 => return 58;
         when 805306368 .. 1073741823 => return 59;
         when 1073741824 .. 1610612735 => return 60;
         when 1610612736 .. Natural'Last => return 61;
      end case;
   end Pos_Slot;

   function Reorder_Reps (R : Rep_Quad; Idx : Natural) return Rep_Quad
   is
      N : Rep_Quad := R;
   begin
      case Idx is
         when 0 =>
            null;
         when 1 =>
            N (0) := R (1);
            N (1) := R (0);
         when 2 =>
            N (0) := R (2);
            N (1) := R (0);
            N (2) := R (1);
         when others =>
            N (0) := R (3);
            N (1) := R (0);
            N (2) := R (1);
            N (3) := R (2);
      end case;
      return N;
   end Reorder_Reps;

   function Shift_Reps (R : Rep_Quad; Dist : Natural) return Rep_Quad is
     ([0 => Dist, 1 => R (0), 2 => R (1), 3 => R (2)]);

   procedure Init_Len (Len : out Len_Encoder)
     with SPARK_Mode => Off
   is
   begin
      Init_Probs (Len.Choice);
      Init_Probs (Len.Low);
      Init_Probs (Len.Mid);
      Init_Probs (Len.High);
   end Init_Len;

end Zlib.LZMA_Core;
