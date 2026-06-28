with AUnit.Assertions; use AUnit.Assertions;
with Zlib;

package body Zlib_Public_Tests is

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib public API");
   end Name;

   procedure Test_Status_Image (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Zlib.Status_Image (Zlib.Ok) = "ok",
         "Ok image must match release contract");

      Assert
        (Zlib.Status_Image (Zlib.Invalid_Header) = "invalid zlib header",
         "Invalid_Header image must match release contract");

      Assert
        (Zlib.Status_Image (Zlib.Invalid_Checksum) =
           "invalid checksum",
         "Invalid_Checksum image must match release contract");

      Assert
        (Zlib.Status_Image (Zlib.Input_File_Error) =
           "input file error",
         "Input_File_Error image must match release contract");

      Assert
        (Zlib.Status_Image (Zlib.Output_File_Error) =
           "output file error",
         "Output_File_Error image must match release contract");
   end Test_Status_Image;

   procedure Test_Looks_Like_Zlib_Header
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
        (Zlib.Looks_Like_Zlib_Header ([16#78#, 16#01#]),
         "stored zlib header should be recognized");
      Assert
        (Zlib.Looks_Like_Zlib_Header ([16#78#, 16#9C#]),
         "default zlib header should be recognized");
      Assert
        (Zlib.Looks_Like_Zlib_Header ([16#78#, 16#DA#, 16#03#]),
         "zlib header should be recognized with trailing payload bytes");
      Assert
        (not Zlib.Looks_Like_Zlib_Header ([1 .. 0 => 0]),
         "empty input is not a zlib header");
      Assert
        (not Zlib.Looks_Like_Zlib_Header ([16#78#]),
         "single byte input is not a zlib header");
      Assert
        (not Zlib.Looks_Like_Zlib_Header ([16#77#, 16#9C#]),
         "non-Deflate compression method is not a zlib header");
      Assert
        (not Zlib.Looks_Like_Zlib_Header ([16#88#, 16#98#]),
         "invalid CINFO window value is not a zlib header");
      Assert
        (not Zlib.Looks_Like_Zlib_Header ([16#78#, 16#9D#]),
         "bad CMF/FLG check value is not a zlib header");
   end Test_Looks_Like_Zlib_Header;

   procedure Test_Looks_Like_GZip_Header
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
        (Zlib.Looks_Like_GZip_Header
           ([16#1F#, 16#8B#, 16#08#, 16#00#]),
         "minimal gzip header prefix should be recognized");
      Assert
        (Zlib.Looks_Like_GZip_Header
           ([16#1F#, 16#8B#, 16#08#, 16#1F#, 0, 0, 0, 0]),
         "gzip optional flag bits should be accepted");
      Assert
        (not Zlib.Looks_Like_GZip_Header ([1 .. 0 => 0]),
         "empty input is not a gzip header");
      Assert
        (not Zlib.Looks_Like_GZip_Header ([16#1F#, 16#8B#, 16#08#]),
         "three-byte input is not enough for gzip flag validation");
      Assert
        (not Zlib.Looks_Like_GZip_Header
           ([16#00#, 16#8B#, 16#08#, 16#00#]),
         "bad gzip ID1 should be rejected");
      Assert
        (not Zlib.Looks_Like_GZip_Header
           ([16#1F#, 16#00#, 16#08#, 16#00#]),
         "bad gzip ID2 should be rejected");
      Assert
        (not Zlib.Looks_Like_GZip_Header
           ([16#1F#, 16#8B#, 16#00#, 16#00#]),
         "non-Deflate gzip method should be rejected");
      Assert
        (not Zlib.Looks_Like_GZip_Header
           ([16#1F#, 16#8B#, 16#08#, 16#20#]),
         "reserved gzip FLG bit 5 should be rejected");
      Assert
        (not Zlib.Looks_Like_GZip_Header
           ([16#1F#, 16#8B#, 16#08#, 16#E0#]),
         "reserved gzip FLG bits should be rejected");
   end Test_Looks_Like_GZip_Header;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T,
         Test_Status_Image'Access,
         "Status_Image returns release-contract public strings");
      Registration.Register_Routine
        (T,
         Test_Looks_Like_Zlib_Header'Access,
         "Looks_Like_Zlib_Header recognizes only syntactic zlib headers");
      Registration.Register_Routine
        (T,
         Test_Looks_Like_GZip_Header'Access,
         "Looks_Like_GZip_Header recognizes only syntactic gzip header prefixes");
   end Register_Tests;

end Zlib_Public_Tests;
