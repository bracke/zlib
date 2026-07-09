with AUnit.Assertions; use AUnit.Assertions;
with Interfaces;       use Interfaces;
with Zlib;             use Zlib;
with Zlib.Bit_Writer;
with Zlib.LZMA2_Decoder;
with Zlib.LZMA2_Framing;
with Zlib.LZMA_Core;
with Zlib.LZMA_Literals;
with Zlib.LZMA_Match_Finder;
with Zlib.LZMA_Parser;
with Zlib.LZMA_Properties;
with Zlib.LZMA_Range_Encoder;
with Zlib.LZMA_Range_Decoders;
with Zlib.LZMA_Repetitions;
with Zlib.Seven_Zip_Filters; use Zlib.Seven_Zip_Filters;
with Zlib.Seven_Zip_Graphs;
with Zlib.Seven_Zip_Methods; use Zlib.Seven_Zip_Methods;
with Zlib.Seven_Zip_Numbers;
with Zlib.Seven_Zip_Properties;

package body Zlib_Seven_Zip_Filter_Tests is

   use type Zlib.LZMA2_Framing.Control_Kind;
   use type Zlib.LZMA_Parser.Opt_Kind;

   --  Frozen fixtures: minimal .7z archives produced by stock 7-Zip with a
   --  <branch-filter> + Copy folder over the 16-byte Input_Bytes payload
   --  (entry name "inp.bin"). They lock in interop decode of real 7z
   --  branch-filtered archives; the IA64 coder id 03030401 in Archive_IA64
   --  is the exact byte that distinguishes IA-64 from the Alpha filter.
   Input_Bytes : constant Byte_Array :=
     [16#eb#, 16#00#, 16#00#, 16#eb#, 16#48#, 16#01#, 16#02#, 16#03#, 16#f0#,
      16#12#, 16#f8#, 16#34#, 16#40#, 16#00#, 16#00#, 16#10#];
   Archive_ARM : constant Byte_Array :=
     [16#37#, 16#7a#, 16#bc#, 16#af#, 16#27#, 16#1c#, 16#00#, 16#04#, 16#6d#,
      16#80#, 16#35#, 16#fb#, 16#10#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#,
      16#00#, 16#00#, 16#5a#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#,
      16#00#, 16#b6#, 16#53#, 16#80#, 16#a9#, 16#ed#, 16#00#, 16#00#, 16#eb#,
      16#48#, 16#01#, 16#02#, 16#03#, 16#f0#, 16#12#, 16#f8#, 16#34#, 16#40#,
      16#00#, 16#00#, 16#10#, 16#01#, 16#04#, 16#06#, 16#00#, 16#01#, 16#09#,
      16#10#, 16#00#, 16#07#, 16#0b#, 16#01#, 16#00#, 16#02#, 16#01#, 16#00#,
      16#04#, 16#03#, 16#03#, 16#05#, 16#01#, 16#01#, 16#00#, 16#0c#, 16#10#,
      16#10#, 16#00#, 16#08#, 16#0a#, 16#01#, 16#81#, 16#e6#, 16#fc#, 16#74#,
      16#00#, 16#00#, 16#05#, 16#01#, 16#19#, 16#06#, 16#00#, 16#00#, 16#00#,
      16#00#, 16#00#, 16#00#, 16#11#, 16#11#, 16#00#, 16#69#, 16#00#, 16#6e#,
      16#00#, 16#70#, 16#00#, 16#2e#, 16#00#, 16#62#, 16#00#, 16#69#, 16#00#,
      16#6e#, 16#00#, 16#00#, 16#00#, 16#19#, 16#02#, 16#00#, 16#00#, 16#14#,
      16#0a#, 16#01#, 16#00#, 16#57#, 16#f7#, 16#ea#, 16#64#, 16#ee#, 16#06#,
      16#dd#, 16#01#, 16#15#, 16#06#, 16#01#, 16#00#, 16#20#, 16#80#, 16#b4#,
      16#81#, 16#00#, 16#00#];
   Archive_ARMT : constant Byte_Array :=
     [16#37#, 16#7a#, 16#bc#, 16#af#, 16#27#, 16#1c#, 16#00#, 16#04#, 16#50#,
      16#e4#, 16#c1#, 16#3c#, 16#10#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#,
      16#00#, 16#00#, 16#5a#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#,
      16#00#, 16#df#, 16#f2#, 16#e7#, 16#2e#, 16#eb#, 16#00#, 16#00#, 16#eb#,
      16#48#, 16#01#, 16#02#, 16#03#, 16#f0#, 16#12#, 16#f8#, 16#34#, 16#40#,
      16#00#, 16#00#, 16#10#, 16#01#, 16#04#, 16#06#, 16#00#, 16#01#, 16#09#,
      16#10#, 16#00#, 16#07#, 16#0b#, 16#01#, 16#00#, 16#02#, 16#01#, 16#00#,
      16#04#, 16#03#, 16#03#, 16#07#, 16#01#, 16#01#, 16#00#, 16#0c#, 16#10#,
      16#10#, 16#00#, 16#08#, 16#0a#, 16#01#, 16#81#, 16#e6#, 16#fc#, 16#74#,
      16#00#, 16#00#, 16#05#, 16#01#, 16#19#, 16#06#, 16#00#, 16#00#, 16#00#,
      16#00#, 16#00#, 16#00#, 16#11#, 16#11#, 16#00#, 16#69#, 16#00#, 16#6e#,
      16#00#, 16#70#, 16#00#, 16#2e#, 16#00#, 16#62#, 16#00#, 16#69#, 16#00#,
      16#6e#, 16#00#, 16#00#, 16#00#, 16#19#, 16#02#, 16#00#, 16#00#, 16#14#,
      16#0a#, 16#01#, 16#00#, 16#57#, 16#f7#, 16#ea#, 16#64#, 16#ee#, 16#06#,
      16#dd#, 16#01#, 16#15#, 16#06#, 16#01#, 16#00#, 16#20#, 16#80#, 16#b4#,
      16#81#, 16#00#, 16#00#];
   Archive_PPC : constant Byte_Array :=
     [16#37#, 16#7a#, 16#bc#, 16#af#, 16#27#, 16#1c#, 16#00#, 16#04#, 16#a3#,
      16#89#, 16#83#, 16#a1#, 16#10#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#,
      16#00#, 16#00#, 16#5a#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#,
      16#00#, 16#fa#, 16#92#, 16#57#, 16#8b#, 16#eb#, 16#00#, 16#00#, 16#eb#,
      16#48#, 16#01#, 16#02#, 16#03#, 16#f0#, 16#12#, 16#f8#, 16#34#, 16#40#,
      16#00#, 16#00#, 16#10#, 16#01#, 16#04#, 16#06#, 16#00#, 16#01#, 16#09#,
      16#10#, 16#00#, 16#07#, 16#0b#, 16#01#, 16#00#, 16#02#, 16#01#, 16#00#,
      16#04#, 16#03#, 16#03#, 16#02#, 16#05#, 16#01#, 16#00#, 16#0c#, 16#10#,
      16#10#, 16#00#, 16#08#, 16#0a#, 16#01#, 16#81#, 16#e6#, 16#fc#, 16#74#,
      16#00#, 16#00#, 16#05#, 16#01#, 16#19#, 16#06#, 16#00#, 16#00#, 16#00#,
      16#00#, 16#00#, 16#00#, 16#11#, 16#11#, 16#00#, 16#69#, 16#00#, 16#6e#,
      16#00#, 16#70#, 16#00#, 16#2e#, 16#00#, 16#62#, 16#00#, 16#69#, 16#00#,
      16#6e#, 16#00#, 16#00#, 16#00#, 16#19#, 16#02#, 16#00#, 16#00#, 16#14#,
      16#0a#, 16#01#, 16#00#, 16#57#, 16#f7#, 16#ea#, 16#64#, 16#ee#, 16#06#,
      16#dd#, 16#01#, 16#15#, 16#06#, 16#01#, 16#00#, 16#20#, 16#80#, 16#b4#,
      16#81#, 16#00#, 16#00#];
   Archive_SPARC : constant Byte_Array :=
     [16#37#, 16#7a#, 16#bc#, 16#af#, 16#27#, 16#1c#, 16#00#, 16#04#, 16#e8#,
      16#71#, 16#44#, 16#cf#, 16#10#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#,
      16#00#, 16#00#, 16#5a#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#,
      16#00#, 16#f4#, 16#bc#, 16#3d#, 16#7c#, 16#eb#, 16#00#, 16#00#, 16#eb#,
      16#48#, 16#01#, 16#02#, 16#03#, 16#f0#, 16#12#, 16#f8#, 16#34#, 16#40#,
      16#00#, 16#00#, 16#13#, 16#01#, 16#04#, 16#06#, 16#00#, 16#01#, 16#09#,
      16#10#, 16#00#, 16#07#, 16#0b#, 16#01#, 16#00#, 16#02#, 16#01#, 16#00#,
      16#04#, 16#03#, 16#03#, 16#08#, 16#05#, 16#01#, 16#00#, 16#0c#, 16#10#,
      16#10#, 16#00#, 16#08#, 16#0a#, 16#01#, 16#81#, 16#e6#, 16#fc#, 16#74#,
      16#00#, 16#00#, 16#05#, 16#01#, 16#19#, 16#06#, 16#00#, 16#00#, 16#00#,
      16#00#, 16#00#, 16#00#, 16#11#, 16#11#, 16#00#, 16#69#, 16#00#, 16#6e#,
      16#00#, 16#70#, 16#00#, 16#2e#, 16#00#, 16#62#, 16#00#, 16#69#, 16#00#,
      16#6e#, 16#00#, 16#00#, 16#00#, 16#19#, 16#02#, 16#00#, 16#00#, 16#14#,
      16#0a#, 16#01#, 16#00#, 16#57#, 16#f7#, 16#ea#, 16#64#, 16#ee#, 16#06#,
      16#dd#, 16#01#, 16#15#, 16#06#, 16#01#, 16#00#, 16#20#, 16#80#, 16#b4#,
      16#81#, 16#00#, 16#00#];
   Archive_IA64 : constant Byte_Array :=
     [16#37#, 16#7a#, 16#bc#, 16#af#, 16#27#, 16#1c#, 16#00#, 16#04#, 16#53#,
      16#31#, 16#77#, 16#75#, 16#10#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#,
      16#00#, 16#00#, 16#5a#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#,
      16#00#, 16#22#, 16#00#, 16#8b#, 16#07#, 16#eb#, 16#00#, 16#00#, 16#eb#,
      16#48#, 16#01#, 16#02#, 16#03#, 16#f0#, 16#12#, 16#f8#, 16#34#, 16#40#,
      16#00#, 16#00#, 16#10#, 16#01#, 16#04#, 16#06#, 16#00#, 16#01#, 16#09#,
      16#10#, 16#00#, 16#07#, 16#0b#, 16#01#, 16#00#, 16#02#, 16#01#, 16#00#,
      16#04#, 16#03#, 16#03#, 16#04#, 16#01#, 16#01#, 16#00#, 16#0c#, 16#10#,
      16#10#, 16#00#, 16#08#, 16#0a#, 16#01#, 16#81#, 16#e6#, 16#fc#, 16#74#,
      16#00#, 16#00#, 16#05#, 16#01#, 16#19#, 16#06#, 16#00#, 16#00#, 16#00#,
      16#00#, 16#00#, 16#00#, 16#11#, 16#11#, 16#00#, 16#69#, 16#00#, 16#6e#,
      16#00#, 16#70#, 16#00#, 16#2e#, 16#00#, 16#62#, 16#00#, 16#69#, 16#00#,
      16#6e#, 16#00#, 16#00#, 16#00#, 16#19#, 16#02#, 16#00#, 16#00#, 16#14#,
      16#0a#, 16#01#, 16#00#, 16#57#, 16#f7#, 16#ea#, 16#64#, 16#ee#, 16#06#,
      16#dd#, 16#01#, 16#15#, 16#06#, 16#01#, 16#00#, 16#20#, 16#80#, 16#b4#,
      16#81#, 16#00#, 16#00#];

   --  Stock x86 BCJ (masked) and ARM64 filter fixtures: filter+Copy archives
   --  over crafted machine-code payloads (CALL/JMP for x86; BL/ADRP for ARM64)
   --  so the converter actually transforms bytes. Entry names "xi.bin"/"ai.bin".
   BCJ_Input : constant Byte_Array :=
     [16#e8#, 16#04#, 16#00#, 16#00#, 16#00#, 16#90#, 16#e9#, 16#08#, 16#00#,
      16#00#, 16#00#, 16#90#, 16#90#, 16#90#, 16#90#, 16#90#];
   Stock_BCJ : constant Byte_Array :=
     [16#37#, 16#7a#, 16#bc#, 16#af#, 16#27#, 16#1c#, 16#00#, 16#04#, 16#c7#,
      16#ee#, 16#ae#, 16#79#, 16#10#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#,
      16#00#, 16#00#, 16#5a#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#,
      16#00#, 16#33#, 16#71#, 16#e7#, 16#4f#, 16#e8#, 16#09#, 16#00#, 16#00#,
      16#00#, 16#90#, 16#e9#, 16#13#, 16#00#, 16#00#, 16#00#, 16#90#, 16#90#,
      16#90#, 16#90#, 16#90#, 16#01#, 16#04#, 16#06#, 16#00#, 16#01#, 16#09#,
      16#10#, 16#00#, 16#07#, 16#0b#, 16#01#, 16#00#, 16#02#, 16#01#, 16#00#,
      16#04#, 16#03#, 16#03#, 16#01#, 16#03#, 16#01#, 16#00#, 16#0c#, 16#10#,
      16#10#, 16#00#, 16#08#, 16#0a#, 16#01#, 16#e7#, 16#c3#, 16#4b#, 16#c9#,
      16#00#, 16#00#, 16#05#, 16#01#, 16#19#, 16#06#, 16#00#, 16#00#, 16#00#,
      16#00#, 16#00#, 16#00#, 16#11#, 16#0f#, 16#00#, 16#78#, 16#00#, 16#69#,
      16#00#, 16#2e#, 16#00#, 16#62#, 16#00#, 16#69#, 16#00#, 16#6e#, 16#00#,
      16#00#, 16#00#, 16#19#, 16#04#, 16#00#, 16#00#, 16#00#, 16#00#, 16#14#,
      16#0a#, 16#01#, 16#00#, 16#ce#, 16#69#, 16#d1#, 16#86#, 16#08#, 16#07#,
      16#dd#, 16#01#, 16#15#, 16#06#, 16#01#, 16#00#, 16#20#, 16#80#, 16#b4#,
      16#81#, 16#00#, 16#00#];
   ARM64_Input : constant Byte_Array :=
     [16#01#, 16#00#, 16#00#, 16#94#, 16#00#, 16#00#, 16#00#, 16#90#, 16#02#,
      16#00#, 16#00#, 16#94#, 16#00#, 16#00#, 16#00#, 16#b0#];
   Stock_ARM64 : constant Byte_Array :=
     [16#37#, 16#7a#, 16#bc#, 16#af#, 16#27#, 16#1c#, 16#00#, 16#04#, 16#8b#,
      16#0b#, 16#4a#, 16#c3#, 16#10#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#,
      16#00#, 16#00#, 16#5a#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#,
      16#00#, 16#cc#, 16#0c#, 16#7d#, 16#b7#, 16#01#, 16#00#, 16#00#, 16#94#,
      16#00#, 16#00#, 16#00#, 16#90#, 16#04#, 16#00#, 16#00#, 16#94#, 16#00#,
      16#00#, 16#00#, 16#b0#, 16#01#, 16#04#, 16#06#, 16#00#, 16#01#, 16#09#,
      16#10#, 16#00#, 16#07#, 16#0b#, 16#01#, 16#00#, 16#02#, 16#01#, 16#00#,
      16#01#, 16#0a#, 16#01#, 16#00#, 16#0c#, 16#10#, 16#10#, 16#00#, 16#08#,
      16#0a#, 16#01#, 16#80#, 16#44#, 16#50#, 16#f1#, 16#00#, 16#00#, 16#05#,
      16#01#, 16#19#, 16#09#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#,
      16#00#, 16#00#, 16#00#, 16#11#, 16#0f#, 16#00#, 16#61#, 16#00#, 16#69#,
      16#00#, 16#2e#, 16#00#, 16#62#, 16#00#, 16#69#, 16#00#, 16#6e#, 16#00#,
      16#00#, 16#00#, 16#19#, 16#04#, 16#00#, 16#00#, 16#00#, 16#00#, 16#14#,
      16#0a#, 16#01#, 16#00#, 16#48#, 16#d5#, 16#d2#, 16#86#, 16#08#, 16#07#,
      16#dd#, 16#01#, 16#15#, 16#06#, 16#01#, 16#00#, 16#20#, 16#80#, 16#b4#,
      16#81#, 16#00#, 16#00#];

   --  Deterministic pseudo-random fill (xorshift32) so any failure is
   --  reproducible without external fixtures.
   procedure Fill (B : out Byte_Array; Seed : in out Unsigned_32) is
   begin
      for I in B'Range loop
         Seed := Seed xor Shift_Left (Seed, 13);
         Seed := Seed xor Shift_Right (Seed, 17);
         Seed := Seed xor Shift_Left (Seed, 5);
         B (I) := Byte (Seed and 16#FF#);
      end loop;
   end Fill;

   overriding
   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib.Seven_Zip_Filters");
   end Name;

   --  Encode then Decode must reproduce the input exactly, for every
   --  architecture and a range of buffer lengths (including sub-instruction
   --  and unaligned sizes).
   procedure Test_Branch_Roundtrip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      for Arch in Branch_Arch loop
         for Len in 0 .. 80 loop
            declare
               Data : Byte_Array (1 .. Len);
               Seed : Unsigned_32 := Unsigned_32 (Len) * 2654435761 + 1;
            begin
               Fill (Data, Seed);
               declare
                  Enc  : constant Byte_Array :=
                    Branch_Convert (Arch, Data, True);
                  Back : constant Byte_Array :=
                    Branch_Convert (Arch, Enc, False);
               begin
                  Assert
                    (Back = Data,
                     "branch filter round-trip failed for "
                     & Branch_Arch'Image (Arch)
                     & " at length" & Integer'Image (Len));
               end;
            end;
         end loop;
      end loop;
   end Test_Branch_Roundtrip;

   --  Delta round-trips for every supported distance.
   procedure Test_Delta_Roundtrip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      for Dist in 1 .. 256 loop
         declare
            Data : Byte_Array (1 .. 300);
            Seed : Unsigned_32 := Unsigned_32 (Dist) * 40503 + 7;
         begin
            Fill (Data, Seed);
            declare
               Enc  : constant Byte_Array := Delta_Encode (Data, Dist);
               Back : constant Byte_Array := Delta_Decode (Enc, Dist);
            begin
               Assert
                 (Back = Data,
                  "delta round-trip failed for distance"
                  & Integer'Image (Dist));
            end;
         end;
      end loop;
   end Test_Delta_Roundtrip;

   --  Interop-correct known answers (not merely self-consistent): these match
   --  the LZMA SDK / 7-Zip Bra.c converters.
   procedure Test_Known_Answers
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      --  ARM BL at offset 0 with a zero offset field encodes the absolute
      --  target ip+8 = 8, stored as 8 >> 2 = 2.
      ARM_In  : constant Byte_Array := [16#00#, 16#00#, 16#00#, 16#EB#];
      ARM_Out : constant Byte_Array := Branch_Convert (ARM, ARM_In, True);

      --  Delta distance 1: successive differences.
      Delta_In  : constant Byte_Array := [16#10#, 16#12#, 16#15#];
      Delta_Out : constant Byte_Array := Delta_Encode (Delta_In, 1);

      --  RISC-V JAL x0, 0 at byte offset 4 encodes the absolute target 4.
      RISCV_In  : constant Byte_Array :=
        [16#13#, 16#00#, 16#00#, 16#00#, 16#6F#, 16#00#, 16#00#, 16#00#];
      RISCV_Out : constant Byte_Array := Branch_Convert (RISCV, RISCV_In, True);

      --  Non-branch bytes pass through unchanged.
      Plain     : constant Byte_Array := [16#01#, 16#02#, 16#03#, 16#04#];
      Plain_Out : constant Byte_Array := Branch_Convert (PPC, Plain, True);
   begin
      Assert
        (ARM_Out = [16#02#, 16#00#, 16#00#, 16#EB#],
         "ARM BL known-answer encode mismatch");
      Assert
        (Delta_Out = [16#10#, 16#02#, 16#03#],
         "Delta distance-1 known-answer encode mismatch");
      Assert
        (RISCV_Out =
           [16#13#, 16#00#, 16#00#, 16#00#, 16#6F#, 16#00#, 16#40#, 16#00#],
         "RISC-V JAL known-answer encode mismatch");
      Assert
        (Branch_Convert (RISCV, RISCV_Out, False) = RISCV_In,
         "RISC-V JAL known-answer decode mismatch");
      Assert
        (Plain_Out = Plain,
         "non-branch bytes must pass through unchanged");
   end Test_Known_Answers;

   --  End-to-end interop: extract real stock-7z branch-filtered archives via
   --  the public neutral extractor and confirm the payload round-trips.
   procedure Test_Stock_7z_Decode
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      procedure Check_Archive (Label : String; Archive : Byte_Array) is
         Status : Zlib.Status_Code;
         Result : constant Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "inp.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "extraction of stock 7z " & Label
            & " archive failed: " & Zlib.Status_Image (Status));
         Assert
           (Result = Input_Bytes,
            "stock 7z " & Label & " filter payload mismatch");
      end Check_Archive;
   begin
      Check_Archive ("ARM", Archive_ARM);
      Check_Archive ("ARMT", Archive_ARMT);
      Check_Archive ("PPC", Archive_PPC);
      Check_Archive ("SPARC", Archive_SPARC);
      Check_Archive ("IA64", Archive_IA64);
   end Test_Stock_7z_Decode;

   --  Stock interop for the masked x86 BCJ and ARM64 filters.
   procedure Test_Stock_X86_ARM64_Decode
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      procedure Check (Label, Name : String;
                       Archive, Expected : Byte_Array) is
         Status : Zlib.Status_Code;
         Result : constant Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, Name, Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "stock 7z " & Label & " extraction failed: "
            & Zlib.Status_Image (Status));
         Assert (Result = Expected, "stock 7z " & Label & " payload mismatch");
      end Check;
   begin
      Check ("x86 BCJ", "xi.bin", Stock_BCJ, BCJ_Input);
      Check ("ARM64", "ai.bin", Stock_ARM64, ARM64_Input);
   end Test_Stock_X86_ARM64_Decode;

   procedure Test_Seven_Zip_Number_Encoding
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Sample : constant Byte_Array :=
        [16#78#, 16#56#, 16#34#, 16#12#, 16#EF#, 16#CD#, 16#AB#, 16#90#];

      procedure Check
        (Value    : Interfaces.Unsigned_64;
         Expected : Byte_Array)
      is
         Actual : constant Byte_Array := Zlib.Seven_Zip_Numbers.Encode_Number (Value);
         Pos    : Natural := Actual'First;
         Parsed : Interfaces.Unsigned_64 := 0;
      begin
         Assert
           (Zlib.Seven_Zip_Numbers.Encoded_Length (Value) = Expected'Length,
            "7z UInt64 encoded length mismatch for" & Interfaces.Unsigned_64'Image (Value));
         Assert
           (Actual = Expected,
            "7z UInt64 encoding mismatch for" & Interfaces.Unsigned_64'Image (Value));
         Assert
           (Zlib.Seven_Zip_Numbers.Read_Number (Actual, Pos, Actual'Last, Parsed),
            "7z UInt64 reader rejected encoded value" & Interfaces.Unsigned_64'Image (Value));
         Assert
           (Parsed = Value,
            "7z UInt64 reader value mismatch for" & Interfaces.Unsigned_64'Image (Value));
         Assert
           (Pos = Actual'Last + 1,
            "7z UInt64 reader cursor mismatch for" & Interfaces.Unsigned_64'Image (Value));
      end Check;
   begin
      Check (0, [1 => 16#00#]);
      Check (127, [1 => 16#7F#]);
      Check (128, [16#80#, 16#80#]);
      Check (16_383, [16#BF#, 16#FF#]);
      Check (16_384, [16#C0#, 16#00#, 16#40#]);
      Check (2 ** 21 - 1, [16#DF#, 16#FF#, 16#FF#]);
      Check (2 ** 21, [16#E0#, 16#00#, 16#00#, 16#20#]);
      Check
        (2 ** 56,
         [16#FF#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#01#]);
      Check
        (Interfaces.Unsigned_64'Last,
         [16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#]);
      Assert
        (Zlib.Seven_Zip_Numbers.U32_At (Sample, Sample'First) = 16#1234_5678#,
         "7z little-endian UInt32 reader mismatch");
      Assert
        (Zlib.Seven_Zip_Numbers.U64_At (Sample, Sample'First) = 16#90AB_CDEF_1234_5678#,
         "7z little-endian UInt64 reader mismatch");
   end Test_Seven_Zip_Number_Encoding;

   procedure Test_Seven_Zip_Method_IDs
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      procedure Check
        (Label     : String;
         ID        : Byte_Array;
         ID_Length : Natural;
         Code      : Seven_Zip_Method_Code;
         Method    : Seven_Zip_Coder_Method)
      is
         Parsed : Seven_Zip_Coder_Method := Seven_Zip_Copy;
      begin
         Assert
           (Method_Code_For_ID (ID, ID_Length) = Code,
            "7z method code mismatch for " & Label);
         Assert
           (Method_For_ID (ID, ID_Length, Parsed),
            "7z method legacy lookup rejected " & Label);
         Assert
           (Parsed = Method,
            "7z method legacy lookup mismatch for " & Label);
      end Check;

      procedure Check_Unknown
        (Label     : String;
         ID        : Byte_Array;
         ID_Length : Natural)
      is
         Parsed : Seven_Zip_Coder_Method;
      begin
         Assert
           (Method_Code_For_ID (ID, ID_Length) = Unknown_Method_Code,
            "7z unknown method code mismatch for " & Label);
         Assert
           (not Method_For_ID (ID, ID_Length, Parsed),
            "7z unknown method legacy lookup accepted " & Label);
         Assert
           (Parsed = Seven_Zip_Copy,
            "7z unknown method legacy lookup fallback changed for " & Label);
      end Check_Unknown;
   begin
      Check ("Copy", [1 => 16#00#], 1, 1, Seven_Zip_Copy);
      Check ("Deflate", [16#04#, 16#01#, 16#08#], 3, 2, Seven_Zip_Deflate_Method);
      Check ("BZip2", [16#04#, 16#02#, 16#02#], 3, 3, Seven_Zip_BZip2_Method);
      Check ("LZMA", [16#03#, 16#01#, 16#01#], 3, 4, Seven_Zip_LZMA_Method);
      Check ("LZMA2", [1 => 16#21#], 1, 5, Seven_Zip_LZMA2_Method);
      Check ("Delta", [1 => 16#03#], 1, 6, Seven_Zip_Delta_Method);
      Check ("x86 BCJ", [16#03#, 16#03#, 16#01#, 16#03#], 4, 7, Seven_Zip_BCJ_X86_Method);
      Check ("compact ARM", [1 => 16#07#], 1, 8, Seven_Zip_BCJ_ARM_Method);
      Check ("classic ARM", [16#03#, 16#03#, 16#05#, 16#01#], 4, 8, Seven_Zip_BCJ_ARM_Method);
      Check ("ARMT", [1 => 16#08#], 1, 9, Seven_Zip_BCJ_ARMT_Method);
      Check ("ARM64", [1 => 16#0A#], 1, 10, Seven_Zip_BCJ_ARM64_Method);
      Check ("PPC", [1 => 16#05#], 1, 11, Seven_Zip_BCJ_PPC_Method);
      Check ("SPARC", [1 => 16#09#], 1, 12, Seven_Zip_BCJ_SPARC_Method);
      Check ("IA64", [1 => 16#06#], 1, 13, Seven_Zip_BCJ_IA64_Method);
      Check ("RISC-V", [1 => 16#0B#], 1, 14, Seven_Zip_BCJ_RISCV_Method);
      Check ("BCJ2", [16#03#, 16#03#, 16#01#, 16#1B#], 4, 15, Seven_Zip_BCJ2_Method);
      Check ("PPMd", [16#03#, 16#04#, 16#01#], 3, 16, Seven_Zip_PPMd_Method);
      Check ("AES", [16#06#, 16#F1#, 16#07#, 16#01#], 4, 17, Seven_Zip_AES_Method);
      Check_Unknown ("bad one-byte", [1 => 16#7F#], 1);
      Check_Unknown ("bad classic branch", [16#03#, 16#03#, 16#06#, 16#01#], 4);
      Check_Unknown ("unsupported length", [16#01#, 16#02#], 2);
      Assert
        (Descriptor_Flags (Seven_Zip_Copy, False) = 16#01#,
         "Copy coder flags mismatch");
      Assert
        (Descriptor_Flags (Seven_Zip_LZMA_Method, True) = 16#23#,
         "LZMA property coder flags mismatch");
      Assert
        (Descriptor_Flags (Seven_Zip_BCJ2_Method, False) = 16#14#,
         "BCJ2 multi-stream coder flags mismatch");
   end Test_Seven_Zip_Method_IDs;

   procedure Test_LZMA_Property_Helpers
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Props : constant Byte_Array :=
        Zlib.LZMA_Properties.Default_Dict_Properties (Zlib.LZMA_Properties.Default_Props);
      Raw_Header : constant Byte_Array :=
        Zlib.LZMA_Properties.Raw_Stream_Header
          (Zlib.LZMA_Properties.LZMA_Properties (Props));
   begin
      Assert
        (Zlib.LZMA_Properties.Props_Byte (3, 0, 2) = Zlib.LZMA_Properties.Default_Props,
         "default lc/lp/pb property byte mismatch");
      Assert
        (Props = [16#5D#, 16#00#, 16#00#, 16#80#, 16#00#],
         "default LZMA dictionary properties mismatch");
      Assert
        (Raw_Header = [0, 0, 5, 0, 16#5D#, 16#00#, 16#00#, 16#80#, 16#00#],
         "raw LZMA decode header prefix mismatch");
      Assert
        (Zlib.LZMA_Properties.Valid_Props (16#5D#),
         "default LZMA property byte must be valid");
      Assert
        (Zlib.LZMA_Properties.Valid_Props (Zlib.LZMA_Properties.Props_Byte (4, 0, 4)),
         "max supported LZMA property tuple must be valid");
      Assert
        (not Zlib.LZMA_Properties.Valid_Props (16#FF#),
         "invalid LZMA property byte accepted");
   end Test_LZMA_Property_Helpers;

   procedure Test_LZMA_Core_Helpers
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Probs : Zlib.LZMA_Core.Prob_Array (0 .. 2);
      Len   : Zlib.LZMA_Core.Len_Encoder;
      Reps  : constant Zlib.LZMA_Core.Rep_Quad := [1, 2, 3, 4];
      Settings : constant Zlib.LZMA_Core.Property_Decode_Result :=
        Zlib.LZMA_Core.Decode_Properties (Zlib.LZMA_Properties.Default_Props);
      Bad_Settings : constant Zlib.LZMA_Core.Property_Decode_Result :=
        Zlib.LZMA_Core.Decode_Properties (16#FF#);
   begin
      Zlib.LZMA_Core.Init_Probs (Probs);
      for P of Probs loop
         Assert
           (P = Zlib.LZMA_Core.Bit_Model_Total / 2,
            "LZMA probability initializer mismatch");
      end loop;

      Assert
        (Zlib.LZMA_Core.Literal_Context (3, 0, 0, 0) = 0,
         "LZMA zero literal context mismatch");
      Assert
        (Zlib.LZMA_Core.Literal_Context (3, 1, 3, 16#E0#) = 15,
         "LZMA literal context with lc/lp mismatch");
      Assert
        (Settings.Valid,
         "LZMA property decode rejected default properties");
      Assert
        (Settings.Settings.LC = 3
         and then Settings.Settings.LP = 0
         and then Settings.Settings.PB = 2,
         "LZMA property decode default tuple mismatch");
      Assert
        (not Bad_Settings.Valid,
         "LZMA property decode accepted invalid properties");
      Assert
        (Zlib.LZMA_Core.Encode_Candidates'Length = 7,
         "LZMA encode candidate count changed");
      Assert
        (Zlib.LZMA_Core.Encode_Candidates (1).LC = 3
         and then Zlib.LZMA_Core.Encode_Candidates (1).LP = 0
         and then Zlib.LZMA_Core.Encode_Candidates (1).PB = 2,
         "LZMA first encode candidate must remain the default tuple");
      for Candidate of Zlib.LZMA_Core.Encode_Candidates loop
         Assert
           (Zlib.LZMA_Properties.Valid_Props
              (Zlib.LZMA_Properties.Props_Byte
                 (Candidate.LC, Candidate.LP, Candidate.PB)),
            "LZMA encode candidate has invalid property tuple");
      end loop;

      Assert
        (Zlib.LZMA_Core.Literal_State_After (0) = 0,
         "LZMA literal state after literal mismatch for state 0");
      Assert
        (Zlib.LZMA_Core.Literal_State_After (7) = 4,
         "LZMA literal state after literal mismatch for state 7");
      Assert
        (Zlib.LZMA_Core.Literal_State_After (10) = 4,
         "LZMA literal state after literal mismatch for state 10");
      Assert
        (Zlib.LZMA_Core.Match_State_After (0) = 7,
         "LZMA match state after match mismatch for state 0");
      Assert
        (Zlib.LZMA_Core.Match_State_After (7) = 10,
         "LZMA match state after match mismatch for state 7");
      Assert
        (Zlib.LZMA_Core.Rep_State_After (0) = 8,
         "LZMA rep state mismatch for state 0");
      Assert
        (Zlib.LZMA_Core.Rep_State_After (7) = 11,
         "LZMA rep state mismatch for state 7");
      Assert
        (Zlib.LZMA_Core.Short_Rep_State_After (0) = 9,
         "LZMA short-rep state mismatch for state 0");
      Assert
        (Zlib.LZMA_Core.Short_Rep_State_After (7) = 11,
         "LZMA short-rep state mismatch for state 7");

      Assert (Zlib.LZMA_Core.Pos_Slot (0) = 0, "LZMA distance slot 0 mismatch");
      Assert (Zlib.LZMA_Core.Pos_Slot (3) = 3, "LZMA distance slot 3 mismatch");
      Assert (Zlib.LZMA_Core.Pos_Slot (4) = 4, "LZMA distance slot 4 mismatch");
      Assert (Zlib.LZMA_Core.Pos_Slot (5) = 4, "LZMA distance slot 5 mismatch");
      Assert (Zlib.LZMA_Core.Pos_Slot (6) = 5, "LZMA distance slot 6 mismatch");

      Zlib.LZMA_Core.Init_Len (Len);
      Assert
        (Len.Choice (0) = Zlib.LZMA_Core.Bit_Model_Total / 2
         and then Len.Low (0) = Zlib.LZMA_Core.Bit_Model_Total / 2
         and then Len.Mid (0) = Zlib.LZMA_Core.Bit_Model_Total / 2
         and then Len.High (0) = Zlib.LZMA_Core.Bit_Model_Total / 2,
         "LZMA length encoder initializer mismatch");

      Assert
        (Zlib.LZMA_Core.Bit_Price (Zlib.LZMA_Core.Bit_Model_Total - 1, 0) <
         Zlib.LZMA_Core.Bit_Price (Zlib.LZMA_Core.Bit_Model_Total - 1, 1),
         "LZMA high-probability bit price ordering mismatch");
      Assert
        (Zlib.LZMA_Core.Bit_Price (1, 1) <
         Zlib.LZMA_Core.Bit_Price (1, 0),
         "LZMA low-probability bit price ordering mismatch");
      Assert
        (Zlib.LZMA_Core.Reorder_Reps (Reps, 2) (0) = 3
         and then Zlib.LZMA_Core.Reorder_Reps (Reps, 2) (1) = 1
         and then Zlib.LZMA_Core.Reorder_Reps (Reps, 2) (2) = 2
         and then Zlib.LZMA_Core.Reorder_Reps (Reps, 2) (3) = 4,
         "LZMA rep reorder helper mismatch");
      Assert
        (Zlib.LZMA_Core.Shift_Reps (Reps, 9) (0) = 9
         and then Zlib.LZMA_Core.Shift_Reps (Reps, 9) (1) = 1
         and then Zlib.LZMA_Core.Shift_Reps (Reps, 9) (2) = 2
         and then Zlib.LZMA_Core.Shift_Reps (Reps, 9) (3) = 3,
         "LZMA rep shift helper mismatch");
   end Test_LZMA_Core_Helpers;

   procedure Test_LZMA_Range_Encoder_Helpers
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      E     : Zlib.LZMA_Range_Encoder.Encoder;
      E_Fin : Zlib.LZMA_Range_Encoder.Encoder;
      Probs : Zlib.LZMA_Core.Prob_Array (0 .. 7);
      Len   : Zlib.LZMA_Core.Len_Encoder;
      Pos_Slot : Zlib.LZMA_Core.Prob_Array
        (0 .. Zlib.LZMA_Core.Num_Len_To_Pos_States * 64 - 1);
      Pos_Special : Zlib.LZMA_Core.Prob_Array
        (0 .. Zlib.LZMA_Core.Num_Full_Distances - Zlib.LZMA_Core.End_Pos_Model_Index - 1);
      Pos_Align : Zlib.LZMA_Core.Prob_Array (0 .. Zlib.LZMA_Core.Align_Table_Size - 1);
   begin
      Zlib.LZMA_Core.Init_Probs (Probs);
      Zlib.LZMA_Core.Init_Probs (Pos_Slot);
      Zlib.LZMA_Core.Init_Probs (Pos_Special);
      Zlib.LZMA_Core.Init_Probs (Pos_Align);
      Zlib.LZMA_Range_Encoder.Encode_Bit (E, Probs (0), 0);
      Assert
        (Probs (0) > Zlib.LZMA_Core.Bit_Model_Total / 2,
         "LZMA range encoder did not adapt zero-bit probability");

      Zlib.LZMA_Range_Encoder.Encode_Bit_Tree (E, Probs, 0, 2, 3);
      Assert
        (Probs (1) < Zlib.LZMA_Core.Bit_Model_Total / 2
         and then Probs (3) < Zlib.LZMA_Core.Bit_Model_Total / 2,
         "LZMA range encoder bit-tree probabilities did not adapt");

      Zlib.LZMA_Range_Encoder.Encode_Direct_Bits (E, 3, 2);
      Zlib.LZMA_Core.Init_Len (Len);
      Zlib.LZMA_Range_Encoder.Encode_Len (E, Len, 0, 0);
      Assert
        (Len.Choice (0) > Zlib.LZMA_Core.Bit_Model_Total / 2
         and then Len.Low (1) > Zlib.LZMA_Core.Bit_Model_Total / 2,
         "LZMA range encoder length probabilities did not adapt");
      Assert
        (Zlib.LZMA_Range_Encoder.Tree_Price (Probs, 0, 2, 3) > 0,
         "LZMA range encoder tree price must be positive");
      Assert
        (Zlib.LZMA_Range_Encoder.Reverse_Tree_Price (Probs, 0, 2, 3) > 0,
         "LZMA range encoder reverse tree price must be positive");
      Assert
        (Zlib.LZMA_Range_Encoder.Len_Price (Len, 0, 0) > 0,
         "LZMA range encoder length price must be positive");
      Assert
        (Zlib.LZMA_Range_Encoder.Distance_Price
           (Pos_Slot, Pos_Special, Pos_Align, Zlib.LZMA_Core.Min_Match_Length, 4) > 0,
         "LZMA range encoder distance price must be positive");

      for I in 1 .. 5 loop
         Zlib.LZMA_Range_Encoder.Shift_Low (E);
      end loop;
      Assert
        (Zlib.Bit_Writer.To_Array (E.Writer)'Length > 0,
         "LZMA range encoder shift did not emit bytes");
      Zlib.LZMA_Range_Encoder.Encode_Direct_Bits (E_Fin, 3, 2);
      Assert
        (Zlib.LZMA_Range_Encoder.Finish (E_Fin)'Length > 0,
         "LZMA range encoder finish did not emit bytes");
   end Test_LZMA_Range_Encoder_Helpers;

   procedure Test_LZMA_Match_Finder_Helpers
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Plain : constant Byte_Array :=
        [Character'Pos ('a'), Character'Pos ('b'), Character'Pos ('c'),
         Character'Pos ('a'), Character'Pos ('b'), Character'Pos ('c')];
      Head  : Zlib.LZMA_Match_Finder.Pos_Table
        (0 .. 2 ** Zlib.LZMA_Match_Finder.Hash_Bits - 1) := [others => 0];
      Chain : Zlib.LZMA_Match_Finder.Pos_Table (1 .. Plain'Length) := [others => 0];
      H     : constant Natural := Zlib.LZMA_Match_Finder.Hash3 (Plain, Plain'First);
      Count : Natural := 0;
      Lens  : Zlib.LZMA_Match_Finder.Len_Array;
      Dists : Zlib.LZMA_Match_Finder.Len_Array;
      Span  : Natural := 3;
   begin
      Zlib.LZMA_Match_Finder.Insert (Plain, Head, Chain, Plain'First);
      Assert
        (Head (H) = 1,
         "LZMA match finder did not insert the first position");
      Assert
        (Zlib.LZMA_Match_Finder.Match_Length (Plain, Plain'First + 3, 3) = 3,
         "LZMA match finder length mismatch");
      Zlib.LZMA_Match_Finder.Find_All_Matches
        (Plain, Head, Chain, Plain'First + 3, 16#0080_0000#, Count, Lens, Dists);
      Assert
        (Count = 1 and then Lens (1) = 3 and then Dists (1) = 3,
         "LZMA match finder all-match enumeration mismatch");
      Assert
        (Zlib.LZMA_Match_Finder.Longest_Match_From
           (Plain, Head, Chain, Plain'First + 3, 16#0080_0000#) = 3,
         "LZMA match finder longest-match query mismatch");
      Zlib.LZMA_Match_Finder.Prepare_Adaptive_Segment
        (Plain, Head, Chain, Plain'First, 16#0080_0000#, Span);
      Assert (Span = 3, "LZMA match finder segment preparation changed span");
   end Test_LZMA_Match_Finder_Helpers;

   procedure Test_LZMA_Literal_Helpers
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Plain        : constant Byte_Array :=
        [Character'Pos ('a'), Character'Pos ('b'), Character'Pos ('a')];
      Literal_Ctxs : constant Natural :=
        2 ** (Zlib.LZMA_Core.Default_LC + Zlib.LZMA_Core.Default_LP);
      Literals     : Zlib.LZMA_Core.Prob_Array
        (0 .. Literal_Ctxs * Zlib.LZMA_Core.Literal_Probs - 1);
      E            : Zlib.LZMA_Range_Encoder.Encoder;
      Price_Before : Natural;
      Price_After  : Natural;
   begin
      Zlib.Bit_Writer.Reset (E.Writer);
      Zlib.LZMA_Core.Init_Probs (Literals);
      Price_Before :=
        Zlib.LZMA_Literals.Price
          (Literals     => Literals,
           Plain        => Plain,
           Index        => Plain'First,
           State        => 0,
           Rep0         => 0,
           Position     => 0,
           Lit_Ctx_Bits => Zlib.LZMA_Core.Default_LC,
           Lit_Pos_Bits => Zlib.LZMA_Core.Default_LP);
      Zlib.LZMA_Literals.Encode
        (E            => E,
         Literals     => Literals,
         Plain        => Plain,
         Index        => Plain'First,
         State        => 0,
         Rep0         => 0,
         Position     => 0,
         Lit_Ctx_Bits => Zlib.LZMA_Core.Default_LC,
         Lit_Pos_Bits => Zlib.LZMA_Core.Default_LP,
         Prev         => 0);
      Price_After :=
        Zlib.LZMA_Literals.Price
          (Literals     => Literals,
           Plain        => Plain,
           Index        => Plain'First,
           State        => 0,
           Rep0         => 0,
           Position     => 0,
           Lit_Ctx_Bits => Zlib.LZMA_Core.Default_LC,
           Lit_Pos_Bits => Zlib.LZMA_Core.Default_LP);
      Assert
        (Price_Before > 0 and then Price_After < Price_Before,
         "LZMA literal helper did not adapt literal probabilities");
      Assert
        (Zlib.LZMA_Literals.Price
           (Literals     => Literals,
            Plain        => Plain,
            Index        => Plain'First + 2,
            State        => 7,
            Rep0         => 2,
            Position     => 2,
            Lit_Ctx_Bits => Zlib.LZMA_Core.Default_LC,
            Lit_Pos_Bits => Zlib.LZMA_Core.Default_LP) > 0,
         "LZMA literal helper matched literal price must be positive");
   end Test_LZMA_Literal_Helpers;

   procedure Test_LZMA_Repetition_Helpers
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Is_Rep_G0    : Zlib.LZMA_Core.Prob_Array
        (0 .. Zlib.LZMA_Core.Num_States - 1);
      Is_Rep_G1    : Zlib.LZMA_Core.Prob_Array
        (0 .. Zlib.LZMA_Core.Num_States - 1);
      Is_Rep_G2    : Zlib.LZMA_Core.Prob_Array
        (0 .. Zlib.LZMA_Core.Num_States - 1);
      Is_Rep0_Long : Zlib.LZMA_Core.Prob_Array
        (0 .. Zlib.LZMA_Core.Num_States * Zlib.LZMA_Core.Num_Pos_States_Max - 1);
   begin
      Zlib.LZMA_Core.Init_Probs (Is_Rep_G0);
      Zlib.LZMA_Core.Init_Probs (Is_Rep_G1);
      Zlib.LZMA_Core.Init_Probs (Is_Rep_G2);
      Zlib.LZMA_Core.Init_Probs (Is_Rep0_Long);
      Assert
        (Zlib.LZMA_Repetitions.Choice_Price
           (Is_Rep_G0, Is_Rep_G1, Is_Rep_G2, Is_Rep0_Long, 0, 0, 0) > 0,
         "LZMA rep0 choice price must be positive");
      Assert
        (Zlib.LZMA_Repetitions.Choice_Price
           (Is_Rep_G0, Is_Rep_G1, Is_Rep_G2, Is_Rep0_Long, 0, 3, 0) > 0,
         "LZMA rep3 choice price must be positive");
   end Test_LZMA_Repetition_Helpers;

   procedure Test_LZMA_Parser_Helpers
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Opt : Zlib.LZMA_Parser.Opt_Array (0 .. 3);
      Ops : Zlib.LZMA_Parser.Op_Array (1 .. 3);
      N   : Natural := 0;
   begin
      Opt (0) := (Price => 0, From => 0, Kind => Zlib.LZMA_Parser.Op_Lit,
                  Dist => 0, Len => 1, Rep_Idx => 0, St => 0,
                  Reps => [0, 0, 0, 0]);
      Opt (1) := (Price => 1, From => 0, Kind => Zlib.LZMA_Parser.Op_Lit,
                  Dist => 0, Len => 1, Rep_Idx => 0, St => 0,
                  Reps => [0, 0, 0, 0]);
      Opt (3) := (Price => 2, From => 1, Kind => Zlib.LZMA_Parser.Op_Match,
                  Dist => 3, Len => 2, Rep_Idx => 0, St => 7,
                  Reps => [3, 0, 0, 0]);
      Zlib.LZMA_Parser.Backtrack (Opt, 3, Ops, N);
      Assert
        (N = 2
         and then Ops (1).Kind = Zlib.LZMA_Parser.Op_Match
         and then Ops (1).Dist = 3
         and then Ops (2).Kind = Zlib.LZMA_Parser.Op_Lit,
         "LZMA parser backtrack order mismatch");
   end Test_LZMA_Parser_Helpers;

   procedure Test_LZMA_Range_Decoder_Helpers
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      D           : Zlib.LZMA_Range_Decoders.Decoder;
      Status      : Status_Code := Ok;
      Probs       : Zlib.LZMA_Core.Prob_Array (0 .. 7);
      Len         : Zlib.LZMA_Core.Len_Encoder;
      Short_Input : constant Byte_Array := [1 => 0, 2 => 0, 3 => 0, 4 => 0];
      Input       : constant Byte_Array := [1 .. 8 => 0];
   begin
      Zlib.LZMA_Range_Decoders.Init (D, Short_Input, Status);
      Assert
        (Status = Unexpected_End_Of_Input,
         "LZMA range decoder accepted a short init stream");

      Status := Ok;
      Zlib.LZMA_Core.Init_Probs (Probs);
      Zlib.LZMA_Range_Decoders.Init (D, Input, Status);
      Assert (Status = Ok, "LZMA range decoder rejected a valid init stream");
      Assert
        (Zlib.LZMA_Range_Decoders.Decode_Bit (D, Input, Probs (0), Status) = 0,
         "LZMA range decoder zero stream bit mismatch");
      Assert
        (Status = Ok and then Probs (0) > Zlib.LZMA_Core.Bit_Model_Total / 2,
         "LZMA range decoder probability adaptation mismatch");

      Zlib.LZMA_Core.Init_Len (Len);
      Assert
        (Zlib.LZMA_Range_Decoders.Decode_Len (D, Input, Len, 0, Status) = 0,
         "LZMA range decoder length symbol mismatch");
   end Test_LZMA_Range_Decoder_Helpers;

   procedure Test_LZMA2_Framing_Helpers
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Uncompressed_First : constant Byte_Array :=
        Zlib.LZMA2_Framing.Uncompressed_Chunk ([16#AA#, 16#BB#], True);
      Uncompressed_Next : constant Byte_Array :=
        Zlib.LZMA2_Framing.Uncompressed_Chunk ([16#AA#, 16#BB#], False);
      Compressed : constant Byte_Array :=
        Zlib.LZMA2_Framing.Compressed_Chunk
          ([1 => 16#11#, 2 => 16#22#], [1 => 16#33#], 16#5D#);
      End_Info : constant Zlib.LZMA2_Framing.Control_Info :=
        Zlib.LZMA2_Framing.Decode_Control (0, True);
      First_Uncompressed : constant Zlib.LZMA2_Framing.Control_Info :=
        Zlib.LZMA2_Framing.Decode_Control (16#01#, True);
      Bad_First_Uncompressed : constant Zlib.LZMA2_Framing.Control_Info :=
        Zlib.LZMA2_Framing.Decode_Control (16#02#, True);
      Next_Uncompressed : constant Zlib.LZMA2_Framing.Control_Info :=
        Zlib.LZMA2_Framing.Decode_Control (16#02#, False);
      Reset_Compressed : constant Zlib.LZMA2_Framing.Control_Info :=
        Zlib.LZMA2_Framing.Decode_Control (16#E0#, False);
   begin
      Assert
        (Uncompressed_First = [16#01#, 0, 1, 16#AA#, 16#BB#],
         "LZMA2 first uncompressed chunk framing mismatch");
      Assert
        (Uncompressed_Next = [16#02#, 0, 1, 16#AA#, 16#BB#],
         "LZMA2 continued uncompressed chunk framing mismatch");
      Assert
        (Compressed = [16#E0#, 0, 1, 0, 0, 16#5D#, 16#33#],
         "LZMA2 compressed chunk framing mismatch");
      Assert
        (End_Info.Kind = Zlib.LZMA2_Framing.End_Marker,
         "LZMA2 end control classification mismatch");
      Assert
        (First_Uncompressed.Kind = Zlib.LZMA2_Framing.Uncompressed
         and then First_Uncompressed.Reset_Dict,
         "LZMA2 first uncompressed control classification mismatch");
      Assert
        (Bad_First_Uncompressed.Kind = Zlib.LZMA2_Framing.Invalid,
         "LZMA2 invalid first uncompressed control was accepted");
      Assert
        (Next_Uncompressed.Kind = Zlib.LZMA2_Framing.Uncompressed
         and then not Next_Uncompressed.Reset_Dict,
         "LZMA2 continued uncompressed control classification mismatch");
      Assert
        (Reset_Compressed.Kind = Zlib.LZMA2_Framing.Compressed
         and then Reset_Compressed.Need_Props
         and then Reset_Compressed.Reset_State
         and then Reset_Compressed.Reset_Dict,
         "LZMA2 reset compressed control classification mismatch");
      Assert
        (Zlib.LZMA2_Framing.Uncompressed_Size (0, 1) = 2,
         "LZMA2 uncompressed size decode mismatch");
      Assert
        (Zlib.LZMA2_Framing.Compressed_Unpacked_Size (16#E0#, 0, 1) = 2,
         "LZMA2 unpacked size decode mismatch");
      Assert
        (Zlib.LZMA2_Framing.Packed_Size (0, 0) = 1,
         "LZMA2 packed size decode mismatch");
   end Test_LZMA2_Framing_Helpers;

   procedure Test_LZMA2_Decoder_Helpers
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Ctx     : Zlib.LZMA2_Decoder.Context;
      Status  : Status_Code := Ok;
      Plain   : Byte_Array (1 .. 1) := [others => 0];
      Out_Pos : Natural := 0;
   begin
      Zlib.LZMA2_Decoder.Reset_State (Ctx);
      Assert
        (not Zlib.LZMA2_Decoder.Properties_Seen (Ctx),
         "LZMA2 decoder context unexpectedly starts with properties");
      Assert
        (not Zlib.LZMA2_Decoder.Set_Properties (Ctx, 16#FF#),
         "LZMA2 decoder accepted invalid properties");
      Assert
        (Zlib.LZMA2_Decoder.Set_Properties (Ctx, Zlib.LZMA_Properties.Default_Props),
         "LZMA2 decoder rejected default properties");
      Assert
        (Zlib.LZMA2_Decoder.Properties_Seen (Ctx),
         "LZMA2 decoder did not remember accepted properties");

      Zlib.LZMA2_Decoder.Reset_Dictionary (Ctx, Out_Pos);
      Zlib.LZMA2_Decoder.Decode_Compressed_Chunk
        (Ctx, [1 => 0], Plain, Out_Pos, 1, Status);
      Assert
        (Status = Unexpected_End_Of_Input,
         "LZMA2 decoder short compressed chunk status mismatch");
   end Test_LZMA2_Decoder_Helpers;

   procedure Test_Seven_Zip_Graph_Helpers
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Copy_Coder : constant Seven_Zip_Graph_Coder :=
        (Method => Seven_Zip_Graph_Copy, Delta_Distance => 1);
      BCJ2_Coder : constant Seven_Zip_Graph_Coder :=
        (Method => Seven_Zip_Graph_BCJ2, Delta_Distance => 1);
      Delta_Coder : constant Seven_Zip_Graph_Coder :=
        (Method => Seven_Zip_Graph_Delta, Delta_Distance => 3);
      Bad_Delta_Coder : constant Seven_Zip_Graph_Coder :=
        (Method => Seven_Zip_Graph_Delta, Delta_Distance => 257);
      Coders : constant Seven_Zip_Graph_Coder_Array :=
        [Copy_Coder, Delta_Coder, BCJ2_Coder];
      Binds : constant Seven_Zip_Bind_Pair_Array :=
        [(In_Index => 1, Out_Index => 0), (In_Index => 2, Out_Index => 1)];
      Packs : constant Seven_Zip_Stream_Index_Array := [0, 3, 4];
      Sizes : constant Seven_Zip_Size_Array := [2, 3, 4];
      Unpack : constant Seven_Zip_Size_Array := [9, 9, 9];
      Packed_Total : constant Zlib.Seven_Zip_Graphs.Pack_Size_Summary :=
        Zlib.Seven_Zip_Graphs.Pack_Size_Total (Sizes);
      Overflow_Total : constant Zlib.Seven_Zip_Graphs.Pack_Size_Summary :=
        Zlib.Seven_Zip_Graphs.Pack_Size_Total ([Unsigned_64'Last, 1]);
   begin
      Assert
        (Zlib.Seven_Zip_Graphs.Coder_Input_Count (Copy_Coder) = 1,
         "Copy graph coder input count mismatch");
      Assert
        (Zlib.Seven_Zip_Graphs.Coder_Input_Count (BCJ2_Coder) = 4,
         "BCJ2 graph coder input count mismatch");
      Assert
        (Zlib.Seven_Zip_Graphs.Total_Input_Streams (Coders) = 6,
         "graph total input stream count mismatch");
      Assert
        (Zlib.Seven_Zip_Graphs.Expected_Packed_Stream_Count (Coders, Binds) = 4,
         "graph expected pack count mismatch");
      Assert
        (Packed_Total.Total = 9 and then Packed_Total.Fits,
         "graph packed size total mismatch");
      Assert
        (not Overflow_Total.Fits,
         "graph packed size overflow was not detected");
      Assert
        (not Zlib.Seven_Zip_Graphs.Graph_Shape_Valid
           (Coders, Binds, Packs, Sizes, Unpack, 9),
         "graph with too few packed stream indices was accepted");
      Assert
        (Zlib.Seven_Zip_Graphs.Graph_Shape_Valid
           ([Copy_Coder], [1 .. 0 => (In_Index => 0, Out_Index => 0)],
            [1 => 0], [1 => 9], [1 => 9], 9),
         "simple graph shape was rejected");
      Assert
        (not Zlib.Seven_Zip_Graphs.Graph_Shape_Valid
           ([Copy_Coder], [1 .. 0 => (In_Index => 0, Out_Index => 0)],
            [1 => 1], [1 => 9], [1 => 9], 9),
         "out-of-range packed stream index was accepted");
      Assert
        (not Zlib.Seven_Zip_Graphs.Graph_Shape_Valid
           ([Copy_Coder], [1 => (In_Index => 0, Out_Index => 1)],
            [1 .. 0 => 0], [1 .. 0 => 0], [1 => 9], 0),
         "out-of-range bind pair output index was accepted");
      Assert
        (not Zlib.Seven_Zip_Graphs.Graph_Shape_Valid
           ([Bad_Delta_Coder], [1 .. 0 => (In_Index => 0, Out_Index => 0)],
            [1 => 0], [1 => 9], [1 => 9], 9),
         "out-of-range Delta distance was accepted");
   end Test_Seven_Zip_Graph_Helpers;

   procedure Test_Seven_Zip_Property_Helpers
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Time_Property : constant Byte_Array :=
        [1, 0,
         16#88#, 16#77#, 16#66#, 16#55#, 16#44#, 16#33#, 16#22#, 16#11#,
         16#00#, 16#ff#, 16#ee#, 16#dd#, 16#cc#, 16#bb#, 16#aa#, 16#99#];
      U32_Property : constant Byte_Array :=
        [1, 0, 16#78#, 16#56#, 16#34#, 16#12#, 16#ef#, 16#cd#, 16#ab#, 16#90#];
      Bitmap_U32_Property : constant Byte_Array :=
        [0, 16#80#, 16#78#, 16#56#, 16#34#, 16#12#];
      Names : constant Byte_Array :=
        [0,
         Character'Pos ('a'), 0, 0, 0,
         Character'Pos ('b'), 0, Character'Pos ('c'), 0, 0, 0];
      Has_Time  : Boolean := False;
      Time      : Unsigned_64 := 0;
      Has_Value : Boolean := False;
      Value     : Unsigned_32 := 0;
      Index     : Natural := 0;
   begin
      Assert
        (Zlib.Seven_Zip_Properties.Bit_Is_Set ([1 => 16#80#], 1, 1),
         "7z bitmap first bit was not recognized");
      Assert
        (not Zlib.Seven_Zip_Properties.Bit_Is_Set ([1 => 16#80#], 1, 2),
         "7z bitmap second bit was incorrectly recognized");
      Assert
        (Zlib.Seven_Zip_Properties.U64_LE (Time_Property, Time_Property'First + 2) =
           16#1122_3344_5566_7788#,
         "7z little-endian FILETIME reader mismatch");
      Assert
        (Zlib.Seven_Zip_Properties.U32_LE (U32_Property, U32_Property'First + 2) =
           16#1234_5678#,
         "7z little-endian UInt32 property reader mismatch");
      Assert
        (Zlib.Seven_Zip_Properties.Read_File_Time_Property
           (Time_Property, Time_Property'First, Time_Property'Length, 2, 2,
            Has_Time, Time),
         "7z FILETIME property reader rejected a valid property");
      Assert
        (Has_Time and then Time = 16#99AA_BBCC_DDEE_FF00#,
         "7z FILETIME property value mismatch");
      Assert
        (Zlib.Seven_Zip_Properties.Read_U32_Property
           (U32_Property, U32_Property'First, U32_Property'Length, 2, 2,
            Has_Value, Value),
         "7z UInt32 property reader rejected a valid all-defined property");
      Assert
        (Has_Value and then Value = 16#90AB_CDEF#,
         "7z UInt32 all-defined property value mismatch");
      Assert
        (Zlib.Seven_Zip_Properties.Read_U32_Property
           (Bitmap_U32_Property, Bitmap_U32_Property'First,
            Bitmap_U32_Property'Length, 2, 2, Has_Value, Value),
         "7z UInt32 bitmap property reader rejected a valid property");
      Assert
        (not Has_Value and then Value = 0,
         "7z UInt32 bitmap absent value mismatch");
      Assert
        (Zlib.Seven_Zip_Properties.Name_Index
           (Names, Names'First, Names'Length, 2, "bc", Index),
         "7z name index reader rejected a valid name property");
      Assert (Index = 2, "7z name index mismatch");
   end Test_Seven_Zip_Property_Helpers;

   overriding
   procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_Branch_Roundtrip'Access,
         "branch filter encode/decode round-trip");
      Registration.Register_Routine
        (T, Test_Delta_Roundtrip'Access,
         "delta filter encode/decode round-trip");
      Registration.Register_Routine
        (T, Test_Known_Answers'Access,
         "branch/delta interop known answers");
      Registration.Register_Routine
        (T, Test_Stock_7z_Decode'Access,
         "stock 7z branch-filtered archive decode");
      Registration.Register_Routine
        (T, Test_Stock_X86_ARM64_Decode'Access,
         "stock 7z x86 BCJ / ARM64 archive decode");
      Registration.Register_Routine
        (T, Test_Seven_Zip_Number_Encoding'Access,
         "7z UInt64 variable-length number encoding");
      Registration.Register_Routine
        (T, Test_Seven_Zip_Method_IDs'Access,
         "7z method ID classification");
      Registration.Register_Routine
        (T, Test_LZMA_Property_Helpers'Access,
         "LZMA property helper classification");
      Registration.Register_Routine
        (T, Test_LZMA_Core_Helpers'Access,
         "LZMA core helper state transitions");
      Registration.Register_Routine
        (T, Test_LZMA_Range_Encoder_Helpers'Access,
         "LZMA range encoder helper emission");
      Registration.Register_Routine
        (T, Test_LZMA_Match_Finder_Helpers'Access,
         "LZMA match finder helper indexing");
      Registration.Register_Routine
        (T, Test_LZMA_Literal_Helpers'Access,
         "LZMA literal helper pricing");
      Registration.Register_Routine
        (T, Test_LZMA_Repetition_Helpers'Access,
         "LZMA repetition helper pricing");
      Registration.Register_Routine
        (T, Test_LZMA_Parser_Helpers'Access,
         "LZMA parser helper backtracking");
      Registration.Register_Routine
        (T, Test_LZMA_Range_Decoder_Helpers'Access,
         "LZMA range decoder helper parsing");
      Registration.Register_Routine
        (T, Test_LZMA2_Framing_Helpers'Access,
         "LZMA2 chunk framing helpers");
      Registration.Register_Routine
        (T, Test_LZMA2_Decoder_Helpers'Access,
         "LZMA2 decoder helper lifecycle");
      Registration.Register_Routine
        (T, Test_Seven_Zip_Graph_Helpers'Access,
         "7z method graph helper validation");
      Registration.Register_Routine
        (T, Test_Seven_Zip_Property_Helpers'Access,
         "7z file property helper parsing");
   end Register_Tests;

end Zlib_Seven_Zip_Filter_Tests;
