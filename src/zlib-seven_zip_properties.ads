--  Support level: private internal implementation.
--
--  7z FilesInfo property readers used by native archive extraction.

with Interfaces;

package Zlib.Seven_Zip_Properties is

   type Entry_Metadata_Array is array (Positive range <>) of Seven_Zip_Entry_Metadata;

   type Files_Info_Target is record
      File_Index  : Natural := 0;
      Stream_Index : Natural := 0;
      Has_Stream  : Boolean := False;
      Is_Directory : Boolean := False;
      Metadata    : Seven_Zip_Entry_Metadata := No_Seven_Zip_Entry_Metadata;
   end record;

   function Bit_Is_Set
     (Data  : Byte_Array;
      First : Natural;
      Index : Natural) return Boolean
     with SPARK_Mode => On;
   --  Return True when the one-based FilesInfo bitmap Index is set.

   function U64_LE
     (Data : Byte_Array;
      Pos  : Natural) return Interfaces.Unsigned_64
     with SPARK_Mode => On;
   --  Return a little-endian UInt64, or zero if Pos is out of range.

   function U32_LE
     (Data : Byte_Array;
      Pos  : Natural) return Interfaces.Unsigned_32
     with SPARK_Mode => On;
   --  Return a little-endian UInt32, or zero if Pos is out of range.

   function Read_File_Time_Property
     (Data       : Byte_Array;
      First      : Natural;
      Count      : Natural;
      File_Count : Natural;
      Target     : Natural;
      Has_Time   : out Boolean;
      Time       : out Interfaces.Unsigned_64) return Boolean;
   --  Read Target's optional 7z FILETIME from a FilesInfo time property.

   function Read_U32_Property
     (Data       : Byte_Array;
      First      : Natural;
      Count      : Natural;
      File_Count : Natural;
      Target     : Natural;
      Has_Value  : out Boolean;
      Value      : out Interfaces.Unsigned_32) return Boolean;
   --  Read Target's optional UInt32 FilesInfo property value.

   function Name_Index
     (Data       : Byte_Array;
      First      : Natural;
      Count      : Natural;
      File_Count : Natural;
      Entry_Name : String;
      Index      : out Natural) return Boolean;
   --  Return the one-based index of Entry_Name in a 7z UTF-16LE name property.

   function Read_Target_Entry
     (Data        : Byte_Array;
      Pos         : in out Natural;
      Last        : Natural;
      File_Count  : Natural;
      Entry_Name  : String;
      Target      : out Files_Info_Target;
      Stream_Count : out Natural) return Boolean;
   --  Walk a FilesInfo property list and return Entry_Name's file/stream info.
   --  Pos must point at the first FilesInfo property ID and is left after the
   --  FilesInfo kEnd byte.

   function Metadata_Image (Metadata : Seven_Zip_Entry_Metadata) return Byte_Array;
   --  Return FilesInfo metadata property bytes for one entry.

   function Metadata_Image (Metadata : Entry_Metadata_Array) return Byte_Array;
   --  Return FilesInfo metadata property bytes for entries that all define a value.

   function Source_Metadata
     (Input_Path : String) return Seven_Zip_Entry_Metadata;
   --  Collect supported filesystem metadata for a source archive entry.

   procedure Apply_Metadata
     (Path     : String;
      Metadata : Seven_Zip_Entry_Metadata);
   --  Restore supported filesystem metadata for an extracted 7z entry.

end Zlib.Seven_Zip_Properties;
