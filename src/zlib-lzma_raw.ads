with Zlib.LZMA_Properties;

package Zlib.LZMA_Raw is
   --  Support level: private internal implementation.
   --  Raw LZMA stream helpers for 7z folders and encoded headers.

   function Decode
     (Stream    : Byte_Array;
      Props     : Zlib.LZMA_Properties.LZMA_Properties;
      Plain_Len : Natural;
      Status    : out Status_Code) return Byte_Array;

   function Decode_With
     (Stream               : Byte_Array;
      Props                : Zlib.LZMA_Properties.LZMA_Properties;
      Plain_Len            : Natural;
      Require_Full_Stream  : Boolean;
      Initial_Rep_Distance : Natural;
      Use_Matched_Literals : Boolean;
      Status               : out Status_Code) return Byte_Array;

   function Decode_Encoded_Header
     (Stream    : Byte_Array;
      Props     : Zlib.LZMA_Properties.LZMA_Properties;
      Plain_Len : Natural;
      Status    : out Status_Code) return Byte_Array;

end Zlib.LZMA_Raw;
