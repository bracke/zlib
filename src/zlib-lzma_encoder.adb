with Interfaces;
with Zlib.Bit_Writer;
with Zlib.LZMA_Literals;
with Zlib.LZMA_Match_Finder;
with Zlib.LZMA_Parser;
with Zlib.LZMA_Range_Encoder;
with Zlib.LZMA_Repetitions;

package body Zlib.LZMA_Encoder is
   LZMA_Num_States      : constant Natural := Zlib.LZMA_Core.Num_States;
   LZMA_Literal_Probs   : constant Natural := Zlib.LZMA_Core.Literal_Probs;
   LZMA_Num_Pos_States_Max : constant Natural := Zlib.LZMA_Core.Num_Pos_States_Max;
   LZMA_Num_Len_To_Pos_States : constant Natural := Zlib.LZMA_Core.Num_Len_To_Pos_States;
   LZMA_Min_Match_Length : constant Natural := Zlib.LZMA_Core.Min_Match_Length;
   LZMA_Default_Dict    : constant Interfaces.Unsigned_32 := Zlib.LZMA_Core.Default_Dict;
   LZMA_End_Pos_Model_Index : constant Natural := Zlib.LZMA_Core.End_Pos_Model_Index;
   LZMA_Num_Full_Distances : constant Natural := Zlib.LZMA_Core.Num_Full_Distances;
   LZMA_Align_Table_Size : constant Natural := Zlib.LZMA_Core.Align_Table_Size;

   subtype LZMA_Prob_Array is Zlib.LZMA_Core.Prob_Array;

   subtype LZMA_Len_Encoder is Zlib.LZMA_Core.Len_Encoder;

   procedure LZMA_Init_Probs (Probs : out LZMA_Prob_Array)
     renames Zlib.LZMA_Core.Init_Probs;

   function LZMA_Literal_State_After (State : Natural) return Natural
     renames Zlib.LZMA_Core.Literal_State_After;

   function LZMA_Match_State_After (State : Natural) return Natural
     renames Zlib.LZMA_Core.Match_State_After;

   function LZMA_Rep_State_After (State : Natural) return Natural
     renames Zlib.LZMA_Core.Rep_State_After;

   function LZMA_Short_Rep_State_After (State : Natural) return Natural
     renames Zlib.LZMA_Core.Short_Rep_State_After;

   subtype LZMA_Range_Encoder_State is Zlib.LZMA_Range_Encoder.Encoder;

   procedure LZMA_Encode_Bit
     (E     : in out LZMA_Range_Encoder_State;
      Prob  : in out Interfaces.Unsigned_32;
      Bit   : Natural)
     renames Zlib.LZMA_Range_Encoder.Encode_Bit;

   procedure LZMA_Encode_Distance
     (E             : in out LZMA_Range_Encoder_State;
      Pos_Slot      : in out LZMA_Prob_Array;
      Pos_Special   : in out LZMA_Prob_Array;
      Pos_Align     : in out LZMA_Prob_Array;
      Len           : Natural;
      Distance      : Natural)
     renames Zlib.LZMA_Range_Encoder.Encode_Distance;

   procedure LZMA_Init_Len (Len : out LZMA_Len_Encoder)
     renames Zlib.LZMA_Core.Init_Len;

   procedure LZMA_Encode_Len
     (E         : in out LZMA_Range_Encoder_State;
      Len       : in out LZMA_Len_Encoder;
      Pos_State : Natural;
      Symbol    : Natural)
     renames Zlib.LZMA_Range_Encoder.Encode_Len;

   function Bit_Price
     (Prob : Interfaces.Unsigned_32; Bit : Natural) return Natural
     renames Zlib.LZMA_Core.Bit_Price;

   function Encode_Bounded
     (Plain          : Byte_Array;
      Lit_Ctx_Bits   : Natural := Zlib.LZMA_Core.Default_LC;
      Lit_Pos_Bits   : Natural := Zlib.LZMA_Core.Default_LP;
      Pos_State_Bits : Natural := Zlib.LZMA_Core.Default_PB) return Byte_Array
   is
      E             : LZMA_Range_Encoder_State;
      Pos_States    : constant Natural := 2 ** Pos_State_Bits;
      Literal_Ctxs  : constant Natural := 2 ** (Lit_Ctx_Bits + Lit_Pos_Bits);
      Is_Match      : LZMA_Prob_Array (0 .. LZMA_Num_States * LZMA_Num_Pos_States_Max - 1);
      Is_Rep        : LZMA_Prob_Array (0 .. LZMA_Num_States - 1);
      Is_Rep_G0     : LZMA_Prob_Array (0 .. LZMA_Num_States - 1);
      Is_Rep_G1     : LZMA_Prob_Array (0 .. LZMA_Num_States - 1);
      Is_Rep_G2     : LZMA_Prob_Array (0 .. LZMA_Num_States - 1);
      Is_Rep0_Long  : LZMA_Prob_Array (0 .. LZMA_Num_States * LZMA_Num_Pos_States_Max - 1);
      Match_Len     : LZMA_Len_Encoder;
      Rep_Len       : LZMA_Len_Encoder;
      Pos_Slot      : LZMA_Prob_Array
        (0 .. LZMA_Num_Len_To_Pos_States * 64 - 1);
      Pos_Special   : LZMA_Prob_Array
        (0 .. LZMA_Num_Full_Distances - LZMA_End_Pos_Model_Index - 1);
      Pos_Align     : LZMA_Prob_Array (0 .. LZMA_Align_Table_Size - 1);
      Literals      : LZMA_Prob_Array (0 .. Literal_Ctxs * LZMA_Literal_Probs - 1);
      State         : Natural := 0;
      Prev          : Byte := 0;
      Position      : Natural := 0;
      In_Index      : Natural := Plain'First;
      Rep0          : Natural := 0;
      Rep1          : Natural := 0;
      Rep2          : Natural := 0;
      Rep3          : Natural := 0;

      Nice_Len     : constant Natural := Zlib.LZMA_Match_Finder.Nice_Len;
      Base_Seg_Len : constant Natural := Zlib.LZMA_Match_Finder.Base_Seg_Len;
      Max_Seg_Len  : constant Natural := Zlib.LZMA_Match_Finder.Max_Seg_Len;
      Hash_Bits    : constant Natural := Zlib.LZMA_Match_Finder.Hash_Bits;
      Dict_Sz   : constant Natural := Natural (LZMA_Default_Dict);
      subtype Pos_Table is Zlib.LZMA_Match_Finder.Pos_Table;
      Head  : Pos_Table (0 .. 2 ** Hash_Bits - 1) := [others => 0];
      Chain : Pos_Table (1 .. Natural'Max (Plain'Length, 1)) := [others => 0];

      function Match_Length (I, D : Natural) return Natural is
        (Zlib.LZMA_Match_Finder.Match_Length (Plain, I, D));

      procedure Emit_Literal is
         B         : constant Byte := Plain (In_Index);
         Pos_State : constant Natural := Position mod Pos_States;
      begin
         LZMA_Encode_Bit
           (E, Is_Match (State * LZMA_Num_Pos_States_Max + Pos_State), 0);
         Zlib.LZMA_Literals.Encode
           (E            => E,
            Literals     => Literals,
            Plain        => Plain,
            Index        => In_Index,
            State        => State,
            Rep0         => Rep0,
            Position     => Position,
            Lit_Ctx_Bits => Lit_Ctx_Bits,
            Lit_Pos_Bits => Lit_Pos_Bits,
            Prev         => Prev);
         State := LZMA_Literal_State_After (State);
         Prev := B;
         Position := Position + 1;
         In_Index := In_Index + 1;
      end Emit_Literal;

      ----------------------------------------------------------------------
      --  Optimal parser: price-based shortest-path over each segment.
      --  Pricing helpers mirror the encode routines exactly (in 1/16-bit
      --  units); emission reuses the proven encoders, so a wrong price only
      --  costs ratio, never correctness.
      ----------------------------------------------------------------------

      function Lit_Price_At
        (I : Natural; St : Natural; Rep0_D : Natural) return Natural
      is
        (Zlib.LZMA_Literals.Price
           (Literals     => Literals,
            Plain        => Plain,
            Index        => I,
            State        => St,
            Rep0         => Rep0_D,
            Position     => I - Plain'First,
            Lit_Ctx_Bits => Lit_Ctx_Bits,
            Lit_Pos_Bits => Lit_Pos_Bits));

      function Rep_Choice_Price
        (St, Idx, Pos_State : Natural) return Natural
      is
        (Zlib.LZMA_Repetitions.Choice_Price
           (Is_Rep_G0    => Is_Rep_G0,
            Is_Rep_G1    => Is_Rep_G1,
            Is_Rep_G2    => Is_Rep_G2,
            Is_Rep0_Long => Is_Rep0_Long,
            State        => St,
            Rep_Index    => Idx,
            Pos_State    => Pos_State));

      procedure Emit_Match (Dist, Len : Natural) is
         Pos_State : constant Natural := Position mod Pos_States;
      begin
         LZMA_Encode_Bit
           (E, Is_Match (State * LZMA_Num_Pos_States_Max + Pos_State), 1);
         LZMA_Encode_Bit (E, Is_Rep (State), 0);
         LZMA_Encode_Len
           (E, Match_Len, Pos_State, Len - LZMA_Min_Match_Length);
         LZMA_Encode_Distance
           (E, Pos_Slot, Pos_Special, Pos_Align, Len, Dist);
         Rep3 := Rep2;
         Rep2 := Rep1;
         Rep1 := Rep0;
         Rep0 := Dist;
         State := LZMA_Match_State_After (State);
         Prev := Plain (In_Index + Len - 1);
         Position := Position + Len;
         In_Index := In_Index + Len;
      end Emit_Match;

      procedure Emit_Rep (Idx, Len : Natural) is
         Pos_State : constant Natural := Position mod Pos_States;
      begin
         LZMA_Encode_Bit
           (E, Is_Match (State * LZMA_Num_Pos_States_Max + Pos_State), 1);
         LZMA_Encode_Bit (E, Is_Rep (State), 1);
         case Idx is
            when 0 =>
               LZMA_Encode_Bit (E, Is_Rep_G0 (State), 0);
               LZMA_Encode_Bit
                 (E,
                  Is_Rep0_Long (State * LZMA_Num_Pos_States_Max + Pos_State), 1);
            when 1 =>
               LZMA_Encode_Bit (E, Is_Rep_G0 (State), 1);
               LZMA_Encode_Bit (E, Is_Rep_G1 (State), 0);
               declare
                  D : constant Natural := Rep1;
               begin
                  Rep1 := Rep0;
                  Rep0 := D;
               end;
            when 2 =>
               LZMA_Encode_Bit (E, Is_Rep_G0 (State), 1);
               LZMA_Encode_Bit (E, Is_Rep_G1 (State), 1);
               LZMA_Encode_Bit (E, Is_Rep_G2 (State), 0);
               declare
                  D : constant Natural := Rep2;
               begin
                  Rep2 := Rep1;
                  Rep1 := Rep0;
                  Rep0 := D;
               end;
            when others =>
               LZMA_Encode_Bit (E, Is_Rep_G0 (State), 1);
               LZMA_Encode_Bit (E, Is_Rep_G1 (State), 1);
               LZMA_Encode_Bit (E, Is_Rep_G2 (State), 1);
               declare
                  D : constant Natural := Rep3;
               begin
                  Rep3 := Rep2;
                  Rep2 := Rep1;
                  Rep1 := Rep0;
                  Rep0 := D;
               end;
         end case;
         LZMA_Encode_Len (E, Rep_Len, Pos_State, Len - LZMA_Min_Match_Length);
         State := LZMA_Rep_State_After (State);
         Prev := Plain (In_Index + Len - 1);
         Position := Position + Len;
         In_Index := In_Index + Len;
      end Emit_Rep;

      procedure Emit_Short_Rep is
         Pos_State : constant Natural := Position mod Pos_States;
      begin
         LZMA_Encode_Bit
           (E, Is_Match (State * LZMA_Num_Pos_States_Max + Pos_State), 1);
         LZMA_Encode_Bit (E, Is_Rep (State), 1);
         LZMA_Encode_Bit (E, Is_Rep_G0 (State), 0);
         LZMA_Encode_Bit
           (E, Is_Rep0_Long (State * LZMA_Num_Pos_States_Max + Pos_State), 0);
         State := LZMA_Short_Rep_State_After (State);
         Prev := Plain (In_Index);
         Position := Position + 1;
         In_Index := In_Index + 1;
      end Emit_Short_Rep;

      subtype Rep_Quad is Zlib.LZMA_Core.Rep_Quad;
      --  The parser starts with stock-sized 8 KiB passes, then extends a pass
      --  when a nice-length match would otherwise be cut at the boundary.
      Opt : Zlib.LZMA_Parser.Opt_Array (0 .. Max_Seg_Len);
   begin
      Zlib.Bit_Writer.Reset (E.Writer);
      LZMA_Init_Probs (Is_Match);
      LZMA_Init_Probs (Is_Rep);
      LZMA_Init_Probs (Is_Rep_G0);
      LZMA_Init_Probs (Is_Rep_G1);
      LZMA_Init_Probs (Is_Rep_G2);
      LZMA_Init_Probs (Is_Rep0_Long);
      LZMA_Init_Len (Match_Len);
      LZMA_Init_Len (Rep_Len);
      LZMA_Init_Probs (Pos_Slot);
      LZMA_Init_Probs (Pos_Special);
      LZMA_Init_Probs (Pos_Align);
      LZMA_Init_Probs (Literals);

      while In_Index <= Plain'Last loop
         declare
            Base_Pos : constant Natural := Position;
            Cur      : constant Natural := In_Index;
            Span     : Natural :=
              Natural'Min (Base_Seg_Len, Plain'Last - Cur + 1);
         begin
            Zlib.LZMA_Match_Finder.Prepare_Adaptive_Segment
              (Plain, Head, Chain, Cur, Dict_Sz, Span);

            --  Initialise the DP for this segment from the live coder state.
            Opt (0) :=
              (Price => 0, From => 0, Kind => Zlib.LZMA_Parser.Op_Lit,
               Dist => 0, Len => 1, Rep_Idx => 0, St => State,
               Reps => [Rep0, Rep1, Rep2, Rep3]);
            for J in 1 .. Span loop
               Opt (J).Price := Natural'Last;
            end loop;

            --  Forward relaxation over the segment.
            for I in 0 .. Span - 1 loop
               if Opt (I).Price < Natural'Last then
                  declare
                     S   : constant Natural := Opt (I).St;
                     R   : constant Rep_Quad := Opt (I).Reps;
                     P   : constant Natural := Opt (I).Price;
                     CI  : constant Natural := Cur + I;
                     Pos : constant Natural := Base_Pos + I;
                     PS  : constant Natural := Pos mod Pos_States;
                     Mbase : constant Natural :=
                       P + Bit_Price
                             (Is_Match (S * LZMA_Num_Pos_States_Max + PS), 1);

                     procedure Relax
                       (J, New_Price : Natural; Kind : Zlib.LZMA_Parser.Opt_Kind;
                        Dist, Len, Ridx, New_St : Natural; New_R : Rep_Quad) is
                     begin
                        if New_Price < Opt (J).Price then
                           Opt (J) :=
                             (Price => New_Price, From => I, Kind => Kind,
                              Dist => Dist, Len => Len, Rep_Idx => Ridx,
                              St => New_St, Reps => New_R);
                        end if;
                     end Relax;
                  begin
                     --  Literal.
                     Relax
                       (I + 1,
                        P + Bit_Price
                              (Is_Match (S * LZMA_Num_Pos_States_Max + PS), 0)
                          + Lit_Price_At (CI, S, R (0)),
                        Zlib.LZMA_Parser.Op_Lit,
                        0, 1, 0, LZMA_Literal_State_After (S), R);

                     --  One-byte rep0 match.
                     if R (0) > 0 and then R (0) <= Pos
                       and then Plain (CI) = Plain (CI - R (0))
                     then
                        Relax
                          (I + 1,
                           Mbase + Bit_Price (Is_Rep (S), 1)
                           + Bit_Price (Is_Rep_G0 (S), 0)
                           + Bit_Price
                               (Is_Rep0_Long
                                  (S * LZMA_Num_Pos_States_Max + PS), 0),
                           Zlib.LZMA_Parser.Op_Short_Rep, R (0), 1, 0,
                           LZMA_Short_Rep_State_After (S), R);
                     end if;

                     --  Repeated-distance matches (every length).
                     for Idx in 0 .. 3 loop
                        if R (Idx) > 0 and then R (Idx) <= Pos then
                           declare
                              Max_L  : constant Natural :=
                                Natural'Min (Match_Length (CI, R (Idx)),
                                             Span - I);
                              Base   : constant Natural :=
                                Mbase + Bit_Price (Is_Rep (S), 1)
                                + Rep_Choice_Price (S, Idx, PS);
                              New_R  : constant Rep_Quad :=
                                Zlib.LZMA_Core.Reorder_Reps (R, Idx);
                              New_St : constant Natural := LZMA_Rep_State_After (S);
                              --  A long match is taken whole; only short ones
                              --  need every length explored (keeps the DP fast
                              --  on repetitive data).
                              From_L : constant Natural :=
                                (if Max_L >= Nice_Len then Max_L
                                 else LZMA_Min_Match_Length);
                           begin
                              for Len in From_L .. Max_L loop
                                 Relax
                                   (I + Len,
                                    Base + Zlib.LZMA_Range_Encoder.Len_Price
                                             (Rep_Len, PS,
                                              Len - LZMA_Min_Match_Length),
                                    Zlib.LZMA_Parser.Op_Rep,
                                    R (Idx), Len, Idx, New_St, New_R);
                              end loop;
                           end;
                        end if;
                     end loop;

                     --  Normal matches: each length at its shortest distance.
                     declare
                        Count       : Natural;
                        Lens, Dists : Zlib.LZMA_Match_Finder.Len_Array;
                        Prev_L      : Natural := LZMA_Min_Match_Length - 1;
                     begin
                        Zlib.LZMA_Match_Finder.Find_All_Matches
                          (Plain, Head, Chain, CI, Dict_Sz,
                           Count, Lens, Dists);
                        for K in 1 .. Count loop
                           declare
                              D      : constant Natural := Dists (K);
                              Upto   : constant Natural :=
                                Natural'Min (Lens (K), Span - I);
                              New_R  : constant Rep_Quad :=
                                Zlib.LZMA_Core.Shift_Reps (R, D);
                              New_St : constant Natural :=
                                LZMA_Match_State_After (S);
                              Base   : constant Natural :=
                                Mbase + Bit_Price (Is_Rep (S), 0);
                              From_L : constant Natural :=
                                (if Upto >= Nice_Len then Upto
                                 else Natural'Max
                                        (LZMA_Min_Match_Length, Prev_L + 1));
                           begin
                              for Len in From_L .. Upto loop
                                 Relax
                                   (I + Len,
                                    Base
                                    + Zlib.LZMA_Range_Encoder.Len_Price
                                        (Match_Len, PS,
                                         Len - LZMA_Min_Match_Length)
                                    + Zlib.LZMA_Range_Encoder.Distance_Price
                                        (Pos_Slot, Pos_Special, Pos_Align,
                                         Len, D),
                                    Zlib.LZMA_Parser.Op_Match,
                                    D, Len, 0, New_St, New_R);
                              end loop;
                              Prev_L := Lens (K);
                           end;
                        end loop;
                     end;
                  end;
               end if;
            end loop;

            --  Backtrack the cheapest path, then emit it forwards.
            declare
               Ops : Zlib.LZMA_Parser.Op_Array (1 .. Span);
               N   : Natural := 0;
            begin
               Zlib.LZMA_Parser.Backtrack (Opt, Span, Ops, N);
               for M in reverse 1 .. N loop
                  case Ops (M).Kind is
                     when Zlib.LZMA_Parser.Op_Lit =>
                        Emit_Literal;
                     when Zlib.LZMA_Parser.Op_Match =>
                        Emit_Match (Ops (M).Dist, Ops (M).Len);
                     when Zlib.LZMA_Parser.Op_Rep =>
                        Emit_Rep (Ops (M).Ridx, Ops (M).Len);
                     when Zlib.LZMA_Parser.Op_Short_Rep =>
                        Emit_Short_Rep;
                  end case;
               end loop;
            end;
         end;
      end loop;

      return Zlib.LZMA_Range_Encoder.Finish (E);
   end Encode_Bounded;

end Zlib.LZMA_Encoder;
