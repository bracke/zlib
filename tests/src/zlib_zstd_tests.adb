with AUnit.Assertions; use AUnit.Assertions;

with Ada.Directories;
with Ada.Streams.Stream_IO;

with Interfaces;

with Zlib;
with Zlib.Zstd_Decoder;
with Zlib.Zstd_Encoder;
with Zlib.Zstd_XXH64;

with Zlib_Zstd_Fixtures;

package body Zlib_Zstd_Tests is

   use type Interfaces.Unsigned_64;
   use type Zlib.Byte;
   use type Zlib.Byte_Array;
   use type Zlib.Status_Code;

   overriding
   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib.Zstd codec");
   end Name;

   procedure Assert_Same
     (Got   : Zlib.Byte_Array;
      Want  : Zlib.Byte_Array;
      Label : String);

   procedure Assert_Same
     (Got   : Zlib.Byte_Array;
      Want  : Zlib.Byte_Array;
      Label : String) is
   begin
      Assert (Got'Length = Want'Length,
              Label & ": length must be" & Natural'Image (Want'Length)
              & ", got" & Natural'Image (Got'Length));

      for Index in 0 .. Natural'Min (Got'Length, Want'Length) - 1 loop
         Assert (Got (Got'First + Index) = Want (Want'First + Index),
                 Label & ": byte" & Natural'Image (Index) & " differs");
      end loop;
   end Assert_Same;

   procedure Assert_Decodes
     (Payload : Zlib.Byte_Array;
      Plain   : Zlib.Byte_Array;
      Label   : String);

   procedure Assert_Decodes
     (Payload : Zlib.Byte_Array;
      Plain   : Zlib.Byte_Array;
      Label   : String)
   is
      Status  : Zlib.Status_Code;
      Decoded : constant Zlib.Byte_Array :=
        Zlib.Zstd_Decoder.Decode (Payload, Status);
   begin
      Assert (Status = Zlib.Ok,
              Label & ": status must be Ok, got "
              & Zlib.Status_Code'Image (Status));
      Assert_Same (Decoded, Plain, Label);
   end Assert_Decodes;

   procedure Assert_Round_Trip
     (Plain : Zlib.Byte_Array;
      Label : String);

   procedure Assert_Round_Trip
     (Plain : Zlib.Byte_Array;
      Label : String)
   is
      Encode_Status : Zlib.Status_Code;
      Coded : constant Zlib.Byte_Array :=
        Zlib.Zstd_Encoder.Encode (Plain, Encode_Status);
   begin
      Assert (Encode_Status = Zlib.Ok,
              Label & ": encode must be Ok, got "
              & Zlib.Status_Code'Image (Encode_Status));
      Assert_Decodes (Coded, Plain, Label & " round trip");
   end Assert_Round_Trip;

   --  Decoding streams from the real encoder.

   procedure Test_Stock_Empty (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Empty : constant Zlib.Byte_Array (1 .. 0) := [others => 0];
   begin
      Assert_Decodes (Zlib_Zstd_Fixtures.Empty_ZST, Empty, "stock empty");
   end Test_Stock_Empty;

   procedure Test_Stock_Hello (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Decodes
        (Zlib_Zstd_Fixtures.Hello_ZST, Zlib_Zstd_Fixtures.Hello_Plain,
         "stock hello");
   end Test_Stock_Hello;

   procedure Test_Stock_Runs (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Decodes
        (Zlib_Zstd_Fixtures.Runs_ZST, Zlib_Zstd_Fixtures.Runs_Plain,
         "stock runs");
   end Test_Stock_Runs;

   procedure Test_Stock_Noise (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      --  Incompressible: exercises raw literals and raw blocks.
      Assert_Decodes
        (Zlib_Zstd_Fixtures.Noise_ZST, Zlib_Zstd_Fixtures.Noise_Plain,
         "stock noise");
   end Test_Stock_Noise;

   procedure Test_Stock_Level_1 (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_Decodes
        (Zlib_Zstd_Fixtures.Level1_ZST,
         Zlib_Zstd_Fixtures.Pattern_Plain (200_000),
         "stock level 1");
   end Test_Stock_Level_1;

   procedure Test_Stock_Level_19 (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Level 19 turns on zstd's block splitter, so blocks stop being uniform
      --  and start reusing entropy tables across one another. This is the case
      --  that caught the FSE end-of-stream rule.
      Assert_Decodes
        (Zlib_Zstd_Fixtures.Multi_ZST,
         Zlib_Zstd_Fixtures.Pattern_Plain (300_000),
         "stock level 19");
   end Test_Stock_Level_19;

   --  Our own encoder, checked by our own decoder.

   procedure Test_Round_Trips (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Empty  : constant Zlib.Byte_Array (1 .. 0) := [others => 0];
      Single : constant Zlib.Byte_Array (1 .. 1) := [16#5A#];
      Repeat : constant Zlib.Byte_Array (1 .. 200_000) := [others => 16#41#];
   begin
      Assert_Round_Trip (Empty, "empty");
      Assert_Round_Trip (Single, "one byte");
      Assert_Round_Trip (Zlib_Zstd_Fixtures.Hello_Plain, "hello");
      Assert_Round_Trip (Zlib_Zstd_Fixtures.Runs_Plain, "runs");
      --  Incompressible, so the encoder must fall back to stored blocks.
      Assert_Round_Trip (Zlib_Zstd_Fixtures.Noise_Plain, "noise");
      --  Longer than one block, so this covers the block loop.
      Assert_Round_Trip
        (Zlib_Zstd_Fixtures.Pattern_Plain (300_000), "multi-block pattern");
      Assert_Round_Trip (Repeat, "one repeated byte");
   end Test_Round_Trips;

   procedure Test_Compresses (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Plain  : constant Zlib.Byte_Array :=
        Zlib_Zstd_Fixtures.Pattern_Plain (200_000);
      Status : Zlib.Status_Code;
      Coded  : constant Zlib.Byte_Array :=
        Zlib.Zstd_Encoder.Encode (Plain, Status);
   begin
      Assert (Status = Zlib.Ok, "encode must be Ok");
      --  A repeating pattern must actually compress, not merely round trip.
      Assert (Coded'Length < Plain'Length / 100,
              "200k of a repeating pattern must compress hard, got"
              & Natural'Image (Coded'Length) & " bytes");
   end Test_Compresses;

   procedure Test_Rejects_Bad_Magic
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Bad    : Zlib.Byte_Array := Zlib_Zstd_Fixtures.Hello_ZST;
      Status : Zlib.Status_Code;
   begin
      Bad (Bad'First) := 16#00#;
      declare
         Decoded : constant Zlib.Byte_Array :=
           Zlib.Zstd_Decoder.Decode (Bad, Status);
      begin
         Assert (Status = Zlib.Invalid_Header,
                 "a corrupt magic must give Invalid_Header, got "
                 & Zlib.Status_Code'Image (Status));
         Assert (Decoded'Length = 0, "a failed decode must return no bytes");
      end;
   end Test_Rejects_Bad_Magic;

   procedure Test_Rejects_Truncation
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Full   : constant Zlib.Byte_Array := Zlib_Zstd_Fixtures.Multi_ZST;
      Cut    : constant Zlib.Byte_Array :=
        Full (Full'First .. Full'Last - 20);
      Status : Zlib.Status_Code;
   begin
      declare
         Decoded : constant Zlib.Byte_Array :=
           Zlib.Zstd_Decoder.Decode (Cut, Status);
      begin
         Assert (Status /= Zlib.Ok,
                 "a truncated stream must not decode as Ok");
         Assert (Decoded'Length = 0, "a failed decode must return no bytes");
      end;
   end Test_Rejects_Truncation;

   procedure Test_XXH64 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Empty : constant Zlib.Byte_Array (1 .. 0) := [others => 0];
      Abc   : constant Zlib.Byte_Array (1 .. 3) :=
        [Character'Pos ('a'), Character'Pos ('b'), Character'Pos ('c')];
   begin
      --  zstd's content checksum is XXH64, not the XXH3 CryptoLib offers.
      Assert (Zlib.Zstd_XXH64.Compute (Empty) = 16#EF46_DB37_51D8_E999#,
              "XXH64 of the empty input must be 16#EF46DB3751D8E999#");
      Assert (Zlib.Zstd_XXH64.Compute (Abc) = 16#44BC_2CF5_AD77_0999#,
              "XXH64 of ""abc"" must be 16#44BC2CF5AD770999#");
   end Test_XXH64;

   ----------------------------------------------------------------------------
   --  Hand-built frames. Each is the smallest stream that reaches one rule.
   --
   --  Frame header: magic 28 B5 2F FD, descriptor 20 (single segment, one-byte
   --  content size, no checksum), then the content size. Block header: three
   --  bytes little-endian, Last + 2 * Kind + 8 * Size. A compressed block here
   --  carries raw literals (header byte 8 * count), one sequence (01), RLE mode
   --  for all three tables (54) with literal, offset and match codes, then the
   --  backward bitstream: the extra bits below a high end-mark bit.
   ----------------------------------------------------------------------------

   --  "ABCDEFGHIJ" as a raw block.
   Frame_ABCDEFGHIJ : constant Zlib.Byte_Array :=
     [16#28#, 16#B5#, 16#2F#, 16#FD#, 16#20#, 16#0A#,
      16#51#, 16#00#, 16#00#,
      16#41#, 16#42#, 16#43#, 16#44#, 16#45#,
      16#46#, 16#47#, 16#48#, 16#49#, 16#4A#];

   --  Literals "VWXYZ", then a match of 3 at offset 5 (offset code 3, extra
   --  bits 000): "VWXYZVWX". Leaves 5 as the first repeat offset.
   Frame_VWXYZVWX : constant Zlib.Byte_Array :=
     [16#28#, 16#B5#, 16#2F#, 16#FD#, 16#20#, 16#08#,
      16#65#, 16#00#, 16#00#,
      16#28#, 16#56#, 16#57#, 16#58#, 16#59#, 16#5A#,
      16#01#, 16#54#, 16#05#, 16#03#, 16#00#, 16#08#];

   --  No literals, then a match of 3 at offset 5: within this frame there is
   --  nothing to copy from, so it can only be satisfied from a frame before.
   Frame_Reaches_Back : constant Zlib.Byte_Array :=
     [16#28#, 16#B5#, 16#2F#, 16#FD#, 16#20#, 16#03#,
      16#3D#, 16#00#, 16#00#,
      16#00#,
      16#01#, 16#54#, 16#00#, 16#03#, 16#00#, 16#08#];

   --  Literals "VW", then a match of 3 at repeat offset 1 (offset code 0). A
   --  fresh frame's first repeat offset is 1: "VWWWW". Had the repeat offsets
   --  carried over from Frame_VWXYZVWX, it would name offset 5 instead.
   Frame_VWWWW : constant Zlib.Byte_Array :=
     [16#28#, 16#B5#, 16#2F#, 16#FD#, 16#20#, 16#05#,
      16#4D#, 16#00#, 16#00#,
      16#10#, 16#56#, 16#57#,
      16#01#, 16#54#, 16#02#, 16#00#, 16#00#, 16#01#];

   --  Literals "VWXYZ" and a sequence whose three tables are all "repeat the
   --  previous block's": in a frame's first block there is none, whatever an
   --  earlier frame defined.
   Frame_Repeats_Tables : constant Zlib.Byte_Array :=
     [16#28#, 16#B5#, 16#2F#, 16#FD#, 16#20#, 16#08#,
      16#4D#, 16#00#, 16#00#,
      16#28#, 16#56#, 16#57#, 16#58#, 16#59#, 16#5A#,
      16#01#, 16#FC#, 16#08#];

   procedure Write_File (Path : String; Data : Zlib.Byte_Array);

   procedure Write_File (Path : String; Data : Zlib.Byte_Array) is
      File : Ada.Streams.Stream_IO.File_Type;
   begin
      Ada.Streams.Stream_IO.Create (File, Ada.Streams.Stream_IO.Out_File, Path);
      for Item of Data loop
         Ada.Streams.Stream_Element'Write
           (Ada.Streams.Stream_IO.Stream (File),
            Ada.Streams.Stream_Element (Item));
      end loop;
      Ada.Streams.Stream_IO.Close (File);
   end Write_File;

   procedure Assert_Rejects
     (Payload : Zlib.Byte_Array;
      Want    : Zlib.Status_Code;
      Label   : String);
   --  Payload must decode to Want and no bytes -- not raise -- both through the
   --  decoder and through Zstd_File_To_Consumer, where an escaped exception
   --  used to surface as Input_File_Error.

   procedure Assert_Rejects
     (Payload : Zlib.Byte_Array;
      Want    : Zlib.Status_Code;
      Label   : String)
   is
      Path      : constant String := "zlib_zstd_malformed.zst";
      Status    : Zlib.Status_Code := Zlib.Ok;
      Length    : Natural := 0;
      Escaped   : Boolean := False;
      Size      : Interfaces.Unsigned_64 := 0;
      Delivered : Boolean := False;

      procedure Take (Bytes : Zlib.Byte_Array; Continue : in out Boolean);

      procedure Take (Bytes : Zlib.Byte_Array; Continue : in out Boolean) is
         pragma Unreferenced (Bytes, Continue);
      begin
         Delivered := True;
      end Take;
   begin
      begin
         declare
            Decoded : constant Zlib.Byte_Array :=
              Zlib.Zstd_Decoder.Decode (Payload, Status);
         begin
            Length := Decoded'Length;
         end;
      exception
         when others =>
            Escaped := True;
      end;

      Assert (not Escaped, Label & ": the decoder must report a status, not raise");
      Assert (Status = Want,
              Label & ": expected " & Zlib.Status_Code'Image (Want)
              & ", got " & Zlib.Status_Code'Image (Status));
      Assert (Length = 0, Label & ": a failed decode must return no bytes");

      Write_File (Path, Payload);
      Zlib.Zstd_File_To_Consumer (Path, Payload'Length, Take'Access, Size, Status);
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;

      Assert (Status = Want,
              Label & " (file): expected " & Zlib.Status_Code'Image (Want)
              & ", got " & Zlib.Status_Code'Image (Status));
      Assert (Size = 0 and then not Delivered,
              Label & " (file): a failed decode must deliver nothing");
   end Assert_Rejects;

   procedure Test_Rejects_Oversized_Offset_Codes
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Offset code 31: 2 ** 31 does not fit a Natural.
      Code_31 : constant Zlib.Byte_Array :=
        [16#28#, 16#B5#, 16#2F#, 16#FD#, 16#20#, 16#08#,
         16#65#, 16#00#, 16#00#,
         16#28#, 16#56#, 16#57#, 16#58#, 16#59#, 16#5A#,
         16#01#, 16#54#, 16#05#, 16#1F#, 16#00#, 16#08#];
      --  Offset code 30 with thirty zero extra bits: 2 ** 30 fits, and is far
      --  past the five bytes of output.
      Code_30 : constant Zlib.Byte_Array :=
        [16#28#, 16#B5#, 16#2F#, 16#FD#, 16#20#, 16#08#,
         16#7D#, 16#00#, 16#00#,
         16#28#, 16#56#, 16#57#, 16#58#, 16#59#, 16#5A#,
         16#01#, 16#54#, 16#05#, 16#1E#, 16#00#,
         16#00#, 16#00#, 16#00#, 16#40#];
   begin
      Assert_Rejects (Code_31, Zlib.Invalid_Distance, "offset code 31");
      Assert_Rejects (Code_30, Zlib.Invalid_Distance, "offset code 30");
   end Test_Rejects_Oversized_Offset_Codes;

   procedure Test_Rejects_Oversized_Skippable_Frames
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Sizes of 2 ** 31 and 2 ** 32 - 1 overflow a Natural; neither frame's
      --  bytes are present.
      Half : constant Zlib.Byte_Array :=
        [16#50#, 16#2A#, 16#4D#, 16#18#, 16#00#, 16#00#, 16#00#, 16#80#];
      Full : constant Zlib.Byte_Array :=
        [16#5F#, 16#2A#, 16#4D#, 16#18#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#00#];
      --  A small size whose bytes are cut short is truncation as well.
      Short : constant Zlib.Byte_Array :=
        [16#50#, 16#2A#, 16#4D#, 16#18#, 16#03#, 16#00#, 16#00#, 16#00#,
         16#AA#, 16#BB#];
      --  And a whole skippable frame is still skipped.
      Skipped : constant Zlib.Byte_Array :=
        Zlib.Byte_Array'[16#50#, 16#2A#, 16#4D#, 16#18#, 16#02#, 16#00#, 16#00#, 16#00#,
         16#AA#, 16#BB#] & Frame_ABCDEFGHIJ;
      Want : constant Zlib.Byte_Array :=
        [16#41#, 16#42#, 16#43#, 16#44#, 16#45#,
         16#46#, 16#47#, 16#48#, 16#49#, 16#4A#];
   begin
      Assert_Rejects (Half, Zlib.Unexpected_End_Of_Input, "skippable size 2 ** 31");
      Assert_Rejects (Full, Zlib.Unexpected_End_Of_Input, "skippable size 2 ** 32 - 1");
      Assert_Rejects (Short, Zlib.Unexpected_End_Of_Input, "truncated skippable frame");
      Assert_Decodes (Skipped, Want, "a skippable frame before a frame");
   end Test_Rejects_Oversized_Skippable_Frames;

   procedure Test_Rejects_Empty_Compressed_Block
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  A last compressed block of size 0, at the very end of the input.
      At_End : constant Zlib.Byte_Array :=
        [16#28#, 16#B5#, 16#2F#, 16#FD#, 16#20#, 16#00#,
         16#05#, 16#00#, 16#00#];
      --  The same with bytes after it, which must not be read as its body.
      Before_More : constant Zlib.Byte_Array :=
        At_End & Zlib.Byte_Array'[16#00#, 16#00#, 16#00#, 16#00#];
   begin
      Assert_Rejects (At_End, Zlib.Invalid_Block_Type, "empty compressed block at the end");
      Assert_Rejects (Before_More, Zlib.Invalid_Block_Type, "empty compressed block");
   end Test_Rejects_Empty_Compressed_Block;

   procedure Test_Frames_Are_Independent
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Expected : constant Zlib.Byte_Array :=
        [16#41#, 16#42#, 16#43#, 16#44#, 16#45#,
         16#46#, 16#47#, 16#48#, 16#49#, 16#4A#,
         16#56#, 16#57#, 16#58#, 16#59#, 16#5A#, 16#56#, 16#57#, 16#58#,
         16#56#, 16#57#, 16#57#, 16#57#, 16#57#];
   begin
      --  The hand-built frames are sound on their own terms.
      Assert_Decodes
        (Frame_ABCDEFGHIJ & Frame_VWXYZVWX & Frame_VWWWW, Expected,
         "three hand-built frames");

      --  A match may not reach into the frame before: this one would copy
      --  "FGH" out of "ABCDEFGHIJ" were the window shared.
      Assert_Rejects
        (Frame_ABCDEFGHIJ & Frame_Reaches_Back, Zlib.Invalid_Distance,
         "a match reaching into the previous frame");

      --  Nor may a block lean on the previous frame's entropy tables.
      Assert_Rejects
        (Frame_VWXYZVWX & Frame_Repeats_Tables, Zlib.Invalid_Huffman_Code,
         "repeat tables at the start of a frame");
   end Test_Frames_Are_Independent;

   procedure Test_Multi_Frame_Round_Trip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status_1 : Zlib.Status_Code;
      Status_2 : Zlib.Status_Code;
      Status_3 : Zlib.Status_Code;
      Plain_1  : constant Zlib.Byte_Array := Zlib_Zstd_Fixtures.Pattern_Plain (150_000);
      Plain_2  : constant Zlib.Byte_Array := Zlib_Zstd_Fixtures.Hello_Plain;
      Plain_3  : constant Zlib.Byte_Array := Zlib_Zstd_Fixtures.Noise_Plain;
      Coded_1  : constant Zlib.Byte_Array := Zlib.Zstd_Encoder.Encode (Plain_1, Status_1);
      Coded_2  : constant Zlib.Byte_Array := Zlib.Zstd_Encoder.Encode (Plain_2, Status_2);
      Coded_3  : constant Zlib.Byte_Array := Zlib.Zstd_Encoder.Encode (Plain_3, Status_3);
      Joined   : constant Zlib.Byte_Array := Coded_1 & Coded_2 & Coded_3;
      Damaged  : Zlib.Byte_Array := Joined;
   begin
      Assert (Status_1 = Zlib.Ok and then Status_2 = Zlib.Ok and then Status_3 = Zlib.Ok,
              "fixture: every frame must encode");

      --  Each frame carries a content checksum of its own content only.
      Assert_Decodes (Joined, Plain_1 & Plain_2 & Plain_3, "three encoded frames");

      --  The last four bytes are the last frame's checksum.
      Damaged (Damaged'Last) := Damaged (Damaged'Last) xor 16#01#;
      Assert_Rejects (Damaged, Zlib.Invalid_Checksum, "a damaged last-frame checksum");
   end Test_Multi_Frame_Round_Trip;

   procedure Test_XXH64_Streaming
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Data   : constant Zlib.Byte_Array := Zlib_Zstd_Fixtures.Pattern_Plain (1_000);
      Splits : constant array (1 .. 8) of Positive := [1, 3, 7, 31, 32, 33, 100, 1_000];
      Totals : constant array (1 .. 8) of Natural := [0, 5, 31, 32, 33, 64, 999, 1_000];
   begin
      for Total of Totals loop
         declare
            Whole : constant Interfaces.Unsigned_64 :=
              Zlib.Zstd_XXH64.Compute (Data (Data'First .. Data'First + Total - 1));
         begin
            for Step of Splits loop
               declare
                  S    : Zlib.Zstd_XXH64.State;
                  Next : Natural := Data'First;
                  Stop : constant Natural := Data'First + Total;
               begin
                  Zlib.Zstd_XXH64.Reset (S);
                  while Next < Stop loop
                     declare
                        Take : constant Natural := Natural'Min (Step, Stop - Next);
                     begin
                        Zlib.Zstd_XXH64.Update (S, Data (Next .. Next + Take - 1));
                        Next := Next + Take;
                     end;
                  end loop;
                  Assert (Zlib.Zstd_XXH64.Digest (S) = Whole,
                          "XXH64 of" & Natural'Image (Total) & " bytes fed"
                          & Natural'Image (Step) & " at a time must match");
               end;
            end loop;
         end;
      end loop;
   end Test_XXH64_Streaming;

   overriding
   procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_XXH64'Access,
                        "XXH64 matches the published vectors");
      Register_Routine (T, Test_Stock_Empty'Access,
                        "decodes a stock empty frame");
      Register_Routine (T, Test_Stock_Hello'Access,
                        "decodes a stock zstd frame");
      Register_Routine (T, Test_Stock_Runs'Access,
                        "decodes stock long runs");
      Register_Routine (T, Test_Stock_Noise'Access,
                        "decodes stock incompressible data");
      Register_Routine (T, Test_Stock_Level_1'Access,
                        "decodes a stock level 1 stream");
      Register_Routine (T, Test_Stock_Level_19'Access,
                        "decodes a stock level 19 stream (block splitter)");
      Register_Routine (T, Test_Round_Trips'Access,
                        "round trips through encode and decode");
      Register_Routine (T, Test_Compresses'Access,
                        "actually compresses a repeating pattern");
      Register_Routine (T, Test_Rejects_Bad_Magic'Access,
                        "rejects a corrupt magic");
      Register_Routine (T, Test_Rejects_Truncation'Access,
                        "rejects a truncated stream");
      Register_Routine (T, Test_XXH64_Streaming'Access,
                        "XXH64 fed piecewise matches the one-shot hash");
      Register_Routine (T, Test_Rejects_Oversized_Offset_Codes'Access,
                        "rejects offset codes past what a Natural holds");
      Register_Routine (T, Test_Rejects_Oversized_Skippable_Frames'Access,
                        "rejects skippable frames longer than the input");
      Register_Routine (T, Test_Rejects_Empty_Compressed_Block'Access,
                        "rejects an empty compressed block");
      Register_Routine (T, Test_Frames_Are_Independent'Access,
                        "decodes each frame independently of the one before");
      Register_Routine (T, Test_Multi_Frame_Round_Trip'Access,
                        "decodes concatenated frames, each with its checksum");
   end Register_Tests;

end Zlib_Zstd_Tests;
