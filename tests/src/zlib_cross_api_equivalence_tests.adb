with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;
with Zlib_Fixture_Data;
with Zlib_Conformance_Test_Support;

package body Zlib_Cross_Api_Equivalence_Tests is
   use type Zlib.Status_Code;

   package F renames Zlib_Fixture_Data;
   package S renames Zlib_Conformance_Test_Support;
   package SIO renames Ada.Streams.Stream_IO;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib cross-API equivalence");
   end Name;

   procedure Delete_If_Exists (Path : String) is
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   end Delete_If_Exists;

   procedure Write_Bytes
     (Path : String;
      Data : Zlib.Byte_Array)
   is
      File : SIO.File_Type;
   begin
      Ada.Directories.Create_Path (Ada.Directories.Containing_Directory (Path));
      SIO.Create (File, SIO.Out_File, Path);
      if Data'Length > 0 then
         declare
            Buffer : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Data'Length));
         begin
            for I in Data'Range loop
               Buffer (Ada.Streams.Stream_Element_Offset (I - Data'First + 1)) :=
                 Ada.Streams.Stream_Element (Data (I));
            end loop;
            SIO.Write (File, Buffer);
         end;
      end if;
      SIO.Close (File);
   end Write_Bytes;

   function Read_Bytes
     (Path : String)
      return Zlib.Byte_Array
   is
      File : SIO.File_Type;
   begin
      SIO.Open (File, SIO.In_File, Path);
      declare
         Size : constant Natural := Natural (SIO.Size (File));
      begin
         if Size = 0 then
            SIO.Close (File);
            return [1 .. 0 => 0];
         end if;

         declare
            Buffer : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Size));
            Last   : Ada.Streams.Stream_Element_Offset;
            Result : Zlib.Byte_Array (1 .. Size);
         begin
            SIO.Read (File, Buffer, Last);
            SIO.Close (File);
            for I in Result'Range loop
               Result (I) := Zlib.Byte (Buffer (Ada.Streams.Stream_Element_Offset (I)));
            end loop;
            return Result;
         end;
      end;
   end Read_Bytes;

   procedure Assert_All_Chunks
     (Input    : Zlib.Byte_Array;
      Header   : Zlib.Header_Type;
      Expected : Zlib.Byte_Array;
      Message  : String)
   is
      Input_Chunks  : constant array (Positive range 1 .. 5) of Positive :=
        [1, 2, 3, 5, Positive'Max (Input'Length, 1)];
      Output_Chunks : constant array (Positive range 1 .. 4) of Positive :=
        [1, 2, 7, Positive'Max (Expected'Length, 1)];
   begin
      S.Assert_One_Shot_OK (Input, Header, Expected, Message & ": one-shot");
      for IC of Input_Chunks loop
         for OC of Output_Chunks loop
            S.Assert_Streaming_OK
              (Input, Header, Expected, IC, OC,
               Message & ": chunk matrix");
         end loop;
      end loop;
   end Assert_All_Chunks;

   procedure Test_Valid_Fixtures_Equivalent
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_All_Chunks (F.Zlib_Stored, Zlib.Zlib_Header, F.Plain_Stored, "zlib stored");
      Assert_All_Chunks (F.Zlib_Fixed, Zlib.Zlib_Header, F.Plain_Fixed, "zlib fixed");
      Assert_All_Chunks (F.Zlib_Dynamic, Zlib.Zlib_Header, F.Plain_Dynamic, "zlib dynamic");
      Assert_All_Chunks (F.Zlib_Binary, Zlib.Zlib_Header, F.Plain_Binary, "zlib binary");
      Assert_All_Chunks (F.Zlib_Git_Blob, Zlib.Zlib_Header, F.Plain_Git_Blob, "zlib git");
      Assert_All_Chunks
        (F.Zlib_Large_Repeated, Zlib.Zlib_Header, F.Plain_Large_Repeated,
         "zlib large repeated");
      Assert_All_Chunks (F.GZip_Fixed, Zlib.GZip, F.Plain_Fixed, "gzip fixed");
      Assert_All_Chunks (F.GZip_Dynamic, Zlib.GZip, F.Plain_Dynamic, "gzip dynamic");
      Assert_All_Chunks (F.Raw_Stored, Zlib.Raw_Deflate, F.Plain_Stored, "raw stored");
      Assert_All_Chunks (F.Raw_Fixed, Zlib.Raw_Deflate, F.Plain_Fixed, "raw fixed");
      Assert_All_Chunks (F.Raw_Dynamic, Zlib.Raw_Deflate, F.Plain_Dynamic, "raw dynamic");
   end Test_Valid_Fixtures_Equivalent;

   procedure Test_Zlib_File_Api_Equivalent
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      In_Path  : constant String := "tests/obj/conformance_fixture.z";
      Out_Path : constant String := "tests/obj/conformance_fixture.out";
      Status   : Zlib.Status_Code;
   begin
      Delete_If_Exists (In_Path);
      Delete_If_Exists (Out_Path);
      Write_Bytes (In_Path, F.Zlib_Binary);
      Zlib.Inflate_File (In_Path, Out_Path, Status);
      Assert (Status = Zlib.Ok, "Inflate_File zlib status");
      S.Assert_Bytes_Equal (Read_Bytes (Out_Path), F.Plain_Binary, "Inflate_File output");
      Delete_If_Exists (In_Path);
      Delete_If_Exists (Out_Path);
   end Test_Zlib_File_Api_Equivalent;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_Valid_Fixtures_Equivalent'Access,
         "valid fixtures match one-shot and streaming across chunk matrix");
      Registration.Register_Routine
        (T, Test_Zlib_File_Api_Equivalent'Access,
         "zlib file API is equivalent to one-shot output");
   end Register_Tests;
end Zlib_Cross_Api_Equivalence_Tests;
