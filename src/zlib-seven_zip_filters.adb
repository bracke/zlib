with Interfaces; use Interfaces;

package body Zlib.Seven_Zip_Filters is

   --  All converters operate on a normalized 0-based working copy of the
   --  input. The implicit instruction-pointer origin (ip) is 0.

   procedure Convert_IA64 (B : in out Byte_Array; Encoding : Boolean);
   procedure Convert_X86 (B : in out Byte_Array; Encoding : Boolean);
   procedure Convert_ARM64 (B : in out Byte_Array; Encoding : Boolean);
   --  Forward declarations; bodies below.

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

   ------------------
   -- Delta_Encode --
   ------------------

   function Delta_Encode
     (Data     : Byte_Array;
      Distance : Positive) return Byte_Array
   is
      Result  : Byte_Array (1 .. Data'Length);
      History : array (0 .. 255) of Byte := [others => 0];
      Pos     : Natural := 0;
   begin
      for K in 0 .. Data'Length - 1 loop
         declare
            Cur : constant Byte := Data (Data'First + K);
         begin
            Result (K + 1) := Cur - History (Pos);
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
      Result  : Byte_Array (1 .. Data'Length);
      History : array (0 .. 255) of Byte := [others => 0];
      Pos     : Natural := 0;
   begin
      for K in 0 .. Data'Length - 1 loop
         declare
            Cur : constant Byte := Data (Data'First + K) + History (Pos);
         begin
            Result (K + 1) := Cur;
            History (Pos) := Cur;
            Pos := (Pos + 1) mod Distance;
         end;
      end loop;
      return Result;
   end Delta_Decode;

end Zlib.Seven_Zip_Filters;
