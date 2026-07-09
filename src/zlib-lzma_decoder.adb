with Zlib.LZMA_Core;
with Zlib.LZMA_Range_Decoders;

package body Zlib.LZMA_Decoder is

   function Decode_Payload
     (Payload              : Byte_Array;
      Plain_Len            : Natural;
      Require_Full_Stream  : Boolean;
      Initial_Rep_Distance : Natural;
      Use_Matched_Literals : Boolean;
      Status               : out Status_Code) return Byte_Array
   is
      Empty : constant Byte_Array (1 .. 0) := [others => 0];
   begin
      Status := Unsupported_Method;

      if Payload'Length < 9 then
         Status := Unexpected_End_Of_Input;
         return Empty;
      end if;

      declare
         Props_Size  : constant Natural :=
           Natural (Payload (Payload'First + 2))
           + 256 * Natural (Payload (Payload'First + 3));
         Props_First : constant Natural := Payload'First + 4;
         Stream_First : constant Natural := Props_First + Props_Size;
      begin
         if Props_Size /= 5
           or else Stream_First > Payload'Last + 1
         then
            Status := Unsupported_Method;
            return Empty;
         end if;

         declare
            Props0 : constant Byte := Payload (Props_First);
            Props  : constant Zlib.LZMA_Core.Property_Decode_Result :=
              Zlib.LZMA_Core.Decode_Properties (Props0);
         begin
            if not Props.Valid then
               Status := Unsupported_Method;
               return Empty;
            end if;

            declare
               Stream : constant Byte_Array :=
                 (if Stream_First > Payload'Last then Empty
                  else Payload (Stream_First .. Payload'Last));
               Pos_States   : constant Natural := 2 ** Props.Settings.PB;
               Literal_Ctxs : constant Natural :=
                 2 ** (Props.Settings.LC + Props.Settings.LP);
               Is_Match     : Zlib.LZMA_Core.Prob_Array
                 (0 .. Zlib.LZMA_Core.Num_States
                       * Zlib.LZMA_Core.Num_Pos_States_Max - 1);
               Is_Rep       : Zlib.LZMA_Core.Prob_Array
                 (0 .. Zlib.LZMA_Core.Num_States - 1);
               Is_Rep_G0    : Zlib.LZMA_Core.Prob_Array
                 (0 .. Zlib.LZMA_Core.Num_States - 1);
               Is_Rep_G1    : Zlib.LZMA_Core.Prob_Array
                 (0 .. Zlib.LZMA_Core.Num_States - 1);
               Is_Rep_G2    : Zlib.LZMA_Core.Prob_Array
                 (0 .. Zlib.LZMA_Core.Num_States - 1);
               Is_Rep0_Long : Zlib.LZMA_Core.Prob_Array
                 (0 .. Zlib.LZMA_Core.Num_States
                       * Zlib.LZMA_Core.Num_Pos_States_Max - 1);
               Match_Len    : Zlib.LZMA_Core.Len_Encoder;
               Rep_Len      : Zlib.LZMA_Core.Len_Encoder;
               Pos_Slot     : Zlib.LZMA_Core.Prob_Array
                 (0 .. Zlib.LZMA_Core.Num_Len_To_Pos_States * 64 - 1);
               Pos_Special  : Zlib.LZMA_Core.Prob_Array
                 (0 .. Zlib.LZMA_Core.Num_Full_Distances
                       - Zlib.LZMA_Core.End_Pos_Model_Index - 1);
               Pos_Align    : Zlib.LZMA_Core.Prob_Array
                 (0 .. Zlib.LZMA_Core.Align_Table_Size - 1);
               Literals     : Zlib.LZMA_Core.Prob_Array
                 (0 .. Literal_Ctxs * Zlib.LZMA_Core.Literal_Probs - 1);
               D            : Zlib.LZMA_Range_Decoders.Decoder;
               State        : Natural := 0;
               Prev         : Byte := 0;
               Rep0         : Natural := Initial_Rep_Distance;
               Rep1         : Natural := Initial_Rep_Distance;
               Rep2         : Natural := Initial_Rep_Distance;
               Rep3         : Natural := Initial_Rep_Distance;
               Plain        : Byte_Array (1 .. Natural'Max (1, Plain_Len)) :=
                 [others => 0];
               Out_Pos      : Natural := 0;
               Local_Status : Status_Code := Ok;
            begin
               if Stream'Length < 5 then
                  Status := Unexpected_End_Of_Input;
                  return Empty;
               end if;

               Zlib.LZMA_Core.Init_Probs (Is_Match);
               Zlib.LZMA_Core.Init_Probs (Is_Rep);
               Zlib.LZMA_Core.Init_Probs (Is_Rep_G0);
               Zlib.LZMA_Core.Init_Probs (Is_Rep_G1);
               Zlib.LZMA_Core.Init_Probs (Is_Rep_G2);
               Zlib.LZMA_Core.Init_Probs (Is_Rep0_Long);
               Zlib.LZMA_Core.Init_Len (Match_Len);
               Zlib.LZMA_Core.Init_Len (Rep_Len);
               Zlib.LZMA_Core.Init_Probs (Pos_Slot);
               Zlib.LZMA_Core.Init_Probs (Pos_Special);
               Zlib.LZMA_Core.Init_Probs (Pos_Align);
               Zlib.LZMA_Core.Init_Probs (Literals);
               Zlib.LZMA_Range_Decoders.Init (D, Stream, Local_Status);

               while Local_Status = Ok and then Out_Pos < Plain_Len loop
                  declare
                     Pos_State : constant Natural := Out_Pos mod Pos_States;
                     Match_Bit : constant Natural :=
                       Zlib.LZMA_Range_Decoders.Decode_Bit
                         (D, Stream,
                          Is_Match
                            (State * Zlib.LZMA_Core.Num_Pos_States_Max
                             + Pos_State),
                          Local_Status);
                  begin
                     if Local_Status /= Ok then
                        exit;
                     end if;

                     if Match_Bit = 0 then
                        declare
                           Context : constant Natural :=
                             Zlib.LZMA_Core.Literal_Context
                               (Props.Settings.LC, Props.Settings.LP,
                                Out_Pos, Prev);
                           Symbol  : Natural := 1;
                        begin
                           if Use_Matched_Literals
                             and then State >= 7
                             and then Rep0 > 0
                             and then Rep0 <= Out_Pos
                           then
                              declare
                                 Match_Byte : Natural :=
                                   Natural (Plain (Out_Pos - Rep0 + 1));
                              begin
                                 while Symbol < 16#100# loop
                                    Match_Byte := Match_Byte * 2;
                                    declare
                                       Match_Bit_Literal : constant Natural :=
                                         ((Match_Byte / 16#100#) mod 2)
                                         * 16#100#;
                                       Decoded_Bit : constant Natural :=
                                         Zlib.LZMA_Range_Decoders.Decode_Bit
                                           (D, Stream,
                                            Literals
                                              (Context
                                               * Zlib.LZMA_Core.Literal_Probs
                                               + 16#100# + Match_Bit_Literal
                                               + Symbol),
                                            Local_Status);
                                    begin
                                       Symbol := Symbol * 2 + Decoded_Bit;
                                       exit when Local_Status /= Ok
                                         or else Match_Bit_Literal /=
                                           Decoded_Bit * 16#100#;
                                    end;
                                 end loop;
                              end;
                           end if;

                           while Symbol < 16#100# loop
                              Symbol :=
                                Symbol * 2
                                + Zlib.LZMA_Range_Decoders.Decode_Bit
                                  (D, Stream,
                                   Literals
                                     (Context * Zlib.LZMA_Core.Literal_Probs
                                      + Symbol),
                                   Local_Status);
                              exit when Local_Status /= Ok;
                           end loop;

                           if Local_Status /= Ok then
                              exit;
                           end if;

                           Out_Pos := Out_Pos + 1;
                           Plain (Out_Pos) := Byte (Symbol - 16#100#);
                           Prev := Plain (Out_Pos);
                           State := Zlib.LZMA_Core.Literal_State_After (State);
                        end;
                     else
                        if Zlib.LZMA_Range_Decoders.Decode_Bit
                          (D, Stream, Is_Rep (State), Local_Status) /= 0
                        then
                           declare
                              Distance : Natural := Rep0;
                              Len      : Natural :=
                                Zlib.LZMA_Core.Min_Match_Length;
                           begin
                              if Zlib.LZMA_Range_Decoders.Decode_Bit
                                (D, Stream, Is_Rep_G0 (State),
                                 Local_Status) = 0
                              then
                                 if Zlib.LZMA_Range_Decoders.Decode_Bit
                                   (D, Stream,
                                    Is_Rep0_Long
                                      (State
                                       * Zlib.LZMA_Core.Num_Pos_States_Max
                                       + Pos_State),
                                    Local_Status) = 0
                                 then
                                    Len := 1;
                                    State :=
                                      Zlib.LZMA_Core.Short_Rep_State_After
                                        (State);
                                 else
                                    Len :=
                                      Zlib.LZMA_Range_Decoders.Decode_Len
                                        (D, Stream, Rep_Len, Pos_State,
                                         Local_Status)
                                      + Zlib.LZMA_Core.Min_Match_Length;
                                    State :=
                                      Zlib.LZMA_Core.Rep_State_After (State);
                                 end if;
                              else
                                 if Zlib.LZMA_Range_Decoders.Decode_Bit
                                   (D, Stream, Is_Rep_G1 (State),
                                    Local_Status) = 0
                                 then
                                    Distance := Rep1;
                                 else
                                    if Zlib.LZMA_Range_Decoders.Decode_Bit
                                      (D, Stream, Is_Rep_G2 (State),
                                       Local_Status) = 0
                                    then
                                       Distance := Rep2;
                                    else
                                       Distance := Rep3;
                                       Rep3 := Rep2;
                                    end if;
                                    Rep2 := Rep1;
                                 end if;
                                 Rep1 := Rep0;
                                 Rep0 := Distance;
                                 Len :=
                                   Zlib.LZMA_Range_Decoders.Decode_Len
                                     (D, Stream, Rep_Len, Pos_State,
                                      Local_Status)
                                   + Zlib.LZMA_Core.Min_Match_Length;
                                 State := Zlib.LZMA_Core.Rep_State_After
                                   (State);
                              end if;

                              if Local_Status /= Ok then
                                 exit;
                              end if;

                              if Distance = 0
                                or else Distance > Out_Pos
                                or else Len > Plain_Len - Out_Pos
                              then
                                 Status := Unsupported_Method;
                                 return Empty;
                              end if;

                              for I in 1 .. Len loop
                                 Out_Pos := Out_Pos + 1;
                                 Plain (Out_Pos) := Plain (Out_Pos - Distance);
                              end loop;

                              Prev := Plain (Out_Pos);
                           end;
                        else
                           declare
                              Len_Symbol : constant Natural :=
                                Zlib.LZMA_Range_Decoders.Decode_Len
                                  (D, Stream, Match_Len, Pos_State,
                                   Local_Status);
                              Len        : constant Natural :=
                                Len_Symbol
                                + Zlib.LZMA_Core.Min_Match_Length;
                              Distance   : constant Natural :=
                                Zlib.LZMA_Range_Decoders.Decode_Distance
                                  (D, Stream, Pos_Slot, Pos_Special, Pos_Align,
                                   Len, Local_Status);
                           begin
                              if Local_Status /= Ok then
                                 exit;
                              end if;

                              if Distance > Out_Pos
                                or else Len > Plain_Len - Out_Pos
                              then
                                 Status := Unsupported_Method;
                                 return Empty;
                              end if;

                              for I in 1 .. Len loop
                                 Out_Pos := Out_Pos + 1;
                                 Plain (Out_Pos) := Plain (Out_Pos - Distance);
                              end loop;

                              Rep3 := Rep2;
                              Rep2 := Rep1;
                              Rep1 := Rep0;
                              Rep0 := Distance;
                              Prev := Plain (Out_Pos);
                              State :=
                                Zlib.LZMA_Core.Match_State_After (State);
                           end;
                        end if;
                     end if;
                  end;
               end loop;

               if Local_Status /= Ok then
                  Status := Local_Status;
                  return Empty;
               end if;

               if Require_Full_Stream and then D.Pos /= Stream'Length then
                  Status := Unsupported_Method;
                  return Empty;
               end if;

               if Plain_Len = 0 then
                  Status := Ok;
                  return Empty;
               end if;

               Status := Ok;
               return Plain (1 .. Plain_Len);
            end;
         end;
      end;
   exception
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end Decode_Payload;

end Zlib.LZMA_Decoder;
