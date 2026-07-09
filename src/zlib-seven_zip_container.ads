with Interfaces;
with Zlib.Seven_Zip_Filters;
with Zlib.Seven_Zip_Methods;
with Zlib.Seven_Zip_Properties;

--  Support level: private internal implementation.
--
--  7z container envelope construction shared by native archive writers.

package Zlib.Seven_Zip_Container is

   type Start_Header_Info is record
      Payload_First : Natural := 0;
      Header_First  : Natural := 0;
      Header_Last   : Natural := 0;
      Payload_Count : Natural := 0;
      Header_Count  : Natural := 0;
      Header_CRC    : Interfaces.Unsigned_32 := 0;
   end record;

   type Boolean_Array is array (Positive range <>) of Boolean;
   type U32_Array is array (Positive range <>) of Interfaces.Unsigned_32;
   type U64_Array is array (Positive range <>) of Interfaces.Unsigned_64;

   function UTF16LE_NT (Text : String) return Byte_Array;
   --  Encode Text as a 7z UTF-16LE null-terminated name fragment.

   function Packed_Bits
     (Bits  : Boolean_Array;
      Count : Natural) return Byte_Array;
   --  Pack Count one-based boolean flags using the 7z high-bit-first bitmap format.

   function Read_Byte
     (Data : Byte_Array;
      Pos  : in out Natural;
      Last : Natural;
      B    : out Byte) return Boolean;
   --  Read one byte from Data when Pos is inside Last, then advance Pos.

   function Expect_Byte
     (Data     : Byte_Array;
      Pos      : in out Natural;
      Last     : Natural;
      Expected : Byte) return Boolean;
   --  Read one byte and compare it with Expected.

   function Has_Bytes
     (Pos   : Natural;
      Last  : Natural;
      Count : Natural) return Boolean
     with SPARK_Mode => On;
   --  Return True when Count bytes are available in Pos .. Last.

   function Find_Signature
     (Data : Byte_Array;
      Pos  : out Natural) return Boolean;
   --  Find a 7z signature header, accepting SFX prefixes with a valid start CRC.

   function Has_Archive_Signature (Data : Byte_Array) return Boolean
     with SPARK_Mode => On;
   --  Return True when Data starts with the 7z archive signature bytes.

   function Skip_Properties
     (Data : Byte_Array;
      Pos  : in out Natural;
      Last : Natural) return Boolean;
   --  Skip a sequence of sized 7z property records through kEnd.

   function Read_Start_Header
     (Archive       : Byte_Array;
      Signature_Pos : Natural;
      Info          : out Start_Header_Info;
      Status        : in out Status_Code) return Boolean;
   --  Decode and validate the 7z start header at Signature_Pos.

   function Build_Archive
     (Header  : Byte_Array;
      Payload : Byte_Array) return Byte_Array;
   --  Build a complete 7z archive from an encoded next header and payload.

   function Header_Only_Entry
     (Entry_Name : String;
      Metadata   : Seven_Zip_Entry_Metadata;
      Status     : out Status_Code) return Byte_Array;
   --  Build a complete 7z archive containing one no-stream directory entry.

   function Single_File_Archive
     (Packed_Data   : Byte_Array;
      Unpacked_Data : Byte_Array;
      Entry_Name    : String;
      Method        : Zlib.Seven_Zip_Methods.Seven_Zip_Coder_Method;
      Metadata      : Seven_Zip_Entry_Metadata;
      Status        : out Status_Code;
      LZMA_Props    : Byte) return Byte_Array;
   --  Build a complete one-file 7z archive for one packed stream and coder.

   function Filtered_Archive
     (Packed_Data    : Byte_Array;
      Filtered_Data  : Byte_Array;
      Unpacked_Data  : Byte_Array;
      Entry_Name     : String;
      Filter_Method  : Zlib.Seven_Zip_Methods.Seven_Zip_Coder_Method;
      Codec_Method   : Zlib.Seven_Zip_Methods.Seven_Zip_Coder_Method;
      Delta_Distance : Positive;
      Metadata       : Seven_Zip_Entry_Metadata;
      Status         : out Status_Code;
      LZMA_Props     : Byte) return Byte_Array;
   --  Build a complete single-entry 7z archive with codec + filter coders.

   function Method_Graph_Archive
     (Packed_Data    : Byte_Array;
      Entry_Name     : String;
      Coders         : Seven_Zip_Graph_Coder_Array;
      Bind_Pairs     : Seven_Zip_Bind_Pair_Array;
      Packed_Streams : Seven_Zip_Stream_Index_Array;
      Pack_Sizes     : Seven_Zip_Size_Array;
      Unpack_Sizes   : Seven_Zip_Size_Array;
      Unpacked_CRC   : Interfaces.Unsigned_32;
      Metadata       : Seven_Zip_Entry_Metadata;
      Status         : out Status_Code) return Byte_Array;
   --  Build a complete single-entry arbitrary method-graph 7z archive.

   function Stored_File_List_Archive
     (Payload            : Byte_Array;
      Entry_Names        : Text_Array;
      Sizes              : U64_Array;
      CRCs               : U32_Array;
      Metadata           : Zlib.Seven_Zip_Properties.Entry_Metadata_Array;
      Entry_Is_Directory : Boolean_Array;
      Stream_Count       : Natural;
      Status             : out Status_Code) return Byte_Array;
   --  Build a complete stored multi-entry 7z archive with one Copy folder.

   function Compressed_File_List_Archive
     (Payload              : Byte_Array;
      Entry_Names          : Text_Array;
      Method               : Zlib.Seven_Zip_Methods.Seven_Zip_Coder_Method;
      Pack_Sizes           : U64_Array;
      Pack_CRCs            : U32_Array;
      Unpack_Sizes         : U64_Array;
      Unpack_CRCs          : U32_Array;
      LZMA_Props           : Byte_Array;
      Metadata             : Zlib.Seven_Zip_Properties.Entry_Metadata_Array;
      Entry_Is_Directory   : Boolean_Array;
      Stream_Count         : Natural;
      Solid                : Boolean;
      Encrypt              : Boolean;
      Solid_Compressed_Len : Natural;
      AES_IV               : Byte_Array;
      Status               : out Status_Code) return Byte_Array;
   --  Build a complete compressed multi-entry 7z archive.

   function AES_LZMA_Archive
     (Packed_Data     : Byte_Array;
      Entry_Name      : String;
      Compressed_Size : Natural;
      Plain_Size      : Natural;
      Plain_CRC       : Interfaces.Unsigned_32;
      IV              : Byte_Array;
      LZMA_Props      : Byte;
      Status          : out Status_Code) return Byte_Array;
   --  Build a complete single-entry AES -> LZMA 7z archive.

   function BCJ2_Archive
     (Streams    : Zlib.Seven_Zip_Filters.BCJ2_Encoded_Streams;
      Entry_Name : String;
      Plain_Size : Natural;
      Plain_CRC  : Interfaces.Unsigned_32;
      Status     : out Status_Code) return Byte_Array;
   --  Build a complete single-entry stored BCJ2 7z archive.

   function AES_LZMA_Encoded_Header
     (Pack_Offset     : Interfaces.Unsigned_64;
      Encrypted_Size  : Interfaces.Unsigned_64;
      Compressed_Size : Interfaces.Unsigned_64;
      Plain_Size      : Interfaces.Unsigned_64;
      IV              : Byte_Array;
      LZMA_Props      : Byte) return Byte_Array;
   --  Build kEncodedHeader StreamsInfo for an AES -> LZMA header folder.

   function Encrypted_Header_Archive
     (Main_Pack         : Byte_Array;
      Encrypted_Header  : Byte_Array;
      Compressed_Size   : Natural;
      Plain_Header_Size : Natural;
      IV                : Byte_Array;
      LZMA_Props        : Byte;
      Status            : out Status_Code) return Byte_Array;
   --  Build a complete archive whose next header is AES -> LZMA encoded.

end Zlib.Seven_Zip_Container;
