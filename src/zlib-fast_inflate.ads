--  Support level: private internal implementation.
--
--  A whole zlib stream decoded at once, quickly: the input complete in
--  memory, a 64-bit bit buffer refilled a byte at a time, Huffman codes
--  of up to ten bits found by one table lookup, and the output written
--  in place. The streaming decoder (Zlib.Stream_Inflate) remains the one
--  that says what is wrong with a stream: this one only succeeds or
--  declines, and a caller that is declined decodes with that one.
package Zlib.Fast_Inflate is

   --  Decode Input, a zlib stream -- header, Deflate data, Adler-32 --
   --  that ends exactly where Input ends.
   --
   --  @param Input The stream.
   --  @param Done True where it decoded and its checksum held; False where
   --    it declined: a preset dictionary, bytes after the stream, or
   --    anything wrong with it, which the streaming decoder then reports.
   --  @return The decoded bytes when Done; empty otherwise.
   function Decode_Zlib (Input : Zlib.Byte_Array; Done : out Boolean) return Zlib.Byte_Array;

end Zlib.Fast_Inflate;
