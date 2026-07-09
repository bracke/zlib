--  Support level: private internal implementation.
--
--  File-system orchestration for single-entry 7z extraction. Archive decoding
--  and raw file IO remain supplied by the root body through callbacks.

package Zlib.Seven_Zip_File_Extraction is

   function Extract_Metadata
     (Archive_Image  : Byte_Array;
      Entry_Name     : String;
      Extract_Entry  : not null access function
        (Archive      : Byte_Array;
         Entry_Name   : String;
         Status       : out Status_Code;
         Is_Directory : out Boolean;
         Metadata     : out Seven_Zip_Entry_Metadata) return Byte_Array;
      Status         : out Status_Code) return Seven_Zip_Entry_Metadata;
   --  Extract Entry_Name metadata without writing the entry payload.

   procedure Extract_File
     (Input_Path    : String;
      Output_Path   : String;
      Entry_Name    : String;
      Read_File     : not null access function
        (Path : String; Status : out Status_Code) return Byte_Array;
      Write_File    : not null access procedure
        (Path : String; Data : Byte_Array; Status : out Status_Code);
      Extract_Entry : not null access function
        (Archive      : Byte_Array;
         Entry_Name   : String;
         Status       : out Status_Code;
         Is_Directory : out Boolean;
         Metadata     : out Seven_Zip_Entry_Metadata) return Byte_Array;
      Status        : out Status_Code);
   --  Extract Entry_Name from Input_Path to Output_Path and restore metadata.

   procedure Extract_Files
     (Input_Path    : String;
      Output_Dir    : String;
      Entry_Names   : Text_Array;
      Read_File     : not null access function
        (Path : String; Status : out Status_Code) return Byte_Array;
      Write_File    : not null access procedure
        (Path : String; Data : Byte_Array; Status : out Status_Code);
      Extract_Entry : not null access function
        (Archive      : Byte_Array;
         Entry_Name   : String;
         Status       : out Status_Code;
         Is_Directory : out Boolean;
         Metadata     : out Seven_Zip_Entry_Metadata) return Byte_Array;
      Status        : out Status_Code);
   --  Stage selected entries from Input_Path and write them below Output_Dir.

end Zlib.Seven_Zip_File_Extraction;
