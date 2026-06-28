with Zlib;

package Zlib_Bench_Support is
   type Wrapper_Kind is (Wrapper_Zlib, Wrapper_Gzip, Wrapper_Raw);
   type Pattern_Kind is (Pattern_Randomish, Pattern_Repeated, Pattern_Text_Like);

   type Compression_Config is record
      Wrapper      : Wrapper_Kind := Wrapper_Zlib;
      Mode         : Zlib.Compression_Mode := Zlib.Auto;
      Level        : Zlib.Compression_Level := Zlib.Default_Level;
      Use_Level    : Boolean := False;
      Have_Mode    : Boolean := False;
      Input_Chunk  : Positive := 32_768;
      Output_Chunk : Positive := 32_768;
      Repeat_Count : Positive := 1;
      Verify       : Boolean := True;
   end record;

   type Inflate_Config is record
      Wrapper      : Wrapper_Kind := Wrapper_Zlib;
      Input_Chunk  : Positive := 32_768;
      Output_Chunk : Positive := 32_768;
      Repeat_Count : Positive := 1;
      Expect_Size  : Natural := 0;
      Have_Expect  : Boolean := False;
   end record;

   function Header_For (Wrapper : Wrapper_Kind) return Zlib.Header_Type;
   --  Return the Header For result.
   --  @param Wrapper Wrapper argument supplied to Header_For
   --  @return result produced by Header_For

   function Wrapper_Image (Wrapper : Wrapper_Kind) return String;
   --  Return the Wrapper Image result.
   --  @param Wrapper Wrapper argument supplied to Wrapper_Image
   --  @return result produced by Wrapper_Image

   function Mode_Image (Mode : Zlib.Compression_Mode) return String;
   --  Return the Mode Image result.
   --  @param Mode Mode argument supplied to Mode_Image
   --  @return result produced by Mode_Image

   function Ratio (Compressed_Bytes, Input_Bytes : Natural) return Long_Float;
   --  Return the Ratio result.
   --  @param Compressed_Bytes Compressed_Bytes argument supplied to Ratio
   --  @param Input_Bytes Input_Bytes argument supplied to Ratio
   --  @return result produced by Ratio

   function Throughput_MiB_S (Bytes : Natural; Seconds : Duration) return Long_Float;
   --  Return the Throughput MiB S result.
   --  @param Bytes Bytes argument supplied to Throughput_MiB_S
   --  @param Seconds Seconds argument supplied to Throughput_MiB_S
   --  @return result produced by Throughput_MiB_S


   function Read_File (Path : String; Status : out Zlib.Status_Code) return Zlib.Byte_Array;
   --  Return the Read File result.
   --  @param Path Path argument supplied to Read_File
   --  @param Status Status argument supplied to Read_File
   --  @return result produced by Read_File

   function Synthetic_Data (Pattern : Pattern_Kind; Size : Natural) return Zlib.Byte_Array;
   --  Return the Synthetic Data result.
   --  @param Pattern Pattern argument supplied to Synthetic_Data
   --  @param Size Size argument supplied to Synthetic_Data
   --  @return result produced by Synthetic_Data


   function Parse_Wrapper (Value : String; Ok : out Boolean) return Wrapper_Kind;
   --  Return the Parse Wrapper result.
   --  @param Value Value argument supplied to Parse_Wrapper
   --  @param Ok Ok argument supplied to Parse_Wrapper
   --  @return result produced by Parse_Wrapper

   function Parse_Mode (Value : String; Ok : out Boolean) return Zlib.Compression_Mode;
   --  Return the Parse Mode result.
   --  @param Value Value argument supplied to Parse_Mode
   --  @param Ok Ok argument supplied to Parse_Mode
   --  @return result produced by Parse_Mode

   function Parse_Level (Value : String; Ok : out Boolean) return Zlib.Compression_Level;
   --  Return the Parse Level result.
   --  @param Value Value argument supplied to Parse_Level
   --  @param Ok Ok argument supplied to Parse_Level
   --  @return result produced by Parse_Level

   function Parse_Positive (Value : String; Ok : out Boolean) return Positive;
   --  Return the Parse Positive result.
   --  @param Value Value argument supplied to Parse_Positive
   --  @param Ok Ok argument supplied to Parse_Positive
   --  @return result produced by Parse_Positive

   function Parse_Natural (Value : String; Ok : out Boolean) return Natural;
   --  Return the Parse Natural result.
   --  @param Value Value argument supplied to Parse_Natural
   --  @param Ok Ok argument supplied to Parse_Natural
   --  @return result produced by Parse_Natural

   function Parse_Pattern (Value : String; Ok : out Boolean) return Pattern_Kind;
   --  Return the Parse Pattern result.
   --  @param Value Value argument supplied to Parse_Pattern
   --  @param Ok Ok argument supplied to Parse_Pattern
   --  @return result produced by Parse_Pattern


   function Starts_With (Text, Prefix : String) return Boolean;
   --  Return the Starts With result.
   --  @param Text Text argument supplied to Starts_With
   --  @param Prefix Prefix argument supplied to Starts_With
   --  @return result produced by Starts_With

   function Option_Value (Text, Prefix : String) return String;
   --  Return the Option Value result.
   --  @param Text Text argument supplied to Option_Value
   --  @param Prefix Prefix argument supplied to Option_Value
   --  @return result produced by Option_Value


   function Streaming_Compress
     (Input        : Zlib.Byte_Array;
      Config       : Compression_Config;
      Status       : out Zlib.Status_Code)
      return Zlib.Byte_Array;
   --  Return the Streaming Compress result.
   --  @param Input Input argument supplied to Streaming_Compress
   --  @param Config Config argument supplied to Streaming_Compress
   --  @param Status Status argument supplied to Streaming_Compress
   --  @return result produced by Streaming_Compress


   function Streaming_Inflate
     (Input        : Zlib.Byte_Array;
      Config       : Inflate_Config;
      Status       : out Zlib.Status_Code)
      return Zlib.Byte_Array;
   --  Return the Streaming Inflate result.
   --  @param Input Input argument supplied to Streaming_Inflate
   --  @param Config Config argument supplied to Streaming_Inflate
   --  @param Status Status argument supplied to Streaming_Inflate
   --  @return result produced by Streaming_Inflate

end Zlib_Bench_Support;
