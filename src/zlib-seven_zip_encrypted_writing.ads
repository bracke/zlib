--  Support level: private internal implementation.
--
--  Single-entry encrypted 7z writer orchestration. Compression is supplied by
--  the root body through a callback.

package Zlib.Seven_Zip_Encrypted_Writing is

   function Build_AES_LZMA
     (Input       : Byte_Array;
      Entry_Name  : String;
      Password    : String;
      Encode_LZMA : not null access function
        (Input : Byte_Array; LZMA_Props : in out Byte) return Byte_Array;
      Status      : out Status_Code) return Byte_Array;
   --  Compress with LZMA, encrypt with 7z AES, and build the archive.

end Zlib.Seven_Zip_Encrypted_Writing;
