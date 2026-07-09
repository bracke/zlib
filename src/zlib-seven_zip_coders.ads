--  Support level: private internal implementation.
--
--  7z folder coder descriptor byte emission. This package keeps method
--  descriptor properties out of the monolithic container writer.

with Zlib.Seven_Zip_Methods;
with Interfaces;
with Zlib.LZMA_Properties;

package Zlib.Seven_Zip_Coders is

   PPMd_Default_Order  : constant Natural := 6;
   PPMd_Default_Memory : constant Interfaces.Unsigned_32 := 16#0100_0000#;

   function Descriptor_Bytes
     (Method     : Zlib.Seven_Zip_Methods.Seven_Zip_Coder_Method;
      LZMA_Props : Byte := Zlib.LZMA_Properties.Default_Props) return Byte_Array;
   --  Return the complete 7z coder descriptor bytes for Method. AES returns
   --  an empty array because encrypted writers emit per-archive AES props.

   function Delta_Descriptor_Bytes (Distance : Positive) return Byte_Array;
   --  Return a Delta coder descriptor with the requested one-based distance.

   function AES_Descriptor_Bytes
     (IV               : Byte_Array;
      Num_Cycles_Power : Natural := 19) return Byte_Array;
   --  Return an AES-256 coder descriptor with no salt and a 16-byte IV.

end Zlib.Seven_Zip_Coders;
