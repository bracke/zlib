with Zlib.Seven_Zip_Methods;
with Interfaces;

--  Support level: private internal implementation.
--
--  Native 7z folder graph analysis shared by read-side extraction paths.
--  Codec execution remains callback-owned by the root body while it depends on
--  root-only Deflate/LZMA/BZip2 entry points.

package Zlib.Seven_Zip_Folder_Decoding is
   Max_Folder_Coders : constant Positive := 8;

   type Folder_Method_Array is
     array (Positive range <>) of Zlib.Seven_Zip_Methods.Seven_Zip_Coder_Method;
   type Coder_Link_Array is array (1 .. Max_Folder_Coders) of Natural;

   type Folder_Graph_Info is record
      Packed_Coder      : Natural := 1;
      Terminal_Coder    : Natural := 1;
      Next_Coder        : Coder_Link_Array := [others => 0];
      Reverse_Chain     : Boolean := False;
      Pack_Count        : Natural := 1;
      Pack_Indices_Read : Boolean := False;
   end record;

   function Analyze_Bind_Pairs
     (Archive_Image : Byte_Array;
      Pos           : in out Natural;
      Header_Last   : Natural;
      Coder_Count   : Positive;
      Methods       : Folder_Method_Array;
      Info          : out Folder_Graph_Info) return Boolean;
   --  Read and validate bind pairs for one folder and report the packed coder,
   --  terminal coder, coder links, and packed-stream count.

   subtype LZMA_Props is Byte_Array (1 .. 5);
   subtype AES_Block is Byte_Array (1 .. 16);

   type Folder_Coder_Info is record
      Method         : Zlib.Seven_Zip_Methods.Seven_Zip_Coder_Method :=
        Zlib.Seven_Zip_Methods.Seven_Zip_Copy;
      LZMA_Props     : Zlib.Seven_Zip_Folder_Decoding.LZMA_Props :=
        [others => 0];
      Expected_Size  : Natural := 0;
      Delta_Distance : Positive := 1;
      PPMd_Order     : Natural := 0;
      PPMd_Memory    : Interfaces.Unsigned_32 := 0;
      AES_Cycles     : Natural := 0;
      AES_Salt_Len   : Natural := 0;
      AES_IV_Len     : Natural := 0;
      AES_Salt       : AES_Block := [others => 0];
      AES_IV         : AES_Block := [others => 0];
   end record;

   type Folder_Coder_Array is array (Positive range <>) of Folder_Coder_Info;

   function Decode_Coder_Chain
     (Input       : Byte_Array;
      Password    : String;
      Coders      : Folder_Coder_Array;
      First_Coder : Natural;
      Next_Coder  : Coder_Link_Array;
      Decode_Core : not null access function
        (Input         : Byte_Array;
         Method        : Zlib.Seven_Zip_Methods.Seven_Zip_Coder_Method;
         LZMA_Props    : Byte_Array;
         Expected_Size : Natural;
         Status        : out Status_Code) return Byte_Array;
      Status      : out Status_Code) return Byte_Array;
   --  Decode a linear folder coder chain. Root-only codecs are supplied by
   --  Decode_Core; filters, AES, Copy, and PPMd are handled internally.

   function Decode_BCJ2_Graph
     (Main_Input : Byte_Array;
      Call_Input : Byte_Array;
      Jump_Input : Byte_Array;
      Range_Input : Byte_Array;
      Coders      : Folder_Coder_Array;
      Output_Size : Natural;
      Decode_Core : not null access function
        (Input         : Byte_Array;
         Method        : Zlib.Seven_Zip_Methods.Seven_Zip_Coder_Method;
         LZMA_Props    : Byte_Array;
         Expected_Size : Natural;
         Status        : out Status_Code) return Byte_Array;
      Status      : out Status_Code) return Byte_Array;
   --  Decode a BCJ2 folder graph, including optional main-stream pre-coders.
   --  Root-only codecs are supplied by Decode_Core.

   function Validate_And_Slice_Substream
     (Plain                 : Byte_Array;
      Folder_Index          : Natural;
      Target_Index          : Natural;
      Folder_Size           : Interfaces.Unsigned_64;
      Folder_CRC_Defined    : Boolean;
      Folder_CRC            : Interfaces.Unsigned_32;
      Substream_Folder      : not null access function
        (Index : Natural) return Natural;
      Substream_Size        : not null access function
        (Index : Natural) return Interfaces.Unsigned_64;
      Substream_CRC_Defined : not null access function
        (Index : Natural) return Boolean;
      Substream_CRC         : not null access function
        (Index : Natural) return Interfaces.Unsigned_32;
      Status                : out Status_Code) return Byte_Array;
   --  Validate a decoded folder payload and return Target_Index's slice from
   --  its solid folder, including folder and substream CRC checks.

   function Decode_PPMd_With_Fallback
     (Payload               : Byte_Array;
      Output_Size           : Natural;
      Folder_Output_Size    : Natural;
      Order                 : Natural;
      Memory                : Interfaces.Unsigned_32;
      Has_Next_Coder        : Boolean;
      Folder_CRC_Defined    : Boolean;
      Folder_CRC            : Interfaces.Unsigned_32;
      Substream_CRC_Defined : Boolean;
      Substream_CRC         : Interfaces.Unsigned_32;
      Substream_Size        : Interfaces.Unsigned_64;
      Finish                : not null access function
        (Plain  : Byte_Array;
         Status : out Status_Code) return Byte_Array;
      Status                : out Status_Code) return Byte_Array;
   --  Decode a PPMd packed stream using the compatibility retry/fallback
   --  policy required by existing native 7z extraction tests. Finish validates
   --  the decoded folder image and returns the requested substream.

end Zlib.Seven_Zip_Folder_Decoding;
