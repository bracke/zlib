with Zlib;

package Zlib_Conformance_Test_Support is
   procedure Assert_Bytes_Equal
     (Actual   : Zlib.Byte_Array;
      Expected : Zlib.Byte_Array;
      Message  : String);
   --  Perform the Assert Bytes Equal operation.
   --  @param Actual Actual argument supplied to Assert_Bytes_Equal
   --  @param Expected Expected argument supplied to Assert_Bytes_Equal
   --  @param Message Message argument supplied to Assert_Bytes_Equal

   procedure Assert_One_Shot_OK
     (Input    : Zlib.Byte_Array;
      Header   : Zlib.Header_Type;
      Expected : Zlib.Byte_Array;
      Message  : String);
   --  Perform the Assert One Shot OK operation.
   --  @param Input Input argument supplied to Assert_One_Shot_OK
   --  @param Header Header argument supplied to Assert_One_Shot_OK
   --  @param Expected Expected argument supplied to Assert_One_Shot_OK
   --  @param Message Message argument supplied to Assert_One_Shot_OK

   procedure Assert_One_Shot_Fails
     (Input   : Zlib.Byte_Array;
      Header  : Zlib.Header_Type;
      Message : String);
   --  Perform the Assert One Shot Fails operation.
   --  @param Input Input argument supplied to Assert_One_Shot_Fails
   --  @param Header Header argument supplied to Assert_One_Shot_Fails
   --  @param Message Message argument supplied to Assert_One_Shot_Fails

   procedure Assert_Streaming_OK
     (Input       : Zlib.Byte_Array;
      Header      : Zlib.Header_Type;
      Expected    : Zlib.Byte_Array;
      Chunk_Size  : Positive;
      Output_Size : Positive;
      Message     : String);
   --  Perform the Assert Streaming OK operation.
   --  @param Input Input argument supplied to Assert_Streaming_OK
   --  @param Header Header argument supplied to Assert_Streaming_OK
   --  @param Expected Expected argument supplied to Assert_Streaming_OK
   --  @param Chunk_Size Chunk_Size argument supplied to Assert_Streaming_OK
   --  @param Output_Size Output_Size argument supplied to Assert_Streaming_OK
   --  @param Message Message argument supplied to Assert_Streaming_OK

   procedure Expect_Streaming_Zlib_Error
     (Input   : Zlib.Byte_Array;
      Header  : Zlib.Header_Type;
      Message : String);
   --  Perform the Expect Streaming Zlib Error operation.
   --  @param Input Input argument supplied to Expect_Streaming_Zlib_Error
   --  @param Header Header argument supplied to Expect_Streaming_Zlib_Error
   --  @param Message Message argument supplied to Expect_Streaming_Zlib_Error

end Zlib_Conformance_Test_Support;
