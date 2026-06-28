with AUnit.Assertions; use AUnit.Assertions;
with Zlib;
with Zlib_Fixture_Data;
with Zlib_Conformance_Test_Support;

package body Zlib_Consumer_Fixture_Tests is
   use type Zlib.Byte;
   use type Zlib.Status_Code;

   package F renames Zlib_Fixture_Data;
   package S renames Zlib_Conformance_Test_Support;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib consumer fixtures");
   end Name;

   procedure Assert_Roundtrip_All_Modes
     (Plain   : Zlib.Byte_Array;
      Message : String)
   is
      Status : Zlib.Status_Code;
   begin
      for Mode in Zlib.Compression_Mode loop
         declare
            Encoded : constant Zlib.Byte_Array := Zlib.Deflate (Plain, Mode, Status);
         begin
            Assert (Status = Zlib.Ok, Message & ": Deflate status");
            S.Assert_One_Shot_OK
              (Encoded, Zlib.Zlib_Header, Plain, Message & ": one-shot roundtrip");
            S.Assert_Streaming_OK
              (Encoded, Zlib.Zlib_Header, Plain, 2, 1,
               Message & ": streaming roundtrip");
         end;
      end loop;
   end Assert_Roundtrip_All_Modes;

   procedure Test_Version_Git_Shaped_Payloads
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_Roundtrip_All_Modes (F.Plain_Git_Empty_Blob, "Git empty blob");
      Assert_Roundtrip_All_Modes (F.Plain_Git_Blob, "Git blob with NUL separator");
      Assert_Roundtrip_All_Modes (F.Plain_Git_Tree_Like, "Git tree-like binary data");
      Assert_Roundtrip_All_Modes (F.Plain_Git_Commit_Like, "Git commit-like text");

      declare
         Status : Zlib.Status_Code;
         Encoded : constant Zlib.Byte_Array :=
           Zlib.Deflate_Dynamic (F.Plain_Git_Blob, Status);
         Decoded : Zlib.Byte_Array (1 .. F.Plain_Git_Blob'Length);
         Decoded_Status : Zlib.Status_Code;
      begin
         Assert (Status = Zlib.Ok, "Git fixture dynamic compression status");
         Decoded := Zlib.Inflate (Encoded, Decoded_Status);
         Assert (Decoded_Status = Zlib.Ok, "Git fixture inflate status");
         Assert (Decoded (8) = 16#00#, "Git fixture preserves NUL separator");
         S.Assert_Bytes_Equal
           (Decoded, F.Plain_Git_Blob, "Zlib does not parse Git headers");
      end;
   end Test_Version_Git_Shaped_Payloads;

   procedure Test_Httpclient_Body_Fixtures
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      S.Assert_Streaming_OK
        (F.GZip_Binary, Zlib.GZip, F.Plain_Http_Binary, 1, 1,
         "HttpClient gzip binary body");
      S.Assert_Streaming_OK
        (F.Zlib_Binary, Zlib.Zlib_Header, F.Plain_Binary, 1, 1,
         "HttpClient deflate/zlib binary body");
      S.Assert_Streaming_OK
        (F.GZip_Binary, Zlib.GZip, F.Plain_Http_Binary, 3, 2,
         "HttpClient chunked-like split gzip body");
      S.Assert_Streaming_OK
        (F.Zlib_Binary, Zlib.Zlib_Header, F.Plain_Binary, 3, 2,
         "HttpClient chunked-like split zlib body");
      S.Expect_Streaming_Zlib_Error
        (F.Missing_GZip_Trailer, Zlib.GZip,
         "HttpClient truncated gzip response maps to Zlib_Error");
      S.Expect_Streaming_Zlib_Error
        (F.Truncated_Zlib_Adler, Zlib.Zlib_Header,
         "HttpClient truncated zlib response maps to Zlib_Error");
      S.Expect_Streaming_Zlib_Error
        (F.Bad_GZip_CRC32, Zlib.GZip,
         "HttpClient bad gzip checksum maps to Zlib_Error");
      S.Expect_Streaming_Zlib_Error
        (F.Bad_Zlib_Adler, Zlib.Zlib_Header,
         "HttpClient bad Adler checksum maps to Zlib_Error");
   end Test_Httpclient_Body_Fixtures;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_Version_Git_Shaped_Payloads'Access,
         "version Git-shaped payloads roundtrip without header parsing");
      Registration.Register_Routine
        (T, Test_Httpclient_Body_Fixtures'Access,
         "HttpClient compressed body fixtures stream exactly");
   end Register_Tests;
end Zlib_Consumer_Fixture_Tests;
