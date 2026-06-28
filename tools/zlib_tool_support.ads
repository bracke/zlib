with Zlib;

package Zlib_Tool_Support is
   function Read_File
     (Path   : String;
      Status : out Zlib.Status_Code)
      return Zlib.Byte_Array;
   --  Return the Read File result.
   --  @param Path Path argument supplied to Read_File
   --  @param Status Status argument supplied to Read_File
   --  @return result produced by Read_File


   procedure Write_File
     (Path   : String;
      Data   : Zlib.Byte_Array;
      Status : out Zlib.Status_Code);
   --  Perform the Write File operation.
   --  @param Path Path argument supplied to Write_File
   --  @param Data Data argument supplied to Write_File
   --  @param Status Status argument supplied to Write_File


   function Mode_From_Option
     (Option : String;
      Status : out Zlib.Status_Code)
      return Zlib.Compression_Mode;
   --  Return the Mode From Option result.
   --  @param Option Option argument supplied to Mode_From_Option
   --  @param Status Status argument supplied to Mode_From_Option
   --  @return result produced by Mode_From_Option


   function Level_From_Option
     (Option : String;
      Status : out Zlib.Status_Code)
      return Zlib.Compression_Level;
   --  Return the Level From Option result.
   --  @param Option Option argument supplied to Level_From_Option
   --  @param Status Status argument supplied to Level_From_Option
   --  @return result produced by Level_From_Option


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


   function Streaming_Compress
     (Input  : Zlib.Byte_Array;
      Header : Zlib.Header_Type;
      Level  : Zlib.Compression_Level)
      return Zlib.Byte_Array;
   --  Return the Streaming Compress result.
   --  @param Input Input argument supplied to Streaming_Compress
   --  @param Header Header argument supplied to Streaming_Compress
   --  @param Level Level argument supplied to Streaming_Compress
   --  @return result produced by Streaming_Compress

end Zlib_Tool_Support;
