--  Support level: private internal implementation.
--
--  7z AES-256 encryption helpers (method 06F10701: AES-256 + SHA-256).
--  Key derivation and the AES-256-CBC cipher are provided by the cryptolib
--  crate; this package adapts them to the crate's Byte_Array interface and the
--  7z key-derivation rule. Validated bit-exact against stock 7-Zip: decrypting
--  a stock-encrypted pack reproduces the exact inner (e.g. LZMA) stream.

with Interfaces;

package Zlib.Seven_Zip_AES is

   function Derive_Key
     (Password         : String;
      Salt             : Byte_Array;
      Num_Cycles_Power : Natural) return Byte_Array;
   --  7z AES key derivation: iterated SHA-256 over the salt, the UTF-16LE
   --  password, and an 8-byte little-endian counter, for 2**Num_Cycles_Power
   --  rounds. Returns a 32-byte AES-256 key.
   --  @param Password the archive password (treated as Latin-1 -> UTF-16LE)
   --  @param Salt the coder salt (may be empty)
   --  @param Num_Cycles_Power log2 of the iteration count

   function Decrypt_CBC (Key, IV, Ciphertext : Byte_Array) return Byte_Array;
   --  AES-256-CBC decrypt. Key is 32 bytes, IV 16 bytes, Ciphertext a
   --  multiple of 16 bytes. Returns the same length as Ciphertext.

   function Encrypt_CBC (Key, IV, Plaintext : Byte_Array) return Byte_Array;
   --  AES-256-CBC encrypt. Plaintext must be a multiple of 16 bytes.

   function Pad_To_Block (Data : Byte_Array) return Byte_Array;
   --  Zero-pad Data up to the next 16-byte boundary (7z AES padding).

   function Random_IV return Byte_Array;
   --  16 cryptographically-random bytes (CSPRNG) for an AES-CBC IV. Falls
   --  back to zeros only if the system entropy source is unavailable.

end Zlib.Seven_Zip_AES;
