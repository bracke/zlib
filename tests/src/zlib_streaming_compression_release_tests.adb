with Ada.Containers.Vectors;
with Ada.Streams;
with Interfaces;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib; use Zlib;

package body Zlib_Streaming_Compression_Release_Tests is
   use type Ada.Streams.Stream_Element_Offset;
   use type Interfaces.Unsigned_32;

   package Byte_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Zlib.Byte);

   type Header_Array is array (Positive range <>) of Zlib.Header_Type;
   type Mode_Array is array (Positive range <>) of Zlib.Compression_Mode;

   Supported_Headers : constant Header_Array :=
     [Zlib.Default, Zlib.Zlib_Header, Zlib.GZip];
   Supported_Modes : constant Mode_Array :=
     [Zlib.Stored, Zlib.Fixed, Zlib.Dynamic, Zlib.Auto];

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib streaming compression release hardening");
   end Name;

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
     (Data : Byte_Vectors.Vector)
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
            Result (Index) := B;
            Index := Index + 1;
         end loop;
         return Result;
      end;
   end To_Bytes;

   function Header_Name
     (Header : Zlib.Header_Type)
      return String
   is
   begin
      case Header is
         when Zlib.Default     => return "Default";
         when Zlib.Zlib_Header => return "Zlib_Header";
         when Zlib.GZip        => return "GZip";
         when Zlib.Raw_Deflate => return "Raw_Deflate";
      end case;
   end Header_Name;

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

   function Inflate_Header
     (Header : Zlib.Header_Type)
      return Zlib.Header_Type
   is
   begin
      if Header = Zlib.GZip then
         return Zlib.GZip;
      else
         return Zlib.Zlib_Header;
      end if;
   end Inflate_Header;

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
         Result (I) := Zlib.Byte ((I * 37 + 11) mod 256);
      end loop;
      return Result;
   end Binary_Payload;

   function Repeated_Payload
     (Length : Positive)
      return Zlib.Byte_Array
   is
      Result : Zlib.Byte_Array (1 .. Length);
      Pattern : constant Zlib.Byte_Array :=
        [1 => Zlib.Byte (Character'Pos ('a')),
         2 => Zlib.Byte (Character'Pos ('b')),
         3 => Zlib.Byte (Character'Pos ('c')),
         4 => Zlib.Byte (Character'Pos ('d')),
         5 => Zlib.Byte (Character'Pos ('e')),
         6 => Zlib.Byte (Character'Pos ('f')),
         7 => Zlib.Byte (Character'Pos (Character'Val (10)))];
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
      Result : Zlib.Byte_Array (1 .. Length);
      Pattern : constant String :=
        "blob 12345" & Character'Val (10) &
        "tree 0123456789abcdef0123456789abcdef01234567" & Character'Val (10) &
        "parent fedcba9876543210fedcba9876543210fedcba98" & Character'Val (10) &
        "author Ada User <ada@example.invalid> 0 +0000" & Character'Val (10) &
        "committer Ada User <ada@example.invalid> 0 +0000" & Character'Val (10) &
        Character'Val (10) &
        "deterministic release fixture line" & Character'Val (10);
   begin
      for I in Result'Range loop
         Result (I) :=
           Zlib.Byte (Character'Pos (Pattern (Pattern'First + ((I - Result'First) mod Pattern'Length))));
      end loop;
      return Result;
   end Git_Shaped_Payload;

   function Adler_32
     (Input : Zlib.Byte_Array)
      return Interfaces.Unsigned_32
   is
      Modulus : constant Interfaces.Unsigned_32 := 65_521;
      A       : Interfaces.Unsigned_32 := 1;
      B       : Interfaces.Unsigned_32 := 0;
   begin
      for X of Input loop
         A := (A + Interfaces.Unsigned_32 (X)) mod Modulus;
         B := (B + A) mod Modulus;
      end loop;
      return B * 65_536 + A;
   end Adler_32;

   function CRC32
     (Input : Zlib.Byte_Array)
      return Interfaces.Unsigned_32
   is
      C : Interfaces.Unsigned_32 := 16#FFFF_FFFF#;
   begin
      for X of Input loop
         C := C xor Interfaces.Unsigned_32 (X);
         for Bit in 1 .. 8 loop
            if (C and 1) = 1 then
               C := Interfaces.Shift_Right (C, 1) xor 16#EDB8_8320#;
            else
               C := Interfaces.Shift_Right (C, 1);
            end if;
         end loop;
      end loop;
      return C xor 16#FFFF_FFFF#;
   end CRC32;

   function U32_BE_At
     (Data  : Zlib.Byte_Array;
      Index : Natural)
      return Interfaces.Unsigned_32
   is
   begin
      return Interfaces.Unsigned_32 (Data (Index)) * 16#01_00_00_00#
        + Interfaces.Unsigned_32 (Data (Index + 1)) * 16#00_01_00_00#
        + Interfaces.Unsigned_32 (Data (Index + 2)) * 16#00_00_01_00#
        + Interfaces.Unsigned_32 (Data (Index + 3));
   end U32_BE_At;

   function U32_LE_At
     (Data  : Zlib.Byte_Array;
      Index : Natural)
      return Interfaces.Unsigned_32
   is
   begin
      return Interfaces.Unsigned_32 (Data (Index))
        + Interfaces.Unsigned_32 (Data (Index + 1)) * 16#00_00_01_00#
        + Interfaces.Unsigned_32 (Data (Index + 2)) * 16#00_01_00_00#
        + Interfaces.Unsigned_32 (Data (Index + 3)) * 16#01_00_00_00#;
   end U32_LE_At;

   function Streaming_Compress
     (Input              : Zlib.Byte_Array;
      Header             : Zlib.Header_Type;
      Mode               : Zlib.Compression_Mode;
      Input_Chunk_Size   : Positive;
      Output_Chunk_Size  : Positive;
      Empty_Alternation  : Boolean := False;
      No_Flush_Drains    : Natural := 0)
      return Zlib.Byte_Array
   is
      Filter     : Zlib.Compression_Filter_Type;
      Input_Data : constant Ada.Streams.Stream_Element_Array := To_Stream (Input);
      Empty      : constant Ada.Streams.Stream_Element_Array (1 .. 0) := [];
      Output     : Byte_Vectors.Vector;
      Next_Input : Ada.Streams.Stream_Element_Offset := Input_Data'First;
      In_Last    : Ada.Streams.Stream_Element_Offset;
      Out_Last   : Ada.Streams.Stream_Element_Offset;
      Calls      : Natural := 0;
   begin
      Zlib.Deflate_Init (Filter, Header => Header, Mode => Mode);

      while Input_Data'Length > 0 and then Next_Input <= Input_Data'Last loop
         if Empty_Alternation then
            declare
               Out_Buffer : Ada.Streams.Stream_Element_Array
                 (1 .. Ada.Streams.Stream_Element_Offset (Output_Chunk_Size));
            begin
               Zlib.Compress (Filter, Empty, In_Last, Out_Buffer, Out_Last, Zlib.No_Flush);
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
            Assert (Calls < 5_000_000, "streaming compression input phase must make progress");
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
            Assert (Calls < 5_000_000, "streaming compression finish must make progress");
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
   end Streaming_Compress;

   function Streaming_Compress_Finish_With_Input
     (Input             : Zlib.Byte_Array;
      Header            : Zlib.Header_Type;
      Mode              : Zlib.Compression_Mode;
      Output_Chunk_Size : Positive)
      return Zlib.Byte_Array
   is
      Filter     : Zlib.Compression_Filter_Type;
      Input_Data : constant Ada.Streams.Stream_Element_Array := To_Stream (Input);
      Output     : Byte_Vectors.Vector;
      Next_Input : Ada.Streams.Stream_Element_Offset := Input_Data'First;
      In_Last    : Ada.Streams.Stream_Element_Offset;
      Out_Last   : Ada.Streams.Stream_Element_Offset;
      Calls      : Natural := 0;
   begin
      Zlib.Deflate_Init (Filter, Header => Header, Mode => Mode);
      while Input_Data'Length > 0 and then Next_Input <= Input_Data'Last loop
         declare
            Out_Buffer : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Output_Chunk_Size));
         begin
            Zlib.Compress
              (Filter   => Filter,
               In_Data  => Input_Data (Next_Input .. Input_Data'Last),
               In_Last  => In_Last,
               Out_Data => Out_Buffer,
               Out_Last => Out_Last,
               Flush    => Zlib.Finish);
            Append_Output (Output, Out_Buffer, Out_Last);
            if In_Last >= Next_Input then
               Next_Input := In_Last + 1;
            end if;
            Calls := Calls + 1;
            Assert (Calls < 5_000_000, "Finish-with-input must consume boundedly");
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
            Assert (Calls < 5_000_000, "Finish-with-input drain must make progress");
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
   end Streaming_Compress_Finish_With_Input;

   function Streaming_Inflate
     (Input             : Zlib.Byte_Array;
      Header            : Zlib.Header_Type;
      Output_Chunk_Size : Positive)
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
      Zlib.Inflate_Init (Filter, Header => Header);

      while Input_Data'Length > 0 and then Next_Input <= Input_Data'Last loop
         declare
            Chunk_Last : constant Ada.Streams.Stream_Element_Offset :=
              Ada.Streams.Stream_Element_Offset'Min (Input_Data'Last, Next_Input + 2);
            Out_Buffer : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Output_Chunk_Size));
         begin
            Zlib.Translate (Filter, Input_Data (Next_Input .. Chunk_Last), In_Last, Out_Buffer, Out_Last);
            Append_Output (Output, Out_Buffer, Out_Last);
            if In_Last >= Next_Input then
               Next_Input := In_Last + 1;
            end if;
            Calls := Calls + 1;
            Assert (Calls < 5_000_000, "streaming inflate input phase must make progress");
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
            Assert (Calls < 5_000_000, "streaming inflate finish must make progress");
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
   end Streaming_Inflate;

   procedure Assert_Roundtrip
     (Payload : Zlib.Byte_Array;
      Header  : Zlib.Header_Type;
      Mode    : Zlib.Compression_Mode;
      Label   : String;
      Input_Chunk_Size  : Positive := 257;
      Output_Chunk_Size : Positive := 17)
   is
      Status     : Zlib.Status_Code;
      Compressed : constant Zlib.Byte_Array :=
        Streaming_Compress (Payload, Header, Mode, Input_Chunk_Size, Output_Chunk_Size);
      Decoded_Stream : constant Zlib.Byte_Array :=
        Streaming_Inflate (Compressed, Inflate_Header (Header), 11);
      Decoded_One_Shot : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Compressed, Inflate_Header (Header), Status);
   begin
      Assert (Status = Zlib.Ok, Label & ": one-shot explicit inflate status");
      Assert_Same (Decoded_Stream, Payload, Label & ": streaming inflate payload");
      Assert_Same (Decoded_One_Shot, Payload, Label & ": one-shot inflate payload");
      Assert (Compressed'Length > 0, Label & ": compressed output must not be empty");
   end Assert_Roundtrip;

   procedure Test_Large_Payload_Matrix
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Binary   : constant Zlib.Byte_Array := Binary_Payload (131_200);
      Repeated : constant Zlib.Byte_Array := Repeated_Payload (196_700);
      Gitish   : constant Zlib.Byte_Array := Git_Shaped_Payload (140_003);
   begin
      for Header of Supported_Headers loop
         for Mode of Supported_Modes loop
            Assert_Roundtrip (Binary, Header, Mode, Header_Name (Header) & "+" & Mode_Name (Mode) & " large binary");
            Assert_Roundtrip
              (Repeated, Header, Mode,
               Header_Name (Header) & "+" & Mode_Name (Mode) & " large repeated");
            Assert_Roundtrip
              (Gitish, Header, Mode,
               Header_Name (Header) & "+" & Mode_Name (Mode) & " large git-shaped");
         end loop;
      end loop;
   end Test_Large_Payload_Matrix;

   procedure Test_Many_Chunk_Tiny_Buffer_Matrix
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Payload : constant Zlib.Byte_Array := Binary_Payload (4_096);
   begin
      for Header of Supported_Headers loop
         for Mode of Supported_Modes loop
            declare
               C1 : constant Zlib.Byte_Array :=
                 Streaming_Compress
                   (Payload, Header, Mode, 1, 1, Empty_Alternation => True, No_Flush_Drains => 64);
               D1 : constant Zlib.Byte_Array := Streaming_Inflate (C1, Inflate_Header (Header), 1);
               C2 : constant Zlib.Byte_Array :=
                 Streaming_Compress_Finish_With_Input (Payload, Header, Mode, 1);
               D2 : constant Zlib.Byte_Array := Streaming_Inflate (C2, Inflate_Header (Header), 1);
            begin
               Assert_Same (D1, Payload, Header_Name (Header) & "+" & Mode_Name (Mode) & " tiny buffers");
               Assert_Same (D2, Payload, Header_Name (Header) & "+" & Mode_Name (Mode) & " Finish with input");
            end;
         end loop;
      end loop;
   end Test_Many_Chunk_Tiny_Buffer_Matrix;

   procedure Test_Deterministic_Repeated_Runs
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Payload : constant Zlib.Byte_Array := Git_Shaped_Payload (19_999);
   begin
      for Header of Supported_Headers loop
         for Mode of Supported_Modes loop
            declare
               A : constant Zlib.Byte_Array := Streaming_Compress (Payload, Header, Mode, 13, 7);
               B : constant Zlib.Byte_Array := Streaming_Compress (Payload, Header, Mode, 13, 7);
               C : constant Zlib.Byte_Array := Streaming_Compress (Payload, Header, Mode, 13, 7);
            begin
               Assert_Same (B, A, Header_Name (Header) & "+" & Mode_Name (Mode) & " deterministic run 2");
               Assert_Same (C, A, Header_Name (Header) & "+" & Mode_Name (Mode) & " deterministic run 3");
            end;
         end loop;
      end loop;
   end Test_Deterministic_Repeated_Runs;

   procedure Test_Cross_Api_Semantic_Equivalence
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Payload : constant Zlib.Byte_Array := Repeated_Payload (8_001);
      Status  : Zlib.Status_Code;
   begin
      for Mode of Supported_Modes loop
         declare
            One_Zlib : constant Zlib.Byte_Array := Zlib.Deflate (Payload, Mode, Status);
         begin
            Assert (Status = Zlib.Ok, Mode_Name (Mode) & " one-shot zlib compression status");
            declare
               Stream_Zlib : constant Zlib.Byte_Array :=
                 Streaming_Compress (Payload, Zlib.Zlib_Header, Mode, 31, 23);
               One_Status : Zlib.Status_Code;
               One_Decoded : constant Zlib.Byte_Array := Zlib.Inflate (One_Zlib, One_Status);
               Stream_Status : Zlib.Status_Code;
               Stream_Decoded : constant Zlib.Byte_Array := Zlib.Inflate (Stream_Zlib, Stream_Status);
            begin
               Assert (One_Status = Zlib.Ok, Mode_Name (Mode) & " zlib one-shot inflate status");
               Assert (Stream_Status = Zlib.Ok, Mode_Name (Mode) & " zlib streaming inflate status");
               Assert_Same (One_Decoded, Payload, Mode_Name (Mode) & " one-shot zlib semantic payload");
               Assert_Same (Stream_Decoded, Payload, Mode_Name (Mode) & " streaming zlib semantic payload");
            end;
         end;

         declare
            One_Gzip : constant Zlib.Byte_Array := Zlib.GZip (Payload, Mode, Status);
         begin
            Assert (Status = Zlib.Ok, Mode_Name (Mode) & " one-shot gzip compression status");
            declare
               Stream_Gzip : constant Zlib.Byte_Array :=
                 Streaming_Compress (Payload, Zlib.GZip, Mode, 31, 23);
               One_Decoded : constant Zlib.Byte_Array :=
                 Zlib.Inflate_With_Header (One_Gzip, Zlib.GZip, Status);
               Stream_Decoded : constant Zlib.Byte_Array :=
                 Zlib.Inflate_With_Header (Stream_Gzip, Zlib.GZip, Status);
            begin
               Assert (Status = Zlib.Ok, Mode_Name (Mode) & " gzip semantic inflate status");
               Assert_Same (One_Decoded, Payload, Mode_Name (Mode) & " one-shot gzip semantic payload");
               Assert_Same (Stream_Decoded, Payload, Mode_Name (Mode) & " streaming gzip semantic payload");
            end;
         end;
      end loop;
   end Test_Cross_Api_Semantic_Equivalence;

   procedure Test_Trailers_Split_And_Endian
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Payload : constant Zlib.Byte_Array := Binary_Payload (257);
      Zout    : constant Zlib.Byte_Array := Streaming_Compress (Payload, Zlib.Zlib_Header, Zlib.Stored, 1, 1);
      Gout    : constant Zlib.Byte_Array := Streaming_Compress (Payload, Zlib.GZip, Zlib.Stored, 1, 1);
   begin
      Assert (Zout'Length >= 6, "zlib output includes header and Adler-32 trailer");
      Assert
        (U32_BE_At (Zout, Zout'Last - 3) = Adler_32 (Payload),
         "zlib Adler-32 trailer must be big-endian and match input");

      Assert (Gout'Length >= 18, "gzip output includes deterministic header and trailer");
      Assert (Gout (Gout'First) = 16#1F#, "gzip ID1");
      Assert (Gout (Gout'First + 1) = 16#8B#, "gzip ID2");
      Assert (Gout (Gout'First + 2) = 16#08#, "gzip method Deflate");
      Assert (Gout (Gout'First + 3) = 16#00#, "gzip FLG has no optional metadata");
      Assert (Gout (Gout'First + 4) = 16#00#, "gzip MTIME byte 0 deterministic");
      Assert (Gout (Gout'First + 5) = 16#00#, "gzip MTIME byte 1 deterministic");
      Assert (Gout (Gout'First + 6) = 16#00#, "gzip MTIME byte 2 deterministic");
      Assert (Gout (Gout'First + 7) = 16#00#, "gzip MTIME byte 3 deterministic");
      Assert (Gout (Gout'First + 8) = 16#00#, "gzip XFL deterministic");
      Assert (Gout (Gout'First + 9) = 16#FF#, "gzip OS deterministic unknown");
      Assert
        (U32_LE_At (Gout, Gout'Last - 7) = CRC32 (Payload),
         "gzip CRC32 trailer must be little-endian and match input");
      Assert
        (U32_LE_At (Gout, Gout'Last - 3) = Interfaces.Unsigned_32 (Payload'Length),
         "gzip ISIZE trailer must be little-endian input length modulo 2^32");
   end Test_Trailers_Split_And_Endian;

   procedure Test_Wrapper_Strictness_Final
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Payload : constant Zlib.Byte_Array := Git_Shaped_Payload (1_000);
      Status  : Zlib.Status_Code;
      Zout    : constant Zlib.Byte_Array := Streaming_Compress (Payload, Zlib.Zlib_Header, Zlib.Auto, 5, 3);
      Gout    : constant Zlib.Byte_Array := Streaming_Compress (Payload, Zlib.GZip, Zlib.Auto, 5, 3);
   begin
      declare
         Rejected : constant Zlib.Byte_Array := Zlib.Inflate_With_Header (Zout, Zlib.GZip, Status);
         pragma Unreferenced (Rejected);
      begin
         Assert (Status /= Zlib.Ok, "zlib output rejected by GZip mode");
      end;

      declare
         Rejected : constant Zlib.Byte_Array := Zlib.Inflate_With_Header (Zout, Zlib.Raw_Deflate, Status);
         pragma Unreferenced (Rejected);
      begin
         Assert (Status /= Zlib.Ok, "zlib output rejected by Raw_Deflate mode");
      end;

      declare
         Rejected : constant Zlib.Byte_Array := Zlib.Inflate_With_Header (Gout, Zlib.Zlib_Header, Status);
         pragma Unreferenced (Rejected);
      begin
         Assert (Status /= Zlib.Ok, "gzip output rejected by Zlib_Header mode");
      end;

      declare
         Rejected : constant Zlib.Byte_Array := Zlib.Inflate_With_Header (Gout, Zlib.Raw_Deflate, Status);
         pragma Unreferenced (Rejected);
      begin
         Assert (Status /= Zlib.Ok, "gzip output rejected by Raw_Deflate mode");
      end;

      declare
         Rejected : constant Zlib.Byte_Array := Zlib.Inflate (Gout, Status);
         pragma Unreferenced (Rejected);
      begin
         Assert (Status /= Zlib.Ok, "gzip output rejected by Inflate");
      end;
   end Test_Wrapper_Strictness_Final;

   procedure Test_Stream_End_Only_After_Output_Drained
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Payload : constant Zlib.Byte_Array := Binary_Payload (513);
      Status  : Zlib.Status_Code;
   begin
      for Header of Header_Array'[Zlib.Zlib_Header, Zlib.GZip] loop
         declare
            Filter     : Zlib.Compression_Filter_Type;
            Input_Data : constant Ada.Streams.Stream_Element_Array := To_Stream (Payload);
            Output     : Byte_Vectors.Vector;
            Next_Input : Ada.Streams.Stream_Element_Offset := Input_Data'First;
            In_Last    : Ada.Streams.Stream_Element_Offset;
            Out_Last   : Ada.Streams.Stream_Element_Offset;
            Calls      : Natural := 0;
            Final_Count : Natural := 0;
         begin
            Zlib.Deflate_Init (Filter, Header => Header, Mode => Zlib.Stored);
            Assert
              (not Zlib.Compress_Stream_End (Filter),
               Header_Name (Header) & " stream end must be false immediately after init");

            while not Zlib.Compress_Stream_End (Filter) loop
               declare
                  Out_Buffer : Ada.Streams.Stream_Element_Array (1 .. 1);
               begin
                  if Next_Input <= Input_Data'Last then
                     Zlib.Compress
                       (Filter,
                        Input_Data (Next_Input .. Input_Data'Last),
                        In_Last,
                        Out_Buffer,
                        Out_Last,
                        Zlib.Finish);
                     if In_Last >= Next_Input then
                        Next_Input := In_Last + 1;
                     end if;
                  else
                     Zlib.Compress_Flush (Filter, Out_Buffer, Out_Last, Zlib.Finish);
                  end if;

                  Final_Count := Produced (Out_Buffer, Out_Last);
                  Append_Output (Output, Out_Buffer, Out_Last);
                  Calls := Calls + 1;
                  Assert (Calls < 100_000, Header_Name (Header) & " finish drain must terminate");
               end;
            end loop;

            Assert
              (Final_Count > 0,
               Header_Name (Header) & " stream end becomes true only on an output-draining call");

            declare
               Out_Buffer : Ada.Streams.Stream_Element_Array (1 .. 1);
            begin
               Zlib.Compress_Flush (Filter, Out_Buffer, Out_Last, Zlib.Finish);
               Assert
                 (Produced (Out_Buffer, Out_Last) = 0,
                  Header_Name (Header) & " extra Finish after stream end emits no further bytes");
            end;

            Zlib.Compress_Close (Filter);

            declare
               Encoded : constant Zlib.Byte_Array := To_Bytes (Output);
               Decoded : constant Zlib.Byte_Array :=
                 Zlib.Inflate_With_Header (Encoded, Inflate_Header (Header), Status);
            begin
               Assert (Status = Zlib.Ok, Header_Name (Header) & " drained output inflates");
               Assert_Same
                 (Decoded,
                  Payload,
                  Header_Name (Header) & " stream-end-drained payload");
            end;
         end;
      end loop;
   end Test_Stream_End_Only_After_Output_Drained;

   procedure Test_Close_Finish_Cleanup_Matrix
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Compression_Filter_Type;
      Input    : constant Ada.Streams.Stream_Element_Array (1 .. 1) := [1 => 1];
      Output   : Ada.Streams.Stream_Element_Array (1 .. 1);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Raised   : Boolean;
   begin
      for Mode of Supported_Modes loop
         Zlib.Deflate_Init (Filter, Header => Zlib.Raw_Deflate, Mode => Mode);
         Raised := False;
         begin
            Zlib.Compress (Filter, Input, In_Last, Output, Out_Last);
         exception
            when Zlib.Zlib_Error =>
               Raised := True;
         end;
         Assert
           (not Raised,
            "Raw_Deflate compression succeeds deterministically for " & Mode_Name (Mode));
         Zlib.Compress_Close (Filter, Ignore_Error => True);
         Assert (not Zlib.Is_Open (Filter), "Ignore_Error cleanup closes failed filter");
      end loop;

      Zlib.Deflate_Init (Filter, Header => Zlib.Raw_Deflate, Mode => Zlib.Auto);
      Raised := False;
      begin
         Zlib.Compress_Flush (Filter, Output, Out_Last, Zlib.Finish);
      exception
         when Zlib.Zlib_Error =>
            Raised := True;
      end;
      Assert (not Raised, "Raw_Deflate Auto compression flush succeeds deterministically");
      Zlib.Compress_Close (Filter, Ignore_Error => True);
      Assert (not Zlib.Is_Open (Filter), "Close after raw Auto Compress_Flush clears state");

      Zlib.Deflate_Init (Filter, Header => Zlib.Raw_Deflate, Mode => Zlib.Auto);
      Raised := False;
      begin
         Zlib.Compress (Filter, Input, In_Last, Output, Out_Last, Zlib.No_Flush);
      exception
         when Zlib.Zlib_Error =>
            Raised := True;
      end;
      Assert (not Raised, "raw Auto Compress setup succeeds before reset");
      Zlib.Deflate_Init (Filter, Header => Zlib.Zlib_Header, Mode => Zlib.Stored);
      Assert (Zlib.Is_Open (Filter), "Deflate_Init resets state after active raw Auto setup");
      Zlib.Compress_Close (Filter, Ignore_Error => True);

      Zlib.Deflate_Init (Filter, Header => Zlib.Zlib_Header, Mode => Zlib.Stored);
      Raised := False;
      begin
         Zlib.Compress_Close (Filter);
      exception
         when Zlib.Zlib_Error =>
            Raised := True;
      end;
      Assert (Raised, "Close before Finish reports deterministic Zlib_Error");
      Assert (not Zlib.Is_Open (Filter), "Close before Finish clears state");

      Zlib.Deflate_Init (Filter, Header => Zlib.GZip, Mode => Zlib.Auto);
      Zlib.Compress (Filter, Input, In_Last, Output, Out_Last, Zlib.Finish);
      while not Zlib.Compress_Stream_End (Filter) loop
         Zlib.Compress_Flush (Filter, Output, Out_Last, Zlib.Finish);
      end loop;
      Zlib.Compress_Close (Filter);
      Assert (not Zlib.Is_Open (Filter), "completed filter closes normally");

      Zlib.Deflate_Init (Filter, Header => Zlib.Zlib_Header, Mode => Zlib.Dynamic);
      Assert (Zlib.Is_Open (Filter), "Deflate_Init resets after completion/close");
      Zlib.Compress_Close (Filter, Ignore_Error => True);
   end Test_Close_Finish_Cleanup_Matrix;

   procedure Test_Public_Api_External_Style_Compression_Contract
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Payload : constant Zlib.Byte_Array := [1 => 1, 2 => 2, 3 => 3, 4 => 4];
      Status  : Zlib.Status_Code;
      F       : Zlib.Filter_Type;
      CF      : Zlib.Compression_Filter_Type;
      In_Data : constant Ada.Streams.Stream_Element_Array := To_Stream (Payload);
      Out_Data     : Ada.Streams.Stream_Element_Array (1 .. 128);
      In_Last : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
   begin
      declare
         Zout : constant Zlib.Byte_Array := Zlib.Deflate (Payload, Zlib.Auto, Status);
      begin
         Assert (Status = Zlib.Ok, "external-style Deflate visible");
         Assert_Same (Zlib.Inflate (Zout, Status), Payload, "external-style Inflate visible");
         Assert (Status = Zlib.Ok, "external-style Inflate status visible");
      end;

      declare
         Gout : constant Zlib.Byte_Array := Zlib.GZip (Payload, Zlib.Auto, Status);
      begin
         Assert (Status = Zlib.Ok, "external-style GZip visible");
         Assert_Same
           (Zlib.Inflate_With_Header (Gout, Zlib.GZip, Status),
            Payload,
            "external-style Inflate_With_Header GZip visible");
         Assert (Status = Zlib.Ok, "external-style Inflate_With_Header status visible");
      end;

      Zlib.Inflate_Init (F, Header => Zlib.Raw_Deflate);
      Assert (Zlib.Is_Open (F), "external-style streaming inflate types visible");
      Zlib.Close (F, Ignore_Error => True);

      Zlib.Deflate_Init (CF, Header => Zlib.GZip, Mode => Zlib.Auto);
      Zlib.Compress (CF, In_Data, In_Last, Out_Data, Out_Last, Zlib.No_Flush);
      while not Zlib.Compress_Stream_End (CF) loop
         Zlib.Compress_Flush (CF, Out_Data, Out_Last, Zlib.Finish);
      end loop;
      Zlib.Compress_Close (CF);

      Assert (Zlib.Status_Image (Zlib.Ok) = "ok", "Status_Image visible through root package");
   end Test_Public_Api_External_Style_Compression_Contract;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_Large_Payload_Matrix'Access,
         "large payload zlib/gzip stored/fixed/dynamic/auto roundtrips");
      Registration.Register_Routine
        (T, Test_Many_Chunk_Tiny_Buffer_Matrix'Access,
         "many chunks and one-byte buffers across supported compression modes");
      Registration.Register_Routine
        (T, Test_Deterministic_Repeated_Runs'Access,
         "streaming compression output is byte-for-byte deterministic");
      Registration.Register_Routine
        (T, Test_Cross_Api_Semantic_Equivalence'Access,
         "one-shot and streaming compression are semantically equivalent");
      Registration.Register_Routine
        (T, Test_Trailers_Split_And_Endian'Access,
         "zlib and gzip trailers split across one-byte output calls validate endian/checksum contracts");
      Registration.Register_Routine
        (T, Test_Wrapper_Strictness_Final'Access,
         "wrong-wrapper output is rejected without auto-detection");
      Registration.Register_Routine
        (T, Test_Stream_End_Only_After_Output_Drained'Access,
         "Compress_Stream_End becomes true only after final output is drained");
      Registration.Register_Routine
        (T, Test_Close_Finish_Cleanup_Matrix'Access,
         "compression Close/Finish cleanup matrix is deterministic");
      Registration.Register_Routine
        (T, Test_Public_Api_External_Style_Compression_Contract'Access,
         "external-style public Zlib API compression contract uses root package only");
   end Register_Tests;
end Zlib_Streaming_Compression_Release_Tests;
