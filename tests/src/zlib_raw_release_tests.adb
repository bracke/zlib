with Ada.Containers.Vectors;
with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;

package body Zlib_Raw_Release_Tests is
   use type Ada.Streams.Stream_Element_Offset;
   use type Zlib.Byte;
   use type Zlib.Status_Code;

   package SIO renames Ada.Streams.Stream_IO;

   package Byte_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Zlib.Byte);

   type Mode_Array is array (Positive range <>) of Zlib.Compression_Mode;
   Raw_Modes : constant Mode_Array := [Zlib.Stored, Zlib.Fixed, Zlib.Dynamic, Zlib.Auto];

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib raw Deflate release hardening");
   end Name;

   function Empty return Zlib.Byte_Array is
   begin
      return [1 .. 0 => 0];
   end Empty;

   function Mode_Name
     (Mode : Zlib.Compression_Mode)
      return String
   is
   begin
      case Mode is
         when Zlib.Stored  => return "Stored";
         when Zlib.Fixed   => return "Fixed";
         when Zlib.Dynamic => return "Dynamic";
         when Zlib.Auto    => return "Auto";
      end case;
   end Mode_Name;

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
     (Output : in out Byte_Vectors.Vector;
      Buffer : Ada.Streams.Stream_Element_Array;
      Last   : Ada.Streams.Stream_Element_Offset)
   is
      Count : constant Natural := Produced (Buffer, Last);
   begin
      for I in Buffer'First .. Buffer'First + Ada.Streams.Stream_Element_Offset (Count) - 1 loop
         Output.Append (Zlib.Byte (Buffer (I)));
      end loop;
   end Append_Output;

   function To_Bytes
     (Data : Byte_Vectors.Vector)
      return Zlib.Byte_Array
   is
   begin
      if Data.Is_Empty then
         return Empty;
      end if;

      declare
         Result : Zlib.Byte_Array (1 .. Natural (Data.Length));
         Index  : Natural := Result'First;
      begin
         for B of Data loop
            Result (Index) := B;
            Index := Index + 1;
         end loop;
         return Result;
      end;
   end To_Bytes;

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

   procedure Delete_If_Exists
     (Path : String)
   is
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
      SIO.Create (File, SIO.Out_File, Path);
      if Data'Length > 0 then
         declare
            Buffer : constant Ada.Streams.Stream_Element_Array := To_Stream (Data);
         begin
            SIO.Write (File, Buffer);
         end;
      end if;
      SIO.Close (File);
   exception
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         raise;
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
            return Empty;
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
              (Natural (Last - Buffer'First + 1) = Size,
               "raw release file read must consume whole file");
            for I in Result'Range loop
               Result (I) := Zlib.Byte (Buffer (Ada.Streams.Stream_Element_Offset (I)));
            end loop;
            return Result;
         end;
      end;
   exception
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         raise;
   end Read_Bytes;

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
            Message & ": byte mismatch at offset" & Natural'Image (I - Expected'First));
      end loop;
   end Assert_Same;

   function Binary_Payload
     (Length : Positive)
      return Zlib.Byte_Array
   is
      Result : Zlib.Byte_Array (1 .. Length);
   begin
      for I in Result'Range loop
         Result (I) := Zlib.Byte ((I * 73 + 19) mod 256);
      end loop;
      return Result;
   end Binary_Payload;

   function Repeated_Payload
     (Length : Positive)
      return Zlib.Byte_Array
   is
      Result  : Zlib.Byte_Array (1 .. Length);
      Pattern : constant Zlib.Byte_Array :=
        [1 => Zlib.Byte (Character'Pos ('r')),
         2 => Zlib.Byte (Character'Pos ('a')),
         3 => Zlib.Byte (Character'Pos ('w')),
         4 => Zlib.Byte (Character'Pos ('-')),
         5 => Zlib.Byte (Character'Pos ('d')),
         6 => Zlib.Byte (Character'Pos ('e')),
         7 => Zlib.Byte (Character'Pos ('f')),
         8 => Zlib.Byte (Character'Pos ('l')),
         9 => Zlib.Byte (Character'Pos ('a')),
         10 => Zlib.Byte (Character'Pos ('t')),
         11 => Zlib.Byte (Character'Pos ('e')),
         12 => 10];
   begin
      for I in Result'Range loop
         Result (I) := Pattern (Pattern'First + ((I - Result'First) mod Pattern'Length));
      end loop;
      return Result;
   end Repeated_Payload;

   function Git_Shaped_Payload
     (Length : Positive)
      return Zlib.Byte_Array
   is
      Result  : Zlib.Byte_Array (1 .. Length);
      Pattern : constant String :=
        "blob 12345" & Character'Val (0) &
        "tree 0123456789abcdef0123456789abcdef01234567" & Character'Val (10) &
        "parent fedcba9876543210fedcba9876543210fedcba98" & Character'Val (10) &
        "author Ada User <ada@example.invalid> 0 +0000" & Character'Val (10) &
        "committer Ada User <ada@example.invalid> 0 +0000" & Character'Val (10) &
        Character'Val (10) &
        "raw release hardening fixture" & Character'Val (10);
   begin
      for I in Result'Range loop
         Result (I) :=
           Zlib.Byte (Character'Pos (Pattern (Pattern'First + ((I - Result'First) mod Pattern'Length))));
      end loop;
      return Result;
   end Git_Shaped_Payload;

   function Streaming_Raw_Compress
     (Input              : Zlib.Byte_Array;
      Mode               : Zlib.Compression_Mode;
      Input_Chunk_Size   : Positive := 257;
      Output_Chunk_Size  : Positive := 17;
      Empty_Alternation  : Boolean := False;
      No_Flush_Drains    : Natural := 0;
      Finish_With_Input  : Boolean := False)
      return Zlib.Byte_Array
   is
      Filter     : Zlib.Compression_Filter_Type;
      Input_Data : constant Ada.Streams.Stream_Element_Array := To_Stream (Input);
      Empty_In   : constant Ada.Streams.Stream_Element_Array (1 .. 0) := [];
      Output     : Byte_Vectors.Vector;
      Next_Input : Ada.Streams.Stream_Element_Offset := Input_Data'First;
      In_Last    : Ada.Streams.Stream_Element_Offset;
      Out_Last   : Ada.Streams.Stream_Element_Offset;
      Calls      : Natural := 0;
   begin
      Zlib.Deflate_Init (Filter, Header => Zlib.Raw_Deflate, Mode => Mode);

      while Input_Data'Length > 0 and then Next_Input <= Input_Data'Last loop
         if Empty_Alternation then
            declare
               Out_Buffer : Ada.Streams.Stream_Element_Array
                 (1 .. Ada.Streams.Stream_Element_Offset (Output_Chunk_Size));
            begin
               Zlib.Compress (Filter, Empty_In, In_Last, Out_Buffer, Out_Last, Zlib.No_Flush);
               Append_Output (Output, Out_Buffer, Out_Last);
            end;
         end if;

         declare
            Chunk_Last : constant Ada.Streams.Stream_Element_Offset :=
              Ada.Streams.Stream_Element_Offset'Min
                (Input_Data'Last,
                 Next_Input + Ada.Streams.Stream_Element_Offset (Input_Chunk_Size) - 1);
            Out_Buffer : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Output_Chunk_Size));
            Flush_Mode : constant Zlib.Flush_Mode :=
              (if Finish_With_Input and then Chunk_Last = Input_Data'Last
               then Zlib.Finish
               else Zlib.No_Flush);
         begin
            Zlib.Compress
              (Filter   => Filter,
               In_Data  => Input_Data (Next_Input .. Chunk_Last),
               In_Last  => In_Last,
               Out_Data => Out_Buffer,
               Out_Last => Out_Last,
               Flush    => Flush_Mode);
            Append_Output (Output, Out_Buffer, Out_Last);
            if In_Last >= Next_Input then
               Next_Input := In_Last + 1;
            end if;
            Calls := Calls + 1;
            Assert (Calls < 5_000_000, Mode_Name (Mode) & " raw compression input loop must progress");
         end;
      end loop;

      for I in 1 .. No_Flush_Drains loop
         declare
            Out_Buffer : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Output_Chunk_Size));
         begin
            Zlib.Compress_Flush (Filter, Out_Buffer, Out_Last, Zlib.No_Flush);
            Append_Output (Output, Out_Buffer, Out_Last);
         end;
      end loop;

      while not Zlib.Compress_Stream_End (Filter) loop
         declare
            Out_Buffer : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Output_Chunk_Size));
         begin
            Zlib.Compress_Flush (Filter, Out_Buffer, Out_Last, Zlib.Finish);
            Append_Output (Output, Out_Buffer, Out_Last);
            Calls := Calls + 1;
            Assert (Calls < 5_000_000, Mode_Name (Mode) & " raw compression finish loop must progress");
         end;
      end loop;

      Zlib.Compress_Close (Filter);
      return To_Bytes (Output);
   exception
      when others =>
         if Zlib.Is_Open (Filter) then
            Zlib.Compress_Close (Filter, Ignore_Error => True);
         end if;
         raise;
   end Streaming_Raw_Compress;

   function Streaming_Raw_Inflate
     (Input             : Zlib.Byte_Array;
      Output_Chunk_Size : Positive := 13)
      return Zlib.Byte_Array
   is
      Filter     : Zlib.Filter_Type;
      Input_Data : constant Ada.Streams.Stream_Element_Array := To_Stream (Input);
      Output     : Byte_Vectors.Vector;
      Next_Input : Ada.Streams.Stream_Element_Offset := Input_Data'First;
      In_Last    : Ada.Streams.Stream_Element_Offset;
      Out_Last   : Ada.Streams.Stream_Element_Offset;
      Calls      : Natural := 0;
   begin
      Zlib.Inflate_Init (Filter, Header => Zlib.Raw_Deflate);

      while Input_Data'Length > 0 and then Next_Input <= Input_Data'Last loop
         declare
            Chunk_Last : constant Ada.Streams.Stream_Element_Offset :=
              Ada.Streams.Stream_Element_Offset'Min (Input_Data'Last, Next_Input);
            Out_Buffer : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Output_Chunk_Size));
         begin
            Zlib.Translate
              (Filter,
               Input_Data (Next_Input .. Chunk_Last),
               In_Last,
               Out_Buffer,
               Out_Last,
               Flush => (if Chunk_Last = Input_Data'Last then Zlib.Finish else Zlib.No_Flush));
            Append_Output (Output, Out_Buffer, Out_Last);
            if In_Last >= Next_Input then
               Next_Input := In_Last + 1;
            end if;
            Calls := Calls + 1;
            Assert (Calls < 5_000_000, "raw inflate input loop must progress");
         end;
      end loop;

      while not Zlib.Stream_End (Filter) loop
         declare
            Out_Buffer : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Output_Chunk_Size));
         begin
            Zlib.Flush (Filter, Out_Buffer, Out_Last, Zlib.Finish);
            Append_Output (Output, Out_Buffer, Out_Last);
            Calls := Calls + 1;
            Assert (Calls < 5_000_000, "raw inflate finish loop must progress");
         end;
      end loop;

      Zlib.Close (Filter);
      return To_Bytes (Output);
   exception
      when others =>
         if Zlib.Is_Open (Filter) then
            Zlib.Close (Filter, Ignore_Error => True);
         end if;
         raise;
   end Streaming_Raw_Inflate;

   procedure Assert_Rejected
     (Payload : Zlib.Byte_Array;
      Header  : Zlib.Header_Type;
      Label   : String);

   procedure Assert_Raw_Roundtrip
     (Payload : Zlib.Byte_Array;
      Mode    : Zlib.Compression_Mode;
      Label   : String;
      Input_Chunk_Size  : Positive := 257;
      Output_Chunk_Size : Positive := 17)
   is
      Streamed : constant Zlib.Byte_Array :=
        Streaming_Raw_Compress (Payload, Mode, Input_Chunk_Size, Output_Chunk_Size);
      Stream_Decoded : constant Zlib.Byte_Array := Streaming_Raw_Inflate (Streamed, 11);
      Status : Zlib.Status_Code;
      One_Shot : constant Zlib.Byte_Array := Zlib.Deflate_Raw (Payload, Mode, Status);
   begin
      Assert (Status = Zlib.Ok, Label & ": one-shot raw compression status");
      Assert_Same (Stream_Decoded, Payload, Label & ": streaming raw inflate");
      Assert_Same
        (Zlib.Inflate_With_Header (Streamed, Zlib.Raw_Deflate, Status),
         Payload,
         Label & ": one-shot raw inflate of streamed output");
      Assert (Status = Zlib.Ok, Label & ": one-shot raw inflate status");
      Assert_Same
        (Zlib.Inflate_With_Header (One_Shot, Zlib.Raw_Deflate, Status),
         Payload,
         Label & ": one-shot raw semantic roundtrip");
      Assert (Status = Zlib.Ok, Label & ": one-shot raw semantic status");
      Assert_Same
        (Zlib.Inflate_With_Header (Streamed, Zlib.Default, Status),
         Payload,
         Label & ": streamed raw auto-detected by default Inflate");
      Assert (Status = Zlib.Ok, Label & ": streamed raw default status");
      Assert_Same
        (Zlib.Inflate_With_Header (One_Shot, Zlib.Default, Status),
         Payload,
         Label & ": one-shot raw auto-detected by default Inflate");
      Assert (Status = Zlib.Ok, Label & ": one-shot raw default status");
      Assert (Streamed'Length > 0, Label & ": streamed raw output non-empty");
      Assert (One_Shot'Length > 0, Label & ": one-shot raw output non-empty");
   end Assert_Raw_Roundtrip;

   procedure Assert_Rejected
     (Payload : Zlib.Byte_Array;
      Header  : Zlib.Header_Type;
      Label   : String)
   is
      Status : Zlib.Status_Code := Zlib.Ok;
      Output : constant Zlib.Byte_Array := Zlib.Inflate_With_Header (Payload, Header, Status);
      pragma Unreferenced (Output);
   begin
      Assert (Status /= Zlib.Ok, Label);
   end Assert_Rejected;

   procedure Test_Large_Raw_Stored_Roundtrip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_Raw_Roundtrip (Binary_Payload (150_000), Zlib.Stored, "large raw Stored binary", 4096, 19);
      Assert_Raw_Roundtrip (Repeated_Payload (160_000), Zlib.Stored, "large raw Stored repeated", 2048, 7);
      Assert_Raw_Roundtrip (Git_Shaped_Payload (131_123), Zlib.Stored, "large raw Stored Git-shaped", 333, 1);
   end Test_Large_Raw_Stored_Roundtrip;

   procedure Test_Large_Raw_Fixed_Roundtrip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_Raw_Roundtrip (Binary_Payload (150_000), Zlib.Fixed, "large raw Fixed binary", 4096, 19);
      Assert_Raw_Roundtrip (Repeated_Payload (160_000), Zlib.Fixed, "large raw Fixed repeated", 2048, 7);
      Assert_Raw_Roundtrip (Git_Shaped_Payload (131_123), Zlib.Fixed, "large raw Fixed Git-shaped", 333, 1);
   end Test_Large_Raw_Fixed_Roundtrip;

   procedure Test_Large_Raw_Dynamic_Roundtrip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_Raw_Roundtrip (Binary_Payload (150_000), Zlib.Dynamic, "large raw Dynamic binary", 4096, 19);
      Assert_Raw_Roundtrip (Repeated_Payload (160_000), Zlib.Dynamic, "large raw Dynamic repeated", 2048, 7);
      Assert_Raw_Roundtrip (Git_Shaped_Payload (131_123), Zlib.Dynamic, "large raw Dynamic Git-shaped", 333, 1);
   end Test_Large_Raw_Dynamic_Roundtrip;

   procedure Test_Large_Raw_Auto_Roundtrip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_Raw_Roundtrip (Binary_Payload (150_000), Zlib.Auto, "large raw Auto binary", 4096, 19);
      Assert_Raw_Roundtrip (Repeated_Payload (160_000), Zlib.Auto, "large raw Auto repeated", 2048, 7);
      Assert_Raw_Roundtrip (Git_Shaped_Payload (131_123), Zlib.Auto, "large raw Auto Git-shaped", 333, 1);
   end Test_Large_Raw_Auto_Roundtrip;

   procedure Test_Tiny_Buffer_Raw_Stress
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Payload : constant Zlib.Byte_Array := Binary_Payload (4_096);
   begin
      for Mode of Raw_Modes loop
         declare
            C1 : constant Zlib.Byte_Array :=
              Streaming_Raw_Compress
                (Payload, Mode, 1, 1, Empty_Alternation => True, No_Flush_Drains => 32);
            D1 : constant Zlib.Byte_Array := Streaming_Raw_Inflate (C1, 1);
            C2 : constant Zlib.Byte_Array :=
              Streaming_Raw_Compress
                (Payload, Mode, 1, 1, Finish_With_Input => True);
            D2 : constant Zlib.Byte_Array := Streaming_Raw_Inflate (C2, 1);
         begin
            Assert_Same (D1, Payload, Mode_Name (Mode) & " tiny-buffer alternating input");
            Assert_Same (D2, Payload, Mode_Name (Mode) & " Finish with pending one-byte output");
         end;
      end loop;
   end Test_Tiny_Buffer_Raw_Stress;

   procedure Test_Many_Chunk_Raw_Stress
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Payload : constant Zlib.Byte_Array := Git_Shaped_Payload (24_003);
   begin
      for Mode of Raw_Modes loop
         Assert_Raw_Roundtrip (Payload, Mode, Mode_Name (Mode) & " many one-byte chunks", 1, 3);
      end loop;
   end Test_Many_Chunk_Raw_Stress;

   procedure Test_Raw_Determinism_Across_Repeated_Runs
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Payload : constant Zlib.Byte_Array := Git_Shaped_Payload (19_999);
      Status  : Zlib.Status_Code;
   begin
      for Mode of Raw_Modes loop
         declare
            S1 : constant Zlib.Byte_Array := Streaming_Raw_Compress (Payload, Mode, 13, 7);
            S2 : constant Zlib.Byte_Array := Streaming_Raw_Compress (Payload, Mode, 13, 7);
            S3 : constant Zlib.Byte_Array := Streaming_Raw_Compress (Payload, Mode, 13, 7);
            O1 : constant Zlib.Byte_Array := Zlib.Deflate_Raw (Payload, Mode, Status);
         begin
            Assert (Status = Zlib.Ok, Mode_Name (Mode) & " one-shot determinism status 1");
            declare
               O2 : constant Zlib.Byte_Array := Zlib.Deflate_Raw (Payload, Mode, Status);
            begin
               Assert (Status = Zlib.Ok, Mode_Name (Mode) & " one-shot determinism status 2");
               Assert_Same (S2, S1, Mode_Name (Mode) & " streaming deterministic run 2");
               Assert_Same (S3, S1, Mode_Name (Mode) & " streaming deterministic run 3");
               Assert_Same (O2, O1, Mode_Name (Mode) & " one-shot deterministic run 2");
            end;
         end;
      end loop;
   end Test_Raw_Determinism_Across_Repeated_Runs;

   procedure Test_Raw_One_Shot_Vs_Streaming_Semantic_Equivalence
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Payload : constant Zlib.Byte_Array := Repeated_Payload (8_001);
      Status  : Zlib.Status_Code;
   begin
      for Mode of Raw_Modes loop
         declare
            One    : constant Zlib.Byte_Array := Zlib.Deflate_Raw (Payload, Mode, Status);
            Stream : constant Zlib.Byte_Array := Streaming_Raw_Compress (Payload, Mode, 31, 23);
         begin
            Assert (Status = Zlib.Ok, Mode_Name (Mode) & " one-shot raw status");
            Assert_Same
              (Zlib.Inflate_With_Header (One, Zlib.Raw_Deflate, Status),
               Payload,
               Mode_Name (Mode) & " one-shot raw semantic payload");
            Assert (Status = Zlib.Ok, Mode_Name (Mode) & " one-shot raw inflate status");
            Assert_Same
              (Zlib.Inflate_With_Header (Stream, Zlib.Raw_Deflate, Status),
               Payload,
               Mode_Name (Mode) & " streaming raw semantic payload");
            Assert (Status = Zlib.Ok, Mode_Name (Mode) & " streaming raw inflate status");
         end;
      end loop;
   end Test_Raw_One_Shot_Vs_Streaming_Semantic_Equivalence;

   procedure Test_Raw_Wrapper_Strictness_Matrix
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Payload : constant Zlib.Byte_Array := Git_Shaped_Payload (2_000);
      Status  : Zlib.Status_Code;
   begin
      for Mode of Raw_Modes loop
         declare
            Raw_Status  : Zlib.Status_Code;
            Zlib_Status : Zlib.Status_Code;
            Gzip_Status : Zlib.Status_Code;
            Raw_Out     : constant Zlib.Byte_Array :=
              Zlib.Deflate_Raw (Payload, Mode, Raw_Status);
            Zlib_Out    : constant Zlib.Byte_Array :=
              Zlib.Deflate (Payload, Mode, Zlib_Status);
            Gzip_Out    : constant Zlib.Byte_Array :=
              Zlib.GZip (Payload, Mode, Gzip_Status);
         begin
            Assert (Raw_Status = Zlib.Ok, Mode_Name (Mode) & " raw wrapper matrix compression status");
            Assert (Zlib_Status = Zlib.Ok, Mode_Name (Mode) & " zlib wrapper matrix compression status");
            Assert (Gzip_Status = Zlib.Ok, Mode_Name (Mode) & " gzip wrapper matrix compression status");
            Assert_Same
              (Zlib.Inflate_With_Header (Raw_Out, Zlib.Raw_Deflate, Status),
               Payload,
               Mode_Name (Mode) & " raw accepted by Raw_Deflate");
            Assert (Status = Zlib.Ok, Mode_Name (Mode) & " raw accepted status");
            Assert_Same
              (Zlib.Inflate_With_Header (Raw_Out, Zlib.Default, Status),
               Payload,
               Mode_Name (Mode) & " raw accepted by Default");
            Assert (Status = Zlib.Ok, Mode_Name (Mode) & " raw Default status");
            Assert_Rejected (Raw_Out, Zlib.Zlib_Header, Mode_Name (Mode) & " raw rejected by Zlib_Header");
            Assert_Rejected (Raw_Out, Zlib.GZip, Mode_Name (Mode) & " raw rejected by GZip");
            Assert_Rejected (Zlib_Out, Zlib.Raw_Deflate, Mode_Name (Mode) & " zlib rejected by Raw_Deflate");
            Assert_Rejected (Gzip_Out, Zlib.Raw_Deflate, Mode_Name (Mode) & " gzip rejected by Raw_Deflate");
         end;
      end loop;
   end Test_Raw_Wrapper_Strictness_Matrix;

   procedure Test_Raw_Output_Structure_Sanity
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Payload : constant Zlib.Byte_Array := Binary_Payload (257);
      Status  : Zlib.Status_Code;
   begin
      for Mode of Raw_Modes loop
         declare
            Raw_Status  : Zlib.Status_Code;
            Zlib_Status : Zlib.Status_Code;
            Gzip_Status : Zlib.Status_Code;
            Raw_Out     : constant Zlib.Byte_Array :=
              Zlib.Deflate_Raw (Payload, Mode, Raw_Status);
            Zlib_Out    : constant Zlib.Byte_Array :=
              Zlib.Deflate (Payload, Mode, Zlib_Status);
            Gzip_Out    : constant Zlib.Byte_Array :=
              Zlib.GZip (Payload, Mode, Gzip_Status);
         begin
            Assert (Raw_Status = Zlib.Ok, Mode_Name (Mode) & " raw structure compression status");
            Assert (Zlib_Status = Zlib.Ok, Mode_Name (Mode) & " zlib structure compression status");
            Assert (Gzip_Status = Zlib.Ok, Mode_Name (Mode) & " gzip structure compression status");
            Assert_Same
              (Zlib.Inflate_With_Header (Raw_Out, Zlib.Raw_Deflate, Status),
               Payload,
               Mode_Name (Mode) & " raw structure sanity roundtrip");
            Assert (Status = Zlib.Ok, Mode_Name (Mode) & " raw structure sanity status");
            Assert_Rejected (Raw_Out, Zlib.Zlib_Header, Mode_Name (Mode) & " raw has no zlib wrapper/checksum");
            Assert_Rejected (Raw_Out, Zlib.GZip, Mode_Name (Mode) & " raw has no gzip wrapper/trailer");
            Assert_Rejected (Zlib_Out, Zlib.Raw_Deflate, Mode_Name (Mode) & " zlib wrapper bytes are not raw Deflate");
            Assert_Rejected (Gzip_Out, Zlib.Raw_Deflate, Mode_Name (Mode) & " gzip wrapper bytes are not raw Deflate");
         end;
      end loop;
   end Test_Raw_Output_Structure_Sanity;

   procedure Test_Raw_Cleanup_Failure_Lifecycle
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Compression_Filter_Type;
      Inflater : Zlib.Filter_Type;
      Input    : constant Ada.Streams.Stream_Element_Array (1 .. 1) := [1 => 42];
      Output   : Ada.Streams.Stream_Element_Array (1 .. 1);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Raised   : Boolean;
   begin
      for Mode of Raw_Modes loop
         Zlib.Deflate_Init (Filter, Header => Zlib.Raw_Deflate, Mode => Mode);
         Raised := False;
         begin
            Zlib.Compress_Close (Filter, Ignore_Error => False);
         exception
            when Zlib.Zlib_Error =>
               Raised := True;
         end;
         Assert (Raised, Mode_Name (Mode) & " Close before Finish raises Zlib_Error");
         Assert (not Zlib.Is_Open (Filter), Mode_Name (Mode) & " Close before Finish clears state");

         Zlib.Deflate_Init (Filter, Header => Zlib.Raw_Deflate, Mode => Mode);
         Zlib.Compress (Filter, Input, In_Last, Output, Out_Last, Zlib.Finish);
         while not Zlib.Compress_Stream_End (Filter) loop
            Zlib.Compress_Flush (Filter, Output, Out_Last, Zlib.Finish);
         end loop;
         Zlib.Compress_Close (Filter);
         Assert (not Zlib.Is_Open (Filter), Mode_Name (Mode) & " completed raw filter closes");

         Zlib.Deflate_Init (Filter, Header => Zlib.Raw_Deflate, Mode => Mode);
         Assert (Zlib.Is_Open (Filter), Mode_Name (Mode) & " Deflate_Init resets after completed compression");
         Zlib.Compress_Close (Filter, Ignore_Error => True);
      end loop;

      Zlib.Inflate_Init (Inflater, Header => Zlib.Raw_Deflate);
      Raised := False;
      begin
         Zlib.Flush (Inflater, Output, Out_Last, Zlib.Finish);
      exception
         when Zlib.Zlib_Error =>
            Raised := True;
      end;
      Assert (Raised, "failed raw inflate remains deterministic");
      Assert (Zlib.Is_Open (Inflater), "failed raw inflate remains closeable");
      Zlib.Close (Inflater, Ignore_Error => True);
      Assert (not Zlib.Is_Open (Inflater), "Ignore_Error closes failed raw inflate");

      Zlib.Deflate_Init (Filter, Header => Zlib.Raw_Deflate, Mode => Zlib.Auto);
      Assert (Zlib.Is_Open (Filter), "Deflate_Init succeeds after failed inflate cleanup");
      Zlib.Compress_Close (Filter, Ignore_Error => True);
   end Test_Raw_Cleanup_Failure_Lifecycle;

   procedure Test_External_Style_Public_Api_Raw_Contract
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Payload : constant Zlib.Byte_Array := [1 => 1, 2 => 2, 3 => 0, 4 => 255, 5 => 10];
      Status  : Zlib.Status_Code;
      F       : Zlib.Filter_Type;
      CF      : Zlib.Compression_Filter_Type;
      In_Data : constant Ada.Streams.Stream_Element_Array := To_Stream (Payload);
      Out_Data     : Ada.Streams.Stream_Element_Array (1 .. 64);
      In_Last : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
   begin
      declare
         Raw : constant Zlib.Byte_Array := Zlib.Deflate_Raw (Payload, Zlib.Auto, Status);
      begin
         Assert (Status = Zlib.Ok, "external-style Deflate_Raw visible");
         Assert_Same
           (Zlib.Inflate_With_Header (Raw, Zlib.Raw_Deflate, Status),
            Payload,
            "external-style Inflate_With_Header Raw_Deflate visible");
         Assert (Status = Zlib.Ok, "external-style raw inflate status visible");
      end;

      Zlib.Inflate_Init (F, Header => Zlib.Raw_Deflate);
      Assert (Zlib.Is_Open (F), "external-style streaming raw inflate type visible");
      Zlib.Close (F, Ignore_Error => True);

      Zlib.Deflate_Init (CF, Header => Zlib.Raw_Deflate, Mode => Zlib.Auto);
      Zlib.Compress (CF, In_Data, In_Last, Out_Data, Out_Last, Zlib.Finish);
      while not Zlib.Compress_Stream_End (CF) loop
         Zlib.Compress_Flush (CF, Out_Data, Out_Last, Zlib.Finish);
      end loop;
      Zlib.Compress_Close (CF);

      declare
         Input_Path : constant String := "zlib_raw_release_public_api.in";
         Raw_Path   : constant String := "zlib_raw_release_public_api.raw";
      begin
         Delete_If_Exists (Input_Path);
         Delete_If_Exists (Raw_Path);
         Write_Bytes (Input_Path, Payload);
         Zlib.Deflate_Raw_File (Input_Path, Raw_Path, Zlib.Auto, Status);
         Assert (Status = Zlib.Ok, "external-style Deflate_Raw_File visible");
         Assert_Same
           (Zlib.Inflate_With_Header
              (Read_Bytes (Raw_Path), Zlib.Raw_Deflate, Status),
            Payload,
            "external-style Deflate_Raw_File output is raw Deflate");
         Assert (Status = Zlib.Ok, "external-style Deflate_Raw_File inflate status");
         Delete_If_Exists (Input_Path);
         Delete_If_Exists (Raw_Path);
      exception
         when others =>
            Delete_If_Exists (Input_Path);
            Delete_If_Exists (Raw_Path);
            raise;
      end;

      Assert (Zlib.Status_Image (Zlib.Ok) = "ok", "root package release status contract visible");
   end Test_External_Style_Public_Api_Raw_Contract;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine (T, Test_Large_Raw_Stored_Roundtrip'Access, "large raw Stored roundtrip");
      Registration.Register_Routine (T, Test_Large_Raw_Fixed_Roundtrip'Access, "large raw Fixed roundtrip");
      Registration.Register_Routine (T, Test_Large_Raw_Dynamic_Roundtrip'Access, "large raw Dynamic roundtrip");
      Registration.Register_Routine (T, Test_Large_Raw_Auto_Roundtrip'Access, "large raw Auto roundtrip");
      Registration.Register_Routine (T, Test_Tiny_Buffer_Raw_Stress'Access, "tiny-buffer raw stress tests");
      Registration.Register_Routine (T, Test_Many_Chunk_Raw_Stress'Access, "many-chunk raw stress tests");
      Registration.Register_Routine
        (T, Test_Raw_Determinism_Across_Repeated_Runs'Access,
         "raw determinism across repeated runs");
      Registration.Register_Routine
        (T, Test_Raw_One_Shot_Vs_Streaming_Semantic_Equivalence'Access,
         "raw one-shot vs streaming semantic equivalence");
      Registration.Register_Routine (T, Test_Raw_Wrapper_Strictness_Matrix'Access, "raw wrapper strictness matrix");
      Registration.Register_Routine (T, Test_Raw_Output_Structure_Sanity'Access, "raw-output structure sanity");
      Registration.Register_Routine
        (T, Test_Raw_Cleanup_Failure_Lifecycle'Access,
         "raw cleanup/failure lifecycle tests");
      Registration.Register_Routine
        (T, Test_External_Style_Public_Api_Raw_Contract'Access,
         "external-style public API raw contract");
   end Register_Tests;
end Zlib_Raw_Release_Tests;
