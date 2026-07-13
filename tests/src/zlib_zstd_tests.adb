with AUnit.Assertions; use AUnit.Assertions;

with Interfaces;

with Zlib;
with Zlib.Zstd_Decoder;
with Zlib.Zstd_Encoder;
with Zlib.Zstd_XXH64;

with Zlib_Zstd_Fixtures;

package body Zlib_Zstd_Tests is

   use type Interfaces.Unsigned_64;
   use type Zlib.Byte;
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
   end Register_Tests;

end Zlib_Zstd_Tests;
