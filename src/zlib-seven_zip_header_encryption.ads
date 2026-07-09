--  Support level: private internal implementation.
--
--  7z encoded-header encryption orchestration. Header compression is supplied
--  by the root body so codec selection stays in one place.

package Zlib.Seven_Zip_Header_Encryption is

   function Encrypt_Header
     (Archive       : Byte_Array;
      Password      : String;
      Encode_Header : not null access function
        (Input : Byte_Array; LZMA_Props : in out Byte) return Byte_Array;
      Status        : out Status_Code) return Byte_Array;
   --  Replace a plain next header with an AES -> LZMA encoded header.

end Zlib.Seven_Zip_Header_Encryption;
