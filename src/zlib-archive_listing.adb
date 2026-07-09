package body Zlib.Archive_Listing is

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
      Status         : out Status_Code) return Archive_Entry_Array
   is
   begin
      Status := Unsupported_Method;

      if Is_Seven_Zip then
         return List_Seven_Zip (Archive_Image, Password, Status);
      else
         return List_ZIP (Archive_Image, Status);
      end if;
   exception
      when others =>
         Status := Unsupported_Method;
         return No : Archive_Entry_Array (1 .. 0) do
            null;
         end return;
   end List_Entries;

end Zlib.Archive_Listing;
