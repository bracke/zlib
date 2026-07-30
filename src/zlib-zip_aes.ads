--  Support level: private internal implementation.
--
--  WinZip AES ("AE-1"/"AE-2") decryption for encrypted ZIP members
--  (compression method 99, extra-field header id 0x9901). Read-only: this
--  reproduces the scheme WinZip and Info-ZIP write, so a stock AES-encrypted
--  ZIP can be opened; it never writes one. The cryptographic primitives --
--  PBKDF2-HMAC-SHA1, HMAC-SHA1, and the AES-CTR keystream -- come from the
--  cryptolib crate; this package adapts them to the zlib crate's Byte_Array
--  interface and the WinZip-AES wire format, and fails closed on any doubt.
--
--  Ported from the archive application's validated ZIP-AES reader, which was
--  checked against stock WinZip/Info-ZIP output.

with Interfaces;

private package Zlib.Zip_AES is

   --  A parsed WinZip-AES extra field (header id 0x9901). Present is True when
   --  a 0x9901 record was found for the entry, regardless of whether it was
   --  well formed; Valid is True only when it also carries a known version and
   --  strength, so callers can tell "not an AES entry" (Present = False) from
   --  "an AES entry we refuse to trust" (Present and not Valid).
   type AES_Params is record
      Present       : Boolean := False;
      Valid         : Boolean := False;
      Version       : Natural := 0;                      --  1 (AE-1) or 2 (AE-2)
      Strength      : Natural := 0;                      --  1=128 2=192 3=256
      Actual_Method : Interfaces.Unsigned_16 := 0;       --  real compression method
   end record;

   --  Scan an extra-field block (Bytes (Offset .. Offset + Length - 1)) for the
   --  0x9901 AES record. A malformed field yields Present with Valid = False.
   function Parse_Extra
     (Bytes  : Byte_Array;
      Offset : Natural;
      Length : Natural) return AES_Params;

   --  The salt length, in bytes, for a strength of 1/2/3 (8/12/16). Zero for
   --  any other value.
   function Salt_Length (Strength : Natural) return Natural;

   --  Decrypt one WinZip-AES member payload. Wire is the whole encrypted body
   --  as it sits in the archive:
   --
   --     salt (8/12/16) | 2-byte password verifier | ciphertext |
   --     10-byte truncated HMAC-SHA1 authentication code
   --
   --  On success Status is Ok and the result is the plaintext, which is still
   --  compressed under the entry's actual method. Failures are deterministic
   --  and fail closed (empty result):
   --    * Invalid_Header           -- bad strength, or a wire too short to hold
   --                                  even the fixed header and trailer
   --    * Unexpected_End_Of_Input  -- wire shorter than salt + verifier + auth
   --    * Invalid_Password         -- the 2-byte verifier did not match
   --    * Invalid_Checksum         -- the authentication code did not match
   --                                  (corrupt ciphertext, or a verifier
   --                                  collision on the wrong password)
   function Decrypt
     (Wire     : Byte_Array;
      Strength : Natural;
      Password : String;
      Status   : out Status_Code) return Byte_Array;

end Zlib.Zip_AES;
