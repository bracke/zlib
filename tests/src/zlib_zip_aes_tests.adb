with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with AUnit.Assertions; use AUnit.Assertions;
with CryptoLib.Ciphers;
with CryptoLib.Checksums;
with CryptoLib.Errors;
with CryptoLib.Macs;
with Interfaces;
with Zlib;

--  Round-trip tests for WinZip-AES ("AE-1") encrypted ZIP reading. The library
--  is read-only for AES, so these tests carry their own small AES *encryptor*
--  -- ported from the archive application's validated fixture builder -- to
--  synthesise a stock-shaped encrypted ZIP entirely in memory, then assert that
--  Zlib.Extract_ZIP_External_Entry recovers the plaintext and fails closed on a
--  wrong password or a mangled payload. Nothing here adds encryption to the
--  library; the encryptor lives only in the test.
package body Zlib_ZIP_AES_Tests is

   use type Ada.Streams.Stream_Element_Offset;
   use type CryptoLib.Errors.Status;
   use type Zlib.Byte_Array;
   use type Zlib.Status_Code;

   Entry_Name : constant String := "large.bin";

   ---------------------------------------------------------------------------
   --  Little-endian writers over a 0-based offset into a Byte_Array.
   ---------------------------------------------------------------------------

   procedure Put16 (Bytes : in out Zlib.Byte_Array; Offset : Natural;
                    Value : Natural) is
   begin
      Bytes (Bytes'First + Offset) := Zlib.Byte (Value mod 256);
      Bytes (Bytes'First + Offset + 1) := Zlib.Byte ((Value / 256) mod 256);
   end Put16;

   procedure Put32 (Bytes : in out Zlib.Byte_Array; Offset : Natural;
                    Value : Interfaces.Unsigned_32) is
      use type Interfaces.Unsigned_32;
   begin
      for I in 0 .. 3 loop
         Bytes (Bytes'First + Offset + I) :=
           Zlib.Byte
             (Interfaces.Shift_Right (Value, 8 * I) and 16#FF#);
      end loop;
   end Put32;

   procedure Put_Text (Bytes : in out Zlib.Byte_Array; Offset : Natural;
                       Text : String) is
   begin
      for I in Text'Range loop
         Bytes (Bytes'First + Offset + (I - Text'First)) :=
           Zlib.Byte (Character'Pos (Text (I)));
      end loop;
   end Put_Text;

   ---------------------------------------------------------------------------
   --  Byte_Array <-> Stream_Element_Array bridges.
   ---------------------------------------------------------------------------

   function To_Stream
     (Bytes : Zlib.Byte_Array) return Ada.Streams.Stream_Element_Array
   is
      Result : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Bytes'Length));
   begin
      for I in Bytes'Range loop
         Result (Ada.Streams.Stream_Element_Offset (I - Bytes'First + 1)) :=
           Ada.Streams.Stream_Element (Bytes (I));
      end loop;
      return Result;
   end To_Stream;

   function To_Bytes
     (Bytes : Ada.Streams.Stream_Element_Array) return Zlib.Byte_Array
   is
      Result : Zlib.Byte_Array (1 .. Natural (Bytes'Length));
   begin
      for I in Result'Range loop
         Result (I) :=
           Zlib.Byte
             (Bytes
                (Bytes'First
                 + Ada.Streams.Stream_Element_Offset (I - Result'First)));
      end loop;
      return Result;
   end To_Bytes;

   function Password_Stream
     (Password : String) return Ada.Streams.Stream_Element_Array
   is
      Result : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Password'Length));
   begin
      for I in Password'Range loop
         Result (Ada.Streams.Stream_Element_Offset (I - Password'First + 1)) :=
           Ada.Streams.Stream_Element (Character'Pos (Password (I)));
      end loop;
      return Result;
   end Password_Stream;

   ---------------------------------------------------------------------------
   --  Strength-derived sizes and cryptolib algorithm name.
   ---------------------------------------------------------------------------

   function Salt_Length (Strength : Natural) return Natural is
     (case Strength is when 1 => 8, when 2 => 12, when others => 16);

   function Key_Length (Strength : Natural) return Natural is
     (case Strength is when 1 => 16, when 2 => 24, when others => 32);

   function Algorithm (Strength : Natural) return String is
     (case Strength is when 1 => "aes128", when 2 => "aes192",
        when others => "aes256");

   function CRC32 (Data : Zlib.Byte_Array) return Interfaces.Unsigned_32 is
      State : CryptoLib.Checksums.CRC32_State;
   begin
      CryptoLib.Checksums.CRC32_Reset (State);
      for B of Data loop
         CryptoLib.Checksums.CRC32_Update
           (State, Ada.Streams.Stream_Element (B));
      end loop;
      return CryptoLib.Checksums.CRC32_Value (State);
   end CRC32;

   ---------------------------------------------------------------------------
   --  Encrypt one compressed payload into a WinZip-AES wire:
   --    salt | 2-byte verifier | ciphertext | 10-byte truncated HMAC-SHA1.
   ---------------------------------------------------------------------------

   function AES_Wire
     (Compressed : Zlib.Byte_Array;
      Strength   : Natural;
      Password   : String) return Zlib.Byte_Array
   is
      Salt_Len : constant Natural := Salt_Length (Strength);
      Key_Len  : constant Natural := Key_Length (Strength);
      Salt : Zlib.Byte_Array (1 .. Salt_Len);
      Password_Data : constant Ada.Streams.Stream_Element_Array :=
        Password_Stream (Password);
   begin
      for I in Salt'Range loop
         Salt (I) := Zlib.Byte ((16#11# * I) mod 256);
      end loop;

      declare
         Derived : constant Ada.Streams.Stream_Element_Array :=
           CryptoLib.Macs.PBKDF2_HMAC_SHA1
             (Password_Data, To_Stream (Salt), 1_000, Key_Len * 2 + 2);
         Ciphertext : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Compressed'Length));
         Cipher_Status : CryptoLib.Errors.Status;
      begin
         Cipher_Status :=
           CryptoLib.Ciphers.Apply_ZIP_AES_CTR
             (Algorithm (Strength),
              Derived
                (Derived'First
                 .. Derived'First
                    + Ada.Streams.Stream_Element_Offset (Key_Len - 1)),
              To_Stream (Compressed),
              Ciphertext);
         Assert (Cipher_Status = CryptoLib.Errors.Ok,
                 "zip aes fixture encryption succeeds");

         declare
            Auth : constant CryptoLib.Macs.HMAC_SHA1_Digest :=
              CryptoLib.Macs.HMAC_SHA1
                (Derived
                   (Derived'First
                    + Ada.Streams.Stream_Element_Offset (Key_Len)
                    .. Derived'First
                       + Ada.Streams.Stream_Element_Offset (Key_Len * 2 - 1)),
                 Ciphertext);
            Cipher_Bytes : constant Zlib.Byte_Array := To_Bytes (Ciphertext);
            Result : Zlib.Byte_Array
              (1 .. Salt_Len + 2 + Cipher_Bytes'Length + 10);
            Cursor : Natural := Result'First;
         begin
            for I in Salt'Range loop
               Result (Cursor) := Salt (I);
               Cursor := Cursor + 1;
            end loop;
            Result (Cursor) := Zlib.Byte (Derived (Derived'Last - 1));
            Result (Cursor + 1) := Zlib.Byte (Derived (Derived'Last));
            Cursor := Cursor + 2;
            for I in Cipher_Bytes'Range loop
               Result (Cursor) := Cipher_Bytes (I);
               Cursor := Cursor + 1;
            end loop;
            for I in 1 .. 10 loop
               Result (Cursor) := Zlib.Byte (Auth (I));
               Cursor := Cursor + 1;
            end loop;
            return Result;
         end;
      end;
   end AES_Wire;

   ---------------------------------------------------------------------------
   --  Assemble a single-entry WinZip-AES ZIP around a payload, encrypting it
   --  under the given strength and (real) compression method (0 or 8).
   ---------------------------------------------------------------------------

   function AES_Zip
     (Payload  : Zlib.Byte_Array;
      Method   : Natural;
      Strength : Natural;
      Password : String) return Zlib.Byte_Array
   is
      CRC : constant Interfaces.Unsigned_32 := CRC32 (Payload);

      function Compressed return Zlib.Byte_Array is
         Status : Zlib.Status_Code;
      begin
         if Method = 0 then
            return Payload;
         end if;
         declare
            Deflated : constant Zlib.Byte_Array :=
              Zlib.Deflate_Raw (Payload, Zlib.Fixed, Status);
         begin
            Assert (Status = Zlib.Ok, "zip aes fixture deflate succeeds");
            return Deflated;
         end;
      end Compressed;

      Wire : constant Zlib.Byte_Array :=
        AES_Wire (Compressed, Strength, Password);

      Extra_Len      : constant Natural := 11;
      Central_Offset : constant Natural :=
        30 + Entry_Name'Length + Extra_Len + Wire'Length;
      Central_Size   : constant Natural := 46 + Entry_Name'Length + Extra_Len;
      EOCD_Offset    : constant Natural := Central_Offset + Central_Size;
      Bytes          : Zlib.Byte_Array (1 .. EOCD_Offset + 22) :=
        [others => 0];

      procedure Put_AES_Extra (Offset : Natural) is
      begin
         Put16 (Bytes, Offset, 16#9901#);
         Put16 (Bytes, Offset + 2, 7);
         Put16 (Bytes, Offset + 4, 1);                --  AE-1
         Put_Text (Bytes, Offset + 6, "AE");
         Bytes (Bytes'First + Offset + 8) := Zlib.Byte (Strength);
         Put16 (Bytes, Offset + 9, Method);           --  real method
      end Put_AES_Extra;
   begin
      --  Local header (method 99, encryption flag set, 0x9901 extra).
      Put32 (Bytes, 0, 16#0403_4B50#);
      Put16 (Bytes, 6, 1);
      Put16 (Bytes, 8, 99);
      Put32 (Bytes, 14, CRC);
      Put32 (Bytes, 18, Interfaces.Unsigned_32 (Wire'Length));
      Put32 (Bytes, 22, Interfaces.Unsigned_32 (Payload'Length));
      Put16 (Bytes, 26, Entry_Name'Length);
      Put16 (Bytes, 28, Extra_Len);
      Put_Text (Bytes, 30, Entry_Name);
      Put_AES_Extra (30 + Entry_Name'Length);
      for I in Wire'Range loop
         Bytes
           (Bytes'First + 30 + Entry_Name'Length + Extra_Len
            + (I - Wire'First)) := Wire (I);
      end loop;

      --  Central directory record (mirrors the local header).
      Put32 (Bytes, Central_Offset, 16#0201_4B50#);
      Put16 (Bytes, Central_Offset + 8, 1);
      Put16 (Bytes, Central_Offset + 10, 99);
      Put32 (Bytes, Central_Offset + 16, CRC);
      Put32 (Bytes, Central_Offset + 20, Interfaces.Unsigned_32 (Wire'Length));
      Put32 (Bytes, Central_Offset + 24,
             Interfaces.Unsigned_32 (Payload'Length));
      Put16 (Bytes, Central_Offset + 28, Entry_Name'Length);
      Put16 (Bytes, Central_Offset + 30, Extra_Len);
      Put32 (Bytes, Central_Offset + 42, 0);
      Put_Text (Bytes, Central_Offset + 46, Entry_Name);
      Put_AES_Extra (Central_Offset + 46 + Entry_Name'Length);

      --  End of central directory.
      Put32 (Bytes, EOCD_Offset, 16#0605_4B50#);
      Put16 (Bytes, EOCD_Offset + 8, 1);
      Put16 (Bytes, EOCD_Offset + 10, 1);
      Put32 (Bytes, EOCD_Offset + 12, Interfaces.Unsigned_32 (Central_Size));
      Put32 (Bytes, EOCD_Offset + 16, Interfaces.Unsigned_32 (Central_Offset));
      return Bytes;
   end AES_Zip;

   ---------------------------------------------------------------------------
   --  A payload big enough to exercise a multi-block AES-CTR keystream and a
   --  non-trivial Deflate stream.
   ---------------------------------------------------------------------------

   function Sample_Payload return Zlib.Byte_Array is
      Result : Zlib.Byte_Array (1 .. 5_000);
   begin
      for I in Result'Range loop
         Result (I) := Zlib.Byte ((I * 37 + I / 3) mod 256);
      end loop;
      return Result;
   end Sample_Payload;

   Password : constant String := "correct horse battery staple";

   ---------------------------------------------------------------------------
   --  Tests.
   ---------------------------------------------------------------------------

   Methods : constant array (1 .. 2) of Natural := [0, 8];

   procedure Test_Round_Trip (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Payload : constant Zlib.Byte_Array := Sample_Payload;
   begin
      for Strength in 1 .. 3 loop
         for M in Methods'Range loop
            declare
               Method : constant Natural := Methods (M);
               Image : constant Zlib.Byte_Array :=
                 AES_Zip (Payload, Method, Strength, Password);
               Status : Zlib.Status_Code := Zlib.Ok;
               Decoded : constant Zlib.Byte_Array :=
                 Zlib.Extract_ZIP_External_Entry
                   (Image, Entry_Name, Password, Status);
               Label : constant String :=
                 "strength" & Strength'Image & " method" & Method'Image;
            begin
               Assert (Status = Zlib.Ok,
                       "aes decrypt Ok for " & Label);
               Assert (Decoded = Payload,
                       "aes plaintext byte-exact for " & Label);
            end;
         end loop;
      end loop;
   end Test_Round_Trip;

   procedure Test_Wrong_Password
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Payload : constant Zlib.Byte_Array := Sample_Payload;
      Image : constant Zlib.Byte_Array :=
        AES_Zip (Payload, 8, 3, Password);
      Status : Zlib.Status_Code := Zlib.Ok;
      Decoded : constant Zlib.Byte_Array :=
        Zlib.Extract_ZIP_External_Entry
          (Image, Entry_Name, "wrong password", Status);
   begin
      Assert (Status /= Zlib.Ok,
              "a wrong password must not report Ok");
      Assert (Status = Zlib.Invalid_Password
                or else Status = Zlib.Invalid_Checksum,
              "a wrong password is Invalid_Password or Invalid_Checksum");
      Assert (Decoded'Length = 0, "a wrong password yields no bytes");
   end Test_Wrong_Password;

   procedure Test_No_Password_Needs_One
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Payload : constant Zlib.Byte_Array := Sample_Payload;
      Image : constant Zlib.Byte_Array :=
        AES_Zip (Payload, 0, 3, Password);
      Status : Zlib.Status_Code := Zlib.Ok;
      Decoded : constant Zlib.Byte_Array :=
        Zlib.Extract_ZIP_External_Entry (Image, Entry_Name, "", Status);
   begin
      Assert (Status = Zlib.Password_Required,
              "an AES entry with no password reports Password_Required");
      Assert (Decoded'Length = 0, "no password yields no bytes");
   end Test_No_Password_Needs_One;

   procedure Test_Truncated_Fails_Closed
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Payload : constant Zlib.Byte_Array := Sample_Payload;
      Full  : constant Zlib.Byte_Array := AES_Zip (Payload, 8, 3, Password);
      --  Chop bytes out of the middle of the encrypted body so the central
      --  directory still parses but the authentication code cannot match.
      Cut   : constant Zlib.Byte_Array :=
        Full (Full'First .. Full'First + 60)
        & Full (Full'First + 90 .. Full'Last);
      Status : Zlib.Status_Code := Zlib.Ok;
      Decoded : constant Zlib.Byte_Array :=
        Zlib.Extract_ZIP_External_Entry (Cut, Entry_Name, Password, Status);
   begin
      Assert (Status /= Zlib.Ok, "a mangled AES body must not report Ok");
      Assert (Decoded'Length = 0, "a mangled AES body yields no bytes");
   end Test_Truncated_Fails_Closed;

   procedure Test_Missing_Entry
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Payload : constant Zlib.Byte_Array := Sample_Payload;
      Image : constant Zlib.Byte_Array :=
        AES_Zip (Payload, 0, 3, Password);
      Status : Zlib.Status_Code := Zlib.Ok;
      Decoded : constant Zlib.Byte_Array :=
        Zlib.Extract_ZIP_External_Entry
          (Image, "absent.bin", Password, Status);
   begin
      Assert (Status /= Zlib.Ok, "an absent entry must not report Ok");
      Assert (Decoded'Length = 0, "an absent entry yields no bytes");
   end Test_Missing_Entry;

   procedure Write_File (Path : String; Data : Zlib.Byte_Array) is
      File : Ada.Streams.Stream_IO.File_Type;
      Raw  : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Data'Length));
   begin
      for I in Data'Range loop
         Raw (Ada.Streams.Stream_Element_Offset (I - Data'First + 1)) :=
           Ada.Streams.Stream_Element (Data (I));
      end loop;
      Ada.Streams.Stream_IO.Create
        (File, Ada.Streams.Stream_IO.Out_File, Path);
      Ada.Streams.Stream_IO.Write (File, Raw);
      Ada.Streams.Stream_IO.Close (File);
   end Write_File;

   function Read_File (Path : String) return Zlib.Byte_Array is
      File : Ada.Streams.Stream_IO.File_Type;
      Size : constant Natural := Natural (Ada.Directories.Size (Path));
      Raw  : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Size));
      Last : Ada.Streams.Stream_Element_Offset := 0;
   begin
      Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Path);
      Ada.Streams.Stream_IO.Read (File, Raw, Last);
      Ada.Streams.Stream_IO.Close (File);
      return Result : Zlib.Byte_Array (1 .. Natural (Last)) do
         for I in Result'Range loop
            Result (I) :=
              Zlib.Byte (Raw (Ada.Streams.Stream_Element_Offset (I)));
         end loop;
      end return;
   end Read_File;

   --  Exercise the streaming *file* API, which rebuilds a foreign member as a
   --  single-entry image: this proves the 0x9901 extra field survives that
   --  rebuild so the codec bridge can decrypt an AES member read from a file.
   procedure Test_File_API_Streaming
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Payload   : constant Zlib.Byte_Array := Sample_Payload;
      Zip_Path  : constant String := "obj/zlib-aes-stream.zip";
      Out_Path  : constant String := "obj/zlib-aes-stream.out";
   begin
      Ada.Directories.Create_Path ("obj");
      for Strength in 1 .. 3 loop
         for M in Methods'Range loop
            declare
               Method : constant Natural := Methods (M);
               Status : Zlib.Status_Code := Zlib.Ok;
               Label  : constant String :=
                 "strength" & Strength'Image & " method" & Method'Image;
            begin
               Write_File
                 (Zip_Path, AES_Zip (Payload, Method, Strength, Password));
               Zlib.Extract_Archive_File_Entry_To_File
                 (Zip_Path, Entry_Name, Out_Path, Password, Status);
               Assert (Status = Zlib.Ok,
                       "file-API aes decrypt Ok for " & Label);
               Assert (Read_File (Out_Path) = Payload,
                       "file-API aes plaintext byte-exact for " & Label);
            end;
         end loop;
      end loop;
   end Test_File_API_Streaming;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib WinZip-AES ZIP reader");
   end Name;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Round_Trip'Access,
         "AES-128/192/256 over Stored and Deflate round-trips byte-exact");
      Register_Routine
        (T, Test_Wrong_Password'Access,
         "a wrong password fails closed deterministically");
      Register_Routine
        (T, Test_No_Password_Needs_One'Access,
         "an AES entry with no password reports Password_Required");
      Register_Routine
        (T, Test_Truncated_Fails_Closed'Access,
         "a mangled AES body fails the authentication check");
      Register_Routine
        (T, Test_Missing_Entry'Access,
         "extracting an absent member fails closed");
      Register_Routine
        (T, Test_File_API_Streaming'Access,
         "AES members decrypt through the streaming file API");
   end Register_Tests;

end Zlib_ZIP_AES_Tests;
