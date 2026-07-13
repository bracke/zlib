with Interfaces;

package Zlib.BZip2_CRC is
   --  Support level: private internal implementation.
   --  bzip2's unreflected, MSB-first CRC-32 (polynomial 16#04C1_1DB7#).
   --
   --  This is NOT the CRC-32 the rest of the crate uses. Deflate, ZIP and 7z all
   --  use the reflected polynomial 16#EDB8_8320# (via CryptoLib.Checksums), which
   --  shifts right and feeds bytes in least-significant-bit-first. bzip2 shifts
   --  left and feeds bytes most-significant-bit-first, so the two disagree on
   --  every input and cannot share a table.

   subtype Checksum is Interfaces.Unsigned_32;

   Initial : constant Checksum := 16#FFFF_FFFF#;
   --  Starting value of a running block checksum.

   function Update (Current : Checksum; Data : Byte_Array) return Checksum;
   --  Fold Data into a running block checksum.
   --  @param Current running value, starting from Initial
   --  @param Data    bytes to incorporate, in order
   --  @return the updated running value

   function Finish (Current : Checksum) return Checksum;
   --  Complete a running block checksum.
   --  @param Current the running value returned by Update
   --  @return the final block CRC, as stored in the block header

   function Compute (Data : Byte_Array) return Checksum;
   --  One-shot block checksum: Finish (Update (Initial, Data)).
   --  @param Data the block's decompressed bytes
   --  @return the block CRC

   function Combine (Running : Checksum; Block : Checksum) return Checksum;
   --  Fold a block CRC into the stream's combined CRC, as the stream trailer
   --  stores it: rotate the running value left by one bit, then XOR the block's.
   --  @param Running the combined value so far (0 before the first block)
   --  @param Block   the block CRC to fold in
   --  @return the updated combined value

end Zlib.BZip2_CRC;
