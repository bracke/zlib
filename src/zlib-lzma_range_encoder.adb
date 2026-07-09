package body Zlib.LZMA_Range_Encoder is
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;

   procedure Shift_Low (E : in out Encoder) is
      Low_Hi : constant Interfaces.Unsigned_32 :=
        Interfaces.Unsigned_32 (Interfaces.Shift_Right (E.Low, 32));
      Temp   : Interfaces.Unsigned_32;
   begin
      if E.Low < 16#FF00_0000# or else Low_Hi /= 0 then
         Temp := E.Cache;
         loop
            Zlib.Bit_Writer.Write_Byte_Aligned
              (E.Writer, Byte ((Temp + Low_Hi) and 16#FF#));
            E.Cache_Size := E.Cache_Size - 1;
            exit when E.Cache_Size = 0;
            Temp := 16#FF#;
         end loop;
         E.Cache :=
           Interfaces.Unsigned_32 (Interfaces.Shift_Right (E.Low, 24) and 16#FF#);
      end if;

      E.Cache_Size := E.Cache_Size + 1;
      E.Low := Interfaces.Shift_Left (E.Low and 16#00FF_FFFF#, 8);
   end Shift_Low;

   function Finish (E : in out Encoder) return Byte_Array is
   begin
      for I in 1 .. 5 loop
         pragma Unreferenced (I);
         Shift_Low (E);
      end loop;

      return Zlib.Bit_Writer.To_Array (E.Writer);
   end Finish;

   procedure Encode_Bit
     (E    : in out Encoder;
      Prob : in out Interfaces.Unsigned_32;
      Bit  : Natural)
   is
      Bound : constant Interfaces.Unsigned_32 :=
        Interfaces.Shift_Right (E.Range_Code, 11) * Prob;
   begin
      if Bit = 0 then
         E.Range_Code := Bound;
         Prob := Prob + Interfaces.Shift_Right
           (Zlib.LZMA_Core.Bit_Model_Total - Prob, Zlib.LZMA_Core.Move_Bits);
      else
         E.Low := E.Low + Interfaces.Unsigned_64 (Bound);
         E.Range_Code := E.Range_Code - Bound;
         Prob := Prob - Interfaces.Shift_Right (Prob, Zlib.LZMA_Core.Move_Bits);
      end if;

      if E.Range_Code < Zlib.LZMA_Core.Top_Value then
         E.Range_Code := Interfaces.Shift_Left (E.Range_Code, 8);
         Shift_Low (E);
      end if;
   end Encode_Bit;

   procedure Encode_Bit_Tree
     (E      : in out Encoder;
      Probs  : in out Zlib.LZMA_Core.Prob_Array;
      Offset : Natural;
      Bits   : Natural;
      Symbol : Natural)
   is
      Node : Natural := 1;
   begin
      for Bit_Index in reverse 0 .. Bits - 1 loop
         declare
            Bit : constant Natural := (Symbol / (2 ** Bit_Index)) mod 2;
         begin
            Encode_Bit (E, Probs (Offset + Node), Bit);
            Node := Node * 2 + Bit;
         end;
      end loop;
   end Encode_Bit_Tree;

   procedure Encode_Reverse_Bit_Tree
     (E      : in out Encoder;
      Probs  : in out Zlib.LZMA_Core.Prob_Array;
      Offset : Integer;
      Bits   : Natural;
      Symbol : Natural)
   is
      Node : Natural := 1;
   begin
      for Bit_Index in 0 .. Bits - 1 loop
         declare
            Bit : constant Natural := (Symbol / (2 ** Bit_Index)) mod 2;
         begin
            Encode_Bit (E, Probs (Natural (Offset + Node)), Bit);
            Node := Node * 2 + Bit;
         end;
      end loop;
   end Encode_Reverse_Bit_Tree;

   procedure Encode_Direct_Bits
     (E     : in out Encoder;
      Value : Natural;
      Bits  : Natural)
   is
   begin
      if Bits = 0 then
         return;
      end if;

      for Bit_Index in reverse 0 .. Bits - 1 loop
         declare
            Bit : constant Natural := (Value / (2 ** Bit_Index)) mod 2;
         begin
            E.Range_Code := Interfaces.Shift_Right (E.Range_Code, 1);
            if Bit /= 0 then
               E.Low := E.Low + Interfaces.Unsigned_64 (E.Range_Code);
            end if;

            if E.Range_Code < Zlib.LZMA_Core.Top_Value then
               E.Range_Code := Interfaces.Shift_Left (E.Range_Code, 8);
               Shift_Low (E);
            end if;
         end;
      end loop;
   end Encode_Direct_Bits;

   procedure Encode_Distance
     (E           : in out Encoder;
      Pos_Slot    : in out Zlib.LZMA_Core.Prob_Array;
      Pos_Special : in out Zlib.LZMA_Core.Prob_Array;
      Pos_Align   : in out Zlib.LZMA_Core.Prob_Array;
      Len         : Natural;
      Distance    : Natural)
   is
      Distance_Code     : constant Natural := Distance - 1;
      Pos_State_For_Len : constant Natural :=
        Natural'Min
          (Len - Zlib.LZMA_Core.Min_Match_Length,
           Zlib.LZMA_Core.Num_Len_To_Pos_States - 1);
      Slot              : constant Natural := Zlib.LZMA_Core.Pos_Slot (Distance_Code);
   begin
      Encode_Bit_Tree (E, Pos_Slot, Pos_State_For_Len * 64, 6, Slot);

      if Slot >= Zlib.LZMA_Core.Start_Pos_Model_Index then
         declare
            Footer_Bits : constant Natural := Slot / 2 - 1;
            Base        : constant Natural :=
              (2 + Slot mod 2) * (2 ** Footer_Bits);
            Reduced     : constant Natural := Distance_Code - Base;
            Offset      : constant Integer := Integer (Base) - Integer (Slot) - 1;
         begin
            if Slot < Zlib.LZMA_Core.End_Pos_Model_Index then
               Encode_Reverse_Bit_Tree
                 (E, Pos_Special, Offset, Footer_Bits, Reduced);
            else
               Encode_Direct_Bits
                 (E, Reduced / Zlib.LZMA_Core.Align_Table_Size,
                  Footer_Bits - Zlib.LZMA_Core.Num_Align_Bits);
               Encode_Reverse_Bit_Tree
                 (E, Pos_Align, 0, Zlib.LZMA_Core.Num_Align_Bits,
                  Reduced mod Zlib.LZMA_Core.Align_Table_Size);
            end if;
         end;
      end if;
   end Encode_Distance;

   procedure Encode_Len
     (E         : in out Encoder;
      Len       : in out Zlib.LZMA_Core.Len_Encoder;
      Pos_State : Natural;
      Symbol    : Natural)
   is
   begin
      if Symbol < Zlib.LZMA_Core.Len_Low_Symbols then
         Encode_Bit (E, Len.Choice (0), 0);
         Encode_Bit_Tree
           (E, Len.Low, Pos_State * Zlib.LZMA_Core.Len_Low_Symbols, 3, Symbol);
      elsif Symbol < Zlib.LZMA_Core.Len_Low_Symbols + Zlib.LZMA_Core.Len_Mid_Symbols then
         Encode_Bit (E, Len.Choice (0), 1);
         Encode_Bit (E, Len.Choice (1), 0);
         Encode_Bit_Tree
           (E, Len.Mid, Pos_State * Zlib.LZMA_Core.Len_Mid_Symbols, 3,
            Symbol - Zlib.LZMA_Core.Len_Low_Symbols);
      else
         Encode_Bit (E, Len.Choice (0), 1);
         Encode_Bit (E, Len.Choice (1), 1);
         Encode_Bit_Tree
           (E, Len.High, 0, 8,
            Symbol - Zlib.LZMA_Core.Len_Low_Symbols - Zlib.LZMA_Core.Len_Mid_Symbols);
      end if;
   end Encode_Len;

   function Tree_Price
     (Probs  : Zlib.LZMA_Core.Prob_Array;
      Offset : Natural;
      Bits   : Natural;
      Symbol : Natural) return Natural
   is
      Node : Natural := 1;
      Pr   : Natural := 0;
   begin
      for Bit_Index in reverse 0 .. Bits - 1 loop
         declare
            Bit : constant Natural := (Symbol / (2 ** Bit_Index)) mod 2;
         begin
            Pr := Pr + Zlib.LZMA_Core.Bit_Price (Probs (Offset + Node), Bit);
            Node := Node * 2 + Bit;
         end;
      end loop;
      return Pr;
   end Tree_Price;

   function Reverse_Tree_Price
     (Probs  : Zlib.LZMA_Core.Prob_Array;
      Offset : Integer;
      Bits   : Natural;
      Symbol : Natural) return Natural
   is
      Node : Natural := 1;
      Pr   : Natural := 0;
   begin
      for Bit_Index in 0 .. Bits - 1 loop
         declare
            Bit : constant Natural := (Symbol / (2 ** Bit_Index)) mod 2;
         begin
            Pr := Pr + Zlib.LZMA_Core.Bit_Price (Probs (Natural (Offset + Node)), Bit);
            Node := Node * 2 + Bit;
         end;
      end loop;
      return Pr;
   end Reverse_Tree_Price;

   function Len_Price
     (Len       : Zlib.LZMA_Core.Len_Encoder;
      Pos_State : Natural;
      Symbol    : Natural) return Natural
   is
   begin
      if Symbol < Zlib.LZMA_Core.Len_Low_Symbols then
         return Zlib.LZMA_Core.Bit_Price (Len.Choice (0), 0)
           + Tree_Price
               (Len.Low, Pos_State * Zlib.LZMA_Core.Len_Low_Symbols, 3, Symbol);
      elsif Symbol < Zlib.LZMA_Core.Len_Low_Symbols + Zlib.LZMA_Core.Len_Mid_Symbols then
         return Zlib.LZMA_Core.Bit_Price (Len.Choice (0), 1)
           + Zlib.LZMA_Core.Bit_Price (Len.Choice (1), 0)
           + Tree_Price
               (Len.Mid, Pos_State * Zlib.LZMA_Core.Len_Mid_Symbols, 3,
                Symbol - Zlib.LZMA_Core.Len_Low_Symbols);
      else
         return Zlib.LZMA_Core.Bit_Price (Len.Choice (0), 1)
           + Zlib.LZMA_Core.Bit_Price (Len.Choice (1), 1)
           + Tree_Price
               (Len.High, 0, 8,
                Symbol - Zlib.LZMA_Core.Len_Low_Symbols - Zlib.LZMA_Core.Len_Mid_Symbols);
      end if;
   end Len_Price;

   function Distance_Price
     (Pos_Slot    : Zlib.LZMA_Core.Prob_Array;
      Pos_Special : Zlib.LZMA_Core.Prob_Array;
      Pos_Align   : Zlib.LZMA_Core.Prob_Array;
      Len         : Natural;
      Distance    : Natural) return Natural
   is
      Distance_Code     : constant Natural := Distance - 1;
      Pos_State_For_Len : constant Natural :=
        Natural'Min
          (Len - Zlib.LZMA_Core.Min_Match_Length,
           Zlib.LZMA_Core.Num_Len_To_Pos_States - 1);
      Slot              : constant Natural := Zlib.LZMA_Core.Pos_Slot (Distance_Code);
      Pr                : Natural := Tree_Price (Pos_Slot, Pos_State_For_Len * 64, 6, Slot);
   begin
      if Slot >= Zlib.LZMA_Core.Start_Pos_Model_Index then
         declare
            Footer_Bits : constant Natural := Slot / 2 - 1;
            Base        : constant Natural :=
              (2 + Slot mod 2) * (2 ** Footer_Bits);
            Reduced     : constant Natural := Distance_Code - Base;
         begin
            if Slot < Zlib.LZMA_Core.End_Pos_Model_Index then
               Pr := Pr
                 + Reverse_Tree_Price
                     (Pos_Special, Integer (Base) - Integer (Slot) - 1,
                      Footer_Bits, Reduced);
            else
               Pr := Pr + (Footer_Bits - Zlib.LZMA_Core.Num_Align_Bits) * 16
                 + Reverse_Tree_Price
                     (Pos_Align, 0, Zlib.LZMA_Core.Num_Align_Bits,
                      Reduced mod Zlib.LZMA_Core.Align_Table_Size);
            end if;
         end;
      end if;
      return Pr;
   end Distance_Price;

end Zlib.LZMA_Range_Encoder;
