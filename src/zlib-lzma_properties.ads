--  Support level: private internal implementation.
--
--  LZMA property-byte helpers shared by native 7z, LZMA2, and ZIP-LZMA
--  container paths. This package keeps the small, proof-friendly property
--  grammar separate from the large encoder/decoder implementation.

with Interfaces;

package Zlib.LZMA_Properties
  with SPARK_Mode => On
is

   Default_LC    : constant Natural := 3;
   Default_LP    : constant Natural := 0;
   Default_PB    : constant Natural := 2;
   Default_Dict  : constant Interfaces.Unsigned_32 := 16#0080_0000#;
   Default_Props : constant Byte := Byte ((Default_PB * 5 + Default_LP) * 9 + Default_LC);

   subtype LZMA_Properties is Byte_Array (1 .. 5);

   subtype LZMA_Raw_Header is Byte_Array (1 .. 9);

   function Valid_Props (Props : Byte) return Boolean;
   --  Return True when Props encodes a supported 7z LZMA lc/lp/pb tuple.

   function Props_Byte
     (LC, LP, PB : Natural) return Byte
     with Pre => LC <= 4 and then LP <= 4 and then PB <= 4 and then LC + LP <= 4;
   --  Return the 7z LZMA property byte for a valid lc/lp/pb tuple.

   function Default_Dict_Properties
     (Props : Byte) return LZMA_Properties;
   --  Return Props plus the default little-endian dictionary size bytes.

   function Raw_Stream_Header
     (Props : LZMA_Properties) return LZMA_Raw_Header;
   --  Return the internal raw-LZMA decode header prefix plus Props.

end Zlib.LZMA_Properties;
