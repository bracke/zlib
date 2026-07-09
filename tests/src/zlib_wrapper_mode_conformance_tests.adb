with AUnit.Assertions; use AUnit.Assertions;
with Zlib;
with Zlib_Fixture_Data;
with Zlib_Conformance_Test_Support;

package body Zlib_Wrapper_Mode_Conformance_Tests is
   use type Zlib.Status_Code;

   package F renames Zlib_Fixture_Data;
   package S renames Zlib_Conformance_Test_Support;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib wrapper-mode conformance");
   end Name;

   procedure Test_One_Shot_Implicit_Auto_Detection
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array := Zlib.Inflate (F.Zlib_Stored, Status);
   begin
      Assert (Status = Zlib.Ok, "Inflate accepts zlib-wrapped input");
      S.Assert_Bytes_Equal (Output, F.Plain_Stored, "Inflate zlib output");

      declare
         Raw_Output : constant Zlib.Byte_Array := Zlib.Inflate (F.Raw_Stored, Status);
      begin
         Assert (Status = Zlib.Ok, "Inflate auto-detects raw Deflate input");
         S.Assert_Bytes_Equal (Raw_Output, F.Plain_Stored, "Inflate raw output");
      end;

      declare
         GZip_Output : constant Zlib.Byte_Array := Zlib.Inflate (F.GZip_Fixed, Status);
      begin
         Assert (Status = Zlib.Ok, "Inflate auto-detects gzip input");
         S.Assert_Bytes_Equal (GZip_Output, F.Plain_Fixed, "Inflate gzip output");
      end;

      S.Assert_One_Shot_OK
        (F.Zlib_Stored, Zlib.Default, F.Plain_Stored,
         "Default auto-detects zlib");
      S.Assert_One_Shot_OK
        (F.GZip_Fixed, Zlib.Default, F.Plain_Fixed,
         "Default auto-detects gzip");
      S.Assert_One_Shot_OK
        (F.Raw_Stored, Zlib.Default, F.Plain_Stored,
         "Default auto-detects raw");
      S.Assert_One_Shot_OK
        (F.Zlib_Stored, Zlib.Zlib_Header, F.Plain_Stored,
         "Zlib_Header accepts zlib only");
      S.Assert_One_Shot_OK
        (F.GZip_Fixed, Zlib.GZip, F.Plain_Fixed,
         "GZip accepts gzip only");
      S.Assert_One_Shot_OK
        (F.Raw_Stored, Zlib.Raw_Deflate, F.Plain_Stored,
         "Raw_Deflate accepts raw only");

      S.Assert_One_Shot_Fails (F.GZip_Fixed, Zlib.Zlib_Header, "zlib rejects gzip");
      S.Assert_One_Shot_Fails (F.Raw_Stored, Zlib.Zlib_Header, "zlib rejects raw");
      S.Assert_One_Shot_Fails (F.Zlib_Stored, Zlib.GZip, "gzip rejects zlib");
      S.Assert_One_Shot_Fails (F.Raw_Stored, Zlib.GZip, "gzip rejects raw");
      S.Assert_One_Shot_Fails (F.Zlib_Stored, Zlib.Raw_Deflate, "raw rejects zlib");
      S.Assert_One_Shot_Fails (F.GZip_Fixed, Zlib.Raw_Deflate, "raw rejects gzip");
   end Test_One_Shot_Implicit_Auto_Detection;

   procedure Test_Streaming_Strict_Wrappers
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      S.Assert_Streaming_OK
        (F.Zlib_Stored, Zlib.Default, F.Plain_Stored, 1, 1,
         "stream Default auto-detects zlib");
      S.Assert_Streaming_OK
        (F.GZip_Fixed, Zlib.Default, F.Plain_Fixed, 1, 1,
         "stream Default auto-detects gzip");
      S.Assert_Streaming_OK
        (F.Raw_Stored, Zlib.Default, F.Plain_Stored, 1, 1,
         "stream Default auto-detects raw");
      S.Assert_Streaming_OK
        (F.Zlib_Stored, Zlib.Zlib_Header, F.Plain_Stored, 2, 1,
         "stream Zlib_Header accepts zlib only");
      S.Assert_Streaming_OK
        (F.GZip_Fixed, Zlib.GZip, F.Plain_Fixed, 3, 2,
         "stream GZip accepts gzip only");
      S.Assert_Streaming_OK
        (F.Raw_Stored, Zlib.Raw_Deflate, F.Plain_Stored, 1, 1,
         "stream Raw_Deflate accepts raw only");

      S.Expect_Streaming_Zlib_Error (F.GZip_Fixed, Zlib.Zlib_Header, "zlib rejects gzip");
      S.Expect_Streaming_Zlib_Error (F.Raw_Stored, Zlib.Zlib_Header, "zlib rejects raw");
      S.Expect_Streaming_Zlib_Error (F.Zlib_Stored, Zlib.GZip, "gzip rejects zlib");
      S.Expect_Streaming_Zlib_Error (F.Raw_Stored, Zlib.GZip, "gzip rejects raw");
      S.Expect_Streaming_Zlib_Error (F.Zlib_Stored, Zlib.Raw_Deflate, "raw rejects zlib");
      S.Expect_Streaming_Zlib_Error (F.GZip_Fixed, Zlib.Raw_Deflate, "raw rejects gzip");
   end Test_Streaming_Strict_Wrappers;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_One_Shot_Implicit_Auto_Detection'Access,
         "one-shot Default and Inflate auto-detect wrappers");
      Registration.Register_Routine
        (T, Test_Streaming_Strict_Wrappers'Access,
         "streaming Default auto-detects and concrete boundaries stay strict");
   end Register_Tests;
end Zlib_Wrapper_Mode_Conformance_Tests;
