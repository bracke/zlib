with AUnit.Assertions; use AUnit.Assertions;

with Interfaces;

with Zlib;
with Zlib.BZip2_CRC;
with Zlib.BZip2_Decoder;

with Zlib_BZip2_Fixtures;

package body Zlib_BZip2_Tests is

   use type Interfaces.Unsigned_32;
   use type Zlib.Byte;
   use type Zlib.Status_Code;

   overriding
   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib.BZip2 decoder");
   end Name;

   procedure Assert_Decodes
     (Payload : Zlib.Byte_Array;
      Plain   : Zlib.Byte_Array;
      Label   : String);
   --  Decode Payload and assert it reproduces Plain exactly.

   procedure Assert_Decodes
     (Payload : Zlib.Byte_Array;
      Plain   : Zlib.Byte_Array;
      Label   : String)
   is
      Status  : Zlib.Status_Code;
      Decoded : constant Zlib.Byte_Array :=
        Zlib.BZip2_Decoder.Decode (Payload, Status);
   begin
      Assert (Status = Zlib.Ok,
              Label & ": status must be Ok, got "
              & Zlib.Status_Code'Image (Status));
      Assert (Decoded'Length = Plain'Length,
              Label & ": length must be" & Natural'Image (Plain'Length)
              & ", got" & Natural'Image (Decoded'Length));

      for Index in 0 .. Natural'Min (Decoded'Length, Plain'Length) - 1 loop
         Assert
           (Decoded (Decoded'First + Index) = Plain (Plain'First + Index),
            Label & ": byte" & Natural'Image (Index) & " differs");
      end loop;
   end Assert_Decodes;

   procedure Test_Empty_Stream (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Empty : constant Zlib.Byte_Array (1 .. 0) := [others => 0];
   begin
      --  A bzip2 stream of no data: header and trailer, not a single block.
      Assert_Decodes (Zlib_BZip2_Fixtures.Empty_BZ2, Empty, "empty");
   end Test_Empty_Stream;

   procedure Test_Hello (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Decodes
        (Zlib_BZip2_Fixtures.Hello_BZ2,
         Zlib_BZip2_Fixtures.Hello_Plain,
         "hello");
   end Test_Hello;

   procedure Test_Runs (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      --  Long runs exercise the initial run-length coding, where four equal
      --  bytes are followed by a repeat count.
      Assert_Decodes
        (Zlib_BZip2_Fixtures.Runs_BZ2,
         Zlib_BZip2_Fixtures.Runs_Plain,
         "runs");
   end Test_Runs;

   procedure Test_Noise (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      --  251 distinct symbols, so the block needs several Huffman groups and a
      --  non-trivial selector list.
      Assert_Decodes
        (Zlib_BZip2_Fixtures.Noise_BZ2,
         Zlib_BZip2_Fixtures.Noise_Plain,
         "noise");
   end Test_Noise;

   procedure Test_Multi_Block (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      --  250_000 bytes at level 1 spans three blocks, so this also covers the
      --  combined stream CRC.
      Assert_Decodes
        (Zlib_BZip2_Fixtures.Multi_BZ2,
         Zlib_BZip2_Fixtures.Multi_Plain,
         "multi-block");
   end Test_Multi_Block;

   procedure Test_Concatenated (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      --  Two whole streams back to back, which bzip2(1) itself accepts.
      Assert_Decodes
        (Zlib_BZip2_Fixtures.Concat_BZ2,
         Zlib_BZip2_Fixtures.Concat_Plain,
         "concatenated");
   end Test_Concatenated;

   procedure Test_Rejects_Bad_Header
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Bad    : Zlib.Byte_Array := Zlib_BZip2_Fixtures.Hello_BZ2;
      Status : Zlib.Status_Code;
   begin
      Bad (Bad'First) := 16#00#;
      declare
         Decoded : constant Zlib.Byte_Array :=
           Zlib.BZip2_Decoder.Decode (Bad, Status);
      begin
         Assert (Status = Zlib.Invalid_Header,
                 "a corrupt signature must give Invalid_Header, got "
                 & Zlib.Status_Code'Image (Status));
         Assert (Decoded'Length = 0, "a failed decode must return no bytes");
      end;
   end Test_Rejects_Bad_Header;

   procedure Test_Rejects_Bad_CRC
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Bad    : Zlib.Byte_Array := Zlib_BZip2_Fixtures.Hello_BZ2;
      Status : Zlib.Status_Code;
   begin
      --  Flip a bit in the block's stored CRC (the four bytes after the block
      --  magic, which itself follows the four-byte stream header).
      Bad (Bad'First + 10) := Bad (Bad'First + 10) xor 16#01#;
      declare
         Decoded : constant Zlib.Byte_Array :=
           Zlib.BZip2_Decoder.Decode (Bad, Status);
      begin
         Assert (Status = Zlib.Invalid_Checksum,
                 "a corrupt block CRC must give Invalid_Checksum, got "
                 & Zlib.Status_Code'Image (Status));
         Assert (Decoded'Length = 0, "a failed decode must return no bytes");
      end;
   end Test_Rejects_Bad_CRC;

   procedure Test_Rejects_Truncation
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Full   : constant Zlib.Byte_Array := Zlib_BZip2_Fixtures.Noise_BZ2;
      Cut    : constant Zlib.Byte_Array :=
        Full (Full'First .. Full'Last - 40);
      Status : Zlib.Status_Code;
   begin
      declare
         Decoded : constant Zlib.Byte_Array :=
           Zlib.BZip2_Decoder.Decode (Cut, Status);
      begin
         Assert (Status /= Zlib.Ok,
                 "a truncated stream must not decode as Ok");
         Assert (Decoded'Length = 0, "a failed decode must return no bytes");
      end;
   end Test_Rejects_Truncation;

   procedure Test_CRC_Is_Unreflected
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Data : constant Zlib.Byte_Array (1 .. 9) :=
        [Character'Pos ('1'), Character'Pos ('2'), Character'Pos ('3'),
         Character'Pos ('4'), Character'Pos ('5'), Character'Pos ('6'),
         Character'Pos ('7'), Character'Pos ('8'), Character'Pos ('9')];
   begin
      --  bzip2's MSB-first CRC-32 of "123456789" is 0xFC891918. The reflected
      --  variant the rest of the crate uses gives 0xCBF43926 -- a different
      --  value, which is the whole reason this unit exists.
      Assert (Zlib.BZip2_CRC.Compute (Data) = 16#FC89_1918#,
              "bzip2 CRC-32 of ""123456789"" must be 16#FC891918#");
   end Test_CRC_Is_Unreflected;

   overriding
   procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_CRC_Is_Unreflected'Access,
                        "bzip2 CRC-32 is the unreflected variant");
      Register_Routine (T, Test_Empty_Stream'Access,
                        "decodes a stream with no blocks");
      Register_Routine (T, Test_Hello'Access,
                        "decodes a stock bzip2 stream");
      Register_Routine (T, Test_Runs'Access,
                        "decodes long runs through RLE1");
      Register_Routine (T, Test_Noise'Access,
                        "decodes multi-group, multi-selector data");
      Register_Routine (T, Test_Multi_Block'Access,
                        "decodes a multi-block stream and its combined CRC");
      Register_Routine (T, Test_Concatenated'Access,
                        "decodes concatenated streams");
      Register_Routine (T, Test_Rejects_Bad_Header'Access,
                        "rejects a corrupt signature");
      Register_Routine (T, Test_Rejects_Bad_CRC'Access,
                        "rejects a corrupt block CRC");
      Register_Routine (T, Test_Rejects_Truncation'Access,
                        "rejects a truncated stream");
   end Register_Tests;

end Zlib_BZip2_Tests;
