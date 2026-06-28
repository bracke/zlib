with AUnit.Assertions; use AUnit.Assertions;
with Interfaces;       use Interfaces;
with Zlib;             use Zlib;
with Zlib.Seven_Zip_Filters; use Zlib.Seven_Zip_Filters;

package body Zlib_Seven_Zip_Filter_Tests is

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
   end Register_Tests;

end Zlib_Seven_Zip_Filter_Tests;
