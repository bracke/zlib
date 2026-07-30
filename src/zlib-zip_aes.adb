with Ada.Streams;
with CryptoLib.Ciphers;
with CryptoLib.Errors;
with CryptoLib.Macs;

package body Zlib.Zip_AES is

   use type Interfaces.Unsigned_16;
   use type Ada.Streams.Stream_Element_Offset;
   use type CryptoLib.Errors.Status;

   --  WinZip-AES fixed lengths: a 10-byte truncated HMAC-SHA1 trailer and a
   --  2-byte password verifier, independent of the strength.
   Authentication_Length : constant := 10;
   Verifier_Length       : constant := 2;

   ---------------------------------------------------------------------------
   --  Little-endian readers over an in-memory window. The root body's
   --  ZIP_U*_At helpers are not visible to a child package.
   ---------------------------------------------------------------------------

   function U16 (Bytes : Byte_Array; Pos : Natural) return Interfaces.Unsigned_16
   is
   begin
      return Interfaces.Unsigned_16 (Bytes (Pos))
        or Interfaces.Shift_Left (Interfaces.Unsigned_16 (Bytes (Pos + 1)), 8);
   end U16;

   ---------------------------------------------------------------------------
   --  Byte_Array <-> Stream_Element_Array bridges for the cryptolib calls.
   ---------------------------------------------------------------------------

   function To_Stream
     (Bytes : Byte_Array) return Ada.Streams.Stream_Element_Array
   is
      Result : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Bytes'Length));
   begin
      for Index in Bytes'Range loop
         Result (Ada.Streams.Stream_Element_Offset (Index - Bytes'First + 1)) :=
           Ada.Streams.Stream_Element (Bytes (Index));
      end loop;
      return Result;
   end To_Stream;

   function To_Bytes
     (Bytes : Ada.Streams.Stream_Element_Array) return Byte_Array
   is
      Result : Byte_Array (1 .. Natural (Bytes'Length));
   begin
      for Index in Result'Range loop
         Result (Index) :=
           Byte
             (Bytes
                (Bytes'First
                 + Ada.Streams.Stream_Element_Offset (Index - Result'First)));
      end loop;
      return Result;
   end To_Bytes;

   function Password_Stream
     (Password : String) return Ada.Streams.Stream_Element_Array
   is
      Result : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Password'Length));
   begin
      for Index in Password'Range loop
         Result
           (Ada.Streams.Stream_Element_Offset (Index - Password'First + 1)) :=
             Ada.Streams.Stream_Element (Character'Pos (Password (Index)));
      end loop;
      return Result;
   end Password_Stream;

   ---------------------------------------------------------------------------
   --  Strength-derived sizes and the cryptolib algorithm name.
   ---------------------------------------------------------------------------

   function Salt_Length (Strength : Natural) return Natural is
   begin
      case Strength is
         when 1 => return 8;
         when 2 => return 12;
         when 3 => return 16;
         when others => return 0;
      end case;
   end Salt_Length;

   function Key_Length (Strength : Natural) return Natural is
   begin
      case Strength is
         when 1 => return 16;
         when 2 => return 24;
         when 3 => return 32;
         when others => return 0;
      end case;
   end Key_Length;

   function Algorithm (Strength : Natural) return String is
   begin
      case Strength is
         when 1 => return "aes128";
         when 2 => return "aes192";
         when 3 => return "aes256";
         when others => return "";
      end case;
   end Algorithm;

   ---------------------------------------------------------------------------
   --  Extra-field parsing.
   ---------------------------------------------------------------------------

   function Parse_Extra
     (Bytes  : Byte_Array;
      Offset : Natural;
      Length : Natural) return AES_Params
   is
      Cursor : Natural := Offset;
      Result : AES_Params;

      function In_Range (Pos : Natural; Count : Natural) return Boolean is
        (Pos >= Bytes'First
         and then Count <= Bytes'Last - Pos + 1);
   begin
      if Length = 0 then
         return Result;
      end if;

      while Cursor < Offset + Length loop
         if not In_Range (Cursor, 4) then
            Result.Valid := False;
            return Result;
         end if;

         declare
            Header_Id : constant Interfaces.Unsigned_16 := U16 (Bytes, Cursor);
            Data_Len  : constant Natural := Natural (U16 (Bytes, Cursor + 2));
            Data_Off  : constant Natural := Cursor + 4;
         begin
            if Data_Off > Offset + Length
              or else Data_Len > Offset + Length - Data_Off
            then
               Result.Valid := False;
               return Result;
            elsif Header_Id = 16#9901# then
               Result.Present := True;
               if Data_Len < 7
                 or else not In_Range (Data_Off, 7)
                 or else Character'Val (Natural (Bytes (Data_Off + 2))) /= 'A'
                 or else Character'Val (Natural (Bytes (Data_Off + 3))) /= 'E'
               then
                  Result.Valid := False;
                  return Result;
               end if;

               Result.Version := Natural (U16 (Bytes, Data_Off));
               Result.Strength := Natural (Bytes (Data_Off + 4));
               Result.Actual_Method := U16 (Bytes, Data_Off + 5);
               Result.Valid :=
                 Result.Version in 1 | 2
                 and then Result.Strength in 1 | 2 | 3;
               return Result;
            end if;
            Cursor := Data_Off + Data_Len;
         end;
      end loop;
      return Result;
   end Parse_Extra;

   ---------------------------------------------------------------------------
   --  Payload decryption.
   ---------------------------------------------------------------------------

   function Decrypt
     (Wire     : Byte_Array;
      Strength : Natural;
      Password : String;
      Status   : out Status_Code) return Byte_Array
   is
      Empty       : constant Byte_Array (1 .. 0) := [others => 0];
      Salt_Len    : constant Natural := Salt_Length (Strength);
      Key_Len     : constant Natural := Key_Length (Strength);
      Header_Len  : constant Natural := Salt_Len + Verifier_Length;
   begin
      Status := Invalid_Header;

      if Salt_Len = 0 or else Key_Len = 0 then
         Status := Invalid_Header;
         return Empty;
      end if;

      if Wire'Length < Header_Len + Authentication_Length then
         Status := Unexpected_End_Of_Input;
         return Empty;
      end if;

      declare
         Cipher_Length : constant Natural :=
           Wire'Length - Header_Len - Authentication_Length;
         Salt : constant Ada.Streams.Stream_Element_Array :=
           To_Stream (Wire (Wire'First .. Wire'First + Salt_Len - 1));
         Ciphertext : constant Ada.Streams.Stream_Element_Array :=
           To_Stream
             (Wire
                (Wire'First + Header_Len
                 .. Wire'First + Header_Len + Cipher_Length - 1));
         Password_Data : constant Ada.Streams.Stream_Element_Array :=
           Password_Stream (Password);
         --  PBKDF2 output packs, in order: the AES key (Key_Len), the HMAC
         --  authentication key (Key_Len), then the 2-byte password verifier.
         Derived : constant Ada.Streams.Stream_Element_Array :=
           CryptoLib.Macs.PBKDF2_HMAC_SHA1
             (Password_Data, Salt, 1_000, Key_Len * 2 + 2);
         Auth : constant CryptoLib.Macs.HMAC_SHA1_Digest :=
           CryptoLib.Macs.HMAC_SHA1
             (Derived
                (Derived'First + Ada.Streams.Stream_Element_Offset (Key_Len)
                 .. Derived'First
                    + Ada.Streams.Stream_Element_Offset (Key_Len * 2 - 1)),
              Ciphertext);
         Plain : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Cipher_Length));
         Crypto_Status : CryptoLib.Errors.Status;
      begin
         --  The 2-byte verifier is a cheap pre-filter on the password. It
         --  cannot by itself confirm the password (1 in 65536 collide), so a
         --  match still goes on to the authentication check below.
         if Byte (Derived (Derived'Last - 1)) /= Wire (Wire'First + Salt_Len)
           or else Byte (Derived (Derived'Last)) /=
             Wire (Wire'First + Salt_Len + 1)
         then
            Status := Invalid_Password;
            return Empty;
         end if;

         --  The truncated HMAC-SHA1 over the ciphertext is authoritative: it
         --  rejects a wrong password that slipped past the verifier and any
         --  corruption of the encrypted bytes.
         for Index in 1 .. Authentication_Length loop
            if Byte (Auth (Index)) /=
              Wire (Wire'First + Header_Len + Cipher_Length + Index - 1)
            then
               Status := Invalid_Checksum;
               return Empty;
            end if;
         end loop;

         Crypto_Status :=
           CryptoLib.Ciphers.Apply_ZIP_AES_CTR
             (Algorithm (Strength),
              Derived
                (Derived'First
                 .. Derived'First
                    + Ada.Streams.Stream_Element_Offset (Key_Len - 1)),
              Ciphertext,
              Plain);
         if Crypto_Status /= CryptoLib.Errors.Ok then
            Status := Invalid_Header;
            return Empty;
         end if;

         Status := Ok;
         return To_Bytes (Plain);
      end;
   exception
      when Storage_Error =>
         Status := Insufficient_Memory;
         return Empty;
      when others =>
         Status := Invalid_Header;
         return Empty;
   end Decrypt;

end Zlib.Zip_AES;
