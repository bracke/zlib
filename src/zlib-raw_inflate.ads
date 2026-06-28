package Zlib.Raw_Inflate is
   --  Support level: private internal implementation.
   --  Quarantined internal Deflate decoder retained for maintenance comparison.
   --  Public callers use the root Zlib package. New public code must not call
   --  this package.

   function Decode
     (Input  : Zlib.Byte_Array;
      Status : out Zlib.Status_Code)
      return Zlib.Byte_Array;
   --  Decode a raw Deflate payload.
   --  @param Input raw Deflate blocks without zlib wrapper
   --  @param Status set to Ok or a deterministic decode failure
   --  @return inflated bytes when Status is Ok; otherwise invalid partial data
end Zlib.Raw_Inflate;
