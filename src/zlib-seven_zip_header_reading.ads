with Interfaces;
with Zlib.Seven_Zip_Container;
with Zlib.Seven_Zip_Methods;

--  Support level: private internal implementation.
--
--  7z read-side header recovery. This package owns encoded-header parsing and
--  normalization; root-body callbacks provide codecs that still depend on root
--  Deflate/LZMA entry points.

package Zlib.Seven_Zip_Header_Reading is
   subtype LZMA_Props is Byte_Array (1 .. 5);

   function Decode_Encoded_Header
     (Archive_Image : Byte_Array;
      Password      : String;
      Info          : Zlib.Seven_Zip_Container.Start_Header_Info;
      Decode        : not null access function
        (Input          : Byte_Array;
         Method         : Zlib.Seven_Zip_Methods.Seven_Zip_Coder_Method;
         LZMA_Props     : Byte_Array;
         Expected_Size  : Natural;
         Delta_Distance : Positive;
         PPMd_Order     : Natural;
         PPMd_Memory    : Interfaces.Unsigned_32;
         Status         : out Status_Code) return Byte_Array;
      Pack_Pos      : out Natural;
      Status        : out Status_Code) return Byte_Array;
   --  Decode kEncodedHeader into plain kHeader bytes and report the packed
   --  offset so callers can rebuild the logical archive payload prefix.

end Zlib.Seven_Zip_Header_Reading;
