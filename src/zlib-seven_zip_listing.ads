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

   function List_From_Parts
     (Signature                  : Byte_Array;
      Next_Header                : Byte_Array;
      Password                   : String;
      Decode_LZMA_Encoded_Header : not null access function
        (Input         : Byte_Array;
         LZMA_Props    : Byte_Array;
         Expected_Size : Natural;
         Status        : out Status_Code) return Byte_Array;
      Fetch_Packed               : access function
        (First : Natural; Last : Natural) return Byte_Array := null;
      Status                     : out Status_Code) return Archive_Entry_Array;
   --  Return the native 7z catalogue from the two regions a catalogue actually
   --  needs: the 32-byte signature header, and the next header. Both must be
   --  indexed at their true archive offsets. Fetch_Packed supplies the packed
   --  stream of an encoded header, which is the only other region involved, so
   --  an archive can be catalogued without being held in memory. List is this
   --  with both regions sliced out of a whole image.

end Zlib.Seven_Zip_Listing;
