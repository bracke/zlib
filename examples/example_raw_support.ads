with Zlib;

package Example_Raw_Support is
   function Plain return Zlib.Byte_Array;
   --  Return the Plain result.
   --  @return result produced by Plain


   function Streaming_Compress
     (Input  : Zlib.Byte_Array;
      Header : Zlib.Header_Type;
      Mode   : Zlib.Compression_Mode)
      return Zlib.Byte_Array;
   --  Return the Streaming Compress result.
   --  @param Input Input argument supplied to Streaming_Compress
   --  @param Header Header argument supplied to Streaming_Compress
   --  @param Mode Mode argument supplied to Streaming_Compress
   --  @return result produced by Streaming_Compress


   function Streaming_Inflate
     (Input  : Zlib.Byte_Array;
      Header : Zlib.Header_Type)
      return Zlib.Byte_Array;
   --  Return the Streaming Inflate result.
   --  @param Input Input argument supplied to Streaming_Inflate
   --  @param Header Header argument supplied to Streaming_Inflate
   --  @return result produced by Streaming_Inflate


   function Equal
     (Left  : Zlib.Byte_Array;
      Right : Zlib.Byte_Array)
      return Boolean;
   --  Return the Equal result.
   --  @param Left Left argument supplied to Equal
   --  @param Right Right argument supplied to Equal
   --  @return result produced by Equal

end Example_Raw_Support;
