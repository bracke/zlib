with Interfaces;
with Zlib.Seven_Zip_Methods;

--  Support level: private internal implementation.
--
--  Single-entry compressed 7z writer orchestration. Codec packing is supplied
--  by the root body through callbacks; pre-packed method-graph archives are
--  routed through the same writer boundary.

package Zlib.Seven_Zip_Codec_Writing is
   pragma Elaborate_Body;

   function Build_Codec
     (Input         : Byte_Array;
      Entry_Name    : String;
      Method        : Zlib.Seven_Zip_Methods.Seven_Zip_Coder_Method;
      Metadata      : Seven_Zip_Entry_Metadata;
      Pack_Input    : not null access function
        (Input      : Byte_Array;
         LZMA_Props : in out Byte;
         Status     : out Status_Code) return Byte_Array;
      Status        : out Status_Code) return Byte_Array;
   --  Pack Input with a codec callback and build a single-entry archive.

   function Build_Copy
     (Input      : Byte_Array;
      Entry_Name : String;
      Metadata   : Seven_Zip_Entry_Metadata;
      Status     : out Status_Code) return Byte_Array;
   --  Build a single-entry Copy-coder archive.

   function Build_PPMd
     (Input      : Byte_Array;
      Entry_Name : String;
      Metadata   : Seven_Zip_Entry_Metadata;
      Status     : out Status_Code) return Byte_Array;
   --  Build a single-entry PPMd archive.

   function Build_LZMA2
     (Input      : Byte_Array;
      Entry_Name : String;
      Metadata   : Seven_Zip_Entry_Metadata;
      Encode     : not null access function
        (Input : Byte_Array) return Byte_Array;
      Status     : out Status_Code) return Byte_Array;
   --  Build a single-entry LZMA2 archive with a root-supplied encoder.

   function Build_LZMA
     (Input      : Byte_Array;
      Entry_Name : String;
      Metadata   : Seven_Zip_Entry_Metadata;
      Encode     : not null access function
        (Input      : Byte_Array;
         LZMA_Props : in out Byte) return Byte_Array;
      Status     : out Status_Code) return Byte_Array;
   --  Build a single-entry LZMA archive with a root-supplied encoder.

   function Build_Deflate
     (Input      : Byte_Array;
      Entry_Name : String;
      Metadata   : Seven_Zip_Entry_Metadata;
      Compress   : not null access function
        (Input  : Byte_Array;
         Status : out Status_Code) return Byte_Array;
      Status     : out Status_Code) return Byte_Array;
   --  Build a single-entry Deflate archive with a root-supplied compressor.

   function Build_BZip2
     (Input      : Byte_Array;
      Entry_Name : String;
      Metadata   : Seven_Zip_Entry_Metadata;
      Compress   : not null access function
        (Input  : Byte_Array;
         Status : out Status_Code) return Byte_Array;
      Status     : out Status_Code) return Byte_Array;
   --  Build a single-entry BZip2 archive with a root-supplied compressor.

   function Build_Method_Graph
     (Packed_Data    : Byte_Array;
      Entry_Name     : String;
      Coders         : Seven_Zip_Graph_Coder_Array;
      Bind_Pairs     : Seven_Zip_Bind_Pair_Array;
      Packed_Streams : Seven_Zip_Stream_Index_Array;
      Pack_Sizes     : Seven_Zip_Size_Array;
      Unpack_Sizes   : Seven_Zip_Size_Array;
      Unpacked_CRC   : Interfaces.Unsigned_32;
      Metadata       : Seven_Zip_Entry_Metadata;
      Status         : out Status_Code) return Byte_Array;
   --  Build a complete single-entry arbitrary method-graph 7z archive.

end Zlib.Seven_Zip_Codec_Writing;
