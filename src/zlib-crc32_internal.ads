with Ada.Streams;
with Interfaces;

package Zlib.CRC32_Internal is
   --  Support level: private internal implementation.
   --  Incremental CRC-32 helper for gzip header and payload validation.

   type CRC32_State is private;
   --  Running CRC-32 state.

   procedure Reset
     (State : out CRC32_State);
   --  Reset State to the initial gzip CRC-32 value.
   --  @param State State argument supplied to Reset
   procedure Update
     (State : in out CRC32_State;
      B     : Ada.Streams.Stream_Element);
   --  Incorporate one byte.
   --  @param State State argument supplied to Update
   --  @param B B argument supplied to Update
   procedure Update_Raw
     (CRC : in out Interfaces.Unsigned_32;
      B   : Ada.Streams.Stream_Element);
   --  Incorporate one byte into a raw running CRC value. CRC must use the
   --  same unfinalized representation as CRC32_State. This helper keeps
   --  wrapper code on the shared CRC-32 table implementation without exposing
   --  CRC32_State internals.
   --  @param CRC CRC argument supplied to Update_Raw
   --  @param B B argument supplied to Update_Raw
   procedure Update
     (State : in out CRC32_State;
      Data  : Ada.Streams.Stream_Element_Array);
   --  Incorporate a byte slice in order.
   --  @param State State argument supplied to Update
   --  @param Data Data argument supplied to Update
   function Value
     (State : CRC32_State)
      return Interfaces.Unsigned_32;
   --  Return the finalized CRC-32 value.
   --  @param State State argument supplied to Value
   --  @return result produced by Value
private
   type CRC32_State is record
      CRC : Interfaces.Unsigned_32 := 16#FFFF_FFFF#;
   end record;
end Zlib.CRC32_Internal;
