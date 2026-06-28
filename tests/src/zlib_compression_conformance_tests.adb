with Ada.Containers.Vectors;
with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Interfaces;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;
with Zlib.Checksums;
with Zlib.CRC32_Internal;
with Zlib_Fixture_Data;
with Zlib_Conformance_Test_Support;

package body Zlib_Compression_Conformance_Tests is
   use type Ada.Streams.Stream_Element_Offset;
   use type Interfaces.Unsigned_32;
   use type Zlib.Byte;
   use type Zlib.Status_Code;
   use Ada.Streams;

   package F renames Zlib_Fixture_Data;
   package S renames Zlib_Conformance_Test_Support;
   package SIO renames Ada.Streams.Stream_IO;

   package Stream_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Ada.Streams.Stream_Element);

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib compression conformance");
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
            Assert
              (Last = Buffer'Last,
               "file helper must read the complete compressed file");
            for I in Result'Range loop
               Result (I) := Zlib.Byte (Buffer (Ada.Streams.Stream_Element_Offset (I)));
            end loop;
            return Result;
         end;
      end;
   end Read_Bytes;

   function Before_First
     (Data : Ada.Streams.Stream_Element_Array)
      return Ada.Streams.Stream_Element_Offset
   is
   begin
      if Data'Length = 0 then
         return Data'First;
      elsif Data'First = Ada.Streams.Stream_Element_Offset'First then
         return Data'First;
      else
         return Data'First - 1;
      end if;
   end Before_First;

   function Produced
     (Data : Ada.Streams.Stream_Element_Array;
      Last : Ada.Streams.Stream_Element_Offset)
      return Natural
   is
   begin
      if Data'Length = 0 or else Last = Before_First (Data) then
         return 0;
      else
         return Natural (Last - Data'First + 1);
      end if;
   end Produced;

   procedure Append_Output
     (Output : in out Stream_Vectors.Vector;
      Buffer : Ada.Streams.Stream_Element_Array;
      Last   : Ada.Streams.Stream_Element_Offset)
   is
      Count : constant Natural := Produced (Buffer, Last);
   begin
      for I in Buffer'First .. Buffer'First + Ada.Streams.Stream_Element_Offset (Count) - 1 loop
         Output.Append (Buffer (I));
      end loop;
   end Append_Output;

   function To_Stream
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
   end To_Stream;

   function To_Bytes
     (Data : Stream_Vectors.Vector)
      return Zlib.Byte_Array
   is
   begin
      if Data.Is_Empty then
         return [1 .. 0 => 0];
      end if;

      declare
         Result : Zlib.Byte_Array (1 .. Natural (Data.Length));
         Index  : Natural := Result'First;
      begin
         for B of Data loop
            Result (Index) := Zlib.Byte (B);
            Index := Index + 1;
         end loop;
         return Result;
      end;
   end To_Bytes;

   function Streaming_Compress
     (Input              : Zlib.Byte_Array;
      Header             : Zlib.Header_Type;
      Mode               : Zlib.Compression_Mode;
      Input_Chunk_Size   : Positive;
      Output_Buffer_Size : Positive)
      return Zlib.Byte_Array
   is
      Filter     : Zlib.Compression_Filter_Type;
      Input_Data : constant Ada.Streams.Stream_Element_Array := To_Stream (Input);
      Output     : Stream_Vectors.Vector;
      Next_Input : Ada.Streams.Stream_Element_Offset := Input_Data'First;
      In_Last    : Ada.Streams.Stream_Element_Offset;
      Out_Last   : Ada.Streams.Stream_Element_Offset;
      Calls      : Natural := 0;
   begin
      Zlib.Deflate_Init (Filter, Header => Header, Mode => Mode);

      while Input_Data'Length > 0 and then Next_Input <= Input_Data'Last loop
         declare
            Chunk_Last : constant Ada.Streams.Stream_Element_Offset :=
              Ada.Streams.Stream_Element_Offset'Min
                (Input_Data'Last,
                 Next_Input + Ada.Streams.Stream_Element_Offset (Input_Chunk_Size) - 1);
            Out_Buffer : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Output_Buffer_Size));
         begin
            Zlib.Compress
              (Filter   => Filter,
               In_Data  => Input_Data (Next_Input .. Chunk_Last),
               In_Last  => In_Last,
               Out_Data => Out_Buffer,
               Out_Last => Out_Last,
               Flush    => Zlib.No_Flush);
            Append_Output (Output, Out_Buffer, Out_Last);

            if In_Last >= Next_Input then
               Next_Input := In_Last + 1;
            end if;

            Calls := Calls + 1;
            Assert (Calls < 1_000_000, "streaming compression input loop progress");
         end;
      end loop;

      while not Zlib.Compress_Stream_End (Filter) loop
         declare
            Out_Buffer : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Output_Buffer_Size));
         begin
            Zlib.Compress_Flush
              (Filter   => Filter,
               Out_Data => Out_Buffer,
               Out_Last => Out_Last,
               Flush    => Zlib.Finish);
            Append_Output (Output, Out_Buffer, Out_Last);

            Calls := Calls + 1;
            Assert (Calls < 1_000_000, "streaming compression finish loop progress");
         end;
      end loop;

      Zlib.Compress_Close (Filter);
      return To_Bytes (Output);
   end Streaming_Compress;

   function Footer_Adler
     (Data : Zlib.Byte_Array)
      return Interfaces.Unsigned_32
   is
   begin
      return Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (Data'Last - 3)), 24)
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (Data'Last - 2)), 16)
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (Data'Last - 1)), 8)
        or Interfaces.Unsigned_32 (Data (Data'Last));
   end Footer_Adler;

   procedure Assert_Compressed_Output
     (Encoded  : Zlib.Byte_Array;
      Expected : Zlib.Byte_Array;
      Message  : String)
   is
   begin
      Assert (Encoded'Length >= 6, Message & ": zlib output minimum length");
      Assert ((Natural (Encoded (Encoded'First)) mod 16) = 8,
              Message & ": zlib CM must be Deflate");
      Assert
        (((Natural (Encoded (Encoded'First)) * 256)
          + Natural (Encoded (Encoded'First + 1))) mod 31 = 0,
         Message & ": zlib header FCHECK");
      Assert
        (((Natural (Encoded (Encoded'First + 1)) / 32) mod 2) = 0,
         Message & ": no preset dictionary flag");
      Assert
        (Footer_Adler (Encoded) = Zlib.Checksums.Adler32 (Expected),
         Message & ": Adler-32 footer");

      S.Assert_One_Shot_OK (Encoded, Zlib.Zlib_Header, Expected, Message);
      S.Assert_Streaming_OK (Encoded, Zlib.Zlib_Header, Expected, 1, 1, Message);
      S.Assert_One_Shot_Fails
        (Encoded, Zlib.Raw_Deflate, Message & ": raw rejects zlib output");
      S.Assert_One_Shot_Fails
        (Encoded, Zlib.GZip, Message & ": gzip rejects zlib output");
   end Assert_Compressed_Output;

   function Trailer_U32_LE
     (Data  : Zlib.Byte_Array;
      Start : Natural)
      return Interfaces.Unsigned_32
   is
   begin
      return Interfaces.Unsigned_32 (Data (Start))
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (Start + 1)), 8)
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (Start + 2)), 16)
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (Start + 3)), 24);
   end Trailer_U32_LE;

   function CRC32_Of
     (Input : Zlib.Byte_Array)
      return Interfaces.Unsigned_32
   is
      State : Zlib.CRC32_Internal.CRC32_State;
   begin
      Zlib.CRC32_Internal.Reset (State);
      for B of Input loop
         Zlib.CRC32_Internal.Update (State, Ada.Streams.Stream_Element (B));
      end loop;
      return Zlib.CRC32_Internal.Value (State);
   end CRC32_Of;

   procedure Assert_GZip_Output
     (Encoded  : Zlib.Byte_Array;
      Expected : Zlib.Byte_Array;
      Message  : String)
   is
      Header : constant Zlib.Byte_Array :=
        [1 => 16#1F#, 2 => 16#8B#, 3 => 16#08#, 4 => 16#00#,
         5 => 16#00#, 6 => 16#00#, 7 => 16#00#, 8 => 16#00#,
         9 => 16#00#, 10 => 16#FF#];
      CRC_Start : constant Natural := Encoded'Last - 7;
      ISZ_Start : constant Natural := Encoded'Last - 3;
   begin
      Assert (Encoded'Length >= 18, Message & ": gzip output minimum length");
      for I in Header'Range loop
         Assert
           (Encoded (Encoded'First + (I - Header'First)) = Header (I),
            Message & ": deterministic gzip header");
      end loop;
      Assert
        (Trailer_U32_LE (Encoded, CRC_Start) = CRC32_Of (Expected),
         Message & ": gzip CRC32 trailer");
      Assert
        (Trailer_U32_LE (Encoded, ISZ_Start) = Interfaces.Unsigned_32 (Expected'Length),
         Message & ": gzip ISIZE trailer");

      S.Assert_One_Shot_OK (Encoded, Zlib.GZip, Expected, Message);
      S.Assert_Streaming_OK (Encoded, Zlib.GZip, Expected, 1, 1, Message);
      S.Assert_One_Shot_Fails
        (Encoded, Zlib.Zlib_Header, Message & ": zlib rejects gzip output");
      S.Assert_One_Shot_Fails
        (Encoded, Zlib.Raw_Deflate, Message & ": raw rejects gzip output");
   end Assert_GZip_Output;

   procedure Assert_Deterministic
     (Left    : Zlib.Byte_Array;
      Right   : Zlib.Byte_Array;
      Message : String)
   is
   begin
      S.Assert_Bytes_Equal (Left, Right, Message & ": deterministic output");
   end Assert_Deterministic;

   procedure Test_Explicit_Compression_Apis
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status_A : Zlib.Status_Code;
      Status_B : Zlib.Status_Code;
   begin
      declare
         A : constant Zlib.Byte_Array := Zlib.Deflate_Stored (F.Plain_Binary, Status_A);
         B : constant Zlib.Byte_Array := Zlib.Deflate_Stored (F.Plain_Binary, Status_B);
      begin
         Assert (Status_A = Zlib.Ok and then Status_B = Zlib.Ok, "Deflate_Stored status");
         Assert_Deterministic (A, B, "Deflate_Stored");
         Assert_Compressed_Output (A, F.Plain_Binary, "Deflate_Stored");
      end;

      declare
         A : constant Zlib.Byte_Array := Zlib.Deflate_Fixed (F.Plain_Binary, Status_A);
         B : constant Zlib.Byte_Array := Zlib.Deflate_Fixed (F.Plain_Binary, Status_B);
      begin
         Assert (Status_A = Zlib.Ok and then Status_B = Zlib.Ok, "Deflate_Fixed status");
         Assert_Deterministic (A, B, "Deflate_Fixed");
         Assert_Compressed_Output (A, F.Plain_Binary, "Deflate_Fixed");
      end;

      declare
         A : constant Zlib.Byte_Array := Zlib.Deflate_Dynamic (F.Plain_Binary, Status_A);
         B : constant Zlib.Byte_Array := Zlib.Deflate_Dynamic (F.Plain_Binary, Status_B);
      begin
         Assert (Status_A = Zlib.Ok and then Status_B = Zlib.Ok, "Deflate_Dynamic status");
         Assert_Deterministic (A, B, "Deflate_Dynamic");
         Assert_Compressed_Output (A, F.Plain_Binary, "Deflate_Dynamic");
      end;
   end Test_Explicit_Compression_Apis;

   procedure Test_Policy_Compression_Apis
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status_A : Zlib.Status_Code;
      Status_B : Zlib.Status_Code;
   begin
      for Mode in Zlib.Compression_Mode loop
         declare
            A : constant Zlib.Byte_Array := Zlib.Deflate (F.Plain_Large_Repeated, Mode, Status_A);
            B : constant Zlib.Byte_Array := Zlib.Deflate (F.Plain_Large_Repeated, Mode, Status_B);
         begin
            Assert (Status_A = Zlib.Ok and then Status_B = Zlib.Ok,
                    "Deflate policy status");
            Assert_Deterministic (A, B, "Deflate policy");
            Assert_Compressed_Output
              (A, F.Plain_Large_Repeated, "Deflate policy zlib output");
         end;
      end loop;
   end Test_Policy_Compression_Apis;

   procedure Test_File_Compression_Apis
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input_Path  : constant String := "tests/obj/conformance_compress.in";
      Output_Path : constant String := "tests/obj/conformance_compress.z";
      Status      : Zlib.Status_Code;
   begin
      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Output_Path);
      Write_Bytes (Input_Path, F.Plain_Binary);

      Zlib.Deflate_Stored_File (Input_Path, Output_Path, Status);
      Assert (Status = Zlib.Ok, "Deflate_Stored_File status");
      Assert_Compressed_Output
        (Read_Bytes (Output_Path), F.Plain_Binary, "Deflate_Stored_File");
      Delete_If_Exists (Output_Path);

      Zlib.Deflate_Fixed_File (Input_Path, Output_Path, Status);
      Assert (Status = Zlib.Ok, "Deflate_Fixed_File status");
      Assert_Compressed_Output
        (Read_Bytes (Output_Path), F.Plain_Binary, "Deflate_Fixed_File");
      Delete_If_Exists (Output_Path);

      Zlib.Deflate_Dynamic_File (Input_Path, Output_Path, Status);
      Assert (Status = Zlib.Ok, "Deflate_Dynamic_File status");
      Assert_Compressed_Output
        (Read_Bytes (Output_Path), F.Plain_Binary, "Deflate_Dynamic_File");
      Delete_If_Exists (Output_Path);

      for Mode in Zlib.Compression_Mode loop
         Zlib.Deflate_File (Input_Path, Output_Path, Mode, Status);
         Assert (Status = Zlib.Ok, "Deflate_File status");
         Assert_Compressed_Output
           (Read_Bytes (Output_Path), F.Plain_Binary, "Deflate_File");
         Delete_If_Exists (Output_Path);
      end loop;

      Delete_If_Exists (Input_Path);
   end Test_File_Compression_Apis;

   procedure Test_Streaming_Zlib_Compression_Matrix
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      for Mode in Zlib.Compression_Mode loop
         declare
            A : constant Zlib.Byte_Array :=
              Streaming_Compress
                (F.Plain_Large_Repeated, Zlib.Zlib_Header, Mode, 1, 1);
            B : constant Zlib.Byte_Array :=
              Streaming_Compress
                (F.Plain_Large_Repeated, Zlib.Zlib_Header, Mode, 19, 7);
         begin
            Assert_Deterministic (A, B, "streaming Deflate zlib policy");
            Assert_Compressed_Output
              (A, F.Plain_Large_Repeated, "streaming Deflate zlib policy");
         end;
      end loop;
   end Test_Streaming_Zlib_Compression_Matrix;

   procedure Test_GZip_Compression_Matrix
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status_A : Zlib.Status_Code;
      Status_B : Zlib.Status_Code;
   begin
      for Mode in Zlib.Compression_Mode loop
         declare
            A : constant Zlib.Byte_Array := Zlib.GZip (F.Plain_Binary, Mode, Status_A);
            B : constant Zlib.Byte_Array := Zlib.GZip (F.Plain_Binary, Mode, Status_B);
         begin
            Assert (Status_A = Zlib.Ok and then Status_B = Zlib.Ok,
                    "GZip policy status");
            Assert_Deterministic (A, B, "GZip policy");
            Assert_GZip_Output
              (A, F.Plain_Binary, "GZip policy gzip output");
         end;
      end loop;
   end Test_GZip_Compression_Matrix;

   procedure Test_Streaming_GZip_Compression_Matrix
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      for Mode in Zlib.Compression_Mode loop
         declare
            A : constant Zlib.Byte_Array :=
              Streaming_Compress (F.Plain_Binary, Zlib.GZip, Mode, 1, 1);
            B : constant Zlib.Byte_Array :=
              Streaming_Compress (F.Plain_Binary, Zlib.GZip, Mode, 17, 5);
         begin
            Assert_Deterministic (A, B, "streaming GZip policy");
            Assert_GZip_Output
              (A, F.Plain_Binary, "streaming GZip policy output");
         end;
      end loop;
   end Test_Streaming_GZip_Compression_Matrix;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_Explicit_Compression_Apis'Access,
         "explicit compression APIs emit deterministic zlib streams");
      Registration.Register_Routine
        (T, Test_Policy_Compression_Apis'Access,
         "Deflate policy APIs emit deterministic zlib streams");
      Registration.Register_Routine
        (T, Test_File_Compression_Apis'Access,
         "file compression APIs emit valid zlib streams");
      Registration.Register_Routine
        (T, Test_Streaming_Zlib_Compression_Matrix'Access,
         "streaming zlib compression matrix emits deterministic streams");
      Registration.Register_Routine
        (T, Test_GZip_Compression_Matrix'Access,
         "GZip APIs emit deterministic gzip streams");
      Registration.Register_Routine
        (T, Test_Streaming_GZip_Compression_Matrix'Access,
         "streaming GZip compression emits deterministic gzip streams");
   end Register_Tests;
end Zlib_Compression_Conformance_Tests;
