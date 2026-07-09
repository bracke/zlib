--  Support level: private internal implementation.
--
--  7z variable-length integer encoding helpers used by native container
--  writers. This package keeps the byte-level number grammar separate from
--  higher-level archive assembly.

with Interfaces;

package Zlib.Seven_Zip_Numbers
  with SPARK_Mode => On
is

   subtype Encoded_Number_Length is Positive range 1 .. 9;

   function Encoded_Length
     (Value : Interfaces.Unsigned_64)
      return Encoded_Number_Length;
   --  Return the number of bytes needed for the 7z encoded UInt64 form.

   function Encode_Number
     (Value : Interfaces.Unsigned_64)
      return Byte_Array
     with Post => Encode_Number'Result'Length = Encoded_Length (Value),
          SPARK_Mode => Off;
   --  Return Value encoded as a 7z UInt64.

   function U32_At
     (Data : Byte_Array;
      Pos  : Natural)
      return Interfaces.Unsigned_32
     with Pre => Pos >= Data'First
                   and then Pos <= Data'Last
                   and then Data'Last - Pos >= 3;
   --  Return the little-endian UInt32 at Pos.

   function U64_At
     (Data : Byte_Array;
      Pos  : Natural)
      return Interfaces.Unsigned_64
     with Pre => Pos >= Data'First
                   and then Pos <= Data'Last
                   and then Data'Last - Pos >= 7;
   --  Return the little-endian UInt64 at Pos.

   function Read_Number
     (Data  : Byte_Array;
      Pos   : in out Natural;
      Last  : Natural;
      Value : out Interfaces.Unsigned_64) return Boolean
     with SPARK_Mode => Off;
   --  Read a 7z variable-length UInt64 at Pos and advance Pos on success.

end Zlib.Seven_Zip_Numbers;
