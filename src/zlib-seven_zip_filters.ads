--  Support level: private internal implementation.
--
--  7z branch and delta filters (encode and decode). These are the
--  reversible byte transforms that 7z applies before an entropy coder so
--  that machine-code relative branches become absolute (more compressible).
--
--  The branch algorithms are faithful transcriptions of the LZMA SDK
--  Bra.c converters used by 7-Zip itself, so encoded output matches stock
--  7z and stock 7z output decodes here. Encode and Decode for a given
--  architecture are exact inverses.
--
--  Whole-buffer, one-shot, allocation-light: each call returns a converted
--  copy of Data. The implicit instruction-pointer origin is 0, matching how
--  7z filters a contiguous coder stream.

package Zlib.Seven_Zip_Filters is

   type Branch_Arch is (X86, ARM, ARMT, ARM64, PPC, SPARC, IA64);
   --  Architectures with a shipped, stock-7z-validated branch converter. X86
   --  is the full masked BCJ. RISC-V is intentionally not yet included: the
   --  filter exists in 7-Zip 24.x+ but cannot be cross-checked with the
   --  available 7-Zip 23.01, so it is deferred to avoid shipping an
   --  unvalidated converter (see docs/SEVEN_ZIP_PLAN.md).

   function Branch_Convert
     (Arch     : Branch_Arch;
      Data     : Byte_Array;
      Encoding : Boolean) return Byte_Array;
   --  Apply the branch converter for Arch. Encoding => True converts
   --  relative branches to the 7z-filtered (absolute) form; Encoding =>
   --  False reverses it. Buffers shorter than one instruction are returned
   --  unchanged.
   --  @param Arch target architecture branch filter
   --  @param Data input bytes
   --  @param Encoding True to filter (encode), False to unfilter (decode)

   function Delta_Encode
     (Data     : Byte_Array;
      Distance : Positive) return Byte_Array
     with Pre => Distance in 1 .. 256;
   --  Forward delta filter with the given byte distance (1 .. 256).
   --  @param Data input bytes
   --  @param Distance delta byte distance, 1 .. 256

   function Delta_Decode
     (Data     : Byte_Array;
      Distance : Positive) return Byte_Array
     with Pre => Distance in 1 .. 256;
   --  Inverse of Delta_Encode for the same Distance.
   --  @param Data input bytes
   --  @param Distance delta byte distance, 1 .. 256

end Zlib.Seven_Zip_Filters;
