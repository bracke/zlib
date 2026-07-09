with Interfaces;

package Zlib.Fuzzing is
   --  Support level: private internal implementation.
   --  Deterministic fuzzing helpers used by repository tools and smoke tests.
   --  This child package is infrastructure-only: it adds no public compression
   --  or inflate behavior and keeps all generated inputs reproducible from a
   --  seed, target, and iteration count.

   type Target_Kind is
     (Inflate_Target,
      Streaming_Inflate_Target,
      Compress_Roundtrip_Target,
      Wrapper_Mix_Target,
      Dictionary_Target,
      GZip_Metadata_Target,
      Compression_Level_Target,
      Lifecycle_Target,
      Mutation_Target,
      Flush_Target,
      Tiny_Buffer_Target);

   type Fuzz_Result is record
      Runs              : Natural := 0;
      Success           : Natural := 0;
      Failures          : Natural := 0;
      Crashes           : Natural := 0;
      Digest            : Interfaces.Unsigned_32 := 0;
      Last_Input_Length : Natural := 0;
      Last_Hex_Length   : Natural := 0;
      Last_Hex          : String (1 .. 32) := [others => ' '];
   end record;

   function Random_Bytes
     (Seed : in out Interfaces.Unsigned_32; Length : Natural)
      return Byte_Array;
   --  Return the Random Bytes result.
   --  @param Seed Seed argument supplied to Random_Bytes
   --  @param Length Length argument supplied to Random_Bytes
   --  @return result produced by Random_Bytes

   function Mutated
     (Input : Byte_Array; Seed : in out Interfaces.Unsigned_32; Step : Natural)
      return Byte_Array;
   --  Return the Mutated result.
   --  @param Input Input argument supplied to Mutated
   --  @param Seed Seed argument supplied to Mutated
   --  @param Step Step argument supplied to Mutated
   --  @return result produced by Mutated

   function Hex_Snippet
     (Input : Byte_Array; Limit : Natural := 16) return String;
   --  Return the Hex Snippet result.
   --  @param Input Input argument supplied to Hex_Snippet
   --  @param Limit Limit argument supplied to Hex_Snippet
   --  @return result produced by Hex_Snippet

   function Run
     (Target     : Target_Kind;
      Seed       : Interfaces.Unsigned_32;
      Iterations : Natural) return Fuzz_Result;
   --  Return the Run result.
   --  @param Target Target argument supplied to Run
   --  @param Seed Seed argument supplied to Run
   --  @param Iterations Iterations argument supplied to Run
   --  @return result produced by Run

   function Last_Hex_Snippet (Result : Fuzz_Result) return String;
   --  Return the Last Hex Snippet result.
   --  @param Result Result argument supplied to Last_Hex_Snippet
   --  @return result produced by Last_Hex_Snippet

   function Expected_Failures_Are_Allowed
     (Target : Target_Kind) return Boolean
     with SPARK_Mode => On;
   --  Return the Expected Failures Are Allowed result.
   --  @param Target Target argument supplied to Expected_Failures_Are_Allowed
   --  @return result produced by Expected_Failures_Are_Allowed

   function Acceptable
     (Target : Target_Kind; Result : Fuzz_Result) return Boolean
     with SPARK_Mode => On;
   --  Return the Acceptable result.
   --  @param Target Target argument supplied to Acceptable
   --  @param Result Result argument supplied to Acceptable
   --  @return result produced by Acceptable

   function Same_Result
     (Left : Fuzz_Result; Right : Fuzz_Result) return Boolean
     with SPARK_Mode => On;
   --  Return the Same Result result.
   --  @param Left Left argument supplied to Same_Result
   --  @param Right Right argument supplied to Same_Result
   --  @return result produced by Same_Result

end Zlib.Fuzzing;
