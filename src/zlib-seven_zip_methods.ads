--  Support level: private internal implementation.
--
--  7z coder method identities and descriptor metadata. This package keeps the
--  method table out of the monolithic container implementation so writer and
--  parser paths can converge on one source of method-id truth.

with Zlib.Seven_Zip_Filters;

package Zlib.Seven_Zip_Methods
  with SPARK_Mode => On
is

   type Seven_Zip_Coder_Method is
     (Seven_Zip_Copy, Seven_Zip_Deflate_Method, Seven_Zip_BZip2_Method,
      Seven_Zip_LZMA_Method, Seven_Zip_LZMA2_Method,
      Seven_Zip_Delta_Method, Seven_Zip_BCJ_X86_Method,
      Seven_Zip_BCJ_ARM_Method, Seven_Zip_BCJ_ARMT_Method,
      Seven_Zip_BCJ_ARM64_Method,
      Seven_Zip_BCJ_PPC_Method, Seven_Zip_BCJ_SPARC_Method,
      Seven_Zip_BCJ_IA64_Method, Seven_Zip_BCJ_RISCV_Method,
      Seven_Zip_BCJ2_Method, Seven_Zip_PPMd_Method,
      Seven_Zip_AES_Method);
   --  Internal normalized method names used by the 7z reader/writer.

   subtype Seven_Zip_Method_ID_Length is Positive range 1 .. 4;
   type Seven_Zip_Method_ID is array (Seven_Zip_Method_ID_Length range <>) of Byte;

   type Seven_Zip_Coder_Descriptor
     (ID_Length : Seven_Zip_Method_ID_Length) is
   record
      ID          : Seven_Zip_Method_ID (1 .. ID_Length);
      Input_Count : Positive := 1;
      Output_Count : Positive := 1;
   end record;
   --  7z coder metadata that is independent of coder properties.

   function Descriptor
     (Method : Seven_Zip_Coder_Method) return Seven_Zip_Coder_Descriptor;
   --  Return the canonical 7z method ID and stream arity.

   function Descriptor_Flags
     (Method         : Seven_Zip_Coder_Method;
      Has_Properties : Boolean) return Byte;
   --  Return the 7z coder descriptor flags byte for Method and property
   --  presence. This includes ID length and non-default stream arity bits.

   subtype Seven_Zip_Method_Code is Natural range 0 .. 17;
   Unknown_Method_Code : constant Seven_Zip_Method_Code := 0;

   function Method_Code_For_ID
     (ID        : Byte_Array;
      ID_Length : Natural) return Seven_Zip_Method_Code
     with Pre => ID_Length <= 4
                   and then
                 (ID_Length = 0
                  or else (ID'First <= ID'Last
                           and then ID_Length - 1 <= ID'Last - ID'First));
   --  Decode a 7z method ID into a stable internal method code. Returns
   --  Unknown_Method_Code for unsupported or malformed IDs.

   function Method_For_ID
     (ID        : Byte_Array;
      ID_Length : Natural;
      Method    : out Seven_Zip_Coder_Method) return Boolean
     with Pre => ID_Length <= 4
                   and then
                 (ID_Length = 0
                  or else (ID'First <= ID'Last
                           and then ID_Length - 1 <= ID'Last - ID'First)),
          SPARK_Mode => Off;
   --  Decode a 7z method ID into the normalized internal method name. Accepts
   --  canonical writer IDs and compact branch-filter IDs used by stock 7-Zip.

   function Method_For_Filter
     (Filter : Seven_Zip_Filter_Method) return Seven_Zip_Coder_Method;
   --  Map the public filtered-writer selector to the internal coder method.

   function Method_For_Codec
     (Codec : Seven_Zip_Codec_Method) return Seven_Zip_Coder_Method;
   --  Map the public terminal-codec selector to the internal coder method.

   function Method_For_Graph
     (Method : Seven_Zip_Graph_Method) return Seven_Zip_Coder_Method;
   --  Map the public graph-coder selector to the internal coder method.

   function Is_Propertyless_Coder
     (Method : Seven_Zip_Coder_Method) return Boolean;
   --  Return True for supported 7z coders whose folder coder descriptor must
   --  not carry property bytes in this implementation.

   function Is_Branch_Converter
     (Method : Seven_Zip_Coder_Method) return Boolean;
   --  Return True for branch filters handled by Branch_Arch_Of and the shared
   --  non-x86 converter. x86 BCJ is intentionally separate.

   function Is_BCJ2_Main_Chain_Coder
     (Method : Seven_Zip_Coder_Method) return Boolean;
   --  Return True for coders allowed before the BCJ2 terminal coder in the
   --  supported five-coder main-chain layout.

   function Branch_Arch_Of
     (Method : Seven_Zip_Coder_Method)
      return Zlib.Seven_Zip_Filters.Branch_Arch
     with Pre => Method in Seven_Zip_BCJ_ARM_Method
                         | Seven_Zip_BCJ_ARMT_Method
                         | Seven_Zip_BCJ_ARM64_Method
                         | Seven_Zip_BCJ_PPC_Method
                         | Seven_Zip_BCJ_SPARC_Method
                         | Seven_Zip_BCJ_IA64_Method
                         | Seven_Zip_BCJ_RISCV_Method;
   --  Map a branch-filter coder method to its filter architecture.

end Zlib.Seven_Zip_Methods;
