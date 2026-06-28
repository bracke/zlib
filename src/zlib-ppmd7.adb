--  Faithful clean-room port of the LZMA SDK PPMd7 (PPMd variant H) model and
--  the 7z range coder. See the package spec for scope. Layout mirrors the C:
--  a flat byte pool addressed by 32-bit "refs" (byte offsets), a unit
--  sub-allocator, a suffix-context tree, SEE and binary contexts.

with Ada.Unchecked_Deallocation;

package body Zlib.PPMd7 is

   use Interfaces;

   subtype U16 is Interfaces.Unsigned_16;
   subtype U32 is Interfaces.Unsigned_32;
   subtype U64 is Interfaces.Unsigned_64;

   Unit_Size        : constant := 12;
   Num_Indexes      : constant := 38;
   Bin_Scale        : constant := 2 ** 14;      --  PPMD_BIN_SCALE
   Period_Bits      : constant := 7;            --  PPMD_PERIOD_BITS
   Top_Value        : constant U32 := 2 ** 24;  --  range-coder kTopValue
   Max_Freq         : constant := 124;

   K_Init_Bin_Esc : constant array (0 .. 7) of U16 :=
     [16#3CDD#, 16#1F3F#, 16#59BF#, 16#48F3#,
      16#64A1#, 16#5ABC#, 16#6632#, 16#6051#];

   type See_Type is record
      Summ  : U16 := 0;
      Shift : Byte := 0;
      Count : Byte := 0;
   end record;

   type Byte_Array_Access is access Byte_Array;
   procedure Free_Pool is
     new Ada.Unchecked_Deallocation (Byte_Array, Byte_Array_Access);

   type Nat_38 is array (0 .. Num_Indexes - 1) of Natural;
   type Nat_128 is array (0 .. 127) of Natural;
   type Nat_256 is array (0 .. 255) of Natural;
   type See_Grid is array (0 .. 24, 0 .. 15) of See_Type;
   type Bin_Grid is array (0 .. 127, 0 .. 63) of U16;

   --  The model. "Ref" fields and the Text/Unit pointers are 0-based byte
   --  offsets into Base.all; ref 0 means NULL.
   type CPpmd7 is record
      Base        : Byte_Array_Access;
      Size        : U32 := 0;
      Align_Off   : Natural := 0;

      Min_Context : Natural := 0;   --  ref to current (deepest) context
      Max_Context : Natural := 0;   --  ref to current shallowest context
      Found_State : Natural := 0;   --  ref to the state just coded

      Text        : Natural := 0;   --  next text-pool write position
      Hi_Unit     : Natural := 0;
      Lo_Unit     : Natural := 0;
      Units_Start : Natural := 0;

      Glue_Count  : U32 := 0;
      Order_Fall  : Natural := 0;
      Run_Length  : Integer := 0;
      Init_RL     : Integer := 0;
      Prev_Success : Natural := 0;
      Max_Order   : Natural := 0;
      Init_Esc    : Natural := 0;
      Hi_Bits_Flag : Natural := 0;

      Free_List   : Nat_38 := [others => 0];
      Indx2Units  : Nat_38 := [others => 0];
      Units2Indx  : Nat_128 := [others => 0];
      NS2BSIndx   : Nat_256 := [others => 0];
      NS2Indx     : Nat_256 := [others => 0];
      HB2Flag     : Nat_256 := [others => 0];
      See         : See_Grid;
      Bin_Summ    : Bin_Grid := [others => [others => 0]];
      Dummy_See   : See_Type := (0, 0, 0);
   end record;

   --  7z range decoder.
   type Range_Dec is record
      Code      : U32 := 0;
      Rng       : U32 := 0;
      In_Buf    : Byte_Array_Access;  --  not owned; aliases input
      In_Pos    : Natural := 0;       --  next byte index in In_Buf
      In_Last   : Natural := 0;
      Overrun   : Boolean := False;
   end record;

   --  7z range encoder. Output bytes accumulate in Out_Buf (grown on demand).
   type Range_Enc is record
      Low        : U64 := 0;
      Rng        : U32 := 16#FFFF_FFFF#;
      Cache      : Byte := 0;
      Cache_Size : U64 := 1;
      Out_Buf    : Byte_Array_Access;
      Out_Len    : Natural := 0;
   end record;

   ----------------------------------------------------------------------
   --  Pool accessors (little-endian fields within Base.all).
   ----------------------------------------------------------------------

   function Get_U16 (P : CPpmd7; R : Natural) return U32 is
     (U32 (P.Base (R)) or Shift_Left (U32 (P.Base (R + 1)), 8));

   procedure Set_U16 (P : CPpmd7; R : Natural; V : U32) is
   begin
      P.Base (R) := Byte (V and 16#FF#);
      P.Base (R + 1) := Byte (Shift_Right (V, 8) and 16#FF#);
   end Set_U16;

   function Get_U32 (P : CPpmd7; R : Natural) return U32 is
     (U32 (P.Base (R))
      or Shift_Left (U32 (P.Base (R + 1)), 8)
      or Shift_Left (U32 (P.Base (R + 2)), 16)
      or Shift_Left (U32 (P.Base (R + 3)), 24));

   procedure Set_U32 (P : CPpmd7; R : Natural; V : U32) is
   begin
      P.Base (R) := Byte (V and 16#FF#);
      P.Base (R + 1) := Byte (Shift_Right (V, 8) and 16#FF#);
      P.Base (R + 2) := Byte (Shift_Right (V, 16) and 16#FF#);
      P.Base (R + 3) := Byte (Shift_Right (V, 24) and 16#FF#);
   end Set_U32;

   --  Context fields (C is a context ref).
   function Ctx_Num_Stats (P : CPpmd7; C : Natural) return Natural is
     (Natural (Get_U16 (P, C)));
   procedure Set_Num_Stats (P : CPpmd7; C : Natural; V : Natural) is
   begin
      Set_U16 (P, C, U32 (V));
   end Set_Num_Stats;

   function Ctx_Summ_Freq (P : CPpmd7; C : Natural) return Natural is
     (Natural (Get_U16 (P, C + 2)));
   procedure Set_Summ_Freq (P : CPpmd7; C : Natural; V : Natural) is
   begin
      Set_U16 (P, C + 2, U32 (V));
   end Set_Summ_Freq;

   function Ctx_Stats (P : CPpmd7; C : Natural) return Natural is
     (Natural (Get_U32 (P, C + 4)));
   procedure Set_Stats (P : CPpmd7; C : Natural; V : Natural) is
   begin
      Set_U32 (P, C + 4, U32 (V));
   end Set_Stats;

   function Ctx_Suffix (P : CPpmd7; C : Natural) return Natural is
     (Natural (Get_U32 (P, C + 8)));
   procedure Set_Suffix (P : CPpmd7; C : Natural; V : Natural) is
   begin
      Set_U32 (P, C + 8, U32 (V));
   end Set_Suffix;

   --  The single state of a one-state context overlaps SummFreq/Stats.
   function One_State (C : Natural) return Natural is (C + 2);

   --  State fields (S is a state ref).
   function St_Symbol (P : CPpmd7; S : Natural) return Byte is (P.Base (S));
   procedure Set_Symbol (P : CPpmd7; S : Natural; V : Byte) is
   begin
      P.Base (S) := V;
   end Set_Symbol;

   function St_Freq (P : CPpmd7; S : Natural) return Natural is
     (Natural (P.Base (S + 1)));
   procedure Set_Freq (P : CPpmd7; S : Natural; V : Natural) is
   begin
      P.Base (S + 1) := Byte (V);
   end Set_Freq;

   function St_Successor (P : CPpmd7; S : Natural) return Natural is
     (Natural (Get_U16 (P, S + 2)) + Natural (Get_U16 (P, S + 4)) * 65536);
   procedure Set_Successor (P : CPpmd7; S : Natural; V : Natural) is
   begin
      Set_U16 (P, S + 2, U32 (V mod 65536));
      Set_U16 (P, S + 4, U32 (V / 65536));
   end Set_Successor;

   --  nu units <-> bytes and index conversions.
   function U2B (NU : Natural) return Natural is (NU * Unit_Size);
   function U2I (P : CPpmd7; NU : Natural) return Natural is
     (P.Units2Indx (NU - 1));
   function I2U (P : CPpmd7; Indx : Natural) return Natural is
     (P.Indx2Units (Indx));

   ----------------------------------------------------------------------
   --  Construction of the static tables (Ppmd7_Construct).
   ----------------------------------------------------------------------

   procedure Construct (P : in out CPpmd7) is
      K : Natural := 0;
      M : Natural;
      I : Natural;
   begin
      I := 0;
      while I < Num_Indexes loop
         declare
            Step : Natural := (if I >= 12 then 4 else (I / 4) + 1);
         begin
            loop
               P.Units2Indx (K) := I;
               K := K + 1;
               Step := Step - 1;
               exit when Step = 0;
            end loop;
            P.Indx2Units (I) := K;
         end;
         I := I + 1;
      end loop;

      P.NS2BSIndx (0) := 0;
      P.NS2BSIndx (1) := 2;
      for J in 2 .. 10 loop
         P.NS2BSIndx (J) := 4;
      end loop;
      for J in 11 .. 255 loop
         P.NS2BSIndx (J) := 6;
      end loop;

      for J in 0 .. 2 loop
         P.NS2Indx (J) := J;
      end loop;
      M := 3;
      K := 1;
      for J in 3 .. 255 loop
         P.NS2Indx (J) := M;
         K := K - 1;
         if K = 0 then
            M := M + 1;
            K := M - 2;
         end if;
      end loop;

      for J in 0 .. 16#3F# loop
         P.HB2Flag (J) := 0;
      end loop;
      for J in 16#40# .. 16#FF# loop
         P.HB2Flag (J) := 8;
      end loop;
   end Construct;

   ----------------------------------------------------------------------
   --  Sub-allocator (faithful to Ppmd7.c). Free nodes store their "next"
   --  ref in their first 4 bytes.
   ----------------------------------------------------------------------

   procedure Insert_Node (P : in out CPpmd7; Node : Natural; Indx : Natural) is
   begin
      Set_U32 (P, Node, U32 (P.Free_List (Indx)));
      P.Free_List (Indx) := Node;
   end Insert_Node;

   function Remove_Node (P : in out CPpmd7; Indx : Natural) return Natural is
      Node : constant Natural := P.Free_List (Indx);
   begin
      P.Free_List (Indx) := Natural (Get_U32 (P, Node));
      return Node;
   end Remove_Node;

   procedure Split_Block
     (P : in out CPpmd7; Ptr : Natural; Old_Indx, New_Indx : Natural)
   is
      NU : constant Natural := I2U (P, Old_Indx) - I2U (P, New_Indx);
      PV : constant Natural := Ptr + U2B (I2U (P, New_Indx));
      I  : Natural := U2I (P, NU);
   begin
      if I2U (P, I) /= NU then
         declare
            KK : constant Natural := I2U (P, I - 1);
         begin
            I := I - 1;
            Insert_Node (P, PV + U2B (KK), NU - KK - 1);
         end;
      end if;
      Insert_Node (P, PV, I);
   end Split_Block;

   procedure Glue_Free_Blocks (P : in out CPpmd7);
   --  Defined later; rebuilds/merges the free lists (OOM path).

   function Alloc_Units_Rare
     (P : in out CPpmd7; Indx : Natural) return Natural
   is
      I : Natural;
   begin
      if P.Glue_Count = 0 then
         Glue_Free_Blocks (P);
         if P.Free_List (Indx) /= 0 then
            return Remove_Node (P, Indx);
         end if;
      end if;
      I := Indx;
      loop
         I := I + 1;
         if I = Num_Indexes then
            declare
               Num_Bytes : constant Natural := U2B (I2U (P, Indx));
            begin
               P.Glue_Count := P.Glue_Count - 1;
               if P.Units_Start - P.Text > Num_Bytes then
                  P.Units_Start := P.Units_Start - Num_Bytes;
                  return P.Units_Start;
               else
                  return 0;
               end if;
            end;
         end if;
         exit when P.Free_List (I) /= 0;
      end loop;
      declare
         Ret : constant Natural := Remove_Node (P, I);
      begin
         Split_Block (P, Ret, I, Indx);
         return Ret;
      end;
   end Alloc_Units_Rare;

   function Alloc_Units (P : in out CPpmd7; Indx : Natural) return Natural is
      Num_Bytes : Natural;
   begin
      if P.Free_List (Indx) /= 0 then
         return Remove_Node (P, Indx);
      end if;
      Num_Bytes := U2B (I2U (P, Indx));
      if Num_Bytes <= P.Hi_Unit - P.Lo_Unit then
         declare
            Ret : constant Natural := P.Lo_Unit;
         begin
            P.Lo_Unit := P.Lo_Unit + Num_Bytes;
            return Ret;
         end;
      end if;
      return Alloc_Units_Rare (P, Indx);
   end Alloc_Units;

   function Shrink_Units
     (P : in out CPpmd7; Old_Ptr : Natural; Old_NU, New_NU : Natural)
      return Natural
   is
      I0 : constant Natural := U2I (P, Old_NU);
      I1 : constant Natural := U2I (P, New_NU);
   begin
      if I0 = I1 then
         return Old_Ptr;
      end if;
      if P.Free_List (I1) /= 0 then
         declare
            Ptr : constant Natural := Remove_Node (P, I1);
         begin
            P.Base (Ptr .. Ptr + U2B (New_NU) - 1) :=
              P.Base (Old_Ptr .. Old_Ptr + U2B (New_NU) - 1);
            Insert_Node (P, Old_Ptr, I0);
            return Ptr;
         end;
      end if;
      Split_Block (P, Old_Ptr, I0, I1);
      return Old_Ptr;
   end Shrink_Units;

   procedure Free_Units
     (P : in out CPpmd7; Ptr : Natural; NU : Natural) is
   begin
      Insert_Node (P, Ptr, U2I (P, NU));
   end Free_Units;

   ----------------------------------------------------------------------
   --  Model restart / init.
   ----------------------------------------------------------------------

   procedure Restart_Model (P : in out CPpmd7) is
      Stats : Natural;
   begin
      P.Free_List := [others => 0];
      P.Text := P.Align_Off;
      P.Hi_Unit := P.Align_Off + Natural (P.Size);
      P.Lo_Unit := P.Hi_Unit - Natural (P.Size) / 8 / Unit_Size * 7 * Unit_Size;
      P.Units_Start := P.Lo_Unit;
      P.Glue_Count := 0;

      P.Order_Fall := P.Max_Order;
      P.Init_RL := -(if P.Max_Order < 12 then P.Max_Order else 12) - 1;
      P.Run_Length := P.Init_RL;
      P.Prev_Success := 0;

      --  Root context: one unit at the top of the pool.
      P.Hi_Unit := P.Hi_Unit - Unit_Size;
      P.Min_Context := P.Hi_Unit;
      P.Max_Context := P.Hi_Unit;
      Set_Suffix (P, P.Min_Context, 0);
      Set_Num_Stats (P, P.Min_Context, 256);
      Set_Summ_Freq (P, P.Min_Context, 256 + 1);

      P.Found_State := P.Lo_Unit;
      Stats := P.Lo_Unit;
      Set_Stats (P, P.Min_Context, Stats);
      P.Lo_Unit := P.Lo_Unit + U2B (256 / 2);
      for I in 0 .. 255 loop
         declare
            S : constant Natural := Stats + I * 6;
         begin
            Set_Symbol (P, S, Byte (I));
            Set_Freq (P, S, 1);
            Set_Successor (P, S, 0);
         end;
      end loop;

      for I in 0 .. 127 loop
         for K in 0 .. 7 loop
            declare
               Val : constant U16 :=
                 U16 (Bin_Scale - Natural (K_Init_Bin_Esc (K)) / (I + 2));
            begin
               for M in 0 .. 7 loop
                  P.Bin_Summ (I, K + M * 8) := Val;
               end loop;
            end;
         end loop;
      end loop;

      for I in 0 .. 24 loop
         for K in 0 .. 15 loop
            P.See (I, K) :=
              (Summ => U16 (Shift_Left (U32 (5 * I + 10), Period_Bits - 4)),
               Shift => Byte (Period_Bits - 4),
               Count => 4);
         end loop;
      end loop;
      P.Dummy_See := (Summ => 0, Shift => Byte (Period_Bits), Count => 64);
   end Restart_Model;

   procedure Init (P : in out CPpmd7; Order : Natural) is
   begin
      P.Max_Order := Order;
      Restart_Model (P);
   end Init;

   --  Placeholder for the OOM glue path (only hit by large inputs).
   --  Coalesce adjacent free blocks back into larger units, then re-split
   --  them across the indexed free lists (faithful to Ppmd7 GlueFreeBlocks).
   --  Free nodes are tagged Stamp=0; allocated contexts/state blocks always
   --  have a non-zero first u16, and the Head/Lo_Unit sentinels are tagged 1,
   --  so the merge knows where to stop. PPMd output is address-independent,
   --  so what matters is reclaiming the same memory stock does (hence the same
   --  model-restart timing), not byte-matching its internal free lists.
   procedure Glue_Free_Blocks (P : in out CPpmd7) is
      Head : constant Natural := P.Align_Off + Natural (P.Size);
      N    : Natural := Head;

      function Nd_Stamp (R : Natural) return Natural is
        (Natural (Get_U16 (P, R)));
      procedure Set_Stamp (R, V : Natural) is
      begin
         Set_U16 (P, R, U32 (V));
      end Set_Stamp;
      function Nd_NU (R : Natural) return Natural is
        (Natural (Get_U16 (P, R + 2)));
      procedure Set_NU (R, V : Natural) is
      begin
         Set_U16 (P, R + 2, U32 (V));
      end Set_NU;
      function Nd_Next (R : Natural) return Natural is
        (Natural (Get_U32 (P, R + 4)));
      procedure Set_Next (R, V : Natural) is
      begin
         Set_U32 (P, R + 4, U32 (V));
      end Set_Next;
      function Nd_Prev (R : Natural) return Natural is
        (Natural (Get_U32 (P, R + 8)));
      procedure Set_Prev (R, V : Natural) is
      begin
         Set_U32 (P, R + 8, U32 (V));
      end Set_Prev;
   begin
      P.Glue_Count := 255;

      --  Build a doubly-linked list of every free block (Stamp = 0).
      for I in 0 .. Num_Indexes - 1 loop
         declare
            NU  : constant Natural := I2U (P, I);
            Nxt : Natural := P.Free_List (I);
         begin
            P.Free_List (I) := 0;
            while Nxt /= 0 loop
               declare
                  Node : constant Natural := Nxt;
               begin
                  Nxt := Natural (Get_U32 (P, Node));  -- old singly-linked next
                  Set_Next (Node, N);
                  Set_Prev (N, Node);
                  N := Node;
                  Set_Stamp (Node, 0);
                  Set_NU (Node, NU);
               end;
            end loop;
         end;
      end loop;

      Set_Stamp (Head, 1);
      Set_Next (Head, N);
      Set_Prev (N, Head);
      if P.Lo_Unit /= P.Hi_Unit then
         Set_Stamp (P.Lo_Unit, 1);
      end if;

      --  Coalesce each free block with adjacent free blocks.
      N := Nd_Next (Head);
      while N /= Head loop
         declare
            Node : constant Natural := N;
            NU   : Natural := Nd_NU (Node);
         begin
            loop
               declare
                  Node2 : constant Natural := Node + U2B (NU);
               begin
                  exit when Nd_Stamp (Node2) /= 0;
                  NU := NU + Nd_NU (Node2);
                  Set_NU (Node, NU);
                  Set_Next (Nd_Prev (Node2), Nd_Next (Node2));
                  Set_Prev (Nd_Next (Node2), Nd_Prev (Node2));
               end;
            end loop;
            N := Nd_Next (Node);
         end;
      end loop;

      --  Re-split coalesced blocks back into the indexed free lists.
      N := Nd_Next (Head);
      while N /= Head loop
         declare
            Node : Natural := N;
            NU   : Natural := Nd_NU (Node);
         begin
            N := Nd_Next (Node);
            while NU > 128 loop
               Insert_Node (P, Node, Num_Indexes - 1);
               NU := NU - 128;
               Node := Node + U2B (128);
            end loop;
            if NU > 0 then
               declare
                  Idx : Natural := U2I (P, NU);
               begin
                  if I2U (P, Idx) /= NU then
                     Idx := Idx - 1;
                     declare
                        K : constant Natural := I2U (P, Idx);
                     begin
                        Insert_Node (P, Node + U2B (K), NU - K - 1);
                     end;
                  end if;
                  Insert_Node (P, Node, Idx);
               end;
            end if;
         end;
      end loop;
   end Glue_Free_Blocks;

   Max_Order_Limit : constant := 64;
   State_Size      : constant := 6;

   K_Exp_Escape : constant array (0 .. 15) of Natural :=
     [25, 14, 9, 7, 5, 5, 4, 4, 4, 3, 3, 3, 2, 2, 2, 2];

   function State_At (P : CPpmd7; C, Idx : Natural) return Natural is
     (Ctx_Stats (P, C) + Idx * State_Size);

   procedure Copy_State (P : CPpmd7; Dst, Src : Natural) is
   begin
      P.Base (Dst .. Dst + State_Size - 1) :=
        P.Base (Src .. Src + State_Size - 1);
   end Copy_State;

   procedure Swap_States (P : CPpmd7; A, B : Natural) is
      Tmp : constant Byte_Array := P.Base (A .. A + State_Size - 1);
   begin
      P.Base (A .. A + State_Size - 1) := P.Base (B .. B + State_Size - 1);
      P.Base (B .. B + State_Size - 1) := Tmp;
   end Swap_States;

   function Get_Mean (Summ : U32) return U32 is
     (Shift_Right (Summ + 2 ** (Period_Bits - 2), Period_Bits));

   procedure Update_Model (P : in out CPpmd7);
   function Create_Successors
     (P : in out CPpmd7; Skip : Boolean) return Natural;

   procedure Rescale (P : in out CPpmd7) is
      C        : constant Natural := P.Min_Context;
      Stats    : constant Natural := Ctx_Stats (P, C);
      S        : Natural := P.Found_State;
      Esc_Freq : Integer;
      Sum_Freq : Natural;
      Adder    : Natural;
      Num_Stat : Natural := Ctx_Num_Stats (P, C);
      I        : Natural;
   begin
      declare
         Tmp : constant Byte_Array := P.Base (S .. S + State_Size - 1);
      begin
         while S /= Stats loop
            Copy_State (P, S, S - State_Size);
            S := S - State_Size;
         end loop;
         P.Base (Stats .. Stats + State_Size - 1) := Tmp;
      end;

      S := Stats;
      Esc_Freq := Ctx_Summ_Freq (P, C) - St_Freq (P, S);
      Adder := (if P.Order_Fall /= 0 then 1 else 0);
      Set_Freq (P, S, (St_Freq (P, S) + 4 + Adder) / 2);
      Sum_Freq := St_Freq (P, S);
      I := Num_Stat - 1;
      loop
         S := S + State_Size;
         Esc_Freq := Esc_Freq - St_Freq (P, S);
         Set_Freq (P, S, (St_Freq (P, S) + Adder) / 2);
         Sum_Freq := Sum_Freq + St_Freq (P, S);
         if St_Freq (P, S) > St_Freq (P, S - State_Size) then
            declare
               S1  : Natural := S;
               Tmp : constant Byte_Array := P.Base (S .. S + State_Size - 1);
               TF  : constant Natural := St_Freq (P, S);
            begin
               loop
                  Copy_State (P, S1, S1 - State_Size);
                  S1 := S1 - State_Size;
                  exit when S1 = Stats
                    or else TF <= St_Freq (P, S1 - State_Size);
               end loop;
               P.Base (S1 .. S1 + State_Size - 1) := Tmp;
            end;
         end if;
         I := I - 1;
         exit when I = 0;
      end loop;

      if St_Freq (P, S) = 0 then
         declare
            Num0 : constant Natural := Num_Stat;
            Cnt  : Natural := 0;
            N0, N1 : Natural;
         begin
            loop
               Cnt := Cnt + 1;
               S := S - State_Size;
               exit when St_Freq (P, S) /= 0;
            end loop;
            Esc_Freq := Esc_Freq + Cnt;
            Num_Stat := Num_Stat - Cnt;
            Set_Num_Stats (P, C, Num_Stat);
            if Num_Stat = 1 then
               declare
                  Tmp_Sym  : constant Byte := St_Symbol (P, Stats);
                  Tmp_Freq : Natural := St_Freq (P, Stats);
                  Tmp_Succ : constant Natural := St_Successor (P, Stats);
                  EF       : Integer := Esc_Freq;
               begin
                  loop
                     Tmp_Freq := Tmp_Freq - Tmp_Freq / 2;
                     EF := EF / 2;
                     exit when EF <= 1;
                  end loop;
                  Free_Units (P, Stats, (Num0 + 1) / 2);
                  P.Found_State := One_State (C);
                  Set_Symbol (P, P.Found_State, Tmp_Sym);
                  Set_Freq (P, P.Found_State, Tmp_Freq);
                  Set_Successor (P, P.Found_State, Tmp_Succ);
                  return;
               end;
            end if;
            N0 := (Num0 + 1) / 2;
            N1 := (Num_Stat + 1) / 2;
            if N0 /= N1 then
               Set_Stats (P, C, Shrink_Units (P, Stats, N0, N1));
            end if;
         end;
      end if;
      Set_Summ_Freq (P, C, Sum_Freq + Esc_Freq - Esc_Freq / 2);
      P.Found_State := Ctx_Stats (P, C);
   end Rescale;

   procedure Next_Context (P : in out CPpmd7) is
      C : constant Natural := St_Successor (P, P.Found_State);
   begin
      if P.Order_Fall = 0 and then C > P.Text then
         P.Min_Context := C;
         P.Max_Context := C;
      else
         Update_Model (P);
      end if;
   end Next_Context;

   procedure Update1 (P : in out CPpmd7) is
      S : Natural := P.Found_State;
   begin
      Set_Freq (P, S, St_Freq (P, S) + 4);
      Set_Summ_Freq (P, P.Min_Context, Ctx_Summ_Freq (P, P.Min_Context) + 4);
      if St_Freq (P, S) > St_Freq (P, S - State_Size) then
         Swap_States (P, S, S - State_Size);
         S := S - State_Size;
         P.Found_State := S;
         if St_Freq (P, S) > Max_Freq then
            Rescale (P);
         end if;
      end if;
      Next_Context (P);
   end Update1;

   procedure Update1_0 (P : in out CPpmd7) is
      S : constant Natural := P.Found_State;
   begin
      P.Prev_Success :=
        (if 2 * St_Freq (P, S) > Ctx_Summ_Freq (P, P.Min_Context)
         then 1 else 0);
      P.Run_Length := P.Run_Length + P.Prev_Success;
      Set_Summ_Freq (P, P.Min_Context, Ctx_Summ_Freq (P, P.Min_Context) + 4);
      Set_Freq (P, S, St_Freq (P, S) + 4);
      if St_Freq (P, S) > Max_Freq then
         Rescale (P);
      end if;
      Next_Context (P);
   end Update1_0;

   procedure Update_Bin (P : in out CPpmd7) is
      S : constant Natural := P.Found_State;
   begin
      Set_Freq (P, S, St_Freq (P, S) + (if St_Freq (P, S) < 128 then 1 else 0));
      P.Prev_Success := 1;
      P.Run_Length := P.Run_Length + 1;
      Next_Context (P);
   end Update_Bin;

   procedure Update2 (P : in out CPpmd7) is
      S : constant Natural := P.Found_State;
   begin
      Set_Freq (P, S, St_Freq (P, S) + 4);
      Set_Summ_Freq (P, P.Min_Context, Ctx_Summ_Freq (P, P.Min_Context) + 4);
      if St_Freq (P, S) > Max_Freq then
         Rescale (P);
      end if;
      P.Run_Length := P.Init_RL;
      Update_Model (P);
   end Update2;

   function Create_Successors
     (P : in out CPpmd7; Skip : Boolean) return Natural
   is
      C         : Natural := P.Min_Context;
      Up_Branch : constant Natural := St_Successor (P, P.Found_State);
      Ps        : array (0 .. Max_Order_Limit - 1) of Natural;
      Num_Ps    : Natural := 0;
      Up_Sym    : Byte;
      Up_Freq   : Natural;
      Up_Succ   : Natural;
   begin
      if not Skip then
         Ps (Num_Ps) := P.Found_State;
         Num_Ps := Num_Ps + 1;
      end if;
      while Ctx_Suffix (P, C) /= 0 loop
         declare
            S    : Natural;
            Succ : Natural;
         begin
            C := Ctx_Suffix (P, C);
            if Ctx_Num_Stats (P, C) /= 1 then
               S := Ctx_Stats (P, C);
               while St_Symbol (P, S) /= St_Symbol (P, P.Found_State) loop
                  S := S + State_Size;
               end loop;
            else
               S := One_State (C);
            end if;
            Succ := St_Successor (P, S);
            if Succ /= Up_Branch then
               C := Succ;
               if Num_Ps = 0 then
                  return C;
               end if;
               exit;
            end if;
            Ps (Num_Ps) := S;
            Num_Ps := Num_Ps + 1;
         end;
      end loop;

      Up_Sym := P.Base (Up_Branch);
      Up_Succ := Up_Branch + 1;
      if Ctx_Num_Stats (P, C) = 1 then
         Up_Freq := St_Freq (P, One_State (C));
      else
         declare
            S      : Natural := Ctx_Stats (P, C);
            CF, S0 : Natural;
         begin
            while St_Symbol (P, S) /= Up_Sym loop
               S := S + State_Size;
            end loop;
            CF := St_Freq (P, S) - 1;
            S0 := Ctx_Summ_Freq (P, C) - Ctx_Num_Stats (P, C) - CF;
            if 2 * CF <= S0 then
               Up_Freq := 1 + (if 5 * CF > S0 then 1 else 0);
            else
               Up_Freq := 1 + (2 * CF + 3 * S0 - 1) / (2 * S0);
            end if;
         end;
      end if;

      loop
         declare
            C1 : Natural;
         begin
            if P.Hi_Unit /= P.Lo_Unit then
               P.Hi_Unit := P.Hi_Unit - Unit_Size;
               C1 := P.Hi_Unit;
            elsif P.Free_List (0) /= 0 then
               C1 := Remove_Node (P, 0);
            else
               C1 := Alloc_Units_Rare (P, 0);
               if C1 = 0 then
                  return 0;
               end if;
            end if;
            Set_Num_Stats (P, C1, 1);
            Set_Symbol (P, One_State (C1), Up_Sym);
            Set_Freq (P, One_State (C1), Up_Freq);
            Set_Successor (P, One_State (C1), Up_Succ);
            Set_Suffix (P, C1, C);
            Num_Ps := Num_Ps - 1;
            Set_Successor (P, Ps (Num_Ps), C1);
            C := C1;
         end;
         exit when Num_Ps = 0;
      end loop;
      return C;
   end Create_Successors;

   procedure Update_Model (P : in out CPpmd7) is
      F_Successor : Natural := St_Successor (P, P.Found_State);
      Successor   : Natural;
      C           : Natural;
      F_Freq      : constant Natural := St_Freq (P, P.Found_State);
      F_Symbol    : constant Byte := St_Symbol (P, P.Found_State);
      NS, S0      : Natural;
   begin
      if F_Freq < Max_Freq / 4 and then Ctx_Suffix (P, P.Min_Context) /= 0 then
         C := Ctx_Suffix (P, P.Min_Context);
         if Ctx_Num_Stats (P, C) = 1 then
            declare
               S : constant Natural := One_State (C);
            begin
               if St_Freq (P, S) < 32 then
                  Set_Freq (P, S, St_Freq (P, S) + 1);
               end if;
            end;
         else
            declare
               S : Natural := Ctx_Stats (P, C);
            begin
               if St_Symbol (P, S) /= F_Symbol then
                  loop
                     S := S + State_Size;
                     exit when St_Symbol (P, S) = F_Symbol;
                  end loop;
                  if St_Freq (P, S) >= St_Freq (P, S - State_Size) then
                     Swap_States (P, S, S - State_Size);
                     S := S - State_Size;
                  end if;
               end if;
               if St_Freq (P, S) < Max_Freq - 9 then
                  Set_Freq (P, S, St_Freq (P, S) + 2);
                  Set_Summ_Freq (P, C, Ctx_Summ_Freq (P, C) + 2);
               end if;
            end;
         end if;
      end if;

      if P.Order_Fall = 0 then
         declare
            CS : constant Natural := Create_Successors (P, True);
         begin
            if CS = 0 then
               Restart_Model (P);
               return;
            end if;
            P.Min_Context := CS;
            P.Max_Context := CS;
            Set_Successor (P, P.Found_State, CS);
            return;
         end;
      end if;

      P.Base (P.Text) := F_Symbol;
      P.Text := P.Text + 1;
      Successor := P.Text;
      if P.Text >= P.Units_Start then
         Restart_Model (P);
         return;
      end if;

      if F_Successor /= 0 then
         if F_Successor < P.Units_Start then
            declare
               CS : constant Natural := Create_Successors (P, False);
            begin
               if CS = 0 then
                  Restart_Model (P);
                  return;
               end if;
               F_Successor := CS;
            end;
         end if;
         P.Order_Fall := P.Order_Fall - 1;
         if P.Order_Fall = 0 then
            Successor := F_Successor;
            if P.Max_Context /= P.Min_Context then
               P.Text := P.Text - 1;
            end if;
         end if;
      else
         Set_Successor (P, P.Found_State, Successor);
         F_Successor := P.Min_Context;
      end if;

      NS := Ctx_Num_Stats (P, P.Min_Context);
      S0 := Ctx_Summ_Freq (P, P.Min_Context) - NS - (F_Freq - 1);
      C := P.Max_Context;
      while C /= P.Min_Context loop
         declare
            NS1    : constant Natural := Ctx_Num_Stats (P, C);
            CF, SF : Natural;
         begin
            if NS1 /= 1 then
               if NS1 mod 2 = 0 then
                  declare
                     Old_NU : constant Natural := NS1 / 2;
                     I0     : constant Natural := U2I (P, Old_NU);
                  begin
                     if I0 /= U2I (P, Old_NU + 1) then
                        declare
                           Ptr : constant Natural := Alloc_Units (P, I0 + 1);
                        begin
                           if Ptr = 0 then
                              Restart_Model (P);
                              return;
                           end if;
                           P.Base (Ptr .. Ptr + U2B (Old_NU) - 1) :=
                             P.Base (Ctx_Stats (P, C)
                                     .. Ctx_Stats (P, C) + U2B (Old_NU) - 1);
                           Insert_Node (P, Ctx_Stats (P, C), I0);
                           Set_Stats (P, C, Ptr);
                        end;
                     end if;
                  end;
               end if;
               Set_Summ_Freq
                 (P, C,
                  Ctx_Summ_Freq (P, C)
                  + (if 2 * NS1 < NS then 1 else 0)
                  + 2 * (if 4 * NS1 <= NS
                           and then Ctx_Summ_Freq (P, C) <= 8 * NS1
                         then 1 else 0));
            else
               declare
                  Ns_Ptr : constant Natural := Alloc_Units (P, 0);
                  Fr     : Natural;
               begin
                  if Ns_Ptr = 0 then
                     Restart_Model (P);
                     return;
                  end if;
                  Copy_State (P, Ns_Ptr, One_State (C));
                  Set_Stats (P, C, Ns_Ptr);
                  Fr := St_Freq (P, Ns_Ptr);
                  if Fr < Max_Freq / 4 - 1 then
                     Fr := Fr + Fr;
                  else
                     Fr := Max_Freq - 4;
                  end if;
                  Set_Freq (P, Ns_Ptr, Fr);
                  Set_Summ_Freq
                    (P, C, Fr + P.Init_Esc + (if NS > 3 then 1 else 0));
               end;
            end if;

            CF := 2 * F_Freq * (Ctx_Summ_Freq (P, C) + 6);
            SF := S0 + Ctx_Summ_Freq (P, C);
            if CF < 6 * SF then
               CF := 1 + (if CF > SF then 1 else 0)
                 + (if CF >= 4 * SF then 1 else 0);
               Set_Summ_Freq (P, C, Ctx_Summ_Freq (P, C) + 3);
            else
               CF := 4 + (if CF >= 9 * SF then 1 else 0)
                 + (if CF >= 12 * SF then 1 else 0)
                 + (if CF >= 15 * SF then 1 else 0);
               Set_Summ_Freq (P, C, Ctx_Summ_Freq (P, C) + CF);
            end if;
            declare
               New_S : constant Natural := State_At (P, C, NS1);
            begin
               Set_Successor (P, New_S, Successor);
               Set_Symbol (P, New_S, F_Symbol);
               Set_Freq (P, New_S, CF);
               Set_Num_Stats (P, C, NS1 + 1);
            end;
         end;
         C := Ctx_Suffix (P, C);
      end loop;
      P.Max_Context := F_Successor;
      P.Min_Context := F_Successor;
   end Update_Model;

   procedure Make_Esc_Freq
     (P          : in out CPpmd7;
      Num_Masked : Natural;
      Esc_Freq   : out U32;
      See_I      : out Natural;
      See_K      : out Natural;
      Dummy      : out Boolean)
   is
      C  : constant Natural := P.Min_Context;
      NS : constant Natural := Ctx_Num_Stats (P, C);
      Non_Masked : constant Natural := NS - Num_Masked;
   begin
      if NS /= 256 then
         Dummy := False;
         See_I := P.NS2Indx (Non_Masked - 1);
         See_K :=
           (if Non_Masked < Ctx_Num_Stats (P, Ctx_Suffix (P, C)) - NS
            then 1 else 0)
           + 2 * (if Ctx_Summ_Freq (P, C) < 11 * NS then 1 else 0)
           + 4 * (if Num_Masked > Non_Masked then 1 else 0)
           + P.Hi_Bits_Flag;
         declare
            Sm : constant U32 := U32 (P.See (See_I, See_K).Summ);
            R  : constant U32 :=
              Shift_Right (Sm, Natural (P.See (See_I, See_K).Shift));
         begin
            P.See (See_I, See_K).Summ := U16 (Sm - R);
            Esc_Freq := R + (if R = 0 then 1 else 0);
         end;
      else
         Dummy := True;
         See_I := 0;
         See_K := 0;
         Esc_Freq := 1;
      end if;
   end Make_Esc_Freq;

   procedure See_Update (P : in out CPpmd7; I, K : Natural; Dummy : Boolean) is
   begin
      if Dummy then
         return;
      end if;
      declare
         S : See_Type renames P.See (I, K);
      begin
         if S.Shift < Period_Bits then
            S.Count := S.Count - 1;
            if S.Count = 0 then
               S.Summ := Shift_Left (S.Summ, 1);
               S.Count := Byte (3 * 2 ** Natural (S.Shift));
               S.Shift := S.Shift + 1;
            end if;
         end if;
      end;
   end See_Update;

   ----------------------------------------------------------------------
   --  7z range decoder.
   ----------------------------------------------------------------------

   function Read_Byte (RD : in out Range_Dec) return U32 is
   begin
      if RD.In_Pos < RD.In_Last then
         declare
            B : constant Byte := RD.In_Buf (RD.In_Pos);
         begin
            RD.In_Pos := RD.In_Pos + 1;
            return U32 (B);
         end;
      else
         RD.Overrun := True;
         return 0;
      end if;
   end Read_Byte;

   function Range_Init (RD : in out Range_Dec) return Boolean is
   begin
      RD.Code := 0;
      RD.Rng := 16#FFFF_FFFF#;
      if Read_Byte (RD) /= 0 then
         return False;
      end if;
      for I in 1 .. 4 loop
         declare
            B : constant U32 := Read_Byte (RD);
         begin
            RD.Code := Shift_Left (RD.Code, 8) or B;
         end;
      end loop;
      return RD.Code < 16#FFFF_FFFF#;
   end Range_Init;

   procedure Range_Normalize (RD : in out Range_Dec) is
   begin
      if RD.Rng < Top_Value then
         declare
            B : constant U32 := Read_Byte (RD);
         begin
            RD.Code := Shift_Left (RD.Code, 8) or B;
         end;
         RD.Rng := Shift_Left (RD.Rng, 8);
         if RD.Rng < Top_Value then
            declare
            B : constant U32 := Read_Byte (RD);
         begin
            RD.Code := Shift_Left (RD.Code, 8) or B;
         end;
            RD.Rng := Shift_Left (RD.Rng, 8);
         end if;
      end if;
   end Range_Normalize;

   function Get_Threshold (RD : in out Range_Dec; Total : U32) return U32 is
   begin
      RD.Rng := RD.Rng / Total;
      return RD.Code / RD.Rng;
   end Get_Threshold;

   procedure Range_Decode (RD : in out Range_Dec; Start, Size : U32) is
   begin
      RD.Code := RD.Code - Start * RD.Rng;
      RD.Rng := RD.Rng * Size;
      Range_Normalize (RD);
   end Range_Decode;

   function Range_Decode_Bit (RD : in out Range_Dec; Size0 : U32) return U32 is
      New_Bound : constant U32 := Shift_Right (RD.Rng, 14) * Size0;
      Sym       : U32;
   begin
      if RD.Code < New_Bound then
         Sym := 0;
         RD.Rng := New_Bound;
      else
         Sym := 1;
         RD.Code := RD.Code - New_Bound;
         RD.Rng := RD.Rng - New_Bound;
      end if;
      Range_Normalize (RD);
      return Sym;
   end Range_Decode_Bit;

   ----------------------------------------------------------------------
   --  Decode one symbol (faithful to Ppmd7_DecodeSymbol). Returns the
   --  byte value, or -1 / -2 on error.
   ----------------------------------------------------------------------

   function Decode_Symbol (P : in out CPpmd7; RD : in out Range_Dec)
      return Integer
   is
      Mask : array (0 .. 255) of Boolean := [others => True];
      Ps   : array (0 .. 255) of Natural;
      C    : Natural := P.Min_Context;
   begin
      if Ctx_Num_Stats (P, C) /= 1 then
         declare
            S      : Natural := Ctx_Stats (P, C);
            Summ_F : constant U32 := U32 (Ctx_Summ_Freq (P, C));
            Thresh : constant U32 := Get_Threshold (RD, Summ_F);
            Low    : U32 := 0;
            NS     : constant Natural := Ctx_Num_Stats (P, C);
         begin
            if Thresh >= Summ_F then
               return -2;
            end if;
            if Thresh < U32 (St_Freq (P, S)) then
               Range_Decode (RD, 0, U32 (St_Freq (P, S)));
               P.Found_State := S;
               return R : constant Integer := Integer (St_Symbol (P, S)) do
                  Update1_0 (P);
               end return;
            end if;
            P.Prev_Success := 0;
            Low := U32 (St_Freq (P, S));
            for Idx in 1 .. NS - 1 loop
               S := S + State_Size;
               if Thresh < Low + U32 (St_Freq (P, S)) then
                  Range_Decode (RD, Low, U32 (St_Freq (P, S)));
                  P.Found_State := S;
                  return R : constant Integer := Integer (St_Symbol (P, S)) do
                     Update1 (P);
                  end return;
               end if;
               Low := Low + U32 (St_Freq (P, S));
            end loop;
            P.Hi_Bits_Flag :=
              P.HB2Flag (Natural (St_Symbol (P, P.Found_State)));
            Range_Decode (RD, Low, Summ_F - Low);
            for Idx in 0 .. NS - 1 loop
               Mask (Natural (St_Symbol (P, State_At (P, C, Idx)))) := False;
            end loop;
         end;
      else
         declare
            One       : constant Natural := One_State (C);
            Row       : constant Natural := St_Freq (P, One) - 1;
            Suffix_NS : constant Natural :=
              Ctx_Num_Stats (P, Ctx_Suffix (P, C));
            Col       : Natural;
            Prob      : U16;
         begin
            P.Hi_Bits_Flag :=
              P.HB2Flag (Natural (St_Symbol (P, P.Found_State)));
            Col := P.Prev_Success
              + P.NS2BSIndx (Suffix_NS - 1)
              + P.Hi_Bits_Flag
              + 2 * P.HB2Flag (Natural (St_Symbol (P, One)))
              + (if P.Run_Length < 0 then 16#20# else 0);
            Prob := P.Bin_Summ (Row, Col);
            if Range_Decode_Bit (RD, U32 (Prob)) = 0 then
               P.Bin_Summ (Row, Col) :=
                 U16 (U32 (Prob) + 2 ** Period_Bits - Get_Mean (U32 (Prob)));
               P.Found_State := One;
               return R : constant Integer := Integer (St_Symbol (P, One)) do
                  Update_Bin (P);
               end return;
            end if;
            P.Bin_Summ (Row, Col) := U16 (U32 (Prob) - Get_Mean (U32 (Prob)));
            P.Init_Esc :=
              K_Exp_Escape
                (Natural (Shift_Right (U32 (P.Bin_Summ (Row, Col)), 10)));
            Mask (Natural (St_Symbol (P, One))) := False;
            P.Prev_Success := 0;
         end;
      end if;

      loop
         declare
            Num_Masked : constant Natural := Ctx_Num_Stats (P, P.Min_Context);
            Hi_Cnt   : U32 := 0;
            Num      : Natural;
            Kk       : Natural := 0;
            S        : Natural;
            Esc_Freq : U32;
            Freq_Sum : U32;
            Count    : U32;
            See_I, See_K : Natural;
            See_Dummy : Boolean;
         begin
            loop
               P.Order_Fall := P.Order_Fall + 1;
               if Ctx_Suffix (P, P.Min_Context) = 0 then
                  return -1;
               end if;
               P.Min_Context := Ctx_Suffix (P, P.Min_Context);
               exit when Ctx_Num_Stats (P, P.Min_Context) /= Num_Masked;
            end loop;

            C := P.Min_Context;
            Num := Ctx_Num_Stats (P, C) - Num_Masked;
            S := Ctx_Stats (P, C);
            loop
               if Mask (Natural (St_Symbol (P, S))) then
                  Hi_Cnt := Hi_Cnt + U32 (St_Freq (P, S));
                  Ps (Kk) := S;
                  Kk := Kk + 1;
               end if;
               S := S + State_Size;
               exit when Kk = Num;
            end loop;

            Make_Esc_Freq (P, Num_Masked, Esc_Freq, See_I, See_K, See_Dummy);
            Freq_Sum := Esc_Freq + Hi_Cnt;
            Count := Get_Threshold (RD, Freq_Sum);

            if Count < Hi_Cnt then
               declare
                  Cum : U32 := 0;
                  Idx : Natural := 0;
               begin
                  loop
                     Cum := Cum + U32 (St_Freq (P, Ps (Idx)));
                     exit when Cum > Count;
                     Idx := Idx + 1;
                  end loop;
                  S := Ps (Idx);
                  Range_Decode (RD, Cum - U32 (St_Freq (P, S)),
                                U32 (St_Freq (P, S)));
                  See_Update (P, See_I, See_K, See_Dummy);
                  P.Found_State := S;
                  return R : constant Integer := Integer (St_Symbol (P, S)) do
                     Update2 (P);
                  end return;
               end;
            end if;
            if Count >= Freq_Sum then
               return -2;
            end if;
            Range_Decode (RD, Hi_Cnt, Freq_Sum - Hi_Cnt);
            if not See_Dummy then
               P.See (See_I, See_K).Summ :=
                 U16 ((U32 (P.See (See_I, See_K).Summ) + Freq_Sum)
                      and 16#FFFF#);
            end if;
            for J in 0 .. Num - 1 loop
               Mask (Natural (St_Symbol (P, Ps (J)))) := False;
            end loop;
         end;
      end loop;
   end Decode_Symbol;

   ----------------------------------------------------------------------
   --  7z range encoder + symbol encoder (mirror of the decoder).
   ----------------------------------------------------------------------

   procedure Append_Byte (RE : in out Range_Enc; B : Byte) is
   begin
      if RE.Out_Len >= RE.Out_Buf'Length then
         declare
            New_Buf : constant Byte_Array_Access :=
              new Byte_Array'(0 .. RE.Out_Buf'Length * 2 - 1 => 0);
         begin
            New_Buf (0 .. RE.Out_Len - 1) := RE.Out_Buf (0 .. RE.Out_Len - 1);
            Free_Pool (RE.Out_Buf);
            RE.Out_Buf := New_Buf;
         end;
      end if;
      RE.Out_Buf (RE.Out_Len) := B;
      RE.Out_Len := RE.Out_Len + 1;
   end Append_Byte;

   procedure Enc_Shift_Low (RE : in out Range_Enc) is
   begin
      if (RE.Low and 16#FFFF_FFFF#) < 16#FF00_0000#
        or else Shift_Right (RE.Low, 32) /= 0
      then
         declare
            Temp  : Byte := RE.Cache;
            Carry : constant Byte := Byte (Shift_Right (RE.Low, 32) and 16#FF#);
         begin
            loop
               Append_Byte (RE, Temp + Carry);
               Temp := 16#FF#;
               RE.Cache_Size := RE.Cache_Size - 1;
               exit when RE.Cache_Size = 0;
            end loop;
            RE.Cache := Byte (Shift_Right (RE.Low, 24) and 16#FF#);
         end;
      end if;
      RE.Cache_Size := RE.Cache_Size + 1;
      --  Low := (UInt32) Low << 8: truncate to 32 bits, so the high byte
      --  (already saved in Cache) is dropped and Low>>32 is only the carry.
      RE.Low := Shift_Left (RE.Low and 16#FFFF_FFFF#, 8) and 16#FFFF_FFFF#;
   end Enc_Shift_Low;

   procedure Enc_Encode (RE : in out Range_Enc; Start, Size, Total : U32) is
   begin
      RE.Rng := RE.Rng / Total;
      RE.Low := RE.Low + U64 (Start) * U64 (RE.Rng);
      RE.Rng := RE.Rng * Size;
      while RE.Rng < Top_Value loop
         RE.Rng := Shift_Left (RE.Rng, 8);
         Enc_Shift_Low (RE);
      end loop;
   end Enc_Encode;

   procedure Enc_Encode_Bit (RE : in out Range_Enc; Size0 : U32; Bit : U32) is
      New_Bound : constant U32 := Shift_Right (RE.Rng, 14) * Size0;
   begin
      if Bit = 0 then
         RE.Rng := New_Bound;
      else
         RE.Low := RE.Low + U64 (New_Bound);
         RE.Rng := RE.Rng - New_Bound;
      end if;
      while RE.Rng < Top_Value loop
         RE.Rng := Shift_Left (RE.Rng, 8);
         Enc_Shift_Low (RE);
      end loop;
   end Enc_Encode_Bit;

   procedure Enc_Flush (RE : in out Range_Enc) is
   begin
      for I in 1 .. 5 loop
         Enc_Shift_Low (RE);
      end loop;
   end Enc_Flush;

   --  Encode one known symbol; updates the model identically to decode.
   procedure Encode_Symbol
     (P : in out CPpmd7; RE : in out Range_Enc; Symbol : Byte)
   is
      Mask : array (0 .. 255) of Boolean := [others => True];
      Ps   : array (0 .. 255) of Natural;
      C    : Natural := P.Min_Context;
   begin
      if Ctx_Num_Stats (P, C) /= 1 then
         declare
            S      : Natural := Ctx_Stats (P, C);
            Summ_F : constant U32 := U32 (Ctx_Summ_Freq (P, C));
            Low    : U32 := 0;
            NS     : constant Natural := Ctx_Num_Stats (P, C);
         begin
            if St_Symbol (P, S) = Symbol then
               Enc_Encode (RE, 0, U32 (St_Freq (P, S)), Summ_F);
               P.Found_State := S;
               Update1_0 (P);
               return;
            end if;
            P.Prev_Success := 0;
            Low := U32 (St_Freq (P, S));
            for Idx in 1 .. NS - 1 loop
               S := S + State_Size;
               if St_Symbol (P, S) = Symbol then
                  Enc_Encode (RE, Low, U32 (St_Freq (P, S)), Summ_F);
                  P.Found_State := S;
                  Update1 (P);
                  return;
               end if;
               Low := Low + U32 (St_Freq (P, S));
            end loop;
            P.Hi_Bits_Flag :=
              P.HB2Flag (Natural (St_Symbol (P, P.Found_State)));
            Enc_Encode (RE, Low, Summ_F - Low, Summ_F);
            for Idx in 0 .. NS - 1 loop
               Mask (Natural (St_Symbol (P, State_At (P, C, Idx)))) := False;
            end loop;
         end;
      else
         declare
            One       : constant Natural := One_State (C);
            Row       : constant Natural := St_Freq (P, One) - 1;
            Suffix_NS : constant Natural :=
              Ctx_Num_Stats (P, Ctx_Suffix (P, C));
            Col       : Natural;
            Prob      : U16;
         begin
            P.Hi_Bits_Flag :=
              P.HB2Flag (Natural (St_Symbol (P, P.Found_State)));
            Col := P.Prev_Success
              + P.NS2BSIndx (Suffix_NS - 1)
              + P.Hi_Bits_Flag
              + 2 * P.HB2Flag (Natural (St_Symbol (P, One)))
              + (if P.Run_Length < 0 then 16#20# else 0);
            Prob := P.Bin_Summ (Row, Col);
            if St_Symbol (P, One) = Symbol then
               Enc_Encode_Bit (RE, U32 (Prob), 0);
               P.Bin_Summ (Row, Col) :=
                 U16 (U32 (Prob) + 2 ** Period_Bits - Get_Mean (U32 (Prob)));
               P.Found_State := One;
               Update_Bin (P);
               return;
            end if;
            Enc_Encode_Bit (RE, U32 (Prob), 1);
            P.Bin_Summ (Row, Col) := U16 (U32 (Prob) - Get_Mean (U32 (Prob)));
            P.Init_Esc :=
              K_Exp_Escape
                (Natural (Shift_Right (U32 (P.Bin_Summ (Row, Col)), 10)));
            Mask (Natural (St_Symbol (P, One))) := False;
            P.Prev_Success := 0;
         end;
      end if;

      loop
         declare
            Num_Masked : constant Natural := Ctx_Num_Stats (P, P.Min_Context);
            Hi_Cnt   : U32 := 0;
            Num      : Natural;
            Kk       : Natural := 0;
            S        : Natural;
            Esc_Freq : U32;
            Freq_Sum : U32;
            See_I, See_K : Natural;
            See_Dummy : Boolean;
            Found_Idx : Integer := -1;
            Cum_Low  : U32 := 0;
         begin
            loop
               P.Order_Fall := P.Order_Fall + 1;
               P.Min_Context := Ctx_Suffix (P, P.Min_Context);
               exit when Ctx_Num_Stats (P, P.Min_Context) /= Num_Masked;
            end loop;

            C := P.Min_Context;
            Num := Ctx_Num_Stats (P, C) - Num_Masked;
            S := Ctx_Stats (P, C);
            loop
               if Mask (Natural (St_Symbol (P, S))) then
                  Hi_Cnt := Hi_Cnt + U32 (St_Freq (P, S));
                  Ps (Kk) := S;
                  Kk := Kk + 1;
               end if;
               S := S + State_Size;
               exit when Kk = Num;
            end loop;

            Make_Esc_Freq (P, Num_Masked, Esc_Freq, See_I, See_K, See_Dummy);
            Freq_Sum := Esc_Freq + Hi_Cnt;

            --  Cumulative low of the target symbol among the collected states.
            for J in 0 .. Num - 1 loop
               if St_Symbol (P, Ps (J)) = Symbol then
                  Found_Idx := J;
                  exit;
               end if;
               Cum_Low := Cum_Low + U32 (St_Freq (P, Ps (J)));
            end loop;

            if Found_Idx >= 0 then
               S := Ps (Found_Idx);
               Enc_Encode (RE, Cum_Low, U32 (St_Freq (P, S)), Freq_Sum);
               See_Update (P, See_I, See_K, See_Dummy);
               P.Found_State := S;
               Update2 (P);
               return;
            end if;
            Enc_Encode (RE, Hi_Cnt, Freq_Sum - Hi_Cnt, Freq_Sum);
            if not See_Dummy then
               P.See (See_I, See_K).Summ :=
                 U16 ((U32 (P.See (See_I, See_K).Summ) + Freq_Sum)
                      and 16#FFFF#);
            end if;
            for J in 0 .. Num - 1 loop
               Mask (Natural (St_Symbol (P, Ps (J)))) := False;
            end loop;
         end;
      end loop;
   end Encode_Symbol;

   procedure Setup_Pool (P : in out CPpmd7; Mem_Size : U32) is
   begin
      P.Align_Off := 4 - Natural (Mem_Size and 3);
      P.Size := Mem_Size;
      P.Base :=
        new Byte_Array'
          (0 .. P.Align_Off + Natural (Mem_Size) + Unit_Size - 1 => 0);
      Construct (P);
   end Setup_Pool;

   ----------------------------------------------------------------------
   --  Top-level entry points.
   ----------------------------------------------------------------------

   function Compress
     (Data     : Byte_Array;
      Order    : Positive;
      Mem_Size : Interfaces.Unsigned_32) return Byte_Array
   is
      P  : CPpmd7;
      RE : Range_Enc;
   begin
      Setup_Pool (P, Mem_Size);
      Init (P, Order);
      RE.Out_Buf :=
        new Byte_Array'(0 .. Natural'Max (Data'Length, 16) + 16 - 1 => 0);
      RE.Out_Len := 0;
      for I in Data'Range loop
         Encode_Symbol (P, RE, Data (I));
      end loop;
      Enc_Flush (RE);
      return Result : constant Byte_Array := RE.Out_Buf (0 .. RE.Out_Len - 1) do
         Free_Pool (P.Base);
         Free_Pool (RE.Out_Buf);
      end return;
   end Compress;

   function Decompress
     (Data     : Byte_Array;
      Out_Size : Natural;
      Order    : Positive;
      Mem_Size : Interfaces.Unsigned_32;
      Status   : out Status_Code) return Byte_Array
   is
      P       : CPpmd7;
      RD      : Range_Dec;
      In_Copy : Byte_Array_Access :=
        new Byte_Array'(0 .. Natural'Max (Data'Length, 1) - 1 => 0);
      Out_Buf : Byte_Array (0 .. Natural'Max (Out_Size, 1) - 1) :=
        [others => 0];
   begin
      if Data'Length > 0 then
         In_Copy (0 .. Data'Length - 1) := Data;
      end if;
      Setup_Pool (P, Mem_Size);
      Init (P, Order);

      RD.In_Buf := In_Copy;
      RD.In_Pos := 0;
      RD.In_Last := Data'Length;  --  count of valid input bytes
      if not Range_Init (RD) then
         Free_Pool (P.Base);
         Free_Pool (In_Copy);
         Status := Invalid_Block_Type;
         return [1 .. Out_Size => 0];
      end if;

      for I in 0 .. Out_Size - 1 loop
         declare
            Sym : constant Integer := Decode_Symbol (P, RD);
         begin
            if Sym < 0 then
               Free_Pool (P.Base);
               Free_Pool (In_Copy);
               Status := Invalid_Block_Type;
               return [1 .. Out_Size => 0];
            end if;
            Out_Buf (I) := Byte (Sym);
         end;
      end loop;

      Free_Pool (P.Base);
      Free_Pool (In_Copy);
      Status := Ok;
      return Out_Buf (0 .. Out_Size - 1);
   end Decompress;

end Zlib.PPMd7;
