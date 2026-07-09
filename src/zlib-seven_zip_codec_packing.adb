with Zlib.PPMd7;
with Zlib.Seven_Zip_Coders;
with Zlib.Seven_Zip_Methods; use Zlib.Seven_Zip_Methods;

package body Zlib.Seven_Zip_Codec_Packing is

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
      Status             : out Status_Code) return Byte_Array
   is
      Props : Byte := Default_LZMA_Props;
   begin
      LZMA_Props := Default_LZMA_Props;

      case Codec is
         when Seven_Zip_Codec_Deflate =>
            return Deflate (Input, Status);

         when Seven_Zip_Codec_BZip2 =>
            return BZip2 (Input, Status);

         when Seven_Zip_Codec_LZMA =>
            Status := Ok;
            declare
               Packed : constant Byte_Array := LZMA (Input, Props);
            begin
               LZMA_Props := Props;
               return Packed;
            end;

         when Seven_Zip_Codec_LZMA2 =>
            Status := Ok;
            return LZMA2 (Input);

         when Seven_Zip_Codec_PPMd =>
            Status := Ok;
            return
              Zlib.PPMd7.Compress
                (Input, Zlib.Seven_Zip_Coders.PPMd_Default_Order,
                 Zlib.Seven_Zip_Coders.PPMd_Default_Memory);
      end case;
   end Pack_Filtered;

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
      Status             : out Status_Code) return Byte_Array
   is
      Empty : constant Byte_Array (1 .. 0) := [others => 0];
   begin
      LZMA_Props := Default_LZMA_Props;

      case Method is
         when Seven_Zip_Deflate_Method =>
            return Deflate (Input, Status);

         when Seven_Zip_BZip2_Method =>
            return BZip2 (Input, Status);

         when Seven_Zip_LZMA_Method =>
            Status := Ok;
            return LZMA (Input, LZMA_Props);

         when Seven_Zip_LZMA2_Method =>
            Status := Ok;
            return LZMA2 (Input);

         when Seven_Zip_PPMd_Method =>
            Status := Ok;
            return
              Zlib.PPMd7.Compress
                (Input, Zlib.Seven_Zip_Coders.PPMd_Default_Order,
                 Zlib.Seven_Zip_Coders.PPMd_Default_Memory);

         when others =>
            Status := Unsupported_Method;
            return Empty;
      end case;
   end Pack_Method;

end Zlib.Seven_Zip_Codec_Packing;
