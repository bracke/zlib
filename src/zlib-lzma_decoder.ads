package Zlib.LZMA_Decoder is
   --  Support level: private internal implementation.
   --  Raw LZMA payload decoder used by ZIP, 7z, and encoded headers.

   function Decode_Payload
     (Payload              : Byte_Array;
      Plain_Len            : Natural;
      Require_Full_Stream  : Boolean;
      Initial_Rep_Distance : Natural;
      Use_Matched_Literals : Boolean;
      Status               : out Status_Code) return Byte_Array;

end Zlib.LZMA_Decoder;
