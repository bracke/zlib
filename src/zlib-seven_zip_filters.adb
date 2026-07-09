with Ada.Containers.Vectors;
with Interfaces; use Interfaces;

package body Zlib.Seven_Zip_Filters is

   --  All converters operate on a normalized 0-based working copy of the
   --  input. The implicit instruction-pointer origin (ip) is 0.

   procedure Convert_IA64 (B : in out Byte_Array; Encoding : Boolean);
   procedure Convert_X86 (B : in out Byte_Array; Encoding : Boolean);
   procedure Convert_ARM64 (B : in out Byte_Array; Encoding : Boolean);
   procedure Convert_RISCV (B : in out Byte_Array; Encoding : Boolean);
   --  Forward declarations; bodies below.

   package Byte_Vectors is new Ada.Containers.Vectors
     (Index_Type => Natural, Element_Type => Byte);

   function To_Byte_Array (Data : Byte_Vectors.Vector) return Byte_Array is
      Result : Byte_Array (1 .. Natural (Data.Length));
      J      : Natural := Result'First;
   begin
      for B of Data loop
         Result (J) := B;
         J := J + 1;
      end loop;
      return Result;
   end To_Byte_Array;

   --------------------
   -- Branch_Convert --
   --------------------

   function Branch_Convert
     (Arch     : Branch_Arch;
      Data     : Byte_Array;
      Encoding : Boolean) return Byte_Array
   is
      Len : constant Natural := Data'Length;
      B   : Byte_Array (0 .. (if Len = 0 then 0 else Len - 1));
      --  Working copy, 0-based. (When Len = 0 the array has bounds 0 .. 0
      --  but is never indexed; the result slice below is empty.)
   begin
      if Len = 0 then
         return Data;
      end if;

      --  Copy input into the 0-based working buffer.
      for K in 0 .. Len - 1 loop
         B (K) := Data (Data'First + K);
      end loop;

      case Arch is

         when X86 =>
            Convert_X86 (B, Encoding);

         when ARM64 =>
            Convert_ARM64 (B, Encoding);

         when RISCV =>
            Convert_RISCV (B, Encoding);

         when ARM =>
            --  4-byte BL (0xEB) instructions, target << 2, ip += 8.
            if Len >= 4 then
               declare
                  I : Natural := 0;
               begin
                  while I <= Len - 4 loop
                     if B (I + 3) = 16#EB# then
                        declare
                           Src : Unsigned_32 :=
                             Shift_Left (Unsigned_32 (B (I + 2)), 16)
                             or Shift_Left (Unsigned_32 (B (I + 1)), 8)
                             or Unsigned_32 (B (I));
                           Dst : Unsigned_32;
                           Cur : constant Unsigned_32 :=
                             8 + Unsigned_32 (I);
                        begin
                           Src := Shift_Left (Src, 2);
                           Dst := (if Encoding then Cur + Src
                                   else Src - Cur);
                           Dst := Shift_Right (Dst, 2);
                           B (I + 2) :=
                             Byte (Shift_Right (Dst, 16) and 16#FF#);
                           B (I + 1) :=
                             Byte (Shift_Right (Dst, 8) and 16#FF#);
                           B (I)     := Byte (Dst and 16#FF#);
                        end;
                     end if;
                     I := I + 4;
                  end loop;
               end;
            end if;

         when ARMT =>
            --  Thumb BL pair (F0.. / F8..), 2-byte step, target << 1, ip += 4.
            if Len >= 4 then
               declare
                  I : Natural := 0;
               begin
                  while I <= Len - 4 loop
                     if (B (I + 1) and 16#F8#) = 16#F0#
                       and then (B (I + 3) and 16#F8#) = 16#F8#
                     then
                        declare
                           Src : Unsigned_32 :=
                             Shift_Left
                               (Unsigned_32 (B (I + 1)) and 16#7#, 19)
                             or Shift_Left (Unsigned_32 (B (I)), 11)
                             or Shift_Left
                               (Unsigned_32 (B (I + 3)) and 16#7#, 8)
                             or Unsigned_32 (B (I + 2));
                           Dst : Unsigned_32;
                           Cur : constant Unsigned_32 :=
                             4 + Unsigned_32 (I);
                        begin
                           Src := Shift_Left (Src, 1);
                           Dst := (if Encoding then Cur + Src
                                   else Src - Cur);
                           Dst := Shift_Right (Dst, 1);
                           B (I + 1) :=
                             Byte (16#F0#
                               or (Shift_Right (Dst, 19) and 16#7#));
                           B (I)     :=
                             Byte (Shift_Right (Dst, 11) and 16#FF#);
                           B (I + 3) :=
                             Byte (16#F8#
                               or (Shift_Right (Dst, 8) and 16#7#));
                           B (I + 2) := Byte (Dst and 16#FF#);
                        end;
                        I := I + 2;
                     end if;
                     I := I + 2;
                  end loop;
               end;
            end if;

         when PPC =>
            --  Branch (0x48.. with low 2 bits 01), big-endian, ip += 0.
            if Len >= 4 then
               declare
                  I : Natural := 0;
               begin
                  while I <= Len - 4 loop
                     if (B (I) and 16#FC#) = 16#48#
                       and then (B (I + 3) and 16#3#) = 16#1#
                     then
                        declare
                           Src : constant Unsigned_32 :=
                             Shift_Left (Unsigned_32 (B (I)) and 16#3#, 24)
                             or Shift_Left (Unsigned_32 (B (I + 1)), 16)
                             or Shift_Left (Unsigned_32 (B (I + 2)), 8)
                             or (Unsigned_32 (B (I + 3)) and 16#FC#);
                           Dst : Unsigned_32;
                           Cur : constant Unsigned_32 := Unsigned_32 (I);
                        begin
                           Dst := (if Encoding then Cur + Src
                                   else Src - Cur);
                           B (I) :=
                             Byte (16#48#
                               or (Shift_Right (Dst, 24) and 16#3#));
                           B (I + 1) :=
                             Byte (Shift_Right (Dst, 16) and 16#FF#);
                           B (I + 2) :=
                             Byte (Shift_Right (Dst, 8) and 16#FF#);
                           B (I + 3) :=
                             Byte ((Unsigned_32 (B (I + 3)) and 16#3#)
                               or (Dst and 16#FC#));
                        end;
                     end if;
                     I := I + 4;
                  end loop;
               end;
            end if;

         when SPARC =>
            --  CALL (0x40.. or 0x7F..), big-endian, target << 2, ip += 0.
            if Len >= 4 then
               declare
                  I : Natural := 0;
               begin
                  while I <= Len - 4 loop
                     if (B (I) = 16#40#
                          and then (B (I + 1) and 16#C0#) = 16#00#)
                       or else (B (I) = 16#7F#
                          and then (B (I + 1) and 16#C0#) = 16#C0#)
                     then
                        declare
                           Src : Unsigned_32 :=
                             Shift_Left (Unsigned_32 (B (I)), 24)
                             or Shift_Left (Unsigned_32 (B (I + 1)), 16)
                             or Shift_Left (Unsigned_32 (B (I + 2)), 8)
                             or Unsigned_32 (B (I + 3));
                           Dst : Unsigned_32;
                           Cur : constant Unsigned_32 := Unsigned_32 (I);
                        begin
                           Src := Shift_Left (Src, 2);
                           Dst := (if Encoding then Cur + Src
                                   else Src - Cur);
                           Dst := Shift_Right (Dst, 2);
                           Dst :=
                             ((16#40000000# - (Dst and 16#400000#))
                              or 16#40000000#
                              or (Dst and 16#3FFFFF#));
                           B (I)     :=
                             Byte (Shift_Right (Dst, 24) and 16#FF#);
                           B (I + 1) :=
                             Byte (Shift_Right (Dst, 16) and 16#FF#);
                           B (I + 2) :=
                             Byte (Shift_Right (Dst, 8) and 16#FF#);
                           B (I + 3) := Byte (Dst and 16#FF#);
                        end;
                     end if;
                     I := I + 4;
                  end loop;
               end;
            end if;

         when IA64 =>
            Convert_IA64 (B, Encoding);

      end case;

      --  Return the converted bytes as a 1-based array (matches the crate's
      --  Byte_Array convention so downstream coders index from 'First = 1).
      return Result : Byte_Array (1 .. Len) do
         for K in 1 .. Len loop
            Result (K) := B (K - 1);
         end loop;
      end return;
   end Branch_Convert;

   -------------------
   -- Convert_RISCV --
   -------------------

   procedure Convert_RISCV (B : in out Byte_Array; Encoding : Boolean) is
      Len : constant Natural := B'Length;
      I   : Natural := B'First;
   begin
      if Len < 4 then
         return;
      end if;

      while I <= B'Last - 3 loop
         declare
            Inst : constant Unsigned_32 :=
              Unsigned_32 (B (I))
              or Shift_Left (Unsigned_32 (B (I + 1)), 8)
              or Shift_Left (Unsigned_32 (B (I + 2)), 16)
              or Shift_Left (Unsigned_32 (B (I + 3)), 24);
         begin
            if (Inst and 16#7F#) = 16#6F# then
               declare
                  Imm : Unsigned_32 :=
                    Shift_Left (Shift_Right (Inst, 31) and 1, 20)
                    or Shift_Left (Shift_Right (Inst, 21) and 16#3FF#, 1)
                    or Shift_Left (Shift_Right (Inst, 20) and 1, 11)
                    or (Inst and 16#000F_F000#);
                  Dst      : Unsigned_32;
                  Cur      : constant Unsigned_32 := Unsigned_32 (I);
                  New_Inst : Unsigned_32;
               begin
                  if (Imm and 16#0010_0000#) /= 0 then
                     Imm := Imm or 16#FFE0_0000#;
                  end if;

                  Dst := (if Encoding then Cur + Imm else Imm - Cur);
                  Imm := Dst and 16#001F_FFFE#;
                  New_Inst :=
                    (Inst and 16#0000_0FFF#)
                    or Shift_Left (Shift_Right (Imm, 20) and 1, 31)
                    or Shift_Left (Shift_Right (Imm, 1) and 16#3FF#, 21)
                    or Shift_Left (Shift_Right (Imm, 11) and 1, 20)
                    or (Imm and 16#000F_F000#);

                  B (I)     := Byte (New_Inst and 16#FF#);
                  B (I + 1) := Byte (Shift_Right (New_Inst, 8) and 16#FF#);
                  B (I + 2) := Byte (Shift_Right (New_Inst, 16) and 16#FF#);
                  B (I + 3) := Byte (Shift_Right (New_Inst, 24) and 16#FF#);
               end;
            end if;
         end;

         I := I + 4;
      end loop;
   end Convert_RISCV;

   ------------------
   -- Convert_IA64 --
   ------------------

   --  IA-64 (Itanium) bundle/slot branch converter. 16-byte bundles, three
   --  41-bit instruction slots; only slots flagged in the template table and
   --  carrying a long branch (opcode 5, qp 0) are rewritten.
   procedure Convert_IA64 (B : in out Byte_Array; Encoding : Boolean) is
      Branch_Table : constant array (0 .. 31) of Unsigned_32 :=
        [0, 0, 0, 0, 0, 0, 0, 0,
         0, 0, 0, 0, 0, 0, 0, 0,
         4, 4, 6, 6, 0, 0, 7, 7,
         4, 4, 0, 0, 4, 4, 0, 0];
      Len : constant Natural := B'Length;
      I   : Natural := B'First;
   begin
      if Len < 16 then
         return;
      end if;

      while I <= B'Last - 15 loop
         declare
            Template : constant Unsigned_32 :=
              Unsigned_32 (B (I)) and 16#1F#;
            Mask     : constant Unsigned_32 := Branch_Table (Natural (Template));
            Bit_Pos  : Natural := 5;
         begin
            for Slot in 0 .. 2 loop
               if (Shift_Right (Mask, Slot) and 1) /= 0 then
                  declare
                     Byte_Pos : constant Natural := Bit_Pos / 8;
                     Bit_Res  : constant Natural := Bit_Pos mod 8;
                     Instr    : Unsigned_64 := 0;
                     Norm     : Unsigned_64;
                  begin
                     for J in 0 .. 5 loop
                        Instr := Instr
                          or Shift_Left
                               (Unsigned_64 (B (I + J + Byte_Pos)), 8 * J);
                     end loop;
                     Norm := Shift_Right (Instr, Bit_Res);

                     if (Shift_Right (Norm, 37) and 16#F#) = 5
                       and then (Shift_Right (Norm, 9) and 16#7#) = 0
                     then
                        declare
                           Src : Unsigned_32 :=
                             Unsigned_32 (Shift_Right (Norm, 13)
                                          and 16#FFFFF#);
                           Dst : Unsigned_32;
                           Cur : constant Unsigned_32 :=
                             Unsigned_32 (I - B'First);
                        begin
                           Src := Src
                             or Shift_Left
                                  (Unsigned_32
                                     (Shift_Right (Norm, 36) and 1), 20);
                           Src := Shift_Left (Src, 4);
                           Dst := (if Encoding then Cur + Src
                                   else Src - Cur);
                           Dst := Shift_Right (Dst, 4);

                           Norm := Norm
                             and not Shift_Left (Unsigned_64 (16#8FFFFF#), 13);
                           Norm := Norm
                             or Shift_Left
                                  (Unsigned_64 (Dst and 16#FFFFF#), 13);
                           Norm := Norm
                             or Shift_Left
                                  (Unsigned_64 (Dst and 16#100000#), 16);

                           Instr := Instr
                             and (Shift_Left (Unsigned_64 (1), Bit_Res) - 1);
                           Instr := Instr or Shift_Left (Norm, Bit_Res);

                           for J in 0 .. 5 loop
                              B (I + J + Byte_Pos) :=
                                Byte (Shift_Right (Instr, 8 * J) and 16#FF#);
                           end loop;
                        end;
                     end if;
                  end;
               end if;
               Bit_Pos := Bit_Pos + 41;
            end loop;
         end;
         I := I + 16;
      end loop;
   end Convert_IA64;

   -----------------
   -- Convert_X86 --
   -----------------

   --  Full masked x86 BCJ (LZMA SDK Bra86.c x86_Convert). Rewrites the 4-byte
   --  relative operand of CALL/JMP (0xE8/0xE9) instructions, using a rolling
   --  mask to avoid converting bytes that only look like an opcode. ip = 0.
   procedure Convert_X86 (B : in out Byte_Array; Encoding : Boolean) is
      Len  : constant Natural := B'Length;
      Pos  : Natural := 0;
      Mask : Unsigned_32 := 0;
      Lim  : Natural;

      function MSB (X : Unsigned_32) return Boolean is
        ((X and 16#FF#) = 0 or else (X and 16#FF#) = 16#FF#);
      --  Test86MSByte: the operand's top byte must be 0x00 or 0xFF.
   begin
      if Len < 5 then
         return;
      end if;
      Lim := Len - 4;

      Outer :
      loop
         declare
            P : Natural := Pos;
         begin
            while P < Lim
              and then (B (B'First + P) and 16#FE#) /= 16#E8#
            loop
               P := P + 1;
            end loop;

            declare
               D : constant Natural := P - Pos;
            begin
               Pos := P;
               if P >= Lim then
                  return;
               end if;

               if D > 2 then
                  Mask := 0;
               else
                  Mask := Shift_Right (Mask, D);
                  if Mask /= 0
                    and then
                      (Mask > 4 or else Mask = 3
                       or else MSB
                         (Unsigned_32
                            (B (B'First + P
                                + Natural (Shift_Right (Mask, 1)) + 1))))
                  then
                     Mask := Shift_Right (Mask, 1) or 4;
                     Pos := Pos + 1;
                     goto Continue;
                  end if;
               end if;
            end;
         end;

         if MSB (Unsigned_32 (B (B'First + Pos + 4))) then
            declare
               V   : Unsigned_32 :=
                 Shift_Left (Unsigned_32 (B (B'First + Pos + 4)), 24)
                 or Shift_Left (Unsigned_32 (B (B'First + Pos + 3)), 16)
                 or Shift_Left (Unsigned_32 (B (B'First + Pos + 2)), 8)
                 or Unsigned_32 (B (B'First + Pos + 1));
               Cur : constant Unsigned_32 := 5 + Unsigned_32 (Pos);
            begin
               Pos := Pos + 5;
               if Encoding then
                  V := V + Cur;
               else
                  V := V - Cur;
               end if;

               if Mask /= 0 then
                  declare
                     Sh : constant Natural :=
                       Natural (Shift_Left (Mask and 6, 2));
                  begin
                     if MSB (Shift_Right (V, Sh)) then
                        V := V xor
                          (Shift_Left (Unsigned_32 (16#100#), Sh) - 1);
                        if Encoding then
                           V := V + Cur;
                        else
                           V := V - Cur;
                        end if;
                     end if;
                  end;
                  Mask := 0;
               end if;

               B (B'First + Pos - 4) := Byte (V and 16#FF#);
               B (B'First + Pos - 3) := Byte (Shift_Right (V, 8) and 16#FF#);
               B (B'First + Pos - 2) := Byte (Shift_Right (V, 16) and 16#FF#);
               B (B'First + Pos - 1) :=
                 Byte ((0 - (Shift_Right (V, 24) and 1)) and 16#FF#);
            end;
         else
            Mask := Shift_Right (Mask, 1) or 4;
            Pos := Pos + 1;
         end if;

         <<Continue>>
      end loop Outer;
   end Convert_X86;

   -------------------
   -- Convert_ARM64 --
   -------------------

   --  ARM64 BCJ (matches the 7-Zip / xz ARM64 filter). Converts BL call
   --  targets and ADRP page offsets to absolute form. ip = 0, so pc = i.
   procedure Convert_ARM64 (B : in out Byte_Array; Encoding : Boolean) is
      Len : constant Natural := B'Length;
      I   : Natural := 0;

      function Get32 (K : Natural) return Unsigned_32 is
        (Unsigned_32 (B (B'First + K))
         or Shift_Left (Unsigned_32 (B (B'First + K + 1)), 8)
         or Shift_Left (Unsigned_32 (B (B'First + K + 2)), 16)
         or Shift_Left (Unsigned_32 (B (B'First + K + 3)), 24));

      procedure Put32 (K : Natural; V : Unsigned_32) is
      begin
         B (B'First + K)     := Byte (V and 16#FF#);
         B (B'First + K + 1) := Byte (Shift_Right (V, 8) and 16#FF#);
         B (B'First + K + 2) := Byte (Shift_Right (V, 16) and 16#FF#);
         B (B'First + K + 3) := Byte (Shift_Right (V, 24) and 16#FF#);
      end Put32;
   begin
      if Len < 4 then
         return;
      end if;

      while I + 4 <= Len loop
         declare
            PC    : constant Unsigned_32 := Unsigned_32 (I);
            Instr : Unsigned_32 := Get32 (I);
         begin
            if Shift_Right (Instr, 26) = 16#25# then
               --  BL (branch with link): 26-bit signed word offset.
               declare
                  Src : constant Unsigned_32 := Instr;
                  P   : Unsigned_32 := Shift_Right (PC, 2);
               begin
                  Instr := 16#9400_0000#;
                  if not Encoding then
                     P := 0 - P;
                  end if;
                  Instr := Instr or ((Src + P) and 16#03FF_FFFF#);
                  Put32 (I, Instr);
               end;
            elsif (Instr and 16#9F00_0000#) = 16#9000_0000# then
               --  ADRP: 21-bit signed page offset (immlo:immhi).
               declare
                  Src : constant Unsigned_32 :=
                    (Shift_Right (Instr, 29) and 3)
                    or (Shift_Right (Instr, 3) and 16#001F_FFFC#);
               begin
                  if ((Src + 16#0002_0000#) and 16#001C_0000#) = 0 then
                     declare
                        P    : Unsigned_32 := Shift_Right (PC, 12);
                        Dest : Unsigned_32;
                     begin
                        Instr := Instr and 16#9000_001F#;
                        if not Encoding then
                           P := 0 - P;
                        end if;
                        Dest := Src + P;
                        Instr := Instr or Shift_Left (Dest and 3, 29);
                        Instr := Instr
                          or Shift_Left (Dest and 16#0003_FFFC#, 3);
                        Instr := Instr
                          or ((0 - (Dest and 16#0002_0000#))
                              and 16#00E0_0000#);
                        Put32 (I, Instr);
                     end;
                  end if;
               end;
            end if;
         end;
         I := I + 4;
      end loop;
   end Convert_ARM64;

   -----------------
   -- BCJ2_Decode --
   -----------------

   function BCJ2_Decode
     (Main_Stream : Byte_Array;
      Call_Stream : Byte_Array;
      Jump_Stream : Byte_Array;
      RC_Stream   : Byte_Array;
      Expected    : Natural;
      Status      : out Status_Code) return Byte_Array
   is
      Empty : constant Byte_Array (1 .. 0) := [others => 0];

      subtype Prob_Index is Natural range 0 .. 257;
      type Prob_Array is array (Prob_Index) of Unsigned_16;

      Top_Value       : constant Unsigned_32 := 16#0100_0000#;
      Bit_Model_Total : constant Unsigned_32 := 2048;
      Move_Bits       : constant Natural := 5;

      Output   : Byte_Array (1 .. Expected) := [others => 0];
      Probs    : Prob_Array := [others => 1024];
      RC_Range : Unsigned_32 := Unsigned_32'Last;
      Code     : Unsigned_32 := 0;
      IP       : Unsigned_32 := 0;
      V        : Unsigned_32 := 0;
      Main_Pos : Natural := Main_Stream'First;
      Call_Pos : Natural := Call_Stream'First;
      Jump_Pos : Natural := Jump_Stream'First;
      RC_Pos   : Natural := RC_Stream'First;
      Out_Pos  : Natural := Output'First;

      function Has_Byte (Pos : Natural; Data : Byte_Array) return Boolean is
      begin
         return Pos in Data'Range;
      end Has_Byte;

      function Read_RC_Byte return Boolean is
      begin
         if not Has_Byte (RC_Pos, RC_Stream) then
            return False;
         end if;

         Code := Shift_Left (Code, 8) or Unsigned_32 (RC_Stream (RC_Pos));
         RC_Pos := RC_Pos + 1;
         return True;
      end Read_RC_Byte;

      function Read_BE32
        (Data  : Byte_Array;
         Pos   : in out Natural;
         Value : out Unsigned_32) return Boolean is
      begin
         if Pos not in Data'Range
           or else Pos + 3 > Data'Last
         then
            Value := 0;
            return False;
         end if;

         Value :=
           Shift_Left (Unsigned_32 (Data (Pos)), 24)
           or Shift_Left (Unsigned_32 (Data (Pos + 1)), 16)
           or Shift_Left (Unsigned_32 (Data (Pos + 2)), 8)
           or Unsigned_32 (Data (Pos + 3));
         Pos := Pos + 4;
         return True;
      end Read_BE32;

      procedure Put_Byte (B : Byte) is
      begin
         Output (Out_Pos) := B;
         Out_Pos := Out_Pos + 1;
         IP := IP + 1;
      end Put_Byte;

      function Candidate (Value : Unsigned_32) return Boolean is
         B : constant Unsigned_32 := Value and 16#FF#;
      begin
         return ((B + 16#18#) and 16#FE#) = 0
           or else
             ((Value - 16#0F00_0080#) and 16#FFFF_FFF0#) = 0;
      end Candidate;

      function Prob_For (Value : Unsigned_32) return Prob_Index is
         C    : constant Unsigned_32 := Shift_Right (Value + 16#17#, 6) and 1;
         High : constant Unsigned_32 := Shift_Right (Value, 24) and 16#FF#;
         Low  : constant Unsigned_32 := Shift_Right (Value, 5) and 1;
      begin
         return Prob_Index (((0 - C) and High) + C + Low);
      end Prob_For;

      function Jump_Stream_For (Value : Unsigned_32) return Natural is
      begin
         return Natural (Shift_Right (Value + 16#57#, 6) and 1);
      end Jump_Stream_For;
   begin
      Status := Unexpected_End_Of_Input;

      for I in 1 .. 5 loop
         if not Read_RC_Byte then
            return Empty;
         end if;

         if I = 2 and then Code /= Unsigned_32 (RC_Stream (RC_Pos - 1)) then
            return Empty;
         end if;
      end loop;

      if Code = Unsigned_32'Last then
         Status := Invalid_Block_Type;
         return Empty;
      end if;

      while Out_Pos <= Output'Last loop
         if RC_Range < Top_Value then
            if not Read_RC_Byte then
               return Empty;
            end if;
            RC_Range := Shift_Left (RC_Range, 8);
         end if;

         if not Has_Byte (Main_Pos, Main_Stream) then
            return Empty;
         end if;

         declare
            B : constant Byte := Main_Stream (Main_Pos);
         begin
            Main_Pos := Main_Pos + 1;
            Put_Byte (B);
            V := Shift_Left (V, 24) or Unsigned_32 (B);
         end;

         if Out_Pos <= Output'Last and then Candidate (V) then
            declare
               P_Index : constant Prob_Index := Prob_For (V);
               Prob    : constant Unsigned_32 := Unsigned_32 (Probs (P_Index));
               Bound   : constant Unsigned_32 := Shift_Right (RC_Range, 11) * Prob;
            begin
               if Code < Bound then
                  RC_Range := Bound;
                  Probs (P_Index) :=
                    Unsigned_16 (Prob + Shift_Right (Bit_Model_Total - Prob, Move_Bits));
               else
                  RC_Range := RC_Range - Bound;
                  Code := Code - Bound;
                  Probs (P_Index) :=
                    Unsigned_16 (Prob - Shift_Right (Prob, Move_Bits));

                  declare
                     Encoded : Unsigned_32 := 0;
                     Source  : constant Natural := Jump_Stream_For (V);
                     Ok_Read : Boolean;
                  begin
                     if Source = 0 then
                        Ok_Read := Read_BE32 (Call_Stream, Call_Pos, Encoded);
                     else
                        Ok_Read := Read_BE32 (Jump_Stream, Jump_Pos, Encoded);
                     end if;

                     if not Ok_Read or else Out_Pos + 3 > Output'Last + 1 then
                        return Empty;
                     end if;

                     Encoded := Encoded - (IP + 4);
                     for I in 0 .. 3 loop
                        Output (Out_Pos + I) :=
                          Byte (Shift_Right (Encoded, 8 * I) and 16#FF#);
                     end loop;
                     Out_Pos := Out_Pos + 4;
                     IP := IP + 4;
                     V := Shift_Right (Encoded, 24);
                  end;
               end if;
            end;
         end if;
      end loop;

      if Main_Pos /= Main_Stream'Last + 1
        or else Call_Pos /= Call_Stream'Last + 1
        or else Jump_Pos /= Jump_Stream'Last + 1
      then
         Status := Invalid_Checksum;
         return Empty;
      end if;

      Status := Ok;
      return Output;
   end BCJ2_Decode;

   -----------------
   -- BCJ2_Encode --
   -----------------

   function BCJ2_Encode (Input : Byte_Array) return BCJ2_Encoded_Streams is
      subtype Prob_Index is Natural range 0 .. 257;
      type Prob_Array is array (Prob_Index) of Unsigned_32;

      Top_Value       : constant Unsigned_32 := 16#0100_0000#;
      Bit_Model_Total : constant Unsigned_32 := 2048;
      Move_Bits       : constant Natural := 5;

      Probs      : Prob_Array := [others => 1024];
      Rng        : Unsigned_32 := Unsigned_32'Last;
      Low        : Unsigned_64 := 0;
      Cache      : Byte := 0;
      Cache_Size : Unsigned_64 := 1;

      Total : constant Natural := Input'Length;
      IP    : Unsigned_32 := 0;
      V     : Unsigned_32 := 0;
      I     : Natural := Input'First;

      Main : Byte_Vectors.Vector;
      Call : Byte_Vectors.Vector;
      Jump : Byte_Vectors.Vector;
      RC   : Byte_Vectors.Vector;

      function Candidate (Value : Unsigned_32) return Boolean is
         B : constant Unsigned_32 := Value and 16#FF#;
      begin
         return ((B + 16#18#) and 16#FE#) = 0
           or else ((Value - 16#0F00_0080#) and 16#FFFF_FFF0#) = 0;
      end Candidate;

      function Prob_For (Value : Unsigned_32) return Prob_Index is
         C    : constant Unsigned_32 := Shift_Right (Value + 16#17#, 6) and 1;
         High : constant Unsigned_32 := Shift_Right (Value, 24) and 16#FF#;
         Lo   : constant Unsigned_32 := Shift_Right (Value, 5) and 1;
      begin
         return Prob_Index (((0 - C) and High) + C + Lo);
      end Prob_For;

      function Jump_Stream_For (Value : Unsigned_32) return Natural is
        (Natural (Shift_Right (Value + 16#57#, 6) and 1));

      procedure Shift_Low is
      begin
         if Low < 16#FF00_0000#
           or else Low > 16#FFFF_FFFF#
         then
            declare
               Temp : Byte := Cache;
            begin
               loop
                  RC.Append
                    (Byte ((Unsigned_64 (Temp) + Shift_Right (Low, 32)) and 16#FF#));
                  Temp := 16#FF#;
                  Cache_Size := Cache_Size - 1;
                  exit when Cache_Size = 0;
               end loop;
               Cache := Byte (Shift_Right (Low, 24) and 16#FF#);
            end;
         end if;
         Cache_Size := Cache_Size + 1;
         Low := Shift_Left (Low and 16#00FF_FFFF#, 8);
      end Shift_Low;

      procedure Encode_Bit (Idx : Prob_Index; Bit : Natural) is
         Prob  : constant Unsigned_32 := Probs (Idx);
         Bound : constant Unsigned_32 := Shift_Right (Rng, 11) * Prob;
      begin
         if Bit = 0 then
            Rng := Bound;
            Probs (Idx) :=
              Prob + Shift_Right (Bit_Model_Total - Prob, Move_Bits);
         else
            Low := Low + Unsigned_64 (Bound);
            Rng := Rng - Bound;
            Probs (Idx) := Prob - Shift_Right (Prob, Move_Bits);
         end if;
         if Rng < Top_Value then
            Rng := Shift_Left (Rng, 8);
            Shift_Low;
         end if;
      end Encode_Bit;

      procedure Append_BE32
        (To : in out Byte_Vectors.Vector; Value : Unsigned_32) is
      begin
         To.Append (Byte (Shift_Right (Value, 24) and 16#FF#));
         To.Append (Byte (Shift_Right (Value, 16) and 16#FF#));
         To.Append (Byte (Shift_Right (Value, 8) and 16#FF#));
         To.Append (Byte (Value and 16#FF#));
      end Append_BE32;
   begin
      while I <= Input'Last loop
         declare
            B : constant Byte := Input (I);
         begin
            I := I + 1;
            Main.Append (B);
            IP := IP + 1;
            V := Shift_Left (V, 24) or Unsigned_32 (B);
         end;

         if Natural (IP) < Total and then Candidate (V) then
            declare
               P_Idx   : constant Prob_Index := Prob_For (V);
               Convert : Boolean := False;
               Rel     : Unsigned_32 := 0;
            begin
               --  Need 4 displacement bytes to convert.
               if I + 3 <= Input'Last then
                  Rel :=
                    Unsigned_32 (Input (I))
                    or Shift_Left (Unsigned_32 (Input (I + 1)), 8)
                    or Shift_Left (Unsigned_32 (Input (I + 2)), 16)
                    or Shift_Left (Unsigned_32 (Input (I + 3)), 24);
                  Convert := Input (I + 3) = 0 or else Input (I + 3) = 16#FF#;
               end if;

               if Convert then
                  Encode_Bit (P_Idx, 1);
                  declare
                     Abs_Addr : constant Unsigned_32 := Rel + IP + 4;
                  begin
                     if Jump_Stream_For (V) = 0 then
                        Append_BE32 (Call, Abs_Addr);
                     else
                        Append_BE32 (Jump, Abs_Addr);
                     end if;
                  end;
                  I := I + 4;
                  IP := IP + 4;
                  V := Shift_Right (Rel, 24);
               else
                  Encode_Bit (P_Idx, 0);
               end if;
            end;
         end if;
      end loop;

      for K in 1 .. 5 loop
         Shift_Low;
      end loop;

      return
        (Main_Length => Natural (Main.Length),
         Call_Length => Natural (Call.Length),
         Jump_Length => Natural (Jump.Length),
         RC_Length   => Natural (RC.Length),
         Main_Stream => To_Byte_Array (Main),
         Call_Stream => To_Byte_Array (Call),
         Jump_Stream => To_Byte_Array (Jump),
         RC_Stream   => To_Byte_Array (RC));
   end BCJ2_Encode;

   ------------------
   -- Delta_Encode --
   ------------------

   function Delta_Encode
     (Data     : Byte_Array;
      Distance : Positive) return Byte_Array
   is
      Result  : Byte_Array (1 .. Data'Length) := [others => 0];
      History : array (0 .. 255) of Byte := [others => 0];
      Pos     : Natural range 0 .. 255 := 0;
   begin
      if Data'Length = 0 then
         return [1 .. 0 => 0];
      end if;

      for I in Data'Range loop
         declare
            Cur : constant Byte := Data (I);
         begin
            Result (1 + (I - Data'First)) := Cur - History (Pos);
            History (Pos) := Cur;
            Pos := (Pos + 1) mod Distance;
         end;
      end loop;
      return Result;
   end Delta_Encode;

   ------------------
   -- Delta_Decode --
   ------------------

   function Delta_Decode
     (Data     : Byte_Array;
      Distance : Positive) return Byte_Array
   is
      Result  : Byte_Array (1 .. Data'Length) := [others => 0];
      History : array (0 .. 255) of Byte := [others => 0];
      Pos     : Natural range 0 .. 255 := 0;
   begin
      if Data'Length = 0 then
         return [1 .. 0 => 0];
      end if;

      for I in Data'Range loop
         declare
            Cur : constant Byte := Data (I) + History (Pos);
         begin
            Result (1 + (I - Data'First)) := Cur;
            History (Pos) := Cur;
            Pos := (Pos + 1) mod Distance;
         end;
      end loop;
      return Result;
   end Delta_Decode;

   --------------------------
   -- Delta_Decode_Checked --
   --------------------------

   function Delta_Decode_Checked
     (Data     : Byte_Array;
      Distance : Natural;
      Status   : out Status_Code) return Byte_Array
   is
      Empty : constant Byte_Array (1 .. 0) := [others => 0];
   begin
      if Distance = 0 or else Distance > 256 then
         Status := Unsupported_Method;
         return Empty;
      end if;

      Status := Ok;
      return Delta_Decode (Data, Distance);
   end Delta_Decode_Checked;

   --------------------
   -- X86_BCJ_Decode --
   --------------------

   function X86_BCJ_Decode
     (Data   : Byte_Array;
      Status : out Status_Code) return Byte_Array is
   begin
      Status := Ok;
      return Branch_Convert (X86, Data, Encoding => False);
   end X86_BCJ_Decode;

   ------------------
   -- Apply_Filter --
   ------------------

   function Apply_Filter
     (Data           : Byte_Array;
      Filter         : Seven_Zip_Filter_Method;
      Delta_Distance : Positive) return Byte_Array
   is
   begin
      case Filter is
         when Seven_Zip_Filter_X86_BCJ =>
            return Branch_Convert (X86, Data, Encoding => True);
         when Seven_Zip_Filter_ARM_BCJ =>
            return Branch_Convert (ARM, Data, Encoding => True);
         when Seven_Zip_Filter_ARMT_BCJ =>
            return Branch_Convert (ARMT, Data, Encoding => True);
         when Seven_Zip_Filter_ARM64_BCJ =>
            return Branch_Convert (ARM64, Data, Encoding => True);
         when Seven_Zip_Filter_PPC_BCJ =>
            return Branch_Convert (PPC, Data, Encoding => True);
         when Seven_Zip_Filter_SPARC_BCJ =>
            return Branch_Convert (SPARC, Data, Encoding => True);
         when Seven_Zip_Filter_IA64_BCJ =>
            return Branch_Convert (IA64, Data, Encoding => True);
         when Seven_Zip_Filter_RISCV_BCJ =>
            return Branch_Convert (RISCV, Data, Encoding => True);
         when Seven_Zip_Filter_Delta =>
            return Delta_Encode (Data, Delta_Distance);
      end case;
   end Apply_Filter;

end Zlib.Seven_Zip_Filters;
