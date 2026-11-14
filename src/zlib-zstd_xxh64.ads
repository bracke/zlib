with Interfaces;

package Zlib.Zstd_XXH64 is
   --  Support level: private internal implementation.
   --  XXH64, the hash zstd puts in a frame's optional content checksum.
   --
   --  CryptoLib.Hashes offers XXH3, which is a different algorithm with a
   --  different output -- it cannot stand in here. zstd stores the low 32 bits
   --  of the XXH64 of the frame's decompressed content.

   function Compute
     (Data : Byte_Array;
      Seed : Interfaces.Unsigned_64 := 0) return Interfaces.Unsigned_64;
   --  Hash Data.
   --  @param Data the bytes to hash
   --  @param Seed the seed; zstd always uses zero
   --  @return the 64-bit hash

   --  The same hash fed piecewise, for data that is not one contiguous array --
   --  a frame's span of a growing output vector, say. Feeding the bytes in any
   --  split gives the same result as Compute over their concatenation.

   type State is private;

   procedure Reset (S : out State; Seed : Interfaces.Unsigned_64 := 0);
   --  Start a hash.
   --  @param S    the hash state
   --  @param Seed the seed; zstd always uses zero

   procedure Update (S : in out State; Data : Byte_Array);
   --  Feed the next bytes.
   --  @param S    the hash state
   --  @param Data the bytes, which follow everything fed before

   function Digest (S : State) return Interfaces.Unsigned_64;
   --  The hash of everything fed since Reset; S is left as it was.
   --  @param S the hash state
   --  @return the 64-bit hash

private

   type State is record
      Seed     : Interfaces.Unsigned_64 := 0;
      V1       : Interfaces.Unsigned_64 := 0;
      V2       : Interfaces.Unsigned_64 := 0;
      V3       : Interfaces.Unsigned_64 := 0;
      V4       : Interfaces.Unsigned_64 := 0;
      Total    : Interfaces.Unsigned_64 := 0;
      Pending  : Byte_Array (0 .. 31) := [others => 0];
      Buffered : Natural range 0 .. 31 := 0;
   end record;
   --  Pending holds the bytes of a not-yet-complete 32-byte stripe.

end Zlib.Zstd_XXH64;
