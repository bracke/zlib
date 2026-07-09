--  Support level: private internal implementation.
--
--  Archive-to-directory extraction orchestration shared by ZIP and 7z
--  front-ends. Format-specific listing and payload extraction are supplied by
--  callbacks from the root body.

package Zlib.Archive_Directory_Extraction is
   pragma Elaborate_Body;

   procedure Extract_File_To_Directory
     (Archive_Path    : String;
      Destination_Dir : String;
      Password        : String;
      Read_File       : not null access function
        (Path : String; Status : out Status_Code) return Byte_Array;
      Extract_Image   : not null access procedure
        (Archive_Image   : Byte_Array;
         Destination_Dir : String;
         Password        : String;
         Status          : out Status_Code);
      Status          : out Status_Code);
   --  Read an archive file and extract its image to Destination_Dir.

   procedure Extract_To_Directory
     (Archive_Image     : Byte_Array;
      Destination_Dir   : String;
      Password          : String;
      Is_Seven_Zip      : Boolean;
      List_Seven_Zip    : not null access function
        (Archive_Image : Byte_Array;
         Password      : String;
         Status        : out Status_Code) return Archive_Entry_Array;
      List_ZIP          : not null access function
        (Archive_Image : Byte_Array;
         Status        : out Status_Code) return Archive_Entry_Array;
      Extract_Seven_Zip : not null access function
        (Archive_Image : Byte_Array;
         Entry_Name    : String;
         Password      : String;
         Status        : out Status_Code) return Byte_Array;
      Extract_ZIP       : not null access function
        (Archive_Image : Byte_Array;
         Entry_Name    : String;
         Status        : out Status_Code) return Byte_Array;
      Safe_Entry_Name   : not null access function
        (Entry_Name : String) return Boolean;
      Write_File        : not null access procedure
        (Path : String; Data : Byte_Array; Status : out Status_Code);
      Status            : out Status_Code);
   --  List entries, validate relative output names, extract payloads, and
   --  write files/directories below Destination_Dir.

end Zlib.Archive_Directory_Extraction;
