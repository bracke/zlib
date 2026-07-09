with Zlib.Seven_Zip_Methods;

--  Support level: private internal implementation.
--
--  File-system orchestration for single-entry 7z writers. Codec selection and
--  archive bytes are supplied by the root body through callbacks.

package Zlib.Seven_Zip_File_Writing is

   procedure Write_File_Archive
     (Input_Path      : String;
      Output_Path     : String;
      Entry_Name      : String;
      Read_File       : not null access function
        (Path : String; Status : out Status_Code) return Byte_Array;
      Write_File      : not null access procedure
        (Path : String; Data : Byte_Array; Status : out Status_Code);
      Source_Metadata : not null access function
        (Path : String) return Seven_Zip_Entry_Metadata;
      Build_Archive   : not null access function
        (Input      : Byte_Array;
         Entry_Name : String;
         Metadata   : Seven_Zip_Entry_Metadata;
         Status     : out Status_Code) return Byte_Array;
      Status          : out Status_Code);
   --  Read Input_Path, preserve source metadata, build a one-entry archive, and
   --  write Output_Path. Directory inputs are encoded as no-stream entries.

   procedure Write_Stored_File_Archive
     (Input_Path      : String;
      Output_Path     : String;
      Entry_Name      : String;
      Read_File       : not null access function
        (Path : String; Status : out Status_Code) return Byte_Array;
      Write_File      : not null access procedure
        (Path : String; Data : Byte_Array; Status : out Status_Code);
      Source_Metadata : not null access function
        (Path : String) return Seven_Zip_Entry_Metadata;
      Status          : out Status_Code);
   --  Build and write a one-entry Copy-coder 7z archive from a path.

   procedure Write_PPMd_File_Archive
     (Input_Path      : String;
      Output_Path     : String;
      Entry_Name      : String;
      Read_File       : not null access function
        (Path : String; Status : out Status_Code) return Byte_Array;
      Write_File      : not null access procedure
        (Path : String; Data : Byte_Array; Status : out Status_Code);
      Source_Metadata : not null access function
        (Path : String) return Seven_Zip_Entry_Metadata;
      Status          : out Status_Code);
   --  Build and write a one-entry PPMd 7z archive from a path.

   procedure Write_PPMd_File_With_Basename
     (Input_Path      : String;
      Output_Path     : String;
      Read_File       : not null access function
        (Path : String; Status : out Status_Code) return Byte_Array;
      Write_File      : not null access procedure
        (Path : String; Data : Byte_Array; Status : out Status_Code);
      Source_Metadata : not null access function
        (Path : String) return Seven_Zip_Entry_Metadata;
      Status          : out Status_Code);
   --  Build and write a PPMd archive using Input_Path's simple name.

   procedure Write_Deflate_File_Archive
     (Input_Path      : String;
      Output_Path     : String;
      Entry_Name      : String;
      Read_File       : not null access function
        (Path : String; Status : out Status_Code) return Byte_Array;
      Write_File      : not null access procedure
        (Path : String; Data : Byte_Array; Status : out Status_Code);
      Source_Metadata : not null access function
        (Path : String) return Seven_Zip_Entry_Metadata;
      Compress        : not null access function
        (Input : Byte_Array; Status : out Status_Code) return Byte_Array;
      Status          : out Status_Code);
   --  Build and write a one-entry Deflate 7z archive from a path.

   procedure Write_BZip2_File_Archive
     (Input_Path      : String;
      Output_Path     : String;
      Entry_Name      : String;
      Read_File       : not null access function
        (Path : String; Status : out Status_Code) return Byte_Array;
      Write_File      : not null access procedure
        (Path : String; Data : Byte_Array; Status : out Status_Code);
      Source_Metadata : not null access function
        (Path : String) return Seven_Zip_Entry_Metadata;
      Compress        : not null access function
        (Input : Byte_Array; Status : out Status_Code) return Byte_Array;
      Status          : out Status_Code);
   --  Build and write a one-entry BZip2 7z archive from a path.

   procedure Write_LZMA_File_Archive
     (Input_Path      : String;
      Output_Path     : String;
      Entry_Name      : String;
      Read_File       : not null access function
        (Path : String; Status : out Status_Code) return Byte_Array;
      Write_File      : not null access procedure
        (Path : String; Data : Byte_Array; Status : out Status_Code);
      Source_Metadata : not null access function
        (Path : String) return Seven_Zip_Entry_Metadata;
      Encode          : not null access function
        (Input : Byte_Array; LZMA_Props : in out Byte) return Byte_Array;
      Status          : out Status_Code);
   --  Build and write a one-entry LZMA 7z archive from a path.

   procedure Write_LZMA2_File_Archive
     (Input_Path      : String;
      Output_Path     : String;
      Entry_Name      : String;
      Read_File       : not null access function
        (Path : String; Status : out Status_Code) return Byte_Array;
      Write_File      : not null access procedure
        (Path : String; Data : Byte_Array; Status : out Status_Code);
      Source_Metadata : not null access function
        (Path : String) return Seven_Zip_Entry_Metadata;
      Encode          : not null access function
        (Input : Byte_Array) return Byte_Array;
      Status          : out Status_Code);
   --  Build and write a one-entry LZMA2 7z archive from a path.

   procedure Write_Stored_File_List
     (Input_Paths     : Text_Array;
      Output_Path     : String;
      Entry_Names     : Text_Array;
      Read_File       : not null access function
        (Path : String; Status : out Status_Code) return Byte_Array;
      Write_File      : not null access procedure
        (Path : String; Data : Byte_Array; Status : out Status_Code);
      Source_Metadata : not null access function
        (Path : String) return Seven_Zip_Entry_Metadata;
      Status          : out Status_Code);
   --  Build and write a multi-entry stored 7z archive from file-system inputs.

   procedure Write_Compressed_File_List
     (Input_Paths     : Text_Array;
      Output_Path     : String;
      Entry_Names     : Text_Array;
      Method          : Zlib.Seven_Zip_Methods.Seven_Zip_Coder_Method;
      Solid           : Boolean;
      Password        : String;
      Read_File       : not null access function
        (Path : String; Status : out Status_Code) return Byte_Array;
      Write_File      : not null access procedure
        (Path : String; Data : Byte_Array; Status : out Status_Code);
      Source_Metadata : not null access function
        (Path : String) return Seven_Zip_Entry_Metadata;
      Pack_Input      : not null access function
        (Input_Data  : Byte_Array;
         LZMA_Props  : in out Byte;
         Pack_Status : out Status_Code) return Byte_Array;
      Status          : out Status_Code);
   --  Build and write a multi-entry compressed 7z archive from inputs.

   procedure Write_Compressed_File_List_Selected
     (Input_Paths     : Text_Array;
      Output_Path     : String;
      Entry_Names     : Text_Array;
      Method          : Zlib.Seven_Zip_Methods.Seven_Zip_Coder_Method;
      Mode            : Compression_Mode;
      Level           : Compression_Level;
      Use_Level       : Boolean;
      Solid           : Boolean;
      Password        : String;
      Read_File       : not null access function
        (Path : String; Status : out Status_Code) return Byte_Array;
      Write_File      : not null access procedure
        (Path : String; Data : Byte_Array; Status : out Status_Code);
      Source_Metadata : not null access function
        (Path : String) return Seven_Zip_Entry_Metadata;
      Deflate_Mode    : not null access function
        (Input  : Byte_Array;
         Mode   : Compression_Mode;
         Status : out Status_Code) return Byte_Array;
      Deflate_Level   : not null access function
        (Input  : Byte_Array;
         Level  : Compression_Level;
         Status : out Status_Code) return Byte_Array;
      BZip2           : not null access function
        (Input : Byte_Array; Status : out Status_Code) return Byte_Array;
      LZMA            : not null access function
        (Input : Byte_Array; LZMA_Props : in out Byte) return Byte_Array;
      LZMA2           : not null access function
        (Input : Byte_Array) return Byte_Array;
      Default_Props   : Byte;
      Status          : out Status_Code);
   --  Build and write a compressed file-list archive with root codec callbacks.

end Zlib.Seven_Zip_File_Writing;
