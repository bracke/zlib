--  Support level: private internal implementation.
--
--  Archive listing orchestration shared by ZIP and 7z front-ends. Format
--  specific parsing is supplied by callbacks from the root body.

package Zlib.Archive_Listing is

   function List_Entries
     (Archive_Image  : Byte_Array;
      Password       : String;
      Is_Seven_Zip   : Boolean;
      List_Seven_Zip : not null access function
        (Archive_Image : Byte_Array;
         Password      : String;
         Status        : out Status_Code) return Archive_Entry_Array;
      List_ZIP       : not null access function
        (Archive_Image : Byte_Array;
         Status        : out Status_Code) return Archive_Entry_Array;
      Status         : out Status_Code) return Archive_Entry_Array;
   --  Dispatch archive listing to the selected container parser.

end Zlib.Archive_Listing;
