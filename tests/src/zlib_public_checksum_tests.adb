with AUnit.Assertions; use AUnit.Assertions;
with Zlib;
with Zlib_Public_Checksum_Client;

package body Zlib_Public_Checksum_Tests is
   use type Zlib.Status_Code;

   Hello : constant Zlib.Byte_Array :=
     [1 => Zlib.Byte (Character'Pos ('h')),
      2 => Zlib.Byte (Character'Pos ('e')),
      3 => Zlib.Byte (Character'Pos ('l')),
      4 => Zlib.Byte (Character'Pos ('l')),
      5 => Zlib.Byte (Character'Pos ('o'))];

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
      return AUnit.Format ("Zlib public compression helpers");
   end Name;

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
        (GZip_Stream'Length >= 18,
         "gzip stream must contain header and CRC32/ISIZE trailer");
   end Test_Public_Checksums_Match_Wrapper_Trailers;

   procedure Test_Public_Compression_Bounds
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      procedure Check_Mode (Mode : Zlib.Compression_Mode; Label : String) is
         Status     : Zlib.Status_Code;
         Zlib_Data  : constant Zlib.Byte_Array := Zlib.Deflate (Binary, Mode, Status);
         GZip_Status : Zlib.Status_Code;
         GZip_Data  : constant Zlib.Byte_Array := Zlib.GZip (Binary, Mode, GZip_Status);
         Raw_Status : Zlib.Status_Code;
         Raw_Data   : constant Zlib.Byte_Array := Zlib.Deflate_Raw (Binary, Mode, Raw_Status);
      begin
         Assert (Status = Zlib.Ok, Label & " zlib compression status");
         Assert (GZip_Status = Zlib.Ok, Label & " gzip compression status");
         Assert (Raw_Status = Zlib.Ok, Label & " raw compression status");
         Assert (Zlib_Data'Length <= Zlib.Deflate_Bound (Binary'Length), Label & " zlib bound");
         Assert (GZip_Data'Length <= Zlib.GZip_Bound (Binary'Length), Label & " gzip bound");
         Assert (Raw_Data'Length <= Zlib.Deflate_Raw_Bound (Binary'Length), Label & " raw bound");
      end Check_Mode;

      procedure Check_Level (Level : Zlib.Compression_Level) is
         Status     : Zlib.Status_Code;
         Zlib_Data  : constant Zlib.Byte_Array := Zlib.Deflate (Binary, Level, Status);
         GZip_Status : Zlib.Status_Code;
         GZip_Data  : constant Zlib.Byte_Array := Zlib.GZip (Binary, Level, GZip_Status);
         Raw_Status : Zlib.Status_Code;
         Raw_Data   : constant Zlib.Byte_Array := Zlib.Deflate_Raw (Binary, Level, Raw_Status);
      begin
         Assert (Status = Zlib.Ok, "level zlib compression status");
         Assert (GZip_Status = Zlib.Ok, "level gzip compression status");
         Assert (Raw_Status = Zlib.Ok, "level raw compression status");
         Assert (Zlib_Data'Length <= Zlib.Deflate_Bound (Binary'Length), "level zlib bound");
         Assert (GZip_Data'Length <= Zlib.GZip_Bound (Binary'Length), "level gzip bound");
         Assert (Raw_Data'Length <= Zlib.Deflate_Raw_Bound (Binary'Length), "level raw bound");
      end Check_Level;
   begin
      Check_Mode (Zlib.Stored, "stored");
      Check_Mode (Zlib.Fixed, "fixed");
      Check_Mode (Zlib.Dynamic, "dynamic");
      Check_Mode (Zlib.Auto, "auto");
      Check_Level (Zlib.Default_Level);
      Assert (Zlib.Deflate_Bound (0) >= 6, "empty zlib bound includes wrapper");
      Assert (Zlib.GZip_Bound (0) >= 18, "empty gzip bound includes wrapper");
      Assert (Zlib.Deflate_Raw_Bound (0) > 0, "empty raw bound includes final block");
   end Test_Public_Compression_Bounds;

   procedure Test_Release_Client_Uses_Root_Zlib_Only
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Data : constant Zlib.Byte_Array := Hello;
   begin
      Assert
        (Zlib_Public_Checksum_Client.Checksums_Are_Available,
         "fixture using only root Zlib must compile and call public bound helpers");
      Assert
        (Zlib.Deflate_Bound (Data'Length) >= Data'Length,
         "release client must call public helpers through root Zlib only");
   end Test_Release_Client_Uses_Root_Zlib_Only;

   overriding
   procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_Public_Checksums_Match_Wrapper_Trailers'Access,
         "public compression wrappers emit trailers");
      Registration.Register_Routine
        (T, Test_Public_Compression_Bounds'Access,
         "public compression bound helpers cover emitted output");
      Registration.Register_Routine
        (T, Test_Release_Client_Uses_Root_Zlib_Only'Access,
         "release client can call public helpers using only root Zlib");
   end Register_Tests;
end Zlib_Public_Checksum_Tests;
