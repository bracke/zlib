with Ada.Containers.Vectors;
with Ada.Streams;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;
with Zlib_Fixture_Data;

package body Zlib_Streaming_GZip_Metadata_Tests is
   use type Ada.Streams.Stream_Element_Offset;
   use type Zlib.Byte;
   use type Zlib.Status_Code;

   package F renames Zlib_Fixture_Data;

   package Byte_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Zlib.Byte);

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib streaming gzip metadata output");
   end Name;

   function Produced
     (Data : Ada.Streams.Stream_Element_Array;
      Last : Ada.Streams.Stream_Element_Offset)
      return Natural
   is
   begin
      if Data'Length = 0 or else Last < Data'First then
         return 0;
      end if;
      return Natural (Last - Data'First + 1);
   end Produced;

   function To_Stream_Array
     (Input : Zlib.Byte_Array)
      return Ada.Streams.Stream_Element_Array
   is
      Result : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Input'Length));
   begin
      for I in Input'Range loop
         Result (Ada.Streams.Stream_Element_Offset (I - Input'First + 1)) :=
           Ada.Streams.Stream_Element (Input (I));
      end loop;
      return Result;
   end To_Stream_Array;

   function To_Byte_Array
     (V : Byte_Vectors.Vector)
      return Zlib.Byte_Array
   is
      Result : Zlib.Byte_Array (1 .. Natural (V.Length));
      J      : Natural := Result'First;
   begin
      for B of V loop
         Result (J) := B;
         J := J + 1;
      end loop;
      return Result;
   end To_Byte_Array;

   procedure Append
     (V    : in out Byte_Vectors.Vector;
      Data : Ada.Streams.Stream_Element_Array;
      Last : Ada.Streams.Stream_Element_Offset)
   is
      Count : constant Natural := Produced (Data, Last);
   begin
      for I in Data'First .. Data'First + Ada.Streams.Stream_Element_Offset (Count) - 1 loop
         V.Append (Zlib.Byte (Data (I)));
      end loop;
   end Append;

   procedure Assert_Same
     (Actual   : Zlib.Byte_Array;
      Expected : Zlib.Byte_Array;
      Message  : String)
   is
   begin
      Assert (Actual'Length = Expected'Length, Message & ": length mismatch");
      for I in Expected'Range loop
         Assert
           (Actual (Actual'First + (I - Expected'First)) = Expected (I),
            Message & ": byte mismatch");
      end loop;
   end Assert_Same;

   procedure Test_One_Byte_Output_Buffer (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Filter   : Zlib.Compression_Filter_Type;
      Metadata : Zlib.GZip_Metadata := Zlib.No_GZip_Metadata;
      Input    : constant Ada.Streams.Stream_Element_Array := To_Stream_Array (F.Plain_Stored);
      Next_In  : Ada.Streams.Stream_Element_Offset := Input'First;
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Out_Data      : Ada.Streams.Stream_Element_Array (1 .. 1);
      Bytes    : Byte_Vectors.Vector;
      Calls    : Natural := 0;
      Status   : Zlib.Status_Code;
   begin
      Zlib.Set_Name (Metadata, "streaming-name-with-many-bytes.bin");
      Zlib.Set_Comment (Metadata, "streaming-comment-with-many-bytes");
      Zlib.Set_Header_CRC (Metadata, True);
      Zlib.Deflate_Init (Filter, Header => Zlib.GZip, Mode => Zlib.Fixed, Metadata => Metadata);

      while Next_In <= Input'Last loop
         Zlib.Compress
           (Filter, Input (Next_In .. Input'Last), In_Last, Out_Data, Out_Last, Zlib.No_Flush);
         Append (Bytes, Out_Data, Out_Last);
         if In_Last >= Next_In then
            Next_In := In_Last + 1;
         end if;
         Calls := Calls + 1;
         Assert (Calls < 100_000, "streaming metadata compression must make progress");
      end loop;

      while not Zlib.Compress_Stream_End (Filter) loop
         Zlib.Compress_Flush (Filter, Out_Data, Out_Last, Zlib.Finish);
         Append (Bytes, Out_Data, Out_Last);
         Calls := Calls + 1;
         Assert (Calls < 100_000, "streaming metadata finish must make progress");
      end loop;
      Zlib.Compress_Close (Filter, Ignore_Error => True);

      declare
         GZ       : constant Zlib.Byte_Array := To_Byte_Array (Bytes);
         Inflated : constant Zlib.Byte_Array := Zlib.Inflate_With_Header (GZ, Zlib.GZip, Status);
      begin
         Assert (Status = Zlib.Ok, "streaming gzip metadata output must inflate");
         Assert (GZ (4) = 16#1A#, "streaming gzip metadata FLG must include FHCRC/FNAME/FCOMMENT");
         Assert_Same (Inflated, F.Plain_Stored, "streaming gzip metadata roundtrip");
      end;
   end Test_One_Byte_Output_Buffer;

   procedure Test_Invalid_Metadata_Rejected_At_Init (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Filter   : Zlib.Compression_Filter_Type;
      Metadata : Zlib.GZip_Metadata := Zlib.No_GZip_Metadata;
      Raised   : Boolean := False;
   begin
      Zlib.Set_Comment (Metadata, "bad" & Character'Val (0) & "comment");
      begin
         Zlib.Deflate_Init (Filter, Header => Zlib.GZip, Mode => Zlib.Stored, Metadata => Metadata);
      exception
         when Zlib.Status_Error =>
            Raised := True;
      end;
      Assert (Raised, "streaming invalid gzip metadata must raise Status_Error at init");
   end Test_Invalid_Metadata_Rejected_At_Init;

   procedure Test_Metadata_Rejected_For_Raw_Deflate (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Filter   : Zlib.Compression_Filter_Type;
      Metadata : Zlib.GZip_Metadata := Zlib.No_GZip_Metadata;
      Raised   : Boolean := False;
   begin
      Zlib.Set_Name (Metadata, "raw-is-not-gzip");
      begin
         Zlib.Deflate_Init (Filter, Header => Zlib.Raw_Deflate, Mode => Zlib.Stored, Metadata => Metadata);
      exception
         when Zlib.Status_Error =>
            Raised := True;
      end;
      Assert (Raised, "streaming raw Deflate must reject gzip metadata");
   end Test_Metadata_Rejected_For_Raw_Deflate;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_One_Byte_Output_Buffer'Access, "gzip metadata one-byte output buffer");
      Register_Routine
        (T, Test_Invalid_Metadata_Rejected_At_Init'Access,
         "invalid metadata rejected at streaming init");
      Register_Routine
        (T, Test_Metadata_Rejected_For_Raw_Deflate'Access,
         "gzip metadata rejected for raw streaming output");
   end Register_Tests;
end Zlib_Streaming_GZip_Metadata_Tests;
