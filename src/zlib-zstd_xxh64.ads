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

end Zlib.Zstd_XXH64;
