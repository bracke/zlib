with Ada.Streams;
with Interfaces;

with Zlib.Checksums;
with Zlib.CRC32_Internal;
with Zlib.Huffman;
with Zlib.Sliding_Window;
with Zlib.Stream_Bits;

package Zlib.Stream_Inflate is
   --  Support level: private internal implementation.
   --  Internal incremental Deflate inflater used by the public streaming API.
   --  Supports zlib-wrapped, gzip-wrapped, and raw stored, fixed-Huffman,
   --  and dynamic-Huffman Deflate streams.

   type Inflate_State is
     (Need_Block_Header,
      Stored_Align,
      Stored_Len_Lo,
      Stored_Len_Hi,
      Stored_NLen_Lo,
      Stored_NLen_Hi,
      Stored_Data,
      Fixed_Init,
      Dynamic_Header_HLIT,
      Dynamic_Header_HDIST,
      Dynamic_Header_HCLEN,
      Dynamic_Code_Length_Code_Lengths,
      Dynamic_Code_Length_Table,
      Dynamic_All_Code_Lengths,
      Dynamic_Build_Tables,
      Compressed_Symbol,
      Compressed_Literal,
      Length_Extra,
      Distance_Symbol,
      Distance_Extra,
      Copying_Match,
      Finished,
      Failed);
   --  Internal Deflate block decoder state.

   type Wrapper_State is
     (Need_CMF,
      Need_FLG,
      Need_DICTID_1,
      Need_DICTID_2,
      Need_DICTID_3,
      Need_DICTID_4,
      Deflate_Data,
      Need_Adler_1,
      Need_Adler_2,
      Need_Adler_3,
      Need_Adler_4,
      Need_GZip_ID1,
      Need_GZip_ID2,
      Need_GZip_CM,
      Need_GZip_FLG,
      Need_GZip_MTIME_0,
      Need_GZip_MTIME_1,
      Need_GZip_MTIME_2,
      Need_GZip_MTIME_3,
      Need_GZip_XFL,
      Need_GZip_OS,
      Need_GZip_XLEN_0,
      Need_GZip_XLEN_1,
      GZip_Extra_Data,
      GZip_File_Name,
      GZip_Comment,
      Need_GZip_HCRC_0,
      Need_GZip_HCRC_1,
      Need_GZip_CRC_0,
      Need_GZip_CRC_1,
      Need_GZip_CRC_2,
      Need_GZip_CRC_3,
      Need_GZip_ISIZE_0,
      Need_GZip_ISIZE_1,
      Need_GZip_ISIZE_2,
      Need_GZip_ISIZE_3,
      Done,
      Failed);
   --  Internal wrapper parser and trailer-validation state.

   type Decode_Status is
     (Ok,
      Need_Input,
      Need_Output,
      Member_End,
      Stream_End,
      Unsupported,
      Malformed,
      Checksum_Error);
   --  Result of one incremental decoder step. Member_End reports a
   --  fully validated gzip member boundary; the public streaming layer
   --  decides whether that is the logical stream end or whether another
   --  concatenated gzip member must be decoded.

   type Decoder is private;
   --  Combined wrapper, Deflate, Huffman, checksum, and trailer state.

   procedure Reset
     (D : in out Decoder);
   --  Reset D to the start of a new explicit-wrapper decode operation.
   --  @param D D argument supplied to Reset
   procedure Reset_GZip_Member
     (D : in out Decoder);
   --  Reset only the per-member gzip and Deflate state so that a
   --  concatenated gzip member can be decoded from the current input
   --  position. The caller-owned bit source, sliding output window, and
   --  streaming filter lifecycle are not reset.
   --  @param D D argument supplied to Reset_GZip_Member
   procedure Set_Dictionary_ID
     (D       : in out Decoder;
      Dict_ID : Interfaces.Unsigned_32);
   --  Record the Adler-32 DICTID of the caller-supplied preset dictionary.
   --  @param D D argument supplied to Set_Dictionary_ID
   --  @param Dict_ID Dict_ID argument supplied to Set_Dictionary_ID
   function Can_Set_Dictionary
     (D : Decoder)
      return Boolean;
   --  Return True while no wrapper or Deflate byte has been decoded yet.
   --  @param D D argument supplied to Can_Set_Dictionary
   --  @return result produced by Can_Set_Dictionary
   procedure Decode
     (D      : in out Decoder;
      Header : Zlib.Header_Type;
      Source : in out Zlib.Stream_Bits.Bit_Source;
      Window : in out Zlib.Sliding_Window.Window;
      Status : out Decode_Status);
   --  Advance decoding until input, output space, stream end, or error.
   --  @param D D argument supplied to Decode
   --  @param Header Header argument supplied to Decode
   --  @param Source Source argument supplied to Decode
   --  @param Window Window argument supplied to Decode
   --  @param Status Status argument supplied to Decode
   function Is_Finished
     (D : Decoder)
      return Boolean;
   --  Return True after the active wrapper mode has fully validated.
   --  @param D D argument supplied to Is_Finished
   --  @return result produced by Is_Finished
   function Is_Failed
     (D : Decoder)
      return Boolean;
   --  Return True after a malformed, unsupported, or checksum failure.
   --  @param D D argument supplied to Is_Failed
   --  @return result produced by Is_Failed
   function Last_Status
     (D : Decoder)
      return Zlib.Status_Code;
   --  Return the public status code corresponding to the last failure.
   --  @param D D argument supplied to Last_Status
   --  @return result produced by Last_Status
private
   type Decoder is record
      Inflate        : Inflate_State := Need_Block_Header;
      Wrapper        : Wrapper_State := Need_CMF;
      BFinal         : Boolean := False;
      CMF            : Ada.Streams.Stream_Element := 0;
      FLG            : Ada.Streams.Stream_Element := 0;
      Len            : Natural range 0 .. 65_535 := 0;
      NLen           : Natural range 0 .. 65_535 := 0;
      Stored_Left    : Natural range 0 .. 65_535 := 0;

      Dist_Table_Empty : Boolean := False;
      Lit_Len_Table  : Zlib.Huffman.Decode_Table;
      Dist_Table     : Zlib.Huffman.Decode_Table;

      Dynamic_HLIT  : Natural range 0 .. 286 := 0;
      Dynamic_HDIST : Natural range 0 .. 32 := 0;
      Dynamic_HCLEN : Natural range 0 .. 19 := 0;
      Dynamic_Code_Length_Index : Natural range 0 .. 19 := 0;
      Dynamic_Length_Index      : Natural range 0 .. 318 := 0;
      Dynamic_Total_Lengths     : Natural range 0 .. 318 := 0;
      Code_Length_Lengths : Zlib.Huffman.Code_Length_Array (0 .. 18) := [others => 0];
      All_Lengths         : Zlib.Huffman.Code_Length_Array (0 .. 317) := [others => 0];
      Code_Length_Table   : Zlib.Huffman.Decode_Table;
      Previous_Code_Length : Zlib.Huffman.Code_Length := 0;
      Have_Previous_Length : Boolean := False;
      Pending_Repeat_Symbol : Natural range 0 .. 18 := 0;
      Have_Pending_Repeat   : Boolean := False;

      Huff_Code      : Natural := 0;
      Huff_Length    : Zlib.Huffman.Code_Length := 0;
      Symbol         : Natural := 0;
      Length_Value   : Natural range 0 .. 258 := 0;
      Distance_Value : Natural range 0 .. 32_768 := 0;

      Adler          : Zlib.Checksums.Adler32_State;
      Expected_Adler : Interfaces.Unsigned_32 := 0;
      Dictionary_ID  : Interfaces.Unsigned_32 := 0;
      Expected_Dictionary_ID : Interfaces.Unsigned_32 := 0;
      Dictionary_Supplied : Boolean := False;

      GZip_FLG       : Ada.Streams.Stream_Element := 0;
      GZip_XLEN      : Natural range 0 .. 65_535 := 0;
      GZip_Extra_Left : Natural range 0 .. 65_535 := 0;
      GZip_Header_CRC : Zlib.CRC32_Internal.CRC32_State;
      GZip_Data_CRC   : Zlib.CRC32_Internal.CRC32_State;
      GZip_HCRC       : Interfaces.Unsigned_32 := 0;
      GZip_Expected_CRC   : Interfaces.Unsigned_32 := 0;
      GZip_Expected_ISIZE : Interfaces.Unsigned_32 := 0;
      GZip_ISIZE          : Interfaces.Unsigned_32 := 0;
      Last_Status         : Zlib.Status_Code := Zlib.Ok;
   end record;
end Zlib.Stream_Inflate;
