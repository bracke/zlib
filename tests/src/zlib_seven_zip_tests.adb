with Ada.Directories;
with Ada.Calendar;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with GNAT.OS_Lib;
with Interfaces;
with Zlib;
with Zlib.Seven_Zip_Filters;

package body Zlib_Seven_Zip_Tests is
   package US renames Ada.Strings.Unbounded;

   use type Ada.Directories.File_Kind;
   use type Ada.Calendar.Time;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;
   use type Zlib.Byte;
   use type Zlib.Byte_Array;
   use type Zlib.Status_Code;

   Payload : constant Zlib.Byte_Array :=
     [16#73#, 16#65#, 16#76#, 16#65#, 16#6E#, 16#2D#, 16#7A#, 16#69#, 16#70#];

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib native 7z container");
   end Name;

   function U32_LE
     (Data : Zlib.Byte_Array;
      Pos  : Natural) return Interfaces.Unsigned_32
   is
   begin
      return Interfaces.Unsigned_32 (Data (Pos))
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (Pos + 1)), 8)
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (Pos + 2)), 16)
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (Pos + 3)), 24);
   end U32_LE;

   procedure Set_U32_LE
     (Data  : in out Zlib.Byte_Array;
      Pos   : Natural;
      Value : Interfaces.Unsigned_32)
   is
   begin
      Data (Pos) := Zlib.Byte (Value and 16#FF#);
      Data (Pos + 1) :=
        Zlib.Byte (Interfaces.Shift_Right (Value, 8) and 16#FF#);
      Data (Pos + 2) :=
        Zlib.Byte (Interfaces.Shift_Right (Value, 16) and 16#FF#);
      Data (Pos + 3) :=
        Zlib.Byte (Interfaces.Shift_Right (Value, 24) and 16#FF#);
   end Set_U32_LE;

   function U64_LE
     (Data : Zlib.Byte_Array;
      Pos  : Natural) return Interfaces.Unsigned_64
   is
      Result : Interfaces.Unsigned_64 := 0;
   begin
      for I in 0 .. 7 loop
         Result :=
           Result
           or Interfaces.Shift_Left
             (Interfaces.Unsigned_64 (Data (Pos + I)), 8 * I);
      end loop;
      return Result;
   end U64_LE;

   procedure Set_U64_LE
     (Data  : in out Zlib.Byte_Array;
      Pos   : Natural;
      Value : Interfaces.Unsigned_64)
   is
   begin
      for I in 0 .. 7 loop
         Data (Pos + I) :=
           Zlib.Byte (Interfaces.Shift_Right (Value, 8 * I) and 16#FF#);
      end loop;
   end Set_U64_LE;

   function Seven_Zip_Header_First (Archive : Zlib.Byte_Array) return Natural is
   begin
      return Archive'First + 32 + Natural (U64_LE (Archive, Archive'First + 12));
   end Seven_Zip_Header_First;

   function Remove_Seven_Zip_Header_Bytes
     (Archive : Zlib.Byte_Array;
      First   : Natural;
      Count   : Natural) return Zlib.Byte_Array
   is
      Header_First : constant Natural := Seven_Zip_Header_First (Archive);
      Result       : Zlib.Byte_Array (Archive'First .. Archive'Last - Count);
      Out_Pos      : Natural := Result'First;
   begin
      Assert
        (First >= Header_First
         and then Count > 0
         and then First + Count - 1 <= Archive'Last,
         "header byte removal range is inside next header");

      for Pos in Archive'Range loop
         if Pos < First or else Pos > First + Count - 1 then
            Result (Out_Pos) := Archive (Pos);
            Out_Pos := Out_Pos + 1;
         end if;
      end loop;

      Set_U64_LE
        (Result, Result'First + 20,
         Interfaces.Unsigned_64 (Result'Last - Header_First + 1));
      Set_U32_LE
        (Result, Result'First + 28,
         Zlib.CRC32 (Result (Header_First .. Result'Last)));
      Set_U32_LE
        (Result, Result'First + 8,
         Zlib.CRC32 (Result (Result'First + 12 .. Result'First + 31)));

      return Result;
   end Remove_Seven_Zip_Header_Bytes;

   procedure Refresh_Seven_Zip_Header_CRCs
     (Archive : in out Zlib.Byte_Array)
   is
      Header_First : constant Natural := Seven_Zip_Header_First (Archive);
   begin
      Set_U64_LE
        (Archive, Archive'First + 20,
         Interfaces.Unsigned_64 (Archive'Last - Header_First + 1));
      Set_U32_LE
        (Archive, Archive'First + 28,
         Zlib.CRC32 (Archive (Header_First .. Archive'Last)));
      Set_U32_LE
        (Archive, Archive'First + 8,
         Zlib.CRC32 (Archive (Archive'First + 12 .. Archive'First + 31)));
   end Refresh_Seven_Zip_Header_CRCs;

   function Insert_Seven_Zip_Header_Bytes
     (Archive : Zlib.Byte_Array;
      Before  : Natural;
      Extra   : Zlib.Byte_Array) return Zlib.Byte_Array
   is
      Header_First : constant Natural := Seven_Zip_Header_First (Archive);
      Result       : Zlib.Byte_Array
        (Archive'First .. Archive'Last + Extra'Length);
      Out_Pos      : Natural := Result'First;
   begin
      Assert
        (Before >= Header_First and then Before <= Archive'Last + 1,
         "header byte insertion range is inside next header");

      for Pos in Archive'First .. Before - 1 loop
         Result (Out_Pos) := Archive (Pos);
         Out_Pos := Out_Pos + 1;
      end loop;

      for B of Extra loop
         Result (Out_Pos) := B;
         Out_Pos := Out_Pos + 1;
      end loop;

      for Pos in Before .. Archive'Last loop
         Result (Out_Pos) := Archive (Pos);
         Out_Pos := Out_Pos + 1;
      end loop;

      Refresh_Seven_Zip_Header_CRCs (Result);
      return Result;
   end Insert_Seven_Zip_Header_Bytes;

   function Find_Seven_Zip_CRC_Property
     (Archive : Zlib.Byte_Array;
      Start   : Natural) return Natural
   is
   begin
      for Pos in Start .. Archive'Last - 5 loop
         if Archive (Pos) = 16#0A# and then Archive (Pos + 1) = 1 then
            return Pos;
         end if;
      end loop;

      return 0;
   end Find_Seven_Zip_CRC_Property;

   function Find_Seven_Zip_Files_Info
     (Archive : Zlib.Byte_Array) return Natural
   is
      Header_First : constant Natural := Seven_Zip_Header_First (Archive);
   begin
      for Pos in Header_First .. Archive'Last - 2 loop
         if Archive (Pos) = 16#05#
           and then Archive (Pos + 1) = 1
           and then Archive (Pos + 2) = 16#11#
         then
            return Pos;
         end if;
      end loop;

      return 0;
   end Find_Seven_Zip_Files_Info;

   type Solid_Archive_Method is
     (Solid_Copy_Method, Solid_Deflate_Method, Solid_BZip2_Method,
      Solid_LZMA_Method, Solid_LZMA2_Method, Solid_Delta_Method,
      Solid_Delta_Deflate_Method, Solid_BCJ_Delta_Deflate_Method,
      Solid_Copy_Deflate_Method, Solid_BCJ_Copy_Method);

   function Seven_Zip_Solid_Substream_Archive
     (First_Name  : String;
      First_Data  : Zlib.Byte_Array;
      Second_Name : String;
      Second_Data : Zlib.Byte_Array;
      Method      : Solid_Archive_Method := Solid_Copy_Method)
      return Zlib.Byte_Array
   is
      Buffer       : Zlib.Byte_Array (1 .. 512) := [others => 0];
      Pos          : Natural := Buffer'First;
      Plain        : constant Zlib.Byte_Array := First_Data & Second_Data;
      Compress_Status : Zlib.Status_Code := Zlib.Ok;

      function Payload_From_Single_Stream_Archive
        (Archive : Zlib.Byte_Array) return Zlib.Byte_Array
      is
         Payload_First  : constant Natural := Archive'First + 32;
         Payload_Length : constant Natural :=
           Natural (U64_LE (Archive, Archive'First + 12));
      begin
         return Archive
           (Payload_First .. Payload_First + Payload_Length - 1);
      end Payload_From_Single_Stream_Archive;

      function Delta_Encode (Input : Zlib.Byte_Array) return Zlib.Byte_Array is
         Output : Zlib.Byte_Array (1 .. Input'Length);
      begin
         for Offset in 0 .. Input'Length - 1 loop
            declare
               Current  : constant Natural :=
                 Natural (Input (Input'First + Offset));
               Previous : constant Natural :=
                 (if Offset = 0
                  then 0
                  else Natural (Input (Input'First + Offset - 1)));
            begin
               Output (Output'First + Offset) :=
                 Zlib.Byte ((Current + 256 - Previous) mod 256);
            end;
         end loop;

         return Output;
      end Delta_Encode;

      function BCJ_X86_Encode (Input : Zlib.Byte_Array) return Zlib.Byte_Array
      is
      begin
         --  Masked x86 BCJ encode, matching the crate's decoder and stock 7z.
         return Zlib.Seven_Zip_Filters.Branch_Convert
           (Zlib.Seven_Zip_Filters.X86, Input, Encoding => True);
      end BCJ_X86_Encode;

      function Build_Payload return Zlib.Byte_Array is
      begin
         case Method is
            when Solid_Copy_Method =>
               return Plain;

            when Solid_Deflate_Method =>
               return Zlib.Deflate_Raw (Plain, Zlib.Fixed, Compress_Status);

            when Solid_BZip2_Method =>
               declare
                  Archive : constant Zlib.Byte_Array :=
                    Zlib.Seven_Zip_BZip2 (Plain, "solid.bin", Compress_Status);
               begin
                  if Compress_Status /= Zlib.Ok then
                     return [];
                  end if;

                  return Payload_From_Single_Stream_Archive (Archive);
               end;

            when Solid_LZMA_Method =>
               declare
                  Archive : constant Zlib.Byte_Array :=
                    Zlib.Seven_Zip_LZMA (Plain, "solid.bin", Compress_Status);
               begin
                  if Compress_Status /= Zlib.Ok then
                     return [];
                  end if;

                  return Payload_From_Single_Stream_Archive (Archive);
               end;

            when Solid_LZMA2_Method =>
               return
                 [16#01#,
                  Zlib.Byte ((Plain'Length - 1) / 256),
                  Zlib.Byte ((Plain'Length - 1) mod 256)]
                 & Plain & [1 => 0];

            when Solid_Delta_Method =>
               return Delta_Encode (Plain);

            when Solid_Delta_Deflate_Method =>
               return
                 Zlib.Deflate_Raw
                   (Delta_Encode (Plain), Zlib.Fixed, Compress_Status);

            when Solid_BCJ_Delta_Deflate_Method =>
               return
                 Zlib.Deflate_Raw
                   (Delta_Encode (BCJ_X86_Encode (Plain)), Zlib.Fixed,
                    Compress_Status);

            when Solid_Copy_Deflate_Method =>
               return Zlib.Deflate_Raw (Plain, Zlib.Fixed, Compress_Status);

            when Solid_BCJ_Copy_Method =>
               return BCJ_X86_Encode (Plain);
         end case;
      end Build_Payload;

      Payload      : constant Zlib.Byte_Array :=
        Build_Payload;
      Payload_CRC  : constant Interfaces.Unsigned_32 := Zlib.CRC32 (Payload);
      Plain_CRC    : constant Interfaces.Unsigned_32 := Zlib.CRC32 (Plain);
      First_CRC    : constant Interfaces.Unsigned_32 := Zlib.CRC32 (First_Data);
      Second_CRC   : constant Interfaces.Unsigned_32 := Zlib.CRC32 (Second_Data);
      Header_First : Natural := 0;

      procedure Put (B : Zlib.Byte) is
      begin
         Buffer (Pos) := B;
         Pos := Pos + 1;
      end Put;

      procedure Put_U32 (Value : Interfaces.Unsigned_32) is
      begin
         Set_U32_LE (Buffer, Pos, Value);
         Pos := Pos + 4;
      end Put_U32;

      procedure Put_U64 (Value : Interfaces.Unsigned_64) is
      begin
         Set_U64_LE (Buffer, Pos, Value);
         Pos := Pos + 8;
      end Put_U64;

      procedure Put_Number (Value : Natural) is
      begin
         Assert (Value < 128, "solid fixture uses short 7z number encoding");
         Put (Zlib.Byte (Value));
      end Put_Number;

      procedure Put_Coder is
      begin
         case Method is
            when Solid_Copy_Method =>
               Put (1);
               Put (0);

            when Solid_Deflate_Method =>
               Put (3);
               Put (16#04#);
               Put (16#01#);
               Put (16#08#);

            when Solid_BZip2_Method =>
               Put (3);
               Put (16#04#);
               Put (16#02#);
               Put (16#02#);

            when Solid_LZMA_Method =>
               Put (16#23#);
               Put (16#03#);
               Put (16#01#);
               Put (16#01#);
               Put (5);
               Put (16#5D#);
               Put (0);
               Put (0);
               Put (16#01#);
               Put (0);

            when Solid_LZMA2_Method =>
               Put (16#21#);
               Put (16#21#);
               Put (1);
               Put (16#16#);

            when Solid_Delta_Method =>
               Put (16#21#);
               Put (16#03#);
               Put (1);
               Put (0);

            when Solid_Delta_Deflate_Method =>
               Put (3);
               Put (16#04#);
               Put (16#01#);
               Put (16#08#);
               Put (16#21#);
               Put (16#03#);
               Put (1);
               Put (0);
               Put (2);
               Put (1);

            when Solid_BCJ_Delta_Deflate_Method =>
               Put (3);
               Put (16#04#);
               Put (16#01#);
               Put (16#08#);
               Put (16#21#);
               Put (16#03#);
               Put (1);
               Put (0);
               Put (4);
               Put (16#03#);
               Put (16#03#);
               Put (16#01#);
               Put (16#03#);
               Put (2);
               Put (1);
               Put (3);
               Put (2);

            when Solid_Copy_Deflate_Method =>
               Put (3);
               Put (16#04#);
               Put (16#01#);
               Put (16#08#);
               Put (1);
               Put (0);
               Put (2);
               Put (1);

            when Solid_BCJ_Copy_Method =>
               Put (1);
               Put (0);
               Put (4);
               Put (16#03#);
               Put (16#03#);
               Put (16#01#);
               Put (16#03#);
               Put (2);
               Put (1);
         end case;
      end Put_Coder;

      procedure Put_Name (Name : String) is
      begin
         for Ch of Name loop
            Put (Zlib.Byte (Character'Pos (Ch)));
            Put (0);
         end loop;
         Put (0);
         Put (0);
      end Put_Name;
   begin
      Assert
        (Compress_Status = Zlib.Ok,
         "solid fixture payload compression succeeds");

      Put (16#37#);
      Put (16#7A#);
      Put (16#BC#);
      Put (16#AF#);
      Put (16#27#);
      Put (16#1C#);
      Put (0);
      Put (4);
      Put_U32 (0);
      Put_U64 (Interfaces.Unsigned_64 (Payload'Length));
      Put_U64 (0);
      Put_U32 (0);

      for B of Payload loop
         Put (B);
      end loop;

      Header_First := Pos;
      Put (16#01#); -- Header
      Put (16#04#); -- MainStreamsInfo
      Put (16#06#); -- PackInfo
      Put (0);      -- PackPos
      Put (1);      -- NumPackStreams
      Put (16#09#); -- Size
      Put_Number (Payload'Length);
      Put (16#0A#); -- CRC
      Put (1);
      Put_U32 (Payload_CRC);
      Put (0);      -- End PackInfo
      Put (16#07#); -- UnpackInfo
      Put (16#0B#); -- Folder
      Put (1);      -- NumFolders
      Put (0);      -- Folders are inline
      Put
        (if Method = Solid_BCJ_Delta_Deflate_Method
         then 3
         elsif Method = Solid_BCJ_Copy_Method
           or else Method = Solid_Delta_Deflate_Method
           or else Method = Solid_Copy_Deflate_Method
         then 2
         else 1);   -- NumCoders
      Put_Coder;
      Put (16#0C#); -- CodersUnPackSize
      Put_Number (Plain'Length);
      if Method = Solid_BCJ_Delta_Deflate_Method then
         Put_Number (Plain'Length);
         Put_Number (Plain'Length);
      elsif Method = Solid_BCJ_Copy_Method
        or else Method = Solid_Delta_Deflate_Method
        or else Method = Solid_Copy_Deflate_Method
      then
         Put_Number (Plain'Length);
      end if;
      Put (16#0A#); -- CRC
      Put (1);
      Put_U32 (Plain_CRC);
      Put (0);      -- End UnpackInfo
      Put (16#08#); -- SubStreamsInfo
      Put (16#0D#); -- NumUnPackStream
      Put (2);
      Put (16#09#); -- Size
      Put (Zlib.Byte (First_Data'Length));
      Put (16#0A#); -- CRC
      Put (1);
      Put_U32 (First_CRC);
      Put_U32 (Second_CRC);
      Put (0);      -- End SubStreamsInfo
      Put (0);      -- End MainStreamsInfo
      Put (16#05#); -- FilesInfo
      Put (2);      -- NumFiles
      Put (16#11#); -- Name
      Put
        (Zlib.Byte
           (1 + 2 * (First_Name'Length + 1 + Second_Name'Length + 1)));
      Put (0);
      Put_Name (First_Name);
      Put_Name (Second_Name);
      Put (0);      -- End FilesInfo
      Put (0);      -- End Header

      Set_U64_LE
        (Buffer, Buffer'First + 20,
         Interfaces.Unsigned_64 (Pos - Header_First));
      Set_U32_LE
        (Buffer, Buffer'First + 28,
         Zlib.CRC32 (Buffer (Header_First .. Pos - 1)));
      Set_U32_LE
        (Buffer, Buffer'First + 8,
         Zlib.CRC32 (Buffer (Buffer'First + 12 .. Buffer'First + 31)));

      return Buffer (Buffer'First .. Pos - 1);
   end Seven_Zip_Solid_Substream_Archive;

   type BCJ2_Main_Pre_Coder is
     (BCJ2_Main_Copy, BCJ2_Main_Deflate, BCJ2_Main_BZip2,
      BCJ2_Main_LZMA, BCJ2_Main_LZMA2, BCJ2_Main_Delta, BCJ2_Main_BCJ,
      BCJ2_Main_PPMd);

   function Seven_Zip_BCJ2_Copy_Archive
     (Name : String;
      Data : Zlib.Byte_Array;
      Main_Pre_Coder : BCJ2_Main_Pre_Coder := BCJ2_Main_Copy)
      return Zlib.Byte_Array
   is
      Main_Stream : constant Zlib.Byte_Array :=
        [16#90#, 16#E8#, 16#90#, 16#E9#, 16#90#, 16#E8#, 16#90#, 16#E9#,
         16#90#, 16#E8#, 16#90#, 16#E9#, 16#90#, 16#E8#, 16#90#, 16#E9#,
         16#90#, 16#E8#, 16#90#, 16#E9#, 16#90#, 16#E8#, 16#90#, 16#E9#,
         16#90#, 16#E8#, 16#90#, 16#E9#, 16#90#, 16#E8#, 16#90#, 16#E9#,
         16#90#, 16#E8#, 16#90#, 16#E9#, 16#90#, 16#E8#, 16#90#, 16#E9#,
         16#90#, 16#E8#, 16#90#, 16#E9#, 16#90#, 16#E8#, 16#90#, 16#E9#,
         16#90#, 16#E8#, 16#90#, 16#E9#, 16#90#, 16#E8#, 16#90#, 16#E9#,
         16#20#, 16#00#, 16#00#, 16#00#,
         16#90#, 16#E8#, 16#90#, 16#E9#, 16#20#, 16#00#, 16#00#, 16#00#,
         16#90#, 16#E8#, 16#10#, 16#00#, 16#00#, 16#00#, 16#90#, 16#E9#,
         16#20#, 16#00#, 16#00#, 16#00#];
      Call_Stream : constant Zlib.Byte_Array :=
        [16#00#, 16#00#, 16#00#, 16#16#, 16#00#, 16#00#, 16#00#, 16#22#,
         16#00#, 16#00#, 16#00#, 16#2E#, 16#00#, 16#00#, 16#00#, 16#3A#,
         16#00#, 16#00#, 16#00#, 16#46#, 16#00#, 16#00#, 16#00#, 16#52#,
         16#00#, 16#00#, 16#00#, 16#5E#, 16#00#, 16#00#, 16#00#, 16#6A#,
         16#00#, 16#00#, 16#00#, 16#76#, 16#00#, 16#00#, 16#00#, 16#82#,
         16#00#, 16#00#, 16#00#, 16#8E#, 16#00#, 16#00#, 16#00#, 16#9A#,
         16#00#, 16#00#, 16#00#, 16#A6#, 16#00#, 16#00#, 16#00#, 16#B2#,
         16#00#, 16#00#, 16#00#, 16#BE#];
      Jump_Stream : constant Zlib.Byte_Array :=
        [16#00#, 16#00#, 16#00#, 16#2C#, 16#00#, 16#00#, 16#00#, 16#38#,
         16#00#, 16#00#, 16#00#, 16#44#, 16#00#, 16#00#, 16#00#, 16#50#,
         16#00#, 16#00#, 16#00#, 16#5C#, 16#00#, 16#00#, 16#00#, 16#68#,
         16#00#, 16#00#, 16#00#, 16#74#, 16#00#, 16#00#, 16#00#, 16#80#,
         16#00#, 16#00#, 16#00#, 16#8C#, 16#00#, 16#00#, 16#00#, 16#98#,
         16#00#, 16#00#, 16#00#, 16#A4#, 16#00#, 16#00#, 16#00#, 16#B0#,
         16#00#, 16#00#, 16#00#, 16#BC#];
      RC_Stream   : constant Zlib.Byte_Array :=
        [16#00#, 16#FF#, 16#FF#, 16#F8#, 16#8F#, 16#8E#, 16#C6#, 16#00#];

      function Payload_From_Single_Stream_Archive
        (Archive : Zlib.Byte_Array) return Zlib.Byte_Array
      is
         Payload_First  : constant Natural := Archive'First + 32;
         Payload_Length : constant Natural :=
           Natural (U64_LE (Archive, Archive'First + 12));
      begin
         return Archive
           (Payload_First .. Payload_First + Payload_Length - 1);
      end Payload_From_Single_Stream_Archive;

      function Delta_Encode (Input : Zlib.Byte_Array) return Zlib.Byte_Array is
         Output : Zlib.Byte_Array (1 .. Input'Length);
      begin
         for Offset in 0 .. Input'Length - 1 loop
            declare
               Current  : constant Natural :=
                 Natural (Input (Input'First + Offset));
               Previous : constant Natural :=
                 (if Offset = 0
                  then 0
                  else Natural (Input (Input'First + Offset - 1)));
            begin
               Output (Output'First + Offset) :=
                 Zlib.Byte ((Current + 256 - Previous) mod 256);
            end;
         end loop;

         return Output;
      end Delta_Encode;

      function BCJ_X86_Encode (Input : Zlib.Byte_Array) return Zlib.Byte_Array
      is
      begin
         --  Masked x86 BCJ encode, matching the crate's decoder and stock 7z.
         return Zlib.Seven_Zip_Filters.Branch_Convert
           (Zlib.Seven_Zip_Filters.X86, Input, Encoding => True);
      end BCJ_X86_Encode;

      function Packed_Main_Stream return Zlib.Byte_Array is
      begin
         case Main_Pre_Coder is
            when BCJ2_Main_Copy =>
               return Main_Stream;

            when BCJ2_Main_Deflate =>
               declare
                  Compress_Status : Zlib.Status_Code := Zlib.Ok;
                  Packed : constant Zlib.Byte_Array :=
                    Zlib.Deflate_Raw
                      (Main_Stream, Zlib.Fixed, Compress_Status);
               begin
                  Assert
                    (Compress_Status = Zlib.Ok,
                     "BCJ2 fixture Deflate pre-coder status");
                  return Packed;
               end;

            when BCJ2_Main_BZip2 =>
               declare
                  Compress_Status : Zlib.Status_Code := Zlib.Ok;
                  Archive : constant Zlib.Byte_Array :=
                    Zlib.Seven_Zip_BZip2
                      (Main_Stream, "bcj2-main.bin", Compress_Status);
               begin
                  Assert
                    (Compress_Status = Zlib.Ok,
                     "BCJ2 fixture BZip2 pre-coder status");
                  return Payload_From_Single_Stream_Archive (Archive);
               end;

            when BCJ2_Main_LZMA =>
               declare
                  Compress_Status : Zlib.Status_Code := Zlib.Ok;
                  Archive : constant Zlib.Byte_Array :=
                    Zlib.Seven_Zip_LZMA
                      (Main_Stream, "bcj2-main.bin", Compress_Status);
               begin
                  Assert
                    (Compress_Status = Zlib.Ok,
                     "BCJ2 fixture LZMA pre-coder status");
                  return Payload_From_Single_Stream_Archive (Archive);
               end;

            when BCJ2_Main_LZMA2 =>
               return
                 [16#01#,
                  Zlib.Byte ((Main_Stream'Length - 1) / 256),
                  Zlib.Byte ((Main_Stream'Length - 1) mod 256)]
                 & Main_Stream & [1 => 0];

            when BCJ2_Main_Delta =>
               return Delta_Encode (Main_Stream);

            when BCJ2_Main_BCJ =>
               return BCJ_X86_Encode (Main_Stream);

            when BCJ2_Main_PPMd =>
               declare
                  Compress_Status : Zlib.Status_Code := Zlib.Ok;
                  Archive : constant Zlib.Byte_Array :=
                    Zlib.Seven_Zip_PPMd
                      (Main_Stream, "bcj2-main.bin", Compress_Status);
               begin
                  Assert
                    (Compress_Status = Zlib.Ok,
                     "BCJ2 fixture PPMd pre-coder status");
                  return Payload_From_Single_Stream_Archive (Archive);
               end;
         end case;
      end Packed_Main_Stream;

      Packed_Main : constant Zlib.Byte_Array := Packed_Main_Stream;
      Payload     : constant Zlib.Byte_Array :=
        Packed_Main & Call_Stream & Jump_Stream & RC_Stream;
      Buffer      : Zlib.Byte_Array (1 .. 512) := [others => 0];
      Pos         : Natural := Buffer'First;
      Header_First : Natural := 0;

      procedure Put (B : Zlib.Byte) is
      begin
         Buffer (Pos) := B;
         Pos := Pos + 1;
      end Put;

      procedure Put_U32 (Value : Interfaces.Unsigned_32) is
      begin
         Set_U32_LE (Buffer, Pos, Value);
         Pos := Pos + 4;
      end Put_U32;

      procedure Put_U64 (Value : Interfaces.Unsigned_64) is
      begin
         Set_U64_LE (Buffer, Pos, Value);
         Pos := Pos + 8;
      end Put_U64;

      procedure Put_Number (Value : Natural) is
      begin
         if Value < 128 then
            Put (Zlib.Byte (Value));
         elsif Value < 16#4000# then
            Put (Zlib.Byte (16#80# + Value / 256));
            Put (Zlib.Byte (Value mod 256));
         else
            Assert (False, "BCJ2 fixture uses short 7z numbers");
         end if;
      end Put_Number;

      procedure Put_Name (Text : String) is
      begin
         for Ch of Text loop
            Put (Zlib.Byte (Character'Pos (Ch)));
            Put (0);
         end loop;
         Put (0);
         Put (0);
      end Put_Name;
   begin
      Assert (Data'Length = 192, "BCJ2 fixture data length");

      Put (16#37#); Put (16#7A#); Put (16#BC#);
      Put (16#AF#); Put (16#27#); Put (16#1C#);
      Put (0); Put (4); Put_U32 (0);
      Put_U64 (Interfaces.Unsigned_64 (Payload'Length));
      Put_U64 (0); Put_U32 (0);

      for B of Payload loop
         Put (B);
      end loop;

      Header_First := Pos;
      Put (16#01#); -- Header
      Put (16#04#); -- MainStreamsInfo
      Put (16#06#); -- PackInfo
      Put (0);      -- PackPos
      Put (4);      -- NumPackStreams
      Put (16#09#); -- Size
      Put_Number (Packed_Main'Length);
      Put_Number (Call_Stream'Length);
      Put_Number (Jump_Stream'Length);
      Put_Number (RC_Stream'Length);
      Put (0);      -- End PackInfo
      Put (16#07#); -- UnpackInfo
      Put (16#0B#); -- Folder
      Put (1);      -- NumFolders
      Put (0);      -- Folders are inline
      if Main_Pre_Coder = BCJ2_Main_Copy then
         Put (1);      -- NumCoders
         Put (16#14#); Put (16#03#); Put (16#03#); Put (16#01#); Put (16#1B#);
         Put (4); Put (1); -- NumInStreams, NumOutStreams
         Put (0); Put (1); Put (2); Put (3); -- Packed stream indices
      else
         Put (5);      -- NumCoders
         case Main_Pre_Coder is
            when BCJ2_Main_Deflate =>
               Put (16#03#); Put (16#04#); Put (16#01#); Put (16#08#);

            when BCJ2_Main_BZip2 =>
               Put (16#03#); Put (16#04#); Put (16#02#); Put (16#02#);

            when BCJ2_Main_LZMA =>
               Put (16#23#); Put (16#03#); Put (16#01#); Put (16#01#);
               Put (5); Put (16#5D#); Put (0); Put (0); Put (16#01#); Put (0);

            when BCJ2_Main_LZMA2 =>
               Put (16#21#); Put (16#21#); Put (1); Put (16#16#);

            when BCJ2_Main_Delta =>
               Put (16#21#); Put (16#03#); Put (1); Put (0);

            when BCJ2_Main_BCJ =>
               Put (4); Put (16#03#); Put (16#03#); Put (16#01#); Put (16#03#);

            when BCJ2_Main_PPMd =>
               Put (16#23#); Put (16#03#); Put (16#04#); Put (16#01#);
               Put (5); Put (6); Put (0); Put (0); Put (1); Put (0);

            when BCJ2_Main_Copy =>
               Assert (False, "BCJ2 Copy pre-coder uses single-coder fixture");
         end case;
         for I in 1 .. 3 loop
            pragma Unreferenced (I);
            Put (1); Put (0); -- Copy
         end loop;
         Put (16#14#); Put (16#03#); Put (16#03#); Put (16#01#); Put (16#1B#);
         Put (4); Put (1); -- NumInStreams, NumOutStreams
         Put (1); Put (0); -- Deflate -> Copy
         Put (2); Put (1); -- Copy -> Copy
         Put (3); Put (2); -- Copy -> Copy
         Put (4); Put (3); -- Copy -> BCJ2
         Put (0); Put (5); Put (6); Put (7); -- Packed stream indices
      end if;
      Put (16#0C#); -- CodersUnPackSize
      if Main_Pre_Coder /= BCJ2_Main_Copy then
         for I in 1 .. 4 loop
            pragma Unreferenced (I);
            Put_Number (Main_Stream'Length);
         end loop;
      end if;
      Put_Number (Data'Length);
      Put (16#0A#); Put (1); Put_U32 (Zlib.CRC32 (Data));
      Put (0);      -- End UnpackInfo
      Put (0);      -- End MainStreamsInfo
      Put (16#05#); -- FilesInfo
      Put (1);      -- NumFiles
      Put (16#11#); -- Name
      Put (Zlib.Byte (1 + 2 * (Name'Length + 1)));
      Put (0);
      Put_Name (Name);
      Put (0);      -- End FilesInfo
      Put (0);      -- End Header

      Set_U64_LE
        (Buffer, Buffer'First + 20,
         Interfaces.Unsigned_64 (Pos - Header_First));
      Set_U32_LE
        (Buffer, Buffer'First + 28,
         Zlib.CRC32 (Buffer (Header_First .. Pos - 1)));
      Set_U32_LE
        (Buffer, Buffer'First + 8,
         Zlib.CRC32 (Buffer (Buffer'First + 12 .. Buffer'First + 31)));

      return Buffer (Buffer'First .. Pos - 1);
   end Seven_Zip_BCJ2_Copy_Archive;

   function Seven_Zip_PPMd_Archive return Zlib.Byte_Array is
   begin
      return
        [16#37#, 16#7A#, 16#BC#, 16#AF#, 16#27#, 16#1C#, 16#00#, 16#04#,
         16#15#, 16#C0#, 16#5A#, 16#91#, 16#1E#, 16#00#, 16#00#, 16#00#,
         16#00#, 16#00#, 16#00#, 16#00#, 16#5A#, 16#00#, 16#00#, 16#00#,
         16#00#, 16#00#, 16#00#, 16#00#, 16#45#, 16#63#, 16#77#, 16#EB#,
         16#00#, 16#72#, 16#F0#, 16#97#, 16#D4#, 16#DC#, 16#1B#, 16#1B#,
         16#24#, 16#82#, 16#93#, 16#6D#, 16#01#, 16#22#, 16#44#, 16#8E#,
         16#08#, 16#4D#, 16#EB#, 16#ED#, 16#63#, 16#F7#, 16#AE#, 16#3C#,
         16#43#, 16#C6#, 16#38#, 16#24#, 16#D7#, 16#00#, 16#01#, 16#04#,
         16#06#, 16#00#, 16#01#, 16#09#, 16#1E#, 16#00#, 16#07#, 16#0B#,
         16#01#, 16#00#, 16#01#, 16#23#, 16#03#, 16#04#, 16#01#, 16#05#,
         16#04#, 16#00#, 16#00#, 16#01#, 16#00#, 16#0C#, 16#1D#, 16#00#,
         16#08#, 16#0A#, 16#01#, 16#D9#, 16#CA#, 16#DE#, 16#71#, 16#00#,
         16#00#, 16#05#, 16#01#, 16#19#, 16#06#, 16#00#, 16#00#, 16#00#,
         16#00#, 16#00#, 16#00#, 16#11#, 16#15#, 16#00#, 16#69#, 16#00#,
         16#6E#, 16#00#, 16#70#, 16#00#, 16#75#, 16#00#, 16#74#, 16#00#,
         16#2E#, 16#00#, 16#74#, 16#00#, 16#78#, 16#00#, 16#74#, 16#00#,
         16#00#, 16#00#, 16#14#, 16#0A#, 16#01#, 16#00#, 16#0C#, 16#E2#,
         16#A4#, 16#51#, 16#3B#, 16#FF#, 16#DC#, 16#01#, 16#15#, 16#06#,
         16#01#, 16#00#, 16#20#, 16#80#, 16#B4#, 16#81#, 16#00#, 16#00#];
   end Seven_Zip_PPMd_Archive;

   function Seven_Zip_PPMd_Props_Pos
     (Archive : Zlib.Byte_Array) return Natural
   is
   begin
      for Pos in Archive'First .. Archive'Last - 9 loop
         if Archive (Pos) = 16#23#
           and then Archive (Pos + 1) = 16#03#
           and then Archive (Pos + 2) = 16#04#
           and then Archive (Pos + 3) = 16#01#
           and then Archive (Pos + 4) = 5
         then
            return Pos + 5;
         end if;
      end loop;

      return 0;
   end Seven_Zip_PPMd_Props_Pos;

   function Mutate_Seven_Zip_PPMd_Props
     (Order  : Zlib.Byte;
      Memory : Interfaces.Unsigned_32) return Zlib.Byte_Array
   is
      Archive  : Zlib.Byte_Array := Seven_Zip_PPMd_Archive;
      Prop_Pos : constant Natural := Seven_Zip_PPMd_Props_Pos (Archive);
   begin
      Assert (Prop_Pos /= 0, "PPMd properties are present in test archive");
      Archive (Prop_Pos) := Order;
      Set_U32_LE (Archive, Prop_Pos + 1, Memory);
      Refresh_Seven_Zip_Header_CRCs (Archive);
      return Archive;
   end Mutate_Seven_Zip_PPMd_Props;

   function Mutate_Seven_Zip_PPMd_Range_Header
     (Prefix : Zlib.Byte_Array) return Zlib.Byte_Array
   is
      Archive       : Zlib.Byte_Array := Seven_Zip_PPMd_Archive;
      Header_First  : constant Natural := Seven_Zip_Header_First (Archive);
      Payload_First : constant Natural := Archive'First + 32;
      Payload_Last  : constant Natural := Header_First - 1;
      Pack_CRC_Pos  : Natural := 0;
   begin
      Assert
        (Prefix'Length <= Payload_Last - Payload_First + 1,
         "PPMd range prefix mutation fits packed payload");

      for Offset in 0 .. Prefix'Length - 1 loop
         Archive (Payload_First + Offset) := Prefix (Prefix'First + Offset);
      end loop;

      Pack_CRC_Pos := Find_Seven_Zip_CRC_Property (Archive, Header_First);
      Assert (Pack_CRC_Pos /= 0, "PPMd packed CRC property is present");
      Set_U32_LE
        (Archive, Pack_CRC_Pos + 2,
         Zlib.CRC32 (Archive (Payload_First .. Payload_Last)));
      Refresh_Seven_Zip_Header_CRCs (Archive);
      return Archive;
   end Mutate_Seven_Zip_PPMd_Range_Header;

   function Seven_Zip_PPMd_Dash_Entry_Archive return Zlib.Byte_Array
   is
      Archive  : Zlib.Byte_Array := Seven_Zip_PPMd_Archive;
      Name_Pos : Natural := 0;
   begin
      for Pos in Archive'First .. Archive'Last - 17 loop
         if Archive (Pos) = Character'Pos ('i')
           and then Archive (Pos + 1) = 0
           and then Archive (Pos + 2) = Character'Pos ('n')
           and then Archive (Pos + 3) = 0
           and then Archive (Pos + 4) = Character'Pos ('p')
           and then Archive (Pos + 5) = 0
           and then Archive (Pos + 6) = Character'Pos ('u')
           and then Archive (Pos + 7) = 0
           and then Archive (Pos + 8) = Character'Pos ('t')
           and then Archive (Pos + 9) = 0
           and then Archive (Pos + 10) = Character'Pos ('.')
           and then Archive (Pos + 11) = 0
           and then Archive (Pos + 12) = Character'Pos ('t')
           and then Archive (Pos + 13) = 0
           and then Archive (Pos + 14) = Character'Pos ('x')
           and then Archive (Pos + 15) = 0
           and then Archive (Pos + 16) = Character'Pos ('t')
           and then Archive (Pos + 17) = 0
         then
            Name_Pos := Pos;
            exit;
         end if;
      end loop;

      Assert (Name_Pos /= 0, "PPMd entry name is present in test archive");
      Archive (Name_Pos) := Character'Pos ('-');
      Refresh_Seven_Zip_Header_CRCs (Archive);
      return Archive;
   end Seven_Zip_PPMd_Dash_Entry_Archive;

   function Seven_Zip_Empty_PPMd_Archive return Zlib.Byte_Array is
      Empty     : constant Zlib.Byte_Array (1 .. 0) := [others => 0];
      Status    : Zlib.Status_Code := Zlib.Ok;
      Archive   : Zlib.Byte_Array :=
        Zlib.Seven_Zip_Stored (Empty, "empty.bin", Status);
      Coder_Pos : Natural := 0;
   begin
      Assert (Status = Zlib.Ok, "empty Copy 7z fixture creation status");

      for Pos in Seven_Zip_Header_First (Archive) .. Archive'Last - 6 loop
         if Archive (Pos) = 16#0B#
           and then Archive (Pos + 1) = 1
           and then Archive (Pos + 2) = 0
           and then Archive (Pos + 3) = 1
           and then Archive (Pos + 4) = 1
           and then Archive (Pos + 5) = 0
           and then Archive (Pos + 6) = 16#0C#
         then
            Coder_Pos := Pos + 4;
            exit;
         end if;
      end loop;

      Assert (Coder_Pos /= 0, "Copy coder is present in empty 7z fixture");
      Archive (Coder_Pos) := 16#23#;
      Archive (Coder_Pos + 1) := 16#03#;
      return Insert_Seven_Zip_Header_Bytes
        (Archive, Coder_Pos + 2,
         [16#04#, 16#01#, 5, 4, 0, 0, 1, 0]);
   end Seven_Zip_Empty_PPMd_Archive;

   function Seven_Zip_Empty_PPMd_With_Range_Header return Zlib.Byte_Array is
      Base         : constant Zlib.Byte_Array := Seven_Zip_Empty_PPMd_Archive;
      Header_First : constant Natural := Seven_Zip_Header_First (Base);
      Result       : Zlib.Byte_Array (Base'First .. Base'Last + 5);
      Out_Pos      : Natural := Result'First;
      Size_Pos     : Natural := 0;
      Pack_CRC_Pos : Natural := 0;
   begin
      for Pos in Base'First .. Header_First - 1 loop
         Result (Out_Pos) := Base (Pos);
         Out_Pos := Out_Pos + 1;
      end loop;

      for J in 1 .. 5 loop
         Result (Out_Pos) := 0;
         Out_Pos := Out_Pos + 1;
      end loop;

      for Pos in Header_First .. Base'Last loop
         Result (Out_Pos) := Base (Pos);
         Out_Pos := Out_Pos + 1;
      end loop;

      Set_U64_LE (Result, Result'First + 12, 5);

      for Pos in Seven_Zip_Header_First (Result) .. Result'Last - 4 loop
         if Result (Pos) = 16#06#
           and then Result (Pos + 1) = 0
           and then Result (Pos + 2) = 1
           and then Result (Pos + 3) = 16#09#
           and then Result (Pos + 4) = 0
         then
            Size_Pos := Pos + 4;
            exit;
         end if;
      end loop;

      Assert (Size_Pos /= 0, "empty PPMd fixture exposes zero pack size");
      Result (Size_Pos) := 5;
      Pack_CRC_Pos := Find_Seven_Zip_CRC_Property
        (Result, Seven_Zip_Header_First (Result));
      Assert
        (Pack_CRC_Pos /= 0,
         "empty PPMd fixture exposes its pack CRC");
      Set_U32_LE
        (Result, Pack_CRC_Pos + 2,
         Zlib.CRC32 (Result (Result'First + 32 .. Result'First + 36)));
      Refresh_Seven_Zip_Header_CRCs (Result);
      return Result;
   end Seven_Zip_Empty_PPMd_With_Range_Header;

   function Seven_Zip_PPMd_Repeated_Archive return Zlib.Byte_Array is
   begin
      return
        [16#37#, 16#7A#, 16#BC#, 16#AF#, 16#27#, 16#1C#, 16#00#, 16#04#,
         16#D2#, 16#ED#, 16#AA#, 16#14#, 16#06#, 16#00#, 16#00#, 16#00#,
         16#00#, 16#00#, 16#00#, 16#00#, 16#6A#, 16#00#, 16#00#, 16#00#,
         16#00#, 16#00#, 16#00#, 16#00#, 16#C5#, 16#51#, 16#58#, 16#82#,
         16#00#, 16#60#, 16#FD#, 16#2C#, 16#05#, 16#40#, 16#01#, 16#04#,
         16#06#, 16#00#, 16#01#, 16#09#, 16#06#, 16#00#, 16#07#, 16#0B#,
         16#01#, 16#00#, 16#01#, 16#23#, 16#03#, 16#04#, 16#01#, 16#05#,
         16#06#, 16#00#, 16#00#, 16#01#, 16#00#, 16#0C#, 16#20#, 16#00#,
         16#08#, 16#0A#, 16#01#, 16#77#, 16#17#, 16#B1#, 16#CA#, 16#00#,
         16#00#, 16#05#, 16#01#, 16#19#, 16#06#, 16#00#, 16#00#, 16#00#,
         16#00#, 16#00#, 16#00#, 16#11#, 16#21#, 16#00#, 16#7A#, 16#00#,
         16#6C#, 16#00#, 16#69#, 16#00#, 16#62#, 16#00#, 16#2D#, 16#00#,
         16#70#, 16#00#, 16#70#, 16#00#, 16#6D#, 16#00#, 16#64#, 16#00#,
         16#2D#, 16#00#, 16#61#, 16#00#, 16#2E#, 16#00#, 16#74#, 16#00#,
         16#78#, 16#00#, 16#74#, 16#00#, 16#00#, 16#00#, 16#19#, 16#02#,
         16#00#, 16#00#, 16#14#, 16#0A#, 16#01#, 16#00#, 16#E9#, 16#F5#,
         16#F9#, 16#E0#, 16#5E#, 16#FF#, 16#DC#, 16#01#, 16#15#, 16#06#,
         16#01#, 16#00#, 16#20#, 16#80#, 16#B4#, 16#81#, 16#00#, 16#00#];
   end Seven_Zip_PPMd_Repeated_Archive;

   function Seven_Zip_Solid_PPMd_Repeated_Substream_Archive return Zlib.Byte_Array is
      Source        : constant Zlib.Byte_Array := Seven_Zip_PPMd_Repeated_Archive;
      Payload_First : constant Natural := Source'First + 32;
      Payload_Size  : constant Natural :=
        Natural (U64_LE (Source, Source'First + 12));
      Payload       : constant Zlib.Byte_Array :=
        Source (Payload_First .. Payload_First + Payload_Size - 1);
      First_Data    : constant Zlib.Byte_Array (1 .. 16) := [others => Character'Pos ('a')];
      Second_Data   : constant Zlib.Byte_Array (1 .. 16) := [others => Character'Pos ('a')];
      Plain         : constant Zlib.Byte_Array := First_Data & Second_Data;
      Buffer        : Zlib.Byte_Array (1 .. 256) := [others => 0];
      Pos           : Natural := Buffer'First;
      Header_First  : Natural := 0;

      procedure Put (B : Zlib.Byte) is
      begin
         Buffer (Pos) := B;
         Pos := Pos + 1;
      end Put;

      procedure Put_U32 (Value : Interfaces.Unsigned_32) is
      begin
         Set_U32_LE (Buffer, Pos, Value);
         Pos := Pos + 4;
      end Put_U32;

      procedure Put_U64 (Value : Interfaces.Unsigned_64) is
      begin
         Set_U64_LE (Buffer, Pos, Value);
         Pos := Pos + 8;
      end Put_U64;

      procedure Put_Name (Name : String) is
      begin
         for Ch of Name loop
            Put (Zlib.Byte (Character'Pos (Ch)));
            Put (0);
         end loop;
         Put (0);
         Put (0);
      end Put_Name;
   begin
      Put (16#37#);
      Put (16#7A#);
      Put (16#BC#);
      Put (16#AF#);
      Put (16#27#);
      Put (16#1C#);
      Put (0);
      Put (4);
      Put_U32 (0);
      Put_U64 (Interfaces.Unsigned_64 (Payload'Length));
      Put_U64 (0);
      Put_U32 (0);

      for B of Payload loop
         Put (B);
      end loop;

      Header_First := Pos;
      Put (16#01#); -- Header
      Put (16#04#); -- MainStreamsInfo
      Put (16#06#); -- PackInfo
      Put (0);      -- PackPos
      Put (1);      -- NumPackStreams
      Put (16#09#); -- Size
      Put (Zlib.Byte (Payload'Length));
      Put (16#0A#); -- CRC
      Put (1);
      Put_U32 (Zlib.CRC32 (Payload));
      Put (0);      -- End PackInfo
      Put (16#07#); -- UnpackInfo
      Put (16#0B#); -- Folder
      Put (1);      -- NumFolders
      Put (0);      -- Folders are inline
      Put (1);      -- NumCoders
      Put (16#23#);
      Put (16#03#);
      Put (16#04#);
      Put (16#01#);
      Put (5);
      Put (6);
      Put (0);
      Put (0);
      Put (1);
      Put (0);
      Put (16#0C#); -- CodersUnPackSize
      Put (Zlib.Byte (Plain'Length));
      Put (16#0A#); -- CRC
      Put (1);
      Put_U32 (Zlib.CRC32 (Plain));
      Put (0);      -- End UnpackInfo
      Put (16#08#); -- SubStreamsInfo
      Put (16#0D#); -- NumUnPackStream
      Put (2);
      Put (16#09#); -- Size
      Put (Zlib.Byte (First_Data'Length));
      Put (16#0A#); -- CRC
      Put (1);
      Put_U32 (Zlib.CRC32 (First_Data));
      Put_U32 (Zlib.CRC32 (Second_Data));
      Put (0);      -- End SubStreamsInfo
      Put (0);      -- End MainStreamsInfo
      Put (16#05#); -- FilesInfo
      Put (2);      -- NumFiles
      Put (16#11#); -- Name
      Put (43);
      Put (0);
      Put_Name ("first.txt");
      Put_Name ("second.txt");
      Put (0);      -- End FilesInfo
      Put (0);      -- End Header

      Set_U64_LE
        (Buffer, Buffer'First + 20,
         Interfaces.Unsigned_64 (Pos - Header_First));
      Set_U32_LE
        (Buffer, Buffer'First + 28,
         Zlib.CRC32 (Buffer (Header_First .. Pos - 1)));
      Set_U32_LE
        (Buffer, Buffer'First + 8,
         Zlib.CRC32 (Buffer (Buffer'First + 12 .. Buffer'First + 31)));

      return Buffer (Buffer'First .. Pos - 1);
   end Seven_Zip_Solid_PPMd_Repeated_Substream_Archive;

   function Seven_Zip_PPMd_Short_Repeated_Archive return Zlib.Byte_Array is
   begin
      return
        [16#37#, 16#7A#, 16#BC#, 16#AF#, 16#27#, 16#1C#, 16#00#, 16#04#,
         16#FC#, 16#03#, 16#B8#, 16#18#, 16#06#, 16#00#, 16#00#, 16#00#,
         16#00#, 16#00#, 16#00#, 16#00#, 16#6A#, 16#00#, 16#00#, 16#00#,
         16#00#, 16#00#, 16#00#, 16#00#, 16#1F#, 16#68#, 16#A3#, 16#81#,
         16#00#, 16#60#, 16#FD#, 16#2C#, 16#05#, 16#40#, 16#01#, 16#04#,
         16#06#, 16#00#, 16#01#, 16#09#, 16#06#, 16#00#, 16#07#, 16#0B#,
         16#01#, 16#00#, 16#01#, 16#23#, 16#03#, 16#04#, 16#01#, 16#05#,
         16#06#, 16#00#, 16#00#, 16#01#, 16#00#, 16#0C#, 16#02#, 16#00#,
         16#08#, 16#0A#, 16#01#, 16#D7#, 16#19#, 16#8A#, 16#07#, 16#00#,
         16#00#, 16#05#, 16#01#, 16#19#, 16#06#, 16#00#, 16#00#, 16#00#,
         16#00#, 16#00#, 16#00#, 16#11#, 16#25#, 16#00#, 16#7A#, 16#00#,
         16#6C#, 16#00#, 16#69#, 16#00#, 16#62#, 16#00#, 16#2D#, 16#00#,
         16#70#, 16#00#, 16#70#, 16#00#, 16#6D#, 16#00#, 16#64#, 16#00#,
         16#2D#, 16#00#, 16#61#, 16#00#, 16#61#, 16#00#, 16#32#, 16#00#,
         16#2E#, 16#00#, 16#74#, 16#00#, 16#78#, 16#00#, 16#74#, 16#00#,
         16#00#, 16#00#, 16#14#, 16#0A#, 16#01#, 16#00#, 16#EA#, 16#76#,
         16#A8#, 16#6B#, 16#63#, 16#FF#, 16#DC#, 16#01#, 16#15#, 16#06#,
         16#01#, 16#00#, 16#20#, 16#80#, 16#B4#, 16#81#, 16#00#, 16#00#];
   end Seven_Zip_PPMd_Short_Repeated_Archive;

   function Seven_Zip_PPMd_Long_Repeated_Archive return Zlib.Byte_Array is
   begin
      return
        [16#37#, 16#7A#, 16#BC#, 16#AF#, 16#27#, 16#1C#, 16#00#, 16#04#,
         16#88#, 16#A1#, 16#BE#, 16#8A#, 16#06#, 16#00#, 16#00#, 16#00#,
         16#00#, 16#00#, 16#00#, 16#00#, 16#72#, 16#00#, 16#00#, 16#00#,
         16#00#, 16#00#, 16#00#, 16#00#, 16#0B#, 16#77#, 16#7C#, 16#B4#,
         16#00#, 16#60#, 16#FD#, 16#2C#, 16#05#, 16#40#, 16#01#, 16#04#,
         16#06#, 16#00#, 16#01#, 16#09#, 16#06#, 16#00#, 16#07#, 16#0B#,
         16#01#, 16#00#, 16#01#, 16#23#, 16#03#, 16#04#, 16#01#, 16#05#,
         16#20#, 16#00#, 16#00#, 16#01#, 16#00#, 16#0C#, 16#80#, 16#BE#,
         16#00#, 16#08#, 16#0A#, 16#01#, 16#D8#, 16#87#, 16#1E#, 16#E3#,
         16#00#, 16#00#, 16#05#, 16#01#, 16#19#, 16#05#, 16#00#, 16#00#,
         16#00#, 16#00#, 16#00#, 16#11#, 16#27#, 16#00#, 16#7A#, 16#00#,
         16#6C#, 16#00#, 16#69#, 16#00#, 16#62#, 16#00#, 16#2D#, 16#00#,
         16#70#, 16#00#, 16#70#, 16#00#, 16#6D#, 16#00#, 16#64#, 16#00#,
         16#2D#, 16#00#, 16#61#, 16#00#, 16#31#, 16#00#, 16#39#, 16#00#,
         16#30#, 16#00#, 16#2E#, 16#00#, 16#74#, 16#00#, 16#78#, 16#00#,
         16#74#, 16#00#, 16#00#, 16#00#, 16#19#, 16#04#, 16#00#, 16#00#,
         16#00#, 16#00#, 16#14#, 16#0A#, 16#01#, 16#00#, 16#F5#, 16#B4#,
         16#F9#, 16#88#, 16#A6#, 16#FF#, 16#DC#, 16#01#, 16#15#, 16#06#,
         16#01#, 16#00#, 16#20#, 16#80#, 16#B4#, 16#81#, 16#00#, 16#00#];
   end Seven_Zip_PPMd_Long_Repeated_Archive;

   function Seven_Zip_PPMd_Over_Boundary_Repeated_Archive return Zlib.Byte_Array is
   begin
      return
        [16#37#, 16#7A#, 16#BC#, 16#AF#, 16#27#, 16#1C#, 16#00#, 16#04#,
         16#2E#, 16#A2#, 16#A7#, 16#DC#, 16#07#, 16#00#, 16#00#, 16#00#,
         16#00#, 16#00#, 16#00#, 16#00#, 16#72#, 16#00#, 16#00#, 16#00#,
         16#00#, 16#00#, 16#00#, 16#00#, 16#08#, 16#7B#, 16#1B#, 16#77#,
         16#00#, 16#60#, 16#FD#, 16#2C#, 16#05#, 16#40#, 16#00#, 16#01#,
         16#04#, 16#06#, 16#00#, 16#01#, 16#09#, 16#07#, 16#00#, 16#07#,
         16#0B#, 16#01#, 16#00#, 16#01#, 16#23#, 16#03#, 16#04#, 16#01#,
         16#05#, 16#20#, 16#00#, 16#00#, 16#01#, 16#00#, 16#0C#, 16#80#,
         16#BF#, 16#00#, 16#08#, 16#0A#, 16#01#, 16#22#, 16#FA#, 16#5C#,
         16#60#, 16#00#, 16#00#, 16#05#, 16#01#, 16#19#, 16#05#, 16#00#,
         16#00#, 16#00#, 16#00#, 16#00#, 16#11#, 16#27#, 16#00#, 16#7A#,
         16#00#, 16#6C#, 16#00#, 16#69#, 16#00#, 16#62#, 16#00#, 16#2D#,
         16#00#, 16#70#, 16#00#, 16#70#, 16#00#, 16#6D#, 16#00#, 16#64#,
         16#00#, 16#2D#, 16#00#, 16#61#, 16#00#, 16#31#, 16#00#, 16#39#,
         16#00#, 16#31#, 16#00#, 16#2E#, 16#00#, 16#74#, 16#00#, 16#78#,
         16#00#, 16#74#, 16#00#, 16#00#, 16#00#, 16#19#, 16#04#, 16#00#,
         16#00#, 16#00#, 16#00#, 16#14#, 16#0A#, 16#01#, 16#00#, 16#53#,
         16#9F#, 16#FA#, 16#88#, 16#A6#, 16#FF#, 16#DC#, 16#01#, 16#15#,
         16#06#, 16#01#, 16#00#, 16#20#, 16#80#, 16#B4#, 16#81#, 16#00#,
         16#00#];
   end Seven_Zip_PPMd_Over_Boundary_Repeated_Archive;

   function Seven_Zip_PPMd_Alternating_Archive return Zlib.Byte_Array is
   begin
      return
        [16#37#, 16#7A#, 16#BC#, 16#AF#, 16#27#, 16#1C#, 16#00#, 16#04#,
         16#45#, 16#5D#, 16#AD#, 16#64#, 16#09#, 16#00#, 16#00#, 16#00#,
         16#00#, 16#00#, 16#00#, 16#00#, 16#6A#, 16#00#, 16#00#, 16#00#,
         16#00#, 16#00#, 16#00#, 16#00#, 16#A8#, 16#62#, 16#D9#, 16#BC#,
         16#00#, 16#61#, 16#03#, 16#6E#, 16#0F#, 16#A7#, 16#19#, 16#40#,
         16#00#, 16#01#, 16#04#, 16#06#, 16#00#, 16#01#, 16#09#, 16#09#,
         16#00#, 16#07#, 16#0B#, 16#01#, 16#00#, 16#01#, 16#23#, 16#03#,
         16#04#, 16#01#, 16#05#, 16#06#, 16#00#, 16#00#, 16#01#, 16#00#,
         16#0C#, 16#24#, 16#00#, 16#08#, 16#0A#, 16#01#, 16#EA#, 16#16#,
         16#01#, 16#F1#, 16#00#, 16#00#, 16#05#, 16#01#, 16#19#, 16#06#,
         16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#11#, 16#25#,
         16#00#, 16#7A#, 16#00#, 16#6C#, 16#00#, 16#69#, 16#00#, 16#62#,
         16#00#, 16#2D#, 16#00#, 16#70#, 16#00#, 16#70#, 16#00#, 16#6D#,
         16#00#, 16#64#, 16#00#, 16#2D#, 16#00#, 16#61#, 16#00#, 16#62#,
         16#00#, 16#63#, 16#00#, 16#2E#, 16#00#, 16#74#, 16#00#, 16#78#,
         16#00#, 16#74#, 16#00#, 16#00#, 16#00#, 16#14#, 16#0A#, 16#01#,
         16#00#, 16#BC#, 16#C6#, 16#15#, 16#72#, 16#60#, 16#FF#, 16#DC#,
         16#01#, 16#15#, 16#06#, 16#01#, 16#00#, 16#20#, 16#80#, 16#B4#,
         16#81#, 16#00#, 16#00#];
   end Seven_Zip_PPMd_Alternating_Archive;

   function Seven_Zip_PPMd_AB_Periodic_Archive return Zlib.Byte_Array is
   begin
      return
        [16#37#, 16#7A#, 16#BC#, 16#AF#, 16#27#, 16#1C#, 16#00#, 16#04#,
         16#A0#, 16#CB#, 16#87#, 16#8F#, 16#08#, 16#00#, 16#00#, 16#00#,
         16#00#, 16#00#, 16#00#, 16#00#, 16#7A#, 16#00#, 16#00#, 16#00#,
         16#00#, 16#00#, 16#00#, 16#00#, 16#5A#, 16#7C#, 16#7F#, 16#56#,
         16#00#, 16#61#, 16#03#, 16#63#, 16#57#, 16#8E#, 16#A0#, 16#00#,
         16#01#, 16#04#, 16#06#, 16#00#, 16#01#, 16#09#, 16#08#, 16#00#,
         16#07#, 16#0B#, 16#01#, 16#00#, 16#01#, 16#23#, 16#03#, 16#04#,
         16#01#, 16#05#, 16#06#, 16#00#, 16#00#, 16#01#, 16#00#, 16#0C#,
         16#28#, 16#00#, 16#08#, 16#0A#, 16#01#, 16#13#, 16#5A#, 16#D4#,
         16#BC#, 16#00#, 16#00#, 16#05#, 16#01#, 16#19#, 16#06#, 16#00#,
         16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#11#, 16#31#, 16#00#,
         16#7A#, 16#00#, 16#6C#, 16#00#, 16#69#, 16#00#, 16#62#, 16#00#,
         16#2D#, 16#00#, 16#70#, 16#00#, 16#70#, 16#00#, 16#6D#, 16#00#,
         16#64#, 16#00#, 16#2D#, 16#00#, 16#61#, 16#00#, 16#62#, 16#00#,
         16#2D#, 16#00#, 16#72#, 16#00#, 16#65#, 16#00#, 16#70#, 16#00#,
         16#65#, 16#00#, 16#61#, 16#00#, 16#74#, 16#00#, 16#2E#, 16#00#,
         16#74#, 16#00#, 16#78#, 16#00#, 16#74#, 16#00#, 16#00#, 16#00#,
         16#19#, 16#02#, 16#00#, 16#00#, 16#14#, 16#0A#, 16#01#, 16#00#,
         16#48#, 16#DA#, 16#7B#, 16#8A#, 16#B0#, 16#01#, 16#DD#, 16#01#,
         16#15#, 16#06#, 16#01#, 16#00#, 16#20#, 16#80#, 16#B4#, 16#81#,
         16#00#, 16#00#];
   end Seven_Zip_PPMd_AB_Periodic_Archive;

   function Seven_Zip_PPMd_ABCD_Periodic_Archive return Zlib.Byte_Array is
   begin
      return
        [16#37#, 16#7A#, 16#BC#, 16#AF#, 16#27#, 16#1C#, 16#00#, 16#04#,
         16#BD#, 16#67#, 16#22#, 16#90#, 16#0A#, 16#00#, 16#00#, 16#00#,
         16#00#, 16#00#, 16#00#, 16#00#, 16#7A#, 16#00#, 16#00#, 16#00#,
         16#00#, 16#00#, 16#00#, 16#00#, 16#98#, 16#0A#, 16#75#, 16#34#,
         16#00#, 16#61#, 16#03#, 16#6E#, 16#1E#, 16#57#, 16#1C#, 16#EB#,
         16#00#, 16#00#, 16#01#, 16#04#, 16#06#, 16#00#, 16#01#, 16#09#,
         16#0A#, 16#00#, 16#07#, 16#0B#, 16#01#, 16#00#, 16#01#, 16#23#,
         16#03#, 16#04#, 16#01#, 16#05#, 16#06#, 16#00#, 16#00#, 16#01#,
         16#00#, 16#0C#, 16#28#, 16#00#, 16#08#, 16#0A#, 16#01#, 16#46#,
         16#19#, 16#58#, 16#F5#, 16#00#, 16#00#, 16#05#, 16#01#, 16#19#,
         16#06#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#11#,
         16#35#, 16#00#, 16#7A#, 16#00#, 16#6C#, 16#00#, 16#69#, 16#00#,
         16#62#, 16#00#, 16#2D#, 16#00#, 16#70#, 16#00#, 16#70#, 16#00#,
         16#6D#, 16#00#, 16#64#, 16#00#, 16#2D#, 16#00#, 16#61#, 16#00#,
         16#62#, 16#00#, 16#63#, 16#00#, 16#64#, 16#00#, 16#2D#, 16#00#,
         16#72#, 16#00#, 16#65#, 16#00#, 16#70#, 16#00#, 16#65#, 16#00#,
         16#61#, 16#00#, 16#74#, 16#00#, 16#2E#, 16#00#, 16#74#, 16#00#,
         16#78#, 16#00#, 16#74#, 16#00#, 16#00#, 16#00#, 16#14#, 16#0A#,
         16#01#, 16#00#, 16#48#, 16#DA#, 16#7B#, 16#8A#, 16#B0#, 16#01#,
         16#DD#, 16#01#, 16#15#, 16#06#, 16#01#, 16#00#, 16#20#, 16#80#,
         16#B4#, 16#81#, 16#00#, 16#00#];
   end Seven_Zip_PPMd_ABCD_Periodic_Archive;

   function Seven_Zip_PPMd_Two_Symbol_Archive return Zlib.Byte_Array is
   begin
      return
        [16#37#, 16#7A#, 16#BC#, 16#AF#, 16#27#, 16#1C#, 16#00#, 16#04#,
         16#E7#, 16#26#, 16#26#, 16#23#, 16#07#, 16#00#, 16#00#, 16#00#,
         16#00#, 16#00#, 16#00#, 16#00#, 16#6A#, 16#00#, 16#00#, 16#00#,
         16#00#, 16#00#, 16#00#, 16#00#, 16#64#, 16#11#, 16#77#, 16#3A#,
         16#00#, 16#61#, 16#03#, 16#08#, 16#BB#, 16#A4#, 16#00#, 16#01#,
         16#04#, 16#06#, 16#00#, 16#01#, 16#09#, 16#07#, 16#00#, 16#07#,
         16#0B#, 16#01#, 16#00#, 16#01#, 16#23#, 16#03#, 16#04#, 16#01#,
         16#05#, 16#06#, 16#00#, 16#00#, 16#01#, 16#00#, 16#0C#, 16#02#,
         16#00#, 16#08#, 16#0A#, 16#01#, 16#6D#, 16#48#, 16#83#, 16#9E#,
         16#00#, 16#00#, 16#05#, 16#01#, 16#19#, 16#06#, 16#00#, 16#00#,
         16#00#, 16#00#, 16#00#, 16#00#, 16#11#, 16#25#, 16#00#, 16#7A#,
         16#00#, 16#6C#, 16#00#, 16#69#, 16#00#, 16#62#, 16#00#, 16#2D#,
         16#00#, 16#70#, 16#00#, 16#70#, 16#00#, 16#6D#, 16#00#, 16#64#,
         16#00#, 16#2D#, 16#00#, 16#61#, 16#00#, 16#62#, 16#00#, 16#32#,
         16#00#, 16#2E#, 16#00#, 16#74#, 16#00#, 16#78#, 16#00#, 16#74#,
         16#00#, 16#00#, 16#00#, 16#14#, 16#0A#, 16#01#, 16#00#, 16#81#,
         16#4B#, 16#C4#, 16#FE#, 16#61#, 16#FF#, 16#DC#, 16#01#, 16#15#,
         16#06#, 16#01#, 16#00#, 16#20#, 16#80#, 16#B4#, 16#81#, 16#00#,
         16#00#];
   end Seven_Zip_PPMd_Two_Symbol_Archive;

   function Seven_Zip_PPMd_Three_Symbol_Archive return Zlib.Byte_Array is
   begin
      return
        [16#37#, 16#7A#, 16#BC#, 16#AF#, 16#27#, 16#1C#, 16#00#, 16#04#,
         16#9A#, 16#A8#, 16#EE#, 16#43#, 16#08#, 16#00#, 16#00#, 16#00#,
         16#00#, 16#00#, 16#00#, 16#00#, 16#72#, 16#00#, 16#00#, 16#00#,
         16#00#, 16#00#, 16#00#, 16#00#, 16#0B#, 16#60#, 16#89#, 16#54#,
         16#00#, 16#61#, 16#03#, 16#6D#, 16#B9#, 16#6C#, 16#2D#, 16#00#,
         16#01#, 16#04#, 16#06#, 16#00#, 16#01#, 16#09#, 16#08#, 16#00#,
         16#07#, 16#0B#, 16#01#, 16#00#, 16#01#, 16#23#, 16#03#, 16#04#,
         16#01#, 16#05#, 16#06#, 16#00#, 16#00#, 16#01#, 16#00#, 16#0C#,
         16#03#, 16#00#, 16#08#, 16#0A#, 16#01#, 16#C2#, 16#41#, 16#24#,
         16#35#, 16#00#, 16#00#, 16#05#, 16#01#, 16#19#, 16#06#, 16#00#,
         16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#11#, 16#27#, 16#00#,
         16#7A#, 16#00#, 16#6C#, 16#00#, 16#69#, 16#00#, 16#62#, 16#00#,
         16#2D#, 16#00#, 16#70#, 16#00#, 16#70#, 16#00#, 16#6D#, 16#00#,
         16#64#, 16#00#, 16#2D#, 16#00#, 16#61#, 16#00#, 16#62#, 16#00#,
         16#63#, 16#00#, 16#33#, 16#00#, 16#2E#, 16#00#, 16#74#, 16#00#,
         16#78#, 16#00#, 16#74#, 16#00#, 16#00#, 16#00#, 16#19#, 16#04#,
         16#00#, 16#00#, 16#00#, 16#00#, 16#14#, 16#0A#, 16#01#, 16#00#,
         16#A0#, 16#20#, 16#B2#, 16#07#, 16#66#, 16#FF#, 16#DC#, 16#01#,
         16#15#, 16#06#, 16#01#, 16#00#, 16#20#, 16#80#, 16#B4#, 16#81#,
         16#00#, 16#00#];
   end Seven_Zip_PPMd_Three_Symbol_Archive;

   function Seven_Zip_PPMd_Six_Symbol_Archive return Zlib.Byte_Array is
   begin
      return
        [16#37#, 16#7A#, 16#BC#, 16#AF#, 16#27#, 16#1C#, 16#00#, 16#04#,
         16#73#, 16#B9#, 16#89#, 16#37#, 16#0B#, 16#00#, 16#00#, 16#00#,
         16#00#, 16#00#, 16#00#, 16#00#, 16#72#, 16#00#, 16#00#, 16#00#,
         16#00#, 16#00#, 16#00#, 16#00#, 16#77#, 16#AE#, 16#06#, 16#3B#,
         16#00#, 16#61#, 16#03#, 16#6E#, 16#1E#, 16#69#, 16#2C#, 16#13#,
         16#A9#, 16#B4#, 16#00#, 16#01#, 16#04#, 16#06#, 16#00#, 16#01#,
         16#09#, 16#0B#, 16#00#, 16#07#, 16#0B#, 16#01#, 16#00#, 16#01#,
         16#23#, 16#03#, 16#04#, 16#01#, 16#05#, 16#06#, 16#00#, 16#00#,
         16#01#, 16#00#, 16#0C#, 16#06#, 16#00#, 16#08#, 16#0A#, 16#01#,
         16#EF#, 16#39#, 16#8E#, 16#4B#, 16#00#, 16#00#, 16#05#, 16#01#,
         16#19#, 16#06#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#,
         16#11#, 16#2D#, 16#00#, 16#7A#, 16#00#, 16#6C#, 16#00#, 16#69#,
         16#00#, 16#62#, 16#00#, 16#2D#, 16#00#, 16#70#, 16#00#, 16#70#,
         16#00#, 16#6D#, 16#00#, 16#64#, 16#00#, 16#2D#, 16#00#, 16#61#,
         16#00#, 16#62#, 16#00#, 16#63#, 16#00#, 16#64#, 16#00#, 16#65#,
         16#00#, 16#66#, 16#00#, 16#36#, 16#00#, 16#2E#, 16#00#, 16#74#,
         16#00#, 16#78#, 16#00#, 16#74#, 16#00#, 16#00#, 16#00#, 16#14#,
         16#0A#, 16#01#, 16#00#, 16#5F#, 16#FA#, 16#93#, 16#D9#, 16#66#,
         16#FF#, 16#DC#, 16#01#, 16#15#, 16#06#, 16#01#, 16#00#, 16#20#,
         16#80#, 16#B4#, 16#81#, 16#00#, 16#00#];
   end Seven_Zip_PPMd_Six_Symbol_Archive;

   function Seven_Zip_PPMd_Ten_Symbol_Archive return Zlib.Byte_Array is
   begin
      return
        [16#37#, 16#7A#, 16#BC#, 16#AF#, 16#27#, 16#1C#, 16#00#, 16#04#,
         16#71#, 16#23#, 16#BD#, 16#5B#, 16#0F#, 16#00#, 16#00#, 16#00#,
         16#00#, 16#00#, 16#00#, 16#00#, 16#7A#, 16#00#, 16#00#, 16#00#,
         16#00#, 16#00#, 16#00#, 16#00#, 16#D8#, 16#E1#, 16#FF#, 16#E7#,
         16#00#, 16#61#, 16#03#, 16#6E#, 16#1E#, 16#69#, 16#2C#, 16#6E#,
         16#0F#, 16#17#, 16#B6#, 16#EB#, 16#11#, 16#96#, 16#00#, 16#01#,
         16#04#, 16#06#, 16#00#, 16#01#, 16#09#, 16#0F#, 16#00#, 16#07#,
         16#0B#, 16#01#, 16#00#, 16#01#, 16#23#, 16#03#, 16#04#, 16#01#,
         16#05#, 16#20#, 16#00#, 16#00#, 16#01#, 16#00#, 16#0C#, 16#0A#,
         16#00#, 16#08#, 16#0A#, 16#01#, 16#3A#, 16#70#, 16#81#, 16#39#,
         16#00#, 16#00#, 16#05#, 16#01#, 16#19#, 16#06#, 16#00#, 16#00#,
         16#00#, 16#00#, 16#00#, 16#00#, 16#11#, 16#33#, 16#00#, 16#7A#,
         16#00#, 16#6C#, 16#00#, 16#69#, 16#00#, 16#62#, 16#00#, 16#2D#,
         16#00#, 16#70#, 16#00#, 16#70#, 16#00#, 16#6D#, 16#00#, 16#64#,
         16#00#, 16#2D#, 16#00#, 16#61#, 16#00#, 16#62#, 16#00#, 16#63#,
         16#00#, 16#64#, 16#00#, 16#65#, 16#00#, 16#66#, 16#00#, 16#67#,
         16#00#, 16#68#, 16#00#, 16#69#, 16#00#, 16#6A#, 16#00#, 16#2E#,
         16#00#, 16#74#, 16#00#, 16#78#, 16#00#, 16#74#, 16#00#, 16#00#,
         16#00#, 16#19#, 16#00#, 16#14#, 16#0A#, 16#01#, 16#00#, 16#17#,
         16#66#, 16#7E#, 16#1A#, 16#86#, 16#FF#, 16#DC#, 16#01#, 16#15#,
         16#06#, 16#01#, 16#00#, 16#20#, 16#80#, 16#B4#, 16#81#, 16#00#,
         16#00#];
   end Seven_Zip_PPMd_Ten_Symbol_Archive;

   function Seven_Zip_PPMd_Eleven_Symbol_Archive return Zlib.Byte_Array is
   begin
      return
        [16#37#, 16#7A#, 16#BC#, 16#AF#, 16#27#, 16#1C#, 16#00#, 16#04#,
         16#C4#, 16#54#, 16#3F#, 16#7E#, 16#10#, 16#00#, 16#00#, 16#00#,
         16#00#, 16#00#, 16#00#, 16#00#, 16#7A#, 16#00#, 16#00#, 16#00#,
         16#00#, 16#00#, 16#00#, 16#00#, 16#48#, 16#1D#, 16#22#, 16#B9#,
         16#00#, 16#61#, 16#03#, 16#6E#, 16#1E#, 16#69#, 16#2C#, 16#6E#,
         16#0F#, 16#17#, 16#B7#, 16#29#, 16#89#, 16#D4#, 16#50#, 16#00#,
         16#01#, 16#04#, 16#06#, 16#00#, 16#01#, 16#09#, 16#10#, 16#00#,
         16#07#, 16#0B#, 16#01#, 16#00#, 16#01#, 16#23#, 16#03#, 16#04#,
         16#01#, 16#05#, 16#20#, 16#00#, 16#00#, 16#01#, 16#00#, 16#0C#,
         16#0B#, 16#00#, 16#08#, 16#0A#, 16#01#, 16#9F#, 16#0F#, 16#57#,
         16#CE#, 16#00#, 16#00#, 16#05#, 16#01#, 16#19#, 16#06#, 16#00#,
         16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#11#, 16#35#, 16#00#,
         16#7A#, 16#00#, 16#6C#, 16#00#, 16#69#, 16#00#, 16#62#, 16#00#,
         16#2D#, 16#00#, 16#70#, 16#00#, 16#70#, 16#00#, 16#6D#, 16#00#,
         16#64#, 16#00#, 16#2D#, 16#00#, 16#61#, 16#00#, 16#62#, 16#00#,
         16#63#, 16#00#, 16#64#, 16#00#, 16#65#, 16#00#, 16#66#, 16#00#,
         16#67#, 16#00#, 16#68#, 16#00#, 16#69#, 16#00#, 16#6A#, 16#00#,
         16#6B#, 16#00#, 16#2E#, 16#00#, 16#74#, 16#00#, 16#78#, 16#00#,
         16#74#, 16#00#, 16#00#, 16#00#, 16#14#, 16#0A#, 16#01#, 16#00#,
         16#EA#, 16#2C#, 16#B1#, 16#F4#, 16#A8#, 16#FF#, 16#DC#, 16#01#,
         16#15#, 16#06#, 16#01#, 16#00#, 16#20#, 16#80#, 16#B4#, 16#81#,
         16#00#, 16#00#];
   end Seven_Zip_PPMd_Eleven_Symbol_Archive;

   type Encoded_Header_Method is
     (Encoded_Header_Copy, Encoded_Header_Deflate, Encoded_Header_BZip2,
      Encoded_Header_LZMA, Encoded_Header_LZMA2);

   function Seven_Zip_With_Encoded_Header
     (Archive : Zlib.Byte_Array;
      Method  : Encoded_Header_Method) return Zlib.Byte_Array
   is
      Buffer       : Zlib.Byte_Array (1 .. 2048) := [others => 0];
      Pos          : Natural := Buffer'First;
      Header_First : constant Natural := Seven_Zip_Header_First (Archive);
      Header       : constant Zlib.Byte_Array :=
        Archive (Header_First .. Archive'Last);
      Payload_Size : constant Natural := Header_First - (Archive'First + 32);
      Compress_Status : Zlib.Status_Code := Zlib.Ok;

      function Payload_From_Single_Stream_Archive
        (Encoded_Archive : Zlib.Byte_Array) return Zlib.Byte_Array
      is
         Payload_First  : constant Natural := Encoded_Archive'First + 32;
         Payload_Length : constant Natural :=
           Natural (U64_LE (Encoded_Archive, Encoded_Archive'First + 12));
      begin
         return Encoded_Archive
           (Payload_First .. Payload_First + Payload_Length - 1);
      end Payload_From_Single_Stream_Archive;

      function Build_Encoded return Zlib.Byte_Array is
      begin
         case Method is
            when Encoded_Header_Copy =>
               return Header;

            when Encoded_Header_Deflate =>
               return Zlib.Deflate_Raw (Header, Zlib.Fixed, Compress_Status);

            when Encoded_Header_BZip2 =>
               declare
                  Encoded_Archive : constant Zlib.Byte_Array :=
                    Zlib.Seven_Zip_BZip2
                      (Header, "header.bin", Compress_Status);
               begin
                  if Compress_Status /= Zlib.Ok then
                     return [];
                  end if;

                  return Payload_From_Single_Stream_Archive (Encoded_Archive);
               end;

            when Encoded_Header_LZMA =>
               declare
                  Encoded_Archive : constant Zlib.Byte_Array :=
                    Zlib.Seven_Zip_LZMA
                      (Header, "header.bin", Compress_Status);
               begin
                  if Compress_Status /= Zlib.Ok then
                     return [];
                  end if;

                  return Payload_From_Single_Stream_Archive (Encoded_Archive);
               end;

            when Encoded_Header_LZMA2 =>
               declare
                  Encoded_Archive : constant Zlib.Byte_Array :=
                    Zlib.Seven_Zip_LZMA2
                      (Header, "header.bin", Compress_Status);
               begin
                  if Compress_Status /= Zlib.Ok then
                     return [];
                  end if;

                  return Payload_From_Single_Stream_Archive (Encoded_Archive);
               end;
         end case;
      end Build_Encoded;

      Encoded      : constant Zlib.Byte_Array := Build_Encoded;
      Encoded_Info_First : Natural := 0;

      procedure Put (B : Zlib.Byte) is
      begin
         Buffer (Pos) := B;
         Pos := Pos + 1;
      end Put;

      procedure Put_U32 (Value : Interfaces.Unsigned_32) is
      begin
         Set_U32_LE (Buffer, Pos, Value);
         Pos := Pos + 4;
      end Put_U32;

      procedure Put_U64 (Value : Interfaces.Unsigned_64) is
      begin
         Set_U64_LE (Buffer, Pos, Value);
         Pos := Pos + 8;
      end Put_U64;

      procedure Put_Number (Value : Natural) is
      begin
         if Value < 128 then
            Put (Zlib.Byte (Value));
         else
            Assert
              (Value < 16#4000#,
               "encoded-header fixture uses one- or two-byte 7z numbers");
            Put (Zlib.Byte (16#80# + (Value / 256)));
            Put (Zlib.Byte (Value mod 256));
         end if;
      end Put_Number;

      procedure Put_Coder is
      begin
         case Method is
            when Encoded_Header_Copy =>
               Put (1);
               Put (0);

            when Encoded_Header_Deflate =>
               Put (3);
               Put (16#04#);
               Put (16#01#);
               Put (16#08#);

            when Encoded_Header_BZip2 =>
               Put (3);
               Put (16#04#);
               Put (16#02#);
               Put (16#02#);

            when Encoded_Header_LZMA =>
               Put (16#23#);
               Put (16#03#);
               Put (16#01#);
               Put (16#01#);
               Put (5);
               Put (16#5D#);
               Put (0);
               Put (0);
               Put (16#01#);
               Put (0);

            when Encoded_Header_LZMA2 =>
               Put (16#21#);
               Put (16#21#);
               Put (1);
               Put (16#16#);
         end case;
      end Put_Coder;
   begin
      Assert
        (Compress_Status = Zlib.Ok,
         "encoded-header fixture compression succeeds");

      Put (16#37#);
      Put (16#7A#);
      Put (16#BC#);
      Put (16#AF#);
      Put (16#27#);
      Put (16#1C#);
      Put (0);
      Put (4);
      Put_U32 (0);
      Put_U64 (Interfaces.Unsigned_64 (Payload_Size + Encoded'Length));
      Put_U64 (0);
      Put_U32 (0);

      if Payload_Size > 0 then
         for I in Archive'First + 32 .. Header_First - 1 loop
            Put (Archive (I));
         end loop;
      end if;

      for B of Encoded loop
         Put (B);
      end loop;

      Encoded_Info_First := Pos;
      Put (16#17#); -- EncodedHeader
      Put (16#04#); -- MainStreamsInfo
      Put (16#06#); -- PackInfo
      Put_Number (Payload_Size);
      Put (1);      -- NumPackStreams
      Put (16#09#); -- Size
      Put_Number (Encoded'Length);
      Put (16#0A#); -- CRC
      Put (1);
      Put_U32 (Zlib.CRC32 (Encoded));
      Put (0);      -- End PackInfo
      Put (16#07#); -- UnpackInfo
      Put (16#0B#); -- Folder
      Put (1);      -- NumFolders
      Put (0);      -- Folders inline
      Put (1);      -- NumCoders
      Put_Coder;
      Put (16#0C#); -- CodersUnPackSize
      Put_Number (Header'Length);
      Put (16#0A#); -- CRC
      Put (1);
      Put_U32 (Zlib.CRC32 (Header));
      Put (0);      -- End UnpackInfo
      Put (0);      -- End MainStreamsInfo

      Set_U64_LE
        (Buffer, Buffer'First + 20,
         Interfaces.Unsigned_64 (Pos - Encoded_Info_First));
      Set_U32_LE
        (Buffer, Buffer'First + 28,
         Zlib.CRC32 (Buffer (Encoded_Info_First .. Pos - 1)));
      Set_U32_LE
        (Buffer, Buffer'First + 8,
         Zlib.CRC32 (Buffer (Buffer'First + 12 .. Buffer'First + 31)));

      return Buffer (Buffer'First .. Pos - 1);
   end Seven_Zip_With_Encoded_Header;

   function Seven_Zip_With_Deflate_Encoded_Header
     (Archive : Zlib.Byte_Array) return Zlib.Byte_Array
   is
   begin
      return Seven_Zip_With_Encoded_Header
        (Archive, Encoded_Header_Deflate);
   end Seven_Zip_With_Deflate_Encoded_Header;

   function Base_Path (Name : String) return String is
   begin
      return Ada.Directories.Compose
        ("/tmp",
         "zlib-seven-zip-" & Name);
   end Base_Path;

   procedure Delete_If_Exists (Path : String) is
   begin
      if Ada.Directories.Exists (Path) then
         if Ada.Directories.Kind (Path) = Ada.Directories.Directory then
            Ada.Directories.Delete_Tree (Path);
         else
            Ada.Directories.Delete_File (Path);
         end if;
      end if;
   exception
      when others =>
         null;
   end Delete_If_Exists;

   procedure Write_File (Path : String; Data : Zlib.Byte_Array) is
      File : Ada.Streams.Stream_IO.File_Type;
      Raw  : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Data'Length));
   begin
      for I in Data'Range loop
         Raw (Ada.Streams.Stream_Element_Offset (I - Data'First + 1)) :=
           Ada.Streams.Stream_Element (Data (I));
      end loop;

      Ada.Streams.Stream_IO.Create
        (File, Ada.Streams.Stream_IO.Out_File, Path);
      Ada.Streams.Stream_IO.Write (File, Raw);
      Ada.Streams.Stream_IO.Close (File);
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         raise;
   end Write_File;

   function Read_File (Path : String) return Zlib.Byte_Array is
      File : Ada.Streams.Stream_IO.File_Type;
   begin
      Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Path);
      declare
         Size : constant Ada.Streams.Stream_Element_Count :=
           Ada.Streams.Stream_Element_Count
             (Ada.Streams.Stream_IO.Size (File));
         Raw  : Ada.Streams.Stream_Element_Array (1 .. Size);
         Last : Ada.Streams.Stream_Element_Offset;
      begin
         Ada.Streams.Stream_IO.Read (File, Raw, Last);
         Ada.Streams.Stream_IO.Close (File);

         declare
            Result : Zlib.Byte_Array (1 .. Natural (Last));
         begin
            for I in Result'Range loop
               Result (I) := Zlib.Byte (Raw (Ada.Streams.Stream_Element_Offset (I)));
            end loop;
            return Result;
         end;
      end;
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         raise;
   end Read_File;

   procedure Test_Stored_Header_Structure
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status  : Zlib.Status_Code := Zlib.Ok;
      Archive : constant Zlib.Byte_Array :=
        Zlib.Seven_Zip_Stored (Payload, "payload.txt", Status);
   begin
      Assert (Status = Zlib.Ok, "stored 7z creation status");
      Assert (Archive'Length > 32 + Payload'Length, "archive has headers");
      Assert
        (Archive (1 .. 6) =
           [16#37#, 16#7A#, 16#BC#, 16#AF#, 16#27#, 16#1C#],
         "7z signature");
      Assert (Archive (7) = 0 and then Archive (8) = 4, "7z version");

      declare
         Start_Header : constant Zlib.Byte_Array := Archive (13 .. 32);
         Offset       : constant Interfaces.Unsigned_64 := U64_LE (Archive, 13);
         Size         : constant Interfaces.Unsigned_64 := U64_LE (Archive, 21);
         Header_CRC   : constant Interfaces.Unsigned_32 := U32_LE (Archive, 29);
         Header_First : constant Natural := 33 + Payload'Length;
         Header_Last  : constant Natural := Archive'Last;
         Header       : constant Zlib.Byte_Array := Archive (Header_First .. Header_Last);
      begin
         Assert (Offset = Interfaces.Unsigned_64 (Payload'Length), "next header offset");
         Assert (Size = Interfaces.Unsigned_64 (Header'Length), "next header size");
         Assert (U32_LE (Archive, 9) = Zlib.CRC32 (Start_Header), "start header CRC");
         Assert (Header_CRC = Zlib.CRC32 (Header), "next header CRC");
         Assert (Header (Header'First) = 16#01#, "next header starts with kHeader");
      end;
   end Test_Stored_Header_Structure;

   procedure Test_Extract_Accepts_Known_Encoded_Header_Coders
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      procedure Check
        (Method : Encoded_Header_Method;
         Label  : String;
         Slug   : String;
         Accept_Message : String)
      is
         Status  : Zlib.Status_Code := Zlib.Ok;
         Base    : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_Stored (Payload, "payload.txt", Status);
         Archive : constant Zlib.Byte_Array :=
           Seven_Zip_With_Encoded_Header (Base, Method);
         Archive_Path : constant String :=
           Base_Path (Slug & "-encoded-header.7z");
         Output_Dir   : constant String :=
           Base_Path (Slug & "-encoded-header.out");
      begin
         Assert (Status = Zlib.Ok, Label & " encoded-header base archive creation");
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);

         declare
            Plain : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip (Archive, "payload.txt", Status);
         begin
            Assert
              (Status = Zlib.Ok, Accept_Message);
            Assert (Plain = Payload, Label & " encoded header payload");
         end;

         Write_File (Archive_Path, Archive);
         Zlib.Extract_Seven_Zip_Stored_Files
           (Archive_Path, Output_Dir,
            [1 => US.To_Unbounded_String ("payload.txt")],
            Status);
         Assert
           (Status = Zlib.Ok,
            Label & " encoded header file-list extraction status");
         Assert
           (Read_File (Ada.Directories.Compose (Output_Dir, "payload.txt")) =
              Payload,
            Label & " encoded header file-list extraction payload");

         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);
      exception
         when others =>
            Delete_If_Exists (Archive_Path);
            Delete_If_Exists (Output_Dir);
            raise;
      end Check;
   begin
      Check
        (Encoded_Header_Copy, "Copy", "copy",
         "native 7z extraction accepts Copy encoded headers");
      Check
        (Encoded_Header_Deflate, "Deflate", "deflate",
         "native 7z extraction accepts Deflate encoded headers");
      Check
        (Encoded_Header_BZip2, "BZip2", "bzip2",
         "native 7z extraction accepts BZip2 encoded headers");
      Check
        (Encoded_Header_LZMA, "LZMA", "lzma",
         "native 7z extraction accepts LZMA encoded headers");
      Check
        (Encoded_Header_LZMA2, "LZMA2", "lzma2",
         "native 7z extraction accepts LZMA2 encoded headers");
   end Test_Extract_Accepts_Known_Encoded_Header_Coders;

   procedure Test_Extract_Rejects_Bad_Encoded_Header_CRC
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Status  : Zlib.Status_Code := Zlib.Ok;
      Base    : constant Zlib.Byte_Array :=
        Zlib.Seven_Zip_Stored (Payload, "payload.txt", Status);
      Archive : Zlib.Byte_Array :=
        Seven_Zip_With_Deflate_Encoded_Header (Base);
      Header_First : constant Natural := Seven_Zip_Header_First (Archive);
      CRC_Pos      : Natural := 0;
   begin
      Assert (Status = Zlib.Ok, "bad encoded-header CRC base archive creation");

      for Pos in Header_First .. Archive'Last - 3 loop
         if U32_LE (Archive, Pos) =
           Zlib.CRC32
             (Archive
                (Archive'First + 32 + Payload'Length ..
                 Header_First - 1))
         then
            CRC_Pos := Pos;
            exit;
         end if;
      end loop;

      Assert (CRC_Pos /= 0, "encoded-header pack CRC field found");
      Archive (CRC_Pos) := Archive (CRC_Pos) xor 16#01#;
      Refresh_Seven_Zip_Header_CRCs (Archive);

      declare
         Plain : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "payload.txt", Status);
      begin
         Assert
           (Status = Zlib.Invalid_Checksum,
            "bad encoded-header pack CRC fails closed");
         Assert
           (Plain'Length = 0,
            "bad encoded-header pack CRC returns no payload");
      end;
   end Test_Extract_Rejects_Bad_Encoded_Header_CRC;

   procedure Test_Invalid_Name_Fails
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code := Zlib.Ok;
   begin
      declare
         Output : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_Stored (Payload, "", Status);
      begin
         Assert (Status = Zlib.Unsupported_Method, "empty names fail closed");
         Assert (Output'Length = 0, "empty names return no archive");
      end;

      declare
         Output : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_Stored (Payload, "bad" & ASCII.NUL & "name", Status);
      begin
         Assert (Status = Zlib.Unsupported_Method, "NUL names fail closed");
         Assert (Output'Length = 0, "NUL names return no archive");
      end;
   end Test_Invalid_Name_Fails;

   procedure Test_Stored_Roundtrip_Native
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code := Zlib.Ok;
   begin
      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_Stored (Payload, "payload.txt", Status);
      begin
         Assert (Status = Zlib.Ok, "native stored 7z creation before extract");
         declare
            Plain : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip_Stored (Archive, "payload.txt", Status);
         begin
            Assert (Status = Zlib.Ok, "native stored 7z extract status");
            Assert (Plain = Payload, "native stored 7z roundtrip payload");
         end;
      end;
   end Test_Stored_Roundtrip_Native;

   procedure Test_Deflate_Roundtrip_Native
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code := Zlib.Ok;
      Input  : constant Zlib.Byte_Array :=
        [1 .. 256 => 16#41#];
   begin
      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_Deflate (Input, "payload.txt", Zlib.Dynamic, Status);
      begin
         Assert (Status = Zlib.Ok, "native Deflate 7z creation before extract");
         Assert
           (Archive'Length < Input'Length,
            "native Deflate 7z archive should compress repeated payload");
         declare
            Plain : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip_Stored (Archive, "payload.txt", Status);
         begin
            Assert (Status = Zlib.Ok, "native Deflate 7z extract status");
            Assert (Plain = Input, "native Deflate 7z roundtrip payload");
         end;
      end;
   end Test_Deflate_Roundtrip_Native;

   procedure Test_Deflate_Level_Roundtrip_Native
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code := Zlib.Ok;
      Input  : constant Zlib.Byte_Array :=
        [1 .. 300 => 16#43#];
   begin
      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_Deflate
             (Input, "payload.txt", Zlib.Default_Level, Status);
      begin
         Assert (Status = Zlib.Ok, "native Deflate level 7z creation");
         declare
            Plain : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip_Stored (Archive, "payload.txt", Status);
         begin
            Assert (Status = Zlib.Ok, "native Deflate level 7z extract status");
            Assert (Plain = Input, "native Deflate level 7z roundtrip payload");
         end;
      end;
   end Test_Deflate_Level_Roundtrip_Native;

   procedure Test_LZMA2_Roundtrip_Native
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code := Zlib.Ok;
      Input  : Zlib.Byte_Array (1 .. 140_000);
   begin
      for I in Input'Range loop
         Input (I) := Zlib.Byte ((I * 17) mod 251);
      end loop;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_LZMA2 (Input, "payload.txt", Status);
      begin
         Assert (Status = Zlib.Ok, "native LZMA2 7z creation before extract");
         declare
            Plain : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip (Archive, "payload.txt", Status);
         begin
            Assert (Status = Zlib.Ok, "native LZMA2 7z extract status");
            Assert (Plain = Input, "native LZMA2 7z roundtrip payload");
         end;
      end;
   end Test_LZMA2_Roundtrip_Native;

   procedure Test_LZMA_Roundtrip_Native
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code := Zlib.Ok;
      Input  : constant Zlib.Byte_Array :=
        [1 .. 4096 => 16#4C#];
   begin
      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_LZMA (Input, "payload.txt", Status);
      begin
         Assert (Status = Zlib.Ok, "native LZMA 7z creation before extract");
         Assert
           (Archive'Length < Input'Length,
            "native LZMA 7z archive should compress repeated payload");
         declare
            Plain : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip (Archive, "payload.txt", Status);
         begin
            Assert (Status = Zlib.Ok, "native LZMA 7z extract status");
            Assert (Plain = Input, "native LZMA 7z roundtrip payload");
         end;
      end;
   end Test_LZMA_Roundtrip_Native;

   procedure Test_BZip2_Roundtrip_Native
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Pattern : constant String := "bzip2 payload";
      Status  : Zlib.Status_Code := Zlib.Ok;
      Input   : Zlib.Byte_Array (1 .. 4096);
   begin
      for I in Input'Range loop
         Input (I) :=
           Zlib.Byte
             (Character'Pos (Pattern ((I - 1) mod Pattern'Length + 1)));
      end loop;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_BZip2 (Input, "payload.txt", Status);
      begin
         Assert (Status = Zlib.Ok, "native BZip2 7z creation before extract");
         Assert
           (Archive'Length < Input'Length,
            "native BZip2 7z archive should compress repeated payload");
         declare
            Plain : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip (Archive, "payload.txt", Status);
         begin
            Assert (Status = Zlib.Ok, "native BZip2 7z extract status");
            Assert (Plain = Input, "native BZip2 7z roundtrip payload");
         end;
      end;
   end Test_BZip2_Roundtrip_Native;

   procedure Test_LZMA_Extracts_Non_Default_Dictionary_Metadata
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status        : Zlib.Status_Code := Zlib.Ok;
      Input         : constant Zlib.Byte_Array := [1 .. 4096 => 16#4D#];
      Archive       : Zlib.Byte_Array :=
        Zlib.Seven_Zip_LZMA (Input, "payload.txt", Status);
      Payload_Count : constant Natural := Natural (U64_LE (Archive, 13));
      Header_First  : constant Natural := 33 + Payload_Count;
      Header_Last   : constant Natural := Archive'Last;
      Props_Pos     : Natural := 0;
   begin
      Assert
        (Status = Zlib.Ok,
         "non-default LZMA dictionary metadata fixture creation");

      for Pos in Header_First .. Header_Last - 8 loop
         if Archive (Pos) = 16#23#
           and then Archive (Pos + 1) = 16#03#
           and then Archive (Pos + 2) = 16#01#
           and then Archive (Pos + 3) = 16#01#
           and then Archive (Pos + 4) = 5
         then
            Props_Pos := Pos + 5;
            exit;
         end if;
      end loop;

      Assert (Props_Pos /= 0, "native LZMA coder properties found");

      Archive (Props_Pos + 1) := 0;
      Archive (Props_Pos + 2) := 0;
      Archive (Props_Pos + 3) := 16#20#;
      Archive (Props_Pos + 4) := 0;

      Set_U32_LE
        (Archive, 29, Zlib.CRC32 (Archive (Header_First .. Header_Last)));
      Set_U32_LE (Archive, 9, Zlib.CRC32 (Archive (13 .. 32)));

      declare
         Plain : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "payload.txt", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native LZMA 7z accepts non-default dictionary metadata");
         Assert (Plain = Input, "non-default LZMA dictionary metadata roundtrip");
      end;
   end Test_LZMA_Extracts_Non_Default_Dictionary_Metadata;

   procedure Test_LZMA2_Compressed_Chunks_Native
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code := Zlib.Ok;
      Input  : Zlib.Byte_Array (1 .. 18_000);
   begin
      for I in Input'Range loop
         Input (I) := 16#41#;
      end loop;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_LZMA2 (Input, "payload.txt", Status);
         Has_Compressed_Control : Boolean := False;
      begin
         Assert (Status = Zlib.Ok, "native compressed LZMA2 7z creation");
         Assert
           (Archive'Length < Input'Length,
            "native LZMA2 compressed chunks shrink repeated payload");

         for B of Archive loop
            if B >= 16#E0# then
               Has_Compressed_Control := True;
               exit;
            end if;
         end loop;
         Assert
           (Has_Compressed_Control,
            "native LZMA2 archive contains compressed chunk control byte");

         declare
            Plain : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip (Archive, "payload.txt", Status);
         begin
            Assert (Status = Zlib.Ok, "native compressed LZMA2 extract status");
            Assert (Plain = Input, "native compressed LZMA2 roundtrip payload");
         end;
      end;
   end Test_LZMA2_Compressed_Chunks_Native;

   procedure Test_Stored_Empty_Payload_Roundtrip_Native
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Empty_Payload : constant Zlib.Byte_Array (1 .. 0) := [others => 0];
      Status        : Zlib.Status_Code := Zlib.Ok;

      type Archive_Builder is access function
        (Input      : Zlib.Byte_Array;
         Entry_Name : String;
         Status     : out Zlib.Status_Code) return Zlib.Byte_Array;

      procedure Check_Empty_Compressed
        (Build : Archive_Builder;
         Label : String)
      is
         Archive : constant Zlib.Byte_Array :=
           Build.all (Empty_Payload, "empty.bin", Status);
      begin
         Assert (Status = Zlib.Ok, Label & " empty 7z creation status");
         declare
            Plain : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip
                (Archive, "empty.bin", Status);
         begin
            Assert (Status = Zlib.Ok, Label & " empty 7z extract status");
            Assert
              (Plain'Length = 0,
               Label & " empty 7z returns empty payload");
         end;
      end Check_Empty_Compressed;
   begin
      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_Stored (Empty_Payload, "empty.bin", Status);
      begin
         Assert (Status = Zlib.Ok, "empty stored 7z creation status");
         declare
            Plain : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip_Stored (Archive, "empty.bin", Status);
         begin
            Assert (Status = Zlib.Ok, "empty stored 7z extract status");
            Assert (Plain'Length = 0, "empty stored 7z returns empty payload");
         end;
      end;

      Check_Empty_Compressed (Zlib.Seven_Zip_Deflate'Access, "Deflate");
      Check_Empty_Compressed (Zlib.Seven_Zip_BZip2'Access, "BZip2");
      Check_Empty_Compressed (Zlib.Seven_Zip_LZMA'Access, "LZMA");
      Check_Empty_Compressed (Zlib.Seven_Zip_LZMA2'Access, "LZMA2");
   end Test_Stored_Empty_Payload_Roundtrip_Native;

   procedure Test_Stored_Non_One_Based_Input_Roundtrip_Native
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Shifted_Payload : constant Zlib.Byte_Array (10 .. 18) :=
        [16#73#, 16#65#, 16#76#, 16#65#, 16#6E#, 16#2D#, 16#7A#, 16#69#, 16#70#];
      Expected        : constant Zlib.Byte_Array :=
        [16#73#, 16#65#, 16#76#, 16#65#, 16#6E#, 16#2D#, 16#7A#, 16#69#, 16#70#];
      Status          : Zlib.Status_Code := Zlib.Ok;
   begin
      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_Stored (Shifted_Payload, "payload.txt", Status);
      begin
         Assert (Status = Zlib.Ok, "non-1-based stored 7z creation status");
         declare
            Shifted_Archive : Zlib.Byte_Array (20 .. 20 + Archive'Length - 1);
         begin
            for I in Archive'Range loop
               Shifted_Archive (20 + I - Archive'First) := Archive (I);
            end loop;

            declare
               Plain : constant Zlib.Byte_Array :=
                 Zlib.Extract_Seven_Zip_Stored
                   (Shifted_Archive, "payload.txt", Status);
            begin
               Assert (Status = Zlib.Ok, "non-1-based stored 7z extract status");
               Assert (Plain = Expected, "non-1-based stored 7z payload roundtrip");
            end;
         end;
      end;
   end Test_Stored_Non_One_Based_Input_Roundtrip_Native;

   procedure Test_Stored_Multibyte_Number_Roundtrip_Native
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Long_Payload : Zlib.Byte_Array (1 .. 200);
      Long_Name    : constant String (1 .. 80) := [others => 'n'];
      Status       : Zlib.Status_Code := Zlib.Ok;
   begin
      for I in Long_Payload'Range loop
         Long_Payload (I) := Zlib.Byte ((I * 37) mod 251);
      end loop;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_Stored (Long_Payload, Long_Name, Status);
      begin
         Assert (Status = Zlib.Ok, "multi-byte 7z number creation status");
         declare
            Plain : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip_Stored (Archive, Long_Name, Status);
         begin
            Assert (Status = Zlib.Ok, "multi-byte 7z number extract status");
            Assert
              (Plain = Long_Payload,
               "multi-byte 7z number payload and name roundtrip");
         end;
      end;
   end Test_Stored_Multibyte_Number_Roundtrip_Native;

   procedure Test_Stored_Extract_Wrong_Name_Fails
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code := Zlib.Ok;
   begin
      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_Stored (Payload, "payload.txt", Status);
      begin
         Assert (Status = Zlib.Ok, "native stored 7z creation before wrong-name extract");
         declare
            Plain : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip_Stored (Archive, "other.txt", Status);
         begin
            Assert (Status = Zlib.Unsupported_Method, "wrong 7z entry name fails closed");
            Assert (Plain'Length = 0, "wrong 7z entry name returns no payload");
         end;
      end;
   end Test_Stored_Extract_Wrong_Name_Fails;

   procedure Test_Stored_Extract_NUL_Name_Fails
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code := Zlib.Ok;
   begin
      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_Stored (Payload, "payload.txt", Status);
      begin
         Assert (Status = Zlib.Ok, "native stored 7z creation before NUL-name extract");
         declare
            Plain : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip_Stored
                (Archive, "payload" & ASCII.NUL & ".txt", Status);
         begin
            Assert (Status = Zlib.Unsupported_Method, "NUL 7z entry name fails closed");
            Assert (Plain'Length = 0, "NUL 7z entry name returns no payload");
         end;
      end;
   end Test_Stored_Extract_NUL_Name_Fails;

   procedure Test_Stored_Extract_Bad_CRC_Fails
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status  : Zlib.Status_Code := Zlib.Ok;
      Archive : Zlib.Byte_Array := Zlib.Seven_Zip_Stored (Payload, "payload.txt", Status);
   begin
      Assert (Status = Zlib.Ok, "bad CRC fixture archive creation status");
      Archive (33) := Archive (33) xor 16#FF#;
      declare
         Plain : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip_Stored (Archive, "payload.txt", Status);
      begin
         Assert (Status = Zlib.Invalid_Checksum, "payload CRC mismatch is reported");
         Assert (Plain'Length = 0, "bad CRC returns no payload");
      end;
   end Test_Stored_Extract_Bad_CRC_Fails;

   procedure Test_Compressed_Extract_Bad_Pack_CRC_Fails
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      type Archive_Builder is access function
        (Input      : Zlib.Byte_Array;
         Entry_Name : String;
         Status     : out Zlib.Status_Code) return Zlib.Byte_Array;

      procedure Check_Bad_Pack_CRC
        (Build : Archive_Builder;
         Label : String)
      is
         Input         : constant Zlib.Byte_Array := [1 .. 512 => 16#44#];
         Status        : Zlib.Status_Code := Zlib.Ok;
         Archive       : Zlib.Byte_Array := Build.all (Input, "payload.txt", Status);
         Payload_Count : constant Natural := Natural (U64_LE (Archive, 13));
         Header_First  : constant Natural := 33 + Payload_Count;
         Header_Last   : constant Natural := Archive'Last;
         Pack_CRC      : constant Interfaces.Unsigned_32 :=
           Zlib.CRC32 (Archive (33 .. Header_First - 1));
         Pack_CRC_Pos  : Natural := 0;
      begin
         Assert (Status = Zlib.Ok, Label & " bad packed CRC fixture creation status");
         Assert (Payload_Count > 0, Label & " bad packed CRC fixture has packed data");

         for Pos in Header_First .. Header_Last - 3 loop
            if U32_LE (Archive, Pos) = Pack_CRC then
               Pack_CRC_Pos := Pos;
               exit;
            end if;
         end loop;

         Assert (Pack_CRC_Pos /= 0, Label & " packed CRC field found");
         Set_U32_LE (Archive, Pack_CRC_Pos, Pack_CRC xor 16#FFFF_FFFF#);
         Set_U32_LE
           (Archive, 29, Zlib.CRC32 (Archive (Header_First .. Header_Last)));
         Set_U32_LE (Archive, 9, Zlib.CRC32 (Archive (13 .. 32)));

         declare
            Plain : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip_Stored (Archive, "payload.txt", Status);
         begin
            Assert
              (Status = Zlib.Invalid_Checksum,
               Label & " bad packed CRC is reported as checksum failure");
            Assert (Plain'Length = 0, Label & " bad packed CRC returns no data");
         end;
      end Check_Bad_Pack_CRC;
   begin
      Check_Bad_Pack_CRC (Zlib.Seven_Zip_BZip2'Access, "BZip2");
      Check_Bad_Pack_CRC (Zlib.Seven_Zip_LZMA'Access, "LZMA");
      Check_Bad_Pack_CRC (Zlib.Seven_Zip_LZMA2'Access, "LZMA2");
   end Test_Compressed_Extract_Bad_Pack_CRC_Fails;

   procedure Test_Deflate_Extract_Corrupt_Payload_Fails
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input         : constant Zlib.Byte_Array := [1 .. 256 => 16#41#];
      Status        : Zlib.Status_Code := Zlib.Ok;
      Archive       : Zlib.Byte_Array :=
        Zlib.Seven_Zip_Deflate (Input, "payload.txt", Zlib.Dynamic, Status);
      Payload_Count : constant Natural := Natural (U64_LE (Archive, 13));
      Header_First  : constant Natural := 33 + Payload_Count;
      Header_Last   : constant Natural := Archive'Last;
      Pack_CRC_Pos  : Natural := 0;
   begin
      Assert (Status = Zlib.Ok, "corrupt Deflate fixture archive creation status");
      Assert (Payload_Count > 0, "corrupt Deflate fixture has packed data");

      declare
         Old_CRC : constant Interfaces.Unsigned_32 :=
           Zlib.CRC32 (Archive (33 .. Header_First - 1));
      begin
         Archive (33) := Archive (33) xor 16#FF#;

         for Pos in Header_First .. Header_Last - 3 loop
            if U32_LE (Archive, Pos) = Old_CRC then
               Pack_CRC_Pos := Pos;
               exit;
            end if;
         end loop;

         Assert (Pack_CRC_Pos /= 0, "packed Deflate CRC field found");
         Set_U32_LE
           (Archive, Pack_CRC_Pos,
            Zlib.CRC32 (Archive (33 .. Header_First - 1)));
         Set_U32_LE
           (Archive, 29, Zlib.CRC32 (Archive (Header_First .. Header_Last)));
         Set_U32_LE (Archive, 9, Zlib.CRC32 (Archive (13 .. 32)));
      end;

      declare
         Plain : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip_Stored (Archive, "payload.txt", Status);
      begin
         Assert
           (Status /= Zlib.Ok and then Status /= Zlib.Invalid_Checksum,
            "corrupt Deflate payload fails during raw Deflate extraction");
         Assert (Plain'Length = 0, "corrupt Deflate payload returns no data");
      end;
   end Test_Deflate_Extract_Corrupt_Payload_Fails;

   procedure Test_Deflate_Extract_Rejects_Trailing_Packed_Bytes
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input         : constant Zlib.Byte_Array := [1 .. 256 => 16#41#];
      Status        : Zlib.Status_Code := Zlib.Ok;
      Archive       : constant Zlib.Byte_Array :=
        Zlib.Seven_Zip_Deflate (Input, "payload.txt", Zlib.Dynamic, Status);
      Payload_Count : constant Natural := Natural (U64_LE (Archive, 13));
      Header_First  : constant Natural := 33 + Payload_Count;
      Header_Last   : constant Natural := Archive'Last;
   begin
      Assert
        (Status = Zlib.Ok,
         "trailing Deflate packed-byte fixture creation status");
      Assert
        (Payload_Count > 0 and then Payload_Count < 127,
         "trailing Deflate fixture uses one-byte 7z pack size");

      declare
         Mutated          : Zlib.Byte_Array (1 .. Archive'Length + 1);
         Mut_Header_First : constant Natural := Header_First + 1;
         Mut_Header_Last  : constant Natural := Header_Last + 1;
         Pack_Size_Pos    : Natural := 0;
         Pack_CRC_Pos     : Natural := 0;
         Old_Pack_CRC     : constant Interfaces.Unsigned_32 :=
           Zlib.CRC32 (Archive (33 .. Header_First - 1));
      begin
         for I in Archive'First .. Header_First - 1 loop
            Mutated (I) := Archive (I);
         end loop;

         Mutated (Header_First) := 0;

         for I in Header_First .. Header_Last loop
            Mutated (I + 1) := Archive (I);
         end loop;

         for Pos in Mut_Header_First .. Mut_Header_Last - 6 loop
            if Mutated (Pos) = 16#01#
              and then Mutated (Pos + 1) = 16#04#
              and then Mutated (Pos + 2) = 16#06#
              and then Mutated (Pos + 3) = 0
              and then Mutated (Pos + 4) = 1
              and then Mutated (Pos + 5) = 16#09#
            then
               Pack_Size_Pos := Pos + 6;
               exit;
            end if;
         end loop;

         Assert
           (Pack_Size_Pos /= 0,
            "single-stream Deflate pack size field found");
         Assert
           (Mutated (Pack_Size_Pos) = Zlib.Byte (Payload_Count),
            "single-stream Deflate pack size field is one-byte encoded");
         Mutated (Pack_Size_Pos) := Zlib.Byte (Payload_Count + 1);

         for Pos in Mut_Header_First .. Mut_Header_Last - 3 loop
            if U32_LE (Mutated, Pos) = Old_Pack_CRC then
               Pack_CRC_Pos := Pos;
               exit;
            end if;
         end loop;

         Assert
           (Pack_CRC_Pos /= 0,
            "single-stream Deflate pack CRC field found");
         Set_U32_LE
           (Mutated, Pack_CRC_Pos,
            Zlib.CRC32 (Mutated (33 .. Mut_Header_First - 1)));
         Set_U64_LE (Mutated, 13, Interfaces.Unsigned_64 (Payload_Count + 1));
         Set_U64_LE
           (Mutated, 21,
            Interfaces.Unsigned_64 (Mut_Header_Last - Mut_Header_First + 1));
         Set_U32_LE
           (Mutated, 29,
            Zlib.CRC32 (Mutated (Mut_Header_First .. Mut_Header_Last)));
         Set_U32_LE (Mutated, 9, Zlib.CRC32 (Mutated (13 .. 32)));

         declare
            Plain : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip_Stored
                (Mutated, "payload.txt", Status);
         begin
            Assert
              (Status = Zlib.Unsupported_Method,
               "Deflate trailing packed bytes fail closed");
            Assert
              (Plain'Length = 0,
               "Deflate trailing packed bytes return no data");
         end;
      end;
   end Test_Deflate_Extract_Rejects_Trailing_Packed_Bytes;

   procedure Test_Deflate_Extract_Bad_Unpack_CRC_Fails
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input         : constant Zlib.Byte_Array := [1 .. 256 => 16#41#];
      Status        : Zlib.Status_Code := Zlib.Ok;
      Archive       : Zlib.Byte_Array :=
        Zlib.Seven_Zip_Deflate (Input, "payload.txt", Zlib.Dynamic, Status);
      Payload_Count : constant Natural := Natural (U64_LE (Archive, 13));
      Header_First  : constant Natural := 33 + Payload_Count;
      Header_Last   : constant Natural := Archive'Last;
      Unpack_CRC    : constant Interfaces.Unsigned_32 := Zlib.CRC32 (Input);
      Unpack_CRC_Pos : Natural := 0;
   begin
      Assert (Status = Zlib.Ok, "bad Deflate unpack CRC fixture creation status");

      for Pos in Header_First .. Header_Last - 3 loop
         if U32_LE (Archive, Pos) = Unpack_CRC then
            Unpack_CRC_Pos := Pos;
            exit;
         end if;
      end loop;

      Assert (Unpack_CRC_Pos /= 0, "Deflate unpack CRC field found");
      Set_U32_LE (Archive, Unpack_CRC_Pos, Unpack_CRC xor 16#FFFF_FFFF#);
      Set_U32_LE
        (Archive, 29, Zlib.CRC32 (Archive (Header_First .. Header_Last)));
      Set_U32_LE (Archive, 9, Zlib.CRC32 (Archive (13 .. 32)));

      declare
         Plain : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip_Stored (Archive, "payload.txt", Status);
      begin
         Assert
           (Status = Zlib.Invalid_Checksum,
            "bad Deflate unpack CRC is reported as checksum failure");
         Assert (Plain'Length = 0, "bad Deflate unpack CRC returns no data");
      end;
   end Test_Deflate_Extract_Bad_Unpack_CRC_Fails;

   procedure Test_Deflate_Extract_Bad_Unpack_Size_Fails
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input         : constant Zlib.Byte_Array := [1 .. 256 => 16#41#];
      Status        : Zlib.Status_Code := Zlib.Ok;
      Archive       : Zlib.Byte_Array :=
        Zlib.Seven_Zip_Deflate (Input, "payload.txt", Zlib.Dynamic, Status);
      Payload_Count : constant Natural := Natural (U64_LE (Archive, 13));
      Header_First  : constant Natural := 33 + Payload_Count;
      Header_Last   : constant Natural := Archive'Last;
      Unpack_Size_Pos : Natural := 0;
   begin
      Assert (Status = Zlib.Ok, "bad Deflate unpack size fixture creation status");

      for Pos in Header_First .. Header_Last - 1 loop
         if Archive (Pos) = 16#81# and then Archive (Pos + 1) = 0 then
            Unpack_Size_Pos := Pos;
            exit;
         end if;
      end loop;

      Assert (Unpack_Size_Pos /= 0, "Deflate unpack size field found");
      Archive (Unpack_Size_Pos + 1) := 1;
      Set_U32_LE
        (Archive, 29, Zlib.CRC32 (Archive (Header_First .. Header_Last)));
      Set_U32_LE (Archive, 9, Zlib.CRC32 (Archive (13 .. 32)));

      declare
         Plain : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip_Stored (Archive, "payload.txt", Status);
      begin
         Assert
           (Status = Zlib.Invalid_Checksum,
            "bad Deflate unpack size is reported as checksum failure");
         Assert (Plain'Length = 0, "bad Deflate unpack size returns no data");
      end;
   end Test_Deflate_Extract_Bad_Unpack_Size_Fails;

   procedure Test_BZip2_Extract_Rejects_Trailing_Packed_Bytes
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input         : constant Zlib.Byte_Array := [1 .. 512 => 16#42#];
      Status        : Zlib.Status_Code := Zlib.Ok;
      Archive       : constant Zlib.Byte_Array :=
        Zlib.Seven_Zip_BZip2 (Input, "payload.txt", Status);
      Payload_Count : constant Natural := Natural (U64_LE (Archive, 13));
      Header_First  : constant Natural := 33 + Payload_Count;
      Header_Last   : constant Natural := Archive'Last;
   begin
      Assert
        (Status = Zlib.Ok,
         "trailing BZip2 packed-byte fixture creation status");
      Assert
        (Payload_Count > 0 and then Payload_Count < 127,
         "trailing BZip2 fixture uses one-byte 7z pack size");

      declare
         Mutated          : Zlib.Byte_Array (1 .. Archive'Length + 1);
         Mut_Header_First : constant Natural := Header_First + 1;
         Mut_Header_Last  : constant Natural := Header_Last + 1;
         Pack_Size_Pos    : Natural := 0;
         Pack_CRC_Pos     : Natural := 0;
         Old_Pack_CRC     : constant Interfaces.Unsigned_32 :=
           Zlib.CRC32 (Archive (33 .. Header_First - 1));
      begin
         for I in Archive'First .. Header_First - 1 loop
            Mutated (I) := Archive (I);
         end loop;

         Mutated (Header_First) := 0;

         for I in Header_First .. Header_Last loop
            Mutated (I + 1) := Archive (I);
         end loop;

         for Pos in Mut_Header_First .. Mut_Header_Last - 6 loop
            if Mutated (Pos) = 16#01#
              and then Mutated (Pos + 1) = 16#04#
              and then Mutated (Pos + 2) = 16#06#
              and then Mutated (Pos + 3) = 0
              and then Mutated (Pos + 4) = 1
              and then Mutated (Pos + 5) = 16#09#
            then
               Pack_Size_Pos := Pos + 6;
               exit;
            end if;
         end loop;

         Assert
           (Pack_Size_Pos /= 0,
            "single-stream BZip2 pack size field found");
         Assert
           (Mutated (Pack_Size_Pos) = Zlib.Byte (Payload_Count),
            "single-stream BZip2 pack size field is one-byte encoded");
         Mutated (Pack_Size_Pos) := Zlib.Byte (Payload_Count + 1);

         for Pos in Mut_Header_First .. Mut_Header_Last - 3 loop
            if U32_LE (Mutated, Pos) = Old_Pack_CRC then
               Pack_CRC_Pos := Pos;
               exit;
            end if;
         end loop;

         Assert
           (Pack_CRC_Pos /= 0,
            "single-stream BZip2 pack CRC field found");
         Set_U32_LE
           (Mutated, Pack_CRC_Pos,
            Zlib.CRC32 (Mutated (33 .. Mut_Header_First - 1)));
         Set_U64_LE (Mutated, 13, Interfaces.Unsigned_64 (Payload_Count + 1));
         Set_U64_LE
           (Mutated, 21,
            Interfaces.Unsigned_64 (Mut_Header_Last - Mut_Header_First + 1));
         Set_U32_LE
           (Mutated, 29,
            Zlib.CRC32 (Mutated (Mut_Header_First .. Mut_Header_Last)));
         Set_U32_LE (Mutated, 9, Zlib.CRC32 (Mutated (13 .. 32)));

         declare
            Plain : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip_Stored
                (Mutated, "payload.txt", Status);
         begin
            Assert
              (Status /= Zlib.Ok,
               "BZip2 trailing packed bytes fail closed");
            Assert
              (Plain'Length = 0,
               "BZip2 trailing packed bytes return no data");
         end;
      end;
   end Test_BZip2_Extract_Rejects_Trailing_Packed_Bytes;

   procedure Test_Compressed_Extract_Corrupt_Payload_Fails
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      type Archive_Builder is access function
        (Input      : Zlib.Byte_Array;
         Entry_Name : String;
         Status     : out Zlib.Status_Code) return Zlib.Byte_Array;

      procedure Check_Corrupt_Payload
        (Build : Archive_Builder;
         Label : String)
      is
         Input         : constant Zlib.Byte_Array := [1 .. 512 => 16#41#];
         Status        : Zlib.Status_Code := Zlib.Ok;
         Archive       : Zlib.Byte_Array := Build.all (Input, "payload.txt", Status);
         Payload_Count : constant Natural := Natural (U64_LE (Archive, 13));
         Header_First  : constant Natural := 33 + Payload_Count;
         Header_Last   : constant Natural := Archive'Last;
         Pack_CRC_Pos  : Natural := 0;
      begin
         Assert (Status = Zlib.Ok, Label & " corrupt fixture archive creation status");
         Assert (Payload_Count > 0, Label & " corrupt fixture has packed data");

         declare
            Old_CRC : constant Interfaces.Unsigned_32 :=
              Zlib.CRC32 (Archive (33 .. Header_First - 1));
         begin
            Archive (33) := Archive (33) xor 16#FF#;

            for Pos in Header_First .. Header_Last - 3 loop
               if U32_LE (Archive, Pos) = Old_CRC then
                  Pack_CRC_Pos := Pos;
                  exit;
               end if;
            end loop;

            Assert (Pack_CRC_Pos /= 0, Label & " packed CRC field found");
            Set_U32_LE
              (Archive, Pack_CRC_Pos,
               Zlib.CRC32 (Archive (33 .. Header_First - 1)));
            Set_U32_LE
              (Archive, 29, Zlib.CRC32 (Archive (Header_First .. Header_Last)));
            Set_U32_LE (Archive, 9, Zlib.CRC32 (Archive (13 .. 32)));
         end;

         declare
            Plain : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip_Stored (Archive, "payload.txt", Status);
         begin
            Assert
              (Status /= Zlib.Ok,
               Label & " corrupt payload fails during native extraction");
            Assert (Plain'Length = 0, Label & " corrupt payload returns no data");
         end;
      end Check_Corrupt_Payload;
   begin
      Check_Corrupt_Payload (Zlib.Seven_Zip_BZip2'Access, "BZip2");
      Check_Corrupt_Payload (Zlib.Seven_Zip_LZMA2'Access, "LZMA2");
   end Test_Compressed_Extract_Corrupt_Payload_Fails;

   procedure Test_Compressed_Extract_Bad_Unpack_CRC_Fails
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      type Archive_Builder is access function
        (Input      : Zlib.Byte_Array;
         Entry_Name : String;
         Status     : out Zlib.Status_Code) return Zlib.Byte_Array;

      procedure Check_Bad_Unpack_CRC
        (Build : Archive_Builder;
         Label : String)
      is
         Input          : constant Zlib.Byte_Array := [1 .. 512 => 16#42#];
         Status         : Zlib.Status_Code := Zlib.Ok;
         Archive        : Zlib.Byte_Array := Build.all (Input, "payload.txt", Status);
         Payload_Count  : constant Natural := Natural (U64_LE (Archive, 13));
         Header_First   : constant Natural := 33 + Payload_Count;
         Header_Last    : constant Natural := Archive'Last;
         Unpack_CRC     : constant Interfaces.Unsigned_32 := Zlib.CRC32 (Input);
         Unpack_CRC_Pos : Natural := 0;
      begin
         Assert (Status = Zlib.Ok, Label & " bad unpack CRC fixture creation status");

         for Pos in Header_First .. Header_Last - 3 loop
            if U32_LE (Archive, Pos) = Unpack_CRC then
               Unpack_CRC_Pos := Pos;
               exit;
            end if;
         end loop;

         Assert (Unpack_CRC_Pos /= 0, Label & " unpack CRC field found");
         Set_U32_LE (Archive, Unpack_CRC_Pos, Unpack_CRC xor 16#FFFF_FFFF#);
         Set_U32_LE
           (Archive, 29, Zlib.CRC32 (Archive (Header_First .. Header_Last)));
         Set_U32_LE (Archive, 9, Zlib.CRC32 (Archive (13 .. 32)));

         declare
            Plain : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip_Stored (Archive, "payload.txt", Status);
         begin
            Assert
              (Status = Zlib.Invalid_Checksum,
               Label & " bad unpack CRC is reported as checksum failure");
            Assert (Plain'Length = 0, Label & " bad unpack CRC returns no data");
         end;
      end Check_Bad_Unpack_CRC;
   begin
      Check_Bad_Unpack_CRC (Zlib.Seven_Zip_BZip2'Access, "BZip2");
      Check_Bad_Unpack_CRC (Zlib.Seven_Zip_LZMA'Access, "LZMA");
      Check_Bad_Unpack_CRC (Zlib.Seven_Zip_LZMA2'Access, "LZMA2");
   end Test_Compressed_Extract_Bad_Unpack_CRC_Fails;

   procedure Test_Compressed_Extract_Bad_Unpack_Size_Fails
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      type Archive_Builder is access function
        (Input      : Zlib.Byte_Array;
         Entry_Name : String;
         Status     : out Zlib.Status_Code) return Zlib.Byte_Array;

      procedure Check_Bad_Unpack_Size
        (Build : Archive_Builder;
         Label : String)
      is
         Input           : constant Zlib.Byte_Array := [1 .. 256 => 16#43#];
         Status          : Zlib.Status_Code := Zlib.Ok;
         Archive         : Zlib.Byte_Array := Build.all (Input, "payload.txt", Status);
         Payload_Count   : constant Natural := Natural (U64_LE (Archive, 13));
         Header_First    : constant Natural := 33 + Payload_Count;
         Header_Last     : constant Natural := Archive'Last;
         Unpack_Size_Pos : Natural := 0;
      begin
         Assert (Status = Zlib.Ok, Label & " bad unpack size fixture creation status");

         for Pos in Header_First .. Header_Last - 1 loop
            if Archive (Pos) = 16#81# and then Archive (Pos + 1) = 0 then
               Unpack_Size_Pos := Pos;
               exit;
            end if;
         end loop;

         Assert (Unpack_Size_Pos /= 0, Label & " unpack size field found");
         Archive (Unpack_Size_Pos + 1) := 1;
         Set_U32_LE
           (Archive, 29, Zlib.CRC32 (Archive (Header_First .. Header_Last)));
         Set_U32_LE (Archive, 9, Zlib.CRC32 (Archive (13 .. 32)));

         declare
            Plain : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip_Stored (Archive, "payload.txt", Status);
         begin
            Assert
              (Status /= Zlib.Ok,
               Label & " bad unpack size is rejected");
            Assert (Plain'Length = 0, Label & " bad unpack size returns no data");
         end;
      end Check_Bad_Unpack_Size;
   begin
      Check_Bad_Unpack_Size (Zlib.Seven_Zip_BZip2'Access, "BZip2");
      Check_Bad_Unpack_Size (Zlib.Seven_Zip_LZMA'Access, "LZMA");
      Check_Bad_Unpack_Size (Zlib.Seven_Zip_LZMA2'Access, "LZMA2");
   end Test_Compressed_Extract_Bad_Unpack_Size_Fails;

   procedure Test_Stored_Extract_Bad_Start_Header_CRC_Fails
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status  : Zlib.Status_Code := Zlib.Ok;
      Archive : Zlib.Byte_Array := Zlib.Seven_Zip_Stored (Payload, "payload.txt", Status);
   begin
      Assert (Status = Zlib.Ok, "bad start-header CRC fixture archive creation status");
      Archive (9) := Archive (9) xor 16#FF#;
      declare
         Plain : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip_Stored (Archive, "payload.txt", Status);
      begin
         Assert (Status = Zlib.Invalid_Checksum, "start-header CRC mismatch is reported");
         Assert (Plain'Length = 0, "bad start-header CRC returns no payload");
      end;
   end Test_Stored_Extract_Bad_Start_Header_CRC_Fails;

   procedure Test_Stored_Extract_Bad_Next_Header_CRC_Fails
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status  : Zlib.Status_Code := Zlib.Ok;
      Archive : Zlib.Byte_Array := Zlib.Seven_Zip_Stored (Payload, "payload.txt", Status);
   begin
      Assert (Status = Zlib.Ok, "bad next-header CRC fixture archive creation status");
      Archive (Archive'Last) := Archive (Archive'Last) xor 16#FF#;
      declare
         Plain : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip_Stored (Archive, "payload.txt", Status);
      begin
         Assert (Status = Zlib.Invalid_Checksum, "next-header CRC mismatch is reported");
         Assert (Plain'Length = 0, "bad next-header CRC returns no payload");
      end;
   end Test_Stored_Extract_Bad_Next_Header_CRC_Fails;

   procedure Test_Extract_Accepts_Optional_CRC_Sections_Omitted
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      type Archive_Builder is access function
        (Input      : Zlib.Byte_Array;
         Entry_Name : String;
         Status     : out Zlib.Status_Code) return Zlib.Byte_Array;

      procedure Check_Archive
        (Builder : Archive_Builder;
         Label   : String)
      is
         Status       : Zlib.Status_Code := Zlib.Ok;
         Archive      : constant Zlib.Byte_Array :=
           Builder.all (Payload, "payload.txt", Status);
         Header_First : Natural := 0;
         Pack_CRC_Pos : Natural := 0;
         Unpack_CRC_Pos : Natural := 0;
      begin
         Assert (Status = Zlib.Ok, Label & " optional-CRC fixture creation");

         Header_First := Seven_Zip_Header_First (Archive);
         Pack_CRC_Pos := Find_Seven_Zip_CRC_Property (Archive, Header_First);
         Assert (Pack_CRC_Pos /= 0, Label & " packed CRC property found");

         Unpack_CRC_Pos :=
           Find_Seven_Zip_CRC_Property (Archive, Pack_CRC_Pos + 6);
         Assert (Unpack_CRC_Pos /= 0, Label & " unpack CRC property found");

         declare
            No_Pack_CRC : constant Zlib.Byte_Array :=
              Remove_Seven_Zip_Header_Bytes (Archive, Pack_CRC_Pos, 6);
            Plain       : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip
                (No_Pack_CRC, "payload.txt", Status);
         begin
            Assert
              (Status = Zlib.Ok,
               Label & " extracts when packed CRC property is omitted");
            Assert
              (Plain = Payload,
               Label & " omitted packed CRC preserves payload");
         end;

         declare
            No_Unpack_CRC : constant Zlib.Byte_Array :=
              Remove_Seven_Zip_Header_Bytes (Archive, Unpack_CRC_Pos, 6);
            Plain         : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip
                (No_Unpack_CRC, "payload.txt", Status);
         begin
            Assert
              (Status = Zlib.Ok,
               Label & " extracts when unpack CRC property is omitted");
            Assert
              (Plain = Payload,
               Label & " omitted unpack CRC preserves payload");
         end;

         declare
            Without_Unpack : constant Zlib.Byte_Array :=
              Remove_Seven_Zip_Header_Bytes (Archive, Unpack_CRC_Pos, 6);
            Without_Both   : constant Zlib.Byte_Array :=
              Remove_Seven_Zip_Header_Bytes (Without_Unpack, Pack_CRC_Pos, 6);
            Plain          : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip
                (Without_Both, "payload.txt", Status);
         begin
            Assert
              (Status = Zlib.Ok,
               Label & " extracts when both optional CRC properties are omitted");
            Assert
              (Plain = Payload,
               Label & " omitted optional CRC properties preserve payload");
         end;
      end Check_Archive;
   begin
      Check_Archive (Zlib.Seven_Zip_Stored'Access, "stored");
      Check_Archive (Zlib.Seven_Zip_Deflate'Access, "Deflate");
      Check_Archive (Zlib.Seven_Zip_BZip2'Access, "BZip2");
      Check_Archive (Zlib.Seven_Zip_LZMA'Access, "LZMA");
      Check_Archive (Zlib.Seven_Zip_LZMA2'Access, "LZMA2");
   end Test_Extract_Accepts_Optional_CRC_Sections_Omitted;

   procedure Test_Extract_Accepts_Archive_And_File_Metadata
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status       : Zlib.Status_Code := Zlib.Ok;
      Base_Archive : constant Zlib.Byte_Array :=
        Zlib.Seven_Zip_Stored (Payload, "payload.txt", Status);
      Archive_Properties : constant Zlib.Byte_Array (1 .. 7) :=
        [16#02#, 16#19#, 3, 1, 2, 3, 0];
      Substream_Properties : constant Zlib.Byte_Array (1 .. 6) :=
        [16#08#, 16#19#, 2, 4, 5, 0];
      File_Properties : constant Zlib.Byte_Array (1 .. 19) :=
        [16#14#, 10, 1, 0, 0, 16#80#, 16#3E#, 16#D5#, 16#DE#, 16#B1#, 16#9D#, 1,
         16#15#, 5, 1, 1, 0, 0, 0];
      Archive_Path : constant String :=
        Base_Path ("metadata-preservation.7z");
      Output_Path  : constant String :=
        Base_Path ("metadata-preservation.out");
      Output_Dir   : constant String :=
        Base_Path ("metadata-preservation.dir");
      Expected_MTime : constant Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (1970, 1, 1, 0.0);

      procedure Assert_MTime (Path : String; Label : String) is
         Difference : Duration :=
           Ada.Directories.Modification_Time (Path) - Expected_MTime;
      begin
         if Difference < 0.0 then
            Difference := -Difference;
         end if;
         Assert (Difference <= 2.0, Label);
      end Assert_MTime;

      procedure Assert_Read_Only (Path : String; Label : String) is
      begin
         Assert (not GNAT.OS_Lib.Is_Owner_Writable_File (Path), Label);
      end Assert_Read_Only;
   begin
      Assert (Status = Zlib.Ok, "metadata fixture archive creation");
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Path);
      Delete_If_Exists (Output_Dir);

      declare
         With_Archive_Properties : constant Zlib.Byte_Array :=
           Insert_Seven_Zip_Header_Bytes
             (Base_Archive,
              Seven_Zip_Header_First (Base_Archive) + 1,
              Archive_Properties);
         With_Substream_Properties : constant Zlib.Byte_Array :=
           Insert_Seven_Zip_Header_Bytes
             (With_Archive_Properties,
              Find_Seven_Zip_Files_Info (With_Archive_Properties) - 1,
              Substream_Properties);
         With_Metadata           : constant Zlib.Byte_Array :=
           Insert_Seven_Zip_Header_Bytes
             (With_Substream_Properties,
              With_Substream_Properties'Last - 1,
              File_Properties);
         Plain                   : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip
             (With_Metadata, "payload.txt", Status);
         Metadata                : Zlib.Seven_Zip_Entry_Metadata;
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z extraction accepts archive and file metadata");
         Assert
           (Plain = Payload,
            "native 7z archive and file metadata preserve payload");

         Metadata :=
           Zlib.Extract_Seven_Zip_Metadata
             (With_Metadata, "payload.txt", Status);
         Assert
           (Status = Zlib.Ok,
            "native 7z metadata query accepts archive and file metadata");
         Assert
           (not Metadata.Is_Directory,
            "native 7z metadata query preserves file kind");
         Assert
           (Metadata.Has_Modification_Time,
            "native 7z metadata query reports modification time");
         Assert
           (Metadata.Modification_Time = 16#019D_B1DE_D53E_8000#,
            "native 7z metadata query preserves modification FILETIME");
         Assert
           (Metadata.Has_Windows_Attributes,
            "native 7z metadata query reports Windows attributes");
         Assert
           (Metadata.Windows_Attributes = 16#0000_0001#,
            "native 7z metadata query preserves read-only attribute");

         Write_File (Archive_Path, With_Metadata);
         Zlib.Extract_Seven_Zip_File
           (Archive_Path, Output_Path, "payload.txt", Status);
         Assert
           (Status = Zlib.Ok,
            "native 7z file extraction preserves metadata status");
         Assert_MTime
           (Output_Path,
            "native 7z file extraction preserves modification time");
         Assert_Read_Only
           (Output_Path,
            "native 7z file extraction preserves read-only attribute");

         Delete_If_Exists (Output_Dir);
         Zlib.Extract_Seven_Zip_Files
           (Archive_Path, Output_Dir,
            [1 => US.To_Unbounded_String ("payload.txt")],
            Status);
         Assert
           (Status = Zlib.Ok,
            "native 7z file-list extraction preserves metadata status");
         Assert_MTime
           (Ada.Directories.Compose (Output_Dir, "payload.txt"),
            "native 7z file-list extraction preserves modification time");
         Assert_Read_Only
           (Ada.Directories.Compose (Output_Dir, "payload.txt"),
            "native 7z file-list extraction preserves read-only attribute");
      end;
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Path);
      Delete_If_Exists (Output_Dir);
   exception
      when others =>
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Path);
         Delete_If_Exists (Output_Dir);
         raise;
   end Test_Extract_Accepts_Archive_And_File_Metadata;

   procedure Test_Stored_Creation_Emits_Metadata
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status        : Zlib.Status_Code := Zlib.Ok;
      Metadata      : constant Zlib.Seven_Zip_Entry_Metadata :=
        (Is_Directory           => False,
         Has_Modification_Time  => True,
         Modification_Time      => 16#019D_B1DE_D53E_8000#,
         Has_Windows_Attributes => True,
         Windows_Attributes     => 16#0000_0001#);
      Archive       : constant Zlib.Byte_Array :=
        Zlib.Seven_Zip_Stored (Payload, "payload.txt", Metadata, Status);
      Archive_Path  : constant String :=
        Base_Path ("metadata-creation.7z");
      Output_Path   : constant String :=
        Base_Path ("metadata-creation.out");
      Expected_Time : constant Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (1970, 1, 1, 0.0);

      procedure Assert_MTime (Path : String; Label : String) is
         Difference : Duration :=
           Ada.Directories.Modification_Time (Path) - Expected_Time;
      begin
         if Difference < 0.0 then
            Difference := -Difference;
         end if;
         Assert (Difference <= 2.0, Label);
      end Assert_MTime;
   begin
      Assert (Status = Zlib.Ok, "native stored 7z metadata creation status");

      declare
         Extract_Status : Zlib.Status_Code := Zlib.Ok;
         Metadata_Status : Zlib.Status_Code := Zlib.Ok;
         Plain    : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "payload.txt", Extract_Status);
         Decoded  : constant Zlib.Seven_Zip_Entry_Metadata :=
           Zlib.Extract_Seven_Zip_Metadata
             (Archive, "payload.txt", Metadata_Status);
      begin
         Assert (Extract_Status = Zlib.Ok, "native stored 7z metadata extract status");
         Assert (Metadata_Status = Zlib.Ok, "native stored 7z metadata query status");
         Assert (Plain = Payload, "native stored 7z metadata preserves payload");
         Assert (not Decoded.Is_Directory, "native stored 7z metadata emits file kind");
         Assert
           (Decoded.Has_Modification_Time
            and then Decoded.Modification_Time = Metadata.Modification_Time,
            "native stored 7z metadata emits modification time");
         Assert
           (Decoded.Has_Windows_Attributes
            and then Decoded.Windows_Attributes = Metadata.Windows_Attributes,
            "native stored 7z metadata emits Windows attributes");
      end;

      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Path);
      Write_File (Archive_Path, Archive);
      Zlib.Extract_Seven_Zip_File
        (Archive_Path, Output_Path, "payload.txt", Status);
      Assert (Status = Zlib.Ok, "native stored 7z metadata file extraction status");
      Assert_MTime (Output_Path, "native stored 7z metadata restores mtime");
      Assert
        (not GNAT.OS_Lib.Is_Owner_Writable_File (Output_Path),
         "native stored 7z metadata restores read-only attribute");

      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Path);
   exception
      when others =>
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Path);
         raise;
   end Test_Stored_Creation_Emits_Metadata;

   procedure Test_Stored_Creation_Emits_Directory_Entry
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status   : Zlib.Status_Code := Zlib.Ok;
      Metadata : constant Zlib.Seven_Zip_Entry_Metadata :=
        (Is_Directory           => True,
         Has_Modification_Time  => True,
         Modification_Time      => 16#019D_B1DE_D53E_8000#,
         Has_Windows_Attributes => True,
         Windows_Attributes     => 16#0000_0010#);
      Empty_Input : constant Zlib.Byte_Array (1 .. 0) := [others => 0];
      Archive  : constant Zlib.Byte_Array :=
        Zlib.Seven_Zip_Stored (Empty_Input, "dir", Metadata, Status);
   begin
      Assert (Status = Zlib.Ok, "native stored 7z directory creation status");
      Assert (Archive'Length > 0, "native stored 7z directory archive emitted");

      declare
         Extract_Status  : Zlib.Status_Code := Zlib.Ok;
         Metadata_Status : Zlib.Status_Code := Zlib.Ok;
         Plain           : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "dir", Extract_Status);
         Decoded         : constant Zlib.Seven_Zip_Entry_Metadata :=
           Zlib.Extract_Seven_Zip_Metadata
             (Archive, "dir", Metadata_Status);
      begin
         Assert
           (Extract_Status = Zlib.Ok,
            "native stored 7z directory extraction status");
         Assert (Plain'Length = 0, "native stored 7z directory has no payload");
         Assert
           (Metadata_Status = Zlib.Ok,
            "native stored 7z directory metadata status");
         Assert (Decoded.Is_Directory, "native stored 7z emits directory kind");
         Assert
           (Decoded.Has_Modification_Time
            and then Decoded.Modification_Time = Metadata.Modification_Time,
            "native stored 7z directory emits modification time");
         Assert
           (Decoded.Has_Windows_Attributes
            and then Decoded.Windows_Attributes = Metadata.Windows_Attributes,
            "native stored 7z directory emits Windows attributes");
      end;
   end Test_Stored_Creation_Emits_Directory_Entry;

   procedure Test_Compressed_Creation_Emits_Metadata
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Metadata : constant Zlib.Seven_Zip_Entry_Metadata :=
        (Is_Directory           => False,
         Has_Modification_Time  => True,
         Modification_Time      => 16#019D_B1DE_D53E_8000#,
         Has_Windows_Attributes => True,
         Windows_Attributes     => 16#0000_0020#);

      procedure Check_Archive
        (Archive : Zlib.Byte_Array;
         Label   : String)
      is
         Extract_Status  : Zlib.Status_Code := Zlib.Ok;
         Metadata_Status : Zlib.Status_Code := Zlib.Ok;
         Plain           : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "payload.txt", Extract_Status);
         Decoded         : constant Zlib.Seven_Zip_Entry_Metadata :=
           Zlib.Extract_Seven_Zip_Metadata
             (Archive, "payload.txt", Metadata_Status);
      begin
         Assert (Extract_Status = Zlib.Ok, Label & " extraction status");
         Assert (Metadata_Status = Zlib.Ok, Label & " metadata status");
         Assert (Plain = Payload, Label & " preserves payload");
         Assert
           (Decoded.Has_Modification_Time
            and then Decoded.Modification_Time = Metadata.Modification_Time,
            Label & " emits modification time");
         Assert
           (Decoded.Has_Windows_Attributes
            and then Decoded.Windows_Attributes = Metadata.Windows_Attributes,
            Label & " emits Windows attributes");
      end Check_Archive;

   begin
      declare
         Status  : Zlib.Status_Code := Zlib.Ok;
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_Deflate
             (Payload, "payload.txt", Zlib.Dynamic, Metadata, Status);
      begin
         Assert (Status = Zlib.Ok, "Deflate metadata creation status");
         Check_Archive (Archive, "Deflate metadata creation");
      end;

      declare
         Status  : Zlib.Status_Code := Zlib.Ok;
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_Deflate
             (Payload, "payload.txt", Zlib.Compression_Level'(6),
              Metadata, Status);
      begin
         Assert (Status = Zlib.Ok, "Deflate level metadata creation status");
         Check_Archive (Archive, "Deflate level metadata creation");
      end;

      declare
         Status  : Zlib.Status_Code := Zlib.Ok;
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_BZip2 (Payload, "payload.txt", Metadata, Status);
      begin
         Assert (Status = Zlib.Ok, "BZip2 metadata creation status");
         Check_Archive (Archive, "BZip2 metadata creation");
      end;

      declare
         Status  : Zlib.Status_Code := Zlib.Ok;
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_LZMA (Payload, "payload.txt", Metadata, Status);
      begin
         Assert (Status = Zlib.Ok, "LZMA metadata creation status");
         Check_Archive (Archive, "LZMA metadata creation");
      end;

      declare
         Status  : Zlib.Status_Code := Zlib.Ok;
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_LZMA2 (Payload, "payload.txt", Metadata, Status);
      begin
         Assert (Status = Zlib.Ok, "LZMA2 metadata creation status");
         Check_Archive (Archive, "LZMA2 metadata creation");
      end;

      declare
         Status  : Zlib.Status_Code := Zlib.Ok;
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd (Payload, "payload.txt", Metadata, Status);
      begin
         Assert (Status = Zlib.Ok, "PPMd metadata creation status");
         Check_Archive (Archive, "PPMd metadata creation");
      end;
   end Test_Compressed_Creation_Emits_Metadata;

   procedure Test_Compressed_Creation_Emits_Directory_Entries
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Metadata : constant Zlib.Seven_Zip_Entry_Metadata :=
        (Is_Directory           => True,
         Has_Modification_Time  => True,
         Modification_Time      => 16#019D_B1DE_D53E_8000#,
         Has_Windows_Attributes => True,
         Windows_Attributes     => 16#0000_0010#);

      procedure Check_Directory
        (Archive : Zlib.Byte_Array;
         Status  : Zlib.Status_Code;
         Label   : String)
      is
         Extract_Status  : Zlib.Status_Code := Zlib.Ok;
         Metadata_Status : Zlib.Status_Code := Zlib.Ok;
         Plain           : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "dir", Extract_Status);
         Decoded         : constant Zlib.Seven_Zip_Entry_Metadata :=
           Zlib.Extract_Seven_Zip_Metadata
             (Archive, "dir", Metadata_Status);
      begin
         Assert (Status = Zlib.Ok, Label & " directory creation status");
         Assert (Archive'Length > 0, Label & " directory archive emitted");
         Assert (Extract_Status = Zlib.Ok, Label & " directory extraction status");
         Assert (Plain'Length = 0, Label & " directory has no payload");
         Assert (Metadata_Status = Zlib.Ok, Label & " directory metadata status");
         Assert (Decoded.Is_Directory, Label & " emits directory kind");
         Assert
           (Decoded.Has_Modification_Time
            and then Decoded.Modification_Time = Metadata.Modification_Time,
            Label & " emits directory modification time");
         Assert
           (Decoded.Has_Windows_Attributes
            and then Decoded.Windows_Attributes = Metadata.Windows_Attributes,
            Label & " emits directory Windows attributes");
      end Check_Directory;
   begin
      declare
         Status  : Zlib.Status_Code := Zlib.Ok;
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_Deflate
             (Payload, "dir", Zlib.Dynamic, Metadata, Status);
      begin
         Check_Directory (Archive, Status, "Deflate");
      end;

      declare
         Status  : Zlib.Status_Code := Zlib.Ok;
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_Deflate
             (Payload, "dir", Zlib.Compression_Level'(6), Metadata, Status);
      begin
         Check_Directory (Archive, Status, "Deflate level");
      end;

      declare
         Status  : Zlib.Status_Code := Zlib.Ok;
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_BZip2 (Payload, "dir", Metadata, Status);
      begin
         Check_Directory (Archive, Status, "BZip2");
      end;

      declare
         Status  : Zlib.Status_Code := Zlib.Ok;
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_LZMA (Payload, "dir", Metadata, Status);
      begin
         Check_Directory (Archive, Status, "LZMA");
      end;

      declare
         Status  : Zlib.Status_Code := Zlib.Ok;
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_LZMA2 (Payload, "dir", Metadata, Status);
      begin
         Check_Directory (Archive, Status, "LZMA2");
      end;

      declare
         Status  : Zlib.Status_Code := Zlib.Ok;
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd (Payload, "dir", Metadata, Status);
      begin
         Check_Directory (Archive, Status, "PPMd");
      end;
   end Test_Compressed_Creation_Emits_Directory_Entries;

   procedure Test_File_Creation_Preserves_Source_Metadata
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Source_Path       : constant String :=
        Base_Path ("metadata-source.bin");
      Archive_Path      : constant String :=
        Base_Path ("metadata-source.7z");
      Output_Path       : constant String :=
        Base_Path ("metadata-source.out");
      Expected_Filetime : constant Interfaces.Unsigned_64 :=
        16#019D_B1DE_D53E_8000#;
      Expected_Time     : constant Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (1970, 1, 1, 0.0);
      Status            : Zlib.Status_Code := Zlib.Ok;

      procedure Prepare_Source is
      begin
         Delete_If_Exists (Source_Path);
         Write_File (Source_Path, Payload);
         GNAT.OS_Lib.Set_File_Last_Modify_Time_Stamp
           (Source_Path,
            GNAT.OS_Lib.GM_Time_Of
              (1970, 1, 1, 0, 0, 0));
         GNAT.OS_Lib.Set_Read_Only (Source_Path);
      end Prepare_Source;

      procedure Assert_MTime (Path : String; Label : String) is
         Difference : Duration :=
           Ada.Directories.Modification_Time (Path) - Expected_Time;
      begin
         if Difference < 0.0 then
            Difference := -Difference;
         end if;
         Assert (Difference <= 2.0, Label);
      end Assert_MTime;

      procedure Check_Archive (Entry_Name : String; Label : String) is
         Archive         : constant Zlib.Byte_Array := Read_File (Archive_Path);
         Extract_Status  : Zlib.Status_Code := Zlib.Ok;
         Metadata_Status : Zlib.Status_Code := Zlib.Ok;
         Plain           : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, Entry_Name, Extract_Status);
         Metadata        : constant Zlib.Seven_Zip_Entry_Metadata :=
           Zlib.Extract_Seven_Zip_Metadata
             (Archive, Entry_Name, Metadata_Status);
      begin
         Assert (Extract_Status = Zlib.Ok, Label & " extraction status");
         Assert (Metadata_Status = Zlib.Ok, Label & " metadata status");
         Assert (Plain = Payload, Label & " preserves payload");
         Assert
           (Metadata.Has_Modification_Time
            and then Metadata.Modification_Time = Expected_Filetime,
            Label & " preserves source modification time");
         Assert
           (Metadata.Has_Windows_Attributes
            and then (Metadata.Windows_Attributes and 16#0000_0001#) /= 0,
            Label & " preserves source read-only attribute");

         Delete_If_Exists (Output_Path);
         Zlib.Extract_Seven_Zip_File
           (Archive_Path, Output_Path, Entry_Name, Status);
         Assert (Status = Zlib.Ok, Label & " file extraction status");
         Assert_MTime (Output_Path, Label & " restores source mtime");
         Assert
           (not GNAT.OS_Lib.Is_Owner_Writable_File (Output_Path),
            Label & " restores source read-only attribute");
      end Check_Archive;
   begin
      Prepare_Source;

      Delete_If_Exists (Archive_Path);
      Zlib.Seven_Zip_Stored_File
        (Source_Path, Archive_Path, "payload.txt", Status);
      Assert (Status = Zlib.Ok, "stored file helper preserves metadata status");
      Check_Archive ("payload.txt", "stored file helper metadata");

      Delete_If_Exists (Archive_Path);
      Zlib.Seven_Zip_Deflate_File
        (Source_Path, Archive_Path, "payload.txt", Zlib.Dynamic, Status);
      Assert (Status = Zlib.Ok, "Deflate file helper preserves metadata status");
      Check_Archive ("payload.txt", "Deflate file helper metadata");

      Delete_If_Exists (Archive_Path);
      Zlib.Seven_Zip_BZip2_File
        (Source_Path, Archive_Path, "payload.txt", Status);
      Assert (Status = Zlib.Ok, "BZip2 file helper preserves metadata status");
      Check_Archive ("payload.txt", "BZip2 file helper metadata");

      Delete_If_Exists (Archive_Path);
      Zlib.Seven_Zip_LZMA_File
        (Source_Path, Archive_Path, "payload.txt", Status);
      Assert (Status = Zlib.Ok, "LZMA file helper preserves metadata status");
      Check_Archive ("payload.txt", "LZMA file helper metadata");

      Delete_If_Exists (Archive_Path);
      Zlib.Seven_Zip_LZMA2_File
        (Source_Path, Archive_Path, "payload.txt", Status);
      Assert (Status = Zlib.Ok, "LZMA2 file helper preserves metadata status");
      Check_Archive ("payload.txt", "LZMA2 file helper metadata");

      Delete_If_Exists (Archive_Path);
      Zlib.Seven_Zip_PPMd_File (Source_Path, Archive_Path, Status);
      Assert (Status = Zlib.Ok, "PPMd file helper preserves metadata status");
      Check_Archive
        ("zlib-seven-zip-metadata-source.bin", "PPMd file helper metadata");

      Delete_If_Exists (Source_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Path);
   exception
      when others =>
         Delete_If_Exists (Source_Path);
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Path);
         raise;
   end Test_File_Creation_Preserves_Source_Metadata;

   procedure Test_File_List_Creation_Preserves_Source_Metadata
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      First_Path        : constant String :=
        Base_Path ("metadata-list-first.bin");
      Second_Path       : constant String :=
        Base_Path ("metadata-list-second.bin");
      Archive_Path      : constant String :=
        Base_Path ("metadata-list.7z");
      Expected_Filetime : constant Interfaces.Unsigned_64 :=
        16#019D_B1DE_D53E_8000#;
      Status            : Zlib.Status_Code := Zlib.Ok;
      Input_Paths       : constant Zlib.Text_Array :=
        [1 => US.To_Unbounded_String (First_Path),
         2 => US.To_Unbounded_String (Second_Path)];
      Entry_Names       : constant Zlib.Text_Array :=
        [1 => US.To_Unbounded_String ("first.txt"),
         2 => US.To_Unbounded_String ("second.txt")];

      procedure Prepare_Source (Path : String; Data : Zlib.Byte_Array) is
      begin
         Delete_If_Exists (Path);
         Write_File (Path, Data);
         GNAT.OS_Lib.Set_File_Last_Modify_Time_Stamp
           (Path,
            GNAT.OS_Lib.GM_Time_Of
              (1970, 1, 1, 0, 0, 0));
         GNAT.OS_Lib.Set_Read_Only (Path);
      end Prepare_Source;

      procedure Check_Entry (Archive : Zlib.Byte_Array; Entry_Name : String) is
         Metadata_Status : Zlib.Status_Code := Zlib.Ok;
         Metadata        : constant Zlib.Seven_Zip_Entry_Metadata :=
           Zlib.Extract_Seven_Zip_Metadata
             (Archive, Entry_Name, Metadata_Status);
      begin
         Assert (Metadata_Status = Zlib.Ok, Entry_Name & " metadata status");
         Assert
           (Metadata.Has_Modification_Time
            and then Metadata.Modification_Time = Expected_Filetime,
            Entry_Name & " source modification time preserved");
         Assert
           (Metadata.Has_Windows_Attributes
            and then (Metadata.Windows_Attributes and 16#0000_0001#) /= 0,
            Entry_Name & " source read-only attribute preserved");
      end Check_Entry;

      procedure Check_Archive (Label : String) is
         Archive : constant Zlib.Byte_Array := Read_File (Archive_Path);
      begin
         Check_Entry (Archive, "first.txt");
         Check_Entry (Archive, "second.txt");
         Assert (Archive'Length > 0, Label & " archive was written");
      end Check_Archive;
   begin
      Prepare_Source (First_Path, Payload);
      Prepare_Source (Second_Path, [16#41#, 16#42#, 16#43#]);

      Delete_If_Exists (Archive_Path);
      Zlib.Seven_Zip_Stored_Files
        (Input_Paths, Archive_Path, Entry_Names, Status);
      Assert (Status = Zlib.Ok, "stored file-list metadata status");
      Check_Archive ("stored file-list metadata");

      Delete_If_Exists (Archive_Path);
      Zlib.Seven_Zip_Deflate_Files
        (Input_Paths, Archive_Path, Entry_Names, Zlib.Dynamic, Status);
      Assert (Status = Zlib.Ok, "Deflate file-list metadata status");
      Check_Archive ("Deflate file-list metadata");

      Delete_If_Exists (Archive_Path);
      Zlib.Seven_Zip_BZip2_Files
        (Input_Paths, Archive_Path, Entry_Names, Status);
      Assert (Status = Zlib.Ok, "BZip2 file-list metadata status");
      Check_Archive ("BZip2 file-list metadata");

      Delete_If_Exists (Archive_Path);
      Zlib.Seven_Zip_LZMA_Files
        (Input_Paths, Archive_Path, Entry_Names, Status);
      Assert (Status = Zlib.Ok, "LZMA file-list metadata status");
      Check_Archive ("LZMA file-list metadata");

      Delete_If_Exists (Archive_Path);
      Zlib.Seven_Zip_LZMA2_Files
        (Input_Paths, Archive_Path, Entry_Names, Status);
      Assert (Status = Zlib.Ok, "LZMA2 file-list metadata status");
      Check_Archive ("LZMA2 file-list metadata");

      Delete_If_Exists (First_Path);
      Delete_If_Exists (Second_Path);
      Delete_If_Exists (Archive_Path);
   exception
      when others =>
         Delete_If_Exists (First_Path);
         Delete_If_Exists (Second_Path);
         Delete_If_Exists (Archive_Path);
         raise;
   end Test_File_List_Creation_Preserves_Source_Metadata;

   procedure Test_Extract_Accepts_SFX_Prefixed_Archive
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status  : Zlib.Status_Code := Zlib.Ok;
      Archive : constant Zlib.Byte_Array :=
        Zlib.Seven_Zip_Stored (Payload, "payload.txt", Status);
      Prefix  : constant Zlib.Byte_Array :=
        [16#4D#, 16#5A#, 16#90#, 0, 3, 0, 0, 0,
         16#37#, 16#7A#, 16#BC#, 16#AF#, 16#27#, 16#1C#, 0, 4,
         0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
         0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
         16#50#, 16#45#, 0, 0];
      SFX     : constant Zlib.Byte_Array := Prefix & Archive;
   begin
      Assert (Status = Zlib.Ok, "SFX-prefixed fixture archive creation");

      declare
         Plain : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (SFX, "payload.txt", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z extraction accepts SFX-prefixed archives");
         Assert
           (Plain = Payload,
            "native 7z SFX-prefixed extraction preserves payload");
      end;

      declare
         Plain : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip_Stored (SFX, "payload.txt", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native stored 7z extraction accepts SFX-prefixed archives");
         Assert
           (Plain = Payload,
            "native stored 7z SFX-prefixed extraction preserves payload");
      end;
   end Test_Extract_Accepts_SFX_Prefixed_Archive;

   procedure Test_Extract_Accepts_Directory_Entries
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Status       : Zlib.Status_Code := Zlib.Ok;
      Base_Archive : constant Zlib.Byte_Array :=
        Zlib.Seven_Zip_Stored (Payload, "payload.txt", Status);
      Archive_Path : constant String := Base_Path ("directory-entry.7z");
      Output_Path  : constant String := Base_Path ("directory-entry.single");
      Output_Dir   : constant String := Base_Path ("directory-entry.out");
      File_Count_Pos : Natural := 0;
      Name_Size_Pos  : Natural := 0;
      Name_Data_First : Natural := 0;
      Old_Name_Size : Natural := 0;
      Dir_Name_Field : constant Zlib.Byte_Array :=
        [16#64#, 0, 16#69#, 0, 16#72#, 0, 16#2F#, 0, 0, 0];
      Empty_Props : constant Zlib.Byte_Array :=
        [16#0E#, 1, 16#80#, 16#0F#, 1, 0];
   begin
      Assert (Status = Zlib.Ok, "directory-entry fixture base archive creation");
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Path);
      Delete_If_Exists (Output_Dir);

      File_Count_Pos := Find_Seven_Zip_Files_Info (Base_Archive);
      if File_Count_Pos /= 0 then
         File_Count_Pos := File_Count_Pos + 1;
         Name_Size_Pos := File_Count_Pos + 2;
         Name_Data_First := File_Count_Pos + 3;
         Old_Name_Size := Natural (Base_Archive (Name_Size_Pos));
      end if;
      Assert (File_Count_Pos /= 0, "directory-entry FilesInfo count found");

      declare
         With_Dir_Name : Zlib.Byte_Array :=
           Insert_Seven_Zip_Header_Bytes
             (Base_Archive, Name_Data_First + 1, Dir_Name_Field);
      begin
         With_Dir_Name (File_Count_Pos) := 2;
         With_Dir_Name (Name_Size_Pos) :=
           Zlib.Byte (Old_Name_Size + Dir_Name_Field'Length);
         Refresh_Seven_Zip_Header_CRCs (With_Dir_Name);

         declare
            With_Directory : constant Zlib.Byte_Array :=
              Insert_Seven_Zip_Header_Bytes
                (With_Dir_Name,
                 Name_Data_First + Old_Name_Size + Dir_Name_Field'Length,
                 Empty_Props);
         begin
            declare
               Plain : constant Zlib.Byte_Array :=
                 Zlib.Extract_Seven_Zip
                   (With_Directory, "payload.txt", Status);
            begin
               Assert
                 (Status = Zlib.Ok,
                  "native 7z directory-entry archive extracts file payload");
               Assert
                 (Plain = Payload,
                  "native 7z directory-entry archive preserves file payload");
            end;

            declare
               Dir_Payload : constant Zlib.Byte_Array :=
                 Zlib.Extract_Seven_Zip
                   (With_Directory, "dir/", Status);
            begin
               Assert
                 (Status = Zlib.Ok,
                  "native 7z directory entry extracts as empty payload");
               Assert
                 (Dir_Payload'Length = 0,
                  "native 7z directory entry has no file payload");
            end;

            Write_File (Archive_Path, With_Directory);
            Zlib.Extract_Seven_Zip_Stored_File
              (Archive_Path, Output_Path, "dir/", Status);
            Assert
              (Status = Zlib.Ok,
               "native 7z directory-entry single extraction status");
            Assert
              (Ada.Directories.Exists (Output_Path)
               and then Ada.Directories.Kind (Output_Path) =
                 Ada.Directories.Directory,
               "native 7z directory-entry single extraction creates directory");

            Zlib.Extract_Seven_Zip_Stored_Files
              (Archive_Path, Output_Dir,
               [US.To_Unbounded_String ("dir/"),
                US.To_Unbounded_String ("payload.txt")],
               Status);
            Assert
              (Status = Zlib.Ok,
               "native 7z directory-entry file-list extraction status");
            Assert
              (Ada.Directories.Exists
                 (Ada.Directories.Compose (Output_Dir, "dir"))
               and then Ada.Directories.Kind
                 (Ada.Directories.Compose (Output_Dir, "dir")) =
                   Ada.Directories.Directory,
               "native 7z directory-entry extraction creates directory");
            Assert
              (Read_File
                 (Ada.Directories.Compose (Output_Dir, "payload.txt")) =
                 Payload,
               "native 7z directory-entry file-list extraction writes payload");
         end;
      end;

      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Path);
      Delete_If_Exists (Output_Dir);
   exception
      when others =>
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Path);
         Delete_If_Exists (Output_Dir);
         raise;
   end Test_Extract_Accepts_Directory_Entries;

   procedure Test_Extract_Accepts_Solid_Copy_Substreams
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      First_Data  : constant Zlib.Byte_Array :=
        [16#66#, 16#69#, 16#72#, 16#73#, 16#74#, 16#2D#, 16#64#, 16#61#, 16#74#, 16#61#];
      Second_Data : constant Zlib.Byte_Array :=
        [16#73#, 16#65#, 16#63#, 16#6F#, 16#6E#, 16#64#, 16#2D#, 16#64#, 16#61#, 16#74#, 16#61#];
      Archive     : constant Zlib.Byte_Array :=
        Seven_Zip_Solid_Substream_Archive
          ("first.txt", First_Data, "second.txt", Second_Data);
      Status      : Zlib.Status_Code := Zlib.Ok;
      Archive_Path : constant String := Base_Path ("solid-copy-substreams.7z");
      Output_Dir   : constant String := Base_Path ("solid-copy-substreams.out");
      Second_CRC_Pos : Natural := 0;
   begin
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);

      declare
         First_Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "first.txt", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z solid Copy substream extracts first file");
         Assert
           (First_Output = First_Data,
            "native 7z solid Copy substream preserves first file");
      end;

      declare
         Second_Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "second.txt", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z solid Copy substream extracts second file");
         Assert
           (Second_Output = Second_Data,
            "native 7z solid Copy substream preserves second file");
      end;

      Write_File (Archive_Path, Archive);
      Zlib.Extract_Seven_Zip_Stored_Files
        (Archive_Path, Output_Dir,
         [US.To_Unbounded_String ("first.txt"),
          US.To_Unbounded_String ("second.txt")],
         Status);
      Assert
        (Status = Zlib.Ok,
         "native 7z solid Copy file-list extraction status");
      Assert
        (Read_File (Ada.Directories.Compose (Output_Dir, "first.txt")) =
           First_Data,
         "native 7z solid Copy file-list extraction writes first file");
      Assert
        (Read_File (Ada.Directories.Compose (Output_Dir, "second.txt")) =
           Second_Data,
         "native 7z solid Copy file-list extraction writes second file");

      for Pos in Seven_Zip_Header_First (Archive) .. Archive'Last - 3 loop
         if U32_LE (Archive, Pos) = Zlib.CRC32 (Second_Data) then
            Second_CRC_Pos := Pos;
            exit;
         end if;
      end loop;

      Assert
        (Second_CRC_Pos /= 0,
         "native 7z solid Copy fixture has second substream CRC");

      declare
         Corrupt_CRC : Zlib.Byte_Array := Archive;
      begin
         Corrupt_CRC (Second_CRC_Pos) :=
           Corrupt_CRC (Second_CRC_Pos) xor 16#01#;
         Refresh_Seven_Zip_Header_CRCs (Corrupt_CRC);

         declare
            First_Output : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip (Corrupt_CRC, "first.txt", Status);
         begin
            Assert
              (Status = Zlib.Ok,
               "native 7z solid Copy substream CRC is target-specific");
            Assert
              (First_Output = First_Data,
               "native 7z solid Copy substream CRC preserves other entries");
         end;

         declare
            Second_Output : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip (Corrupt_CRC, "second.txt", Status);
         begin
            Assert
              (Status = Zlib.Invalid_Checksum,
               "native 7z solid Copy substream rejects bad substream CRC");
            Assert
              (Second_Output'Length = 0,
               "native 7z solid Copy bad substream CRC returns no payload");
         end;
      end;

      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);
   exception
      when others =>
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);
         raise;
   end Test_Extract_Accepts_Solid_Copy_Substreams;

   procedure Test_Extract_Accepts_Solid_Deflate_Substreams
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      First_Data  : constant Zlib.Byte_Array (1 .. 24) := [others => 16#61#];
      Second_Data : constant Zlib.Byte_Array (1 .. 24) := [others => 16#62#];
      Archive     : constant Zlib.Byte_Array :=
        Seven_Zip_Solid_Substream_Archive
          ("first.txt", First_Data, "second.txt", Second_Data,
           Solid_Deflate_Method);
      Status      : Zlib.Status_Code := Zlib.Ok;
      Archive_Path : constant String :=
        Base_Path ("solid-deflate-substreams.7z");
      Output_Dir   : constant String :=
        Base_Path ("solid-deflate-substreams.out");
   begin
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);

      declare
         First_Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "first.txt", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z solid Deflate substream extracts first file");
         Assert
           (First_Output = First_Data,
            "native 7z solid Deflate substream preserves first file");
      end;

      declare
         Second_Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "second.txt", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z solid Deflate substream extracts second file");
         Assert
           (Second_Output = Second_Data,
            "native 7z solid Deflate substream preserves second file");
      end;

      Write_File (Archive_Path, Archive);
      Zlib.Extract_Seven_Zip_Stored_Files
        (Archive_Path, Output_Dir,
         [US.To_Unbounded_String ("first.txt"),
          US.To_Unbounded_String ("second.txt")],
         Status);
      Assert
        (Status = Zlib.Ok,
         "native 7z solid Deflate file-list extraction status");
      Assert
        (Read_File (Ada.Directories.Compose (Output_Dir, "first.txt")) =
           First_Data,
         "native 7z solid Deflate file-list extraction writes first file");
      Assert
        (Read_File (Ada.Directories.Compose (Output_Dir, "second.txt")) =
           Second_Data,
         "native 7z solid Deflate file-list extraction writes second file");

      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);
   exception
      when others =>
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);
         raise;
   end Test_Extract_Accepts_Solid_Deflate_Substreams;

   procedure Test_Extract_Accepts_Solid_BZip2_Substreams
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      First_Data  : constant Zlib.Byte_Array (1 .. 18) := [others => 16#42#];
      Second_Data : constant Zlib.Byte_Array (1 .. 18) := [others => 16#5A#];
      Archive     : constant Zlib.Byte_Array :=
        Seven_Zip_Solid_Substream_Archive
          ("first.txt", First_Data, "second.txt", Second_Data,
           Solid_BZip2_Method);
      Status      : Zlib.Status_Code := Zlib.Ok;
      Archive_Path : constant String :=
        Base_Path ("solid-bzip2-substreams.7z");
      Output_Dir   : constant String :=
        Base_Path ("solid-bzip2-substreams.out");
   begin
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);

      declare
         First_Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "first.txt", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z solid BZip2 substream extracts first file");
         Assert
           (First_Output = First_Data,
            "native 7z solid BZip2 substream preserves first file");
      end;

      declare
         Second_Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "second.txt", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z solid BZip2 substream extracts second file");
         Assert
           (Second_Output = Second_Data,
            "native 7z solid BZip2 substream preserves second file");
      end;

      Write_File (Archive_Path, Archive);
      Zlib.Extract_Seven_Zip_Stored_Files
        (Archive_Path, Output_Dir,
         [US.To_Unbounded_String ("first.txt"),
          US.To_Unbounded_String ("second.txt")],
         Status);
      Assert
        (Status = Zlib.Ok,
         "native 7z solid BZip2 file-list extraction status");
      Assert
        (Read_File (Ada.Directories.Compose (Output_Dir, "first.txt")) =
           First_Data,
         "native 7z solid BZip2 file-list extraction writes first file");
      Assert
        (Read_File (Ada.Directories.Compose (Output_Dir, "second.txt")) =
           Second_Data,
         "native 7z solid BZip2 file-list extraction writes second file");

      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);
   exception
      when others =>
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);
         raise;
   end Test_Extract_Accepts_Solid_BZip2_Substreams;

   procedure Test_Extract_Accepts_Solid_LZMA_Substreams
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      First_Data  : constant Zlib.Byte_Array (1 .. 20) := [others => 16#4C#];
      Second_Data : constant Zlib.Byte_Array (1 .. 20) := [others => 16#5A#];
      Archive     : constant Zlib.Byte_Array :=
        Seven_Zip_Solid_Substream_Archive
          ("first.txt", First_Data, "second.txt", Second_Data,
           Solid_LZMA_Method);
      Status      : Zlib.Status_Code := Zlib.Ok;
      Archive_Path : constant String :=
        Base_Path ("solid-lzma-substreams.7z");
      Output_Dir   : constant String :=
        Base_Path ("solid-lzma-substreams.out");
   begin
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);

      declare
         First_Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "first.txt", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z solid LZMA substream extracts first file");
         Assert
           (First_Output = First_Data,
            "native 7z solid LZMA substream preserves first file");
      end;

      declare
         Second_Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "second.txt", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z solid LZMA substream extracts second file");
         Assert
           (Second_Output = Second_Data,
            "native 7z solid LZMA substream preserves second file");
      end;

      Write_File (Archive_Path, Archive);
      Zlib.Extract_Seven_Zip_Stored_Files
        (Archive_Path, Output_Dir,
         [US.To_Unbounded_String ("first.txt"),
          US.To_Unbounded_String ("second.txt")],
         Status);
      Assert
        (Status = Zlib.Ok,
         "native 7z solid LZMA file-list extraction status");
      Assert
        (Read_File (Ada.Directories.Compose (Output_Dir, "first.txt")) =
           First_Data,
         "native 7z solid LZMA file-list extraction writes first file");
      Assert
        (Read_File (Ada.Directories.Compose (Output_Dir, "second.txt")) =
           Second_Data,
         "native 7z solid LZMA file-list extraction writes second file");

      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);
   exception
      when others =>
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);
         raise;
   end Test_Extract_Accepts_Solid_LZMA_Substreams;

   procedure Test_Extract_Accepts_Solid_LZMA2_Substreams
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      First_Data  : constant Zlib.Byte_Array (1 .. 16) := [others => 16#6C#];
      Second_Data : constant Zlib.Byte_Array (1 .. 16) := [others => 16#7A#];
      Archive     : constant Zlib.Byte_Array :=
        Seven_Zip_Solid_Substream_Archive
          ("first.txt", First_Data, "second.txt", Second_Data,
           Solid_LZMA2_Method);
      Status      : Zlib.Status_Code := Zlib.Ok;
      Archive_Path : constant String :=
        Base_Path ("solid-lzma2-substreams.7z");
      Output_Dir   : constant String :=
        Base_Path ("solid-lzma2-substreams.out");
   begin
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);

      declare
         First_Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "first.txt", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z solid LZMA2 substream extracts first file");
         Assert
           (First_Output = First_Data,
            "native 7z solid LZMA2 substream preserves first file");
      end;

      declare
         Second_Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "second.txt", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z solid LZMA2 substream extracts second file");
         Assert
           (Second_Output = Second_Data,
            "native 7z solid LZMA2 substream preserves second file");
      end;

      Write_File (Archive_Path, Archive);
      Zlib.Extract_Seven_Zip_Stored_Files
        (Archive_Path, Output_Dir,
         [US.To_Unbounded_String ("first.txt"),
          US.To_Unbounded_String ("second.txt")],
         Status);
      Assert
        (Status = Zlib.Ok,
         "native 7z solid LZMA2 file-list extraction status");
      Assert
        (Read_File (Ada.Directories.Compose (Output_Dir, "first.txt")) =
           First_Data,
         "native 7z solid LZMA2 file-list extraction writes first file");
      Assert
        (Read_File (Ada.Directories.Compose (Output_Dir, "second.txt")) =
           Second_Data,
         "native 7z solid LZMA2 file-list extraction writes second file");

      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);
   exception
      when others =>
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);
         raise;
   end Test_Extract_Accepts_Solid_LZMA2_Substreams;

   procedure Test_Extract_Accepts_Solid_Delta_Substreams
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      First_Data  : constant Zlib.Byte_Array :=
        [16#10#, 16#12#, 16#17#, 16#20#, 16#2C#, 16#39#, 16#45#,
         16#52#];
      Second_Data : constant Zlib.Byte_Array :=
        [16#61#, 16#64#, 16#68#, 16#6D#, 16#73#, 16#7A#, 16#82#,
         16#8B#];
      Archive     : constant Zlib.Byte_Array :=
        Seven_Zip_Solid_Substream_Archive
          ("first.txt", First_Data, "second.txt", Second_Data,
           Solid_Delta_Method);
      Status      : Zlib.Status_Code := Zlib.Ok;
      Archive_Path : constant String :=
        Base_Path ("solid-delta-substreams.7z");
      Output_Dir   : constant String :=
        Base_Path ("solid-delta-substreams.out");
   begin
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);

      declare
         First_Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "first.txt", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z solid Delta substream extracts first file");
         Assert
           (First_Output = First_Data,
            "native 7z solid Delta substream preserves first file");
      end;

      declare
         Second_Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "second.txt", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z solid Delta substream extracts second file");
         Assert
           (Second_Output = Second_Data,
            "native 7z solid Delta substream preserves second file");
      end;

      Write_File (Archive_Path, Archive);
      Zlib.Extract_Seven_Zip_Stored_Files
        (Archive_Path, Output_Dir,
         [US.To_Unbounded_String ("first.txt"),
          US.To_Unbounded_String ("second.txt")],
         Status);
      Assert
        (Status = Zlib.Ok,
         "native 7z solid Delta file-list extraction status");
      Assert
        (Read_File (Ada.Directories.Compose (Output_Dir, "first.txt")) =
           First_Data,
         "native 7z solid Delta file-list extraction writes first file");
      Assert
        (Read_File (Ada.Directories.Compose (Output_Dir, "second.txt")) =
           Second_Data,
         "native 7z solid Delta file-list extraction writes second file");

      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);
   exception
      when others =>
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);
         raise;
   end Test_Extract_Accepts_Solid_Delta_Substreams;

   procedure Test_Extract_Accepts_Delta_Deflate_Filter_Chain
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      First_Data  : constant Zlib.Byte_Array :=
        [16#10#, 16#13#, 16#17#, 16#1C#, 16#22#, 16#29#, 16#31#,
         16#3A#, 16#44#, 16#4F#, 16#5B#, 16#68#];
      Second_Data : constant Zlib.Byte_Array :=
        [16#80#, 16#7C#, 16#79#, 16#77#, 16#76#, 16#76#, 16#77#,
         16#79#, 16#7C#, 16#80#, 16#85#, 16#8B#];
      Archive     : constant Zlib.Byte_Array :=
        Seven_Zip_Solid_Substream_Archive
          ("first.bin", First_Data, "second.bin", Second_Data,
           Solid_Delta_Deflate_Method);
      Status      : Zlib.Status_Code := Zlib.Ok;
      Archive_Path : constant String :=
        Base_Path ("delta-deflate-filter-chain.7z");
      Output_Dir   : constant String :=
        Base_Path ("delta-deflate-filter-chain.out");
   begin
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);

      declare
         First_Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "first.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z Delta+Deflate filter chain extracts first file");
         Assert
           (First_Output = First_Data,
            "native 7z Delta+Deflate filter chain preserves first file");
      end;

      declare
         Second_Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "second.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z Delta+Deflate filter chain extracts second file");
         Assert
           (Second_Output = Second_Data,
            "native 7z Delta+Deflate filter chain preserves second file");
      end;

      Write_File (Archive_Path, Archive);
      Zlib.Extract_Seven_Zip_Files
        (Archive_Path, Output_Dir,
         [US.To_Unbounded_String ("first.bin"),
          US.To_Unbounded_String ("second.bin")],
         Status);
      Assert
        (Status = Zlib.Ok,
         "native 7z Delta+Deflate filter-chain file-list extraction status");
      Assert
        (Read_File (Ada.Directories.Compose (Output_Dir, "first.bin")) =
           First_Data,
         "native 7z Delta+Deflate file-list extraction writes first file");
      Assert
        (Read_File (Ada.Directories.Compose (Output_Dir, "second.bin")) =
           Second_Data,
         "native 7z Delta+Deflate file-list extraction writes second file");

      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);
   exception
      when others =>
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);
         raise;
   end Test_Extract_Accepts_Delta_Deflate_Filter_Chain;

   procedure Test_Extract_Accepts_BCJ_Delta_Deflate_Filter_Chain
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      First_Data  : constant Zlib.Byte_Array :=
        [16#90#, 16#E8#, 16#10#, 16#00#, 16#00#, 16#00#,
         16#90#, 16#E9#, 16#20#, 16#00#, 16#00#, 16#00#];
      Second_Data : constant Zlib.Byte_Array :=
        [16#90#, 16#90#, 16#E8#, 16#40#, 16#00#, 16#00#,
         16#00#, 16#90#, 16#E9#, 16#80#, 16#00#, 16#00#,
         16#00#];
      Archive     : constant Zlib.Byte_Array :=
        Seven_Zip_Solid_Substream_Archive
          ("first.bin", First_Data, "second.bin", Second_Data,
           Solid_BCJ_Delta_Deflate_Method);
      Status      : Zlib.Status_Code := Zlib.Ok;
      Archive_Path : constant String :=
        Base_Path ("bcj-delta-deflate-filter-chain.7z");
      Output_Dir   : constant String :=
        Base_Path ("bcj-delta-deflate-filter-chain.out");
   begin
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);

      declare
         First_Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "first.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z BCJ+Delta+Deflate filter chain extracts first file");
         Assert
           (First_Output = First_Data,
            "native 7z BCJ+Delta+Deflate filter chain preserves first file");
      end;

      declare
         Second_Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "second.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z BCJ+Delta+Deflate filter chain extracts second file");
         Assert
           (Second_Output = Second_Data,
            "native 7z BCJ+Delta+Deflate filter chain preserves second file");
      end;

      Write_File (Archive_Path, Archive);
      Zlib.Extract_Seven_Zip_Files
        (Archive_Path, Output_Dir,
         [US.To_Unbounded_String ("first.bin"),
          US.To_Unbounded_String ("second.bin")],
         Status);
      Assert
        (Status = Zlib.Ok,
         "native 7z BCJ+Delta+Deflate filter-chain file-list extraction status");
      Assert
        (Read_File (Ada.Directories.Compose (Output_Dir, "first.bin")) =
           First_Data,
         "native 7z BCJ+Delta+Deflate file-list extraction writes first file");
      Assert
        (Read_File (Ada.Directories.Compose (Output_Dir, "second.bin")) =
           Second_Data,
         "native 7z BCJ+Delta+Deflate file-list extraction writes second file");

      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);
   exception
      when others =>
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);
         raise;
   end Test_Extract_Accepts_BCJ_Delta_Deflate_Filter_Chain;

   procedure Test_Extract_Accepts_Reordered_Linear_Bind_Pairs
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      First_Data  : constant Zlib.Byte_Array :=
        [16#90#, 16#E8#, 16#10#, 16#00#, 16#00#, 16#00#,
         16#90#, 16#E9#, 16#20#, 16#00#, 16#00#, 16#00#];
      Second_Data : constant Zlib.Byte_Array :=
        [16#90#, 16#90#, 16#E8#, 16#40#, 16#00#, 16#00#,
         16#00#, 16#90#, 16#E9#, 16#80#, 16#00#, 16#00#,
         16#00#];
      Archive     : Zlib.Byte_Array :=
        Seven_Zip_Solid_Substream_Archive
          ("first.bin", First_Data, "second.bin", Second_Data,
           Solid_BCJ_Delta_Deflate_Method);
      Status      : Zlib.Status_Code := Zlib.Ok;
      Pattern_Pos : Natural := 0;
   begin
      for Pos in Seven_Zip_Header_First (Archive) .. Archive'Last - 16 loop
         if Archive (Pos) = 3
           and then Archive (Pos + 1) = 16#04#
           and then Archive (Pos + 2) = 16#01#
           and then Archive (Pos + 3) = 16#08#
           and then Archive (Pos + 4) = 16#21#
           and then Archive (Pos + 5) = 16#03#
           and then Archive (Pos + 6) = 1
           and then Archive (Pos + 7) = 0
           and then Archive (Pos + 8) = 4
           and then Archive (Pos + 9) = 16#03#
           and then Archive (Pos + 10) = 16#03#
           and then Archive (Pos + 11) = 16#01#
           and then Archive (Pos + 12) = 16#03#
           and then Archive (Pos + 13) = 2
           and then Archive (Pos + 14) = 1
           and then Archive (Pos + 15) = 3
           and then Archive (Pos + 16) = 2
         then
            Pattern_Pos := Pos;
            exit;
         end if;
      end loop;

      Assert
        (Pattern_Pos /= 0,
         "BCJ+Delta+Deflate fixture exposes its bind pairs");

      --  Reordered zero-based bind pairs (InIndex, OutIndex), listed out of
      --  chain order: (2,1) then (1,0). They describe coder0->coder1->coder2,
      --  so coder0 stays the packed coder. Standard order would be (1,0)(2,1);
      --  here the pairs are swapped to exercise out-of-order bind handling.
      Archive (Pattern_Pos + 13) := 2;
      Archive (Pattern_Pos + 14) := 1;
      Archive (Pattern_Pos + 15) := 1;
      Archive (Pattern_Pos + 16) := 0;
      Refresh_Seven_Zip_Header_CRCs (Archive);

      declare
         First_Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "first.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z reordered bind pairs extract first file: "
            & Zlib.Status_Code'Image (Status));
         Assert
           (First_Output = First_Data,
            "native 7z reordered bind pairs preserve first file");
      end;

      declare
         Second_Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "second.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z reordered bind pairs extract second file: "
            & Zlib.Status_Code'Image (Status));
         Assert
           (Second_Output = Second_Data,
            "native 7z reordered bind pairs preserve second file");
      end;
   end Test_Extract_Accepts_Reordered_Linear_Bind_Pairs;

   procedure Test_Extract_Accepts_Reordered_Legacy_Bind_Pairs
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      First_Data  : constant Zlib.Byte_Array :=
        [16#90#, 16#E8#, 16#10#, 16#00#, 16#00#, 16#00#,
         16#90#, 16#E9#, 16#20#, 16#00#, 16#00#, 16#00#];
      Second_Data : constant Zlib.Byte_Array :=
        [16#90#, 16#90#, 16#E8#, 16#40#, 16#00#, 16#00#,
         16#00#, 16#90#, 16#E9#, 16#80#, 16#00#, 16#00#,
         16#00#];
      Archive     : Zlib.Byte_Array :=
        Seven_Zip_Solid_Substream_Archive
          ("first.bin", First_Data, "second.bin", Second_Data,
           Solid_BCJ_Delta_Deflate_Method);
      Status      : Zlib.Status_Code := Zlib.Ok;
      Pattern_Pos : Natural := 0;
   begin
      for Pos in Seven_Zip_Header_First (Archive) .. Archive'Last - 16 loop
         if Archive (Pos) = 3
           and then Archive (Pos + 1) = 16#04#
           and then Archive (Pos + 2) = 16#01#
           and then Archive (Pos + 3) = 16#08#
           and then Archive (Pos + 4) = 16#21#
           and then Archive (Pos + 5) = 16#03#
           and then Archive (Pos + 6) = 1
           and then Archive (Pos + 7) = 0
           and then Archive (Pos + 8) = 4
           and then Archive (Pos + 9) = 16#03#
           and then Archive (Pos + 10) = 16#03#
           and then Archive (Pos + 11) = 16#01#
           and then Archive (Pos + 12) = 16#03#
           and then Archive (Pos + 13) = 2
           and then Archive (Pos + 14) = 1
           and then Archive (Pos + 15) = 3
           and then Archive (Pos + 16) = 2
         then
            Pattern_Pos := Pos;
            exit;
         end if;
      end loop;

      Assert
        (Pattern_Pos /= 0,
         "BCJ+Delta+Deflate fixture exposes legacy bind pairs");

      Archive (Pattern_Pos + 13) := 3;
      Archive (Pattern_Pos + 14) := 2;
      Archive (Pattern_Pos + 15) := 2;
      Archive (Pattern_Pos + 16) := 1;
      Refresh_Seven_Zip_Header_CRCs (Archive);

      declare
         First_Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "first.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z reordered legacy bind pairs extract first file: "
            & Zlib.Status_Code'Image (Status));
         Assert
           (First_Output = First_Data,
            "native 7z reordered legacy bind pairs preserve first file");
      end;

      declare
         Second_Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "second.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z reordered legacy bind pairs extract second file: "
            & Zlib.Status_Code'Image (Status));
         Assert
           (Second_Output = Second_Data,
            "native 7z reordered legacy bind pairs preserve second file");
      end;
   end Test_Extract_Accepts_Reordered_Legacy_Bind_Pairs;

   procedure Test_Extract_Accepts_Copy_Deflate_Filter_Chain
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      First_Data  : constant Zlib.Byte_Array (1 .. 20) := [others => 16#43#];
      Second_Data : constant Zlib.Byte_Array (1 .. 20) := [others => 16#44#];
      Archive     : constant Zlib.Byte_Array :=
        Seven_Zip_Solid_Substream_Archive
          ("first.bin", First_Data, "second.bin", Second_Data,
           Solid_Copy_Deflate_Method);
      Status      : Zlib.Status_Code := Zlib.Ok;
      Archive_Path : constant String :=
        Base_Path ("copy-deflate-filter-chain.7z");
      Output_Dir   : constant String :=
        Base_Path ("copy-deflate-filter-chain.out");
   begin
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);

      declare
         First_Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "first.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z Copy+Deflate filter chain extracts first file");
         Assert
           (First_Output = First_Data,
            "native 7z Copy+Deflate filter chain preserves first file");
      end;

      declare
         Second_Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "second.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z Copy+Deflate filter chain extracts second file");
         Assert
           (Second_Output = Second_Data,
            "native 7z Copy+Deflate filter chain preserves second file");
      end;

      Write_File (Archive_Path, Archive);
      Zlib.Extract_Seven_Zip_Files
        (Archive_Path, Output_Dir,
         [US.To_Unbounded_String ("first.bin"),
          US.To_Unbounded_String ("second.bin")],
         Status);
      Assert
        (Status = Zlib.Ok,
         "native 7z Copy+Deflate filter-chain file-list extraction status");
      Assert
        (Read_File (Ada.Directories.Compose (Output_Dir, "first.bin")) =
           First_Data,
         "native 7z Copy+Deflate file-list extraction writes first file");
      Assert
        (Read_File (Ada.Directories.Compose (Output_Dir, "second.bin")) =
           Second_Data,
         "native 7z Copy+Deflate file-list extraction writes second file");

      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);
   exception
      when others =>
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);
         raise;
   end Test_Extract_Accepts_Copy_Deflate_Filter_Chain;

   procedure Test_Extract_Accepts_Standard_Copy_Deflate_Bind_Pair
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      First_Data   : constant Zlib.Byte_Array :=
        [16#66#, 16#69#, 16#72#, 16#73#, 16#74#, 16#2D#, 16#7A#, 16#65#, 16#72#, 16#6F#];
      Second_Data  : constant Zlib.Byte_Array :=
        [16#73#, 16#65#, 16#63#, 16#6F#, 16#6E#, 16#64#, 16#2D#, 16#7A#, 16#65#, 16#72#, 16#6F#];
      Archive      : Zlib.Byte_Array :=
        Seven_Zip_Solid_Substream_Archive
          ("first.bin", First_Data, "second.bin", Second_Data,
           Solid_Copy_Deflate_Method);
      Status       : Zlib.Status_Code := Zlib.Ok;
      Pattern_Pos  : Natural := 0;
   begin
      for Pos in Seven_Zip_Header_First (Archive) .. Archive'Last - 6 loop
         if Archive (Pos) = 16#04#
           and then Archive (Pos + 1) = 16#01#
           and then Archive (Pos + 2) = 16#08#
           and then Archive (Pos + 3) = 16#01#
           and then Archive (Pos + 4) = 16#00#
           and then Archive (Pos + 5) = 16#02#
           and then Archive (Pos + 6) = 16#01#
         then
            Pattern_Pos := Pos;
            exit;
         end if;
      end loop;

      Assert
        (Pattern_Pos /= 0,
         "Copy+Deflate fixture exposes its historical bind pair");

      --  Standard zero-based 7z bind pair is (InIndex, OutIndex) = (1, 0):
      --  coder0's output feeds coder1's input, so coder0 is the packed coder.
      --  (This matches what stock 7z emits; see Folder_Packed_Coder analysis.)
      Archive (Pattern_Pos + 5) := 1;
      Archive (Pattern_Pos + 6) := 0;
      Refresh_Seven_Zip_Header_CRCs (Archive);

      declare
         First_Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "first.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z Copy+Deflate standard bind pair extracts first file");
         Assert
           (First_Output = First_Data,
            "native 7z Copy+Deflate standard bind pair preserves first file");
      end;

      declare
         Second_Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "second.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z Copy+Deflate standard bind pair extracts second file");
         Assert
           (Second_Output = Second_Data,
            "native 7z Copy+Deflate standard bind pair preserves second file");
      end;
   end Test_Extract_Accepts_Standard_Copy_Deflate_Bind_Pair;

   procedure Test_Extract_Accepts_Reverse_BCJ_Copy_Bind_Pair
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      First_Data   : constant Zlib.Byte_Array :=
        [16#90#, 16#E8#, 16#10#, 16#00#, 16#00#, 16#00#,
         16#90#, 16#E9#, 16#20#, 16#00#, 16#00#, 16#00#];
      Second_Data  : constant Zlib.Byte_Array :=
        [16#90#, 16#90#, 16#E8#, 16#40#, 16#00#, 16#00#,
         16#00#, 16#90#, 16#E9#, 16#80#, 16#00#, 16#00#,
         16#00#];
      Archive      : Zlib.Byte_Array :=
        Seven_Zip_Solid_Substream_Archive
          ("first.bin", First_Data, "second.bin", Second_Data,
           Solid_BCJ_Copy_Method);
      Status       : Zlib.Status_Code := Zlib.Ok;
      Pattern_Pos  : Natural := 0;
   begin
      for Pos in Seven_Zip_Header_First (Archive) .. Archive'Last - 8 loop
         if Archive (Pos) = 16#01#
           and then Archive (Pos + 1) = 16#00#
           and then Archive (Pos + 2) = 16#04#
           and then Archive (Pos + 3) = 16#03#
           and then Archive (Pos + 4) = 16#03#
           and then Archive (Pos + 5) = 16#01#
           and then Archive (Pos + 6) = 16#03#
           and then Archive (Pos + 7) = 16#02#
           and then Archive (Pos + 8) = 16#01#
         then
            Pattern_Pos := Pos;
            exit;
         end if;
      end loop;

      Assert
        (Pattern_Pos /= 0,
         "BCJ+Copy fixture exposes its historical bind pair");

      Archive (Pattern_Pos + 7) := 1;
      Archive (Pattern_Pos + 8) := 0;
      Refresh_Seven_Zip_Header_CRCs (Archive);

      declare
         First_Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "first.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z BCJ+Copy reverse bind pair extracts first file: "
            & Zlib.Status_Code'Image (Status));
         Assert
           (First_Output = First_Data,
            "native 7z BCJ+Copy reverse bind pair preserves first file");
      end;

      declare
         Second_Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "second.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z BCJ+Copy reverse bind pair extracts second file: "
            & Zlib.Status_Code'Image (Status));
         Assert
           (Second_Output = Second_Data,
            "native 7z BCJ+Copy reverse bind pair preserves second file");
      end;
   end Test_Extract_Accepts_Reverse_BCJ_Copy_Bind_Pair;

   procedure Test_Extract_Accepts_Solid_PPMd_Substreams
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      First_Data   : constant Zlib.Byte_Array (1 .. 16) := [others => Character'Pos ('a')];
      Second_Data  : constant Zlib.Byte_Array (1 .. 16) := [others => Character'Pos ('a')];
      Archive      : constant Zlib.Byte_Array :=
        Seven_Zip_Solid_PPMd_Repeated_Substream_Archive;
      Status       : Zlib.Status_Code := Zlib.Ok;
      Archive_Path : constant String :=
        Base_Path ("solid-ppmd-substreams.7z");
      Output_Dir   : constant String :=
        Base_Path ("solid-ppmd-substreams.out");
      Second_CRC_Pos : Natural := 0;
      CRC_Matches    : Natural := 0;
   begin
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);

      declare
         First_Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "first.txt", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z solid PPMd substream extracts first file");
         Assert
           (First_Output = First_Data,
            "native 7z solid PPMd substream preserves first file");
      end;

      declare
         Second_Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "second.txt", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z solid PPMd substream extracts second file");
         Assert
           (Second_Output = Second_Data,
            "native 7z solid PPMd substream preserves second file");
      end;

      Write_File (Archive_Path, Archive);
      Zlib.Extract_Seven_Zip_Files
        (Archive_Path, Output_Dir,
         [US.To_Unbounded_String ("first.txt"),
          US.To_Unbounded_String ("second.txt")],
         Status);
      Assert
        (Status = Zlib.Ok,
         "native 7z solid PPMd file-list extraction status");
      Assert
        (Read_File (Ada.Directories.Compose (Output_Dir, "first.txt")) =
           First_Data,
         "native 7z solid PPMd file-list extraction writes first file");
      Assert
        (Read_File (Ada.Directories.Compose (Output_Dir, "second.txt")) =
           Second_Data,
         "native 7z solid PPMd file-list extraction writes second file");

      for Pos in Seven_Zip_Header_First (Archive) .. Archive'Last - 3 loop
         if U32_LE (Archive, Pos) = Zlib.CRC32 (Second_Data) then
            CRC_Matches := CRC_Matches + 1;
            if CRC_Matches = 2 then
               Second_CRC_Pos := Pos;
               exit;
            end if;
         end if;
      end loop;

      Assert
        (Second_CRC_Pos /= 0,
         "native 7z solid PPMd fixture has second substream CRC");

      declare
         Corrupt_CRC : Zlib.Byte_Array := Archive;
      begin
         Corrupt_CRC (Second_CRC_Pos) :=
           Corrupt_CRC (Second_CRC_Pos) xor 16#01#;
         Refresh_Seven_Zip_Header_CRCs (Corrupt_CRC);

         declare
            First_Output : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip (Corrupt_CRC, "first.txt", Status);
         begin
            Assert
              (Status = Zlib.Ok,
               "native 7z solid PPMd substream CRC is target-specific");
            Assert
              (First_Output = First_Data,
               "native 7z solid PPMd substream CRC preserves other entries");
         end;

         declare
            Second_Output : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip (Corrupt_CRC, "second.txt", Status);
         begin
            Assert
              (Status = Zlib.Invalid_Checksum,
               "native 7z solid PPMd substream rejects bad substream CRC");
            Assert
              (Second_Output'Length = 0,
               "native 7z solid PPMd bad substream CRC returns no payload");
         end;

         Delete_If_Exists (Output_Dir);
         Write_File (Archive_Path, Corrupt_CRC);
         Zlib.Extract_Seven_Zip_Files
           (Archive_Path, Output_Dir,
            [1 => US.To_Unbounded_String ("first.txt")],
            Status);
         Assert
           (Status = Zlib.Ok,
            "native 7z solid PPMd file-list CRC is target-specific");
         Assert
           (Read_File (Ada.Directories.Compose (Output_Dir, "first.txt")) =
              First_Data,
            "native 7z solid PPMd file-list CRC preserves other entries");

         Delete_If_Exists (Output_Dir);
         Zlib.Extract_Seven_Zip_Files
           (Archive_Path, Output_Dir,
            [1 => US.To_Unbounded_String ("second.txt")],
            Status);
         Assert
           (Status = Zlib.Invalid_Checksum,
            "native 7z solid PPMd file-list rejects bad substream CRC");
         Assert
           (not Ada.Directories.Exists (Output_Dir),
            "native 7z solid PPMd bad file-list CRC writes no output");
      end;

      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);
   exception
      when others =>
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);
         raise;
   end Test_Extract_Accepts_Solid_PPMd_Substreams;

   procedure Test_Extract_Accepts_BCJ_Copy_Filter_Chain
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      First_Data  : constant Zlib.Byte_Array :=
        [16#90#, 16#E8#, 16#10#, 16#00#, 16#00#, 16#00#,
         16#90#, 16#E9#, 16#20#, 16#00#, 16#00#, 16#00#];
      Second_Data : constant Zlib.Byte_Array :=
        [16#90#, 16#90#, 16#E8#, 16#40#, 16#00#, 16#00#,
         16#00#, 16#90#, 16#E9#, 16#80#, 16#00#, 16#00#,
         16#00#];
      Archive     : constant Zlib.Byte_Array :=
        Seven_Zip_Solid_Substream_Archive
          ("first.bin", First_Data, "second.bin", Second_Data,
           Solid_BCJ_Copy_Method);
      Status      : Zlib.Status_Code := Zlib.Ok;
      Archive_Path : constant String :=
        Base_Path ("bcj-copy-filter-chain.7z");
      Output_Dir   : constant String :=
        Base_Path ("bcj-copy-filter-chain.out");
   begin
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);

      declare
         First_Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "first.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z BCJ+Copy filter chain extracts first file");
         Assert
           (First_Output = First_Data,
            "native 7z BCJ+Copy filter chain preserves first file");
      end;

      declare
         Second_Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "second.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z BCJ+Copy filter chain extracts second file");
         Assert
           (Second_Output = Second_Data,
            "native 7z BCJ+Copy filter chain preserves second file");
      end;

      Write_File (Archive_Path, Archive);
      Zlib.Extract_Seven_Zip_Stored_Files
        (Archive_Path, Output_Dir,
         [US.To_Unbounded_String ("first.bin"),
          US.To_Unbounded_String ("second.bin")],
         Status);
      Assert
        (Status = Zlib.Ok,
         "native 7z BCJ+Copy filter-chain file-list extraction status");
      Assert
        (Read_File (Ada.Directories.Compose (Output_Dir, "first.bin")) =
           First_Data,
         "native 7z BCJ+Copy file-list extraction writes first file");
      Assert
        (Read_File (Ada.Directories.Compose (Output_Dir, "second.bin")) =
           Second_Data,
         "native 7z BCJ+Copy file-list extraction writes second file");

      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);
   exception
      when others =>
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);
         raise;
   end Test_Extract_Accepts_BCJ_Copy_Filter_Chain;

   procedure Test_Extract_Accepts_BCJ2_Copy_Filter_Graph
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Unit_Data : constant Zlib.Byte_Array :=
        [16#90#, 16#E8#, 16#10#, 16#00#, 16#00#, 16#00#,
         16#90#, 16#E9#, 16#20#, 16#00#, 16#00#, 16#00#];
      Data : constant Zlib.Byte_Array :=
        Unit_Data & Unit_Data & Unit_Data & Unit_Data
        & Unit_Data & Unit_Data & Unit_Data & Unit_Data
        & Unit_Data & Unit_Data & Unit_Data & Unit_Data
        & Unit_Data & Unit_Data & Unit_Data & Unit_Data;
      Archive : constant Zlib.Byte_Array :=
        Seven_Zip_BCJ2_Copy_Archive ("bcj2.bin", Data);
      Status  : Zlib.Status_Code := Zlib.Ok;
   begin
      declare
         Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "bcj2.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z BCJ2+Copy filter graph extracts: "
            & Zlib.Status_Image (Status));
         Assert
           (Output = Data,
            "native 7z BCJ2+Copy filter graph preserves payload");
      end;
   end Test_Extract_Accepts_BCJ2_Copy_Filter_Graph;

   procedure Test_Extract_Accepts_BCJ2_Main_Pre_Coder_Graphs
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Unit_Data : constant Zlib.Byte_Array :=
        [16#90#, 16#E8#, 16#10#, 16#00#, 16#00#, 16#00#,
         16#90#, 16#E9#, 16#20#, 16#00#, 16#00#, 16#00#];
      Data : constant Zlib.Byte_Array :=
        Unit_Data & Unit_Data & Unit_Data & Unit_Data
        & Unit_Data & Unit_Data & Unit_Data & Unit_Data
        & Unit_Data & Unit_Data & Unit_Data & Unit_Data
        & Unit_Data & Unit_Data & Unit_Data & Unit_Data;
   begin
      for Method in BCJ2_Main_Deflate .. BCJ2_Main_PPMd loop
         declare
            Entry_Name : constant String :=
              "bcj2-" & BCJ2_Main_Pre_Coder'Image (Method) & ".bin";
            Archive : constant Zlib.Byte_Array :=
              Seven_Zip_BCJ2_Copy_Archive (Entry_Name, Data, Method);
            Status  : Zlib.Status_Code := Zlib.Ok;
            Output  : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip (Archive, Entry_Name, Status);
         begin
            Assert
              (Status = Zlib.Ok,
               "native 7z BCJ2 "
               & BCJ2_Main_Pre_Coder'Image (Method)
               & " main graph extracts: " & Zlib.Status_Image (Status));
            Assert
              (Output = Data,
               "native 7z BCJ2 "
               & BCJ2_Main_Pre_Coder'Image (Method)
               & " main graph preserves payload");
         end;
      end loop;
   end Test_Extract_Accepts_BCJ2_Main_Pre_Coder_Graphs;

   procedure Test_Extract_Accepts_Broader_PPMd_Stream
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Archive : constant Zlib.Byte_Array := Seven_Zip_PPMd_Archive;
      Expected : constant Zlib.Byte_Array :=
        [Character'Pos ('s'), Character'Pos ('e'), Character'Pos ('v'),
         Character'Pos ('e'), Character'Pos ('n'), Character'Pos (' '),
         Character'Pos ('z'), Character'Pos ('i'), Character'Pos ('p'),
         Character'Pos (' '), Character'Pos ('p'), Character'Pos ('p'),
         Character'Pos ('m'), Character'Pos ('d'), Character'Pos (' '),
         Character'Pos ('p'), Character'Pos ('r'), Character'Pos ('o'),
         Character'Pos ('b'), Character'Pos ('e'), Character'Pos (' '),
         Character'Pos ('p'), Character'Pos ('a'), Character'Pos ('y'),
         Character'Pos ('l'), Character'Pos ('o'), Character'Pos ('a'),
         Character'Pos ('d'), 10];
      Status  : Zlib.Status_Code := Zlib.Ok;
   begin
      declare
         Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "input.txt", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z broader PPMd stream extracts: "
            & Zlib.Status_Image (Status));
         Assert
           (Output = Expected,
            "native 7z broader PPMd stream returns original payload");
      end;
   end Test_Extract_Accepts_Broader_PPMd_Stream;

   procedure Test_Extract_Accepts_Broader_PPMd_Dash_Entry
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Archive : constant Zlib.Byte_Array := Seven_Zip_PPMd_Dash_Entry_Archive;
      Expected : constant Zlib.Byte_Array :=
        [Character'Pos ('s'), Character'Pos ('e'), Character'Pos ('v'),
         Character'Pos ('e'), Character'Pos ('n'), Character'Pos (' '),
         Character'Pos ('z'), Character'Pos ('i'), Character'Pos ('p'),
         Character'Pos (' '), Character'Pos ('p'), Character'Pos ('p'),
         Character'Pos ('m'), Character'Pos ('d'), Character'Pos (' '),
         Character'Pos ('p'), Character'Pos ('r'), Character'Pos ('o'),
         Character'Pos ('b'), Character'Pos ('e'), Character'Pos (' '),
         Character'Pos ('p'), Character'Pos ('a'), Character'Pos ('y'),
         Character'Pos ('l'), Character'Pos ('o'), Character'Pos ('a'),
         Character'Pos ('d'), 10];
      Status  : Zlib.Status_Code := Zlib.Ok;
   begin
      declare
         Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "-nput.txt", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z broader PPMd dash entry extracts: "
            & Zlib.Status_Image (Status));
         Assert
           (Output = Expected,
            "native 7z broader PPMd dash entry returns original payload");
      end;
   end Test_Extract_Accepts_Broader_PPMd_Dash_Entry;

   procedure Test_Extract_Rejects_Malformed_PPMd_Properties
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      procedure Assert_Rejected
        (Archive : Zlib.Byte_Array;
         Label   : String)
      is
         Status : Zlib.Status_Code := Zlib.Ok;
      begin
         declare
            Output : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip (Archive, "input.txt", Status);
         begin
            Assert
              (Status = Zlib.Unsupported_Method,
               "native 7z malformed PPMd properties fail closed: "
               & Label & ": " & Zlib.Status_Image (Status));
            Assert
              (Output'Length = 0,
               "native 7z malformed PPMd properties return empty output: "
               & Label);
         end;
      end Assert_Rejected;
   begin
      Assert_Rejected
        (Mutate_Seven_Zip_PPMd_Props (1, 16#0001_0000#),
         "order too small");
      Assert_Rejected
        (Mutate_Seven_Zip_PPMd_Props (65, 16#0001_0000#),
         "order too large");
      Assert_Rejected
        (Mutate_Seven_Zip_PPMd_Props (4, 0),
         "memory too small");
   end Test_Extract_Rejects_Malformed_PPMd_Properties;

   procedure Test_Extract_Rejects_Malformed_PPMd_Range_Header
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      procedure Assert_Rejected
        (Archive : Zlib.Byte_Array;
         Label   : String)
      is
         Status : Zlib.Status_Code := Zlib.Ok;
      begin
         declare
            Output : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip (Archive, "input.txt", Status);
         begin
            Assert
              (Status = Zlib.Invalid_Block_Type,
               "native 7z malformed PPMd range header fails as data: "
               & Label & ": " & Zlib.Status_Image (Status));
            Assert
              (Output'Length = 0,
               "native 7z malformed PPMd range header returns no output: "
               & Label);
         end;
      end Assert_Rejected;
   begin
      Assert_Rejected
        (Mutate_Seven_Zip_PPMd_Range_Header ([16#01#]),
         "non-zero marker");
      Assert_Rejected
        (Mutate_Seven_Zip_PPMd_Range_Header
           ([16#00#, 16#FF#, 16#FF#, 16#FF#, 16#FF#]),
         "saturated initial code");
   end Test_Extract_Rejects_Malformed_PPMd_Range_Header;

   procedure Test_Extract_Recognizes_Valid_PPMd_Range_Header
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Archive : constant Zlib.Byte_Array :=
        Mutate_Seven_Zip_PPMd_Range_Header
          ([16#00#, 16#00#, 16#00#, 16#00#, 16#00#]);
      Status  : Zlib.Status_Code := Zlib.Ok;
   begin
      declare
         Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "input.txt", Status);
      begin
         Assert
           (Status = Zlib.Invalid_Checksum,
            "native 7z valid PPMd range header fails closed after CRC check: "
            & Zlib.Status_Image (Status));
         Assert
           (Output'Length = 0,
            "native 7z valid PPMd range header returns no output on checksum failure");
      end;
   end Test_Extract_Recognizes_Valid_PPMd_Range_Header;

   procedure Test_Extract_Accepts_Empty_PPMd_Stream
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Archive : constant Zlib.Byte_Array := Seven_Zip_Empty_PPMd_Archive;
      Status  : Zlib.Status_Code := Zlib.Unsupported_Method;
   begin
      declare
         Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "empty.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z PPMd empty stream extracts: "
            & Zlib.Status_Image (Status));
         Assert
           (Output'Length = 0,
            "native 7z PPMd empty stream returns empty payload");
      end;
   end Test_Extract_Accepts_Empty_PPMd_Stream;

   procedure Test_Extract_Accepts_Empty_PPMd_Range_Header
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Archive : constant Zlib.Byte_Array :=
        Seven_Zip_Empty_PPMd_With_Range_Header;
      Status  : Zlib.Status_Code := Zlib.Ok;
   begin
      declare
         Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "empty.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z PPMd empty stream with range header extracts: "
            & Zlib.Status_Image (Status));
         Assert
           (Output = Zlib.Byte_Array'(1 .. 0 => 0),
            "native 7z PPMd empty stream with range header returns empty payload");
      end;
   end Test_Extract_Accepts_Empty_PPMd_Range_Header;

   procedure Test_Extract_Accepts_Repeated_PPMd_Stream
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Archive : constant Zlib.Byte_Array := Seven_Zip_PPMd_Repeated_Archive;
      Status  : Zlib.Status_Code := Zlib.Unsupported_Method;
      Expected : constant Zlib.Byte_Array (1 .. 32) := [others => Character'Pos ('a')];
   begin
      declare
         Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "zlib-ppmd-a.txt", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z PPMd repeated stream extracts: "
            & Zlib.Status_Image (Status));
         Assert
           (Output = Expected,
            "native 7z PPMd repeated stream returns original payload");
      end;
   end Test_Extract_Accepts_Repeated_PPMd_Stream;

   procedure Test_Extract_Accepts_Short_Repeated_PPMd_Stream
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Archive : constant Zlib.Byte_Array := Seven_Zip_PPMd_Short_Repeated_Archive;
      Status  : Zlib.Status_Code := Zlib.Unsupported_Method;
      Expected : constant Zlib.Byte_Array (1 .. 2) := [others => Character'Pos ('a')];
   begin
      declare
         Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "zlib-ppmd-aa2.txt", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z PPMd short repeated stream extracts: "
            & Zlib.Status_Image (Status));
         Assert
           (Output = Expected,
            "native 7z PPMd short repeated stream returns original payload");
      end;
   end Test_Extract_Accepts_Short_Repeated_PPMd_Stream;

   procedure Test_Extract_Accepts_Long_Repeated_PPMd_Stream
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Archive : constant Zlib.Byte_Array := Seven_Zip_PPMd_Long_Repeated_Archive;
      Status  : Zlib.Status_Code := Zlib.Unsupported_Method;
      Expected : constant Zlib.Byte_Array (1 .. 190) :=
        [others => Character'Pos ('a')];
   begin
      declare
         Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "zlib-ppmd-a190.txt", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z PPMd long repeated stream extracts: "
            & Zlib.Status_Image (Status));
         Assert
           (Output = Expected,
            "native 7z PPMd long repeated stream returns original payload");
      end;
   end Test_Extract_Accepts_Long_Repeated_PPMd_Stream;

   procedure Test_Extract_Accepts_Over_Boundary_Repeated_PPMd_Stream
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Archive : constant Zlib.Byte_Array :=
        Seven_Zip_PPMd_Over_Boundary_Repeated_Archive;
      Status  : Zlib.Status_Code := Zlib.Unsupported_Method;
      Expected : constant Zlib.Byte_Array (1 .. 191) :=
        [others => Character'Pos ('a')];
   begin
      declare
         Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "zlib-ppmd-a191.txt", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z PPMd over-boundary repeated stream extracts: "
            & Zlib.Status_Image (Status));
         Assert
           (Output = Expected,
            "native 7z PPMd over-boundary repeated stream returns original payload");
      end;
   end Test_Extract_Accepts_Over_Boundary_Repeated_PPMd_Stream;

   procedure Test_Extract_Accepts_Alternating_PPMd_Stream
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Archive : constant Zlib.Byte_Array := Seven_Zip_PPMd_Alternating_Archive;
      Status  : Zlib.Status_Code := Zlib.Unsupported_Method;
      Expected : constant Zlib.Byte_Array :=
        [Character'Pos ('a'), Character'Pos ('b'), Character'Pos ('c'),
         Character'Pos ('a'), Character'Pos ('b'), Character'Pos ('c'),
         Character'Pos ('a'), Character'Pos ('b'), Character'Pos ('c'),
         Character'Pos ('a'), Character'Pos ('b'), Character'Pos ('c'),
         Character'Pos ('a'), Character'Pos ('b'), Character'Pos ('c'),
         Character'Pos ('a'), Character'Pos ('b'), Character'Pos ('c'),
         Character'Pos ('a'), Character'Pos ('b'), Character'Pos ('c'),
         Character'Pos ('a'), Character'Pos ('b'), Character'Pos ('c'),
         Character'Pos ('a'), Character'Pos ('b'), Character'Pos ('c'),
         Character'Pos ('a'), Character'Pos ('b'), Character'Pos ('c'),
         Character'Pos ('a'), Character'Pos ('b'), Character'Pos ('c'),
         Character'Pos ('a'), Character'Pos ('b'), Character'Pos ('c')];
   begin
      declare
         Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "zlib-ppmd-abc.txt", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z PPMd alternating stream extracts: "
            & Zlib.Status_Image (Status));
         Assert
           (Output = Expected,
            "native 7z PPMd alternating stream returns original payload");
      end;
   end Test_Extract_Accepts_Alternating_PPMd_Stream;

   procedure Test_Extract_Accepts_Periodic_PPMd_Streams
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      procedure Assert_Periodic
        (Archive    : Zlib.Byte_Array;
         Entry_Name : String;
         Pattern    : String;
         Label      : String)
      is
         Status : Zlib.Status_Code := Zlib.Unsupported_Method;
      begin
         declare
            Output : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip (Archive, Entry_Name, Status);
         begin
            Assert
              (Status = Zlib.Ok,
               "native 7z PPMd periodic stream extracts " & Label & ": "
               & Zlib.Status_Image (Status));
            Assert
              (Output'Length = 40,
               "native 7z PPMd periodic stream length " & Label);

            for I in Output'Range loop
               declare
                  Pattern_Index : constant Positive :=
                    Pattern'First + ((I - Output'First) mod Pattern'Length);
               begin
                  Assert
                    (Output (I) = Character'Pos (Pattern (Pattern_Index)),
                     "native 7z PPMd periodic stream byte " & Label);
               end;
            end loop;
         end;
      end Assert_Periodic;
   begin
      Assert_Periodic
        (Seven_Zip_PPMd_AB_Periodic_Archive,
         "zlib-ppmd-ab-repeat.txt", "ab", "period 2");
      Assert_Periodic
        (Seven_Zip_PPMd_ABCD_Periodic_Archive,
         "zlib-ppmd-abcd-repeat.txt", "abcd", "period 4");
   end Test_Extract_Accepts_Periodic_PPMd_Streams;

   procedure Test_Extract_Rejects_Periodic_PPMd_Bad_Unpack_CRC
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Archive     : Zlib.Byte_Array := Seven_Zip_PPMd_ABCD_Periodic_Archive;
      Expected    : Zlib.Byte_Array (1 .. 40) := [others => 0];
      Expected_CRC : Interfaces.Unsigned_32;
      CRC_Pos     : Natural := 0;
      Status      : Zlib.Status_Code := Zlib.Ok;
      Pattern     : constant String := "abcd";
   begin
      for I in Expected'Range loop
         declare
            Pattern_Index : constant Positive :=
              Pattern'First + ((I - Expected'First) mod Pattern'Length);
         begin
            Expected (I) := Zlib.Byte (Character'Pos (Pattern (Pattern_Index)));
         end;
      end loop;

      Expected_CRC := Zlib.CRC32 (Expected);
      for Pos in Seven_Zip_Header_First (Archive) .. Archive'Last - 3 loop
         if U32_LE (Archive, Pos) = Expected_CRC then
            CRC_Pos := Pos;
            exit;
         end if;
      end loop;

      Assert (CRC_Pos /= 0, "native 7z periodic PPMd unpack CRC field found");
      Set_U32_LE (Archive, CRC_Pos, Expected_CRC xor 16#FFFF_FFFF#);
      Refresh_Seven_Zip_Header_CRCs (Archive);

      declare
         Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip
             (Archive, "zlib-ppmd-abcd-repeat.txt", Status);
      begin
         Assert
           (Status = Zlib.Invalid_Checksum,
            "native 7z periodic PPMd bad unpack CRC rejects recovery: "
            & Zlib.Status_Image (Status));
         Assert
           (Output'Length = 0,
            "native 7z periodic PPMd bad unpack CRC returns no payload");
      end;
   end Test_Extract_Rejects_Periodic_PPMd_Bad_Unpack_CRC;

   procedure Test_Extract_Accepts_Two_Symbol_PPMd_Stream
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Archive : constant Zlib.Byte_Array := Seven_Zip_PPMd_Two_Symbol_Archive;
      Status  : Zlib.Status_Code := Zlib.Unsupported_Method;
      Expected : constant Zlib.Byte_Array :=
        [Character'Pos ('a'), Character'Pos ('b')];
   begin
      declare
         Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "zlib-ppmd-ab2.txt", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z PPMd two-symbol stream extracts: "
            & Zlib.Status_Image (Status));
         Assert
           (Output = Expected,
            "native 7z PPMd two-symbol stream returns original payload");
      end;
   end Test_Extract_Accepts_Two_Symbol_PPMd_Stream;

   procedure Test_Extract_Accepts_Three_Symbol_PPMd_Stream
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Archive : constant Zlib.Byte_Array := Seven_Zip_PPMd_Three_Symbol_Archive;
      Status  : Zlib.Status_Code := Zlib.Unsupported_Method;
      Expected : constant Zlib.Byte_Array :=
        [Character'Pos ('a'), Character'Pos ('b'), Character'Pos ('c')];
   begin
      declare
         Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "zlib-ppmd-abc3.txt", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z PPMd three-symbol stream extracts: "
            & Zlib.Status_Image (Status));
         Assert
           (Output = Expected,
            "native 7z PPMd three-symbol stream returns original payload");
      end;
   end Test_Extract_Accepts_Three_Symbol_PPMd_Stream;

   procedure Test_Extract_Accepts_Six_Symbol_PPMd_Stream
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Archive : constant Zlib.Byte_Array := Seven_Zip_PPMd_Six_Symbol_Archive;
      Status  : Zlib.Status_Code := Zlib.Unsupported_Method;
      Expected : constant Zlib.Byte_Array :=
        [Character'Pos ('a'), Character'Pos ('b'), Character'Pos ('c'),
         Character'Pos ('d'), Character'Pos ('e'), Character'Pos ('f')];
   begin
      declare
         Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "zlib-ppmd-abcdef6.txt", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z PPMd six-symbol stream extracts: "
            & Zlib.Status_Image (Status));
         Assert
           (Output = Expected,
            "native 7z PPMd six-symbol stream returns original payload");
      end;
   end Test_Extract_Accepts_Six_Symbol_PPMd_Stream;

   procedure Test_Extract_Accepts_Ten_Symbol_PPMd_Stream
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Archive : constant Zlib.Byte_Array := Seven_Zip_PPMd_Ten_Symbol_Archive;
      Status  : Zlib.Status_Code := Zlib.Unsupported_Method;
      Expected : constant Zlib.Byte_Array :=
        [Character'Pos ('a'), Character'Pos ('b'), Character'Pos ('c'),
         Character'Pos ('d'), Character'Pos ('e'), Character'Pos ('f'),
         Character'Pos ('g'), Character'Pos ('h'), Character'Pos ('i'),
         Character'Pos ('j')];
   begin
      declare
         Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "zlib-ppmd-abcdefghij.txt", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z PPMd ten-symbol stream extracts: "
            & Zlib.Status_Image (Status));
         Assert
           (Output = Expected,
            "native 7z PPMd ten-symbol stream returns original payload");
      end;
   end Test_Extract_Accepts_Ten_Symbol_PPMd_Stream;

   procedure Test_Extract_Accepts_Eleven_Symbol_PPMd_Stream
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Archive : constant Zlib.Byte_Array := Seven_Zip_PPMd_Eleven_Symbol_Archive;
      Status  : Zlib.Status_Code := Zlib.Unsupported_Method;
      Expected : constant Zlib.Byte_Array :=
        [Character'Pos ('a'), Character'Pos ('b'), Character'Pos ('c'),
         Character'Pos ('d'), Character'Pos ('e'), Character'Pos ('f'),
         Character'Pos ('g'), Character'Pos ('h'), Character'Pos ('i'),
         Character'Pos ('j'), Character'Pos ('k')];
   begin
      declare
         Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "zlib-ppmd-abcdefghijk.txt", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native 7z PPMd eleven-symbol stream extracts: "
            & Zlib.Status_Image (Status));
         Assert
           (Output = Expected,
            "native 7z PPMd eleven-symbol stream returns original payload");
      end;
   end Test_Extract_Accepts_Eleven_Symbol_PPMd_Stream;

   procedure Test_Stored_Extract_Rejects_Overflowing_Next_Header_Offset
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status  : Zlib.Status_Code := Zlib.Ok;
      Archive : Zlib.Byte_Array :=
        Zlib.Seven_Zip_Stored (Payload, "payload.txt", Status);
   begin
      Assert
        (Status = Zlib.Ok,
         "overflowing next-header offset fixture archive creation status");

      Set_U64_LE
        (Archive, 13, Interfaces.Unsigned_64 (Natural'Last));
      Set_U32_LE (Archive, 9, Zlib.CRC32 (Archive (13 .. 32)));

      declare
         Plain : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip_Stored (Archive, "payload.txt", Status);
      begin
         Assert
           (Status = Zlib.Unsupported_Method,
            "overflowing next-header offset fails closed");
         Assert
           (Plain'Length = 0,
            "overflowing next-header offset returns no payload");
      end;
   end Test_Stored_Extract_Rejects_Overflowing_Next_Header_Offset;

   procedure Test_Stored_Extract_Rejects_Short_CRC_Tables
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status        : Zlib.Status_Code := Zlib.Ok;
      Archive       : constant Zlib.Byte_Array :=
        Zlib.Seven_Zip_Stored (Payload, "payload.txt", Status);
      Payload_Count : constant Natural := Natural (U64_LE (Archive, 13));
      Header_First  : constant Natural := 33 + Payload_Count;
      Header_Last   : constant Natural := Archive'Last;
      Payload_CRC   : constant Interfaces.Unsigned_32 := Zlib.CRC32 (Payload);
      Pack_CRC_Pos  : Natural := 0;
   begin
      Assert (Status = Zlib.Ok, "short CRC table fixture archive creation status");

      for Pos in Header_First .. Header_Last - 3 loop
         if U32_LE (Archive, Pos) = Payload_CRC then
            Pack_CRC_Pos := Pos;
            exit;
         end if;
      end loop;

      Assert (Pack_CRC_Pos /= 0, "packed CRC table field found");

      declare
         Mut_Header_Last : constant Natural := Pack_CRC_Pos + 2;
         Mutated         : Zlib.Byte_Array (1 .. Mut_Header_Last);
      begin
         for I in Mutated'Range loop
            Mutated (I) := Archive (I);
         end loop;

         Set_U64_LE
           (Mutated, 21,
            Interfaces.Unsigned_64 (Mut_Header_Last - Header_First + 1));
         Set_U32_LE
           (Mutated, 29,
            Zlib.CRC32 (Mutated (Header_First .. Mut_Header_Last)));
         Set_U32_LE (Mutated, 9, Zlib.CRC32 (Mutated (13 .. 32)));

         declare
            Plain : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip_Stored (Mutated, "payload.txt", Status);
         begin
            Assert
              (Status = Zlib.Unsupported_Method,
               "short 7z CRC table fails closed");
            Assert (Plain'Length = 0, "short 7z CRC table returns no data");
         end;
      end;
   end Test_Stored_Extract_Rejects_Short_CRC_Tables;

   procedure Test_Stored_Extract_Unsupported_Method_Fails
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status       : Zlib.Status_Code := Zlib.Ok;
      Archive      : Zlib.Byte_Array :=
        Zlib.Seven_Zip_Stored (Payload, "payload.txt", Status);
      Header_First : constant Natural := 33 + Payload'Length;
      Method_Pos   : Natural := 0;
   begin
      Assert (Status = Zlib.Ok, "unsupported-method fixture archive creation status");

      for I in Header_First .. Archive'Last - 1 loop
         if Archive (I) = 0 and then Archive (I + 1) = 16#0C# then
            Method_Pos := I;
            exit;
         end if;
      end loop;
      Assert (Method_Pos /= 0, "Copy-coder method byte found");

      Archive (Method_Pos) := 1;
      Set_U32_LE
        (Archive, 29,
         Zlib.CRC32 (Archive (Header_First .. Archive'Last)));
      Set_U32_LE (Archive, 9, Zlib.CRC32 (Archive (13 .. 32)));

      declare
         Plain : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip_Stored (Archive, "payload.txt", Status);
      begin
         Assert (Status = Zlib.Unsupported_Method, "unsupported 7z method fails closed");
         Assert (Plain'Length = 0, "unsupported 7z method returns no payload");
      end;
   end Test_Stored_Extract_Unsupported_Method_Fails;

   procedure Test_Stored_Extract_Truncated_Archive_Fails
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status  : Zlib.Status_Code := Zlib.Ok;
      Archive : constant Zlib.Byte_Array :=
        Zlib.Seven_Zip_Stored (Payload, "payload.txt", Status);
   begin
      Assert (Status = Zlib.Ok, "truncated fixture archive creation status");
      declare
         Truncated : constant Zlib.Byte_Array :=
           Archive (Archive'First .. Archive'Last - 1);
         Plain     : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip_Stored (Truncated, "payload.txt", Status);
      begin
         Assert
           (Status = Zlib.Unexpected_End_Of_Input,
            "truncated 7z archive is reported as unexpected end of input");
         Assert (Plain'Length = 0, "truncated 7z archive returns no payload");
      end;
   end Test_Stored_Extract_Truncated_Archive_Fails;

   procedure Test_Stored_Extract_Trailing_Garbage_Fails
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status  : Zlib.Status_Code := Zlib.Ok;
      Archive : constant Zlib.Byte_Array :=
        Zlib.Seven_Zip_Stored (Payload, "payload.txt", Status);
   begin
      Assert (Status = Zlib.Ok, "trailing-garbage fixture archive creation status");
      declare
         Padded : Zlib.Byte_Array (1 .. Archive'Length + 1);
      begin
         for I in Archive'Range loop
            Padded (I) := Archive (I);
         end loop;
         Padded (Padded'Last) := 16#FF#;

         declare
            Plain : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip_Stored (Padded, "payload.txt", Status);
         begin
            Assert
              (Status = Zlib.Unsupported_Method,
               "trailing bytes after 7z header fail closed");
            Assert (Plain'Length = 0, "trailing 7z garbage returns no payload");
         end;
      end;
   end Test_Stored_Extract_Trailing_Garbage_Fails;

   procedure Test_Stored_Extract_Missing_Header_Sections_Fails
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      procedure Check_Missing_Section
        (Section_ID : Zlib.Byte;
         Label      : String)
      is
         Status        : Zlib.Status_Code := Zlib.Ok;
         Archive       : Zlib.Byte_Array :=
           Zlib.Seven_Zip_Stored (Payload, "payload.txt", Status);
         Payload_Count : constant Natural := Natural (U64_LE (Archive, 13));
         Header_First  : constant Natural := 33 + Payload_Count;
         Header_Last   : constant Natural := Archive'Last;
         Section_Pos   : Natural := 0;
      begin
         Assert (Status = Zlib.Ok, Label & " malformed header fixture creation status");

         for Pos in Header_First .. Header_Last loop
            if Archive (Pos) = Section_ID then
               Section_Pos := Pos;
               exit;
            end if;
         end loop;

         Assert (Section_Pos /= 0, Label & " section marker found");
         Archive (Section_Pos) := 16#FF#;
         Set_U32_LE
           (Archive, 29, Zlib.CRC32 (Archive (Header_First .. Header_Last)));
         Set_U32_LE (Archive, 9, Zlib.CRC32 (Archive (13 .. 32)));

         declare
            Plain : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip_Stored (Archive, "payload.txt", Status);
         begin
            Assert
              (Status = Zlib.Unsupported_Method,
               Label & " malformed 7z header fails closed");
            Assert (Plain'Length = 0, Label & " malformed 7z header returns no data");
         end;
      end Check_Missing_Section;
   begin
      Check_Missing_Section (16#06#, "PackInfo");
      Check_Missing_Section (16#09#, "PackInfo Size");
      Check_Missing_Section (16#07#, "UnPackInfo");
      Check_Missing_Section (16#0B#, "Folder");
      Check_Missing_Section (16#0C#, "CodersUnPackSize");
      Check_Missing_Section (16#05#, "FilesInfo");
      Check_Missing_Section (16#11#, "Name");
   end Test_Stored_Extract_Missing_Header_Sections_Fails;

   procedure Test_Stored_Extract_Rejects_Pack_Size_Overflow
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      First_Path   : constant String := Base_Path ("pack-overflow-first.bin");
      Second_Path  : constant String := Base_Path ("pack-overflow-second.bin");
      Archive_Path : constant String := Base_Path ("pack-overflow.7z");
      Empty_Data   : constant Zlib.Byte_Array (1 .. 0) := [others => 0];
      Input_Paths  : constant Zlib.Text_Array :=
        [US.To_Unbounded_String (First_Path),
         US.To_Unbounded_String (Second_Path)];
      Entry_Names  : constant Zlib.Text_Array :=
        [US.To_Unbounded_String ("first.bin"),
         US.To_Unbounded_String ("second.bin")];
      Status       : Zlib.Status_Code := Zlib.Ok;
   begin
      Delete_If_Exists (First_Path);
      Delete_If_Exists (Second_Path);
      Delete_If_Exists (Archive_Path);
      Write_File (First_Path, Empty_Data);
      Write_File (Second_Path, Empty_Data);

      Zlib.Seven_Zip_Stored_Files
        (Input_Paths, Archive_Path, Entry_Names, Status);
      Assert (Status = Zlib.Ok, "pack-size overflow fixture creation status");

      declare
         Archive       : constant Zlib.Byte_Array := Read_File (Archive_Path);
         Payload_Count : constant Natural := Natural (U64_LE (Archive, 13));
         Header_First  : constant Natural := 33 + Payload_Count;
         Header_Last   : constant Natural := Archive'Last;
         Size_Pos      : Natural := 0;
      begin
         Assert (Payload_Count = 0, "overflow fixture has empty packed payload");

         for Pos in Header_First .. Header_Last - 3 loop
            if Archive (Pos) = 16#09#
              and then Archive (Pos + 1) = 0
              and then Archive (Pos + 2) = 16#0A#
            then
               Size_Pos := Pos + 1;
               exit;
            end if;
         end loop;

         Assert (Size_Pos /= 0, "pack-size fields found");

         declare
            Extra        : constant Natural := 8;
            Mutated      : Zlib.Byte_Array (1 .. Archive'Length + Extra);
            Mut_Header_First : constant Natural := Header_First;
            Mut_Header_Last  : constant Natural := Header_Last + Extra;
         begin
            for I in Archive'First .. Size_Pos - 1 loop
               Mutated (I) := Archive (I);
            end loop;

            Mutated (Size_Pos) := 16#FF#;
            Set_U64_LE (Mutated, Size_Pos + 1, Interfaces.Unsigned_64'Last);

            for I in Size_Pos + 2 .. Archive'Last loop
               Mutated (I + Extra) := Archive (I);
            end loop;

            Set_U64_LE (Mutated, 21, Interfaces.Unsigned_64 (Mut_Header_Last - Mut_Header_First + 1));
            Set_U32_LE
              (Mutated, 29,
               Zlib.CRC32 (Mutated (Mut_Header_First .. Mut_Header_Last)));
            Set_U32_LE (Mutated, 9, Zlib.CRC32 (Mutated (13 .. 32)));

            declare
               Plain : constant Zlib.Byte_Array :=
                 Zlib.Extract_Seven_Zip_Stored (Mutated, "first.bin", Status);
            begin
               Assert
                 (Status = Zlib.Unsupported_Method,
                  "overflowed 7z pack sizes fail closed");
               Assert (Plain'Length = 0, "overflowed 7z pack sizes return no data");
            end;
         end;
      end;

      Delete_If_Exists (First_Path);
      Delete_If_Exists (Second_Path);
      Delete_If_Exists (Archive_Path);
   exception
      when others =>
         Delete_If_Exists (First_Path);
         Delete_If_Exists (Second_Path);
         Delete_If_Exists (Archive_Path);
         raise;
   end Test_Stored_Extract_Rejects_Pack_Size_Overflow;

   procedure Test_Stored_Extract_Rejects_Impossible_Stream_Count
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status        : Zlib.Status_Code := Zlib.Ok;
      Archive       : Zlib.Byte_Array :=
        Zlib.Seven_Zip_Stored (Payload, "payload.txt", Status);
      Payload_Count : constant Natural := Natural (U64_LE (Archive, 13));
      Header_Size   : constant Natural := Natural (U64_LE (Archive, 21));
      Header_First  : constant Natural := 33 + Payload_Count;
      Header_Last   : constant Natural := Archive'Last;
      Count_Pos     : constant Natural := Header_First + 4;
   begin
      Assert (Status = Zlib.Ok, "impossible stream-count fixture creation status");
      Assert (Header_Size < 127, "fixture header size leaves one-byte impossible count");
      Assert (Archive (Count_Pos) = 1, "stream-count field found");

      Archive (Count_Pos) := 127;
      Set_U32_LE
        (Archive, 29, Zlib.CRC32 (Archive (Header_First .. Header_Last)));
      Set_U32_LE (Archive, 9, Zlib.CRC32 (Archive (13 .. 32)));

      declare
         Plain : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip_Stored (Archive, "payload.txt", Status);
      begin
         Assert
           (Status = Zlib.Unsupported_Method,
            "impossible 7z stream count fails closed");
         Assert (Plain'Length = 0, "impossible 7z stream count returns no data");
      end;
   end Test_Stored_Extract_Rejects_Impossible_Stream_Count;

   procedure Test_Stored_Extract_Rejects_Header_Count_Mismatches
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      procedure Check_Count_Mismatch
        (Prefix : Zlib.Byte_Array;
         Label  : String)
      is
         Status        : Zlib.Status_Code := Zlib.Ok;
         Archive       : Zlib.Byte_Array :=
           Zlib.Seven_Zip_Stored (Payload, "payload.txt", Status);
         Payload_Count : constant Natural := Natural (U64_LE (Archive, 13));
         Header_First  : constant Natural := 33 + Payload_Count;
         Header_Last   : constant Natural := Archive'Last;
         Count_Pos     : Natural := 0;
      begin
         Assert (Status = Zlib.Ok, Label & " count-mismatch fixture creation status");

         for Pos in Header_First .. Header_Last - Prefix'Length loop
            declare
               Match : Boolean := True;
            begin
               for Offset in 0 .. Prefix'Length - 1 loop
                  if Archive (Pos + Offset) /= Prefix (Prefix'First + Offset) then
                     Match := False;
                     exit;
                  end if;
               end loop;

               if Match then
                  Count_Pos := Pos + Prefix'Length;
                  exit;
               end if;
            end;
         end loop;

         Assert (Count_Pos /= 0, Label & " count field found");
         Assert (Archive (Count_Pos) = 1, Label & " fixture count starts at one");
         Archive (Count_Pos) := 2;
         Set_U32_LE
           (Archive, 29, Zlib.CRC32 (Archive (Header_First .. Header_Last)));
         Set_U32_LE (Archive, 9, Zlib.CRC32 (Archive (13 .. 32)));

         declare
            Plain : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip_Stored (Archive, "payload.txt", Status);
         begin
            Assert
              (Status = Zlib.Unsupported_Method,
               Label & " count mismatch fails closed");
            Assert (Plain'Length = 0, Label & " count mismatch returns no data");
         end;
      end Check_Count_Mismatch;
   begin
      Check_Count_Mismatch ([0, 16#07#, 16#0B#], "Folder");
      Check_Count_Mismatch ([0, 0, 16#05#], "FilesInfo");
   end Test_Stored_Extract_Rejects_Header_Count_Mismatches;

   procedure Test_Stored_Extract_Rejects_Malformed_Name_Field
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Entry_Name    : constant String := "payload.txt";
      Status        : Zlib.Status_Code := Zlib.Ok;
      Archive       : Zlib.Byte_Array :=
        Zlib.Seven_Zip_Stored (Payload, Entry_Name, Status);
      Payload_Count : constant Natural := Natural (U64_LE (Archive, 13));
      Header_First  : constant Natural := 33 + Payload_Count;
      Header_Last   : constant Natural := Archive'Last;
      Name_Count    : constant Zlib.Byte :=
        Zlib.Byte (1 + 2 * (Entry_Name'Length + 1));
      Count_Pos     : Natural := 0;
   begin
      Assert (Status = Zlib.Ok, "malformed name-field fixture creation status");

      for Pos in Header_First .. Header_Last - 1 loop
         if Archive (Pos) = 16#11# and then Archive (Pos + 1) = Name_Count then
            Count_Pos := Pos + 1;
            exit;
         end if;
      end loop;

      Assert (Count_Pos /= 0, "name-field size found");
      Archive (Count_Pos) := Name_Count - 1;
      Set_U32_LE
        (Archive, 29, Zlib.CRC32 (Archive (Header_First .. Header_Last)));
      Set_U32_LE (Archive, 9, Zlib.CRC32 (Archive (13 .. 32)));

      declare
         Plain : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip_Stored (Archive, Entry_Name, Status);
      begin
         Assert
           (Status = Zlib.Unsupported_Method,
            "malformed 7z name field fails closed");
         Assert (Plain'Length = 0, "malformed 7z name field returns no data");
      end;
   end Test_Stored_Extract_Rejects_Malformed_Name_Field;

   procedure Test_LZMA_Extract_Rejects_Invalid_Properties
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status        : Zlib.Status_Code := Zlib.Ok;
      Archive       : Zlib.Byte_Array :=
        Zlib.Seven_Zip_LZMA (Payload, "payload.txt", Status);
      Payload_Count : constant Natural := Natural (U64_LE (Archive, 13));
      Header_First  : constant Natural := 33 + Payload_Count;
      Header_Last   : constant Natural := Archive'Last;
      Props_Pos     : Natural := 0;
   begin
      Assert (Status = Zlib.Ok, "invalid LZMA properties fixture creation status");

      for Pos in Header_First .. Header_Last - 5 loop
         if Archive (Pos) = 16#23#
           and then Archive (Pos + 1) = 16#03#
           and then Archive (Pos + 2) = 16#01#
           and then Archive (Pos + 3) = 16#01#
           and then Archive (Pos + 4) = 5
         then
            Props_Pos := Pos + 5;
            exit;
         end if;
      end loop;

      Assert (Props_Pos /= 0, "LZMA coder properties found");
      Archive (Props_Pos) := 16#FF#;
      Set_U32_LE
        (Archive, 29, Zlib.CRC32 (Archive (Header_First .. Header_Last)));
      Set_U32_LE (Archive, 9, Zlib.CRC32 (Archive (13 .. 32)));

      declare
         Plain : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip_Stored (Archive, "payload.txt", Status);
      begin
         Assert
           (Status = Zlib.Unsupported_Method,
            "invalid LZMA 7z properties fail closed");
         Assert (Plain'Length = 0, "invalid LZMA 7z properties return no data");
      end;
   end Test_LZMA_Extract_Rejects_Invalid_Properties;

   procedure Test_LZMA_Extract_Rejects_Trailing_Packed_Bytes
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status        : Zlib.Status_Code := Zlib.Ok;
      Input         : constant Zlib.Byte_Array := [1 .. 4096 => 16#4C#];
      Archive       : constant Zlib.Byte_Array :=
        Zlib.Seven_Zip_LZMA (Input, "payload.txt", Status);
      Payload_Count : constant Natural := Natural (U64_LE (Archive, 13));
      Header_First  : constant Natural := 33 + Payload_Count;
      Header_Last   : constant Natural := Archive'Last;
   begin
      Assert
        (Status = Zlib.Ok,
         "trailing LZMA packed-byte fixture creation status");
      Assert
        (Payload_Count > 0 and then Payload_Count < 127,
         "trailing LZMA fixture uses one-byte 7z pack size");

      declare
         Mutated          : Zlib.Byte_Array (1 .. Archive'Length + 1);
         Mut_Header_First : constant Natural := Header_First + 1;
         Mut_Header_Last  : constant Natural := Header_Last + 1;
         Pack_Size_Pos    : Natural := 0;
         Pack_CRC_Pos     : Natural := 0;
         Old_Pack_CRC     : constant Interfaces.Unsigned_32 :=
           Zlib.CRC32 (Archive (33 .. Header_First - 1));
      begin
         for I in Archive'First .. Header_First - 1 loop
            Mutated (I) := Archive (I);
         end loop;

         Mutated (Header_First) := 0;

         for I in Header_First .. Header_Last loop
            Mutated (I + 1) := Archive (I);
         end loop;

         for Pos in Mut_Header_First .. Mut_Header_Last - 6 loop
            if Mutated (Pos) = 16#01#
              and then Mutated (Pos + 1) = 16#04#
              and then Mutated (Pos + 2) = 16#06#
              and then Mutated (Pos + 3) = 0
              and then Mutated (Pos + 4) = 1
              and then Mutated (Pos + 5) = 16#09#
            then
               Pack_Size_Pos := Pos + 6;
               exit;
            end if;
         end loop;

         Assert (Pack_Size_Pos /= 0, "single-stream LZMA pack size field found");
         Assert
           (Mutated (Pack_Size_Pos) = Zlib.Byte (Payload_Count),
            "single-stream LZMA pack size field is one-byte encoded");
         Mutated (Pack_Size_Pos) := Zlib.Byte (Payload_Count + 1);

         for Pos in Mut_Header_First .. Mut_Header_Last - 3 loop
            if U32_LE (Mutated, Pos) = Old_Pack_CRC then
               Pack_CRC_Pos := Pos;
               exit;
            end if;
         end loop;

         Assert (Pack_CRC_Pos /= 0, "single-stream LZMA pack CRC field found");
         Set_U32_LE
           (Mutated, Pack_CRC_Pos,
            Zlib.CRC32 (Mutated (33 .. Mut_Header_First - 1)));
         Set_U64_LE (Mutated, 13, Interfaces.Unsigned_64 (Payload_Count + 1));
         Set_U64_LE
           (Mutated, 21,
            Interfaces.Unsigned_64 (Mut_Header_Last - Mut_Header_First + 1));
         Set_U32_LE
           (Mutated, 29,
            Zlib.CRC32 (Mutated (Mut_Header_First .. Mut_Header_Last)));
         Set_U32_LE (Mutated, 9, Zlib.CRC32 (Mutated (13 .. 32)));

         declare
            Plain : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip_Stored
                (Mutated, "payload.txt", Status);
         begin
            Assert
              (Status = Zlib.Unsupported_Method,
               "LZMA trailing packed bytes fail closed");
            Assert
              (Plain'Length = 0,
               "LZMA trailing packed bytes return no data");
         end;
      end;
   end Test_LZMA_Extract_Rejects_Trailing_Packed_Bytes;

   procedure Test_LZMA2_Extract_Rejects_Malformed_Properties
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status        : Zlib.Status_Code := Zlib.Ok;
      Archive       : constant Zlib.Byte_Array :=
        Zlib.Seven_Zip_LZMA2 (Payload, "payload.txt", Status);
      Payload_Count : constant Natural := Natural (U64_LE (Archive, 13));
      Header_First  : constant Natural := 33 + Payload_Count;
      Header_Last   : constant Natural := Archive'Last;
      Props_Size_Pos : Natural := 0;
   begin
      Assert
        (Status = Zlib.Ok,
         "malformed LZMA2 properties fixture creation status");

      for Pos in Header_First .. Header_Last - 4 loop
         if Archive (Pos) = 16#21#
           and then Archive (Pos + 1) = 16#21#
           and then Archive (Pos + 2) = 1
           and then Archive (Pos + 3) = 16#16#
           and then Archive (Pos + 4) = 16#0C#
         then
            Props_Size_Pos := Pos + 2;
            exit;
         end if;
      end loop;

      Assert (Props_Size_Pos /= 0, "LZMA2 coder property-size byte found");

      declare
         Mutated         : Zlib.Byte_Array (1 .. Archive'Length - 1);
         Mut_Header_Last : constant Natural := Header_Last - 1;
      begin
         for I in Archive'First .. Props_Size_Pos - 1 loop
            Mutated (I) := Archive (I);
         end loop;

         for I in Props_Size_Pos + 1 .. Archive'Last loop
            Mutated (I - 1) := Archive (I);
         end loop;

         Set_U64_LE
           (Mutated, 21,
            Interfaces.Unsigned_64 (Mut_Header_Last - Header_First + 1));
         Set_U32_LE
           (Mutated, 29, Zlib.CRC32 (Mutated (Header_First .. Mut_Header_Last)));
         Set_U32_LE (Mutated, 9, Zlib.CRC32 (Mutated (13 .. 32)));

         declare
            Plain : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip_Stored (Mutated, "payload.txt", Status);
         begin
            Assert
              (Status = Zlib.Unsupported_Method,
               "malformed LZMA2 7z properties fail closed");
            Assert
              (Plain'Length = 0,
               "malformed LZMA2 7z properties return no data");
         end;
      end;
   end Test_LZMA2_Extract_Rejects_Malformed_Properties;

   procedure Test_LZMA2_Extract_Rejects_Trailing_Packed_Bytes
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status        : Zlib.Status_Code := Zlib.Ok;
      Input         : constant Zlib.Byte_Array := [1 .. 4096 => 16#41#];
      Archive       : constant Zlib.Byte_Array :=
        Zlib.Seven_Zip_LZMA2 (Input, "payload.txt", Status);
      Payload_Count : constant Natural := Natural (U64_LE (Archive, 13));
      Header_First  : constant Natural := 33 + Payload_Count;
      Header_Last   : constant Natural := Archive'Last;
      Chunk_Pos     : Natural := 0;
   begin
      Assert
        (Status = Zlib.Ok,
         "trailing LZMA2 packed-byte fixture creation status");
      Assert
        (Payload_Count < 127,
         "trailing LZMA2 fixture uses one-byte 7z pack size");

      for Pos in 33 .. Header_First - 7 loop
         if Archive (Pos) >= 16#E0# then
            Chunk_Pos := Pos;
            exit;
         end if;
      end loop;

      Assert (Chunk_Pos /= 0, "compressed LZMA2 chunk found");

      declare
         Packed_Len : constant Natural :=
           Natural (Archive (Chunk_Pos + 3)) * 256
           + Natural (Archive (Chunk_Pos + 4)) + 1;
         Term_Pos   : constant Natural := Chunk_Pos + 6 + Packed_Len;
      begin
         Assert
           (Term_Pos = Header_First - 1,
            "single compressed LZMA2 chunk reaches stream terminator");
         Assert
           (Archive (Term_Pos) = 0,
            "LZMA2 stream terminator found after compressed chunk");
         Assert
           (Packed_Len < 65_535,
            "LZMA2 packed length can be extended in-place");

         declare
            Mutated          : Zlib.Byte_Array (1 .. Archive'Length + 1);
            Mut_Header_First : constant Natural := Header_First + 1;
            Mut_Header_Last  : constant Natural := Header_Last + 1;
            Pack_Size_Pos    : Natural := 0;
            Pack_CRC_Pos     : Natural := 0;
            Old_Pack_CRC     : constant Interfaces.Unsigned_32 :=
              Zlib.CRC32 (Archive (33 .. Header_First - 1));
         begin
            for I in Archive'First .. Term_Pos loop
               Mutated (I) := Archive (I);
            end loop;

            Mutated (Term_Pos + 1) := 0;

            for I in Header_First .. Header_Last loop
               Mutated (I + 1) := Archive (I);
            end loop;

            Mutated (Chunk_Pos + 3) := Zlib.Byte (Packed_Len / 256);
            Mutated (Chunk_Pos + 4) := Zlib.Byte (Packed_Len mod 256);

            for Pos in Mut_Header_First .. Mut_Header_Last - 6 loop
               if Mutated (Pos) = 16#01#
                 and then Mutated (Pos + 1) = 16#04#
                 and then Mutated (Pos + 2) = 16#06#
                 and then Mutated (Pos + 3) = 0
                 and then Mutated (Pos + 4) = 1
                 and then Mutated (Pos + 5) = 16#09#
               then
                  Pack_Size_Pos := Pos + 6;
                  exit;
               end if;
            end loop;

            Assert (Pack_Size_Pos /= 0, "single-stream pack size field found");
            Assert
              (Mutated (Pack_Size_Pos) = Zlib.Byte (Payload_Count),
               "single-stream pack size field is one-byte encoded");
            Mutated (Pack_Size_Pos) := Zlib.Byte (Payload_Count + 1);

            for Pos in Mut_Header_First .. Mut_Header_Last - 3 loop
               if U32_LE (Mutated, Pos) = Old_Pack_CRC then
                  Pack_CRC_Pos := Pos;
                  exit;
               end if;
            end loop;

            Assert (Pack_CRC_Pos /= 0, "single-stream pack CRC field found");
            Set_U32_LE
              (Mutated, Pack_CRC_Pos,
               Zlib.CRC32 (Mutated (33 .. Mut_Header_First - 1)));
            Set_U64_LE (Mutated, 13, Interfaces.Unsigned_64 (Payload_Count + 1));
            Set_U64_LE
              (Mutated, 21,
               Interfaces.Unsigned_64 (Mut_Header_Last - Mut_Header_First + 1));
            Set_U32_LE
              (Mutated, 29,
               Zlib.CRC32 (Mutated (Mut_Header_First .. Mut_Header_Last)));
            Set_U32_LE (Mutated, 9, Zlib.CRC32 (Mutated (13 .. 32)));

            declare
               Plain : constant Zlib.Byte_Array :=
                 Zlib.Extract_Seven_Zip_Stored
                   (Mutated, "payload.txt", Status);
            begin
               Assert
                 (Status = Zlib.Unsupported_Method,
                  "LZMA2 trailing packed bytes fail closed");
               Assert
                 (Plain'Length = 0,
                  "LZMA2 trailing packed bytes return no data");
            end;
         end;
      end;
   end Test_LZMA2_Extract_Rejects_Trailing_Packed_Bytes;

   procedure Test_Stored_File_Roundtrip_Native
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input_Path   : constant String := Base_Path ("input.bin");
      Archive_Path : constant String := Base_Path ("roundtrip.7z");
      Output_Path  : constant String := Base_Path ("output.bin");
      Status       : Zlib.Status_Code := Zlib.Ok;
   begin
      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Path);

      Write_File (Input_Path, Payload);
      Zlib.Seven_Zip_Stored_File (Input_Path, Archive_Path, "payload.txt", Status);
      Assert (Status = Zlib.Ok, "stored 7z file creation status");
      Zlib.Extract_Seven_Zip_Stored_File (Archive_Path, Output_Path, "payload.txt", Status);
      Assert (Status = Zlib.Ok, "stored 7z file extraction status");
      Assert (Read_File (Output_Path) = Payload, "stored 7z file helper roundtrip");

      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Path);
   exception
      when others =>
         Delete_If_Exists (Input_Path);
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Path);
         raise;
   end Test_Stored_File_Roundtrip_Native;

   procedure Test_Deflate_File_Roundtrip_Native
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input_Path   : constant String := Base_Path ("deflate-input.bin");
      Archive_Path : constant String := Base_Path ("deflate.7z");
      Output_Path  : constant String := Base_Path ("deflate-output.bin");
      Input_Data   : constant Zlib.Byte_Array :=
        [1 .. 512 => 16#42#];
      Status       : Zlib.Status_Code := Zlib.Ok;
   begin
      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Path);

      Write_File (Input_Path, Input_Data);
      Zlib.Seven_Zip_Deflate_File
        (Input_Path, Archive_Path, "payload.txt", Zlib.Dynamic, Status);
      Assert (Status = Zlib.Ok, "native Deflate 7z file creation");
      Zlib.Extract_Seven_Zip_Stored_File
        (Archive_Path, Output_Path, "payload.txt", Status);
      Assert (Status = Zlib.Ok, "native Deflate 7z file extraction");
      Assert
        (Read_File (Output_Path) = Input_Data,
         "native Deflate 7z file helpers roundtrip payload");

      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Path);
   exception
      when others =>
         Delete_If_Exists (Input_Path);
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Path);
         raise;
   end Test_Deflate_File_Roundtrip_Native;

   procedure Test_BZip2_File_Roundtrip_Native
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input_Path   : constant String := Base_Path ("bzip2-input.bin");
      Archive_Path : constant String := Base_Path ("bzip2.7z");
      Output_Path  : constant String := Base_Path ("bzip2-output.bin");
      Pattern      : constant String := "native bzip2 7z";
      Input_Data   : Zlib.Byte_Array (1 .. 2048);
      Status       : Zlib.Status_Code := Zlib.Ok;
   begin
      for I in Input_Data'Range loop
         Input_Data (I) :=
           Zlib.Byte
             (Character'Pos (Pattern ((I - 1) mod Pattern'Length + 1)));
      end loop;

      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Path);

      Write_File (Input_Path, Input_Data);
      Zlib.Seven_Zip_BZip2_File
        (Input_Path, Archive_Path, "payload.txt", Status);
      Assert (Status = Zlib.Ok, "native BZip2 7z file creation");
      Zlib.Extract_Seven_Zip_File
        (Archive_Path, Output_Path, "payload.txt", Status);
      Assert (Status = Zlib.Ok, "native BZip2 7z file extraction");
      Assert
        (Read_File (Output_Path) = Input_Data,
         "native BZip2 7z file helper roundtrip payload");

      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Path);
   exception
      when others =>
         Delete_If_Exists (Input_Path);
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Path);
         raise;
   end Test_BZip2_File_Roundtrip_Native;

   procedure Test_LZMA2_File_Roundtrip_Native
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input_Path   : constant String := Base_Path ("lzma2-input.bin");
      Archive_Path : constant String := Base_Path ("lzma2.7z");
      Output_Path  : constant String := Base_Path ("lzma2-output.bin");
      Input_Data   : constant Zlib.Byte_Array :=
        [1 .. 1024 => 16#4C#];
      Status       : Zlib.Status_Code := Zlib.Ok;
   begin
      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Path);

      Write_File (Input_Path, Input_Data);
      Zlib.Seven_Zip_LZMA2_File
        (Input_Path, Archive_Path, "payload.txt", Status);
      Assert (Status = Zlib.Ok, "native LZMA2 7z file creation");
      Zlib.Extract_Seven_Zip_File
        (Archive_Path, Output_Path, "payload.txt", Status);
      Assert (Status = Zlib.Ok, "native LZMA2 7z file extraction");
      Assert
        (Read_File (Output_Path) = Input_Data,
         "native LZMA2 7z file helper roundtrip payload");

      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Path);
   exception
      when others =>
         Delete_If_Exists (Input_Path);
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Path);
         raise;
   end Test_LZMA2_File_Roundtrip_Native;

   procedure Test_LZMA_File_Roundtrip_Native
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input_Path   : constant String := Base_Path ("lzma-input.bin");
      Archive_Path : constant String := Base_Path ("lzma.7z");
      Output_Path  : constant String := Base_Path ("lzma-output.bin");
      Input_Data   : constant Zlib.Byte_Array :=
        [1 .. 2048 => 16#6D#];
      Status       : Zlib.Status_Code := Zlib.Ok;
   begin
      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Path);

      Write_File (Input_Path, Input_Data);
      Zlib.Seven_Zip_LZMA_File
        (Input_Path, Archive_Path, "payload.txt", Status);
      Assert (Status = Zlib.Ok, "native LZMA 7z file creation");
      Zlib.Extract_Seven_Zip_File
        (Archive_Path, Output_Path, "payload.txt", Status);
      Assert (Status = Zlib.Ok, "native LZMA 7z file extraction");
      Assert
        (Read_File (Output_Path) = Input_Data,
         "native LZMA 7z file helper roundtrip payload");

      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Path);
   exception
      when others =>
         Delete_If_Exists (Input_Path);
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Path);
         raise;
   end Test_LZMA_File_Roundtrip_Native;

   procedure Test_PPMd_File_Extraction_Native
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Archive_Path : constant String := Base_Path ("ppmd-ten-symbol.7z");
      Output_Path  : constant String := Base_Path ("ppmd-ten-symbol-output.bin");
      Status       : Zlib.Status_Code := Zlib.Unsupported_Method;
      Expected     : constant Zlib.Byte_Array :=
        [Character'Pos ('a'), Character'Pos ('b'), Character'Pos ('c'),
         Character'Pos ('d'), Character'Pos ('e'), Character'Pos ('f'),
         Character'Pos ('g'), Character'Pos ('h'), Character'Pos ('i'),
         Character'Pos ('j')];
   begin
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Path);

      Write_File (Archive_Path, Seven_Zip_PPMd_Ten_Symbol_Archive);
      Zlib.Extract_Seven_Zip_File
        (Archive_Path, Output_Path, "zlib-ppmd-abcdefghij.txt", Status);
      Assert
        (Status = Zlib.Ok,
         "native PPMd 7z file helper extracts supported stream: "
         & Zlib.Status_Image (Status));
      Assert
        (Read_File (Output_Path) = Expected,
         "native PPMd 7z file helper writes expected payload");

      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Path);
   exception
      when others =>
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Path);
         raise;
   end Test_PPMd_File_Extraction_Native;

   procedure Test_PPMd_File_Extraction_Accepts_Eleven_Symbol_Stream
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Archive_Path : constant String := Base_Path ("ppmd-eleven-symbol.7z");
      Output_Path  : constant String := Base_Path ("ppmd-eleven-symbol-output.bin");
      Status       : Zlib.Status_Code := Zlib.Unsupported_Method;
      Expected     : constant Zlib.Byte_Array :=
        [Character'Pos ('a'), Character'Pos ('b'), Character'Pos ('c'),
         Character'Pos ('d'), Character'Pos ('e'), Character'Pos ('f'),
         Character'Pos ('g'), Character'Pos ('h'), Character'Pos ('i'),
         Character'Pos ('j'), Character'Pos ('k')];
   begin
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Path);

      Write_File (Archive_Path, Seven_Zip_PPMd_Eleven_Symbol_Archive);
      Zlib.Extract_Seven_Zip_File
        (Archive_Path, Output_Path, "zlib-ppmd-abcdefghijk.txt", Status);
      Assert
        (Status = Zlib.Ok,
         "native PPMd 7z file helper extracts eleven-symbol stream: "
         & Zlib.Status_Image (Status));
      Assert
        (Read_File (Output_Path) = Expected,
         "native PPMd 7z file helper writes eleven-symbol payload");

      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Path);
   exception
      when others =>
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Path);
         raise;
   end Test_PPMd_File_Extraction_Accepts_Eleven_Symbol_Stream;

   procedure Test_PPMd_File_Extraction_Accepts_Periodic_Stream
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Archive_Path : constant String := Base_Path ("ppmd-periodic.7z");
      Output_Path  : constant String := Base_Path ("ppmd-periodic-output.bin");
      Status       : Zlib.Status_Code := Zlib.Unsupported_Method;
      Pattern      : constant String := "abcd";
   begin
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Path);

      Write_File (Archive_Path, Seven_Zip_PPMd_ABCD_Periodic_Archive);
      Zlib.Extract_Seven_Zip_File
        (Archive_Path, Output_Path, "zlib-ppmd-abcd-repeat.txt", Status);
      Assert
        (Status = Zlib.Ok,
         "native PPMd 7z file helper extracts periodic stream: "
         & Zlib.Status_Image (Status));

      declare
         Output : constant Zlib.Byte_Array := Read_File (Output_Path);
      begin
         Assert
           (Output'Length = 40,
            "native PPMd 7z file helper writes periodic payload length");
         for I in Output'Range loop
            declare
               Pattern_Index : constant Positive :=
                 Pattern'First + ((I - Output'First) mod Pattern'Length);
            begin
               Assert
                 (Output (I) = Character'Pos (Pattern (Pattern_Index)),
                  "native PPMd 7z file helper writes periodic payload byte");
            end;
         end loop;
      end;

      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Path);
   exception
      when others =>
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Path);
         raise;
   end Test_PPMd_File_Extraction_Accepts_Periodic_Stream;

   procedure Test_PPMd_File_List_Extraction_Native
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Archive_Path : constant String := Base_Path ("ppmd-list-ten-symbol.7z");
      Output_Dir   : constant String := Base_Path ("ppmd-list-ten-symbol-output");
      Entry_Names  : constant Zlib.Text_Array :=
        [1 => US.To_Unbounded_String ("zlib-ppmd-abcdefghij.txt")];
      Status       : Zlib.Status_Code := Zlib.Unsupported_Method;
      Expected     : constant Zlib.Byte_Array :=
        [Character'Pos ('a'), Character'Pos ('b'), Character'Pos ('c'),
         Character'Pos ('d'), Character'Pos ('e'), Character'Pos ('f'),
         Character'Pos ('g'), Character'Pos ('h'), Character'Pos ('i'),
         Character'Pos ('j')];
   begin
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);

      Write_File (Archive_Path, Seven_Zip_PPMd_Ten_Symbol_Archive);
      Zlib.Extract_Seven_Zip_Files
        (Archive_Path, Output_Dir, Entry_Names, Status);
      Assert
        (Status = Zlib.Ok,
         "native PPMd 7z file-list helper extracts supported stream: "
         & Zlib.Status_Image (Status));
      Assert
        (Read_File
           (Ada.Directories.Compose
              (Output_Dir, "zlib-ppmd-abcdefghij.txt")) = Expected,
         "native PPMd 7z file-list helper writes expected payload");

      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);
   exception
      when others =>
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);
         raise;
   end Test_PPMd_File_List_Extraction_Native;

   procedure Test_PPMd_File_List_Extraction_Accepts_Eleven_Symbol_Stream
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Archive_Path : constant String := Base_Path ("ppmd-list-eleven-symbol.7z");
      Output_Dir   : constant String := Base_Path ("ppmd-list-eleven-symbol-output");
      Output_Path  : constant String :=
        Ada.Directories.Compose (Output_Dir, "zlib-ppmd-abcdefghijk.txt");
      Entry_Names  : constant Zlib.Text_Array :=
        [1 => US.To_Unbounded_String ("zlib-ppmd-abcdefghijk.txt")];
      Status       : Zlib.Status_Code := Zlib.Unsupported_Method;
      Expected     : constant Zlib.Byte_Array :=
        [Character'Pos ('a'), Character'Pos ('b'), Character'Pos ('c'),
         Character'Pos ('d'), Character'Pos ('e'), Character'Pos ('f'),
         Character'Pos ('g'), Character'Pos ('h'), Character'Pos ('i'),
         Character'Pos ('j'), Character'Pos ('k')];
   begin
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);

      Write_File (Archive_Path, Seven_Zip_PPMd_Eleven_Symbol_Archive);
      Zlib.Extract_Seven_Zip_Files
        (Archive_Path, Output_Dir, Entry_Names, Status);
      Assert
        (Status = Zlib.Ok,
         "native PPMd 7z file-list helper extracts eleven-symbol stream: "
         & Zlib.Status_Image (Status));
      Assert
        (Read_File (Output_Path) = Expected,
         "native PPMd 7z file-list helper writes eleven-symbol payload");

      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);
   exception
      when others =>
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);
         raise;
   end Test_PPMd_File_List_Extraction_Accepts_Eleven_Symbol_Stream;

   procedure Test_PPMd_File_List_Extraction_Accepts_Periodic_Stream
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Archive_Path : constant String := Base_Path ("ppmd-list-periodic.7z");
      Output_Dir   : constant String := Base_Path ("ppmd-list-periodic-output");
      Output_Path  : constant String :=
        Ada.Directories.Compose (Output_Dir, "zlib-ppmd-abcd-repeat.txt");
      Entry_Names  : constant Zlib.Text_Array :=
        [1 => US.To_Unbounded_String ("zlib-ppmd-abcd-repeat.txt")];
      Status       : Zlib.Status_Code := Zlib.Unsupported_Method;
      Pattern      : constant String := "abcd";
   begin
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);

      Write_File (Archive_Path, Seven_Zip_PPMd_ABCD_Periodic_Archive);
      Zlib.Extract_Seven_Zip_Files
        (Archive_Path, Output_Dir, Entry_Names, Status);
      Assert
        (Status = Zlib.Ok,
         "native PPMd 7z file-list helper extracts periodic stream: "
         & Zlib.Status_Image (Status));

      declare
         Output : constant Zlib.Byte_Array := Read_File (Output_Path);
      begin
         Assert
           (Output'Length = 40,
            "native PPMd 7z file-list helper writes periodic payload length");
         for I in Output'Range loop
            declare
               Pattern_Index : constant Positive :=
                 Pattern'First + ((I - Output'First) mod Pattern'Length);
            begin
               Assert
                 (Output (I) = Character'Pos (Pattern (Pattern_Index)),
                  "native PPMd 7z file-list helper writes periodic payload byte");
            end;
         end loop;
      end;

      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);
   exception
      when others =>
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);
         raise;
   end Test_PPMd_File_List_Extraction_Accepts_Periodic_Stream;

   procedure Test_PPMd_File_Helpers_Reject_Periodic_Bad_Unpack_CRC
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Archive      : Zlib.Byte_Array := Seven_Zip_PPMd_ABCD_Periodic_Archive;
      Archive_Path : constant String := Base_Path ("ppmd-periodic-bad-crc.7z");
      Output_Path  : constant String := Base_Path ("ppmd-periodic-bad-crc-output.bin");
      Output_Dir   : constant String := Base_Path ("ppmd-periodic-bad-crc-output");
      Entry_Names  : constant Zlib.Text_Array :=
        [1 => US.To_Unbounded_String ("zlib-ppmd-abcd-repeat.txt")];
      Expected     : Zlib.Byte_Array (1 .. 40) := [others => 0];
      Expected_CRC : Interfaces.Unsigned_32;
      CRC_Pos      : Natural := 0;
      Status       : Zlib.Status_Code := Zlib.Ok;
      Pattern      : constant String := "abcd";
   begin
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Path);
      Delete_If_Exists (Output_Dir);

      for I in Expected'Range loop
         declare
            Pattern_Index : constant Positive :=
              Pattern'First + ((I - Expected'First) mod Pattern'Length);
         begin
            Expected (I) := Zlib.Byte (Character'Pos (Pattern (Pattern_Index)));
         end;
      end loop;

      Expected_CRC := Zlib.CRC32 (Expected);
      for Pos in Seven_Zip_Header_First (Archive) .. Archive'Last - 3 loop
         if U32_LE (Archive, Pos) = Expected_CRC then
            CRC_Pos := Pos;
            exit;
         end if;
      end loop;

      Assert
        (CRC_Pos /= 0,
         "native PPMd 7z file helpers periodic unpack CRC field found");
      Set_U32_LE (Archive, CRC_Pos, Expected_CRC xor 16#FFFF_FFFF#);
      Refresh_Seven_Zip_Header_CRCs (Archive);
      Write_File (Archive_Path, Archive);

      Zlib.Extract_Seven_Zip_File
        (Archive_Path, Output_Path, "zlib-ppmd-abcd-repeat.txt", Status);
      Assert
        (Status = Zlib.Invalid_Checksum,
         "native PPMd 7z file helper rejects periodic bad unpack CRC: "
         & Zlib.Status_Image (Status));
      Assert
        (not Ada.Directories.Exists (Output_Path),
         "native PPMd 7z file helper writes no periodic bad-CRC output");

      Zlib.Extract_Seven_Zip_Files
        (Archive_Path, Output_Dir, Entry_Names, Status);
      Assert
        (Status = Zlib.Invalid_Checksum,
         "native PPMd 7z file-list helper rejects periodic bad unpack CRC: "
         & Zlib.Status_Image (Status));
      Assert
        (not Ada.Directories.Exists (Output_Dir),
         "native PPMd 7z file-list helper writes no periodic bad-CRC output");

      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Path);
      Delete_If_Exists (Output_Dir);
   exception
      when others =>
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Path);
         Delete_If_Exists (Output_Dir);
         raise;
   end Test_PPMd_File_Helpers_Reject_Periodic_Bad_Unpack_CRC;

   procedure Test_PPMd_File_Helpers_Reject_Malformed_Properties
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Archive_Path : constant String := Base_Path ("ppmd-malformed-props.7z");
      Output_Path  : constant String := Base_Path ("ppmd-malformed-props-output.bin");
      Output_Dir   : constant String := Base_Path ("ppmd-malformed-props-output");
      Entry_Names  : constant Zlib.Text_Array :=
        [1 => US.To_Unbounded_String ("input.txt")];
      Status       : Zlib.Status_Code := Zlib.Ok;
   begin
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Path);
      Delete_If_Exists (Output_Dir);

      Write_File
        (Archive_Path,
         Mutate_Seven_Zip_PPMd_Props (1, 16#0001_0000#));

      Zlib.Extract_Seven_Zip_File
        (Archive_Path, Output_Path, "input.txt", Status);
      Assert
        (Status = Zlib.Unsupported_Method,
         "native PPMd 7z file helper rejects malformed properties: "
         & Zlib.Status_Image (Status));
      Assert
        (not Ada.Directories.Exists (Output_Path),
         "native PPMd 7z file helper writes no malformed-property output");

      Zlib.Extract_Seven_Zip_Files
        (Archive_Path, Output_Dir, Entry_Names, Status);
      Assert
        (Status = Zlib.Unsupported_Method,
         "native PPMd 7z file-list helper rejects malformed properties: "
         & Zlib.Status_Image (Status));
      Assert
        (not Ada.Directories.Exists (Output_Dir),
         "native PPMd 7z file-list helper writes no malformed-property output");

      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Path);
      Delete_If_Exists (Output_Dir);
   exception
      when others =>
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Path);
         Delete_If_Exists (Output_Dir);
         raise;
   end Test_PPMd_File_Helpers_Reject_Malformed_Properties;

   procedure Test_PPMd_Creation_Rejects_Bad_Unpack_CRC
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input        : constant Zlib.Byte_Array :=
        [Character'Pos ('p'), Character'Pos ('p'), Character'Pos ('m'),
         Character'Pos ('d'), Character'Pos ('-'), Character'Pos ('c'),
         Character'Pos ('r'), Character'Pos ('c')];
      Status       : Zlib.Status_Code := Zlib.Unsupported_Method;
      Archive      : Zlib.Byte_Array :=
        Zlib.Seven_Zip_PPMd (Input, "ppmd-crc.txt", Status);
      Expected_CRC : constant Interfaces.Unsigned_32 := Zlib.CRC32 (Input);
      CRC_Pos      : Natural := 0;
   begin
      Assert
        (Status = Zlib.Ok,
         "native PPMd 7z one-shot creates bad-CRC fixture base: "
         & Zlib.Status_Image (Status));

      for Pos in Seven_Zip_Header_First (Archive) .. Archive'Last - 3 loop
         if U32_LE (Archive, Pos) = Expected_CRC then
            CRC_Pos := Pos;
            exit;
         end if;
      end loop;

      Assert
        (CRC_Pos /= 0,
         "native PPMd 7z one-shot fixture exposes unpack CRC");
      Set_U32_LE (Archive, CRC_Pos, Expected_CRC xor 16#FFFF_FFFF#);
      Refresh_Seven_Zip_Header_CRCs (Archive);

      declare
         Output : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip (Archive, "ppmd-crc.txt", Status);
      begin
         Assert
           (Status = Zlib.Invalid_Checksum,
            "native PPMd 7z one-shot rejects bad unpack CRC: "
            & Zlib.Status_Image (Status));
         Assert
           (Output'Length = 0,
            "native PPMd 7z one-shot bad unpack CRC returns no payload");
      end;
   end Test_PPMd_Creation_Rejects_Bad_Unpack_CRC;

   procedure Test_PPMd_Creation_Emits_Default_Properties
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input    : constant Zlib.Byte_Array :=
        [Character'Pos ('p'), Character'Pos ('p'), Character'Pos ('m'),
         Character'Pos ('d'), Character'Pos ('-'), Character'Pos ('p'),
         Character'Pos ('r'), Character'Pos ('o'), Character'Pos ('p'),
         Character'Pos ('s')];
      Status   : Zlib.Status_Code := Zlib.Unsupported_Method;
      Archive  : constant Zlib.Byte_Array :=
        Zlib.Seven_Zip_PPMd (Input, "ppmd-props.txt", Status);
      Prop_Pos : constant Natural := Seven_Zip_PPMd_Props_Pos (Archive);
   begin
      Assert
        (Status = Zlib.Ok,
         "native PPMd 7z one-shot creates property fixture: "
         & Zlib.Status_Image (Status));
      Assert
        (Prop_Pos /= 0,
         "native PPMd 7z one-shot emits PPMd coder properties");
      Assert
        (Archive (Prop_Pos) = 6,
         "native PPMd 7z one-shot emits default PPMd order");
      Assert
        (U32_LE (Archive, Prop_Pos + 1) = 16#0100_0000#,
         "native PPMd 7z one-shot emits default PPMd memory");
   end Test_PPMd_Creation_Emits_Default_Properties;

   procedure Test_PPMd_One_Shot_Creation_Native_Roundtrip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status        : Zlib.Status_Code := Zlib.Unsupported_Method;
      Small_Input   : constant Zlib.Byte_Array :=
        [Character'Pos ('p'), Character'Pos ('p'), Character'Pos ('m'),
         Character'Pos ('d'), Character'Pos (' '), Character'Pos ('o'),
         Character'Pos ('u'), Character'Pos ('t'), Character'Pos ('p'),
         Character'Pos ('u'), Character'Pos ('t'), 10];
      Single_Input  : constant Zlib.Byte_Array :=
        [1 => Character'Pos ('Q')];
      Tail_Repeat_Input : constant Zlib.Byte_Array :=
        [Character'Pos ('A'), Character'Pos ('B'), Character'Pos ('B')];
      Three_Distinct_Input : constant Zlib.Byte_Array :=
        [Character'Pos ('A'), Character'Pos ('B'), Character'Pos ('C')];
      Three_Return_Input : constant Zlib.Byte_Array :=
        [Character'Pos ('A'), Character'Pos ('B'), Character'Pos ('A')];
      Four_Distinct_Input : constant Zlib.Byte_Array :=
        [Character'Pos ('A'), Character'Pos ('B'), Character'Pos ('C'),
         Character'Pos ('D')];
      Four_Return_Input : constant Zlib.Byte_Array :=
        [Character'Pos ('A'), Character'Pos ('B'), Character'Pos ('A'),
         Character'Pos ('C')];
      Tail_Run_Input : constant Zlib.Byte_Array :=
        [Character'Pos ('A'), Character'Pos ('B'), Character'Pos ('C'),
         Character'Pos ('C'), Character'Pos ('C')];
      Distinct_Tail_Run_Input : constant Zlib.Byte_Array :=
        [Character'Pos ('A'), Character'Pos ('B'), Character'Pos ('C'),
         Character'Pos ('D'), Character'Pos ('D'), Character'Pos ('D')];
      Head_Repeat_Input : constant Zlib.Byte_Array :=
        [Character'Pos ('A'), Character'Pos ('A'), Character'Pos ('B')];
      Head_Run_Input : constant Zlib.Byte_Array :=
        [Character'Pos ('A'), Character'Pos ('A'), Character'Pos ('A'),
         Character'Pos ('B')];
      Head_Run_Suffix_Input : constant Zlib.Byte_Array :=
        [Character'Pos ('A'), Character'Pos ('A'), Character'Pos ('A'),
         Character'Pos ('B'), Character'Pos ('C')];
      Head_Repeat_Suffix_Input : constant Zlib.Byte_Array :=
        [Character'Pos ('A'), Character'Pos ('A'), Character'Pos ('B'),
         Character'Pos ('C'), Character'Pos ('D')];
      Middle_Run_Input : constant Zlib.Byte_Array :=
        [Character'Pos ('A'), Character'Pos ('B'), Character'Pos ('B'),
         Character'Pos ('B'), Character'Pos ('C')];
      Middle_Run_Suffix_Input : constant Zlib.Byte_Array :=
        [Character'Pos ('A'), Character'Pos ('B'), Character'Pos ('C'),
         Character'Pos ('C'), Character'Pos ('D'), Character'Pos ('E')];
      Multi_Run_Input : constant Zlib.Byte_Array :=
        [Character'Pos ('A'), Character'Pos ('A'), Character'Pos ('B'),
         Character'Pos ('B'), Character'Pos ('C'), Character'Pos ('C')];
      Multi_Run_Tail_Input : constant Zlib.Byte_Array :=
        [Character'Pos ('A'), Character'Pos ('B'), Character'Pos ('C'),
         Character'Pos ('C'), Character'Pos ('D'), Character'Pos ('D')];
      Mixed_Run_Input : constant Zlib.Byte_Array :=
        [Character'Pos ('A'), Character'Pos ('A'), Character'Pos ('B'),
         Character'Pos ('C'), Character'Pos ('C'), Character'Pos ('D'),
         Character'Pos ('E')];
      Triple_Repeat_Input : constant Zlib.Byte_Array :=
        [1 .. 3 => Character'Pos ('R')];
      Quad_Repeat_Input : constant Zlib.Byte_Array :=
        [1 .. 4 => Character'Pos ('S')];
      Five_Repeat_Input : constant Zlib.Byte_Array :=
        [1 .. 5 => Character'Pos ('T')];
      Sixteen_Repeat_Input : constant Zlib.Byte_Array :=
        [1 .. 16 => Character'Pos ('U')];
      Repeat_Input  : constant Zlib.Byte_Array (1 .. 200) :=
        [others => Character'Pos ('A')];
      Period2_Input : Zlib.Byte_Array (1 .. 40);
      Period4_Input : Zlib.Byte_Array (1 .. 40);
      Period16_Input : Zlib.Byte_Array (1 .. 160);
      Period64_Input : Zlib.Byte_Array (1 .. 1024);
      Shifted_Period64_Input : Zlib.Byte_Array (20 .. 1043);
      Long_Alternating_Input : Zlib.Byte_Array (1 .. 32);
      Long_Rotating_Input : Zlib.Byte_Array (1 .. 48);
      Long_Sequential_Input : Zlib.Byte_Array (1 .. 96);
      Long_Pair_Run_Input : Zlib.Byte_Array (1 .. 120);
      Long_Mixed_Run_Input : Zlib.Byte_Array (1 .. 150);
      Rescale_Rotating_Input : Zlib.Byte_Array (1 .. 300);
      Rescale_Pair_Run_Input : Zlib.Byte_Array (1 .. 512);
      Long_Tail_Run_Input : Zlib.Byte_Array (1 .. 256);
      Long_Prefix_Run_Input : Zlib.Byte_Array (1 .. 256);
      Long_Infix_Run_Input : Zlib.Byte_Array (1 .. 256);
      Long_Head_Run_Input : Zlib.Byte_Array (1 .. 302);
      Big_Rotating_Input : Zlib.Byte_Array (1 .. 2048);
      Big_Pair_Run_Input : Zlib.Byte_Array (1 .. 2048);
      Huge_Rotating_Input : Zlib.Byte_Array (1 .. 8192);
      Huge_Pair_Run_Input : Zlib.Byte_Array (1 .. 8192);
      Byte_Input    : Zlib.Byte_Array (1 .. 256);
      Adaptive_Input : Zlib.Byte_Array (1 .. 1024);
   begin
      for I in Period2_Input'Range loop
         Period2_Input (I) :=
           (if (I - Period2_Input'First) mod 2 = 0
            then Character'Pos ('A')
            else Character'Pos ('B'));
      end loop;

      for I in Period4_Input'Range loop
         Period4_Input (I) :=
           Zlib.Byte
             (Character'Pos ('A') + ((I - Period4_Input'First) mod 4));
      end loop;

      for I in Period16_Input'Range loop
         Period16_Input (I) :=
           Zlib.Byte
             (Character'Pos ('a') + ((I - Period16_Input'First) mod 16));
      end loop;

      for I in Period64_Input'Range loop
         Period64_Input (I) := Zlib.Byte ((I - Period64_Input'First) mod 64);
      end loop;

      for I in Shifted_Period64_Input'Range loop
         Shifted_Period64_Input (I) :=
           Zlib.Byte ((I - Shifted_Period64_Input'First) mod 64);
      end loop;

      for I in Long_Alternating_Input'Range loop
         Long_Alternating_Input (I) :=
           (if (I - Long_Alternating_Input'First) mod 2 = 0
            then Character'Pos ('A')
            else Character'Pos ('B'));
      end loop;

      for I in Long_Rotating_Input'Range loop
         Long_Rotating_Input (I) :=
           Zlib.Byte
             (Character'Pos ('A') + ((I - Long_Rotating_Input'First) mod 6));
      end loop;

      for I in Long_Sequential_Input'Range loop
         Long_Sequential_Input (I) :=
           Zlib.Byte
             (Character'Pos ('A') + ((I - Long_Sequential_Input'First) mod 8));
      end loop;

      for I in Long_Pair_Run_Input'Range loop
         Long_Pair_Run_Input (I) :=
           Zlib.Byte
             (Character'Pos ('A')
              + (((I - Long_Pair_Run_Input'First) / 2) mod 8));
      end loop;

      for I in Long_Mixed_Run_Input'Range loop
         declare
            Offset : constant Natural := I - Long_Mixed_Run_Input'First;
            Block  : constant Natural := Offset / 5;
            Slot   : constant Natural := Offset mod 5;
         begin
            Long_Mixed_Run_Input (I) :=
              Zlib.Byte
                (Character'Pos ('A') + ((Block * 2 + Natural'Min (Slot, 2)) mod 12));
         end;
      end loop;

      for I in Rescale_Rotating_Input'Range loop
         Rescale_Rotating_Input (I) :=
           Zlib.Byte
             (Character'Pos ('A') + ((I - Rescale_Rotating_Input'First) mod 8));
      end loop;

      for I in Rescale_Pair_Run_Input'Range loop
         Rescale_Pair_Run_Input (I) :=
           Zlib.Byte
             (Character'Pos ('A')
              + (((I - Rescale_Pair_Run_Input'First) / 2) mod 8));
      end loop;

      for I in Long_Tail_Run_Input'Range loop
         Long_Tail_Run_Input (I) :=
           (if I < Long_Tail_Run_Input'Last - 119
            then Zlib.Byte
              (Character'Pos ('A') + ((I - Long_Tail_Run_Input'First) mod 16))
            else Character'Pos ('Z'));
      end loop;

      for I in Long_Prefix_Run_Input'Range loop
         Long_Prefix_Run_Input (I) :=
           (if I <= Long_Prefix_Run_Input'First + 119
            then Character'Pos ('Z')
            else Zlib.Byte
              (Character'Pos ('A') + ((I - Long_Prefix_Run_Input'First) mod 16)));
      end loop;

      for I in Long_Infix_Run_Input'Range loop
         Long_Infix_Run_Input (I) :=
           (if I in Long_Infix_Run_Input'First + 80 .. Long_Infix_Run_Input'First + 179
            then Character'Pos ('Z')
            else Zlib.Byte
              (Character'Pos ('A') + ((I - Long_Infix_Run_Input'First) mod 16)));
      end loop;

      for I in Long_Head_Run_Input'Range loop
         Long_Head_Run_Input (I) :=
           (if I < Long_Head_Run_Input'Last - 1
            then Character'Pos ('A')
            elsif I = Long_Head_Run_Input'Last - 1
            then Character'Pos ('B')
            else Character'Pos ('C'));
      end loop;

      for I in Big_Rotating_Input'Range loop
         Big_Rotating_Input (I) :=
           Zlib.Byte
             (Character'Pos ('A') + ((I - Big_Rotating_Input'First) mod 16));
      end loop;

      for I in Big_Pair_Run_Input'Range loop
         Big_Pair_Run_Input (I) :=
           Zlib.Byte
             (Character'Pos ('A')
              + (((I - Big_Pair_Run_Input'First) / 2) mod 16));
      end loop;

      for I in Huge_Rotating_Input'Range loop
         Huge_Rotating_Input (I) :=
           Zlib.Byte
             (Character'Pos ('A') + ((I - Huge_Rotating_Input'First) mod 16));
      end loop;

      for I in Huge_Pair_Run_Input'Range loop
         Huge_Pair_Run_Input (I) :=
           Zlib.Byte
             (Character'Pos ('A')
              + (((I - Huge_Pair_Run_Input'First) / 2) mod 16));
      end loop;

      for I in Byte_Input'Range loop
         Byte_Input (I) := Zlib.Byte ((I - Byte_Input'First) mod 256);
      end loop;

      for I in Adaptive_Input'Range loop
         Adaptive_Input (I) :=
           Zlib.Byte
             ((I * 17 + (I / 3) * 29 + (I mod 11) * 7) mod 256);
      end loop;

      declare
         Empty_Input : constant Zlib.Byte_Array (1 .. 0) := [others => 0];
         Archive     : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd (Empty_Input, "empty.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates empty archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip (Archive, "empty.bin", Status) =
            Empty_Input,
            "native PPMd 7z one-shot roundtrips empty payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot extracts empty archive: "
            & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd (Single_Input, "single.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates single-symbol archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip (Archive, "single.bin", Status) =
            Single_Input,
            "native PPMd 7z one-shot roundtrips single-symbol payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot extracts single-symbol archive: "
            & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd
             (Tail_Repeat_Input, "tail-repeat.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates tail-repeat archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip
              (Archive, "tail-repeat.bin", Status) = Tail_Repeat_Input,
            "native PPMd 7z one-shot roundtrips tail-repeat payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot extracts tail-repeat archive: "
            & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd
             (Three_Distinct_Input, "three-distinct.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates three-distinct archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip
              (Archive, "three-distinct.bin", Status) = Three_Distinct_Input,
            "native PPMd 7z one-shot roundtrips three-distinct payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot extracts three-distinct archive: "
            & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd
             (Three_Return_Input, "three-return.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates three-return archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip
              (Archive, "three-return.bin", Status) = Three_Return_Input,
            "native PPMd 7z one-shot roundtrips three-return payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot extracts three-return archive: "
            & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd
             (Four_Distinct_Input, "four-distinct.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates four-distinct archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip
              (Archive, "four-distinct.bin", Status) = Four_Distinct_Input,
            "native PPMd 7z one-shot roundtrips four-distinct payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot extracts four-distinct archive: "
            & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd
             (Four_Return_Input, "four-return.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates four-return archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip
              (Archive, "four-return.bin", Status) = Four_Return_Input,
            "native PPMd 7z one-shot roundtrips four-return payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot extracts four-return archive: "
            & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd
             (Tail_Run_Input, "tail-run.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates tail-run archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip
              (Archive, "tail-run.bin", Status) = Tail_Run_Input,
            "native PPMd 7z one-shot roundtrips tail-run payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot extracts tail-run archive: "
            & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd
             (Distinct_Tail_Run_Input, "distinct-tail-run.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates distinct-tail-run archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip
              (Archive, "distinct-tail-run.bin", Status) =
            Distinct_Tail_Run_Input,
            "native PPMd 7z one-shot roundtrips distinct-tail-run payload");
         Assert
           (Status = Zlib.Ok,
           "native PPMd 7z one-shot extracts distinct-tail-run archive: "
           & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd
             (Head_Repeat_Input, "head-repeat.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates head-repeat archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip
              (Archive, "head-repeat.bin", Status) = Head_Repeat_Input,
            "native PPMd 7z one-shot roundtrips head-repeat payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot extracts head-repeat archive: "
            & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd
             (Head_Run_Input, "head-run.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates head-run archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip
              (Archive, "head-run.bin", Status) = Head_Run_Input,
            "native PPMd 7z one-shot roundtrips head-run payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot extracts head-run archive: "
            & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd
             (Head_Run_Suffix_Input, "head-run-suffix.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates head-run-suffix archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip
              (Archive, "head-run-suffix.bin", Status) =
            Head_Run_Suffix_Input,
            "native PPMd 7z one-shot roundtrips head-run-suffix payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot extracts head-run-suffix archive: "
            & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd
             (Head_Repeat_Suffix_Input, "head-repeat-suffix.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates head-repeat-suffix archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip
              (Archive, "head-repeat-suffix.bin", Status) =
            Head_Repeat_Suffix_Input,
            "native PPMd 7z one-shot roundtrips head-repeat-suffix payload");
         Assert
           (Status = Zlib.Ok,
           "native PPMd 7z one-shot extracts head-repeat-suffix archive: "
           & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd
             (Middle_Run_Input, "middle-run.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates middle-run archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip
              (Archive, "middle-run.bin", Status) = Middle_Run_Input,
            "native PPMd 7z one-shot roundtrips middle-run payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot extracts middle-run archive: "
            & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd
             (Middle_Run_Suffix_Input, "middle-run-suffix.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates middle-run-suffix archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip
              (Archive, "middle-run-suffix.bin", Status) =
            Middle_Run_Suffix_Input,
            "native PPMd 7z one-shot roundtrips middle-run-suffix payload");
         Assert
           (Status = Zlib.Ok,
           "native PPMd 7z one-shot extracts middle-run-suffix archive: "
           & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd
             (Multi_Run_Input, "multi-run.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates multi-run archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip
              (Archive, "multi-run.bin", Status) = Multi_Run_Input,
            "native PPMd 7z one-shot roundtrips multi-run payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot extracts multi-run archive: "
            & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd
             (Multi_Run_Tail_Input, "multi-run-tail.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates multi-run-tail archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip
              (Archive, "multi-run-tail.bin", Status) = Multi_Run_Tail_Input,
            "native PPMd 7z one-shot roundtrips multi-run-tail payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot extracts multi-run-tail archive: "
            & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd
             (Mixed_Run_Input, "mixed-run.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates mixed-run archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip
              (Archive, "mixed-run.bin", Status) = Mixed_Run_Input,
            "native PPMd 7z one-shot roundtrips mixed-run payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot extracts mixed-run archive: "
            & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd
             (Long_Alternating_Input, "long-alternating.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates long-alternating archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip
              (Archive, "long-alternating.bin", Status) =
            Long_Alternating_Input,
            "native PPMd 7z one-shot roundtrips long-alternating payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot extracts long-alternating archive: "
            & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd
             (Long_Rotating_Input, "long-rotating.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates long-rotating archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip
              (Archive, "long-rotating.bin", Status) =
            Long_Rotating_Input,
            "native PPMd 7z one-shot roundtrips long-rotating payload");
         Assert
           (Status = Zlib.Ok,
           "native PPMd 7z one-shot extracts long-rotating archive: "
           & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd
             (Long_Sequential_Input, "long-sequential.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates long-sequential archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip
              (Archive, "long-sequential.bin", Status) =
            Long_Sequential_Input,
            "native PPMd 7z one-shot roundtrips long-sequential payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot extracts long-sequential archive: "
            & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd
             (Long_Pair_Run_Input, "long-pair-run.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates long-pair-run archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip
              (Archive, "long-pair-run.bin", Status) =
            Long_Pair_Run_Input,
            "native PPMd 7z one-shot roundtrips long-pair-run payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot extracts long-pair-run archive: "
            & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd
             (Long_Mixed_Run_Input, "long-mixed-run.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates long-mixed-run archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip
              (Archive, "long-mixed-run.bin", Status) =
            Long_Mixed_Run_Input,
            "native PPMd 7z one-shot roundtrips long-mixed-run payload");
         Assert
           (Status = Zlib.Ok,
           "native PPMd 7z one-shot extracts long-mixed-run archive: "
           & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd
             (Rescale_Rotating_Input, "rescale-rotating.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates rescale-rotating archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip
              (Archive, "rescale-rotating.bin", Status) =
            Rescale_Rotating_Input,
            "native PPMd 7z one-shot roundtrips rescale-rotating payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot extracts rescale-rotating archive: "
            & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd
             (Rescale_Pair_Run_Input, "rescale-pair-run.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates rescale-pair-run archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip
              (Archive, "rescale-pair-run.bin", Status) =
            Rescale_Pair_Run_Input,
            "native PPMd 7z one-shot roundtrips rescale-pair-run payload");
         Assert
           (Status = Zlib.Ok,
           "native PPMd 7z one-shot extracts rescale-pair-run archive: "
           & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd
             (Long_Head_Run_Input, "long-head-run.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates long-head-run archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip
              (Archive, "long-head-run.bin", Status) =
            Long_Head_Run_Input,
            "native PPMd 7z one-shot roundtrips long-head-run payload");
         Assert
           (Status = Zlib.Ok,
           "native PPMd 7z one-shot extracts long-head-run archive: "
           & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd
             (Long_Tail_Run_Input, "long-tail-run.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates long-tail-run archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip
              (Archive, "long-tail-run.bin", Status) = Long_Tail_Run_Input,
            "native PPMd 7z one-shot roundtrips long-tail-run payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot extracts long-tail-run archive: "
            & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd
             (Long_Prefix_Run_Input, "long-prefix-run.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates long-prefix-run archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip
              (Archive, "long-prefix-run.bin", Status) = Long_Prefix_Run_Input,
            "native PPMd 7z one-shot roundtrips long-prefix-run payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot extracts long-prefix-run archive: "
            & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd
             (Long_Infix_Run_Input, "long-infix-run.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates long-infix-run archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip
              (Archive, "long-infix-run.bin", Status) = Long_Infix_Run_Input,
            "native PPMd 7z one-shot roundtrips long-infix-run payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot extracts long-infix-run archive: "
            & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd
             (Big_Rotating_Input, "big-rotating.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates big-rotating archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip
              (Archive, "big-rotating.bin", Status) = Big_Rotating_Input,
            "native PPMd 7z one-shot roundtrips big-rotating payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot extracts big-rotating archive: "
            & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd
             (Big_Pair_Run_Input, "big-pair-run.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates big-pair-run archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip
              (Archive, "big-pair-run.bin", Status) = Big_Pair_Run_Input,
            "native PPMd 7z one-shot roundtrips big-pair-run payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot extracts big-pair-run archive: "
            & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd
             (Huge_Rotating_Input, "huge-rotating.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates huge-rotating archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip
              (Archive, "huge-rotating.bin", Status) = Huge_Rotating_Input,
            "native PPMd 7z one-shot roundtrips huge-rotating payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot extracts huge-rotating archive: "
            & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd
             (Huge_Pair_Run_Input, "huge-pair-run.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates huge-pair-run archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip
              (Archive, "huge-pair-run.bin", Status) = Huge_Pair_Run_Input,
            "native PPMd 7z one-shot roundtrips huge-pair-run payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot extracts huge-pair-run archive: "
            & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd
             (Triple_Repeat_Input, "triple-repeat.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates triple-repeat archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip
              (Archive, "triple-repeat.bin", Status) = Triple_Repeat_Input,
            "native PPMd 7z one-shot roundtrips triple-repeat payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot extracts triple-repeat archive: "
            & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd
             (Quad_Repeat_Input, "quad-repeat.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates quad-repeat archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip
              (Archive, "quad-repeat.bin", Status) = Quad_Repeat_Input,
            "native PPMd 7z one-shot roundtrips quad-repeat payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot extracts quad-repeat archive: "
            & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd
             (Five_Repeat_Input, "five-repeat.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates five-repeat archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip
              (Archive, "five-repeat.bin", Status) = Five_Repeat_Input,
            "native PPMd 7z one-shot roundtrips five-repeat payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot extracts five-repeat archive: "
            & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd
             (Sixteen_Repeat_Input, "sixteen-repeat.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates sixteen-repeat archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip
              (Archive, "sixteen-repeat.bin", Status) = Sixteen_Repeat_Input,
            "native PPMd 7z one-shot roundtrips sixteen-repeat payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot extracts sixteen-repeat archive: "
            & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd (Small_Input, "small.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates small archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip_Stored (Archive, "small.bin", Status) =
            Small_Input,
            "native PPMd 7z one-shot roundtrips small payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot extracts small archive: "
            & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd (Repeat_Input, "repeat.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates repeated archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip_Stored (Archive, "repeat.bin", Status) =
            Repeat_Input,
            "native PPMd 7z one-shot roundtrips repeated payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot extracts repeated archive: "
            & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd (Period2_Input, "period2.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates period-2 archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip_Stored (Archive, "period2.bin", Status) =
            Period2_Input,
            "native PPMd 7z one-shot roundtrips period-2 payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot extracts period-2 archive: "
            & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd (Period4_Input, "period4.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates period-4 archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip_Stored (Archive, "period4.bin", Status) =
            Period4_Input,
            "native PPMd 7z one-shot roundtrips period-4 payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot extracts period-4 archive: "
            & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd (Period16_Input, "period16.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates period-16 archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip_Stored (Archive, "period16.bin", Status) =
            Period16_Input,
            "native PPMd 7z one-shot roundtrips period-16 payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot extracts period-16 archive: "
            & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd (Period64_Input, "period64.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates period-64 archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip_Stored (Archive, "period64.bin", Status) =
            Period64_Input,
            "native PPMd 7z one-shot roundtrips period-64 payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot extracts period-64 archive: "
            & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd
             (Shifted_Period64_Input, "shifted-period64.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates shifted period-64 archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip_Stored
              (Archive, "shifted-period64.bin", Status) =
            Shifted_Period64_Input,
            "native PPMd 7z one-shot roundtrips shifted period-64 payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot extracts shifted period-64 archive: "
            & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd (Byte_Input, "bytes.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates byte archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip (Archive, "bytes.bin", Status) =
            Byte_Input,
            "native PPMd 7z one-shot roundtrips byte payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot extracts byte archive: "
            & Zlib.Status_Image (Status));
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_PPMd (Adaptive_Input, "adaptive.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot creates adaptive archive: "
            & Zlib.Status_Image (Status));
         Assert
           (Zlib.Extract_Seven_Zip (Archive, "adaptive.bin", Status) =
            Adaptive_Input,
            "native PPMd 7z one-shot roundtrips adaptive payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z one-shot extracts adaptive archive: "
            & Zlib.Status_Image (Status));
      end;
   end Test_PPMd_One_Shot_Creation_Native_Roundtrip;

   procedure Test_PPMd_File_Creation_Native_Roundtrip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input_Path   : constant String := Base_Path ("ppmd-source.bin");
      Archive_Path : constant String := Base_Path ("ppmd-created.7z");
      Repeat_Input_Path : constant String :=
        Base_Path ("ppmd-repeat-source.bin");
      Repeat_Archive_Path : constant String :=
        Base_Path ("ppmd-repeat-created.7z");
      Period_Input_Path : constant String :=
        Base_Path ("ppmd-period-source.bin");
      Period_Archive_Path : constant String :=
        Base_Path ("ppmd-period-created.7z");
      Status       : Zlib.Status_Code := Zlib.Unsupported_Method;
      Input_Data   : Zlib.Byte_Array (1 .. 1024);
      Repeat_Data  : constant Zlib.Byte_Array (1 .. 192) :=
        [others => 16#52#];
      Period_Data  : Zlib.Byte_Array (1 .. 1024);
   begin
      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Repeat_Input_Path);
      Delete_If_Exists (Repeat_Archive_Path);
      Delete_If_Exists (Period_Input_Path);
      Delete_If_Exists (Period_Archive_Path);

      for I in Input_Data'Range loop
         Input_Data (I) :=
           Zlib.Byte
             ((I * 19 + (I / 5) * 31 + (I mod 13) * 11) mod 256);
      end loop;
      for I in Period_Data'Range loop
         Period_Data (I) :=
           Zlib.Byte ((I - Period_Data'First) mod 64);
      end loop;

      Write_File (Input_Path, Input_Data);
      Zlib.Seven_Zip_PPMd_File
        (Input_Path, Archive_Path, "payload.txt", Status);
      Assert
        (Status = Zlib.Ok,
         "native PPMd 7z file helper creates archive: "
         & Zlib.Status_Image (Status));

      declare
         Archive : constant Zlib.Byte_Array := Read_File (Archive_Path);
      begin
         Assert
           (Zlib.Extract_Seven_Zip_Stored
              (Archive, "payload.txt", Status) =
            Input_Data,
            "native PPMd 7z file helper roundtrips payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z file helper archive extracts: "
            & Zlib.Status_Image (Status));
      end;

      Write_File (Repeat_Input_Path, Repeat_Data);
      Zlib.Seven_Zip_PPMd_File
        (Repeat_Input_Path, Repeat_Archive_Path, "repeat.bin", Status);
      Assert
        (Status = Zlib.Ok,
         "native PPMd 7z file helper creates repeated archive: "
         & Zlib.Status_Image (Status));

      declare
         Archive : constant Zlib.Byte_Array := Read_File (Repeat_Archive_Path);
      begin
         Assert
           (Zlib.Extract_Seven_Zip_Stored
              (Archive, "repeat.bin", Status) =
            Repeat_Data,
            "native PPMd 7z file helper roundtrips repeated payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z file helper repeated archive extracts: "
            & Zlib.Status_Image (Status));
      end;

      Write_File (Period_Input_Path, Period_Data);
      Zlib.Seven_Zip_PPMd_File
        (Period_Input_Path, Period_Archive_Path, "period.bin", Status);
      Assert
        (Status = Zlib.Ok,
         "native PPMd 7z file helper creates periodic archive: "
         & Zlib.Status_Image (Status));

      declare
         Archive : constant Zlib.Byte_Array := Read_File (Period_Archive_Path);
      begin
         Assert
           (Archive'Length < Period_Data'Length,
            "native PPMd 7z file helper period-64 archive uses compact coding");
         Assert
           (Zlib.Extract_Seven_Zip_Stored
              (Archive, "period.bin", Status) =
            Period_Data,
            "native PPMd 7z file helper roundtrips periodic payload");
         Assert
           (Status = Zlib.Ok,
            "native PPMd 7z file helper periodic archive extracts: "
            & Zlib.Status_Image (Status));
      end;

      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Repeat_Input_Path);
      Delete_If_Exists (Repeat_Archive_Path);
      Delete_If_Exists (Period_Input_Path);
      Delete_If_Exists (Period_Archive_Path);
   exception
      when others =>
         Delete_If_Exists (Input_Path);
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Repeat_Input_Path);
         Delete_If_Exists (Repeat_Archive_Path);
         Delete_If_Exists (Period_Input_Path);
         Delete_If_Exists (Period_Archive_Path);
         raise;
   end Test_PPMd_File_Creation_Native_Roundtrip;

   procedure Test_Deflate_Level_File_Roundtrip_Native
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input_Path   : constant String := Base_Path ("deflate-level-input.bin");
      Archive_Path : constant String := Base_Path ("deflate-level.7z");
      Output_Path  : constant String := Base_Path ("deflate-level-output.bin");
      Input_Data   : constant Zlib.Byte_Array :=
        [1 .. 512 => 16#44#];
      Status       : Zlib.Status_Code := Zlib.Ok;
   begin
      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Path);

      Write_File (Input_Path, Input_Data);
      Zlib.Seven_Zip_Deflate_File
        (Input_Path, Archive_Path, "payload.txt", Zlib.Default_Level, Status);
      Assert (Status = Zlib.Ok, "native Deflate level 7z file creation");
      Zlib.Extract_Seven_Zip_Stored_File
        (Archive_Path, Output_Path, "payload.txt", Status);
      Assert (Status = Zlib.Ok, "native Deflate level 7z file extraction");
      Assert
        (Read_File (Output_Path) = Input_Data,
         "native Deflate level 7z file helper roundtrip payload");

      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Path);
   exception
      when others =>
         Delete_If_Exists (Input_Path);
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Path);
         raise;
   end Test_Deflate_Level_File_Roundtrip_Native;

   procedure Test_File_Extraction_Creates_Parent_Directories
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input_Path   : constant String := Base_Path ("nested-output-input.bin");
      Archive_Path : constant String := Base_Path ("nested-output.7z");
      Output_Root  : constant String := Base_Path ("nested-output");
      Output_Path  : constant String :=
        Ada.Directories.Compose
          (Ada.Directories.Compose (Output_Root, "a"), "payload.bin");
      Input_Data   : constant Zlib.Byte_Array :=
        [16#6E#, 16#65#, 16#73#, 16#74#, 16#65#, 16#64#];
      Status       : Zlib.Status_Code := Zlib.Ok;
   begin
      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Root);

      Write_File (Input_Path, Input_Data);
      Zlib.Seven_Zip_Deflate_File
        (Input_Path, Archive_Path, "payload.txt", Status);
      Assert
        (Status = Zlib.Ok,
         "native Deflate 7z nested-output fixture creation");

      Zlib.Extract_Seven_Zip_File
        (Archive_Path, Output_Path, "payload.txt", Status);
      Assert
        (Status = Zlib.Ok,
         "native 7z single-entry extraction creates parent directories");
      Assert
        (Read_File (Output_Path) = Input_Data,
         "native 7z single-entry nested extraction writes payload");

      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Root);
   exception
      when others =>
         Delete_If_Exists (Input_Path);
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Root);
         raise;
   end Test_File_Extraction_Creates_Parent_Directories;

   procedure Test_Compressed_File_Extraction_Rejects_Directory_Output
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      type File_Writer is access procedure
        (Input_Path  : String;
         Output_Path : String;
         Entry_Name  : String;
         Status      : out Zlib.Status_Code);

      procedure Check_Writer
        (Writer : File_Writer;
         Label  : String;
         Suffix : String)
      is
         Input_Path   : constant String :=
           Base_Path (Suffix & "-single-output-input.bin");
         Archive_Path : constant String :=
           Base_Path (Suffix & "-single-output.7z");
         Output_Path  : constant String :=
           Base_Path (Suffix & "-single-output-dir");
         Marker_Path  : constant String :=
           Ada.Directories.Compose (Output_Path, "marker.bin");
         Input_Data   : constant Zlib.Byte_Array :=
           [16#73#, 16#69#, 16#6E#, 16#67#, 16#6C#, 16#65#];
         Marker_Data  : constant Zlib.Byte_Array :=
           [16#6D#, 16#61#, 16#72#, 16#6B#];
         Status       : Zlib.Status_Code := Zlib.Ok;
      begin
         Delete_If_Exists (Input_Path);
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Path);

         Write_File (Input_Path, Input_Data);
         Writer.all (Input_Path, Archive_Path, "payload.txt", Status);
         Assert
           (Status = Zlib.Ok,
            Label & " single-entry output-error fixture creation status");

         Ada.Directories.Create_Path (Output_Path);
         Write_File (Marker_Path, Marker_Data);

         Zlib.Extract_Seven_Zip_File
           (Archive_Path, Output_Path, "payload.txt", Status);
         Assert
           (Status = Zlib.Output_File_Error,
            Label & " single-entry extract rejects directory output path");
         Assert
           (Ada.Directories.Kind (Output_Path) = Ada.Directories.Directory,
            Label & " single-entry directory output target remains a directory");
         Assert
           (Read_File (Marker_Path) = Marker_Data,
            Label & " single-entry directory output marker is preserved");

         Delete_If_Exists (Input_Path);
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Path);
      exception
         when others =>
            Delete_If_Exists (Input_Path);
            Delete_If_Exists (Archive_Path);
            Delete_If_Exists (Output_Path);
            raise;
      end Check_Writer;
   begin
      Check_Writer
        (Zlib.Seven_Zip_Deflate_File'Access, "Deflate", "deflate");
      Check_Writer
        (Zlib.Seven_Zip_BZip2_File'Access, "BZip2", "bzip2");
      Check_Writer
        (Zlib.Seven_Zip_LZMA_File'Access, "LZMA", "lzma");
      Check_Writer
        (Zlib.Seven_Zip_LZMA2_File'Access, "LZMA2", "lzma2");
      Check_Writer
        (Zlib.Seven_Zip_PPMd_File'Access, "PPMd", "ppmd");
   end Test_Compressed_File_Extraction_Rejects_Directory_Output;

   procedure Test_Compressed_File_Creation_Rejects_Directory_Output
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      type File_Writer is access procedure
        (Input_Path  : String;
         Output_Path : String;
         Entry_Name  : String;
         Status      : out Zlib.Status_Code);

      procedure Deflate_Level_File
        (Input_Path  : String;
         Output_Path : String;
         Entry_Name  : String;
         Status      : out Zlib.Status_Code) is
      begin
         Zlib.Seven_Zip_Deflate_File
           (Input_Path, Output_Path, Entry_Name, Zlib.Default_Level, Status);
      end Deflate_Level_File;

      procedure Check_Writer
        (Writer : File_Writer;
         Label  : String;
         Suffix : String)
      is
         Input_Path   : constant String :=
           Base_Path (Suffix & "-single-create-input.bin");
         Archive_Path : constant String :=
           Base_Path (Suffix & "-single-create-output");
         Marker_Path  : constant String :=
           Ada.Directories.Compose (Archive_Path, "marker.bin");
         Input_Data   : constant Zlib.Byte_Array :=
           [16#63#, 16#72#, 16#65#, 16#61#, 16#74#, 16#65#];
         Marker_Data  : constant Zlib.Byte_Array :=
           [16#6D#, 16#61#, 16#72#, 16#6B#];
         Status       : Zlib.Status_Code := Zlib.Ok;
      begin
         Delete_If_Exists (Input_Path);
         Delete_If_Exists (Archive_Path);

         Write_File (Input_Path, Input_Data);
         Ada.Directories.Create_Path (Archive_Path);
         Write_File (Marker_Path, Marker_Data);

         Writer.all (Input_Path, Archive_Path, "payload.txt", Status);
         Assert
           (Status = Zlib.Output_File_Error,
            Label & " single-entry creation rejects directory output path");
         Assert
           (Ada.Directories.Kind (Archive_Path) = Ada.Directories.Directory,
            Label & " single-entry creation output path remains a directory");
         Assert
           (Read_File (Marker_Path) = Marker_Data,
            Label & " single-entry creation marker is preserved");

         Delete_If_Exists (Input_Path);
         Delete_If_Exists (Archive_Path);
      exception
         when others =>
            Delete_If_Exists (Input_Path);
            Delete_If_Exists (Archive_Path);
            raise;
      end Check_Writer;
   begin
      Check_Writer
        (Zlib.Seven_Zip_Deflate_File'Access, "Deflate", "deflate");
      Check_Writer
        (Deflate_Level_File'Access, "Deflate level", "deflate-level");
      Check_Writer
        (Zlib.Seven_Zip_BZip2_File'Access, "BZip2", "bzip2");
      Check_Writer
        (Zlib.Seven_Zip_LZMA_File'Access, "LZMA", "lzma");
      Check_Writer
        (Zlib.Seven_Zip_LZMA2_File'Access, "LZMA2", "lzma2");
      Check_Writer
        (Zlib.Seven_Zip_PPMd_File'Access, "PPMd", "ppmd");
   end Test_Compressed_File_Creation_Rejects_Directory_Output;

   procedure Test_File_Creation_Prevalidates_Output_Paths
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      type File_Writer is access procedure
        (Input_Path  : String;
         Output_Path : String;
         Entry_Name  : String;
         Status      : out Zlib.Status_Code);

      type File_List_Writer is access procedure
        (Input_Paths : Zlib.Text_Array;
         Output_Path : String;
         Entry_Names : Zlib.Text_Array;
         Status      : out Zlib.Status_Code);

      procedure Deflate_Level_File
        (Input_Path  : String;
         Output_Path : String;
         Entry_Name  : String;
         Status      : out Zlib.Status_Code) is
      begin
         Zlib.Seven_Zip_Deflate_File
           (Input_Path, Output_Path, Entry_Name, Zlib.Default_Level, Status);
      end Deflate_Level_File;

      procedure Deflate_Level_Files
        (Input_Paths : Zlib.Text_Array;
         Output_Path : String;
         Entry_Names : Zlib.Text_Array;
         Status      : out Zlib.Status_Code) is
      begin
         Zlib.Seven_Zip_Deflate_Files
           (Input_Paths, Output_Path, Entry_Names, Zlib.Default_Level, Status);
      end Deflate_Level_Files;

      procedure Check_File_Writer
        (Writer : File_Writer;
         Label  : String;
         Suffix : String)
      is
         Missing_Path : constant String :=
           Base_Path (Suffix & "-output-preflight-missing.bin");
         Archive_Path : constant String :=
           Base_Path (Suffix & "-output-preflight-dir");
         Marker_Path  : constant String :=
           Ada.Directories.Compose (Archive_Path, "marker.bin");
         Marker_Data  : constant Zlib.Byte_Array := [16#6D#, 16#61#, 16#72#, 16#6B#];
         Status       : Zlib.Status_Code := Zlib.Ok;
      begin
         Delete_If_Exists (Missing_Path);
         Delete_If_Exists (Archive_Path);

         Ada.Directories.Create_Path (Archive_Path);
         Write_File (Marker_Path, Marker_Data);

         Writer.all (Missing_Path, Archive_Path, "payload.txt", Status);
         Assert
           (Status = Zlib.Output_File_Error,
            Label & " single-entry creation validates output before input read");
         Assert
           (Read_File (Marker_Path) = Marker_Data,
            Label & " single-entry output preflight preserves marker");

         Delete_If_Exists (Missing_Path);
         Delete_If_Exists (Archive_Path);
      exception
         when others =>
            Delete_If_Exists (Missing_Path);
            Delete_If_Exists (Archive_Path);
            raise;
      end Check_File_Writer;

      procedure Check_File_List_Writer
        (Writer : File_List_Writer;
         Label  : String;
         Suffix : String)
      is
         Missing_Path : constant String :=
           Base_Path (Suffix & "-list-output-preflight-missing.bin");
         Archive_Path : constant String :=
           Base_Path (Suffix & "-list-output-preflight-dir");
         Marker_Path  : constant String :=
           Ada.Directories.Compose (Archive_Path, "marker.bin");
         Marker_Data  : constant Zlib.Byte_Array := [16#6D#, 16#61#, 16#72#, 16#6B#];
         Input_Paths  : constant Zlib.Text_Array :=
           [1 => US.To_Unbounded_String (Missing_Path)];
         Entry_Names  : constant Zlib.Text_Array :=
           [1 => US.To_Unbounded_String ("payload.txt")];
         Status       : Zlib.Status_Code := Zlib.Ok;
      begin
         Delete_If_Exists (Missing_Path);
         Delete_If_Exists (Archive_Path);

         Ada.Directories.Create_Path (Archive_Path);
         Write_File (Marker_Path, Marker_Data);

         Writer.all (Input_Paths, Archive_Path, Entry_Names, Status);
         Assert
           (Status = Zlib.Output_File_Error,
            Label & " file-list creation validates output before input read");
         Assert
           (Read_File (Marker_Path) = Marker_Data,
            Label & " file-list output preflight preserves marker");

         Delete_If_Exists (Missing_Path);
         Delete_If_Exists (Archive_Path);
      exception
         when others =>
            Delete_If_Exists (Missing_Path);
            Delete_If_Exists (Archive_Path);
            raise;
      end Check_File_List_Writer;
   begin
      Check_File_Writer
        (Zlib.Seven_Zip_Stored_File'Access, "Stored", "stored");
      Check_File_Writer
        (Zlib.Seven_Zip_Deflate_File'Access, "Deflate", "deflate");
      Check_File_Writer
        (Deflate_Level_File'Access, "Deflate level", "deflate-level");
      Check_File_Writer
        (Zlib.Seven_Zip_BZip2_File'Access, "BZip2", "bzip2");
      Check_File_Writer
        (Zlib.Seven_Zip_LZMA_File'Access, "LZMA", "lzma");
      Check_File_Writer
        (Zlib.Seven_Zip_LZMA2_File'Access, "LZMA2", "lzma2");
      Check_File_Writer
        (Zlib.Seven_Zip_PPMd_File'Access, "PPMd", "ppmd");

      Check_File_List_Writer
        (Zlib.Seven_Zip_Stored_Files'Access, "Stored", "stored");
      Check_File_List_Writer
        (Zlib.Seven_Zip_Deflate_Files'Access, "Deflate", "deflate");
      Check_File_List_Writer
        (Deflate_Level_Files'Access, "Deflate level", "deflate-level");
      Check_File_List_Writer
        (Zlib.Seven_Zip_BZip2_Files'Access, "BZip2", "bzip2");
      Check_File_List_Writer
        (Zlib.Seven_Zip_LZMA_Files'Access, "LZMA", "lzma");
      Check_File_List_Writer
        (Zlib.Seven_Zip_LZMA2_Files'Access, "LZMA2", "lzma2");
      Check_File_List_Writer
        (Zlib.Seven_Zip_PPMd_Files'Access, "PPMd", "ppmd");
   end Test_File_Creation_Prevalidates_Output_Paths;

   procedure Test_File_Creation_Prevalidates_Entry_Names
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      type File_Writer is access procedure
        (Input_Path  : String;
         Output_Path : String;
         Entry_Name  : String;
         Status      : out Zlib.Status_Code);

      procedure Deflate_Level_File
        (Input_Path  : String;
         Output_Path : String;
         Entry_Name  : String;
         Status      : out Zlib.Status_Code) is
      begin
         Zlib.Seven_Zip_Deflate_File
           (Input_Path, Output_Path, Entry_Name, Zlib.Default_Level, Status);
      end Deflate_Level_File;

      procedure Check_Writer
        (Writer : File_Writer;
         Label  : String;
         Suffix : String)
      is
         Missing_Path : constant String :=
           Base_Path (Suffix & "-prevalidate-missing.bin");
         Archive_Path : constant String :=
           Base_Path (Suffix & "-prevalidate.7z");
         Status       : Zlib.Status_Code := Zlib.Ok;
      begin
         Delete_If_Exists (Missing_Path);
         Delete_If_Exists (Archive_Path);

         Writer.all (Missing_Path, Archive_Path, "", Status);
         Assert
           (Status = Zlib.Unsupported_Method,
            Label & " single-entry creation validates name before input read");
         Assert
           (not Ada.Directories.Exists (Archive_Path),
            Label & " invalid-name creation leaves no archive");

         Delete_If_Exists (Missing_Path);
         Delete_If_Exists (Archive_Path);
      exception
         when others =>
            Delete_If_Exists (Missing_Path);
            Delete_If_Exists (Archive_Path);
            raise;
      end Check_Writer;
   begin
      Check_Writer
        (Zlib.Seven_Zip_Stored_File'Access, "Stored", "stored");
      Check_Writer
        (Zlib.Seven_Zip_Deflate_File'Access, "Deflate", "deflate");
      Check_Writer
        (Deflate_Level_File'Access, "Deflate level", "deflate-level");
      Check_Writer
        (Zlib.Seven_Zip_BZip2_File'Access, "BZip2", "bzip2");
      Check_Writer
        (Zlib.Seven_Zip_LZMA_File'Access, "LZMA", "lzma");
      Check_Writer
        (Zlib.Seven_Zip_LZMA2_File'Access, "LZMA2", "lzma2");
      Check_Writer
        (Zlib.Seven_Zip_PPMd_File'Access, "PPMd", "ppmd");
   end Test_File_Creation_Prevalidates_Entry_Names;

   procedure Test_PPMd_Basename_File_Prevalidates_Paths
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Archive_Path : constant String := Base_Path ("ppmd-basename-empty.7z");
      Output_Dir   : constant String := Base_Path ("ppmd-basename-output-dir");
      Marker_Path  : constant String :=
        Ada.Directories.Compose (Output_Dir, "marker.bin");
      Marker_Data  : constant Zlib.Byte_Array := [16#6D#, 16#61#, 16#72#, 16#6B#];
      Status       : Zlib.Status_Code := Zlib.Ok;
   begin
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);

      Zlib.Seven_Zip_PPMd_File ("", Archive_Path, Status);
      Assert
        (Status = Zlib.Input_File_Error,
         "PPMd basename helper rejects empty input path deterministically");
      Assert
        (not Ada.Directories.Exists (Archive_Path),
         "PPMd basename helper empty input leaves no archive");

      Ada.Directories.Create_Path (Output_Dir);
      Write_File (Marker_Path, Marker_Data);
      Zlib.Seven_Zip_PPMd_File ("", Output_Dir, Status);
      Assert
        (Status = Zlib.Output_File_Error,
         "PPMd basename helper validates output before input path");
      Assert
        (Read_File (Marker_Path) = Marker_Data,
         "PPMd basename helper output preflight preserves marker");

      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);
   exception
      when others =>
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);
         raise;
   end Test_PPMd_Basename_File_Prevalidates_Paths;

   procedure Test_File_Extraction_Prevalidates_Output_Paths
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      type File_Extractor is access procedure
        (Input_Path  : String;
         Output_Path : String;
         Entry_Name  : String;
         Status      : out Zlib.Status_Code);

      procedure Check_Extractor
        (Extractor : File_Extractor;
         Label     : String;
         Suffix    : String)
      is
         Missing_Path : constant String :=
           Base_Path (Suffix & "-extract-output-preflight-missing.7z");
         Output_Path  : constant String :=
           Base_Path (Suffix & "-extract-output-preflight-dir");
         Marker_Path  : constant String :=
           Ada.Directories.Compose (Output_Path, "marker.bin");
         Marker_Data  : constant Zlib.Byte_Array := [16#6D#, 16#61#, 16#72#, 16#6B#];
         Status       : Zlib.Status_Code := Zlib.Ok;
      begin
         Delete_If_Exists (Missing_Path);
         Delete_If_Exists (Output_Path);

         Ada.Directories.Create_Path (Output_Path);
         Write_File (Marker_Path, Marker_Data);

         Extractor.all (Missing_Path, Output_Path, "payload.txt", Status);
         Assert
           (Status = Zlib.Output_File_Error,
            Label & " single-entry extraction validates output before input read");
         Assert
           (Read_File (Marker_Path) = Marker_Data,
            Label & " single-entry extraction output preflight preserves marker");

         Delete_If_Exists (Missing_Path);
         Delete_If_Exists (Output_Path);
      exception
         when others =>
            Delete_If_Exists (Missing_Path);
            Delete_If_Exists (Output_Path);
            raise;
      end Check_Extractor;
   begin
      Check_Extractor
        (Zlib.Extract_Seven_Zip_Stored_File'Access, "Stored", "stored");
      Check_Extractor
        (Zlib.Extract_Seven_Zip_File'Access, "Alias", "alias");
   end Test_File_Extraction_Prevalidates_Output_Paths;

   procedure Test_File_Extraction_Prevalidates_Entry_Names
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      type File_Extractor is access procedure
        (Input_Path  : String;
         Output_Path : String;
         Entry_Name  : String;
         Status      : out Zlib.Status_Code);

      procedure Check_Extractor
        (Extractor : File_Extractor;
         Label     : String;
         Suffix    : String)
      is
         Missing_Path : constant String :=
           Base_Path (Suffix & "-extract-prevalidate-missing.7z");
         Output_Path  : constant String :=
           Base_Path (Suffix & "-extract-prevalidate-output.bin");
         Status       : Zlib.Status_Code := Zlib.Ok;
      begin
         Delete_If_Exists (Missing_Path);
         Delete_If_Exists (Output_Path);

         Extractor.all (Missing_Path, Output_Path, "", Status);
         Assert
           (Status = Zlib.Unsupported_Method,
            Label & " single-entry extraction validates empty name before read");
         Assert
           (not Ada.Directories.Exists (Output_Path),
            Label & " empty-name extraction leaves no output");

         Extractor.all
           (Missing_Path, Output_Path, "bad" & ASCII.NUL & "name", Status);
         Assert
           (Status = Zlib.Unsupported_Method,
            Label & " single-entry extraction validates NUL name before read");
         Assert
           (not Ada.Directories.Exists (Output_Path),
            Label & " NUL-name extraction leaves no output");

         Delete_If_Exists (Missing_Path);
         Delete_If_Exists (Output_Path);
      exception
         when others =>
            Delete_If_Exists (Missing_Path);
            Delete_If_Exists (Output_Path);
            raise;
      end Check_Extractor;
   begin
      Check_Extractor
        (Zlib.Extract_Seven_Zip_Stored_File'Access, "Stored", "stored");
      Check_Extractor
        (Zlib.Extract_Seven_Zip_File'Access, "Alias", "alias");
   end Test_File_Extraction_Prevalidates_Entry_Names;

   procedure Test_Stored_Multiple_Files_Roundtrip_Native
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      First_Path   : constant String := Base_Path ("multi-first.bin");
      Second_Path  : constant String := Base_Path ("multi-second.bin");
      Archive_Path : constant String := Base_Path ("multi.7z");
      First_Data   : constant Zlib.Byte_Array :=
        [16#66#, 16#69#, 16#72#, 16#73#, 16#74#];
      Second_Data  : constant Zlib.Byte_Array :=
        [16#73#, 16#65#, 16#63#, 16#6F#, 16#6E#, 16#64#];
      Input_Paths  : constant Zlib.Text_Array :=
        [US.To_Unbounded_String (First_Path),
         US.To_Unbounded_String (Second_Path)];
      Entry_Names  : constant Zlib.Text_Array :=
        [US.To_Unbounded_String ("first.txt"),
         US.To_Unbounded_String ("dir/second.bin")];
      Status       : Zlib.Status_Code := Zlib.Ok;
   begin
      Delete_If_Exists (First_Path);
      Delete_If_Exists (Second_Path);
      Delete_If_Exists (Archive_Path);

      Write_File (First_Path, First_Data);
      Write_File (Second_Path, Second_Data);
      Zlib.Seven_Zip_Stored_Files
        (Input_Paths, Archive_Path, Entry_Names, Status);
      Assert (Status = Zlib.Ok, "multi-file stored 7z creation status");

      declare
         Archive      : constant Zlib.Byte_Array := Read_File (Archive_Path);
         First_Plain  : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip_Stored (Archive, "first.txt", Status);
      begin
         Assert (Status = Zlib.Ok, "first multi-file 7z extract status");
         Assert (First_Plain = First_Data, "first multi-file 7z payload");

         declare
            Second_Plain : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip_Stored
                (Archive, "dir/second.bin", Status);
         begin
            Assert (Status = Zlib.Ok, "second multi-file 7z extract status");
            Assert (Second_Plain = Second_Data, "second multi-file 7z payload");
         end;
      end;

      Delete_If_Exists (First_Path);
      Delete_If_Exists (Second_Path);
      Delete_If_Exists (Archive_Path);
   exception
      when others =>
         Delete_If_Exists (First_Path);
         Delete_If_Exists (Second_Path);
         Delete_If_Exists (Archive_Path);
         raise;
   end Test_Stored_Multiple_Files_Roundtrip_Native;

   procedure Test_Deflate_Multiple_Files_Roundtrip_Native
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      First_Path   : constant String := Base_Path ("deflate-multi-first.bin");
      Second_Path  : constant String := Base_Path ("deflate-multi-second.bin");
      Archive_Path : constant String := Base_Path ("deflate-multi.7z");
      Output_Dir   : constant String := Base_Path ("deflate-multi-out");
      First_Data   : constant Zlib.Byte_Array :=
        [1 .. 256 => 16#61#];
      Second_Data  : constant Zlib.Byte_Array :=
        [1 .. 300 => 16#62#];
      Input_Paths  : constant Zlib.Text_Array :=
        [US.To_Unbounded_String (First_Path),
         US.To_Unbounded_String (Second_Path)];
      Entry_Names  : constant Zlib.Text_Array :=
        [US.To_Unbounded_String ("first.txt"),
         US.To_Unbounded_String ("dir/second.bin")];
      Status       : Zlib.Status_Code := Zlib.Ok;
   begin
      Delete_If_Exists (First_Path);
      Delete_If_Exists (Second_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);

      Write_File (First_Path, First_Data);
      Write_File (Second_Path, Second_Data);
      Zlib.Seven_Zip_Deflate_Files
        (Input_Paths, Archive_Path, Entry_Names, Zlib.Dynamic, Status);
      Assert (Status = Zlib.Ok, "multi-file Deflate 7z creation status");

      declare
         Archive      : constant Zlib.Byte_Array := Read_File (Archive_Path);
         First_Plain  : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip_Stored (Archive, "first.txt", Status);
      begin
         Assert (Status = Zlib.Ok, "first multi-file Deflate 7z extract status");
         Assert (First_Plain = First_Data, "first multi-file Deflate 7z payload");
      end;

      Zlib.Extract_Seven_Zip_Stored_Files
        (Archive_Path, Output_Dir, Entry_Names, Status);
      Assert
        (Status = Zlib.Ok,
         "multi-file Deflate 7z directory extract status");
      Assert
        (Read_File (Ada.Directories.Compose (Output_Dir, "first.txt")) =
         First_Data,
         "multi-file Deflate 7z directory extract first payload");
      Assert
        (Read_File (Output_Dir & "/dir/second.bin") = Second_Data,
         "multi-file Deflate 7z directory extract nested payload");

      Delete_If_Exists (First_Path);
      Delete_If_Exists (Second_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);
   exception
      when others =>
         Delete_If_Exists (First_Path);
         Delete_If_Exists (Second_Path);
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);
         raise;
   end Test_Deflate_Multiple_Files_Roundtrip_Native;

   procedure Test_BZip2_Multiple_Files_Roundtrip_Native
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      First_Path   : constant String := Base_Path ("bzip2-multi-first.bin");
      Second_Path  : constant String := Base_Path ("bzip2-multi-second.bin");
      Archive_Path : constant String := Base_Path ("bzip2-multi.7z");
      Output_Dir   : constant String := Base_Path ("bzip2-multi-out");
      First_Data   : constant Zlib.Byte_Array :=
        [1 .. 512 => 16#63#];
      Second_Data  : constant Zlib.Byte_Array :=
        [1 .. 384 => 16#64#];
      Input_Paths  : constant Zlib.Text_Array :=
        [US.To_Unbounded_String (First_Path),
         US.To_Unbounded_String (Second_Path)];
      Entry_Names  : constant Zlib.Text_Array :=
        [US.To_Unbounded_String ("first-bzip2.txt"),
         US.To_Unbounded_String ("dir/second-bzip2.bin")];
      Status       : Zlib.Status_Code := Zlib.Ok;
   begin
      Delete_If_Exists (First_Path);
      Delete_If_Exists (Second_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);

      Write_File (First_Path, First_Data);
      Write_File (Second_Path, Second_Data);
      Zlib.Seven_Zip_BZip2_Files
        (Input_Paths, Archive_Path, Entry_Names, Status);
      Assert (Status = Zlib.Ok, "multi-file BZip2 7z creation status");

      declare
         Archive      : constant Zlib.Byte_Array := Read_File (Archive_Path);
         First_Plain  : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip_Stored
             (Archive, "first-bzip2.txt", Status);
      begin
         Assert (Status = Zlib.Ok, "first multi-file BZip2 7z extract status");
         Assert (First_Plain = First_Data, "first multi-file BZip2 7z payload");
      end;

      Zlib.Extract_Seven_Zip_Stored_Files
        (Archive_Path, Output_Dir, Entry_Names, Status);
      Assert
        (Status = Zlib.Ok,
         "multi-file BZip2 7z directory extract status");
      Assert
        (Read_File (Ada.Directories.Compose (Output_Dir, "first-bzip2.txt")) =
         First_Data,
         "multi-file BZip2 7z directory extract first payload");
      Assert
        (Read_File (Output_Dir & "/dir/second-bzip2.bin") = Second_Data,
         "multi-file BZip2 7z directory extract nested payload");

      Delete_If_Exists (First_Path);
      Delete_If_Exists (Second_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);
   exception
      when others =>
         Delete_If_Exists (First_Path);
         Delete_If_Exists (Second_Path);
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);
         raise;
   end Test_BZip2_Multiple_Files_Roundtrip_Native;

   procedure Test_LZMA_Multiple_Files_Roundtrip_Native
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      First_Path   : constant String := Base_Path ("lzma-multi-first.bin");
      Second_Path  : constant String := Base_Path ("lzma-multi-second.bin");
      Archive_Path : constant String := Base_Path ("lzma-multi.7z");
      Output_Dir   : constant String := Base_Path ("lzma-multi-out");
      First_Data   : constant Zlib.Byte_Array :=
        [1 .. 512 => 16#65#];
      Second_Data  : constant Zlib.Byte_Array :=
        [1 .. 384 => 16#66#];
      Input_Paths  : constant Zlib.Text_Array :=
        [US.To_Unbounded_String (First_Path),
         US.To_Unbounded_String (Second_Path)];
      Entry_Names  : constant Zlib.Text_Array :=
        [US.To_Unbounded_String ("first-lzma.txt"),
         US.To_Unbounded_String ("dir/second-lzma.bin")];
      Status       : Zlib.Status_Code := Zlib.Ok;
   begin
      Delete_If_Exists (First_Path);
      Delete_If_Exists (Second_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);

      Write_File (First_Path, First_Data);
      Write_File (Second_Path, Second_Data);
      Zlib.Seven_Zip_LZMA_Files
        (Input_Paths, Archive_Path, Entry_Names, Status);
      Assert (Status = Zlib.Ok, "multi-file LZMA 7z creation status");

      declare
         Archive      : constant Zlib.Byte_Array := Read_File (Archive_Path);
         First_Plain  : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip_Stored
             (Archive, "first-lzma.txt", Status);
      begin
         Assert (Status = Zlib.Ok, "first multi-file LZMA 7z extract status");
         Assert (First_Plain = First_Data, "first multi-file LZMA 7z payload");
      end;

      Zlib.Extract_Seven_Zip_Stored_Files
        (Archive_Path, Output_Dir, Entry_Names, Status);
      Assert
        (Status = Zlib.Ok,
         "multi-file LZMA 7z directory extract status");
      Assert
        (Read_File (Ada.Directories.Compose (Output_Dir, "first-lzma.txt")) =
         First_Data,
         "multi-file LZMA 7z directory extract first payload");
      Assert
        (Read_File (Output_Dir & "/dir/second-lzma.bin") = Second_Data,
         "multi-file LZMA 7z directory extract nested payload");

      Delete_If_Exists (First_Path);
      Delete_If_Exists (Second_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);
   exception
      when others =>
         Delete_If_Exists (First_Path);
         Delete_If_Exists (Second_Path);
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);
         raise;
   end Test_LZMA_Multiple_Files_Roundtrip_Native;

   procedure Test_LZMA2_Multiple_Files_Roundtrip_Native
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      First_Path   : constant String := Base_Path ("lzma2-multi-first.bin");
      Second_Path  : constant String := Base_Path ("lzma2-multi-second.bin");
      Archive_Path : constant String := Base_Path ("lzma2-multi.7z");
      Output_Dir   : constant String := Base_Path ("lzma2-multi-out");
      First_Data   : constant Zlib.Byte_Array :=
        [1 .. 512 => 16#67#];
      Second_Data  : constant Zlib.Byte_Array :=
        [1 .. 384 => 16#68#];
      Input_Paths  : constant Zlib.Text_Array :=
        [US.To_Unbounded_String (First_Path),
         US.To_Unbounded_String (Second_Path)];
      Entry_Names  : constant Zlib.Text_Array :=
        [US.To_Unbounded_String ("first-lzma2.txt"),
         US.To_Unbounded_String ("dir/second-lzma2.bin")];
      Status       : Zlib.Status_Code := Zlib.Ok;
   begin
      Delete_If_Exists (First_Path);
      Delete_If_Exists (Second_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);

      Write_File (First_Path, First_Data);
      Write_File (Second_Path, Second_Data);
      Zlib.Seven_Zip_LZMA2_Files
        (Input_Paths, Archive_Path, Entry_Names, Status);
      Assert (Status = Zlib.Ok, "multi-file LZMA2 7z creation status");

      declare
         Archive      : constant Zlib.Byte_Array := Read_File (Archive_Path);
         First_Plain  : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip_Stored
             (Archive, "first-lzma2.txt", Status);
      begin
         Assert (Status = Zlib.Ok, "first multi-file LZMA2 7z extract status");
         Assert (First_Plain = First_Data, "first multi-file LZMA2 7z payload");
      end;

      Zlib.Extract_Seven_Zip_Stored_Files
        (Archive_Path, Output_Dir, Entry_Names, Status);
      Assert
        (Status = Zlib.Ok,
         "multi-file LZMA2 7z directory extract status");
      Assert
        (Read_File (Ada.Directories.Compose (Output_Dir, "first-lzma2.txt")) =
         First_Data,
         "multi-file LZMA2 7z directory extract first payload");
      Assert
        (Read_File (Output_Dir & "/dir/second-lzma2.bin") = Second_Data,
         "multi-file LZMA2 7z directory extract nested payload");

      Delete_If_Exists (First_Path);
      Delete_If_Exists (Second_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);
   exception
      when others =>
         Delete_If_Exists (First_Path);
         Delete_If_Exists (Second_Path);
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);
         raise;
   end Test_LZMA2_Multiple_Files_Roundtrip_Native;

   procedure Test_PPMd_Multiple_Files_Roundtrip_Native
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      First_Path   : constant String := Base_Path ("ppmd-multi-first.bin");
      Second_Path  : constant String := Base_Path ("ppmd-multi-second.bin");
      Archive_Path : constant String := Base_Path ("ppmd-multi.7z");
      Output_Dir   : constant String := Base_Path ("ppmd-multi-out");
      First_Data   : Zlib.Byte_Array (1 .. 1024);
      Second_Data  : constant Zlib.Byte_Array (1 .. 384) :=
        [others => 16#71#];
      Input_Paths  : constant Zlib.Text_Array :=
        [US.To_Unbounded_String (First_Path),
         US.To_Unbounded_String (Second_Path)];
      Entry_Names  : constant Zlib.Text_Array :=
        [US.To_Unbounded_String ("first-ppmd.txt"),
         US.To_Unbounded_String ("dir/second-ppmd.bin")];
      Status       : Zlib.Status_Code := Zlib.Ok;
   begin
      Delete_If_Exists (First_Path);
      Delete_If_Exists (Second_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);

      for I in First_Data'Range loop
         First_Data (I) :=
           Zlib.Byte ((I - First_Data'First) mod 64);
      end loop;

      Write_File (First_Path, First_Data);
      Write_File (Second_Path, Second_Data);
      Zlib.Seven_Zip_PPMd_Files
        (Input_Paths, Archive_Path, Entry_Names, Status);
      Assert (Status = Zlib.Ok, "multi-file PPMd 7z creation status");

      declare
         Archive      : constant Zlib.Byte_Array := Read_File (Archive_Path);
         First_Plain  : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip
             (Archive, "first-ppmd.txt", Status);
      begin
         Assert
           (Archive'Length < First_Data'Length + Second_Data'Length,
            "multi-file PPMd 7z uses compact period-64/repeated coding");
         Assert (Status = Zlib.Ok, "first multi-file PPMd 7z extract status");
         Assert (First_Plain = First_Data, "first multi-file PPMd 7z payload");
      end;

      Zlib.Extract_Seven_Zip_Files
        (Archive_Path, Output_Dir, Entry_Names, Status);
      Assert
        (Status = Zlib.Ok,
         "multi-file PPMd 7z directory extract status");
      Assert
        (Read_File (Ada.Directories.Compose (Output_Dir, "first-ppmd.txt")) =
         First_Data,
         "multi-file PPMd 7z directory extract first payload");
      Assert
        (Read_File (Output_Dir & "/dir/second-ppmd.bin") = Second_Data,
         "multi-file PPMd 7z directory extract nested payload");

      Delete_If_Exists (First_Path);
      Delete_If_Exists (Second_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);
   exception
      when others =>
         Delete_If_Exists (First_Path);
         Delete_If_Exists (Second_Path);
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);
         raise;
   end Test_PPMd_Multiple_Files_Roundtrip_Native;

   procedure Test_File_List_Writers_Emit_Directory_Entries
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      type File_List_Writer is access procedure
        (Input_Paths : Zlib.Text_Array;
         Output_Path : String;
         Entry_Names : Zlib.Text_Array;
         Status      : out Zlib.Status_Code);

      procedure Check_Writer
        (Writer : File_List_Writer;
         Label  : String;
         Suffix : String)
      is
         File_Path   : constant String := Base_Path (Suffix & "-mixed-file.bin");
         Dir_Path    : constant String := Base_Path (Suffix & "-mixed-dir");
         Archive_Path : constant String := Base_Path (Suffix & "-mixed.7z");
         Output_Dir  : constant String := Base_Path (Suffix & "-mixed-out");
         File_Data   : constant Zlib.Byte_Array :=
           [16#64#, 16#69#, 16#72#, 16#2D#, 16#6D#, 16#69#, 16#78#];
         Input_Paths : constant Zlib.Text_Array :=
           [US.To_Unbounded_String (File_Path),
            US.To_Unbounded_String (Dir_Path)];
         Entry_Names : constant Zlib.Text_Array :=
           [US.To_Unbounded_String ("payload.txt"),
            US.To_Unbounded_String ("nested")];
         Status      : Zlib.Status_Code := Zlib.Ok;
      begin
         Delete_If_Exists (File_Path);
         Delete_If_Exists (Dir_Path);
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);

         Write_File (File_Path, File_Data);
         Ada.Directories.Create_Path (Dir_Path);

         Writer.all (Input_Paths, Archive_Path, Entry_Names, Status);
         Assert (Status = Zlib.Ok, Label & " mixed file-list creation status");

         declare
            Archive  : constant Zlib.Byte_Array := Read_File (Archive_Path);
            Metadata : constant Zlib.Seven_Zip_Entry_Metadata :=
              Zlib.Extract_Seven_Zip_Metadata (Archive, "nested", Status);
         begin
            Assert (Status = Zlib.Ok, Label & " directory metadata status");
            Assert (Metadata.Is_Directory, Label & " metadata marks directory");
         end;

         Zlib.Extract_Seven_Zip_Files
           (Archive_Path, Output_Dir, Entry_Names, Status);
         Assert (Status = Zlib.Ok, Label & " mixed file-list extraction status");
         Assert
           (Read_File (Ada.Directories.Compose (Output_Dir, "payload.txt")) =
            File_Data,
            Label & " mixed file-list extracts file payload");
         Assert
           (Ada.Directories.Exists
              (Ada.Directories.Compose (Output_Dir, "nested"))
            and then Ada.Directories.Kind
              (Ada.Directories.Compose (Output_Dir, "nested")) =
                Ada.Directories.Directory,
            Label & " mixed file-list extracts directory");

         Delete_If_Exists (File_Path);
         Delete_If_Exists (Dir_Path);
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);
      exception
         when others =>
            Delete_If_Exists (File_Path);
            Delete_If_Exists (Dir_Path);
            Delete_If_Exists (Archive_Path);
            Delete_If_Exists (Output_Dir);
            raise;
      end Check_Writer;
   begin
      Check_Writer (Zlib.Seven_Zip_Stored_Files'Access, "stored", "stored");
      Check_Writer (Zlib.Seven_Zip_Deflate_Files'Access, "Deflate", "deflate");
      Check_Writer (Zlib.Seven_Zip_BZip2_Files'Access, "BZip2", "bzip2");
      Check_Writer (Zlib.Seven_Zip_LZMA_Files'Access, "LZMA", "lzma");
      Check_Writer (Zlib.Seven_Zip_LZMA2_Files'Access, "LZMA2", "lzma2");
      Check_Writer (Zlib.Seven_Zip_PPMd_Files'Access, "PPMd", "ppmd");
   end Test_File_List_Writers_Emit_Directory_Entries;

   procedure Test_File_Writers_Emit_Directory_Entries
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      type File_Writer is access procedure
        (Input_Path  : String;
         Output_Path : String;
         Entry_Name  : String;
         Status      : out Zlib.Status_Code);

      procedure Deflate_Level_File
        (Input_Path  : String;
         Output_Path : String;
         Entry_Name  : String;
         Status      : out Zlib.Status_Code) is
      begin
         Zlib.Seven_Zip_Deflate_File
           (Input_Path, Output_Path, Entry_Name, Zlib.Default_Level, Status);
      end Deflate_Level_File;

      procedure Check_Writer
        (Writer : File_Writer;
         Label  : String;
         Suffix : String)
      is
         Dir_Path     : constant String := Base_Path (Suffix & "-single-dir");
         Archive_Path : constant String := Base_Path (Suffix & "-single-dir.7z");
         Output_Dir   : constant String := Base_Path (Suffix & "-single-dir-out");
         Output_Path  : constant String :=
           Ada.Directories.Compose (Output_Dir, "nested");
         Status       : Zlib.Status_Code := Zlib.Ok;
      begin
         Delete_If_Exists (Dir_Path);
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);

         Ada.Directories.Create_Path (Dir_Path);

         Writer.all (Dir_Path, Archive_Path, "nested", Status);
         Assert (Status = Zlib.Ok, Label & " directory file-helper status");

         declare
            Archive  : constant Zlib.Byte_Array := Read_File (Archive_Path);
            Metadata : constant Zlib.Seven_Zip_Entry_Metadata :=
              Zlib.Extract_Seven_Zip_Metadata (Archive, "nested", Status);
         begin
            Assert (Status = Zlib.Ok, Label & " directory metadata status");
            Assert (Metadata.Is_Directory, Label & " metadata marks directory");
         end;

         Zlib.Extract_Seven_Zip_File
           (Archive_Path, Output_Path, "nested", Status);
         Assert (Status = Zlib.Ok, Label & " directory extraction status");
         Assert
           (Ada.Directories.Exists (Output_Path)
            and then Ada.Directories.Kind (Output_Path) =
              Ada.Directories.Directory,
            Label & " extracts directory");

         Delete_If_Exists (Dir_Path);
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);
      exception
         when others =>
            Delete_If_Exists (Dir_Path);
            Delete_If_Exists (Archive_Path);
            Delete_If_Exists (Output_Dir);
            raise;
      end Check_Writer;
   begin
      Check_Writer (Zlib.Seven_Zip_Stored_File'Access, "Stored", "stored");
      Check_Writer (Zlib.Seven_Zip_Deflate_File'Access, "Deflate", "deflate");
      Check_Writer
        (Deflate_Level_File'Access, "Deflate level", "deflate-level");
      Check_Writer (Zlib.Seven_Zip_BZip2_File'Access, "BZip2", "bzip2");
      Check_Writer (Zlib.Seven_Zip_LZMA_File'Access, "LZMA", "lzma");
      Check_Writer (Zlib.Seven_Zip_LZMA2_File'Access, "LZMA2", "lzma2");
      Check_Writer (Zlib.Seven_Zip_PPMd_File'Access, "PPMd", "ppmd");
   end Test_File_Writers_Emit_Directory_Entries;

   procedure Test_File_List_Writers_Emit_All_Directory_Archives
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      type File_List_Writer is access procedure
        (Input_Paths : Zlib.Text_Array;
         Output_Path : String;
         Entry_Names : Zlib.Text_Array;
         Status      : out Zlib.Status_Code);

      procedure Deflate_Level_Files
        (Input_Paths : Zlib.Text_Array;
         Output_Path : String;
         Entry_Names : Zlib.Text_Array;
         Status      : out Zlib.Status_Code) is
      begin
         Zlib.Seven_Zip_Deflate_Files
           (Input_Paths, Output_Path, Entry_Names, Zlib.Default_Level, Status);
      end Deflate_Level_Files;

      procedure Check_Writer
        (Writer : File_List_Writer;
         Label  : String;
         Suffix : String)
      is
         First_Dir    : constant String := Base_Path (Suffix & "-dirs-only-a");
         Second_Dir   : constant String := Base_Path (Suffix & "-dirs-only-b");
         Archive_Path : constant String := Base_Path (Suffix & "-dirs-only.7z");
         Output_Dir   : constant String := Base_Path (Suffix & "-dirs-only-out");
         First_Output : constant String :=
           Ada.Directories.Compose (Output_Dir, "alpha");
         Nested_Output_Dir : constant String :=
           Ada.Directories.Compose (Output_Dir, "nested");
         Second_Output : constant String :=
           Ada.Directories.Compose (Nested_Output_Dir, "beta");
         Input_Paths  : constant Zlib.Text_Array :=
           [US.To_Unbounded_String (First_Dir),
            US.To_Unbounded_String (Second_Dir)];
         Entry_Names  : constant Zlib.Text_Array :=
           [US.To_Unbounded_String ("alpha"),
            US.To_Unbounded_String ("nested/beta")];
         Status       : Zlib.Status_Code := Zlib.Ok;
      begin
         Delete_If_Exists (First_Dir);
         Delete_If_Exists (Second_Dir);
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);

         Ada.Directories.Create_Path (First_Dir);
         Ada.Directories.Create_Path (Second_Dir);

         Writer.all (Input_Paths, Archive_Path, Entry_Names, Status);
         Assert (Status = Zlib.Ok, Label & " all-directory creation status");

         declare
            Archive : constant Zlib.Byte_Array := Read_File (Archive_Path);
            First   : constant Zlib.Seven_Zip_Entry_Metadata :=
              Zlib.Extract_Seven_Zip_Metadata (Archive, "alpha", Status);
         begin
            Assert (Status = Zlib.Ok, Label & " first directory metadata status");
            Assert (First.Is_Directory, Label & " first entry is a directory");
         end;

         declare
            Archive : constant Zlib.Byte_Array := Read_File (Archive_Path);
            Second  : constant Zlib.Seven_Zip_Entry_Metadata :=
              Zlib.Extract_Seven_Zip_Metadata (Archive, "nested/beta", Status);
         begin
            Assert (Status = Zlib.Ok, Label & " second directory metadata status");
            Assert (Second.Is_Directory, Label & " second entry is a directory");
         end;

         Zlib.Extract_Seven_Zip_Files
           (Archive_Path, Output_Dir, Entry_Names, Status);
         Assert (Status = Zlib.Ok, Label & " all-directory extraction status");
         Assert
           (Ada.Directories.Exists (First_Output)
            and then Ada.Directories.Kind (First_Output) =
              Ada.Directories.Directory,
            Label & " extracts first directory");
         Assert
           (Ada.Directories.Exists (Second_Output)
            and then Ada.Directories.Kind (Second_Output) =
              Ada.Directories.Directory,
            Label & " extracts nested directory");

         Delete_If_Exists (First_Dir);
         Delete_If_Exists (Second_Dir);
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);
      exception
         when others =>
            Delete_If_Exists (First_Dir);
            Delete_If_Exists (Second_Dir);
            Delete_If_Exists (Archive_Path);
            Delete_If_Exists (Output_Dir);
            raise;
      end Check_Writer;
   begin
      Check_Writer (Zlib.Seven_Zip_Stored_Files'Access, "Stored", "stored");
      Check_Writer (Zlib.Seven_Zip_Deflate_Files'Access, "Deflate", "deflate");
      Check_Writer
        (Deflate_Level_Files'Access, "Deflate level", "deflate-level");
      Check_Writer (Zlib.Seven_Zip_BZip2_Files'Access, "BZip2", "bzip2");
      Check_Writer (Zlib.Seven_Zip_LZMA_Files'Access, "LZMA", "lzma");
      Check_Writer (Zlib.Seven_Zip_LZMA2_Files'Access, "LZMA2", "lzma2");
      Check_Writer (Zlib.Seven_Zip_PPMd_Files'Access, "PPMd", "ppmd");
   end Test_File_List_Writers_Emit_All_Directory_Archives;

   procedure Test_Directory_Creation_Preserves_Source_Metadata
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      type File_Writer is access procedure
        (Input_Path  : String;
         Output_Path : String;
         Entry_Name  : String;
         Status      : out Zlib.Status_Code);

      type File_List_Writer is access procedure
        (Input_Paths : Zlib.Text_Array;
         Output_Path : String;
         Entry_Names : Zlib.Text_Array;
         Status      : out Zlib.Status_Code);

      Expected_Filetime : constant Interfaces.Unsigned_64 :=
        16#019D_B1DE_D53E_8000#;
      Expected_Time     : constant Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (1970, 1, 1, 0.0);

      procedure Deflate_Level_File
        (Input_Path  : String;
         Output_Path : String;
         Entry_Name  : String;
         Status      : out Zlib.Status_Code) is
      begin
         Zlib.Seven_Zip_Deflate_File
           (Input_Path, Output_Path, Entry_Name, Zlib.Default_Level, Status);
      end Deflate_Level_File;

      procedure Deflate_Level_Files
        (Input_Paths : Zlib.Text_Array;
         Output_Path : String;
         Entry_Names : Zlib.Text_Array;
         Status      : out Zlib.Status_Code) is
      begin
         Zlib.Seven_Zip_Deflate_Files
           (Input_Paths, Output_Path, Entry_Names, Zlib.Default_Level, Status);
      end Deflate_Level_Files;

      procedure Prepare_Directory (Path : String) is
      begin
         Delete_If_Exists (Path);
         Ada.Directories.Create_Path (Path);
         GNAT.OS_Lib.Set_File_Last_Modify_Time_Stamp
           (Path,
            GNAT.OS_Lib.GM_Time_Of
              (1970, 1, 1, 0, 0, 0));
      end Prepare_Directory;

      procedure Assert_MTime (Path : String; Label : String) is
         Difference : Duration :=
           Ada.Directories.Modification_Time (Path) - Expected_Time;
      begin
         if Difference < 0.0 then
            Difference := -Difference;
         end if;
         Assert (Difference <= 2.0, Label);
      end Assert_MTime;

      procedure Check_Metadata
        (Archive_Path : String;
         Entry_Name   : String;
         Label        : String)
      is
         Status   : Zlib.Status_Code := Zlib.Ok;
         Archive  : constant Zlib.Byte_Array := Read_File (Archive_Path);
         Metadata : constant Zlib.Seven_Zip_Entry_Metadata :=
           Zlib.Extract_Seven_Zip_Metadata (Archive, Entry_Name, Status);
      begin
         Assert (Status = Zlib.Ok, Label & " metadata status");
         Assert (Metadata.Is_Directory, Label & " metadata marks directory");
         Assert
           (Metadata.Has_Modification_Time
            and then Metadata.Modification_Time = Expected_Filetime,
            Label & " preserves source modification time");
         Assert
           (Metadata.Has_Windows_Attributes
            and then (Metadata.Windows_Attributes and 16#0000_0010#) /= 0,
            Label & " preserves directory attribute");
      end Check_Metadata;

      procedure Check_File_Writer
        (Writer : File_Writer;
         Label  : String;
         Suffix : String)
      is
         Dir_Path     : constant String := Base_Path (Suffix & "-dir-metadata");
         Archive_Path : constant String :=
           Base_Path (Suffix & "-dir-metadata.7z");
         Output_Dir   : constant String :=
           Base_Path (Suffix & "-dir-metadata-out");
         Output_Path  : constant String :=
           Ada.Directories.Compose (Output_Dir, "entry");
         Status       : Zlib.Status_Code := Zlib.Ok;
      begin
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);
         Prepare_Directory (Dir_Path);

         Writer.all (Dir_Path, Archive_Path, "entry", Status);
         Assert (Status = Zlib.Ok, Label & " directory metadata creation status");
         Check_Metadata (Archive_Path, "entry", Label & " file helper");

         Zlib.Extract_Seven_Zip_File
           (Archive_Path, Output_Path, "entry", Status);
         Assert (Status = Zlib.Ok, Label & " directory metadata extraction status");
         Assert_MTime (Output_Path, Label & " restores directory mtime");

         Delete_If_Exists (Dir_Path);
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);
      exception
         when others =>
            Delete_If_Exists (Dir_Path);
            Delete_If_Exists (Archive_Path);
            Delete_If_Exists (Output_Dir);
            raise;
      end Check_File_Writer;

      procedure Check_File_List_Writer
        (Writer : File_List_Writer;
         Label  : String;
         Suffix : String)
      is
         Dir_Path     : constant String := Base_Path (Suffix & "-dir-list-metadata");
         Archive_Path : constant String :=
           Base_Path (Suffix & "-dir-list-metadata.7z");
         Output_Dir   : constant String :=
           Base_Path (Suffix & "-dir-list-metadata-out");
         Output_Path  : constant String :=
           Ada.Directories.Compose (Output_Dir, "entry");
         Input_Paths  : constant Zlib.Text_Array :=
           [1 => US.To_Unbounded_String (Dir_Path)];
         Entry_Names  : constant Zlib.Text_Array :=
           [1 => US.To_Unbounded_String ("entry")];
         Status       : Zlib.Status_Code := Zlib.Ok;
      begin
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);
         Prepare_Directory (Dir_Path);

         Writer.all (Input_Paths, Archive_Path, Entry_Names, Status);
         Assert (Status = Zlib.Ok, Label & " directory list metadata creation status");
         Check_Metadata (Archive_Path, "entry", Label & " file-list helper");

         Zlib.Extract_Seven_Zip_Files
           (Archive_Path, Output_Dir, Entry_Names, Status);
         Assert
           (Status = Zlib.Ok,
            Label & " directory list metadata extraction status");
         Assert_MTime (Output_Path, Label & " restores list directory mtime");

         Delete_If_Exists (Dir_Path);
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);
      exception
         when others =>
            Delete_If_Exists (Dir_Path);
            Delete_If_Exists (Archive_Path);
            Delete_If_Exists (Output_Dir);
            raise;
      end Check_File_List_Writer;
   begin
      Check_File_Writer
        (Zlib.Seven_Zip_Stored_File'Access, "Stored", "stored");
      Check_File_Writer
        (Zlib.Seven_Zip_Deflate_File'Access, "Deflate", "deflate");
      Check_File_Writer
        (Deflate_Level_File'Access, "Deflate level", "deflate-level");
      Check_File_Writer
        (Zlib.Seven_Zip_BZip2_File'Access, "BZip2", "bzip2");
      Check_File_Writer
        (Zlib.Seven_Zip_LZMA_File'Access, "LZMA", "lzma");
      Check_File_Writer
        (Zlib.Seven_Zip_LZMA2_File'Access, "LZMA2", "lzma2");
      Check_File_Writer
        (Zlib.Seven_Zip_PPMd_File'Access, "PPMd", "ppmd");

      Check_File_List_Writer
        (Zlib.Seven_Zip_Stored_Files'Access, "Stored", "stored");
      Check_File_List_Writer
        (Zlib.Seven_Zip_Deflate_Files'Access, "Deflate", "deflate");
      Check_File_List_Writer
        (Deflate_Level_Files'Access, "Deflate level", "deflate-level");
      Check_File_List_Writer
        (Zlib.Seven_Zip_BZip2_Files'Access, "BZip2", "bzip2");
      Check_File_List_Writer
        (Zlib.Seven_Zip_LZMA_Files'Access, "LZMA", "lzma");
      Check_File_List_Writer
        (Zlib.Seven_Zip_LZMA2_Files'Access, "LZMA2", "lzma2");
      Check_File_List_Writer
        (Zlib.Seven_Zip_PPMd_Files'Access, "PPMd", "ppmd");
   end Test_Directory_Creation_Preserves_Source_Metadata;

   procedure Test_Stored_Multiple_Files_Extract_To_Directory
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      First_Path   : constant String := Base_Path ("extract-first.bin");
      Second_Path  : constant String := Base_Path ("extract-second.bin");
      Archive_Path : constant String := Base_Path ("extract-multi.7z");
      Output_Dir   : constant String := Base_Path ("extract-output");
      First_Data   : constant Zlib.Byte_Array :=
        [16#61#, 16#6C#, 16#70#, 16#68#, 16#61#];
      Second_Data  : constant Zlib.Byte_Array :=
        [16#62#, 16#65#, 16#74#, 16#61#];
      Input_Paths  : constant Zlib.Text_Array :=
        [US.To_Unbounded_String (First_Path),
         US.To_Unbounded_String (Second_Path)];
      Entry_Names  : constant Zlib.Text_Array :=
        [US.To_Unbounded_String ("alpha.txt"),
         US.To_Unbounded_String ("nested/beta.bin")];
      Status       : Zlib.Status_Code := Zlib.Ok;
   begin
      Delete_If_Exists (First_Path);
      Delete_If_Exists (Second_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);

      Write_File (First_Path, First_Data);
      Write_File (Second_Path, Second_Data);
      Zlib.Seven_Zip_Stored_Files
        (Input_Paths, Archive_Path, Entry_Names, Status);
      Assert (Status = Zlib.Ok, "directory extract fixture creation status");

      Zlib.Extract_Seven_Zip_Stored_Files
        (Archive_Path, Output_Dir, Entry_Names, Status);
      Assert (Status = Zlib.Ok, "multi-file 7z directory extract status");
      Assert
        (Read_File (Ada.Directories.Compose (Output_Dir, "alpha.txt")) =
         First_Data,
         "multi-file 7z directory extract first payload");
      Assert
        (Read_File
           (Output_Dir & "/nested/beta.bin") =
         Second_Data,
         "multi-file 7z directory extract nested payload");

      Delete_If_Exists (First_Path);
      Delete_If_Exists (Second_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);
   exception
      when others =>
         Delete_If_Exists (First_Path);
         Delete_If_Exists (Second_Path);
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);
         raise;
   end Test_Stored_Multiple_Files_Extract_To_Directory;

   procedure Test_Stored_Multiple_Files_Empty_Entry_Roundtrip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Empty_Path   : constant String := Base_Path ("multi-empty.bin");
      Data_Path    : constant String := Base_Path ("multi-data.bin");
      Archive_Path : constant String := Base_Path ("multi-empty.7z");
      Output_Dir   : constant String := Base_Path ("multi-empty-output");
      Empty_Data   : constant Zlib.Byte_Array (1 .. 0) := [others => 0];
      Data         : constant Zlib.Byte_Array := [16#64#, 16#61#, 16#74#, 16#61#];
      Input_Paths  : constant Zlib.Text_Array :=
        [US.To_Unbounded_String (Empty_Path),
         US.To_Unbounded_String (Data_Path)];
      Entry_Names  : constant Zlib.Text_Array :=
        [US.To_Unbounded_String ("empty.bin"),
         US.To_Unbounded_String ("dir/data.bin")];
      Status       : Zlib.Status_Code := Zlib.Ok;
   begin
      Delete_If_Exists (Empty_Path);
      Delete_If_Exists (Data_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);

      Write_File (Empty_Path, Empty_Data);
      Write_File (Data_Path, Data);
      Zlib.Seven_Zip_Stored_Files
        (Input_Paths, Archive_Path, Entry_Names, Status);
      Assert (Status = Zlib.Ok, "multi-file empty-entry creation status");

      declare
         Archive     : constant Zlib.Byte_Array := Read_File (Archive_Path);
         Empty_Plain : constant Zlib.Byte_Array :=
           Zlib.Extract_Seven_Zip_Stored (Archive, "empty.bin", Status);
      begin
         Assert (Status = Zlib.Ok, "multi-file empty-entry extract status");
         Assert (Empty_Plain'Length = 0, "multi-file empty entry payload");

         declare
            Data_Plain : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip_Stored
                (Archive, "dir/data.bin", Status);
         begin
            Assert (Status = Zlib.Ok, "multi-file non-empty sibling extract status");
            Assert (Data_Plain = Data, "multi-file non-empty sibling payload");
         end;
      end;

      Zlib.Extract_Seven_Zip_Stored_Files
        (Archive_Path, Output_Dir, Entry_Names, Status);
      Assert (Status = Zlib.Ok, "multi-file empty-entry directory extract status");
      Assert
        (Read_File (Ada.Directories.Compose (Output_Dir, "empty.bin"))'Length = 0,
         "multi-file empty entry writes empty output file");
      Assert
        (Read_File (Output_Dir & "/dir/data.bin") = Data,
         "multi-file empty entry preserves sibling output");

      Delete_If_Exists (Empty_Path);
      Delete_If_Exists (Data_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);
   exception
      when others =>
         Delete_If_Exists (Empty_Path);
         Delete_If_Exists (Data_Path);
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);
         raise;
   end Test_Stored_Multiple_Files_Empty_Entry_Roundtrip;

   procedure Test_Compressed_Multiple_Files_Empty_Entry_Roundtrip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      type File_List_Writer is access procedure
        (Input_Paths : Zlib.Text_Array;
         Output_Path : String;
         Entry_Names : Zlib.Text_Array;
         Status      : out Zlib.Status_Code);

      procedure Check_Empty_Entry
        (Writer : File_List_Writer;
         Label  : String;
         Suffix : String)
      is
         Empty_Path   : constant String :=
           Base_Path (Suffix & "-multi-empty.bin");
         Data_Path    : constant String :=
           Base_Path (Suffix & "-multi-data.bin");
         Archive_Path : constant String :=
           Base_Path (Suffix & "-multi-empty.7z");
         Output_Dir   : constant String :=
           Base_Path (Suffix & "-multi-empty-output");
         Empty_Data   : constant Zlib.Byte_Array (1 .. 0) := [others => 0];
         Data         : constant Zlib.Byte_Array :=
           [16#63#, 16#6F#, 16#64#, 16#65#, 16#63#];
         Input_Paths  : constant Zlib.Text_Array :=
           [US.To_Unbounded_String (Empty_Path),
            US.To_Unbounded_String (Data_Path)];
         Entry_Names  : constant Zlib.Text_Array :=
           [US.To_Unbounded_String ("empty.bin"),
            US.To_Unbounded_String ("dir/data.bin")];
         Status       : Zlib.Status_Code := Zlib.Ok;
      begin
         Delete_If_Exists (Empty_Path);
         Delete_If_Exists (Data_Path);
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);

         Write_File (Empty_Path, Empty_Data);
         Write_File (Data_Path, Data);
         Writer.all (Input_Paths, Archive_Path, Entry_Names, Status);
         Assert
           (Status = Zlib.Ok,
            Label & " multi-file empty-entry creation status");

         declare
            Archive     : constant Zlib.Byte_Array := Read_File (Archive_Path);
            Empty_Plain : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip (Archive, "empty.bin", Status);
         begin
            Assert
              (Status = Zlib.Ok,
               Label & " multi-file empty-entry extract status");
            Assert
              (Empty_Plain'Length = 0,
               Label & " multi-file empty entry payload");

            declare
               Data_Plain : constant Zlib.Byte_Array :=
                 Zlib.Extract_Seven_Zip
                   (Archive, "dir/data.bin", Status);
            begin
               Assert
                 (Status = Zlib.Ok,
                  Label & " multi-file non-empty sibling extract status");
               Assert
                 (Data_Plain = Data,
                  Label & " multi-file non-empty sibling payload");
            end;
         end;

         Zlib.Extract_Seven_Zip_Files
           (Archive_Path, Output_Dir, Entry_Names, Status);
         Assert
           (Status = Zlib.Ok,
            Label & " multi-file empty-entry directory extract status");
         Assert
           (Read_File (Ada.Directories.Compose (Output_Dir, "empty.bin"))'Length
            = 0,
            Label & " multi-file empty entry writes empty output file");
         Assert
           (Read_File (Output_Dir & "/dir/data.bin") = Data,
            Label & " multi-file empty entry preserves sibling output");

         Delete_If_Exists (Empty_Path);
         Delete_If_Exists (Data_Path);
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);
      exception
         when others =>
            Delete_If_Exists (Empty_Path);
            Delete_If_Exists (Data_Path);
            Delete_If_Exists (Archive_Path);
            Delete_If_Exists (Output_Dir);
            raise;
      end Check_Empty_Entry;
   begin
      Check_Empty_Entry
        (Zlib.Seven_Zip_Deflate_Files'Access, "Deflate", "deflate");
      Check_Empty_Entry
        (Zlib.Seven_Zip_BZip2_Files'Access, "BZip2", "bzip2");
      Check_Empty_Entry
        (Zlib.Seven_Zip_LZMA_Files'Access, "LZMA", "lzma");
      Check_Empty_Entry
        (Zlib.Seven_Zip_LZMA2_Files'Access, "LZMA2", "lzma2");
      Check_Empty_Entry
        (Zlib.Seven_Zip_PPMd_Files'Access, "PPMd", "ppmd");
   end Test_Compressed_Multiple_Files_Empty_Entry_Roundtrip;

   procedure Test_Compressed_File_List_Extraction_Prevalidates
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      type File_List_Writer is access procedure
        (Input_Paths : Zlib.Text_Array;
         Output_Path : String;
         Entry_Names : Zlib.Text_Array;
         Status      : out Zlib.Status_Code);

      procedure Check_Writer
        (Writer : File_List_Writer;
         Label  : String;
         Suffix : String)
      is
         Input_Path    : constant String :=
           Base_Path (Suffix & "-extract-safe-input.bin");
         Unsafe_Path   : constant String :=
           Base_Path (Suffix & "-extract-unsafe-input.bin");
         Safe_Archive  : constant String :=
           Base_Path (Suffix & "-extract-safe.7z");
         Unsafe_Archive : constant String :=
           Base_Path (Suffix & "-extract-unsafe.7z");
         Output_Dir    : constant String :=
           Base_Path (Suffix & "-extract-output");
         Safe_Data     : constant Zlib.Byte_Array :=
           [16#73#, 16#61#, 16#66#, 16#65#];
         Unsafe_Data   : constant Zlib.Byte_Array :=
           [16#75#, 16#6E#, 16#73#, 16#61#, 16#66#, 16#65#];
         Safe_Path_List : constant Zlib.Text_Array :=
           [1 => US.To_Unbounded_String (Input_Path)];
         Unsafe_Path_List : constant Zlib.Text_Array :=
           [1 => US.To_Unbounded_String (Unsafe_Path)];
         Safe_Names    : constant Zlib.Text_Array :=
           [1 => US.To_Unbounded_String ("safe.txt")];
         Unsafe_Names  : constant Zlib.Text_Array :=
           [1 => US.To_Unbounded_String ("../escape.txt")];
         Duplicate_Requests : constant Zlib.Text_Array :=
           [US.To_Unbounded_String ("safe.txt"),
            US.To_Unbounded_String ("safe.txt")];
         Missing_Requests : constant Zlib.Text_Array :=
           [US.To_Unbounded_String ("safe.txt"),
            US.To_Unbounded_String ("missing.txt")];
         Status        : Zlib.Status_Code := Zlib.Ok;
      begin
         Delete_If_Exists (Input_Path);
         Delete_If_Exists (Unsafe_Path);
         Delete_If_Exists (Safe_Archive);
         Delete_If_Exists (Unsafe_Archive);
         Delete_If_Exists (Output_Dir);

         Write_File (Input_Path, Safe_Data);
         Write_File (Unsafe_Path, Unsafe_Data);

         Writer.all (Unsafe_Path_List, Unsafe_Archive, Unsafe_Names, Status);
         Assert
           (Status = Zlib.Ok,
            Label & " unsafe-name fixture creation status");
         Zlib.Extract_Seven_Zip_Files
           (Unsafe_Archive, Output_Dir, Unsafe_Names, Status);
         Assert
           (Status = Zlib.Unsupported_Method,
            Label & " directory extract rejects unsafe compressed names");
         Assert
           (not Ada.Directories.Exists (Output_Dir),
            Label & " unsafe compressed extract does not create output dir");

         Writer.all (Safe_Path_List, Safe_Archive, Safe_Names, Status);
         Assert
           (Status = Zlib.Ok,
            Label & " safe fixture creation status");

         Zlib.Extract_Seven_Zip_Files
           (Safe_Archive, Output_Dir, Duplicate_Requests, Status);
         Assert
           (Status = Zlib.Unsupported_Method,
            Label & " directory extract rejects duplicate compressed requests");
         Assert
           (not Ada.Directories.Exists
              (Ada.Directories.Compose (Output_Dir, "safe.txt")),
            Label & " duplicate compressed requests do not write output");

         Zlib.Extract_Seven_Zip_Files
           (Safe_Archive, Output_Dir, Missing_Requests, Status);
         Assert
           (Status = Zlib.Unsupported_Method,
            Label & " directory extract rejects missing compressed entries");
         Assert
           (not Ada.Directories.Exists
              (Ada.Directories.Compose (Output_Dir, "safe.txt")),
            Label & " missing compressed request does not write earlier output");

         Delete_If_Exists (Input_Path);
         Delete_If_Exists (Unsafe_Path);
         Delete_If_Exists (Safe_Archive);
         Delete_If_Exists (Unsafe_Archive);
         Delete_If_Exists (Output_Dir);
      exception
         when others =>
            Delete_If_Exists (Input_Path);
            Delete_If_Exists (Unsafe_Path);
            Delete_If_Exists (Safe_Archive);
            Delete_If_Exists (Unsafe_Archive);
            Delete_If_Exists (Output_Dir);
            raise;
      end Check_Writer;
   begin
      Check_Writer
        (Zlib.Seven_Zip_Deflate_Files'Access, "Deflate", "deflate");
      Check_Writer
        (Zlib.Seven_Zip_BZip2_Files'Access, "BZip2", "bzip2");
      Check_Writer
        (Zlib.Seven_Zip_LZMA_Files'Access, "LZMA", "lzma");
      Check_Writer
        (Zlib.Seven_Zip_LZMA2_Files'Access, "LZMA2", "lzma2");
      Check_Writer
        (Zlib.Seven_Zip_PPMd_Files'Access, "PPMd", "ppmd");
   end Test_Compressed_File_List_Extraction_Prevalidates;

   procedure Test_Compressed_File_List_Extraction_Rejects_Output_Dirs
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      type File_List_Writer is access procedure
        (Input_Paths : Zlib.Text_Array;
         Output_Path : String;
         Entry_Names : Zlib.Text_Array;
         Status      : out Zlib.Status_Code);

      procedure Check_Writer
        (Writer : File_List_Writer;
         Label  : String;
         Suffix : String)
      is
         Input_Path   : constant String :=
           Base_Path (Suffix & "-output-root-input.bin");
         Archive_Path : constant String :=
           Base_Path (Suffix & "-output-root.7z");
         Output_Root  : constant String :=
           Base_Path (Suffix & "-output-root-file");
         Entry_Name   : constant String := Suffix & "-safe.txt";
         Input_Data   : constant Zlib.Byte_Array :=
           [16#70#, 16#61#, 16#79#, 16#6C#, 16#6F#, 16#61#, 16#64#];
         Marker_Data  : constant Zlib.Byte_Array :=
           [16#6D#, 16#61#, 16#72#, 16#6B#];
         Input_Paths  : constant Zlib.Text_Array :=
           [1 => US.To_Unbounded_String (Input_Path)];
         Entry_Names  : constant Zlib.Text_Array :=
           [1 => US.To_Unbounded_String (Entry_Name)];
         Status       : Zlib.Status_Code := Zlib.Ok;
      begin
         Delete_If_Exists (Input_Path);
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Root);
         Delete_If_Exists (Entry_Name);
         Delete_If_Exists (Output_Root & "/" & Entry_Name);

         Write_File (Input_Path, Input_Data);
         Writer.all (Input_Paths, Archive_Path, Entry_Names, Status);
         Assert
           (Status = Zlib.Ok,
            Label & " output-root fixture creation status");

         Zlib.Extract_Seven_Zip_Files
           (Archive_Path, "", Entry_Names, Status);
         Assert
           (Status = Zlib.Unsupported_Method,
            Label & " directory extract rejects empty output dir");
         Assert
           (not Ada.Directories.Exists (Entry_Name),
            Label & " empty output dir does not write relative output");

         Write_File (Output_Root, Marker_Data);
         Zlib.Extract_Seven_Zip_Files
           (Archive_Path, Output_Root, Entry_Names, Status);
         Assert
           (Status = Zlib.Output_File_Error,
            Label & " directory extract rejects file output root");
         Assert
           (Read_File (Output_Root) = Marker_Data,
            Label & " file output root marker is not overwritten");
         Assert
           (not Ada.Directories.Exists (Output_Root & "/" & Entry_Name),
            Label & " file output root does not receive payload path");

         Delete_If_Exists (Input_Path);
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Root);
         Delete_If_Exists (Entry_Name);
      exception
         when others =>
            Delete_If_Exists (Input_Path);
            Delete_If_Exists (Archive_Path);
            Delete_If_Exists (Output_Root);
            Delete_If_Exists (Entry_Name);
            raise;
      end Check_Writer;
   begin
      Check_Writer
        (Zlib.Seven_Zip_Deflate_Files'Access, "Deflate", "deflate");
      Check_Writer
        (Zlib.Seven_Zip_BZip2_Files'Access, "BZip2", "bzip2");
      Check_Writer
        (Zlib.Seven_Zip_LZMA_Files'Access, "LZMA", "lzma");
      Check_Writer
        (Zlib.Seven_Zip_LZMA2_Files'Access, "LZMA2", "lzma2");
      Check_Writer
        (Zlib.Seven_Zip_PPMd_Files'Access, "PPMd", "ppmd");
   end Test_Compressed_File_List_Extraction_Rejects_Output_Dirs;

   procedure Test_Stored_Multiple_Files_Rejects_Unsafe_Output_Name
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input_Path   : constant String := Base_Path ("unsafe-input.bin");
      Archive_Path : constant String := Base_Path ("unsafe.7z");
      Output_Dir   : constant String := Base_Path ("unsafe-output");
      Input_Data   : constant Zlib.Byte_Array := [16#78#];
      Input_Paths  : constant Zlib.Text_Array :=
        [1 => US.To_Unbounded_String (Input_Path)];
      Archive_Names : constant Zlib.Text_Array :=
        [1 => US.To_Unbounded_String ("../escape.txt")];
      Status       : Zlib.Status_Code := Zlib.Ok;
   begin
      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);

      Write_File (Input_Path, Input_Data);
      Zlib.Seven_Zip_Stored_Files
        (Input_Paths, Archive_Path, Archive_Names, Status);
      Assert (Status = Zlib.Ok, "unsafe-name fixture creation status");

      Zlib.Extract_Seven_Zip_Stored_Files
        (Archive_Path, Output_Dir, Archive_Names, Status);
      Assert
        (Status = Zlib.Unsupported_Method,
         "directory extract rejects unsafe entry names");

      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);
   exception
      when others =>
         Delete_If_Exists (Input_Path);
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);
         raise;
   end Test_Stored_Multiple_Files_Rejects_Unsafe_Output_Name;

   procedure Test_Stored_Multiple_Files_Prevalidates_Output_Names
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      First_Path   : constant String := Base_Path ("prevalidate-first.bin");
      Second_Path  : constant String := Base_Path ("prevalidate-second.bin");
      Archive_Path : constant String := Base_Path ("prevalidate.7z");
      Output_Dir   : constant String := Base_Path ("prevalidate-output");
      First_Data   : constant Zlib.Byte_Array := [16#31#];
      Second_Data  : constant Zlib.Byte_Array := [16#32#];
      Input_Paths  : constant Zlib.Text_Array :=
        [US.To_Unbounded_String (First_Path),
         US.To_Unbounded_String (Second_Path)];
      Archive_Names : constant Zlib.Text_Array :=
        [US.To_Unbounded_String ("safe.txt"),
         US.To_Unbounded_String ("../escape.txt")];
      Status       : Zlib.Status_Code := Zlib.Ok;
   begin
      Delete_If_Exists (First_Path);
      Delete_If_Exists (Second_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);

      Write_File (First_Path, First_Data);
      Write_File (Second_Path, Second_Data);
      Zlib.Seven_Zip_Stored_Files
        (Input_Paths, Archive_Path, Archive_Names, Status);
      Assert (Status = Zlib.Ok, "prevalidate fixture creation status");

      Zlib.Extract_Seven_Zip_Stored_Files
        (Archive_Path, Output_Dir, Archive_Names, Status);
      Assert
        (Status = Zlib.Unsupported_Method,
         "directory extract prevalidates unsafe names");
      Assert
        (not Ada.Directories.Exists
           (Ada.Directories.Compose (Output_Dir, "safe.txt")),
         "directory extract does not partially write before unsafe name");

      Delete_If_Exists (First_Path);
      Delete_If_Exists (Second_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);
   exception
      when others =>
         Delete_If_Exists (First_Path);
         Delete_If_Exists (Second_Path);
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);
         raise;
   end Test_Stored_Multiple_Files_Prevalidates_Output_Names;

   procedure Test_Stored_Multiple_Files_Rejects_Duplicate_Output_Requests
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input_Path   : constant String := Base_Path ("duplicate-request-input.bin");
      Archive_Path : constant String := Base_Path ("duplicate-request.7z");
      Output_Dir   : constant String := Base_Path ("duplicate-request-output");
      Input_Data   : constant Zlib.Byte_Array := [16#64#];
      Input_Paths  : constant Zlib.Text_Array :=
        [1 => US.To_Unbounded_String (Input_Path)];
      Archive_Names : constant Zlib.Text_Array :=
        [1 => US.To_Unbounded_String ("payload.txt")];
      Requested_Names : constant Zlib.Text_Array :=
        [US.To_Unbounded_String ("payload.txt"),
         US.To_Unbounded_String ("payload.txt")];
      Status       : Zlib.Status_Code := Zlib.Ok;
   begin
      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);

      Write_File (Input_Path, Input_Data);
      Zlib.Seven_Zip_Stored_Files
        (Input_Paths, Archive_Path, Archive_Names, Status);
      Assert (Status = Zlib.Ok, "duplicate-request fixture creation status");

      Zlib.Extract_Seven_Zip_Stored_Files
        (Archive_Path, Output_Dir, Requested_Names, Status);
      Assert
        (Status = Zlib.Unsupported_Method,
         "directory extract rejects duplicate requested names");
      Assert
        (not Ada.Directories.Exists
           (Ada.Directories.Compose (Output_Dir, "payload.txt")),
         "duplicate requested name does not write output");

      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);
   exception
      when others =>
         Delete_If_Exists (Input_Path);
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);
         raise;
   end Test_Stored_Multiple_Files_Rejects_Duplicate_Output_Requests;

   procedure Test_Stored_Multiple_Files_Stages_Before_Writing
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input_Path   : constant String := Base_Path ("stage-before-write-input.bin");
      Archive_Path : constant String := Base_Path ("stage-before-write.7z");
      Output_Dir   : constant String := Base_Path ("stage-before-write-output");
      Input_Data   : constant Zlib.Byte_Array := [16#73#, 16#61#, 16#66#, 16#65#];
      Input_Paths  : constant Zlib.Text_Array :=
        [1 => US.To_Unbounded_String (Input_Path)];
      Archive_Names : constant Zlib.Text_Array :=
        [1 => US.To_Unbounded_String ("safe.txt")];
      Requested_Names : constant Zlib.Text_Array :=
        [US.To_Unbounded_String ("safe.txt"),
         US.To_Unbounded_String ("missing.txt")];
      Status       : Zlib.Status_Code := Zlib.Ok;
   begin
      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);

      Write_File (Input_Path, Input_Data);
      Zlib.Seven_Zip_Stored_Files
        (Input_Paths, Archive_Path, Archive_Names, Status);
      Assert (Status = Zlib.Ok, "stage-before-write fixture creation status");

      Zlib.Extract_Seven_Zip_Stored_Files
        (Archive_Path, Output_Dir, Requested_Names, Status);
      Assert
        (Status = Zlib.Unsupported_Method,
         "directory extract rejects missing requested entries");
      Assert
        (not Ada.Directories.Exists
           (Ada.Directories.Compose (Output_Dir, "safe.txt")),
         "directory extract does not write earlier entries before missing entry");

      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);
   exception
      when others =>
         Delete_If_Exists (Input_Path);
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);
         raise;
   end Test_Stored_Multiple_Files_Stages_Before_Writing;

   procedure Test_Stored_Multiple_Files_Preflights_Output_Paths
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      First_Path   : constant String := Base_Path ("preflight-output-first.bin");
      Second_Path  : constant String := Base_Path ("preflight-output-second.bin");
      Archive_Path : constant String := Base_Path ("preflight-output.7z");
      Output_Dir   : constant String := Base_Path ("preflight-output-dir");
      Blocker_Path : constant String :=
        Ada.Directories.Compose (Output_Dir, "blocked");
      First_Output : constant String :=
        Ada.Directories.Compose (Output_Dir, "safe.txt");
      First_Data   : constant Zlib.Byte_Array := [16#66#, 16#69#, 16#72#, 16#73#, 16#74#];
      Second_Data  : constant Zlib.Byte_Array := [16#73#, 16#65#, 16#63#, 16#6F#, 16#6E#, 16#64#];
      Marker_Data  : constant Zlib.Byte_Array := [16#62#, 16#6C#, 16#6F#, 16#63#, 16#6B#];
      Input_Paths  : constant Zlib.Text_Array :=
        [US.To_Unbounded_String (First_Path),
         US.To_Unbounded_String (Second_Path)];
      Entry_Names  : constant Zlib.Text_Array :=
        [US.To_Unbounded_String ("safe.txt"),
         US.To_Unbounded_String ("blocked/payload.txt")];
      Status       : Zlib.Status_Code := Zlib.Ok;
   begin
      Delete_If_Exists (First_Path);
      Delete_If_Exists (Second_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);

      Write_File (First_Path, First_Data);
      Write_File (Second_Path, Second_Data);
      Zlib.Seven_Zip_Stored_Files
        (Input_Paths, Archive_Path, Entry_Names, Status);
      Assert (Status = Zlib.Ok, "preflight-output fixture creation status");

      Ada.Directories.Create_Path (Output_Dir);
      Write_File (Blocker_Path, Marker_Data);

      Zlib.Extract_Seven_Zip_Stored_Files
        (Archive_Path, Output_Dir, Entry_Names, Status);
      Assert
        (Status = Zlib.Output_File_Error,
         "directory extract rejects blocked nested output parent");
      Assert
        (Read_File (Blocker_Path) = Marker_Data,
         "blocked nested output parent marker is not overwritten");
      Assert
        (not Ada.Directories.Exists (First_Output),
         "directory extract does not write earlier output before path blocker");

      Delete_If_Exists (First_Path);
      Delete_If_Exists (Second_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);
   exception
      when others =>
         Delete_If_Exists (First_Path);
         Delete_If_Exists (Second_Path);
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);
         raise;
   end Test_Stored_Multiple_Files_Preflights_Output_Paths;

   procedure Test_Stored_Multiple_Files_Prevalidates_Output_Dir
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      type File_List_Extractor is access procedure
        (Input_Path  : String;
         Output_Dir  : String;
         Entry_Names : Zlib.Text_Array;
         Status      : out Zlib.Status_Code);

      procedure Check_Extractor
        (Extractor : File_List_Extractor;
         Label     : String;
         Suffix    : String)
      is
         Missing_Path : constant String :=
           Base_Path (Suffix & "-list-output-dir-preflight-missing.7z");
         Output_Dir   : constant String :=
           Base_Path (Suffix & "-list-output-dir-preflight-root");
         Marker_Data  : constant Zlib.Byte_Array := [16#72#, 16#6F#, 16#6F#, 16#74#];
         Entry_Names  : constant Zlib.Text_Array :=
           [1 => US.To_Unbounded_String ("payload.txt")];
         Status       : Zlib.Status_Code := Zlib.Ok;
      begin
         Delete_If_Exists (Missing_Path);
         Delete_If_Exists (Output_Dir);

         Write_File (Output_Dir, Marker_Data);

         Extractor.all (Missing_Path, Output_Dir, Entry_Names, Status);
         Assert
           (Status = Zlib.Output_File_Error,
            Label & " file-list extraction validates output root before input read");
         Assert
           (Read_File (Output_Dir) = Marker_Data,
            Label & " file-list extraction output root marker is preserved");

         Delete_If_Exists (Missing_Path);
         Delete_If_Exists (Output_Dir);
      exception
         when others =>
            Delete_If_Exists (Missing_Path);
            Delete_If_Exists (Output_Dir);
            raise;
      end Check_Extractor;
   begin
      Check_Extractor
        (Zlib.Extract_Seven_Zip_Stored_Files'Access, "Stored", "stored");
      Check_Extractor
        (Zlib.Extract_Seven_Zip_Files'Access, "Alias", "alias");
   end Test_Stored_Multiple_Files_Prevalidates_Output_Dir;

   procedure Test_Stored_Multiple_Files_Rejects_File_Output_Dir
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input_Path   : constant String := Base_Path ("file-output-dir-input.bin");
      Archive_Path : constant String := Base_Path ("file-output-dir.7z");
      Output_Dir   : constant String := Base_Path ("file-output-dir-root");
      Input_Data   : constant Zlib.Byte_Array := [16#66#, 16#69#, 16#6C#, 16#65#];
      Marker_Data  : constant Zlib.Byte_Array := [16#72#, 16#6F#, 16#6F#, 16#74#];
      Input_Paths  : constant Zlib.Text_Array :=
        [1 => US.To_Unbounded_String (Input_Path)];
      Entry_Names  : constant Zlib.Text_Array :=
        [1 => US.To_Unbounded_String ("payload.txt")];
      Status       : Zlib.Status_Code := Zlib.Ok;
   begin
      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);
      Delete_If_Exists (Output_Dir & "/payload.txt");

      Write_File (Input_Path, Input_Data);
      Zlib.Seven_Zip_Stored_Files
        (Input_Paths, Archive_Path, Entry_Names, Status);
      Assert (Status = Zlib.Ok, "file-output-dir fixture creation status");

      Write_File (Output_Dir, Marker_Data);
      Zlib.Extract_Seven_Zip_Stored_Files
        (Archive_Path, Output_Dir, Entry_Names, Status);
      Assert
        (Status = Zlib.Output_File_Error,
         "directory extract rejects output root that is a file");
      Assert
        (Read_File (Output_Dir) = Marker_Data,
         "file output root is not overwritten");
      Assert
        (not Ada.Directories.Exists (Output_Dir & "/payload.txt"),
         "file output root does not receive derived payload path");

      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);
   exception
      when others =>
         Delete_If_Exists (Input_Path);
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);
         raise;
   end Test_Stored_Multiple_Files_Rejects_File_Output_Dir;

   procedure Test_Stored_Multiple_Files_Rejects_Empty_Output_Dir
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input_Path   : constant String := Base_Path ("empty-output-dir-input.bin");
      Archive_Path : constant String := Base_Path ("empty-output-dir.7z");
      Input_Data   : constant Zlib.Byte_Array := [16#6F#, 16#6B#];
      Input_Paths  : constant Zlib.Text_Array :=
        [1 => US.To_Unbounded_String (Input_Path)];
      Entry_Names  : constant Zlib.Text_Array :=
        [1 => US.To_Unbounded_String ("payload.txt")];
      Status       : Zlib.Status_Code := Zlib.Ok;
   begin
      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists ("payload.txt");

      Write_File (Input_Path, Input_Data);
      Zlib.Seven_Zip_Stored_Files
        (Input_Paths, Archive_Path, Entry_Names, Status);
      Assert (Status = Zlib.Ok, "empty-output-dir fixture creation status");

      Zlib.Extract_Seven_Zip_Stored_Files
        (Archive_Path, "", Entry_Names, Status);
      Assert
        (Status = Zlib.Unsupported_Method,
         "directory extract rejects empty output directory");
      Assert
        (not Ada.Directories.Exists ("payload.txt"),
         "empty output directory does not write relative or absolute output");

      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists ("payload.txt");
   exception
      when others =>
         Delete_If_Exists (Input_Path);
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists ("payload.txt");
         raise;
   end Test_Stored_Multiple_Files_Rejects_Empty_Output_Dir;

   procedure Test_Stored_Multiple_Files_Rejects_Duplicate_Names
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      First_Path   : constant String := Base_Path ("duplicate-first.bin");
      Second_Path  : constant String := Base_Path ("duplicate-second.bin");
      Archive_Path : constant String := Base_Path ("duplicate.7z");
      First_Data   : constant Zlib.Byte_Array := [16#31#];
      Second_Data  : constant Zlib.Byte_Array := [16#32#];
      Input_Paths  : constant Zlib.Text_Array :=
        [US.To_Unbounded_String (First_Path),
         US.To_Unbounded_String (Second_Path)];
      Entry_Names  : constant Zlib.Text_Array :=
        [US.To_Unbounded_String ("same.txt"),
         US.To_Unbounded_String ("same.txt")];
      Status       : Zlib.Status_Code := Zlib.Ok;
   begin
      Delete_If_Exists (First_Path);
      Delete_If_Exists (Second_Path);
      Delete_If_Exists (Archive_Path);

      Write_File (First_Path, First_Data);
      Write_File (Second_Path, Second_Data);
      Zlib.Seven_Zip_Stored_Files
        (Input_Paths, Archive_Path, Entry_Names, Status);
      Assert
        (Status = Zlib.Unsupported_Method,
         "multi-file stored 7z creation rejects duplicate entry names");
      Assert
        (not Ada.Directories.Exists (Archive_Path),
         "duplicate-name creation does not leave an archive");

      Delete_If_Exists (First_Path);
      Delete_If_Exists (Second_Path);
      Delete_If_Exists (Archive_Path);
   exception
      when others =>
         Delete_If_Exists (First_Path);
         Delete_If_Exists (Second_Path);
         Delete_If_Exists (Archive_Path);
         raise;
   end Test_Stored_Multiple_Files_Rejects_Duplicate_Names;

   procedure Test_Stored_File_List_Rejects_Invalid_Array_Shapes
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Missing_Path : constant String := Base_Path ("invalid-shape-missing.bin");
      Archive_Path : constant String := Base_Path ("invalid-shape.7z");
      Output_Dir   : constant String := Base_Path ("invalid-shape-output");
      Empty_Paths  : constant Zlib.Text_Array (1 .. 0) := [];
      Empty_Names  : constant Zlib.Text_Array (1 .. 0) := [];
      One_Path     : constant Zlib.Text_Array :=
        [1 => US.To_Unbounded_String (Missing_Path)];
      Two_Names    : constant Zlib.Text_Array :=
        [US.To_Unbounded_String ("one.txt"),
         US.To_Unbounded_String ("two.txt")];
      Status       : Zlib.Status_Code := Zlib.Ok;
   begin
      Delete_If_Exists (Missing_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);

      Zlib.Seven_Zip_Stored_Files
        (Empty_Paths, Archive_Path, Empty_Names, Status);
      Assert
        (Status = Zlib.Unsupported_Method,
         "multi-file stored 7z creation rejects null arrays");
      Assert
        (not Ada.Directories.Exists (Archive_Path),
         "null-array creation does not leave an archive");

      Zlib.Seven_Zip_Stored_Files
        (One_Path, Archive_Path, Two_Names, Status);
      Assert
        (Status = Zlib.Unsupported_Method,
         "multi-file stored 7z creation rejects mismatched arrays");
      Assert
        (not Ada.Directories.Exists (Archive_Path),
         "mismatched-array creation does not read or write an archive");

      Zlib.Extract_Seven_Zip_Stored_Files
        (Archive_Path, Output_Dir, Empty_Names, Status);
      Assert
        (Status = Zlib.Unsupported_Method,
         "multi-file stored 7z extraction rejects null request arrays");
      Assert
        (not Ada.Directories.Exists (Output_Dir),
         "null request extraction does not create output directory");

      Delete_If_Exists (Missing_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);
   exception
      when others =>
         Delete_If_Exists (Missing_Path);
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);
         raise;
   end Test_Stored_File_List_Rejects_Invalid_Array_Shapes;

   procedure Test_Deflate_Level_File_List_Rejects_Invalid_Inputs
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      First_Path   : constant String := Base_Path ("level-invalid-first.bin");
      Second_Path  : constant String := Base_Path ("level-invalid-second.bin");
      Archive_Path : constant String := Base_Path ("level-invalid.7z");
      First_Data   : constant Zlib.Byte_Array := [16#31#];
      Second_Data  : constant Zlib.Byte_Array := [16#32#];
      Empty_Paths  : constant Zlib.Text_Array (1 .. 0) := [];
      Empty_Names  : constant Zlib.Text_Array (1 .. 0) := [];
      One_Path     : constant Zlib.Text_Array :=
        [1 => US.To_Unbounded_String (First_Path)];
      Input_Paths  : constant Zlib.Text_Array :=
        [US.To_Unbounded_String (First_Path),
         US.To_Unbounded_String (Second_Path)];
      Duplicate_Names : constant Zlib.Text_Array :=
        [US.To_Unbounded_String ("same.txt"),
         US.To_Unbounded_String ("same.txt")];
      Two_Names    : constant Zlib.Text_Array :=
        [US.To_Unbounded_String ("one.txt"),
         US.To_Unbounded_String ("two.txt")];
      Status       : Zlib.Status_Code := Zlib.Ok;
   begin
      Delete_If_Exists (First_Path);
      Delete_If_Exists (Second_Path);
      Delete_If_Exists (Archive_Path);

      Write_File (First_Path, First_Data);
      Write_File (Second_Path, Second_Data);

      Zlib.Seven_Zip_Deflate_Files
        (Input_Paths, Archive_Path, Duplicate_Names, Zlib.Default_Level, Status);
      Assert
        (Status = Zlib.Unsupported_Method,
         "level Deflate 7z file-list rejects duplicate entry names");
      Assert
        (not Ada.Directories.Exists (Archive_Path),
         "level duplicate-name creation does not leave an archive");

      Zlib.Seven_Zip_Deflate_Files
        (Empty_Paths, Archive_Path, Empty_Names, Zlib.Default_Level, Status);
      Assert
        (Status = Zlib.Unsupported_Method,
         "level Deflate 7z file-list rejects null arrays");
      Assert
        (not Ada.Directories.Exists (Archive_Path),
         "level null-array creation does not leave an archive");

      Zlib.Seven_Zip_Deflate_Files
        (One_Path, Archive_Path, Two_Names, Zlib.Default_Level, Status);
      Assert
        (Status = Zlib.Unsupported_Method,
         "level Deflate 7z file-list rejects mismatched arrays");
      Assert
        (not Ada.Directories.Exists (Archive_Path),
         "level mismatched-array creation does not leave an archive");

      Delete_If_Exists (First_Path);
      Delete_If_Exists (Second_Path);
      Delete_If_Exists (Archive_Path);
   exception
      when others =>
         Delete_If_Exists (First_Path);
         Delete_If_Exists (Second_Path);
         Delete_If_Exists (Archive_Path);
         raise;
   end Test_Deflate_Level_File_List_Rejects_Invalid_Inputs;

   procedure Test_Deflate_Level_File_List_Rejects_Output_And_Prevalidates
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input_Path   : constant String := Base_Path ("level-output-input.bin");
      Missing_Path : constant String := Base_Path ("level-output-missing.bin");
      Archive_Path : constant String := Base_Path ("level-output.7z");
      Marker_Path  : constant String :=
        Ada.Directories.Compose (Archive_Path, "marker.bin");
      Input_Data   : constant Zlib.Byte_Array := [16#61#, 16#72#, 16#63#];
      Marker_Data  : constant Zlib.Byte_Array := [16#6D#, 16#61#, 16#72#, 16#6B#];
      One_Path     : constant Zlib.Text_Array :=
        [1 => US.To_Unbounded_String (Input_Path)];
      One_Name     : constant Zlib.Text_Array :=
        [1 => US.To_Unbounded_String ("payload.txt")];
      Missing_Paths : constant Zlib.Text_Array :=
        [US.To_Unbounded_String (Missing_Path),
         US.To_Unbounded_String (Missing_Path)];
      Invalid_Names : constant Zlib.Text_Array :=
        [US.To_Unbounded_String ("first.txt"),
         US.To_Unbounded_String ("")];
      Two_Names    : constant Zlib.Text_Array :=
        [US.To_Unbounded_String ("first.txt"),
         US.To_Unbounded_String ("second.txt")];
      Status       : Zlib.Status_Code := Zlib.Ok;
   begin
      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Missing_Path);
      Delete_If_Exists (Archive_Path);

      Write_File (Input_Path, Input_Data);
      Ada.Directories.Create_Path (Archive_Path);
      Write_File (Marker_Path, Marker_Data);

      Zlib.Seven_Zip_Deflate_Files
        (One_Path, Archive_Path, One_Name, Zlib.Default_Level, Status);
      Assert
        (Status = Zlib.Output_File_Error,
         "level Deflate 7z file-list rejects directory output path");
      Assert
        (Ada.Directories.Kind (Archive_Path) = Ada.Directories.Directory,
         "level directory output path remains a directory");
      Assert
        (Read_File (Marker_Path) = Marker_Data,
         "level directory output path marker is not overwritten");

      Delete_If_Exists (Archive_Path);

      Zlib.Seven_Zip_Deflate_Files
        (Missing_Paths, Archive_Path, Invalid_Names, Zlib.Default_Level, Status);
      Assert
        (Status = Zlib.Unsupported_Method,
         "level Deflate 7z file-list validates names before reading");
      Assert
        (not Ada.Directories.Exists (Archive_Path),
         "level prevalidation failure does not leave an archive");

      Zlib.Seven_Zip_Deflate_Files
        (Missing_Paths, Archive_Path, Two_Names, Zlib.Default_Level, Status);
      Assert
        (Status = Zlib.Input_File_Error,
         "level Deflate 7z file-list preflights missing input files");
      Assert
        (not Ada.Directories.Exists (Archive_Path),
         "level missing input preflight does not leave an archive");

      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Missing_Path);
      Delete_If_Exists (Archive_Path);
   exception
      when others =>
         Delete_If_Exists (Input_Path);
         Delete_If_Exists (Missing_Path);
         Delete_If_Exists (Archive_Path);
         raise;
   end Test_Deflate_Level_File_List_Rejects_Output_And_Prevalidates;

   procedure Test_Compressed_File_List_Rejects_Invalid_Inputs
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      type File_List_Writer is access procedure
        (Input_Paths : Zlib.Text_Array;
         Output_Path : String;
         Entry_Names : Zlib.Text_Array;
         Status      : out Zlib.Status_Code);

      procedure Check_Writer
        (Writer : File_List_Writer;
         Label  : String;
         Suffix : String)
      is
         First_Path   : constant String := Base_Path (Suffix & "-invalid-first.bin");
         Second_Path  : constant String := Base_Path (Suffix & "-invalid-second.bin");
         Missing_Path : constant String := Base_Path (Suffix & "-invalid-missing.bin");
         Archive_Path : constant String := Base_Path (Suffix & "-invalid.7z");
         Marker_Path  : constant String :=
           Ada.Directories.Compose (Archive_Path, "marker.bin");
         First_Data   : constant Zlib.Byte_Array := [16#31#];
         Second_Data  : constant Zlib.Byte_Array := [16#32#];
         Marker_Data  : constant Zlib.Byte_Array := [16#6D#, 16#61#, 16#72#, 16#6B#];
         Empty_Paths  : constant Zlib.Text_Array (1 .. 0) := [];
         Empty_Names  : constant Zlib.Text_Array (1 .. 0) := [];
         One_Path     : constant Zlib.Text_Array :=
           [1 => US.To_Unbounded_String (First_Path)];
         One_Name     : constant Zlib.Text_Array :=
           [1 => US.To_Unbounded_String ("payload.txt")];
         Input_Paths  : constant Zlib.Text_Array :=
           [US.To_Unbounded_String (First_Path),
            US.To_Unbounded_String (Second_Path)];
         Duplicate_Names : constant Zlib.Text_Array :=
           [US.To_Unbounded_String ("same.txt"),
            US.To_Unbounded_String ("same.txt")];
         Two_Names    : constant Zlib.Text_Array :=
           [US.To_Unbounded_String ("one.txt"),
            US.To_Unbounded_String ("two.txt")];
         Missing_Paths : constant Zlib.Text_Array :=
           [US.To_Unbounded_String (Missing_Path),
            US.To_Unbounded_String (Missing_Path)];
         Invalid_Names : constant Zlib.Text_Array :=
           [US.To_Unbounded_String ("first.txt"),
            US.To_Unbounded_String ("")];
         Status       : Zlib.Status_Code := Zlib.Ok;
      begin
         Delete_If_Exists (First_Path);
         Delete_If_Exists (Second_Path);
         Delete_If_Exists (Missing_Path);
         Delete_If_Exists (Archive_Path);

         Write_File (First_Path, First_Data);
         Write_File (Second_Path, Second_Data);

         Writer.all (Input_Paths, Archive_Path, Duplicate_Names, Status);
         Assert
           (Status = Zlib.Unsupported_Method,
            Label & " 7z file-list rejects duplicate entry names");
         Assert
           (not Ada.Directories.Exists (Archive_Path),
            Label & " duplicate-name creation does not leave an archive");

         Writer.all (Empty_Paths, Archive_Path, Empty_Names, Status);
         Assert
           (Status = Zlib.Unsupported_Method,
            Label & " 7z file-list rejects null arrays");
         Assert
           (not Ada.Directories.Exists (Archive_Path),
            Label & " null-array creation does not leave an archive");

         Writer.all (One_Path, Archive_Path, Two_Names, Status);
         Assert
           (Status = Zlib.Unsupported_Method,
            Label & " 7z file-list rejects mismatched arrays");
         Assert
           (not Ada.Directories.Exists (Archive_Path),
            Label & " mismatched-array creation does not leave an archive");

         Ada.Directories.Create_Path (Archive_Path);
         Write_File (Marker_Path, Marker_Data);

         Writer.all (One_Path, Archive_Path, One_Name, Status);
         Assert
           (Status = Zlib.Output_File_Error,
            Label & " 7z file-list rejects directory output path");
         Assert
           (Ada.Directories.Kind (Archive_Path) = Ada.Directories.Directory,
            Label & " directory output path remains a directory");
         Assert
           (Read_File (Marker_Path) = Marker_Data,
            Label & " directory output path marker is not overwritten");

         Delete_If_Exists (Archive_Path);

         Writer.all (Missing_Paths, Archive_Path, Invalid_Names, Status);
         Assert
           (Status = Zlib.Unsupported_Method,
            Label & " 7z file-list validates names before reading");
         Assert
           (not Ada.Directories.Exists (Archive_Path),
            Label & " prevalidation failure does not leave an archive");

         Writer.all (Missing_Paths, Archive_Path, Two_Names, Status);
         Assert
           (Status = Zlib.Input_File_Error,
            Label & " 7z file-list preflights missing input files");
         Assert
           (not Ada.Directories.Exists (Archive_Path),
            Label & " missing input preflight does not leave an archive");

         Delete_If_Exists (First_Path);
         Delete_If_Exists (Second_Path);
         Delete_If_Exists (Missing_Path);
         Delete_If_Exists (Archive_Path);
      exception
         when others =>
            Delete_If_Exists (First_Path);
            Delete_If_Exists (Second_Path);
            Delete_If_Exists (Missing_Path);
            Delete_If_Exists (Archive_Path);
            raise;
      end Check_Writer;
   begin
      Check_Writer (Zlib.Seven_Zip_BZip2_Files'Access, "BZip2", "bzip2");
      Check_Writer (Zlib.Seven_Zip_LZMA_Files'Access, "LZMA", "lzma");
      Check_Writer (Zlib.Seven_Zip_LZMA2_Files'Access, "LZMA2", "lzma2");
      Check_Writer (Zlib.Seven_Zip_PPMd_Files'Access, "PPMd", "ppmd");
   end Test_Compressed_File_List_Rejects_Invalid_Inputs;

   procedure Test_Stored_Multiple_Files_Rejects_Directory_Output_Path
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input_Path   : constant String := Base_Path ("directory-output-input.bin");
      Archive_Path : constant String := Base_Path ("directory-output.7z");
      Marker_Path  : constant String :=
        Ada.Directories.Compose (Archive_Path, "marker.bin");
      Input_Data   : constant Zlib.Byte_Array := [16#61#, 16#72#, 16#63#];
      Marker_Data  : constant Zlib.Byte_Array := [16#6D#, 16#61#, 16#72#, 16#6B#];
      Input_Paths  : constant Zlib.Text_Array :=
        [1 => US.To_Unbounded_String (Input_Path)];
      Entry_Names  : constant Zlib.Text_Array :=
        [1 => US.To_Unbounded_String ("payload.txt")];
      Status       : Zlib.Status_Code := Zlib.Ok;
   begin
      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Archive_Path);

      Write_File (Input_Path, Input_Data);
      Ada.Directories.Create_Path (Archive_Path);
      Write_File (Marker_Path, Marker_Data);

      Zlib.Seven_Zip_Stored_Files
        (Input_Paths, Archive_Path, Entry_Names, Status);
      Assert
        (Status = Zlib.Output_File_Error,
         "multi-file stored 7z creation rejects directory output path");
      Assert
        (Ada.Directories.Kind (Archive_Path) = Ada.Directories.Directory,
         "directory output path remains a directory");
      Assert
        (Read_File (Marker_Path) = Marker_Data,
         "directory output path marker is not overwritten");

      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Archive_Path);
   exception
      when others =>
         Delete_If_Exists (Input_Path);
         Delete_If_Exists (Archive_Path);
         raise;
   end Test_Stored_Multiple_Files_Rejects_Directory_Output_Path;

   procedure Test_Stored_Multiple_Files_Prevalidates_Input_Names
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Missing_Path : constant String := Base_Path ("prevalidate-missing.bin");
      Archive_Path : constant String := Base_Path ("prevalidate-input.7z");
      Input_Paths  : constant Zlib.Text_Array :=
        [US.To_Unbounded_String (Missing_Path),
         US.To_Unbounded_String (Missing_Path)];
      Entry_Names  : constant Zlib.Text_Array :=
        [US.To_Unbounded_String ("first.txt"),
         US.To_Unbounded_String ("")];
      Status       : Zlib.Status_Code := Zlib.Ok;
   begin
      Delete_If_Exists (Missing_Path);
      Delete_If_Exists (Archive_Path);

      Zlib.Seven_Zip_Stored_Files
        (Input_Paths, Archive_Path, Entry_Names, Status);
      Assert
        (Status = Zlib.Unsupported_Method,
         "multi-file stored 7z creation validates all names before reading");
      Assert
        (not Ada.Directories.Exists (Archive_Path),
         "prevalidation failure does not leave an archive");

      declare
         Valid_Names : constant Zlib.Text_Array :=
           [US.To_Unbounded_String ("first.txt"),
            US.To_Unbounded_String ("second.txt")];
      begin
         Zlib.Seven_Zip_Stored_Files
           (Input_Paths, Archive_Path, Valid_Names, Status);
         Assert
           (Status = Zlib.Input_File_Error,
            "multi-file stored 7z creation preflights missing input files");
         Assert
           (not Ada.Directories.Exists (Archive_Path),
            "missing input preflight does not leave an archive");
      end;

      Delete_If_Exists (Missing_Path);
      Delete_If_Exists (Archive_Path);
   exception
      when others =>
         Delete_If_Exists (Missing_Path);
         Delete_If_Exists (Archive_Path);
         raise;
   end Test_Stored_Multiple_Files_Prevalidates_Input_Names;

   procedure Test_Stored_Extract_Rejects_Duplicate_Names
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      First_Path   : constant String := Base_Path ("ambiguous-first.bin");
      Second_Path  : constant String := Base_Path ("ambiguous-second.bin");
      Archive_Path : constant String := Base_Path ("ambiguous.7z");
      First_Data   : constant Zlib.Byte_Array := [16#41#];
      Second_Data  : constant Zlib.Byte_Array := [16#42#];
      Input_Paths  : constant Zlib.Text_Array :=
        [US.To_Unbounded_String (First_Path),
         US.To_Unbounded_String (Second_Path)];
      Entry_Names  : constant Zlib.Text_Array :=
        [US.To_Unbounded_String ("same.txt"),
         US.To_Unbounded_String ("copy.txt")];
      Status       : Zlib.Status_Code := Zlib.Ok;
   begin
      Delete_If_Exists (First_Path);
      Delete_If_Exists (Second_Path);
      Delete_If_Exists (Archive_Path);

      Write_File (First_Path, First_Data);
      Write_File (Second_Path, Second_Data);
      Zlib.Seven_Zip_Stored_Files
        (Input_Paths, Archive_Path, Entry_Names, Status);
      Assert (Status = Zlib.Ok, "ambiguous-name fixture creation status");

      declare
         Archive      : Zlib.Byte_Array := Read_File (Archive_Path);
         Payload_Size : constant Natural := First_Data'Length + Second_Data'Length;
         Header_First : constant Natural := 33 + Payload_Size;
         Header_Last  : constant Natural := Archive'Last;
         Patched      : Boolean := False;
         From_Name    : constant String := "copy.txt";
         To_Name      : constant String := "same.txt";
      begin
         for Pos in Header_First .. Header_Last - 2 * From_Name'Length + 1 loop
            declare
               Match : Boolean := True;
            begin
               for Offset in 0 .. From_Name'Length - 1 loop
                  if Archive (Pos + 2 * Offset) /=
                       Zlib.Byte
                         (Character'Pos
                            (From_Name (From_Name'First + Offset)))
                    or else Archive (Pos + 2 * Offset + 1) /= 0
                  then
                     Match := False;
                     exit;
                  end if;
               end loop;

               if Match then
                  for Offset in 0 .. To_Name'Length - 1 loop
                     Archive (Pos + 2 * Offset) :=
                       Zlib.Byte
                         (Character'Pos (To_Name (To_Name'First + Offset)));
                     Archive (Pos + 2 * Offset + 1) := 0;
                  end loop;
                  Patched := True;
                  exit;
               end if;
            end;
         end loop;

         Assert (Patched, "ambiguous-name fixture was patched");
         Set_U32_LE
           (Archive, 29, Zlib.CRC32 (Archive (Header_First .. Header_Last)));
         Set_U32_LE (Archive, 9, Zlib.CRC32 (Archive (13 .. 32)));

         declare
            Plain : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip_Stored (Archive, "same.txt", Status);
         begin
            Assert
              (Status = Zlib.Unsupported_Method,
               "stored 7z extraction rejects duplicate entry names");
            Assert (Plain'Length = 0, "ambiguous-name extraction returns no data");
         end;
      end;

      Delete_If_Exists (First_Path);
      Delete_If_Exists (Second_Path);
      Delete_If_Exists (Archive_Path);
   exception
      when others =>
         Delete_If_Exists (First_Path);
         Delete_If_Exists (Second_Path);
         Delete_If_Exists (Archive_Path);
         raise;
   end Test_Stored_Extract_Rejects_Duplicate_Names;

   procedure Test_AES_Encrypt_Decrypt_Roundtrip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Data   : Zlib.Byte_Array (1 .. 200);
      Status : Zlib.Status_Code := Zlib.Unsupported_Method;
   begin
      for I in Data'Range loop
         Data (I) := Zlib.Byte ((I * 7 + 3) mod 256);
      end loop;
      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_LZMA_Encrypted
             (Data, "secret.bin", "pa55word", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "AES-256 7z encryption: " & Zlib.Status_Image (Status));
         declare
            Out_Status : Zlib.Status_Code := Zlib.Unsupported_Method;
            Decoded    : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip
                (Archive, "secret.bin", "pa55word", Out_Status);
         begin
            Assert
              (Out_Status = Zlib.Ok and then Decoded = Data,
               "AES-256 7z round-trips with the correct password");
         end;
         declare
            Bad_Status : Zlib.Status_Code := Zlib.Ok;
            Bad        : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip
                (Archive, "secret.bin", "wrong-password", Bad_Status);
         begin
            Assert
              (Bad_Status /= Zlib.Ok or else Bad /= Data,
               "AES-256 7z rejects a wrong password");
         end;
      end;
   end Test_AES_Encrypt_Decrypt_Roundtrip;

   procedure Test_AES_Encrypted_Header_Roundtrip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Data   : Zlib.Byte_Array (1 .. 300);
      Status : Zlib.Status_Code := Zlib.Unsupported_Method;
   begin
      for I in Data'Range loop
         Data (I) := Zlib.Byte ((I * 11 + 5) mod 256);
      end loop;
      declare
         Inner : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_LZMA_Encrypted
             (Data, "hidden.bin", "hdr-pw-9", Status);
      begin
         Assert (Status = Zlib.Ok, "encrypted data archive built");
         declare
            HStatus : Zlib.Status_Code := Zlib.Unsupported_Method;
            MHE     : constant Zlib.Byte_Array :=
              Zlib.Encrypt_Seven_Zip_Header (Inner, "hdr-pw-9", HStatus);
         begin
            Assert (HStatus = Zlib.Ok, "header encryption (mhe) applied");
            declare
               OStatus : Zlib.Status_Code := Zlib.Unsupported_Method;
               Out_B   : constant Zlib.Byte_Array :=
                 Zlib.Extract_Seven_Zip
                   (MHE, "hidden.bin", "hdr-pw-9", OStatus);
            begin
               Assert
                 (OStatus = Zlib.Ok and then Out_B = Data,
                  "mhe archive round-trips header + data with the password");
            end;
         end;
      end;
   end Test_AES_Encrypted_Header_Roundtrip;

   procedure Test_BCJ2_Encode_Decode_Roundtrip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Data   : Zlib.Byte_Array (1 .. 600);
      Status : Zlib.Status_Code := Zlib.Unsupported_Method;
   begin
      --  Synthetic x86-ish bytes with E8/E9 branch opcodes and 4-byte
      --  displacements so the BCJ2 conversion path is exercised.
      for I in Data'Range loop
         Data (I) := Zlib.Byte ((I * 13 + 7) mod 256);
      end loop;
      for K in 0 .. 9 loop
         Data (1 + K * 50) := 16#E8#;
         Data (2 + K * 50) := 16#10#;
         Data (3 + K * 50) := 16#00#;
         Data (4 + K * 50) := 16#00#;
         Data (5 + K * 50) := 16#00#;
         Data (11 + K * 50) := 16#E9#;
         Data (12 + K * 50) := 16#FF#;
         Data (13 + K * 50) := 16#FF#;
         Data (14 + K * 50) := 16#FF#;
         Data (15 + K * 50) := 16#FF#;
      end loop;
      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_BCJ2 (Data, "code.bin", Status);
      begin
         Assert (Status = Zlib.Ok, "BCJ2 archive built");
         declare
            OStatus : Zlib.Status_Code := Zlib.Unsupported_Method;
            Out_B   : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip (Archive, "code.bin", OStatus);
         begin
            Assert
              (OStatus = Zlib.Ok and then Out_B = Data,
               "BCJ2 round-trips through Extract_Seven_Zip");
         end;
      end;
   end Test_BCJ2_Encode_Decode_Roundtrip;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_AES_Encrypt_Decrypt_Roundtrip'Access,
         "native 7z AES-256 encrypt/decrypt round-trip");
      Register_Routine
        (T, Test_AES_Encrypted_Header_Roundtrip'Access,
         "native 7z AES-256 encrypted-header (mhe) round-trip");
      Register_Routine
        (T, Test_BCJ2_Encode_Decode_Roundtrip'Access,
         "native 7z BCJ2 encode/decode round-trip");
      Register_Routine
        (T, Test_Stored_Header_Structure'Access,
         "native stored 7z header structure and CRCs");
      Register_Routine
        (T, Test_Extract_Accepts_Known_Encoded_Header_Coders'Access,
         "native 7z extraction accepts known encoded header coders");
      Register_Routine
        (T, Test_Extract_Rejects_Bad_Encoded_Header_CRC'Access,
         "native 7z extraction rejects bad encoded header CRCs");
      Register_Routine
        (T, Test_Invalid_Name_Fails'Access,
         "native stored 7z rejects invalid entry names");
      --  native single-entry 7z validates stored, Deflate, BZip2, LZMA, and
      --  LZMA2 in process
      Register_Routine
        (T, Test_Stored_Roundtrip_Native'Access,
         "native stored 7z extracts its own Copy-coder archives");
      Register_Routine
        (T, Test_Deflate_Roundtrip_Native'Access,
         "native Deflate 7z extracts its own Deflate archives");
      Register_Routine
        (T, Test_Deflate_Level_Roundtrip_Native'Access,
         "native Deflate 7z accepts compression levels");
      Register_Routine
        (T, Test_BZip2_Roundtrip_Native'Access,
         "native BZip2 7z extracts its own BZip2 archives");
      Register_Routine
        (T, Test_LZMA_Roundtrip_Native'Access,
         "native LZMA 7z extracts its own LZMA archives");
      Register_Routine
        (T, Test_LZMA_Extracts_Non_Default_Dictionary_Metadata'Access,
         "native LZMA 7z accepts non-default dictionary metadata");
      Register_Routine
        (T, Test_LZMA2_Roundtrip_Native'Access,
         "native LZMA2 7z extracts its own LZMA2 archives");
      Register_Routine
        (T, Test_LZMA2_Compressed_Chunks_Native'Access,
         "native LZMA2 7z emits and extracts compressed LZMA2 chunks");
      Register_Routine
        (T, Test_Stored_Empty_Payload_Roundtrip_Native'Access,
         "native stored 7z roundtrips empty payloads");
      Register_Routine
        (T, Test_Stored_Non_One_Based_Input_Roundtrip_Native'Access,
         "native stored 7z handles non-1-based byte arrays");
      Register_Routine
        (T, Test_Stored_Multibyte_Number_Roundtrip_Native'Access,
         "native stored 7z handles multi-byte encoded sizes");
      Register_Routine
        (T, Test_Stored_Extract_Wrong_Name_Fails'Access,
         "native stored 7z extraction rejects wrong entry names");
      Register_Routine
        (T, Test_Stored_Extract_NUL_Name_Fails'Access,
         "native stored 7z extraction rejects NUL entry names");
      Register_Routine
        (T, Test_Stored_Extract_Bad_CRC_Fails'Access,
         "native stored 7z extraction rejects payload CRC mismatches");
      Register_Routine
        (T, Test_Deflate_Extract_Corrupt_Payload_Fails'Access,
         "native Deflate 7z extraction rejects corrupt compressed payloads");
      Register_Routine
        (T, Test_Deflate_Extract_Rejects_Trailing_Packed_Bytes'Access,
         "native Deflate 7z extraction rejects trailing packed bytes");
      Register_Routine
        (T, Test_Deflate_Extract_Bad_Unpack_CRC_Fails'Access,
         "native Deflate 7z extraction rejects bad unpack CRCs");
      Register_Routine
        (T, Test_Deflate_Extract_Bad_Unpack_Size_Fails'Access,
         "native Deflate 7z extraction rejects bad unpack sizes");
      Register_Routine
        (T, Test_BZip2_Extract_Rejects_Trailing_Packed_Bytes'Access,
         "native BZip2 7z extraction rejects trailing packed bytes");
      Register_Routine
        (T, Test_Compressed_Extract_Bad_Pack_CRC_Fails'Access,
         "native BZip2/LZMA/LZMA2 7z extraction rejects bad packed CRCs");
      Register_Routine
        (T, Test_Compressed_Extract_Corrupt_Payload_Fails'Access,
         "native BZip2/LZMA2 7z extraction rejects corrupt payloads");
      Register_Routine
        (T, Test_Compressed_Extract_Bad_Unpack_CRC_Fails'Access,
         "native BZip2/LZMA/LZMA2 7z extraction rejects bad unpack CRCs");
      Register_Routine
        (T, Test_Compressed_Extract_Bad_Unpack_Size_Fails'Access,
         "native BZip2/LZMA/LZMA2 7z extraction rejects bad unpack sizes");
      Register_Routine
        (T, Test_Stored_Extract_Bad_Start_Header_CRC_Fails'Access,
         "native stored 7z extraction rejects start-header CRC mismatches");
      Register_Routine
        (T, Test_Stored_Extract_Bad_Next_Header_CRC_Fails'Access,
         "native stored 7z extraction rejects next-header CRC mismatches");
      Register_Routine
        (T, Test_Extract_Accepts_Optional_CRC_Sections_Omitted'Access,
         "native 7z extraction accepts omitted optional CRC sections");
      Register_Routine
        (T, Test_Extract_Accepts_Archive_And_File_Metadata'Access,
         "native 7z extraction accepts archive and file metadata");
      Register_Routine
        (T, Test_Stored_Creation_Emits_Metadata'Access,
         "native stored 7z creation emits file metadata");
      Register_Routine
        (T, Test_Stored_Creation_Emits_Directory_Entry'Access,
         "native stored 7z creation emits directory entries");
      Register_Routine
        (T, Test_Compressed_Creation_Emits_Metadata'Access,
         "native compressed 7z creation emits file metadata");
      Register_Routine
        (T, Test_Compressed_Creation_Emits_Directory_Entries'Access,
         "native compressed 7z creation emits directory entries");
      Register_Routine
        (T, Test_File_Creation_Preserves_Source_Metadata'Access,
         "native 7z file creation preserves source metadata");
      Register_Routine
        (T, Test_File_List_Creation_Preserves_Source_Metadata'Access,
         "native 7z file-list creation preserves source metadata");
      Register_Routine
        (T, Test_Extract_Accepts_SFX_Prefixed_Archive'Access,
         "native 7z extraction accepts SFX-prefixed archives");
      Register_Routine
        (T, Test_Extract_Accepts_Directory_Entries'Access,
         "native 7z extraction accepts directory entries");
      Register_Routine
        (T, Test_Extract_Accepts_Solid_Copy_Substreams'Access,
         "native 7z extraction accepts solid Copy substreams");
      Register_Routine
        (T, Test_Extract_Accepts_Solid_Deflate_Substreams'Access,
         "native 7z extraction accepts solid Deflate substreams");
      Register_Routine
        (T, Test_Extract_Accepts_Solid_BZip2_Substreams'Access,
         "native 7z extraction accepts solid BZip2 substreams");
      Register_Routine
        (T, Test_Extract_Accepts_Solid_LZMA_Substreams'Access,
         "native 7z extraction accepts solid LZMA substreams");
      Register_Routine
        (T, Test_Extract_Accepts_Solid_LZMA2_Substreams'Access,
         "native 7z extraction accepts solid LZMA2 substreams");
      Register_Routine
        (T, Test_Extract_Accepts_Solid_Delta_Substreams'Access,
         "native 7z extraction accepts solid Delta substreams");
      Register_Routine
        (T, Test_Extract_Accepts_Delta_Deflate_Filter_Chain'Access,
         "native 7z extraction accepts Delta+Deflate filter chains");
      Register_Routine
        (T, Test_Extract_Accepts_BCJ_Delta_Deflate_Filter_Chain'Access,
         "native 7z extraction accepts BCJ+Delta+Deflate filter chains");
      Register_Routine
        (T, Test_Extract_Accepts_Reordered_Linear_Bind_Pairs'Access,
         "native 7z extraction accepts reordered linear bind pairs");
      Register_Routine
        (T, Test_Extract_Accepts_Reordered_Legacy_Bind_Pairs'Access,
         "native 7z extraction accepts reordered legacy bind pairs");
      Register_Routine
        (T, Test_Extract_Accepts_Copy_Deflate_Filter_Chain'Access,
         "native 7z extraction accepts Copy+Deflate filter chains");
      Register_Routine
        (T, Test_Extract_Accepts_Standard_Copy_Deflate_Bind_Pair'Access,
         "native 7z extraction accepts standard Copy+Deflate bind pairs");
      Register_Routine
        (T, Test_Extract_Accepts_Reverse_BCJ_Copy_Bind_Pair'Access,
         "native 7z extraction accepts reverse BCJ+Copy bind pairs");
      Register_Routine
        (T, Test_Extract_Accepts_Solid_PPMd_Substreams'Access,
         "native 7z extraction accepts solid PPMd substreams");
      Register_Routine
        (T, Test_Extract_Accepts_BCJ_Copy_Filter_Chain'Access,
         "native 7z extraction accepts BCJ+Copy filter chains");
      Register_Routine
        (T, Test_Extract_Accepts_BCJ2_Copy_Filter_Graph'Access,
         "native 7z extraction accepts BCJ2+Copy filter graphs");
      Register_Routine
        (T, Test_Extract_Accepts_BCJ2_Main_Pre_Coder_Graphs'Access,
         "native 7z extraction accepts BCJ2 main pre-coder filter graphs");
      Register_Routine
        (T, Test_Extract_Accepts_Broader_PPMd_Stream'Access,
         "native 7z extraction accepts broader PPMd streams");
      Register_Routine
        (T, Test_Extract_Accepts_Broader_PPMd_Dash_Entry'Access,
         "native 7z extraction accepts broader PPMd dash entries");
      Register_Routine
        (T, Test_Extract_Rejects_Malformed_PPMd_Properties'Access,
         "native 7z extraction rejects malformed PPMd properties");
      Register_Routine
        (T, Test_Extract_Rejects_Malformed_PPMd_Range_Header'Access,
         "native 7z extraction rejects malformed PPMd range headers");
      Register_Routine
        (T, Test_Extract_Recognizes_Valid_PPMd_Range_Header'Access,
         "native 7z extraction recognizes valid PPMd range headers");
      Register_Routine
        (T, Test_Extract_Accepts_Empty_PPMd_Stream'Access,
         "native 7z extraction accepts empty PPMd streams");
      Register_Routine
        (T, Test_Extract_Accepts_Empty_PPMd_Range_Header'Access,
         "native 7z extraction accepts empty PPMd streams with range headers");
      Register_Routine
        (T, Test_Extract_Accepts_Repeated_PPMd_Stream'Access,
         "native 7z extraction accepts repeated PPMd streams");
      Register_Routine
        (T, Test_Extract_Accepts_Short_Repeated_PPMd_Stream'Access,
         "native 7z extraction accepts short repeated PPMd streams");
      Register_Routine
        (T, Test_Extract_Accepts_Long_Repeated_PPMd_Stream'Access,
         "native 7z extraction accepts long repeated PPMd streams");
      Register_Routine
        (T, Test_Extract_Accepts_Over_Boundary_Repeated_PPMd_Stream'Access,
         "native 7z extraction accepts over-boundary repeated PPMd streams");
      Register_Routine
        (T, Test_Extract_Accepts_Alternating_PPMd_Stream'Access,
         "native 7z extraction accepts alternating PPMd streams");
      Register_Routine
        (T, Test_Extract_Accepts_Periodic_PPMd_Streams'Access,
         "native 7z extraction accepts periodic PPMd streams");
      Register_Routine
        (T, Test_Extract_Rejects_Periodic_PPMd_Bad_Unpack_CRC'Access,
         "native 7z extraction rejects periodic PPMd bad unpack CRCs");
      Register_Routine
        (T, Test_Extract_Accepts_Two_Symbol_PPMd_Stream'Access,
         "native 7z extraction accepts two-symbol PPMd streams");
      Register_Routine
        (T, Test_Extract_Accepts_Three_Symbol_PPMd_Stream'Access,
         "native 7z extraction accepts three-symbol PPMd streams");
      Register_Routine
        (T, Test_Extract_Accepts_Six_Symbol_PPMd_Stream'Access,
         "native 7z extraction accepts six-symbol PPMd streams");
      Register_Routine
        (T, Test_Extract_Accepts_Ten_Symbol_PPMd_Stream'Access,
         "native 7z extraction accepts ten-symbol PPMd streams");
      Register_Routine
        (T, Test_Extract_Accepts_Eleven_Symbol_PPMd_Stream'Access,
         "native 7z extraction accepts eleven-symbol PPMd streams");
      Register_Routine
        (T, Test_Stored_Extract_Rejects_Overflowing_Next_Header_Offset'Access,
         "native stored 7z extraction rejects overflowing next-header offsets");
      Register_Routine
        (T, Test_Stored_Extract_Rejects_Short_CRC_Tables'Access,
         "native stored 7z extraction rejects short CRC tables");
      Register_Routine
        (T, Test_Stored_Extract_Unsupported_Method_Fails'Access,
         "native stored 7z extraction rejects unsupported methods");
      Register_Routine
        (T, Test_Stored_Extract_Truncated_Archive_Fails'Access,
         "native stored 7z extraction rejects truncated archives");
      Register_Routine
        (T, Test_Stored_Extract_Trailing_Garbage_Fails'Access,
         "native stored 7z extraction rejects trailing garbage");
      Register_Routine
        (T, Test_Stored_Extract_Missing_Header_Sections_Fails'Access,
         "native stored 7z extraction rejects missing header sections");
      Register_Routine
        (T, Test_Stored_Extract_Rejects_Pack_Size_Overflow'Access,
         "native stored 7z extraction rejects pack-size overflow");
      Register_Routine
        (T, Test_Stored_Extract_Rejects_Impossible_Stream_Count'Access,
         "native stored 7z extraction rejects impossible stream counts");
      Register_Routine
        (T, Test_Stored_Extract_Rejects_Header_Count_Mismatches'Access,
         "native stored 7z extraction rejects header count mismatches");
      Register_Routine
        (T, Test_Stored_Extract_Rejects_Malformed_Name_Field'Access,
         "native stored 7z extraction rejects malformed name fields");
      Register_Routine
        (T, Test_LZMA_Extract_Rejects_Invalid_Properties'Access,
         "native LZMA 7z extraction rejects invalid coder properties");
      Register_Routine
        (T, Test_LZMA_Extract_Rejects_Trailing_Packed_Bytes'Access,
         "native LZMA 7z extraction rejects trailing packed bytes");
      Register_Routine
        (T, Test_LZMA2_Extract_Rejects_Malformed_Properties'Access,
         "native LZMA2 7z extraction rejects malformed coder properties");
      Register_Routine
        (T, Test_LZMA2_Extract_Rejects_Trailing_Packed_Bytes'Access,
         "native LZMA2 7z extraction rejects trailing packed bytes");
      Register_Routine
        (T, Test_Stored_File_Roundtrip_Native'Access,
         "native stored 7z file helpers roundtrip");
      Register_Routine
        (T, Test_Deflate_File_Roundtrip_Native'Access,
         "native Deflate 7z file helpers roundtrip");
      Register_Routine
        (T, Test_BZip2_File_Roundtrip_Native'Access,
         "native BZip2 7z file helpers roundtrip");
      Register_Routine
        (T, Test_LZMA2_File_Roundtrip_Native'Access,
         "native LZMA2 7z file helpers roundtrip");
      Register_Routine
        (T, Test_LZMA_File_Roundtrip_Native'Access,
         "native LZMA 7z file helpers roundtrip");
      Register_Routine
        (T, Test_PPMd_File_Extraction_Native'Access,
         "native PPMd 7z file helper extracts supported streams");
      Register_Routine
        (T, Test_PPMd_File_Extraction_Accepts_Eleven_Symbol_Stream'Access,
         "native PPMd 7z file helper extracts eleven-symbol streams");
      Register_Routine
        (T, Test_PPMd_File_Extraction_Accepts_Periodic_Stream'Access,
         "native PPMd 7z file helper extracts periodic streams");
      Register_Routine
        (T, Test_PPMd_File_List_Extraction_Native'Access,
         "native PPMd 7z file-list helper extracts supported streams");
      Register_Routine
        (T, Test_PPMd_File_List_Extraction_Accepts_Eleven_Symbol_Stream'Access,
         "native PPMd 7z file-list helper extracts eleven-symbol streams");
      Register_Routine
        (T, Test_PPMd_File_List_Extraction_Accepts_Periodic_Stream'Access,
         "native PPMd 7z file-list helper extracts periodic streams");
      Register_Routine
        (T, Test_PPMd_File_Helpers_Reject_Periodic_Bad_Unpack_CRC'Access,
         "native PPMd 7z file helpers reject periodic bad unpack CRCs");
      Register_Routine
        (T, Test_PPMd_File_Helpers_Reject_Malformed_Properties'Access,
         "native PPMd 7z file helpers reject malformed properties");
      Register_Routine
        (T, Test_PPMd_Creation_Rejects_Bad_Unpack_CRC'Access,
         "native PPMd 7z one-shot helper rejects bad unpack CRCs");
      Register_Routine
        (T, Test_PPMd_Creation_Emits_Default_Properties'Access,
         "native PPMd 7z one-shot helper emits default properties");
      Register_Routine
        (T, Test_PPMd_One_Shot_Creation_Native_Roundtrip'Access,
         "native PPMd 7z one-shot helper roundtrips");
      Register_Routine
        (T, Test_PPMd_File_Creation_Native_Roundtrip'Access,
         "native PPMd 7z file helper roundtrips");
      Register_Routine
        (T, Test_Deflate_Level_File_Roundtrip_Native'Access,
         "native Deflate level 7z file helpers roundtrip");
      Register_Routine
        (T, Test_File_Extraction_Creates_Parent_Directories'Access,
         "native 7z single-entry extraction creates parent directories");
      Register_Routine
        (T, Test_Compressed_File_Extraction_Rejects_Directory_Output'Access,
         "native compressed 7z file extraction rejects directory output path");
      Register_Routine
        (T, Test_Compressed_File_Creation_Rejects_Directory_Output'Access,
         "native compressed 7z file creation rejects directory output path");
      Register_Routine
        (T, Test_File_Creation_Prevalidates_Output_Paths'Access,
         "native 7z file creation prevalidates output paths");
      Register_Routine
        (T, Test_File_Creation_Prevalidates_Entry_Names'Access,
         "native 7z file creation prevalidates entry names");
      Register_Routine
        (T, Test_PPMd_Basename_File_Prevalidates_Paths'Access,
         "native PPMd 7z basename file helper prevalidates paths");
      Register_Routine
        (T, Test_File_Extraction_Prevalidates_Output_Paths'Access,
         "native 7z file extraction prevalidates output paths");
      Register_Routine
        (T, Test_File_Extraction_Prevalidates_Entry_Names'Access,
         "native 7z file extraction prevalidates entry names");
      Register_Routine
        (T, Test_Stored_Multiple_Files_Roundtrip_Native'Access,
         "native stored 7z file-list helper writes multiple entries");
      Register_Routine
        (T, Test_Deflate_Multiple_Files_Roundtrip_Native'Access,
         "native Deflate 7z file-list helper writes multiple entries");
      Register_Routine
        (T, Test_BZip2_Multiple_Files_Roundtrip_Native'Access,
         "native BZip2 7z file-list helper writes multiple entries");
      Register_Routine
        (T, Test_LZMA_Multiple_Files_Roundtrip_Native'Access,
         "native LZMA 7z file-list helper writes multiple entries");
      Register_Routine
        (T, Test_LZMA2_Multiple_Files_Roundtrip_Native'Access,
         "native LZMA2 7z file-list helper writes multiple entries");
      Register_Routine
        (T, Test_PPMd_Multiple_Files_Roundtrip_Native'Access,
         "native PPMd 7z file-list helper writes multiple entries");
      Register_Routine
        (T, Test_File_List_Writers_Emit_Directory_Entries'Access,
         "native 7z file-list helpers emit directory entries");
      Register_Routine
        (T, Test_File_Writers_Emit_Directory_Entries'Access,
         "native 7z file helpers emit directory entries");
      Register_Routine
        (T, Test_File_List_Writers_Emit_All_Directory_Archives'Access,
         "native 7z file-list helpers emit all-directory archives");
      Register_Routine
        (T, Test_Directory_Creation_Preserves_Source_Metadata'Access,
         "native 7z directory creation preserves source metadata");
      Register_Routine
        (T, Test_Stored_Multiple_Files_Extract_To_Directory'Access,
         "native stored 7z file-list helper extracts selected entries");
      Register_Routine
        (T, Test_Stored_Multiple_Files_Empty_Entry_Roundtrip'Access,
         "native stored 7z file-list helper roundtrips empty entries");
      Register_Routine
        (T, Test_Compressed_Multiple_Files_Empty_Entry_Roundtrip'Access,
         "native compressed 7z file-list helper roundtrips empty entries");
      Register_Routine
        (T, Test_Compressed_File_List_Extraction_Prevalidates'Access,
         "native compressed 7z file-list extraction prevalidates output names");
      Register_Routine
        (T, Test_Compressed_File_List_Extraction_Rejects_Output_Dirs'Access,
         "native compressed 7z file-list extraction rejects output dirs");
      Register_Routine
        (T, Test_Stored_Multiple_Files_Rejects_Unsafe_Output_Name'Access,
         "native stored 7z file-list extraction rejects unsafe paths");
      Register_Routine
        (T, Test_Stored_Multiple_Files_Prevalidates_Output_Names'Access,
         "native stored 7z file-list extraction prevalidates output names");
      Register_Routine
        (T, Test_Stored_Multiple_Files_Rejects_Duplicate_Output_Requests'Access,
         "native stored 7z file-list extraction rejects duplicate requests");
      Register_Routine
        (T, Test_Stored_Multiple_Files_Stages_Before_Writing'Access,
         "native stored 7z file-list extraction stages before writing");
      Register_Routine
        (T, Test_Stored_Multiple_Files_Preflights_Output_Paths'Access,
         "native stored 7z file-list extraction preflights output paths");
      Register_Routine
        (T, Test_Stored_Multiple_Files_Prevalidates_Output_Dir'Access,
         "native stored 7z file-list extraction prevalidates output dir");
      Register_Routine
        (T, Test_Stored_Multiple_Files_Rejects_File_Output_Dir'Access,
         "native stored 7z file-list extraction rejects file output dir");
      Register_Routine
        (T, Test_Stored_Multiple_Files_Rejects_Empty_Output_Dir'Access,
         "native stored 7z file-list extraction rejects empty output dir");
      Register_Routine
        (T, Test_Stored_Multiple_Files_Rejects_Duplicate_Names'Access,
         "native stored 7z file-list creation rejects duplicate names");
      Register_Routine
        (T, Test_Stored_File_List_Rejects_Invalid_Array_Shapes'Access,
         "native stored 7z file-list rejects invalid array shapes");
      Register_Routine
        (T, Test_Deflate_Level_File_List_Rejects_Invalid_Inputs'Access,
         "native level Deflate 7z file-list rejects invalid inputs");
      Register_Routine
        (T, Test_Deflate_Level_File_List_Rejects_Output_And_Prevalidates'Access,
         "native level Deflate 7z file-list rejects output and prevalidates");
      Register_Routine
        (T, Test_Compressed_File_List_Rejects_Invalid_Inputs'Access,
         "native BZip2/LZMA/LZMA2 7z file-list rejects invalid inputs");
      Register_Routine
        (T, Test_Stored_Multiple_Files_Rejects_Directory_Output_Path'Access,
         "native stored 7z file-list creation rejects directory output path");
      Register_Routine
        (T, Test_Stored_Multiple_Files_Prevalidates_Input_Names'Access,
         "native stored 7z file-list creation prevalidates entry names");
      Register_Routine
        (T, Test_Stored_Extract_Rejects_Duplicate_Names'Access,
         "native stored 7z extraction rejects duplicate names");
   end Register_Tests;

end Zlib_Seven_Zip_Tests;
