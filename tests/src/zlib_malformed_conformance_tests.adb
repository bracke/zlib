with Ada.Streams;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;
with Zlib_Fixture_Data;
with Zlib_Conformance_Test_Support;

package body Zlib_Malformed_Conformance_Tests is
   use type Zlib.Status_Code;

   package F renames Zlib_Fixture_Data;
   package S renames Zlib_Conformance_Test_Support;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib malformed conformance");
   end Name;

   procedure Expect_Status
     (Input    : Zlib.Byte_Array;
      Header   : Zlib.Header_Type;
      Expected : Zlib.Status_Code;
      Message  : String)
   is
      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Input, Header, Status);
      pragma Unreferenced (Output);
   begin
      Assert (Status = Expected, Message & ": status");
   end Expect_Status;

   procedure Expect_Not_Ok
     (Input   : Zlib.Byte_Array;
      Header  : Zlib.Header_Type;
      Message : String)
   is
      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Input, Header, Status);
      pragma Unreferenced (Output);
   begin
      Assert (Status /= Zlib.Ok, Message & ": status must fail");
   end Expect_Not_Ok;

   procedure Test_One_Shot_Malformed_Matrix
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Expect_Status
        (F.Bad_Zlib_CMF_FLG, Zlib.Zlib_Header, Zlib.Invalid_Header,
         "bad zlib CMF/FLG");
      Expect_Status
        (F.Zlib_Preset_Dictionary, Zlib.Zlib_Header,
         Zlib.Unsupported_Preset_Dictionary, "zlib preset dictionary");
      Expect_Status
        (F.Bad_Zlib_Adler, Zlib.Zlib_Header, Zlib.Invalid_Checksum,
         "bad zlib Adler");
      Expect_Status
        (F.Truncated_Zlib_Adler, Zlib.Zlib_Header,
         Zlib.Unexpected_End_Of_Input, "truncated Adler");
      Expect_Status
        (F.Missing_Zlib_Adler, Zlib.Zlib_Header,
         Zlib.Unexpected_End_Of_Input, "missing Adler");

      Expect_Status
        (F.Bad_GZip_ID, Zlib.GZip, Zlib.Invalid_Header, "bad gzip ID");
      Expect_Status
        (F.Bad_GZip_Method, Zlib.GZip, Zlib.Unsupported_Method,
         "unsupported gzip method");
      Expect_Status
        (F.GZip_Reserved_Flags, Zlib.GZip, Zlib.Invalid_Header,
         "gzip reserved FLG bits");
      Expect_Status
        (F.Truncated_GZip_Header, Zlib.GZip, Zlib.Unexpected_End_Of_Input,
         "truncated gzip fixed header");
      Expect_Not_Ok (F.Truncated_GZip_FExtra, Zlib.GZip, "truncated FEXTRA");
      Expect_Not_Ok (F.Truncated_GZip_FName, Zlib.GZip, "truncated FNAME");
      Expect_Not_Ok (F.Truncated_GZip_FComment, Zlib.GZip, "truncated FCOMMENT");
      Expect_Not_Ok (F.Truncated_GZip_FHCRC, Zlib.GZip, "truncated FHCRC");
      Expect_Status
        (F.Bad_GZip_CRC32, Zlib.GZip, Zlib.Invalid_Checksum,
         "bad gzip CRC32");
      Expect_Status
        (F.Bad_GZip_ISIZE, Zlib.GZip, Zlib.Invalid_Checksum,
         "bad gzip ISIZE");
      Expect_Status
        (F.Missing_GZip_Trailer, Zlib.GZip, Zlib.Unexpected_End_Of_Input,
         "missing gzip trailer");

      Expect_Status
        (F.Truncated_Raw_Stored, Zlib.Raw_Deflate,
         Zlib.Unexpected_End_Of_Input, "truncated raw stored block");
      Expect_Not_Ok
        (F.Truncated_Raw_Fixed, Zlib.Raw_Deflate,
         "truncated raw fixed-Huffman block");
      Expect_Not_Ok
        (F.Truncated_Raw_Dynamic_Header, Zlib.Raw_Deflate,
         "truncated raw dynamic-Huffman header");
      Expect_Status
        (F.Raw_Invalid_Block_Type, Zlib.Raw_Deflate,
         Zlib.Invalid_Block_Type, "invalid raw block type");
      Expect_Not_Ok
        (F.Raw_Invalid_Huffman_Code, Zlib.Raw_Deflate,
         "invalid raw Huffman code");
      Expect_Not_Ok
        (F.Raw_Invalid_Distance, Zlib.Raw_Deflate,
         "invalid raw distance");
   end Test_One_Shot_Malformed_Matrix;

   procedure Test_Streaming_Malformed_Matrix
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      S.Expect_Streaming_Zlib_Error
        (F.Bad_Zlib_CMF_FLG, Zlib.Zlib_Header, "stream bad zlib CMF/FLG");
      S.Expect_Streaming_Zlib_Error
        (F.Zlib_Preset_Dictionary, Zlib.Zlib_Header, "stream preset dictionary");
      S.Expect_Streaming_Zlib_Error
        (F.Bad_Zlib_Adler, Zlib.Zlib_Header, "stream bad Adler");
      S.Expect_Streaming_Zlib_Error
        (F.Truncated_Zlib_Adler, Zlib.Zlib_Header, "stream truncated Adler");
      S.Expect_Streaming_Zlib_Error
        (F.Missing_Zlib_Adler, Zlib.Zlib_Header, "stream missing Adler");
      S.Expect_Streaming_Zlib_Error (F.Bad_GZip_ID, Zlib.GZip, "stream bad gzip ID");
      S.Expect_Streaming_Zlib_Error
        (F.Bad_GZip_Method, Zlib.GZip, "stream bad gzip method");
      S.Expect_Streaming_Zlib_Error
        (F.GZip_Reserved_Flags, Zlib.GZip, "stream gzip reserved flags");
      S.Expect_Streaming_Zlib_Error
        (F.Truncated_GZip_Header, Zlib.GZip, "stream truncated gzip header");
      S.Expect_Streaming_Zlib_Error
        (F.Truncated_GZip_FExtra, Zlib.GZip, "stream truncated FEXTRA");
      S.Expect_Streaming_Zlib_Error
        (F.Truncated_GZip_FName, Zlib.GZip, "stream truncated FNAME");
      S.Expect_Streaming_Zlib_Error
        (F.Truncated_GZip_FComment, Zlib.GZip, "stream truncated FCOMMENT");
      S.Expect_Streaming_Zlib_Error
        (F.Truncated_GZip_FHCRC, Zlib.GZip, "stream truncated FHCRC");
      S.Expect_Streaming_Zlib_Error
        (F.Bad_GZip_CRC32, Zlib.GZip, "stream bad gzip CRC32");
      S.Expect_Streaming_Zlib_Error
        (F.Bad_GZip_ISIZE, Zlib.GZip, "stream bad gzip ISIZE");
      S.Expect_Streaming_Zlib_Error
        (F.Missing_GZip_Trailer, Zlib.GZip, "stream missing gzip trailer");
      S.Expect_Streaming_Zlib_Error
        (F.Truncated_Raw_Stored, Zlib.Raw_Deflate, "stream truncated raw stored");
      S.Expect_Streaming_Zlib_Error
        (F.Truncated_Raw_Fixed, Zlib.Raw_Deflate, "stream truncated raw fixed");
      S.Expect_Streaming_Zlib_Error
        (F.Truncated_Raw_Dynamic_Header, Zlib.Raw_Deflate,
         "stream truncated raw dynamic");
      S.Expect_Streaming_Zlib_Error
        (F.Raw_Invalid_Block_Type, Zlib.Raw_Deflate, "stream invalid block type");
      S.Expect_Streaming_Zlib_Error
        (F.Raw_Invalid_Huffman_Code, Zlib.Raw_Deflate, "stream invalid Huffman code");
      S.Expect_Streaming_Zlib_Error
        (F.Raw_Invalid_Distance, Zlib.Raw_Deflate, "stream invalid distance");
   end Test_Streaming_Malformed_Matrix;

   procedure Test_Streaming_Lifecycle_Misuse
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Filter_Type;
      In_Data  : constant Ada.Streams.Stream_Element_Array (1 .. 1) := [1 => 16#00#];
      Out_Data : Ada.Streams.Stream_Element_Array (1 .. 1);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Raised   : Boolean;
   begin
      Raised := False;
      begin
         Zlib.Translate (Filter, In_Data, In_Last, Out_Data, Out_Last);
      exception
         when Zlib.Status_Error =>
            Raised := True;
      end;
      Assert (Raised, "Translate before init must raise Status_Error");

      Raised := False;
      begin
         Zlib.Flush (Filter, Out_Data, Out_Last);
      exception
         when Zlib.Status_Error =>
            Raised := True;
      end;
      Assert (Raised, "Flush before init must raise Status_Error");

      Raised := False;
      begin
         Zlib.Close (Filter);
      exception
         when Zlib.Status_Error =>
            Raised := True;
      end;
      Assert (Raised, "Close before init must raise Status_Error");

      Zlib.Close (Filter, Ignore_Error => True);

      Zlib.Inflate_Init (Filter, Header => Zlib.Zlib_Header);
      begin
         Zlib.Translate
           (Filter, In_Data, In_Last, Out_Data, Out_Last, Zlib.Finish);
      exception
         when Zlib.Zlib_Error =>
            null;
      end;
      Zlib.Close (Filter, Ignore_Error => True);
      Assert (not Zlib.Is_Open (Filter),
              "Close Ignore_Error after streaming failure must close filter");
   end Test_Streaming_Lifecycle_Misuse;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_One_Shot_Malformed_Matrix'Access,
         "one-shot malformed/truncated inputs produce documented failure statuses");
      Registration.Register_Routine
        (T, Test_Streaming_Malformed_Matrix'Access,
         "streaming malformed/truncated inputs raise Zlib_Error");
      Registration.Register_Routine
        (T, Test_Streaming_Lifecycle_Misuse'Access,
         "streaming lifecycle misuse raises Status_Error and failure close is safe");
   end Register_Tests;
end Zlib_Malformed_Conformance_Tests;
