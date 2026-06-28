with Ada.Streams;
with Interfaces;

package Zlib.Checksums is
   --  Support level: private internal implementation.
   --  One-shot and incremental Adler-32 helper for zlib wrapper validation.

   type Adler32_State is private;
   --  Running Adler-32 state.

   procedure Reset
     (State : out Adler32_State);
   --  Reset State to the initial Adler-32 value.
   --  @param State State argument supplied to Reset
   procedure Update
     (State : in out Adler32_State;
      B     : Zlib.Byte);
   --  Incorporate one public Zlib byte.
   --  @param State State argument supplied to Update
   --  @param B B argument supplied to Update
   procedure Update
     (State : in out Adler32_State;
      B     : Ada.Streams.Stream_Element);
   --  Incorporate one stream element byte.
   --  @param State State argument supplied to Update
   --  @param B B argument supplied to Update
   function Value
     (State : Adler32_State)
      return Interfaces.Unsigned_32;
   --  Return the current Adler-32 value.
   --  @param State State argument supplied to Value
   --  @return result produced by Value
   function Adler32
     (Data : Zlib.Byte_Array)
      return Interfaces.Unsigned_32;
   --  Compute Adler-32 over Data using the zlib checksum algorithm.
   --  @param Data bytes to checksum
   --  @return Adler-32 value in host integer form

private
   type Adler32_State is record
      A : Interfaces.Unsigned_32 := 1;
      B : Interfaces.Unsigned_32 := 0;
   end record;
end Zlib.Checksums;
