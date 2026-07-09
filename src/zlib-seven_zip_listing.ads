--  Support level: private internal implementation.
--
--  Native 7z archive listing orchestration. Root-only codec entry points are
--  supplied by callback so this package can own the header catalogue walk
--  without depending on root-body implementation details.

package Zlib.Seven_Zip_Listing is
   pragma Elaborate_Body;

   function List
     (Archive_Image              : Byte_Array;
      Password                   : String;
      Decode_LZMA_Encoded_Header : not null access function
        (Input         : Byte_Array;
         LZMA_Props    : Byte_Array;
         Expected_Size : Natural;
         Status        : out Status_Code) return Byte_Array;
      Status                     : out Status_Code) return Archive_Entry_Array;
   --  Return the native 7z catalogue for Archive_Image.

end Zlib.Seven_Zip_Listing;
