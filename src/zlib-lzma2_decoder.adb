with Zlib.LZMA_Range_Decoders;
with Zlib.LZMA2_Framing;

package body Zlib.LZMA2_Decoder is
   use type Zlib.LZMA2_Framing.Control_Kind;

   function Set_Properties
     (Ctx   : in out Context;
      Props : Byte) return Boolean
   is
      Decoded : constant Zlib.LZMA_Core.Property_Decode_Result :=
        Zlib.LZMA_Core.Decode_Properties (Props);
   begin
      if not Decoded.Valid then
         return False;
      end if;

      Ctx.LC := Decoded.Settings.LC;
      Ctx.LP := Decoded.Settings.LP;
      Ctx.PB := Decoded.Settings.PB;
      Ctx.Props_Seen := True;
      return True;
   end Set_Properties;

   function Properties_Seen (Ctx : Context) return Boolean is
     (Ctx.Props_Seen)
     with SPARK_Mode => On;

   procedure Reset_Dictionary
     (Ctx     : in out Context;
      Out_Pos : Natural)
     with SPARK_Mode => On
   is
   begin
      Ctx.Dict_Base := Out_Pos;
   end Reset_Dictionary;

   procedure Reset_State (Ctx : in out Context) is
   begin
      Ctx.State := 0;
      Ctx.Prev := 0;
      --  Standard LZMA initial reps: 0-based 0 == distance 1 (our 1-based
      --  convention). Only used by an early rep before any normal match.
      Ctx.Rep0 := 1;
      Ctx.Rep1 := 1;
      Ctx.Rep2 := 1;
      Ctx.Rep3 := 1;
      Zlib.LZMA_Core.Init_Probs (Ctx.Is_Match);
      Zlib.LZMA_Core.Init_Probs (Ctx.Is_Rep);
      Zlib.LZMA_Core.Init_Probs (Ctx.Is_Rep_G0);
      Zlib.LZMA_Core.Init_Probs (Ctx.Is_Rep_G1);
      Zlib.LZMA_Core.Init_Probs (Ctx.Is_Rep_G2);
      Zlib.LZMA_Core.Init_Probs (Ctx.Is_Rep0_Long);
      Zlib.LZMA_Core.Init_Len (Ctx.Match_Len);
      Zlib.LZMA_Core.Init_Len (Ctx.Rep_Len);
      Zlib.LZMA_Core.Init_Probs (Ctx.Pos_Slot);
      Zlib.LZMA_Core.Init_Probs (Ctx.Pos_Special);
      Zlib.LZMA_Core.Init_Probs (Ctx.Pos_Align);
      Zlib.LZMA_Core.Init_Probs (Ctx.Literals);
   end Reset_State;

   procedure Decode_Compressed_Chunk
     (Ctx       : in out Context;
      Stream    : Byte_Array;
      Plain     : in out Byte_Array;
      Out_Pos   : in out Natural;
      Chunk_Len : Natural;
      Status    : in out Status_Code)
   is
      D          : Zlib.LZMA_Range_Decoders.Decoder;
      Target_Pos : constant Natural := Out_Pos + Chunk_Len;
      Pos_States : constant Natural := 2 ** Ctx.PB;
   begin
      if Status /= Ok then
         return;
      end if;

      if not Ctx.Props_Seen or else Stream'Length < 5 then
         Status := Unexpected_End_Of_Input;
         return;
      end if;

      Zlib.LZMA_Range_Decoders.Init (D, Stream, Status);

      while Status = Ok and then Out_Pos < Target_Pos loop
         declare
            Pos_State : constant Natural := Out_Pos mod Pos_States;
            Match_Bit : constant Natural :=
              Zlib.LZMA_Range_Decoders.Decode_Bit
                (D, Stream,
                 Ctx.Is_Match (Ctx.State * Zlib.LZMA_Core.Num_Pos_States_Max
                               + Pos_State),
                 Status);
         begin
            if Status /= Ok then
               exit;
            end if;

            if Match_Bit = 0 then
               declare
                  Context_Index : constant Natural :=
                    Zlib.LZMA_Core.Literal_Context
                      (Ctx.LC, Ctx.LP, Out_Pos, Ctx.Prev);
                  Symbol        : Natural := 1;
               begin
                  if Ctx.State >= 7
                    and then Ctx.Rep0 > 0
                    and then Ctx.Rep0 <= Out_Pos - Ctx.Dict_Base
                  then
                     --  Matched literal (standard LZMA): decode bits against
                     --  the byte Rep0 back until they diverge.
                     declare
                        Match_Byte : Natural :=
                          Natural (Plain (Out_Pos - Ctx.Rep0 + 1));
                     begin
                        while Symbol < 16#100# loop
                           Match_Byte := Match_Byte * 2;
                           declare
                              Match_Bit_Literal : constant Natural :=
                                ((Match_Byte / 16#100#) mod 2) * 16#100#;
                              Decoded_Bit : constant Natural :=
                                Zlib.LZMA_Range_Decoders.Decode_Bit
                                  (D, Stream,
                                   Ctx.Literals
                                     (Context_Index * Zlib.LZMA_Core.Literal_Probs
                                      + 16#100# + Match_Bit_Literal + Symbol),
                                   Status);
                           begin
                              Symbol := Symbol * 2 + Decoded_Bit;
                              exit when Status /= Ok
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
                          Ctx.Literals
                            (Context_Index * Zlib.LZMA_Core.Literal_Probs + Symbol),
                          Status);
                     exit when Status /= Ok;
                  end loop;

                  if Status /= Ok then
                     exit;
                  end if;

                  Out_Pos := Out_Pos + 1;
                  Plain (Out_Pos) := Byte (Symbol - 16#100#);
                  Ctx.Prev := Plain (Out_Pos);
                  Ctx.State := Zlib.LZMA_Core.Literal_State_After (Ctx.State);
               end;
            else
               if Zlib.LZMA_Range_Decoders.Decode_Bit
                 (D, Stream, Ctx.Is_Rep (Ctx.State), Status) /= 0
               then
                  declare
                     Distance : Natural := Ctx.Rep0;
                     Len      : Natural := Zlib.LZMA_Core.Min_Match_Length;
                  begin
                     if Zlib.LZMA_Range_Decoders.Decode_Bit
                       (D, Stream, Ctx.Is_Rep_G0 (Ctx.State), Status) = 0
                     then
                        if Zlib.LZMA_Range_Decoders.Decode_Bit
                          (D, Stream,
                           Ctx.Is_Rep0_Long
                             (Ctx.State * Zlib.LZMA_Core.Num_Pos_States_Max
                              + Pos_State),
                           Status) = 0
                        then
                           Len := 1;
                           Ctx.State := Zlib.LZMA_Core.Short_Rep_State_After (Ctx.State);
                        else
                           Len :=
                             Zlib.LZMA_Range_Decoders.Decode_Len
                               (D, Stream, Ctx.Rep_Len, Pos_State, Status)
                             + Zlib.LZMA_Core.Min_Match_Length;
                           Ctx.State := Zlib.LZMA_Core.Rep_State_After (Ctx.State);
                        end if;
                     else
                        if Zlib.LZMA_Range_Decoders.Decode_Bit
                          (D, Stream, Ctx.Is_Rep_G1 (Ctx.State), Status) = 0
                        then
                           Distance := Ctx.Rep1;
                        else
                           if Zlib.LZMA_Range_Decoders.Decode_Bit
                             (D, Stream, Ctx.Is_Rep_G2 (Ctx.State), Status) = 0
                           then
                              Distance := Ctx.Rep2;
                           else
                              Distance := Ctx.Rep3;
                              Ctx.Rep3 := Ctx.Rep2;
                           end if;
                           Ctx.Rep2 := Ctx.Rep1;
                        end if;
                        Ctx.Rep1 := Ctx.Rep0;
                        Ctx.Rep0 := Distance;
                        Len :=
                          Zlib.LZMA_Range_Decoders.Decode_Len
                            (D, Stream, Ctx.Rep_Len, Pos_State, Status)
                          + Zlib.LZMA_Core.Min_Match_Length;
                        Ctx.State := Zlib.LZMA_Core.Rep_State_After (Ctx.State);
                     end if;

                     if Status /= Ok then
                        exit;
                     end if;

                     if Distance = 0
                       or else Distance > Out_Pos - Ctx.Dict_Base
                       or else Len > Target_Pos - Out_Pos
                     then
                        Status := Unsupported_Method;
                        return;
                     end if;

                     for I in 1 .. Len loop
                        Out_Pos := Out_Pos + 1;
                        Plain (Out_Pos) := Plain (Out_Pos - Distance);
                     end loop;

                     Ctx.Prev := Plain (Out_Pos);
                  end;
               else
                  declare
                     Len_Symbol : constant Natural :=
                       Zlib.LZMA_Range_Decoders.Decode_Len
                         (D, Stream, Ctx.Match_Len, Pos_State, Status);
                     Len        : constant Natural :=
                       Len_Symbol + Zlib.LZMA_Core.Min_Match_Length;
                     Distance   : constant Natural :=
                       Zlib.LZMA_Range_Decoders.Decode_Distance
                         (D, Stream, Ctx.Pos_Slot, Ctx.Pos_Special,
                          Ctx.Pos_Align, Len, Status);
                  begin
                     if Status /= Ok then
                        exit;
                     end if;

                     if Distance > Out_Pos - Ctx.Dict_Base
                       or else Len > Target_Pos - Out_Pos
                     then
                        Status := Unsupported_Method;
                        return;
                     end if;

                     for I in 1 .. Len loop
                        Out_Pos := Out_Pos + 1;
                        Plain (Out_Pos) := Plain (Out_Pos - Distance);
                     end loop;

                     Ctx.Rep3 := Ctx.Rep2;
                     Ctx.Rep2 := Ctx.Rep1;
                     Ctx.Rep1 := Ctx.Rep0;
                     Ctx.Rep0 := Distance;
                     Ctx.Prev := Plain (Out_Pos);
                     Ctx.State := Zlib.LZMA_Core.Match_State_After (Ctx.State);
                  end;
               end if;
            end if;
         end;
      end loop;

      if Status = Ok and then D.Pos /= Stream'Length then
         Status := Unsupported_Method;
      end if;
   end Decode_Compressed_Chunk;

   function Decode
     (Payload   : Byte_Array;
      Plain_Len : Natural;
      Status    : out Status_Code) return Byte_Array
   is
      Empty   : constant Byte_Array (1 .. 0) := [others => 0];
      Plain   : Byte_Array (1 .. Natural'Max (1, Plain_Len));
      Pos     : Natural := Payload'First;
      Out_Pos : Natural := 0;
      First   : Boolean := True;
      Ctx     : Context;
   begin
      Status := Unsupported_Method;
      Reset_State (Ctx);

      loop
         if Pos > Payload'Last then
            Status := Unexpected_End_Of_Input;
            return Empty;
         end if;

         declare
            Control : constant Byte := Payload (Pos);
            Info    : constant Zlib.LZMA2_Framing.Control_Info :=
              Zlib.LZMA2_Framing.Decode_Control (Control, First);
         begin
            Pos := Pos + 1;
            if Info.Kind = Zlib.LZMA2_Framing.End_Marker then
               exit;
            end if;

            if Info.Kind = Zlib.LZMA2_Framing.Uncompressed then
               if Pos + 1 > Payload'Last then
                  Status := Unsupported_Method;
                  return Empty;
               end if;

               declare
                  Chunk_Len : constant Natural :=
                    Zlib.LZMA2_Framing.Uncompressed_Size
                      (Payload (Pos), Payload (Pos + 1));
               begin
                  Pos := Pos + 2;
                  if Chunk_Len > Plain_Len - Out_Pos
                    or else Pos + Chunk_Len - 1 > Payload'Last
                  then
                     Status := Unexpected_End_Of_Input;
                     return Empty;
                  end if;

                  for I in 1 .. Chunk_Len loop
                     Plain (Out_Pos + I) := Payload (Pos + I - 1);
                  end loop;
                  Out_Pos := Out_Pos + Chunk_Len;
                  Pos := Pos + Chunk_Len;
                  if Info.Reset_Dict then
                     Reset_Dictionary (Ctx, Out_Pos);
                  end if;
                  First := False;
               end;
            elsif Info.Kind = Zlib.LZMA2_Framing.Compressed then
               if Pos + 3 + (if Info.Need_Props then 1 else 0) > Payload'Last then
                  Status := Unexpected_End_Of_Input;
                  return Empty;
               end if;

               declare
                  Chunk_Len    : constant Natural :=
                    Zlib.LZMA2_Framing.Compressed_Unpacked_Size
                      (Control, Payload (Pos), Payload (Pos + 1));
                  Packed_Len   : constant Natural :=
                    Zlib.LZMA2_Framing.Packed_Size
                      (Payload (Pos + 2), Payload (Pos + 3));
                  Props        : Byte := 0;
                  Local_Status : Status_Code := Ok;
               begin
                  Pos := Pos + 4;

                  if Info.Reset_Dict then
                     Reset_Dictionary (Ctx, Out_Pos);
                  end if;

                  if Info.Reset_State then
                     Reset_State (Ctx);
                  end if;

                  if Info.Need_Props then
                     Props := Payload (Pos);
                     Pos := Pos + 1;
                     if not Set_Properties (Ctx, Props) then
                        Status := Unsupported_Method;
                        return Empty;
                     end if;
                  elsif not Properties_Seen (Ctx) then
                     Status := Unsupported_Method;
                     return Empty;
                  end if;

                  if Chunk_Len > Plain_Len - Out_Pos
                    or else Pos + Packed_Len - 1 > Payload'Last
                  then
                     Status := Unexpected_End_Of_Input;
                     return Empty;
                  end if;

                  Decode_Compressed_Chunk
                    (Ctx, Payload (Pos .. Pos + Packed_Len - 1),
                     Plain, Out_Pos, Chunk_Len, Local_Status);

                  if Local_Status /= Ok then
                     Status := Local_Status;
                     return Empty;
                  end if;

                  Pos := Pos + Packed_Len;
                  First := False;
               end;
            else
               Status := Unsupported_Method;
               return Empty;
            end if;
         end;
      end loop;

      if Out_Pos /= Plain_Len or else Pos /= Payload'Last + 1 then
         Status := Unsupported_Method;
         return Empty;
      end if;

      Status := Ok;
      if Plain_Len = 0 then
         return Empty;
      end if;
      return Plain (1 .. Plain_Len);
   exception
      when Constraint_Error =>
         Status := Unexpected_End_Of_Input;
         return Empty;
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end Decode;

end Zlib.LZMA2_Decoder;
