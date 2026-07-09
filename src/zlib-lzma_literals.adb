package body Zlib.LZMA_Literals is

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
      Prev         : Byte)
   is
      B       : constant Byte := Plain (Index);
      Context : constant Natural :=
        Zlib.LZMA_Core.Literal_Context
          (Lit_Ctx_Bits, Lit_Pos_Bits, Position, Prev);
      Symbol  : Natural := 1;
   begin
      if State >= 7 and then Rep0 > 0 and then Rep0 <= Position then
         declare
            Match_Byte : Natural := Natural (Plain (Index - Rep0));
            Matched    : Boolean := True;
         begin
            for Bit_Index in reverse 0 .. 7 loop
               declare
                  Bit : constant Natural :=
                    (Natural (B) / (2 ** Bit_Index)) mod 2;
               begin
                  if Matched then
                     Match_Byte := Match_Byte * 2;
                     declare
                        Match_Bit_Literal : constant Natural :=
                          ((Match_Byte / 16#100#) mod 2) * 16#100#;
                     begin
                        Zlib.LZMA_Range_Encoder.Encode_Bit
                          (E,
                           Literals
                             (Context * Zlib.LZMA_Core.Literal_Probs
                              + 16#100# + Match_Bit_Literal + Symbol),
                           Bit);
                        Symbol := Symbol * 2 + Bit;
                        if Match_Bit_Literal /= Bit * 16#100# then
                           Matched := False;
                        end if;
                     end;
                  else
                     Zlib.LZMA_Range_Encoder.Encode_Bit
                       (E,
                        Literals
                          (Context * Zlib.LZMA_Core.Literal_Probs + Symbol),
                        Bit);
                     Symbol := Symbol * 2 + Bit;
                  end if;
               end;
            end loop;
         end;
      else
         for Bit_Index in reverse 0 .. 7 loop
            declare
               Bit : constant Natural :=
                 (Natural (B) / (2 ** Bit_Index)) mod 2;
            begin
               Zlib.LZMA_Range_Encoder.Encode_Bit
                 (E,
                  Literals (Context * Zlib.LZMA_Core.Literal_Probs + Symbol),
                  Bit);
               Symbol := Symbol * 2 + Bit;
            end;
         end loop;
      end if;
   end Encode;

   function Price
     (Literals     : Zlib.LZMA_Core.Prob_Array;
      Plain        : Byte_Array;
      Index        : Natural;
      State        : Natural;
      Rep0         : Natural;
      Position     : Natural;
      Lit_Ctx_Bits : Natural;
      Lit_Pos_Bits : Natural) return Natural
   is
      B       : constant Natural := Natural (Plain (Index));
      Prev_B  : constant Byte :=
        (if Index > Plain'First then Plain (Index - 1) else 0);
      Context : constant Natural :=
        Zlib.LZMA_Core.Literal_Context
          (Lit_Ctx_Bits, Lit_Pos_Bits, Position, Prev_B);
      Symbol  : Natural := 1;
      Result  : Natural := 0;
   begin
      if State >= 7 and then Rep0 > 0 and then Rep0 <= Position then
         declare
            Match_Byte : Natural := Natural (Plain (Index - Rep0));
            Matched    : Boolean := True;
         begin
            for Bit_Index in reverse 0 .. 7 loop
               declare
                  Bit : constant Natural := (B / (2 ** Bit_Index)) mod 2;
               begin
                  if Matched then
                     Match_Byte := Match_Byte * 2;
                     declare
                        Match_Bit_Literal : constant Natural :=
                          ((Match_Byte / 16#100#) mod 2) * 16#100#;
                     begin
                        Result :=
                          Result
                          + Zlib.LZMA_Core.Bit_Price
                              (Literals
                                 (Context * Zlib.LZMA_Core.Literal_Probs
                                  + 16#100# + Match_Bit_Literal + Symbol),
                               Bit);
                        Symbol := Symbol * 2 + Bit;
                        if Match_Bit_Literal /= Bit * 16#100# then
                           Matched := False;
                        end if;
                     end;
                  else
                     Result :=
                       Result
                       + Zlib.LZMA_Core.Bit_Price
                           (Literals
                              (Context * Zlib.LZMA_Core.Literal_Probs + Symbol),
                            Bit);
                     Symbol := Symbol * 2 + Bit;
                  end if;
               end;
            end loop;
         end;
      else
         for Bit_Index in reverse 0 .. 7 loop
            declare
               Bit : constant Natural := (B / (2 ** Bit_Index)) mod 2;
            begin
               Result :=
                 Result
                 + Zlib.LZMA_Core.Bit_Price
                     (Literals
                        (Context * Zlib.LZMA_Core.Literal_Probs + Symbol),
                      Bit);
               Symbol := Symbol * 2 + Bit;
            end;
         end loop;
      end if;

      return Result;
   end Price;

end Zlib.LZMA_Literals;
