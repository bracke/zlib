package Zlib.Zstd_Decoder is
   --  Support level: private internal implementation.
   --  Pure-Ada zstd frame decoder.

   function Decode
     (Payload : Byte_Array;
      Status  : out Status_Code) return Byte_Array;
   --  Decode one or more zstd frames laid end to end, as zstd(1) accepts them.
   --  Skippable frames are ignored. A frame's optional content checksum is
   --  verified when present. Each frame is decoded on its own: no match,
   --  repeat offset or entropy table reaches back into an earlier frame.
   --
   --  Dictionaries are not supported: a frame that names one is refused rather
   --  than decoded wrongly.
   --
   --  @param Payload the zstd stream
   --  @param Status  Ok; Invalid_Header for a bad magic or frame header;
   --                 Unsupported_Method for a dictionary or a reserved block;
   --                 Invalid_Block_Type for an inconsistent block;
   --                 Invalid_Huffman_Code for bad entropy metadata;
   --                 Invalid_Distance when a match reaches before the frame;
   --                 Invalid_Checksum when the content checksum disagrees;
   --                 Unexpected_End_Of_Input when the stream is truncated;
   --                 Insufficient_Memory when the output does not fit
   --  @return the decompressed bytes, empty unless Status is Ok

end Zlib.Zstd_Decoder;
