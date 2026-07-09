--  Support level: private internal implementation.
--
--  Multi-volume 7z byte-stream read/write orchestration.

package Zlib.Seven_Zip_Volumes is

   function Suffix (N : Positive) return String
     with SPARK_Mode => On;
   --  Return the 7z volume suffix for N: 001, 002, ...

   function Read
     (First_Volume_Path : String;
      Read_File         : not null access function
        (Path : String; Status : out Status_Code) return Byte_Array;
      Status            : out Status_Code) return Byte_Array;
   --  Read Base.001, Base.002, ... into one archive byte stream.

   procedure Write
     (Archive     : Byte_Array;
      Base_Path   : String;
      Volume_Size : Positive;
      Write_File  : not null access procedure
        (Path : String; Data : Byte_Array; Status : out Status_Code);
      Status      : out Status_Code);
   --  Split Archive into Base_Path.001, Base_Path.002, ...

   function Extract
     (First_Volume_Path : String;
      Entry_Name        : String;
      Password          : String;
      Read_File         : not null access function
        (Path : String; Status : out Status_Code) return Byte_Array;
      Extract_Entry     : not null access function
        (Archive_Image : Byte_Array;
         Entry_Name    : String;
         Status        : out Status_Code) return Byte_Array;
      Extract_Entry_With_Password : not null access function
        (Archive_Image : Byte_Array;
         Entry_Name    : String;
         Password      : String;
         Status        : out Status_Code) return Byte_Array;
      Status            : out Status_Code) return Byte_Array;
   --  Join split volumes, then extract Entry_Name with the selected password
   --  policy through caller-supplied archive extraction callbacks.

end Zlib.Seven_Zip_Volumes;
