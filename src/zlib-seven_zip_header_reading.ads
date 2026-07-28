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
      Fetch_Packed  : access function
        (First : Natural; Last : Natural) return Byte_Array := null;
      Pack_Pos      : out Natural;
      Status        : out Status_Code) return Byte_Array;
   --  Decode kEncodedHeader into plain kHeader bytes and report the packed
   --  offset so callers can rebuild the logical archive payload prefix.
   --
   --  Every field of the header itself is read from Archive_Image, which need
   --  only span Info.Header_First .. Info.Header_Last: a Byte_Array indexed at
   --  its true archive offsets satisfies that without holding the archive. The
   --  one region outside the header an encoded header needs is its own packed
   --  stream, which Fetch_Packed supplies when it is not null; when it is null
   --  that stream is sliced out of Archive_Image as before.

end Zlib.Seven_Zip_Header_Reading;
