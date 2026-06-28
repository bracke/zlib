with AUnit.Assertions; use AUnit.Assertions;
with Interfaces;
with Zlib; use Zlib;
with Zlib.Fuzzing;

package body Zlib_Fuzz_Smoke_Tests is

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib deterministic fuzz smoke tests");
   end Name;

   procedure Test_Same_Seed_Reproduces_Result
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Left  : constant Zlib.Fuzzing.Fuzz_Result :=
        Zlib.Fuzzing.Run (Zlib.Fuzzing.Inflate_Target, 63, 24);
      Right : constant Zlib.Fuzzing.Fuzz_Result :=
        Zlib.Fuzzing.Run (Zlib.Fuzzing.Inflate_Target, 63, 24);
   begin
      Assert
        (Zlib.Fuzzing.Same_Result (Left, Right),
         "same fuzz target, seed, and iteration count must reproduce summary");
      Assert (Left.Crashes = 0, "inflate smoke fuzz must not raise unexpected exceptions");
   end Test_Same_Seed_Reproduces_Result;

   procedure Test_Corrupted_Stream_Fails_Deterministically
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Payload : constant Zlib.Byte_Array := [0 => 16#41#, 1 => 16#42#, 2 => 16#43#];
      Status  : Zlib.Status_Code;
      Seed    : Interfaces.Unsigned_32 := 1;
   begin
      declare
         Valid  : constant Zlib.Byte_Array := Zlib.Deflate (Payload, Zlib.Fixed, Status);
      begin
         Assert (Status = Zlib.Ok, "fixture compression must succeed before mutation");
         declare
            Broken : constant Zlib.Byte_Array := Zlib.Fuzzing.Mutated (Valid, Seed, 4);
            Plain  : constant Zlib.Byte_Array := Zlib.Inflate (Broken, Status);
         begin
            pragma Unreferenced (Plain);
            Assert
              (Status /= Zlib.Ok,
               "single-bit corrupted stream should fail deterministically in smoke fixture");
         end;
      end;
   end Test_Corrupted_Stream_Fails_Deterministically;

   procedure Test_Roundtrip_Fuzzer_Smoke
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Result : constant Zlib.Fuzzing.Fuzz_Result :=
        Zlib.Fuzzing.Run (Zlib.Fuzzing.Compress_Roundtrip_Target, 630, 20);
   begin
      Assert (Result.Runs = 20, "roundtrip fuzz smoke must execute requested iterations");
      Assert (Result.Crashes = 0, "roundtrip fuzz smoke must not crash");
      Assert (Result.Success > 0, "roundtrip fuzz smoke must exercise successful cases");
   end Test_Roundtrip_Fuzzer_Smoke;

   procedure Test_Lifecycle_Fuzzer_Smoke
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Result : constant Zlib.Fuzzing.Fuzz_Result :=
        Zlib.Fuzzing.Run (Zlib.Fuzzing.Lifecycle_Target, 631, 4);
   begin
      Assert (Result.Crashes = 0, "lifecycle fuzz smoke must report deterministic exceptions only");
      Assert
        (Result.Success > 0,
         "lifecycle fuzz smoke must exercise documented Status_Error paths");
   end Test_Lifecycle_Fuzzer_Smoke;

   procedure Test_Mutation_And_Tiny_Buffer_Fuzzers_Smoke
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Mutation : constant Zlib.Fuzzing.Fuzz_Result :=
        Zlib.Fuzzing.Run (Zlib.Fuzzing.Mutation_Target, 632, 12);
      Tiny     : constant Zlib.Fuzzing.Fuzz_Result :=
        Zlib.Fuzzing.Run (Zlib.Fuzzing.Tiny_Buffer_Target, 633, 12);
   begin
      Assert (Mutation.Runs = 12, "mutation fuzz smoke must execute requested iterations");
      Assert (Tiny.Runs = 12, "tiny-buffer fuzz smoke must execute requested iterations");
      Assert (Mutation.Crashes = 0, "mutation fuzz smoke must not crash");
      Assert (Tiny.Crashes = 0, "tiny-buffer fuzz smoke must not crash");
   end Test_Mutation_And_Tiny_Buffer_Fuzzers_Smoke;

   procedure Test_All_Targets_Reproduce_Summaries
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      for Target in Zlib.Fuzzing.Target_Kind loop
         declare
            Left  : constant Zlib.Fuzzing.Fuzz_Result :=
              Zlib.Fuzzing.Run
                (Target,
                 Interfaces.Unsigned_32
                   (1_000 + Zlib.Fuzzing.Target_Kind'Pos (Target)),
                 6);
            Right : constant Zlib.Fuzzing.Fuzz_Result :=
              Zlib.Fuzzing.Run
                (Target,
                 Interfaces.Unsigned_32
                   (1_000 + Zlib.Fuzzing.Target_Kind'Pos (Target)),
                 6);
         begin
            Assert
              (Zlib.Fuzzing.Same_Result (Left, Right),
               "every fuzz target must reproduce its summary from seed");
            Assert
              (Left.Crashes = 0,
               "deterministic fuzz target must not record unexpected crashes");
         end;
      end loop;
   end Test_All_Targets_Reproduce_Summaries;

   procedure Test_Wrappers_Metadata_Dictionaries_And_Levels_Smoke
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Wrappers : constant Zlib.Fuzzing.Fuzz_Result :=
        Zlib.Fuzzing.Run (Zlib.Fuzzing.Wrapper_Mix_Target, 634, 12);
      Metadata : constant Zlib.Fuzzing.Fuzz_Result :=
        Zlib.Fuzzing.Run (Zlib.Fuzzing.GZip_Metadata_Target, 635, 12);
      Dicts    : constant Zlib.Fuzzing.Fuzz_Result :=
        Zlib.Fuzzing.Run (Zlib.Fuzzing.Dictionary_Target, 636, 12);
      Levels   : constant Zlib.Fuzzing.Fuzz_Result :=
        Zlib.Fuzzing.Run (Zlib.Fuzzing.Compression_Level_Target, 637, 12);
   begin
      Assert (Wrappers.Runs = 12, "wrapper fuzz smoke must execute requested iterations");
      Assert (Metadata.Runs = 12, "gzip metadata fuzz smoke must execute requested iterations");
      Assert (Dicts.Runs = 12, "dictionary fuzz smoke must execute requested iterations");
      Assert (Levels.Runs = 12, "compression-level fuzz smoke must execute requested iterations");
      Assert (Wrappers.Crashes = 0, "wrapper fuzz smoke must not crash");
      Assert (Metadata.Crashes = 0, "gzip metadata fuzz smoke must not crash");
      Assert (Dicts.Crashes = 0, "dictionary fuzz smoke must not crash");
      Assert (Levels.Crashes = 0, "compression-level fuzz smoke must not crash");
   end Test_Wrappers_Metadata_Dictionaries_And_Levels_Smoke;

   procedure Test_Target_Acceptance_Policy
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Clean  : constant Zlib.Fuzzing.Fuzz_Result :=
        (Runs              => 1,
         Success           => 1,
         Failures          => 0,
         Crashes           => 0,
         Digest            => 0,
         Last_Input_Length => 0,
         Last_Hex_Length   => 0,
         Last_Hex          => [others => ' ']);
      Failed : constant Zlib.Fuzzing.Fuzz_Result :=
        (Runs              => 1,
         Success           => 0,
         Failures          => 1,
         Crashes           => 0,
         Digest            => 0,
         Last_Input_Length => 0,
         Last_Hex_Length   => 0,
         Last_Hex          => [others => ' ']);
      Crashed : constant Zlib.Fuzzing.Fuzz_Result :=
        (Runs              => 1,
         Success           => 0,
         Failures          => 0,
         Crashes           => 1,
         Digest            => 0,
         Last_Input_Length => 0,
         Last_Hex_Length   => 0,
         Last_Hex          => [others => ' ']);
   begin
      Assert
        (Zlib.Fuzzing.Acceptable (Zlib.Fuzzing.Compress_Roundtrip_Target, Clean),
         "clean roundtrip fuzz summary must be acceptable");
      Assert
        (not Zlib.Fuzzing.Acceptable (Zlib.Fuzzing.Compress_Roundtrip_Target, Failed),
         "roundtrip fuzz deterministic failure must fail CI policy");
      Assert
        (Zlib.Fuzzing.Acceptable (Zlib.Fuzzing.Mutation_Target, Failed),
         "mutation fuzz deterministic decode failures are expected");
      Assert
        (not Zlib.Fuzzing.Acceptable (Zlib.Fuzzing.Mutation_Target, Crashed),
         "any fuzz crash must fail CI policy");
   end Test_Target_Acceptance_Policy;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T,
         Test_Same_Seed_Reproduces_Result'Access,
         "same seed reproduces fuzz result");
      Registration.Register_Routine
        (T,
         Test_Corrupted_Stream_Fails_Deterministically'Access,
         "corrupted stream fails deterministically");
      Registration.Register_Routine
        (T,
         Test_Roundtrip_Fuzzer_Smoke'Access,
         "roundtrip fuzzer runs a small deterministic pass");
      Registration.Register_Routine
        (T,
         Test_Lifecycle_Fuzzer_Smoke'Access,
         "lifecycle fuzzer covers invalid state transitions");
      Registration.Register_Routine
        (T,
         Test_Mutation_And_Tiny_Buffer_Fuzzers_Smoke'Access,
         "mutation and tiny-buffer fuzzers run small deterministic passes");
      Registration.Register_Routine
        (T,
         Test_All_Targets_Reproduce_Summaries'Access,
         "all fuzz targets reproduce summaries from seed");
      Registration.Register_Routine
        (T,
         Test_Target_Acceptance_Policy'Access,
         "target-aware fuzz acceptance policy rejects semantic failures");
      Registration.Register_Routine
        (T,
         Test_Wrappers_Metadata_Dictionaries_And_Levels_Smoke'Access,
         "wrapper, metadata, dictionary, and level fuzzers run smoke passes");
   end Register_Tests;

end Zlib_Fuzz_Smoke_Tests;
