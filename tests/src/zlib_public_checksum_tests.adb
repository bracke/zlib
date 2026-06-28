with Ada.Streams;
with AUnit.Assertions; use AUnit.Assertions;
with Interfaces;
with Zlib;
with Zlib_Public_Checksum_Client;

package body Zlib_Public_Checksum_Tests is
   use type Interfaces.Unsigned_32;
   use type Zlib.Status_Code;

   Empty : constant Zlib.Byte_Array (1 .. 0) := [others => 0];

   Hello : constant Zlib.Byte_Array :=
     [1 => Zlib.Byte (Character'Pos ('h')),
      2 => Zlib.Byte (Character'Pos ('e')),
      3 => Zlib.Byte (Character'Pos ('l')),
      4 => Zlib.Byte (Character'Pos ('l')),
      5 => Zlib.Byte (Character'Pos ('o'))];

   Decimal_Digits : constant Zlib.Byte_Array :=
     [1 => Zlib.Byte (Character'Pos ('1')),
      2 => Zlib.Byte (Character'Pos ('2')),
      3 => Zlib.Byte (Character'Pos ('3')),
      4 => Zlib.Byte (Character'Pos ('4')),
      5 => Zlib.Byte (Character'Pos ('5')),
      6 => Zlib.Byte (Character'Pos ('6')),
      7 => Zlib.Byte (Character'Pos ('7')),
      8 => Zlib.Byte (Character'Pos ('8')),
      9 => Zlib.Byte (Character'Pos ('9'))];

   Binary : constant Zlib.Byte_Array :=
     [1 => 16#00#,
      2 => 16#FF#,
      3 => 16#80#,
      4 => 16#0D#,
      5 => 16#0A#,
      6 => 16#41#,
      7 => 16#00#,
      8 => 16#7F#];

   overriding
   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib public checksum API");
   end Name;

   function Big_Endian_U32
     (Data  : Zlib.Byte_Array;
      First : Natural)
      return Interfaces.Unsigned_32
   is
   begin
      return Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (First)), 24)
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (First + 1)), 16)
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (First + 2)), 8)
        or Interfaces.Unsigned_32 (Data (First + 3));
   end Big_Endian_U32;

   function Little_Endian_U32
     (Data  : Zlib.Byte_Array;
      First : Natural)
      return Interfaces.Unsigned_32
   is
   begin
      return Interfaces.Unsigned_32 (Data (First))
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (First + 1)), 8)
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (First + 2)), 16)
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (First + 3)), 24);
   end Little_Endian_U32;

   procedure Test_Public_Adler32_Empty
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
        (Zlib.Adler32 (Empty) = 16#0000_0001#,
         "public Adler32(empty) must be 0x00000001");
   end Test_Public_Adler32_Empty;

   procedure Test_Public_Adler32_Hello
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
        (Zlib.Adler32 (Hello) = 16#062C_0215#,
         "public Adler32(hello) must be 0x062C0215");
   end Test_Public_Adler32_Hello;

   procedure Test_Public_Adler32_Digits
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
        (Zlib.Adler32 (Decimal_Digits) = 16#091E_01DE#,
         "public Adler32(123456789) must be 0x091E01DE");
   end Test_Public_Adler32_Digits;

   procedure Test_Public_Adler32_Binary
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
        (Zlib.Adler32 (Binary) = 16#0BAC_0257#,
         "public Adler32 must include NUL, high bytes, and CR/LF exactly");
   end Test_Public_Adler32_Binary;

   procedure Test_Public_CRC32_Empty
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
        (Zlib.CRC32 (Empty) = 16#0000_0000#,
         "public CRC32(empty) must be 0x00000000");
   end Test_Public_CRC32_Empty;

   procedure Test_Public_CRC32_Hello
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
        (Zlib.CRC32 (Hello) = 16#3610_A686#,
         "public CRC32(hello) must be 0x3610A686");
   end Test_Public_CRC32_Hello;

   procedure Test_Public_CRC32_Digits
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
        (Zlib.CRC32 (Decimal_Digits) = 16#CBF4_3926#,
         "public CRC32(123456789) must be 0xCBF43926");
   end Test_Public_CRC32_Digits;

   procedure Test_Public_CRC32_Binary
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
        (Zlib.CRC32 (Binary) = 16#CF6B_2E0E#,
         "public CRC32 must include NUL, high bytes, and CR/LF exactly");
   end Test_Public_CRC32_Binary;

   procedure Test_Public_CRC32_Streaming
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      State : Zlib.CRC32_State;
      Data  : Ada.Streams.Stream_Element_Array (1 .. 8);
   begin
      for I in Binary'Range loop
         Data (Ada.Streams.Stream_Element_Offset (I)) :=
           Ada.Streams.Stream_Element (Binary (I));
      end loop;

      Zlib.CRC32_Reset (State);
      Zlib.CRC32_Update (State, Data (1 .. 2));
      Zlib.CRC32_Update (State, Data (3));
      Zlib.CRC32_Update (State, Data (4 .. 8));
      Assert
        (Zlib.CRC32_Value (State) = Zlib.CRC32 (Binary),
         "streaming CRC32 must match one-shot CRC32");
   end Test_Public_CRC32_Streaming;

   procedure Test_Public_Checksums_Match_Wrapper_Trailers
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status      : Zlib.Status_Code;
      Zlib_Stream : constant Zlib.Byte_Array :=
        Zlib.Deflate (Binary, Zlib.Stored, Status);
      GZip_Status : Zlib.Status_Code;
      GZip_Stream : constant Zlib.Byte_Array :=
        Zlib.GZip (Binary, Zlib.Stored, GZip_Status);
   begin
      Assert (Status = Zlib.Ok, "zlib compression for checksum trailer test must succeed");
      Assert (GZip_Status = Zlib.Ok, "gzip compression for checksum trailer test must succeed");

      Assert
        (Zlib_Stream'Length >= 6,
         "zlib stream must contain header and Adler-32 trailer");
      Assert
        (Big_Endian_U32 (Zlib_Stream, Zlib_Stream'Last - 3) = Zlib.Adler32 (Binary),
         "public Adler32 must match zlib stream trailer");

      Assert
        (GZip_Stream'Length >= 18,
         "gzip stream must contain header and CRC32/ISIZE trailer");
      Assert
        (Little_Endian_U32 (GZip_Stream, GZip_Stream'Last - 7) = Zlib.CRC32 (Binary),
         "public CRC32 must match gzip trailer CRC32");
   end Test_Public_Checksums_Match_Wrapper_Trailers;

   procedure Test_Release_Client_Uses_Root_Zlib_Only
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Data : constant Zlib.Byte_Array := Hello;
      A    : constant Interfaces.Unsigned_32 := Zlib.Adler32 (Data);
      C    : constant Interfaces.Unsigned_32 := Zlib.CRC32 (Data);
   begin
      Assert
        (Zlib_Public_Checksum_Client.Checksums_Are_Available,
         "fixture using only root Zlib must compile and call checksum helpers");
      Assert
        (A = 16#062C_0215# and then C = 16#3610_A686#,
         "release client must call public checksums through root Zlib only");
   end Test_Release_Client_Uses_Root_Zlib_Only;

   overriding
   procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_Public_Adler32_Empty'Access, "public Adler32 empty");
      Registration.Register_Routine
        (T, Test_Public_Adler32_Hello'Access, "public Adler32 hello");
      Registration.Register_Routine
        (T, Test_Public_Adler32_Digits'Access, "public Adler32 123456789");
      Registration.Register_Routine
        (T, Test_Public_Adler32_Binary'Access, "public Adler32 binary payload");
      Registration.Register_Routine
        (T, Test_Public_CRC32_Empty'Access, "public CRC32 empty");
      Registration.Register_Routine
        (T, Test_Public_CRC32_Hello'Access, "public CRC32 hello");
      Registration.Register_Routine
        (T, Test_Public_CRC32_Digits'Access, "public CRC32 123456789");
      Registration.Register_Routine
        (T, Test_Public_CRC32_Binary'Access, "public CRC32 binary payload");
      Registration.Register_Routine
        (T, Test_Public_CRC32_Streaming'Access, "public CRC32 streaming chunks");
      Registration.Register_Routine
        (T, Test_Public_Checksums_Match_Wrapper_Trailers'Access,
         "public checksum functions match wrapper trailers");
      Registration.Register_Routine
        (T, Test_Release_Client_Uses_Root_Zlib_Only'Access,
         "release client can call checksums using only root Zlib");
   end Register_Tests;
end Zlib_Public_Checksum_Tests;
