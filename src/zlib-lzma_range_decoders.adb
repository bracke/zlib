package body Zlib.LZMA_Range_Decoders is
   use type Interfaces.Unsigned_32;

   function Read_Stream_Byte
     (D      : in out Decoder;
      Stream : Byte_Array;
      Status : in out Status_Code) return Interfaces.Unsigned_32
   is
   begin
      if D.Pos >= Stream'Length then
         Status := Unexpected_End_Of_Input;
         return 0;
      end if;

      D.Pos := D.Pos + 1;
      return Interfaces.Unsigned_32 (Stream (Stream'First + D.Pos - 1));
   end Read_Stream_Byte;

   procedure Init
     (D      : in out Decoder;
      Stream : Byte_Array;
      Status : in out Status_Code)
   is
   begin
      D.Code := 0;
      D.Range_Code := Interfaces.Unsigned_32'Last;
      D.Pos := 0;

      for I in 1 .. 5 loop
         declare
            Next_Byte : constant Interfaces.Unsigned_32 :=
              Read_Stream_Byte (D, Stream, Status);
         begin
            D.Code := Interfaces.Shift_Left (D.Code, 8) or Next_Byte;
         end;
         exit when Status /= Ok;
      end loop;
   end Init;

   function Decode_Bit
     (D      : in out Decoder;
      Stream : Byte_Array;
      Prob   : in out Interfaces.Unsigned_32;
      Status : in out Status_Code) return Natural
   is
      Bound : constant Interfaces.Unsigned_32 :=
        Interfaces.Shift_Right (D.Range_Code, 11) * Prob;
      Bit   : Natural;
   begin
      if Status /= Ok then
         return 0;
      end if;

      if D.Code < Bound then
         D.Range_Code := Bound;
         Prob := Prob + Interfaces.Shift_Right
           (Zlib.LZMA_Core.Bit_Model_Total - Prob, Zlib.LZMA_Core.Move_Bits);
         Bit := 0;
      else
         D.Code := D.Code - Bound;
         D.Range_Code := D.Range_Code - Bound;
         Prob := Prob - Interfaces.Shift_Right (Prob, Zlib.LZMA_Core.Move_Bits);
         Bit := 1;
      end if;

      if D.Range_Code < Zlib.LZMA_Core.Top_Value then
         D.Range_Code := Interfaces.Shift_Left (D.Range_Code, 8);
         declare
            Next_Byte : constant Interfaces.Unsigned_32 :=
              Read_Stream_Byte (D, Stream, Status);
         begin
            D.Code := Interfaces.Shift_Left (D.Code, 8) or Next_Byte;
         end;
      end if;

      return Bit;
   end Decode_Bit;

   function Decode_Bit_Tree
     (D      : in out Decoder;
      Stream : Byte_Array;
      Probs  : in out Zlib.LZMA_Core.Prob_Array;
      Offset : Natural;
      Bits   : Natural;
      Status : in out Status_Code) return Natural
   is
      Node : Natural := 1;
   begin
      for I in 1 .. Bits loop
         Node :=
           Node * 2
           + Decode_Bit (D, Stream, Probs (Offset + Node), Status);
         exit when Status /= Ok;
      end loop;

      return Node - 2 ** Bits;
   end Decode_Bit_Tree;

   function Decode_Reverse_Bit_Tree
     (D      : in out Decoder;
      Stream : Byte_Array;
      Probs  : in out Zlib.LZMA_Core.Prob_Array;
      Offset : Integer;
      Bits   : Natural;
      Status : in out Status_Code) return Natural
   is
      Node   : Natural := 1;
      Symbol : Natural := 0;
   begin
      for Bit_Index in 0 .. Bits - 1 loop
         declare
            Bit : constant Natural :=
              Decode_Bit
                (D, Stream, Probs (Natural (Offset + Node)), Status);
         begin
            Symbol := Symbol + Bit * (2 ** Bit_Index);
            Node := Node * 2 + Bit;
         end;
         exit when Status /= Ok;
      end loop;

      return Symbol;
   end Decode_Reverse_Bit_Tree;

   function Decode_Direct_Bits
     (D      : in out Decoder;
      Stream : Byte_Array;
      Bits   : Natural;
      Status : in out Status_Code) return Natural
   is
      Result : Natural := 0;
   begin
      if Bits = 0 then
         return 0;
      end if;

      for I in 1 .. Bits loop
         D.Range_Code := Interfaces.Shift_Right (D.Range_Code, 1);

         declare
            Bit : Natural := 0;
         begin
            if D.Code >= D.Range_Code then
               D.Code := D.Code - D.Range_Code;
               Bit := 1;
            end if;

            if D.Range_Code < Zlib.LZMA_Core.Top_Value then
               D.Range_Code := Interfaces.Shift_Left (D.Range_Code, 8);
               declare
                  Next_Byte : constant Interfaces.Unsigned_32 :=
                    Read_Stream_Byte (D, Stream, Status);
               begin
                  D.Code := Interfaces.Shift_Left (D.Code, 8) or Next_Byte;
               end;
            end if;

            Result := Result * 2 + Bit;
         end;

         exit when Status /= Ok;
      end loop;

      return Result;
   end Decode_Direct_Bits;

   function Decode_Distance
     (D           : in out Decoder;
      Stream      : Byte_Array;
      Pos_Slot    : in out Zlib.LZMA_Core.Prob_Array;
      Pos_Special : in out Zlib.LZMA_Core.Prob_Array;
      Pos_Align   : in out Zlib.LZMA_Core.Prob_Array;
      Len         : Natural;
      Status      : in out Status_Code) return Natural
   is
      Pos_State_For_Len : constant Natural :=
        Natural'Min
          (Len - Zlib.LZMA_Core.Min_Match_Length,
           Zlib.LZMA_Core.Num_Len_To_Pos_States - 1);
      Slot              : constant Natural :=
        Decode_Bit_Tree (D, Stream, Pos_Slot, Pos_State_For_Len * 64, 6, Status);
   begin
      if Status /= Ok then
         return 0;
      end if;

      if Slot < Zlib.LZMA_Core.Start_Pos_Model_Index then
         return Slot + 1;
      elsif Slot < Zlib.LZMA_Core.End_Pos_Model_Index then
         declare
            Footer_Bits : constant Natural := Slot / 2 - 1;
            Base        : constant Natural :=
              (2 + Slot mod 2) * (2 ** Footer_Bits);
            Offset      : constant Integer := Integer (Base) - Integer (Slot) - 1;
            Reduced     : constant Natural :=
              Decode_Reverse_Bit_Tree
                (D, Stream, Pos_Special, Offset, Footer_Bits, Status);
         begin
            return Base + Reduced + 1;
         end;
      else
         declare
            Footer_Bits : constant Natural := Slot / 2 - 1;
            Base        : constant Natural :=
              (2 + Slot mod 2) * (2 ** Footer_Bits);
            Direct      : constant Natural :=
              Decode_Direct_Bits
                (D, Stream, Footer_Bits - Zlib.LZMA_Core.Num_Align_Bits, Status);
            Align       : constant Natural :=
              Decode_Reverse_Bit_Tree
                (D, Stream, Pos_Align, 0, Zlib.LZMA_Core.Num_Align_Bits, Status);
         begin
            return Base + Direct * Zlib.LZMA_Core.Align_Table_Size + Align + 1;
         end;
      end if;
   end Decode_Distance;

   function Decode_Len
     (D         : in out Decoder;
      Stream    : Byte_Array;
      Len       : in out Zlib.LZMA_Core.Len_Encoder;
      Pos_State : Natural;
      Status    : in out Status_Code) return Natural
   is
   begin
      if Decode_Bit (D, Stream, Len.Choice (0), Status) = 0 then
         return
           Decode_Bit_Tree
             (D, Stream, Len.Low, Pos_State * Zlib.LZMA_Core.Len_Low_Symbols, 3,
              Status);
      end if;

      if Decode_Bit (D, Stream, Len.Choice (1), Status) = 0 then
         return
           Zlib.LZMA_Core.Len_Low_Symbols
           + Decode_Bit_Tree
             (D, Stream, Len.Mid, Pos_State * Zlib.LZMA_Core.Len_Mid_Symbols, 3,
              Status);
      end if;

      return
        Zlib.LZMA_Core.Len_Low_Symbols + Zlib.LZMA_Core.Len_Mid_Symbols
        + Decode_Bit_Tree (D, Stream, Len.High, 0, 8, Status);
   end Decode_Len;

end Zlib.LZMA_Range_Decoders;
