with Zlib.Seven_Zip_Container;
with Zlib.Seven_Zip_Coders;
with Zlib.Seven_Zip_Paths;
with Zlib.PPMd7;

package body Zlib.Seven_Zip_Codec_Writing is

   function Build_Codec
     (Input         : Byte_Array;
      Entry_Name    : String;
      Method        : Zlib.Seven_Zip_Methods.Seven_Zip_Coder_Method;
      Metadata      : Seven_Zip_Entry_Metadata;
      Pack_Input    : not null access function
        (Input      : Byte_Array;
         LZMA_Props : in out Byte;
         Status     : out Status_Code) return Byte_Array;
      Status        : out Status_Code) return Byte_Array
   is
      Empty : constant Byte_Array (1 .. 0) := [others => 0];
   begin
      Status := Unsupported_Method;

      if not Zlib.Seven_Zip_Paths.Entry_Name_Valid (Entry_Name) then
         return Empty;
      end if;

      if Metadata.Is_Directory then
         return
           Zlib.Seven_Zip_Container.Header_Only_Entry
             (Entry_Name, Metadata, Status);
      end if;

      declare
         LZMA_Props  : Byte := 16#5D#;
         Pack_Status : Status_Code := Ok;
         Packed_Data : constant Byte_Array :=
           Pack_Input (Input, LZMA_Props, Pack_Status);
      begin
         if Pack_Status /= Ok then
            Status := Pack_Status;
            return Empty;
         end if;

         return
           Zlib.Seven_Zip_Container.Single_File_Archive
             (Packed_Data, Input, Entry_Name, Method, Metadata, Status,
              LZMA_Props);
      end;
   exception
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end Build_Codec;

   function Build_Copy
     (Input      : Byte_Array;
      Entry_Name : String;
      Metadata   : Seven_Zip_Entry_Metadata;
      Status     : out Status_Code) return Byte_Array
   is
      function Pack_Copy
        (Input_Data : Byte_Array;
         LZMA_Props : in out Byte;
         Status     : out Status_Code) return Byte_Array
      is
         pragma Unreferenced (LZMA_Props);
      begin
         Status := Ok;
         return Input_Data;
      end Pack_Copy;
   begin
      return
        Build_Codec
          (Input, Entry_Name, Zlib.Seven_Zip_Methods.Seven_Zip_Copy,
           Metadata, Pack_Copy'Access, Status);
   end Build_Copy;

   function Build_PPMd
     (Input      : Byte_Array;
      Entry_Name : String;
      Metadata   : Seven_Zip_Entry_Metadata;
      Status     : out Status_Code) return Byte_Array
   is
      function Pack_PPMd
        (Input_Data : Byte_Array;
         LZMA_Props : in out Byte;
         Status     : out Status_Code) return Byte_Array
      is
         pragma Unreferenced (LZMA_Props);
      begin
         Status := Ok;
         return
           Zlib.PPMd7.Compress
             (Input_Data, Zlib.Seven_Zip_Coders.PPMd_Default_Order,
              Zlib.Seven_Zip_Coders.PPMd_Default_Memory);
      end Pack_PPMd;
   begin
      return
        Build_Codec
          (Input, Entry_Name, Zlib.Seven_Zip_Methods.Seven_Zip_PPMd_Method,
           Metadata, Pack_PPMd'Access, Status);
   end Build_PPMd;

   function Build_LZMA2
     (Input      : Byte_Array;
      Entry_Name : String;
      Metadata   : Seven_Zip_Entry_Metadata;
      Encode     : not null access function
        (Input : Byte_Array) return Byte_Array;
      Status     : out Status_Code) return Byte_Array
   is
      function Pack_LZMA2
        (Input_Data : Byte_Array;
         LZMA_Props : in out Byte;
         Status     : out Status_Code) return Byte_Array
      is
         pragma Unreferenced (LZMA_Props);
      begin
         Status := Ok;
         return Encode (Input_Data);
      end Pack_LZMA2;
   begin
      return
        Build_Codec
          (Input, Entry_Name, Zlib.Seven_Zip_Methods.Seven_Zip_LZMA2_Method,
           Metadata, Pack_LZMA2'Access, Status);
   end Build_LZMA2;

   function Build_LZMA
     (Input      : Byte_Array;
      Entry_Name : String;
      Metadata   : Seven_Zip_Entry_Metadata;
      Encode     : not null access function
        (Input      : Byte_Array;
         LZMA_Props : in out Byte) return Byte_Array;
      Status     : out Status_Code) return Byte_Array
   is
      function Pack_LZMA
        (Input_Data : Byte_Array;
         LZMA_Props : in out Byte;
         Status     : out Status_Code) return Byte_Array
      is
      begin
         Status := Ok;
         return Encode (Input_Data, LZMA_Props);
      end Pack_LZMA;
   begin
      return
        Build_Codec
          (Input, Entry_Name, Zlib.Seven_Zip_Methods.Seven_Zip_LZMA_Method,
           Metadata, Pack_LZMA'Access, Status);
   end Build_LZMA;

   function Build_Deflate
     (Input      : Byte_Array;
      Entry_Name : String;
      Metadata   : Seven_Zip_Entry_Metadata;
      Compress   : not null access function
        (Input  : Byte_Array;
         Status : out Status_Code) return Byte_Array;
      Status     : out Status_Code) return Byte_Array
   is
      function Pack_Deflate
        (Input_Data : Byte_Array;
         LZMA_Props : in out Byte;
         Status     : out Status_Code) return Byte_Array
      is
         pragma Unreferenced (LZMA_Props);
      begin
         return Compress (Input_Data, Status);
      end Pack_Deflate;
   begin
      return
        Build_Codec
          (Input, Entry_Name, Zlib.Seven_Zip_Methods.Seven_Zip_Deflate_Method,
           Metadata, Pack_Deflate'Access, Status);
   end Build_Deflate;

   function Build_BZip2
     (Input      : Byte_Array;
      Entry_Name : String;
      Metadata   : Seven_Zip_Entry_Metadata;
      Compress   : not null access function
        (Input  : Byte_Array;
         Status : out Status_Code) return Byte_Array;
      Status     : out Status_Code) return Byte_Array
   is
      function Pack_BZip2
        (Input_Data : Byte_Array;
         LZMA_Props : in out Byte;
         Status     : out Status_Code) return Byte_Array
      is
         pragma Unreferenced (LZMA_Props);
      begin
         return Compress (Input_Data, Status);
      end Pack_BZip2;
   begin
      return
        Build_Codec
          (Input, Entry_Name, Zlib.Seven_Zip_Methods.Seven_Zip_BZip2_Method,
           Metadata, Pack_BZip2'Access, Status);
   end Build_BZip2;

   function Build_Method_Graph
     (Packed_Data    : Byte_Array;
      Entry_Name     : String;
      Coders         : Seven_Zip_Graph_Coder_Array;
      Bind_Pairs     : Seven_Zip_Bind_Pair_Array;
      Packed_Streams : Seven_Zip_Stream_Index_Array;
      Pack_Sizes     : Seven_Zip_Size_Array;
      Unpack_Sizes   : Seven_Zip_Size_Array;
      Unpacked_CRC   : Interfaces.Unsigned_32;
      Metadata       : Seven_Zip_Entry_Metadata;
      Status         : out Status_Code) return Byte_Array is
   begin
      return
        Zlib.Seven_Zip_Container.Method_Graph_Archive
          (Packed_Data, Entry_Name, Coders, Bind_Pairs, Packed_Streams,
           Pack_Sizes, Unpack_Sizes, Unpacked_CRC, Metadata, Status);
   end Build_Method_Graph;

end Zlib.Seven_Zip_Codec_Writing;
