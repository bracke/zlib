with Ada.Streams; use Ada.Streams;
with CryptoLib.Hashes;
with CryptoLib.Ciphers;
with CryptoLib.Random;
with CryptoLib.Errors;

package body Zlib.Seven_Zip_AES is

   use type CryptoLib.Errors.Status;
   use type Interfaces.Unsigned_64;

   function To_SEA (B : Byte_Array) return Stream_Element_Array is
      R : Stream_Element_Array (1 .. Stream_Element_Offset (B'Length));
   begin
      for I in 0 .. B'Length - 1 loop
         R (Stream_Element_Offset (I + 1)) := Stream_Element (B (B'First + I));
      end loop;
      return R;
   end To_SEA;

   function To_BA (S : Stream_Element_Array) return Byte_Array is
      R : Byte_Array (0 .. Natural (S'Length) - 1);
   begin
      for I in 0 .. Natural (S'Length) - 1 loop
         R (I) := Byte (S (S'First + Stream_Element_Offset (I)));
      end loop;
      return R;
   end To_BA;

   function Derive_Key
     (Password         : String;
      Salt             : Byte_Array;
      Num_Cycles_Power : Natural) return Byte_Array
   is
      use CryptoLib.Hashes;
      Ctx    : SHA256_Context;
      Salt_S : constant Stream_Element_Array := To_SEA (Salt);
      Pw     : Stream_Element_Array
        (1 .. Stream_Element_Offset (Password'Length) * 2) := [others => 0];
      Ctr    : Stream_Element_Array (1 .. 8) := [others => 0];
      Rounds : Interfaces.Unsigned_64 :=
        Interfaces.Unsigned_64 (2) ** Num_Cycles_Power;
   begin
      --  UTF-16LE encode the password (Latin-1 code points).
      for I in Password'Range loop
         Pw (Stream_Element_Offset (I - Password'First) * 2 + 1) :=
           Stream_Element (Character'Pos (Password (I)));
      end loop;

      Initialize_SHA256 (Ctx);
      loop
         if Salt_S'Length > 0 then
            Update (Ctx, Salt_S);
         end if;
         Update (Ctx, Pw);
         Update (Ctx, Ctr);
         for I in Ctr'Range loop
            Ctr (I) := Ctr (I) + 1;
            exit when Ctr (I) /= 0;
         end loop;
         Rounds := Rounds - 1;
         exit when Rounds = 0;
      end loop;

      declare
         D : constant SHA256_Digest := Finalize (Ctx);
         R : Byte_Array (0 .. 31);
      begin
         for I in 1 .. 32 loop
            R (I - 1) := Byte (D (I));
         end loop;
         return R;
      end;
   end Derive_Key;

   function Decrypt_CBC (Key, IV, Ciphertext : Byte_Array) return Byte_Array is
      PT : Stream_Element_Array (1 .. Stream_Element_Offset (Ciphertext'Length));
      St : CryptoLib.Errors.Status;
   begin
      if Ciphertext'Length = 0 then
         return [1 .. 0 => 0];
      end if;
      St := CryptoLib.Ciphers.Decrypt_CBC_Raw
        ("aes256-cbc", To_SEA (Key), To_SEA (IV), To_SEA (Ciphertext), PT);
      if St /= CryptoLib.Errors.Ok then
         return [1 .. 0 => 0];
      end if;
      return To_BA (PT);
   end Decrypt_CBC;

   function Encrypt_CBC (Key, IV, Plaintext : Byte_Array) return Byte_Array is
      use CryptoLib.Ciphers;
      Item : Cipher_State;
      St   : CryptoLib.Errors.Status;
      CT   : Stream_Element_Array (1 .. Stream_Element_Offset (Plaintext'Length));
   begin
      if Plaintext'Length = 0 then
         return [1 .. 0 => 0];
      end if;
      St := Initialize
        (Item, "aes256-cbc", Client_To_Server, To_SEA (Key), To_SEA (IV));
      if St /= CryptoLib.Errors.Ok then
         return [1 .. 0 => 0];
      end if;
      St := Encrypt (Item, To_SEA (Plaintext), CT);
      if St /= CryptoLib.Errors.Ok then
         return [1 .. 0 => 0];
      end if;
      return To_BA (CT);
   end Encrypt_CBC;

   function Pad_To_Block (Data : Byte_Array) return Byte_Array is
      Rem_Bytes : constant Natural := Data'Length mod 16;
      Pad_Len   : constant Natural :=
        (if Rem_Bytes = 0 then 0 else 16 - Rem_Bytes);
      R         : Byte_Array (0 .. Data'Length + Pad_Len - 1) := [others => 0];
   begin
      if Data'Length > 0 then
         R (0 .. Data'Length - 1) := Data;
      end if;
      return R;
   end Pad_To_Block;

   function Random_IV return Byte_Array is
      Src : CryptoLib.Random.Random_Source;
      Buf : Stream_Element_Array (1 .. 16);
      St  : CryptoLib.Errors.Status;
   begin
      CryptoLib.Random.Initialize_Production (Src);
      St := CryptoLib.Random.Fill (Src, Buf);
      if St /= CryptoLib.Errors.Ok then
         return [1 .. 16 => 0];
      end if;
      return To_BA (Buf);
   end Random_IV;

end Zlib.Seven_Zip_AES;
