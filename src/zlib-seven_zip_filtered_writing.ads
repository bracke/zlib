--  Support level: private internal implementation.
--
--  Single-entry filtered 7z archive orchestration. Codec packing is supplied
--  by the root body through a callback.

package Zlib.Seven_Zip_Filtered_Writing is

   function Build_Filtered
     (Input          : Byte_Array;
      Entry_Name     : String;
      Filter         : Seven_Zip_Filter_Method;
      Codec          : Seven_Zip_Codec_Method;
      Delta_Distance : Positive;
      Metadata       : Seven_Zip_Entry_Metadata;
      Pack_Filtered  : not null access function
        (Input      : Byte_Array;
         Codec      : Seven_Zip_Codec_Method;
         LZMA_Props : out Byte;
         Status     : out Status_Code) return Byte_Array;
      Status         : out Status_Code) return Byte_Array;
   --  Apply the filter, pack the filtered bytes, and build the 7z container.

end Zlib.Seven_Zip_Filtered_Writing;
