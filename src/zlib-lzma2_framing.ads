with Zlib.LZMA_Core;

package Zlib.LZMA2_Framing
  with SPARK_Mode => On
is
   --  Support level: private internal implementation.
   --  LZMA2 chunk header and control-byte helpers.

   Default_Props : constant Byte := Zlib.LZMA_Core.Default_Props;
   Max_Chunk     : constant Natural := 4096;

   type Control_Kind is (End_Marker, Uncompressed, Compressed, Invalid);

   type Control_Info is record
      Kind        : Control_Kind := Invalid;
      Need_Props  : Boolean := False;
      Reset_State : Boolean := False;
      Reset_Dict  : Boolean := False;
   end record;

   function Decode_Control
     (Control : Byte;
      First   : Boolean) return Control_Info;

   function Uncompressed_Size (Hi, Lo : Byte) return Natural
     with Post => Uncompressed_Size'Result in 1 .. 65_536;

   function Compressed_Unpacked_Size (Control, Hi, Lo : Byte) return Natural
     with Pre  => Control >= 16#80#,
          Post => Compressed_Unpacked_Size'Result in 1 .. 2 ** 21;

   function Packed_Size (Hi, Lo : Byte) return Natural
     with Post => Packed_Size'Result in 1 .. 65_536;

   function Uncompressed_Chunk
     (Chunk : Byte_Array;
      First : Boolean) return Byte_Array
     with Pre => Chunk'Length > 0 and then Chunk'Length <= 65_536;

   function Compressed_Chunk
     (Plain : Byte_Array;
      Coded : Byte_Array;
      Props : Byte) return Byte_Array
     with Pre =>
       Plain'Length > 0
       and then Plain'Length <= 2 ** 21
       and then Coded'Length > 0
       and then Coded'Length <= 65_536;

end Zlib.LZMA2_Framing;
