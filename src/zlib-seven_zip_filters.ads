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

   type Branch_Arch is (X86, ARM, ARMT, ARM64, RISCV, PPC, SPARC, IA64);
   --  Architectures with a branch converter. X86 is the full masked BCJ.
   --  RISC-V uses the compact 7z 24.x method ID and handles 32-bit JAL
   --  instructions; stock-7z cross-validation requires a local 24.x+ binary.

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

   function Delta_Decode_Checked
     (Data     : Byte_Array;
      Distance : Natural;
      Status   : out Status_Code) return Byte_Array;
   --  Checked Delta_Decode wrapper for parsed 7z properties.

   function X86_BCJ_Decode
     (Data   : Byte_Array;
      Status : out Status_Code) return Byte_Array;
   --  Checked x86 BCJ decode wrapper for parsed 7z folders.

   function Apply_Filter
     (Data           : Byte_Array;
      Filter         : Seven_Zip_Filter_Method;
      Delta_Distance : Positive) return Byte_Array
     with Pre => Delta_Distance in 1 .. 256;
   --  Apply the public 7z filter selector for writer-side filtering.

   function BCJ2_Decode
     (Main_Stream : Byte_Array;
      Call_Stream : Byte_Array;
      Jump_Stream : Byte_Array;
      RC_Stream   : Byte_Array;
      Expected    : Natural;
      Status      : out Status_Code) return Byte_Array;
   --  Decode a four-stream x86 BCJ2 coder payload.
   --  @param Main_Stream byte stream containing unconverted bytes/opcodes
   --  @param Call_Stream absolute call targets
   --  @param Jump_Stream absolute jump targets
   --  @param RC_Stream range-coded conversion decisions
   --  @param Expected exact decoded output size

   type BCJ2_Encoded_Streams
     (Main_Length : Natural;
      Call_Length : Natural;
      Jump_Length : Natural;
      RC_Length   : Natural) is record
         Main_Stream : Byte_Array (1 .. Main_Length);
         Call_Stream : Byte_Array (1 .. Call_Length);
         Jump_Stream : Byte_Array (1 .. Jump_Length);
         RC_Stream   : Byte_Array (1 .. RC_Length);
   end record;

   function BCJ2_Encode (Input : Byte_Array) return BCJ2_Encoded_Streams;
   --  Split x86 code into the four BCJ2 coder streams.
   --  @param Input executable byte stream to encode

end Zlib.Seven_Zip_Filters;
