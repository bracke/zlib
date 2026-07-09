--  Support level: private internal implementation.
--
--  Single-entry BCJ2 7z writer orchestration.

package Zlib.Seven_Zip_BCJ2_Writing is
   pragma Elaborate_Body;

   function Build_BCJ2
     (Input      : Byte_Array;
      Entry_Name : String;
      Status     : out Status_Code) return Byte_Array;
   --  BCJ2-filter Input and build a stored BCJ2 7z archive.

end Zlib.Seven_Zip_BCJ2_Writing;
