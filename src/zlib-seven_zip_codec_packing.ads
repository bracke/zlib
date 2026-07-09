with Zlib.Seven_Zip_Methods;

--  Support level: private internal implementation.
--
--  Codec packing dispatch shared by 7z writer orchestration. Root-body codec
--  entry points are supplied as callbacks where the implementation still owns
--  selected compression policy.

package Zlib.Seven_Zip_Codec_Packing is
   pragma Elaborate_Body;

   function Pack_Filtered
     (Input              : Byte_Array;
      Codec              : Seven_Zip_Codec_Method;
      Default_LZMA_Props : Byte;
      Deflate            : not null access function
        (Input  : Byte_Array;
         Status : out Status_Code) return Byte_Array;
      BZip2              : not null access function
        (Input  : Byte_Array;
         Status : out Status_Code) return Byte_Array;
      LZMA               : not null access function
        (Input      : Byte_Array;
         LZMA_Props : in out Byte) return Byte_Array;
      LZMA2              : not null access function
        (Input : Byte_Array) return Byte_Array;
      LZMA_Props         : out Byte;
      Status             : out Status_Code) return Byte_Array;
   --  Pack filtered data with the public filtered-writer codec selector.

   function Pack_Method
     (Input              : Byte_Array;
      Method             : Zlib.Seven_Zip_Methods.Seven_Zip_Coder_Method;
      Default_LZMA_Props : Byte;
      Deflate            : not null access function
        (Input  : Byte_Array;
         Status : out Status_Code) return Byte_Array;
      BZip2              : not null access function
        (Input  : Byte_Array;
         Status : out Status_Code) return Byte_Array;
      LZMA               : not null access function
        (Input      : Byte_Array;
         LZMA_Props : in out Byte) return Byte_Array;
      LZMA2              : not null access function
        (Input : Byte_Array) return Byte_Array;
      LZMA_Props         : in out Byte;
      Status             : out Status_Code) return Byte_Array;
   --  Pack file-list data with the internal 7z method selector.

end Zlib.Seven_Zip_Codec_Packing;
