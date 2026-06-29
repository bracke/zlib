with Ada.Calendar;
with Ada.Containers.Vectors;
with Ada.Directories;
with Ada.Streams; use Ada.Streams;
with Ada.Streams.Stream_IO; use Ada.Streams.Stream_IO;
with Ada.Unchecked_Deallocation;
with Ada.Containers; use Ada.Containers;
with Interfaces.C;
with System.Address_To_Access_Conversions;
with GNAT.OS_Lib;

with Zlib.Checksums;
with Zlib.Bit_Writer;
with Zlib.Block_Chooser; use Zlib.Block_Chooser;
with Zlib.CRC32_Internal;
with Zlib.Fixed_Compress;
with Zlib.Deflate_Tables;
with Zlib.Huffman_Builder;
with Zlib.LZ77_Matcher;
with Zlib.Stream_Bits;
with Zlib.Stream_Inflate;
with Zlib.Sliding_Window;
with Zlib.Seven_Zip_Filters;
with Zlib.PPMd7;
with Zlib.Seven_Zip_AES;

package body Zlib is
   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned;
   use type Ada.Calendar.Time;
   use type Ada.Directories.File_Kind;
   use type System.Address;
   use type GNAT.OS_Lib.OS_Time;

   pragma Linker_Options ("-lbz2");
   pragma Linker_Options ("-lzstd");

   package SIO renames Ada.Streams.Stream_IO;
   package US renames Ada.Strings.Unbounded;

   --  Active 7z password for AES-encrypted folders, set by the password-aware
   --  Extract_Seven_Zip overload just before extraction (the deep extractor
   --  call chain makes threading a parameter impractical).
   Active_Seven_Zip_Password : US.Unbounded_String := US.Null_Unbounded_String;

   function BZ2_bzBuffToBuffCompress
     (Dest          : System.Address;
      Dest_Len      : access Interfaces.C.unsigned;
      Source        : System.Address;
      Source_Len    : Interfaces.C.unsigned;
      Block_Size    : Interfaces.C.int;
      Verbosity     : Interfaces.C.int;
      Work_Factor   : Interfaces.C.int) return Interfaces.C.int
     with Import, Convention => C, External_Name => "BZ2_bzBuffToBuffCompress";

   function BZ2_bzBuffToBuffDecompress
     (Dest        : System.Address;
      Dest_Len    : access Interfaces.C.unsigned;
      Source      : System.Address;
      Source_Len  : Interfaces.C.unsigned;
      Small       : Interfaces.C.int;
      Verbosity   : Interfaces.C.int) return Interfaces.C.int
     with Import, Convention => C, External_Name => "BZ2_bzBuffToBuffDecompress";

   type BZ_Stream is record
      Next_In        : System.Address := System.Null_Address;
      Avail_In       : Interfaces.C.unsigned := 0;
      Total_In_Lo32  : Interfaces.C.unsigned := 0;
      Total_In_Hi32  : Interfaces.C.unsigned := 0;
      Next_Out       : System.Address := System.Null_Address;
      Avail_Out      : Interfaces.C.unsigned := 0;
      Total_Out_Lo32 : Interfaces.C.unsigned := 0;
      Total_Out_Hi32 : Interfaces.C.unsigned := 0;
      State          : System.Address := System.Null_Address;
      BZAlloc        : System.Address := System.Null_Address;
      BZFree         : System.Address := System.Null_Address;
      Opaque         : System.Address := System.Null_Address;
   end record
     with Convention => C;

   function BZ2_bzDecompressInit
     (Strm      : access BZ_Stream;
      Verbosity : Interfaces.C.int;
      Small     : Interfaces.C.int) return Interfaces.C.int
     with Import, Convention => C, External_Name => "BZ2_bzDecompressInit";

   function BZ2_bzDecompress
     (Strm : access BZ_Stream) return Interfaces.C.int
     with Import, Convention => C, External_Name => "BZ2_bzDecompress";

   function BZ2_bzDecompressEnd
     (Strm : access BZ_Stream) return Interfaces.C.int
     with Import, Convention => C, External_Name => "BZ2_bzDecompressEnd";

   function ZSTD_compressBound
     (Src_Size : Interfaces.C.size_t) return Interfaces.C.size_t
     with Import, Convention => C, External_Name => "ZSTD_compressBound";

   function ZSTD_compress
     (Dst          : System.Address;
      Dst_Capacity : Interfaces.C.size_t;
      Src          : System.Address;
      Src_Size     : Interfaces.C.size_t;
      Level        : Interfaces.C.int) return Interfaces.C.size_t
     with Import, Convention => C, External_Name => "ZSTD_compress";

   function ZSTD_decompress
     (Dst             : System.Address;
      Dst_Capacity    : Interfaces.C.size_t;
      Src             : System.Address;
      Compressed_Size : Interfaces.C.size_t) return Interfaces.C.size_t
     with Import, Convention => C, External_Name => "ZSTD_decompress";

   function ZSTD_isError
     (Code : Interfaces.C.size_t) return Interfaces.C.unsigned
     with Import, Convention => C, External_Name => "ZSTD_isError";

   package Bit_Source_Addresses is new
     System.Address_To_Access_Conversions (Zlib.Stream_Bits.Bit_Source);

   package Window_Addresses is new
     System.Address_To_Access_Conversions (Zlib.Sliding_Window.Window);

   package Decoder_Addresses is new
     System.Address_To_Access_Conversions (Zlib.Stream_Inflate.Decoder);

   procedure Free is new
     Ada.Unchecked_Deallocation
       (Object => Zlib.Stream_Bits.Bit_Source,
        Name   => Bit_Source_Addresses.Object_Pointer);

   procedure Free is new
     Ada.Unchecked_Deallocation
       (Object => Zlib.Sliding_Window.Window,
        Name   => Window_Addresses.Object_Pointer);

   procedure Free is new
     Ada.Unchecked_Deallocation
       (Object => Zlib.Stream_Inflate.Decoder,
        Name   => Decoder_Addresses.Object_Pointer);

   function Contains_NUL (Text : String) return Boolean is
   begin
      for Ch of Text loop
         if Character'Pos (Ch) = 0 then
            return True;
         end if;
      end loop;
      return False;
   end Contains_NUL;

   function Adler32 (Input : Byte_Array) return Interfaces.Unsigned_32 is
   begin
      return Zlib.Checksums.Adler32 (Input);
   end Adler32;

   function CRC32 (Input : Byte_Array) return Interfaces.Unsigned_32 is
      State : CRC32_State;
   begin
      CRC32_Reset (State);

      for I in Input'Range loop
         CRC32_Update (State, Ada.Streams.Stream_Element (Input (I)));
      end loop;

      return CRC32_Value (State);
   end CRC32;

   procedure CRC32_Reset (State : out CRC32_State) is
   begin
      State.CRC := 16#FFFF_FFFF#;
   end CRC32_Reset;

   procedure CRC32_Update
     (State : in out CRC32_State;
      B     : Ada.Streams.Stream_Element)
   is
   begin
      Zlib.CRC32_Internal.Update_Raw (State.CRC, B);
   end CRC32_Update;

   procedure CRC32_Update
     (State : in out CRC32_State;
      Data  : Ada.Streams.Stream_Element_Array)
   is
   begin
      for I in Data'Range loop
         CRC32_Update (State, Data (I));
      end loop;
   end CRC32_Update;

   function CRC32_Value (State : CRC32_State) return Interfaces.Unsigned_32 is
   begin
      return State.CRC xor 16#FFFF_FFFF#;
   end CRC32_Value;

   function Looks_Like_Zlib_Header (Input : Byte_Array) return Boolean
     with SPARK_Mode => On
   is
      CMF   : Natural;
      FLG   : Natural;
      Value : Natural;
   begin
      if Input'Length < 2 then
         return False;
      end if;

      CMF := Natural (Input (Input'First));
      FLG := Natural (Input (Input'First + 1));

      if (CMF mod 16) /= 8 then
         return False;
      end if;

      if (CMF / 16) > 7 then
         return False;
      end if;

      Value := CMF * 256 + FLG;
      return (Value mod 31) = 0;
   end Looks_Like_Zlib_Header;

   function Looks_Like_GZip_Header (Input : Byte_Array) return Boolean
     with SPARK_Mode => On
   is
      ID1 : Byte;
      ID2 : Byte;
      CM  : Byte;
      FLG : Natural;
   begin
      if Input'Length < 4 then
         return False;
      end if;

      ID1 := Input (Input'First);
      ID2 := Input (Input'First + 1);
      CM  := Input (Input'First + 2);
      FLG := Natural (Input (Input'First + 3));

      return ID1 = 16#1F#
        and then ID2 = 16#8B#
        and then CM = 8
        and then FLG < 16#20#;
   end Looks_Like_GZip_Header;

   function No_GZip_Metadata return GZip_Metadata is
   begin
      return
        (Has_Name    => False,
         Has_Comment => False,
         Has_MTime   => False,
         Has_OS      => False,
         Has_XFL     => False,
         Has_Extra   => False,
         Header_CRC  => False,
         Name        => US.Null_Unbounded_String,
         Comment     => US.Null_Unbounded_String,
         Extra       => US.Null_Unbounded_String,
         MTime       => 0,
         OS          => 255,
         XFL         => 0,
         Valid       => True);
   end No_GZip_Metadata;

   procedure Set_Name (Metadata : in out GZip_Metadata; Name : String) is
   begin
      if Contains_NUL (Name) then
         Metadata.Valid := False;
         Metadata.Has_Name := False;
         Metadata.Name := US.Null_Unbounded_String;
      else
         Metadata.Has_Name := True;
         Metadata.Name := US.To_Unbounded_String (Name);
      end if;
   end Set_Name;

   procedure Set_Comment (Metadata : in out GZip_Metadata; Comment : String) is
   begin
      if Contains_NUL (Comment) then
         Metadata.Valid := False;
         Metadata.Has_Comment := False;
         Metadata.Comment := US.Null_Unbounded_String;
      else
         Metadata.Has_Comment := True;
         Metadata.Comment := US.To_Unbounded_String (Comment);
      end if;
   end Set_Comment;

   procedure Set_MTime
     (Metadata : in out GZip_Metadata; MTime : Interfaces.Unsigned_32) is
   begin
      Metadata.Has_MTime := True;
      Metadata.MTime := MTime;
   end Set_MTime;

   procedure Set_OS (Metadata : in out GZip_Metadata; OS : Byte) is
   begin
      Metadata.Has_OS := True;
      Metadata.OS := OS;
   end Set_OS;

   procedure Set_XFL (Metadata : in out GZip_Metadata; XFL : Byte) is
   begin
      Metadata.Has_XFL := True;
      Metadata.XFL := XFL;
   end Set_XFL;

   procedure Set_Extra (Metadata : in out GZip_Metadata; Extra : Byte_Array) is
      Encoded : US.Unbounded_String := US.Null_Unbounded_String;
   begin
      if Extra'Length > 65_535 then
         Metadata.Valid := False;
         Metadata.Has_Extra := False;
         Metadata.Extra := US.Null_Unbounded_String;
         return;
      end if;

      for B of Extra loop
         US.Append (Encoded, Character'Val (Integer (B)));
      end loop;

      Metadata.Has_Extra := True;
      Metadata.Extra := Encoded;
   end Set_Extra;

   procedure Set_Header_CRC
     (Metadata : in out GZip_Metadata; Enabled : Boolean) is
   begin
      Metadata.Header_CRC := Enabled;
   end Set_Header_CRC;

   function Stored_Raw_Deflate_Size
     (Uncompressed_Size : Interfaces.Unsigned_64;
      Compressed_Size   : out Interfaces.Unsigned_64) return Boolean
   is
      Block_Size : constant Interfaces.Unsigned_64 :=
        Interfaces.Unsigned_64 (Max_Compress_Block_Size);
      Blocks     : Interfaces.Unsigned_64;
      Overhead   : Interfaces.Unsigned_64;
   begin
      if Uncompressed_Size = 0 then
         Compressed_Size := 5;
         return True;
      end if;

      Blocks := Uncompressed_Size / Block_Size;
      if Uncompressed_Size mod Block_Size /= 0 then
         if Blocks = Interfaces.Unsigned_64'Last then
            return False;
         end if;
         Blocks := Blocks + 1;
      end if;

      if Blocks > Interfaces.Unsigned_64'Last / 5 then
         return False;
      end if;
      Overhead := Blocks * 5;

      if Uncompressed_Size > Interfaces.Unsigned_64'Last - Overhead then
         return False;
      end if;

      Compressed_Size := Uncompressed_Size + Overhead;
      return True;
   end Stored_Raw_Deflate_Size;

   function Has_Metadata (Metadata : GZip_Metadata) return Boolean is
   begin
      return
        Metadata.Has_Name
        or else Metadata.Has_Comment
        or else Metadata.Has_MTime
        or else Metadata.Has_OS
        or else Metadata.Has_XFL
        or else Metadata.Has_Extra
        or else Metadata.Header_CRC;
   end Has_Metadata;

   function Input_Bits
     (Filter : in out Filter_Type) return Bit_Source_Addresses.Object_Pointer
   is
   begin
      if Filter.Input_Bits = System.Null_Address then
         declare
            Source : constant Bit_Source_Addresses.Object_Pointer :=
              new Zlib.Stream_Bits.Bit_Source;
         begin
            Filter.Input_Bits := Bit_Source_Addresses.To_Address (Source);
         end;
      end if;

      return Bit_Source_Addresses.To_Pointer (Filter.Input_Bits);
   end Input_Bits;

   function Output_Window
     (Filter : in out Filter_Type) return Window_Addresses.Object_Pointer is
   begin
      if Filter.Output = System.Null_Address then
         declare
            W : constant Window_Addresses.Object_Pointer :=
              new Zlib.Sliding_Window.Window;
         begin
            Filter.Output := Window_Addresses.To_Address (W);
         end;
      end if;

      return Window_Addresses.To_Pointer (Filter.Output);
   end Output_Window;

   function Decoder_State
     (Filter : in out Filter_Type) return Decoder_Addresses.Object_Pointer is
   begin
      if Filter.Decoder = System.Null_Address then
         declare
            D : constant Decoder_Addresses.Object_Pointer :=
              new Zlib.Stream_Inflate.Decoder;
         begin
            Filter.Decoder := Decoder_Addresses.To_Address (D);
         end;
      end if;

      return Decoder_Addresses.To_Pointer (Filter.Decoder);
   end Decoder_State;

   function Before_First
     (Data : Ada.Streams.Stream_Element_Array)
      return Ada.Streams.Stream_Element_Offset is
   begin
      if Data'Length = 0 then
         return Data'First;
      elsif Data'First = Ada.Streams.Stream_Element_Offset'First then
         return Data'First;
      else
         return Data'First - 1;
      end if;
   end Before_First;

   function Mode_For_Level (Level : Compression_Level) return Compression_Mode
   is
   begin
      if Level = 0 then
         return Stored;
      elsif Level = 1 then
         return Fixed;
      else
         return Auto;
      end if;
   end Mode_For_Level;

   procedure Require_Compression_Usable (Filter : Compression_Filter_Type) is
   begin
      case Filter.State is
         when Compression_Open | Compression_Ended =>
            null;

         when Compression_Failed                   =>
            raise Zlib_Error;

         when Compression_Closed                   =>
            raise Status_Error;
      end case;
   end Require_Compression_Usable;

   procedure Reset_Compression_State (Filter : in out Compression_Filter_Type)
   is
   begin
      if Filter.Header = Zlib.GZip then
         Filter.Stored_Next := Need_GZip_ID1;
      elsif Filter.Header = Zlib.Raw_Deflate then
         Filter.Stored_Next := Collecting_Block;
      else
         Filter.Stored_Next := Need_Zlib_Header_0;
      end if;
      Filter.Block := [Filter.Block'Range => 0];
      Filter.Block_Count := 0;
      Filter.Data_Index := 0;
      Filter.Current_Final := False;
      Filter.Finish_Requested := False;
      Filter.Flush_Marker_Pending := False;
      Filter.Adler_A := 1;
      Filter.Adler_B := 0;
      --  Dictionary_Set and Dictionary_ID are session configuration, not
      --  block/trailer state, and are intentionally preserved across reset.
      Filter.CRC := 16#FFFF_FFFF#;
      Filter.ISIZE := 0;
      Filter.GZip_Header_CRC := 16#FFFF_FFFF#;
      Filter.Metadata_Index := 1;
      Filter.Bit_Byte := 0;
      Filter.Bit_Index := 0;
      Filter.Pending_Bit_Byte := 0;
      Filter.Pending_Bit_Valid := False;
      Filter.Symbol_Code := 0;
      Filter.Symbol_Bits_Left := 0;
      Filter.Dynamic_Bits := [others => False];
      Filter.Dynamic_Bit_Count := 0;
      Filter.Dynamic_Bit_Index := 0;
   end Reset_Compression_State;

   procedure Deflate_Init
     (Filter : in out Compression_Filter_Type;
      Header : Header_Type := Zlib_Header;
      Mode   : Compression_Mode := Auto) is
   begin
      Deflate_Init
        (Filter   => Filter,
         Header   => Header,
         Mode     => Mode,
         Metadata => No_GZip_Metadata);
   end Deflate_Init;

   procedure Deflate_Init
     (Filter : in out Compression_Filter_Type;
      Header : Header_Type := Zlib_Header;
      Level  : Compression_Level) is
   begin
      Deflate_Init
        (Filter => Filter, Header => Header, Mode => Mode_For_Level (Level));
      Filter.Level := Level;
   end Deflate_Init;

   procedure Deflate_Init
     (Filter   : in out Compression_Filter_Type;
      Header   : Header_Type := Zlib_Header;
      Level    : Compression_Level;
      Metadata : GZip_Metadata) is
   begin
      Deflate_Init
        (Filter   => Filter,
         Header   => Header,
         Mode     => Mode_For_Level (Level),
         Metadata => Metadata);
      Filter.Level := Level;
   end Deflate_Init;

   procedure Deflate_Init
     (Filter   : in out Compression_Filter_Type;
      Header   : Header_Type := Zlib_Header;
      Mode     : Compression_Mode := Auto;
      Metadata : GZip_Metadata)
   is
      Effective_Header : constant Header_Type :=
        (if Header = Default then Zlib_Header else Header);
   begin
      if Has_Metadata (Metadata) and then Effective_Header /= Zlib.GZip then
         Filter.State := Compression_Failed;
         raise Status_Error;
      end if;

      if not Metadata.Valid then
         Filter.State := Compression_Failed;
         raise Status_Error;
      end if;

      Filter.State := Compression_Open;
      Filter.Header := Header;
      Filter.Mode := Mode;
      Filter.Level := Default_Level;
      Filter.Metadata := Metadata;
      Filter.Dictionary_Set := False;
      Filter.Dictionary_ID := 0;
      Reset_Compression_State (Filter);
   end Deflate_Init;

   procedure Deflate_Set_Dictionary
     (Filter : in out Compression_Filter_Type; Dictionary : Byte_Array)
   is
      Effective_Header : constant Header_Type :=
        (if Filter.Header = Default then Zlib_Header else Filter.Header);
   begin
      if Filter.State /= Compression_Open then
         raise Status_Error;
      end if;

      if Effective_Header /= Zlib_Header
        or else Filter.Stored_Next /= Need_Zlib_Header_0
        or else Filter.Block_Count /= 0
      then
         Filter.State := Compression_Failed;
         raise Status_Error;
      end if;

      Filter.Dictionary_ID := Zlib.Checksums.Adler32 (Dictionary);
      Filter.Dictionary_Set := True;
   end Deflate_Set_Dictionary;

   function Is_Open (Filter : Compression_Filter_Type) return Boolean is
   begin
      return
        Filter.State = Compression_Open
        or else Filter.State = Compression_Failed
        or else Filter.State = Compression_Ended;
   end Is_Open;

   function Compression_Mode_Supported
     (Filter : Compression_Filter_Type) return Boolean is
   begin
      if Filter.Header = Raw_Deflate then
         return
           Filter.Mode = Stored
           or else Filter.Mode = Fixed
           or else Filter.Mode = Dynamic
           or else Filter.Mode = Auto;
      else
         return
           (Filter.Header = Default
            or else Filter.Header = Zlib_Header
            or else Filter.Header = Zlib.GZip)
           and then
             (Filter.Mode = Stored
              or else Filter.Mode = Fixed
              or else Filter.Mode = Dynamic
              or else Filter.Mode = Auto);
      end if;
   end Compression_Mode_Supported;

   procedure Mark_Compression_Failed (Filter : in out Compression_Filter_Type)
   is
   begin
      Filter.State := Compression_Failed;
   end Mark_Compression_Failed;

   procedure Require_Supported_Compression
     (Filter : in out Compression_Filter_Type) is
   begin
      if not Compression_Mode_Supported (Filter) then
         Mark_Compression_Failed (Filter);
         raise Zlib_Error;
      end if;
   end Require_Supported_Compression;

   procedure Update_Compression_Checksum
     (Filter : in out Compression_Filter_Type; B : Ada.Streams.Stream_Element)
   is
      Mod_Adler : constant Interfaces.Unsigned_32 := 65_521;
   begin
      if Filter.Header = Zlib.GZip then
         Zlib.CRC32_Internal.Update_Raw (Filter.CRC, B);
         Filter.ISIZE := Filter.ISIZE + 1;
      elsif Filter.Header = Zlib.Raw_Deflate then
         null;
      else
         Filter.Adler_A :=
           (Filter.Adler_A + Interfaces.Unsigned_32 (B)) mod Mod_Adler;
         Filter.Adler_B := (Filter.Adler_B + Filter.Adler_A) mod Mod_Adler;
      end if;
   end Update_Compression_Checksum;

   function Compression_CRC32
     (Filter : Compression_Filter_Type) return Interfaces.Unsigned_32 is
   begin
      return Filter.CRC xor 16#FFFF_FFFF#;
   end Compression_CRC32;

   function Compression_Adler
     (Filter : Compression_Filter_Type) return Interfaces.Unsigned_32 is
   begin
      return Interfaces.Shift_Left (Filter.Adler_B, 16) or Filter.Adler_A;
   end Compression_Adler;

   procedure Put_Compressed_Byte
     (Out_Data : in out Ada.Streams.Stream_Element_Array;
      Out_Last : in out Ada.Streams.Stream_Element_Offset;
      B        : Ada.Streams.Stream_Element) is
   begin
      if Out_Data'Length = 0 then
         return;
      end if;

      if Out_Last = Before_First (Out_Data) then
         Out_Last := Out_Data'First;
      else
         Out_Last := Out_Last + 1;
      end if;

      Out_Data (Out_Last) := B;
   end Put_Compressed_Byte;

   function Compression_Output_Full
     (Out_Data : Ada.Streams.Stream_Element_Array;
      Out_Last : Ada.Streams.Stream_Element_Offset) return Boolean is
   begin
      return Out_Data'Length > 0 and then Out_Last = Out_Data'Last;
   end Compression_Output_Full;

   function Effective_Compression_Mode
     (Filter : Compression_Filter_Type) return Compression_Mode is
   begin
      if Filter.Mode = Auto then
         --  Streaming Auto collects a block first; Start_Auto_Block_Emission
         --  then chooses Stored, Fixed, or Dynamic by deterministic size
         --  scoring before any byte of that block is emitted.
         return Dynamic;
      else
         return Filter.Mode;
      end if;
   end Effective_Compression_Mode;

   function Using_Fixed_Compression
     (Filter : Compression_Filter_Type) return Boolean is
   begin
      return Effective_Compression_Mode (Filter) = Fixed;
   end Using_Fixed_Compression;

   function Using_Dynamic_Compression
     (Filter : Compression_Filter_Type) return Boolean is
   begin
      return Effective_Compression_Mode (Filter) = Dynamic;
   end Using_Dynamic_Compression;

   procedure Start_Stored_Block_Emission
     (Filter : in out Compression_Filter_Type; Final : Boolean) is
   begin
      Filter.Current_Final := Final;
      Filter.Data_Index := 0;
      Filter.Stored_Next := Emit_Block_Header;
   end Start_Stored_Block_Emission;

   procedure Start_Empty_Stored_Flush_Marker
     (Filter : in out Compression_Filter_Type) is
   begin
      Filter.Current_Final := False;
      Filter.Flush_Marker_Pending := False;
      Filter.Block_Count := 0;
      Filter.Data_Index := 0;
      Filter.Symbol_Code := 0;
      Filter.Symbol_Bits_Left := 0;
      Filter.Stored_Next := Emit_Flush_Block_Header;
   end Start_Empty_Stored_Flush_Marker;

   procedure Build_Fixed_Pending_Bits
     (Filter : in out Compression_Filter_Type; Final : Boolean);

   procedure Start_Fixed_Block_Emission
     (Filter : in out Compression_Filter_Type; Final : Boolean) is
   begin
      Filter.Current_Final := Final;
      Filter.Data_Index := 0;
      Filter.Symbol_Code := 0;
      Filter.Symbol_Bits_Left := 0;
      Build_Fixed_Pending_Bits (Filter, Final);
      Filter.Stored_Next := Dynamic_Emit_Pending_Bits;
   exception
      when Zlib_Error =>
         Mark_Compression_Failed (Filter);
         raise;
   end Start_Fixed_Block_Emission;

   procedure Append_Dynamic_Bit
     (Filter : in out Compression_Filter_Type; Bit : Natural) is
   begin
      if Filter.Dynamic_Bit_Count >= Max_Dynamic_Pending_Bits then
         raise Zlib_Error;
      end if;

      Filter.Dynamic_Bits (Filter.Dynamic_Bit_Count) := (Bit mod 2) = 1;
      Filter.Dynamic_Bit_Count := Filter.Dynamic_Bit_Count + 1;
   end Append_Dynamic_Bit;

   procedure Append_Dynamic_Bits
     (Filter : in out Compression_Filter_Type;
      Value  : Natural;
      Count  : Natural)
   is
      Work : Natural := Value;
   begin
      for I in 1 .. Count loop
         Append_Dynamic_Bit (Filter, Work mod 2);
         Work := Work / 2;
      end loop;
   end Append_Dynamic_Bits;

   function Reverse_Bits (Value : Natural; Count : Natural) return Natural is
      Work   : Natural := Value;
      Result : Natural := 0;
   begin
      for I in 1 .. Count loop
         Result := Result * 2 + (Work mod 2);
         Work := Work / 2;
      end loop;

      return Result;
   end Reverse_Bits;

   procedure Build_Canonical
     (Lengths : Zlib.Huffman_Builder.Length_Array;
      Codes   : out Zlib.Huffman_Builder.Frequency_Array)
   is
      Bl_Count  : array (Natural range 0 .. 15) of Natural := [others => 0];
      Next_Code : array (Natural range 0 .. 15) of Natural := [others => 0];
      Code      : Natural := 0;
   begin
      Codes := [others => 0];

      for Symbol in Lengths'Range loop
         if Lengths (Symbol) /= 0 then
            Bl_Count (Lengths (Symbol)) := Bl_Count (Lengths (Symbol)) + 1;
         end if;
      end loop;

      for Bits in 1 .. 15 loop
         Code := (Code + Bl_Count (Bits - 1)) * 2;
         Next_Code (Bits) := Code;
      end loop;

      for Symbol in Lengths'Range loop
         if Lengths (Symbol) /= 0 then
            Codes (Symbol) :=
              Reverse_Bits (Next_Code (Lengths (Symbol)), Lengths (Symbol));
            Next_Code (Lengths (Symbol)) := Next_Code (Lengths (Symbol)) + 1;
         end if;
      end loop;
   end Build_Canonical;

   procedure Append_Dynamic_Code
     (Filter  : in out Compression_Filter_Type;
      Codes   : Zlib.Huffman_Builder.Frequency_Array;
      Lengths : Zlib.Huffman_Builder.Length_Array;
      Symbol  : Natural) is
   begin
      pragma
        Assert
          (Lengths (Symbol) /= 0,
           "attempt to write absent dynamic Huffman symbol");
      Append_Dynamic_Bits (Filter, Codes (Symbol), Lengths (Symbol));
   end Append_Dynamic_Code;

   function Length_Symbol_For (Length : Natural) return Natural is
   begin
      if Length = Zlib.LZ77_Matcher.Max_Match_Length then
         return 285;
      end if;

      for Symbol in Zlib.Deflate_Tables.Length_Symbol loop
         if Length >= Zlib.Deflate_Tables.Length_Base (Symbol)
           and then
             Length
             < Zlib.Deflate_Tables.Length_Base (Symbol)
               + 2 ** Zlib.Deflate_Tables.Length_Extra (Symbol)
         then
            return Symbol;
         end if;
      end loop;

      return 285;
   end Length_Symbol_For;

   function Distance_Symbol_For (Distance : Natural) return Natural is
   begin
      for Symbol in Zlib.Deflate_Tables.Distance_Symbol loop
         if Distance >= Zlib.Deflate_Tables.Distance_Base (Symbol)
           and then
             Distance
             < Zlib.Deflate_Tables.Distance_Base (Symbol)
               + 2 ** Zlib.Deflate_Tables.Distance_Extra (Symbol)
         then
            return Symbol;
         end if;
      end loop;

      return 29;
   end Distance_Symbol_For;

   procedure Append_Fixed_Code
     (Filter : in out Compression_Filter_Type; Symbol : Natural)
   is
      Code   : Natural;
      Length : Natural;
   begin
      Zlib.Fixed_Compress.Fixed_Code (Symbol, Code, Length);
      Append_Dynamic_Bits (Filter, Code, Length);
   end Append_Fixed_Code;

   procedure Append_Fixed_Distance_Code
     (Filter : in out Compression_Filter_Type; Symbol : Natural)
   is
      Code : constant Natural := Reverse_Bits (Symbol, 5);
   begin
      Append_Dynamic_Bits (Filter, Code, 5);
   end Append_Fixed_Distance_Code;

   procedure Append_Fixed_Token
     (Filter : in out Compression_Filter_Type; T : Zlib.LZ77_Matcher.Token) is
   begin
      case T.Kind is
         when Zlib.LZ77_Matcher.Literal =>
            Append_Fixed_Code (Filter, Natural (T.Value));

         when Zlib.LZ77_Matcher.Match   =>
            declare
               L_Sym : constant Natural := Length_Symbol_For (T.Length);
               D_Sym : constant Natural := Distance_Symbol_For (T.Distance);
            begin
               Append_Fixed_Code (Filter, L_Sym);
               Append_Dynamic_Bits
                 (Filter,
                  T.Length - Zlib.Deflate_Tables.Length_Base (L_Sym),
                  Zlib.Deflate_Tables.Length_Extra (L_Sym));
               Append_Fixed_Distance_Code (Filter, D_Sym);
               Append_Dynamic_Bits
                 (Filter,
                  T.Distance - Zlib.Deflate_Tables.Distance_Base (D_Sym),
                  Zlib.Deflate_Tables.Distance_Extra (D_Sym));
            end;
      end case;
   end Append_Fixed_Token;

   function Compression_Block_As_Bytes
     (Filter : Compression_Filter_Type) return Byte_Array is
   begin
      if Filter.Block_Count = 0 then
         declare
            Empty : constant Byte_Array (1 .. 0) := [others => 0];
         begin
            return Empty;
         end;
      end if;

      declare
         Result : Byte_Array (1 .. Filter.Block_Count);
      begin
         for I in 0 .. Filter.Block_Count - 1 loop
            Result (I + 1) := Byte (Filter.Block (Ada.Streams.Stream_Element_Offset (I)));
         end loop;

         return Result;
      end;
   end Compression_Block_As_Bytes;

   procedure Build_Fixed_Pending_Bits
     (Filter : in out Compression_Filter_Type; Final : Boolean) is
   begin
      Filter.Dynamic_Bits := [others => False];
      Filter.Dynamic_Bit_Count := 0;
      Filter.Dynamic_Bit_Index := 0;

      --  BFINAL followed by BTYPE=01, emitted LSB-first.
      Append_Dynamic_Bits (Filter, (if Final then 2#011# else 2#010#), 3);

      declare
         Block_Data : constant Byte_Array :=
           Compression_Block_As_Bytes (Filter);
         Tokens     : constant Zlib.LZ77_Matcher.Token_Array :=
           Zlib.LZ77_Matcher.Tokenize
             (Block_Data, Zlib.LZ77_Matcher.Chain_Limit_For_Level (1));
      begin
         for T of Tokens loop
            Append_Fixed_Token (Filter, T);
         end loop;
      end;

      Append_Fixed_Code (Filter, 256);
   end Build_Fixed_Pending_Bits;

   procedure Build_Dynamic_Pending_Bits
     (Filter : in out Compression_Filter_Type; Final : Boolean)
   is
      Code_Length_Order : constant array (Natural range 0 .. 18) of Natural :=
        [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15];

      subtype Litlen_Symbol is Natural range 0 .. 285;
      subtype Distance_Symbol is Natural range 0 .. 29;
      subtype Code_Length_Symbol is Natural range 0 .. 18;

      Lit_Freq  : Zlib.Huffman_Builder.Frequency_Array (Litlen_Symbol) :=
        [others => 0];
      Dist_Freq : Zlib.Huffman_Builder.Frequency_Array (Distance_Symbol) :=
        [others => 0];
      CL_Freq   : Zlib.Huffman_Builder.Frequency_Array (Code_Length_Symbol) :=
        [others => 0];

      Lit_Len  : Zlib.Huffman_Builder.Length_Array (Litlen_Symbol) :=
        [others => 0];
      Dist_Len : Zlib.Huffman_Builder.Length_Array (Distance_Symbol) :=
        [others => 0];
      CL_Len   : Zlib.Huffman_Builder.Length_Array (Code_Length_Symbol) :=
        [others => 0];

      Lit_Code  : Zlib.Huffman_Builder.Frequency_Array (Litlen_Symbol) :=
        [others => 0];
      Dist_Code : Zlib.Huffman_Builder.Frequency_Array (Distance_Symbol) :=
        [others => 0];
      CL_Code   : Zlib.Huffman_Builder.Frequency_Array (Code_Length_Symbol) :=
        [others => 0];

      LL_Last : Natural := 256;
      D_Last  : Natural := 0;
      CL_Last : Natural := 3;
   begin
      Filter.Dynamic_Bits := [others => False];
      Filter.Dynamic_Bit_Count := 0;
      Filter.Dynamic_Bit_Index := 0;

      declare
         Block_Data   : constant Byte_Array :=
           Compression_Block_As_Bytes (Filter);
         Tokens       : constant Zlib.LZ77_Matcher.Token_Array :=
           Zlib.LZ77_Matcher.Tokenize_For_Level (Block_Data, Filter.Level);
         Has_Distance : Boolean := False;
      begin
         for T of Tokens loop
            case T.Kind is
               when Zlib.LZ77_Matcher.Literal =>
                  Lit_Freq (Natural (T.Value)) :=
                    Lit_Freq (Natural (T.Value)) + 1;

               when Zlib.LZ77_Matcher.Match   =>
                  Lit_Freq (Length_Symbol_For (T.Length)) :=
                    Lit_Freq (Length_Symbol_For (T.Length)) + 1;
                  Dist_Freq (Distance_Symbol_For (T.Distance)) :=
                    Dist_Freq (Distance_Symbol_For (T.Distance)) + 1;
                  Has_Distance := True;
            end case;
         end loop;

         if not Has_Distance then
            Dist_Freq (0) := 1;
         end if;
      end;
      Lit_Freq (256) := Lit_Freq (256) + 1;

      Zlib.Huffman_Builder.Build_Lengths (Lit_Freq, Lit_Len, 256);
      Zlib.Huffman_Builder.Build_Lengths (Dist_Freq, Dist_Len, 0);

      for Symbol in Lit_Len'Range loop
         if Lit_Len (Symbol) /= 0 then
            LL_Last := Symbol;
         end if;
      end loop;
      LL_Last := Natural'Max (LL_Last, 256);

      for Symbol in Dist_Len'Range loop
         if Dist_Len (Symbol) /= 0 then
            D_Last := Symbol;
         end if;
      end loop;

      for Symbol in 0 .. LL_Last loop
         CL_Freq (Lit_Len (Symbol)) := CL_Freq (Lit_Len (Symbol)) + 1;
      end loop;
      for Symbol in 0 .. D_Last loop
         CL_Freq (Dist_Len (Symbol)) := CL_Freq (Dist_Len (Symbol)) + 1;
      end loop;

      Zlib.Huffman_Builder.Build_Lengths (CL_Freq, CL_Len, 0);

      for Order_Index in Code_Length_Order'Range loop
         if CL_Len (Code_Length_Order (Order_Index)) /= 0 then
            CL_Last := Order_Index;
         end if;
      end loop;
      CL_Last := Natural'Max (CL_Last, 3);

      Build_Canonical (Lit_Len, Lit_Code);
      Build_Canonical (Dist_Len, Dist_Code);
      Build_Canonical (CL_Len, CL_Code);

      Append_Dynamic_Bits (Filter, (if Final then 1 else 0), 1);
      Append_Dynamic_Bits (Filter, 2, 2);
      Append_Dynamic_Bits (Filter, LL_Last - 256, 5);
      Append_Dynamic_Bits (Filter, D_Last, 5);
      Append_Dynamic_Bits (Filter, CL_Last - 3, 4);

      for Order_Index in 0 .. CL_Last loop
         Append_Dynamic_Bits
           (Filter, CL_Len (Code_Length_Order (Order_Index)), 3);
      end loop;

      for Symbol in 0 .. LL_Last loop
         Append_Dynamic_Code (Filter, CL_Code, CL_Len, Lit_Len (Symbol));
      end loop;
      for Symbol in 0 .. D_Last loop
         Append_Dynamic_Code (Filter, CL_Code, CL_Len, Dist_Len (Symbol));
      end loop;

      declare
         Block_Data : constant Byte_Array :=
           Compression_Block_As_Bytes (Filter);
         Tokens     : constant Zlib.LZ77_Matcher.Token_Array :=
           Zlib.LZ77_Matcher.Tokenize_For_Level (Block_Data, Filter.Level);
      begin
         for T of Tokens loop
            case T.Kind is
               when Zlib.LZ77_Matcher.Literal =>
                  Append_Dynamic_Code
                    (Filter, Lit_Code, Lit_Len, Natural (T.Value));

               when Zlib.LZ77_Matcher.Match   =>
                  declare
                     L_Sym : constant Natural := Length_Symbol_For (T.Length);
                     D_Sym : constant Natural :=
                       Distance_Symbol_For (T.Distance);
                  begin
                     Append_Dynamic_Code (Filter, Lit_Code, Lit_Len, L_Sym);
                     Append_Dynamic_Bits
                       (Filter,
                        T.Length - Zlib.Deflate_Tables.Length_Base (L_Sym),
                        Zlib.Deflate_Tables.Length_Extra (L_Sym));
                     Append_Dynamic_Code (Filter, Dist_Code, Dist_Len, D_Sym);
                     Append_Dynamic_Bits
                       (Filter,
                        T.Distance - Zlib.Deflate_Tables.Distance_Base (D_Sym),
                        Zlib.Deflate_Tables.Distance_Extra (D_Sym));
                  end;
            end case;
         end loop;
      end;
      Append_Dynamic_Code (Filter, Lit_Code, Lit_Len, 256);
   end Build_Dynamic_Pending_Bits;

   procedure Start_Dynamic_Block_Emission
     (Filter : in out Compression_Filter_Type; Final : Boolean) is
   begin
      Filter.Current_Final := Final;
      Filter.Data_Index := 0;
      Filter.Symbol_Code := 0;
      Filter.Symbol_Bits_Left := 0;
      Build_Dynamic_Pending_Bits (Filter, Final);
      Filter.Stored_Next := Dynamic_Emit_Pending_Bits;
   exception
      when Zlib_Error =>
         Mark_Compression_Failed (Filter);
         raise;
   end Start_Dynamic_Block_Emission;

   function Try_Start_Dynamic_Block_Emission
     (Filter : in out Compression_Filter_Type; Final : Boolean) return Boolean
   is
   begin
      Filter.Current_Final := Final;
      Filter.Data_Index := 0;
      Filter.Symbol_Code := 0;
      Filter.Symbol_Bits_Left := 0;
      Build_Dynamic_Pending_Bits (Filter, Final);
      Filter.Stored_Next := Dynamic_Emit_Pending_Bits;
      return True;
   exception
      when Zlib_Error =>
         --  Auto fallback is only legal before block emission begins.  Dynamic
         --  block construction happens entirely in this pending-bit buffer, so
         --  no compressed byte from the current block has been exposed yet.
         Filter.Dynamic_Bits := [others => False];
         Filter.Dynamic_Bit_Count := 0;
         Filter.Dynamic_Bit_Index := 0;
         Filter.Data_Index := 0;
         Filter.Symbol_Code := 0;
         Filter.Symbol_Bits_Left := 0;
         return False;
   end Try_Start_Dynamic_Block_Emission;

   function Try_Start_Fixed_Block_Emission
     (Filter : in out Compression_Filter_Type; Final : Boolean) return Boolean
   is
   begin
      Filter.Current_Final := Final;
      Filter.Data_Index := 0;
      Filter.Symbol_Code := 0;
      Filter.Symbol_Bits_Left := 0;
      Build_Fixed_Pending_Bits (Filter, Final);
      Filter.Stored_Next := Dynamic_Emit_Pending_Bits;
      return True;
   exception
      when Zlib_Error =>
         --  Fixed block construction also happens entirely before emission,
         --  so Auto may still fall back to Stored without exposing bytes from
         --  the failed block attempt.
         Filter.Dynamic_Bits := [others => False];
         Filter.Dynamic_Bit_Count := 0;
         Filter.Dynamic_Bit_Index := 0;
         Filter.Data_Index := 0;
         Filter.Symbol_Code := 0;
         Filter.Symbol_Bits_Left := 0;
         return False;
   end Try_Start_Fixed_Block_Emission;

   procedure Start_Auto_Block_Emission
     (Filter : in out Compression_Filter_Type; Final : Boolean)
   is
      Block_Data     : constant Byte_Array :=
        Compression_Block_As_Bytes (Filter);
      Stored_Allowed : constant Boolean :=
        Filter.Bit_Index = 0 and then not Filter.Pending_Bit_Valid;

      Choice : constant Zlib.Block_Chooser.Candidate_Score :=
        Zlib.Block_Chooser.Choose
          (Input              => Block_Data,
           Level              => Filter.Level,
           Allow_Dynamic      => Filter.Level >= 2,
           Allow_Stored       => Stored_Allowed,
           Starting_Bit_Index => Filter.Bit_Index);
   begin
      --  Stored blocks require byte alignment before LEN/NLEN. The existing
      --  stored emitter is byte-oriented, so a non-aligned stream position
      --  removes Stored from the Auto candidate set instead of falling back to
      --  a fixed-first order. This preserves both stream validity and the
      --  scored choice between Fixed and Dynamic.
      if Choice.Kind = Zlib.Block_Chooser.Stored_Block then
         if Stored_Allowed then
            Start_Stored_Block_Emission (Filter, Final);
            return;
         end if;

         if Try_Start_Fixed_Block_Emission (Filter, Final) then
            return;
         end if;

         if Filter.Level >= 2
           and then Try_Start_Dynamic_Block_Emission (Filter, Final)
         then
            return;
         end if;
      end if;

      if Choice.Kind = Zlib.Block_Chooser.Fixed_Block then
         if Try_Start_Fixed_Block_Emission (Filter, Final) then
            return;
         end if;

         if Filter.Level >= 2
           and then Try_Start_Dynamic_Block_Emission (Filter, Final)
         then
            return;
         end if;
      elsif Choice.Kind = Zlib.Block_Chooser.Dynamic_Block then
         if Try_Start_Dynamic_Block_Emission (Filter, Final) then
            return;
         end if;

         if Try_Start_Fixed_Block_Emission (Filter, Final) then
            return;
         end if;
      end if;

      --  Fallback remains before emission of the current block.
      if Stored_Allowed then
         Start_Stored_Block_Emission (Filter, Final);
      elsif Try_Start_Fixed_Block_Emission (Filter, Final) then
         return;
      else
         Mark_Compression_Failed (Filter);
         raise Zlib_Error;
      end if;
   end Start_Auto_Block_Emission;

   procedure Start_Compression_Block_Emission
     (Filter : in out Compression_Filter_Type; Final : Boolean) is
   begin
      if Filter.Mode = Auto then
         Start_Auto_Block_Emission (Filter, Final);
      elsif Using_Dynamic_Compression (Filter) then
         Start_Dynamic_Block_Emission (Filter, Final);
      elsif Using_Fixed_Compression (Filter) then
         Start_Fixed_Block_Emission (Filter, Final);
      else
         Start_Stored_Block_Emission (Filter, Final);
      end if;
   end Start_Compression_Block_Emission;

   function Drain_Pending_Bit_Byte
     (Filter   : in out Compression_Filter_Type;
      Out_Data : in out Ada.Streams.Stream_Element_Array;
      Out_Last : in out Ada.Streams.Stream_Element_Offset) return Boolean is
   begin
      if Filter.Pending_Bit_Valid then
         if Compression_Output_Full (Out_Data, Out_Last) then
            return False;
         end if;

         Put_Compressed_Byte (Out_Data, Out_Last, Filter.Pending_Bit_Byte);
         Filter.Pending_Bit_Byte := 0;
         Filter.Pending_Bit_Valid := False;
      end if;

      return True;
   end Drain_Pending_Bit_Byte;

   function Write_Fixed_Bit
     (Filter   : in out Compression_Filter_Type;
      Bit      : Natural;
      Out_Data : in out Ada.Streams.Stream_Element_Array;
      Out_Last : in out Ada.Streams.Stream_Element_Offset) return Boolean
   is
   begin
      if not Drain_Pending_Bit_Byte (Filter, Out_Data, Out_Last) then
         return False;
      end if;

      if Compression_Output_Full (Out_Data, Out_Last) then
         return False;
      end if;

      if Bit mod 2 = 1 then
         Filter.Bit_Byte :=
           Filter.Bit_Byte
           or Ada.Streams.Stream_Element (2 ** Filter.Bit_Index);
      end if;

      if Filter.Bit_Index = 7 then
         Filter.Pending_Bit_Byte := Filter.Bit_Byte;
         Filter.Pending_Bit_Valid := True;
         Filter.Bit_Byte := 0;
         Filter.Bit_Index := 0;
         declare
            Drained : constant Boolean :=
              Drain_Pending_Bit_Byte (Filter, Out_Data, Out_Last);
         begin
            pragma Unreferenced (Drained);
         end;
      else
         Filter.Bit_Index := Filter.Bit_Index + 1;
      end if;

      return True;
   end Write_Fixed_Bit;

   function Emit_Current_Fixed_Code
     (Filter   : in out Compression_Filter_Type;
      Out_Data : in out Ada.Streams.Stream_Element_Array;
      Out_Last : in out Ada.Streams.Stream_Element_Offset) return Boolean is
   begin
      while Filter.Symbol_Bits_Left > 0 loop
         if not Write_Fixed_Bit
                  (Filter, Filter.Symbol_Code mod 2, Out_Data, Out_Last)
         then
            return False;
         end if;

         Filter.Symbol_Code := Filter.Symbol_Code / 2;
         Filter.Symbol_Bits_Left := Filter.Symbol_Bits_Left - 1;
      end loop;

      return True;
   end Emit_Current_Fixed_Code;

   procedure Start_Fixed_Code
     (Filter : in out Compression_Filter_Type;
      Value  : Natural;
      Count  : Natural) is
   begin
      Filter.Symbol_Code := Value;
      Filter.Symbol_Bits_Left := Count;
   end Start_Fixed_Code;

   procedure Start_Fixed_Symbol
     (Filter : in out Compression_Filter_Type; Symbol : Natural)
   is
      Code   : Natural;
      Length : Natural;
   begin
      Zlib.Fixed_Compress.Fixed_Code (Symbol, Code, Length);
      Start_Fixed_Code (Filter, Code, Length);
   end Start_Fixed_Symbol;

   function Flush_Fixed_Final_Byte
     (Filter   : in out Compression_Filter_Type;
      Out_Data : in out Ada.Streams.Stream_Element_Array;
      Out_Last : in out Ada.Streams.Stream_Element_Offset) return Boolean is
   begin
      if not Drain_Pending_Bit_Byte (Filter, Out_Data, Out_Last) then
         return False;
      end if;

      if Filter.Bit_Index /= 0 then
         if Compression_Output_Full (Out_Data, Out_Last) then
            return False;
         end if;

         Filter.Pending_Bit_Byte := Filter.Bit_Byte;
         Filter.Pending_Bit_Valid := True;
         Filter.Bit_Byte := 0;
         Filter.Bit_Index := 0;
         return Drain_Pending_Bit_Byte (Filter, Out_Data, Out_Last);
      end if;

      return True;
   end Flush_Fixed_Final_Byte;

   function First_Collecting_State
     (Filter : Compression_Filter_Type) return Stored_Compress_State is
   begin
      if Using_Dynamic_Compression (Filter) then
         return Dynamic_Collecting_Block;
      elsif Using_Fixed_Compression (Filter) then
         return Fixed_Collecting_Block;
      else
         return Collecting_Block;
      end if;
   end First_Collecting_State;

   function Is_Compression_Collecting
     (Filter : Compression_Filter_Type) return Boolean is
   begin
      return
        Filter.Stored_Next = Collecting_Block
        or else Filter.Stored_Next = Fixed_Collecting_Block
        or else Filter.Stored_Next = Dynamic_Collecting_Block;
   end Is_Compression_Collecting;

   function Trailer_Start_State
     (Filter : Compression_Filter_Type) return Stored_Compress_State is
   begin
      if Filter.Header = Zlib.GZip then
         return Emit_GZip_CRC_0;
      elsif Filter.Header = Zlib.Raw_Deflate then
         return Done;
      else
         return Emit_Adler_0;
      end if;
   end Trailer_Start_State;

   function GZip_FLG
     (Metadata : GZip_Metadata) return Ada.Streams.Stream_Element
   is
      Result : Ada.Streams.Stream_Element := 0;
   begin
      if Metadata.Header_CRC then
         Result := Result or 16#02#;
      end if;
      if Metadata.Has_Extra then
         Result := Result or 16#04#;
      end if;
      if Metadata.Has_Name then
         Result := Result or 16#08#;
      end if;
      if Metadata.Has_Comment then
         Result := Result or 16#10#;
      end if;
      return Result;
   end GZip_FLG;

   procedure Put_GZip_Header_Byte
     (Filter   : in out Compression_Filter_Type;
      Out_Data : in out Ada.Streams.Stream_Element_Array;
      Out_Last : in out Ada.Streams.Stream_Element_Offset;
      B        : Ada.Streams.Stream_Element) is
   begin
      Put_Compressed_Byte (Out_Data, Out_Last, B);
      Zlib.CRC32_Internal.Update_Raw (Filter.GZip_Header_CRC, B);
   end Put_GZip_Header_Byte;

   function GZip_Header_CRC16
     (Filter : Compression_Filter_Type) return Interfaces.Unsigned_32 is
   begin
      return (Filter.GZip_Header_CRC xor 16#FFFF_FFFF#) and 16#FFFF#;
   end GZip_Header_CRC16;

   procedure Emit_Compression_Output
     (Filter   : in out Compression_Filter_Type;
      Out_Data : in out Ada.Streams.Stream_Element_Array;
      Out_Last : in out Ada.Streams.Stream_Element_Offset)
   is
      Adler : Interfaces.Unsigned_32;
      Len   : Interfaces.Unsigned_32;
      NLen  : Interfaces.Unsigned_32;
   begin
      while Out_Data'Length > 0
        and then not Compression_Output_Full (Out_Data, Out_Last)
      loop
         case Filter.Stored_Next is
            when Need_Zlib_Header_0        =>
               Put_Compressed_Byte (Out_Data, Out_Last, 16#78#);
               Filter.Stored_Next := Need_Zlib_Header_1;

            when Need_Zlib_Header_1        =>
               if Filter.Dictionary_Set then
                  Put_Compressed_Byte (Out_Data, Out_Last, 16#20#);
                  Filter.Stored_Next := Need_Zlib_DICTID_0;
               else
                  Put_Compressed_Byte (Out_Data, Out_Last, 16#01#);
                  Filter.Stored_Next := First_Collecting_State (Filter);
               end if;

            when Need_Zlib_DICTID_0        =>
               Adler := Filter.Dictionary_ID;
               Put_Compressed_Byte
                 (Out_Data,
                  Out_Last,
                  Ada.Streams.Stream_Element
                    (Interfaces.Shift_Right (Adler, 24) and 16#FF#));
               Filter.Stored_Next := Need_Zlib_DICTID_1;

            when Need_Zlib_DICTID_1        =>
               Adler := Filter.Dictionary_ID;
               Put_Compressed_Byte
                 (Out_Data,
                  Out_Last,
                  Ada.Streams.Stream_Element
                    (Interfaces.Shift_Right (Adler, 16) and 16#FF#));
               Filter.Stored_Next := Need_Zlib_DICTID_2;

            when Need_Zlib_DICTID_2        =>
               Adler := Filter.Dictionary_ID;
               Put_Compressed_Byte
                 (Out_Data,
                  Out_Last,
                  Ada.Streams.Stream_Element
                    (Interfaces.Shift_Right (Adler, 8) and 16#FF#));
               Filter.Stored_Next := Need_Zlib_DICTID_3;

            when Need_Zlib_DICTID_3        =>
               Adler := Filter.Dictionary_ID;
               Put_Compressed_Byte
                 (Out_Data,
                  Out_Last,
                  Ada.Streams.Stream_Element (Adler and 16#FF#));
               Filter.Stored_Next := First_Collecting_State (Filter);

            when Need_GZip_ID1             =>
               Put_GZip_Header_Byte (Filter, Out_Data, Out_Last, 16#1F#);
               Filter.Stored_Next := Need_GZip_ID2;

            when Need_GZip_ID2             =>
               Put_GZip_Header_Byte (Filter, Out_Data, Out_Last, 16#8B#);
               Filter.Stored_Next := Need_GZip_CM;

            when Need_GZip_CM              =>
               Put_GZip_Header_Byte (Filter, Out_Data, Out_Last, 16#08#);
               Filter.Stored_Next := Need_GZip_FLG;

            when Need_GZip_FLG             =>
               Put_GZip_Header_Byte
                 (Filter, Out_Data, Out_Last, GZip_FLG (Filter.Metadata));
               Filter.Stored_Next := Need_GZip_MTIME_0;

            when Need_GZip_MTIME_0         =>
               Adler :=
                 (if Filter.Metadata.Has_MTime
                  then Filter.Metadata.MTime
                  else 0);
               Put_GZip_Header_Byte
                 (Filter,
                  Out_Data,
                  Out_Last,
                  Ada.Streams.Stream_Element (Adler and 16#FF#));
               Filter.Stored_Next := Need_GZip_MTIME_1;

            when Need_GZip_MTIME_1         =>
               Adler :=
                 (if Filter.Metadata.Has_MTime
                  then Filter.Metadata.MTime
                  else 0);
               Put_GZip_Header_Byte
                 (Filter,
                  Out_Data,
                  Out_Last,
                  Ada.Streams.Stream_Element
                    (Interfaces.Shift_Right (Adler, 8) and 16#FF#));
               Filter.Stored_Next := Need_GZip_MTIME_2;

            when Need_GZip_MTIME_2         =>
               Adler :=
                 (if Filter.Metadata.Has_MTime
                  then Filter.Metadata.MTime
                  else 0);
               Put_GZip_Header_Byte
                 (Filter,
                  Out_Data,
                  Out_Last,
                  Ada.Streams.Stream_Element
                    (Interfaces.Shift_Right (Adler, 16) and 16#FF#));
               Filter.Stored_Next := Need_GZip_MTIME_3;

            when Need_GZip_MTIME_3         =>
               Adler :=
                 (if Filter.Metadata.Has_MTime
                  then Filter.Metadata.MTime
                  else 0);
               Put_GZip_Header_Byte
                 (Filter,
                  Out_Data,
                  Out_Last,
                  Ada.Streams.Stream_Element
                    (Interfaces.Shift_Right (Adler, 24) and 16#FF#));
               Filter.Stored_Next := Need_GZip_XFL;

            when Need_GZip_XFL             =>
               Put_GZip_Header_Byte
                 (Filter,
                  Out_Data,
                  Out_Last,
                  Ada.Streams.Stream_Element
                    ((if Filter.Metadata.Has_XFL
                      then Filter.Metadata.XFL
                      else 0)));
               Filter.Stored_Next := Need_GZip_OS;

            when Need_GZip_OS              =>
               Put_GZip_Header_Byte
                 (Filter,
                  Out_Data,
                  Out_Last,
                  Ada.Streams.Stream_Element
                    ((if Filter.Metadata.Has_OS
                      then Filter.Metadata.OS
                      else 255)));
               if Filter.Metadata.Has_Extra then
                  Filter.Stored_Next := Need_GZip_XLEN_0;
               elsif Filter.Metadata.Has_Name then
                  Filter.Metadata_Index := 1;
                  Filter.Stored_Next := Need_GZip_Name;
               elsif Filter.Metadata.Has_Comment then
                  Filter.Metadata_Index := 1;
                  Filter.Stored_Next := Need_GZip_Comment;
               elsif Filter.Metadata.Header_CRC then
                  Filter.Stored_Next := Need_GZip_HCRC_0;
               else
                  Filter.Stored_Next := First_Collecting_State (Filter);
               end if;

            when Need_GZip_XLEN_0          =>
               Adler :=
                 Interfaces.Unsigned_32 (US.Length (Filter.Metadata.Extra));
               Put_GZip_Header_Byte
                 (Filter,
                  Out_Data,
                  Out_Last,
                  Ada.Streams.Stream_Element (Adler and 16#FF#));
               Filter.Stored_Next := Need_GZip_XLEN_1;

            when Need_GZip_XLEN_1          =>
               Adler :=
                 Interfaces.Unsigned_32 (US.Length (Filter.Metadata.Extra));
               Put_GZip_Header_Byte
                 (Filter,
                  Out_Data,
                  Out_Last,
                  Ada.Streams.Stream_Element
                    (Interfaces.Shift_Right (Adler, 8) and 16#FF#));
               Filter.Metadata_Index := 1;
               if US.Length (Filter.Metadata.Extra) = 0 then
                  if Filter.Metadata.Has_Name then
                     Filter.Stored_Next := Need_GZip_Name;
                  elsif Filter.Metadata.Has_Comment then
                     Filter.Stored_Next := Need_GZip_Comment;
                  elsif Filter.Metadata.Header_CRC then
                     Filter.Stored_Next := Need_GZip_HCRC_0;
                  else
                     Filter.Stored_Next := First_Collecting_State (Filter);
                  end if;
               else
                  Filter.Stored_Next := Need_GZip_Extra;
               end if;

            when Need_GZip_Extra           =>
               declare
                  Extra : constant String :=
                    US.To_String (Filter.Metadata.Extra);
               begin
                  if Filter.Metadata_Index <= Extra'Length then
                     Put_GZip_Header_Byte
                       (Filter,
                        Out_Data,
                        Out_Last,
                        Ada.Streams.Stream_Element
                          (Character'Pos
                             (Extra
                                (Extra'First + Filter.Metadata_Index - 1))));
                     Filter.Metadata_Index := Filter.Metadata_Index + 1;
                  elsif Filter.Metadata.Has_Name then
                     Filter.Metadata_Index := 1;
                     Filter.Stored_Next := Need_GZip_Name;
                  elsif Filter.Metadata.Has_Comment then
                     Filter.Metadata_Index := 1;
                     Filter.Stored_Next := Need_GZip_Comment;
                  elsif Filter.Metadata.Header_CRC then
                     Filter.Stored_Next := Need_GZip_HCRC_0;
                  else
                     Filter.Stored_Next := First_Collecting_State (Filter);
                  end if;
               end;

            when Need_GZip_Name            =>
               declare
                  Name : constant String :=
                    US.To_String (Filter.Metadata.Name);
               begin
                  if Filter.Metadata_Index <= Name'Length then
                     Put_GZip_Header_Byte
                       (Filter,
                        Out_Data,
                        Out_Last,
                        Ada.Streams.Stream_Element
                          (Character'Pos
                             (Name (Name'First + Filter.Metadata_Index - 1))));
                     Filter.Metadata_Index := Filter.Metadata_Index + 1;
                  else
                     Filter.Stored_Next := Need_GZip_Name_NUL;
                  end if;
               end;

            when Need_GZip_Name_NUL        =>
               Put_GZip_Header_Byte (Filter, Out_Data, Out_Last, 16#00#);
               if Filter.Metadata.Has_Comment then
                  Filter.Metadata_Index := 1;
                  Filter.Stored_Next := Need_GZip_Comment;
               elsif Filter.Metadata.Header_CRC then
                  Filter.Stored_Next := Need_GZip_HCRC_0;
               else
                  Filter.Stored_Next := First_Collecting_State (Filter);
               end if;

            when Need_GZip_Comment         =>
               declare
                  Comment : constant String :=
                    US.To_String (Filter.Metadata.Comment);
               begin
                  if Filter.Metadata_Index <= Comment'Length then
                     Put_GZip_Header_Byte
                       (Filter,
                        Out_Data,
                        Out_Last,
                        Ada.Streams.Stream_Element
                          (Character'Pos
                             (Comment
                                (Comment'First + Filter.Metadata_Index - 1))));
                     Filter.Metadata_Index := Filter.Metadata_Index + 1;
                  else
                     Filter.Stored_Next := Need_GZip_Comment_NUL;
                  end if;
               end;

            when Need_GZip_Comment_NUL     =>
               Put_GZip_Header_Byte (Filter, Out_Data, Out_Last, 16#00#);
               if Filter.Metadata.Header_CRC then
                  Filter.Stored_Next := Need_GZip_HCRC_0;
               else
                  Filter.Stored_Next := First_Collecting_State (Filter);
               end if;

            when Need_GZip_HCRC_0          =>
               Adler := GZip_Header_CRC16 (Filter);
               Put_Compressed_Byte
                 (Out_Data,
                  Out_Last,
                  Ada.Streams.Stream_Element (Adler and 16#FF#));
               Filter.Stored_Next := Need_GZip_HCRC_1;

            when Need_GZip_HCRC_1          =>
               Adler := GZip_Header_CRC16 (Filter);
               Put_Compressed_Byte
                 (Out_Data,
                  Out_Last,
                  Ada.Streams.Stream_Element
                    (Interfaces.Shift_Right (Adler, 8) and 16#FF#));
               Filter.Stored_Next := First_Collecting_State (Filter);

            when Collecting_Block          =>
               return;

            when Emit_Block_Header         =>
               if Filter.Current_Final then
                  Put_Compressed_Byte (Out_Data, Out_Last, 16#01#);
               else
                  Put_Compressed_Byte (Out_Data, Out_Last, 16#00#);
               end if;
               Filter.Stored_Next := Emit_Len_0;

            when Emit_Flush_Block_Header   =>
               if Filter.Symbol_Bits_Left = 0 then
                  --  BFINAL=0, BTYPE=00, emitted at the current bit position.
                  --  The following flush pads to the next byte before LEN/NLEN.
                  Start_Fixed_Code (Filter, 0, 3);
               end if;

               if Emit_Current_Fixed_Code (Filter, Out_Data, Out_Last) then
                  if Flush_Fixed_Final_Byte (Filter, Out_Data, Out_Last) then
                     Filter.Stored_Next := Emit_Len_0;
                  else
                     return;
                  end if;
               else
                  return;
               end if;

            when Emit_Len_0                =>
               Len := Interfaces.Unsigned_32 (Filter.Block_Count);
               Put_Compressed_Byte
                 (Out_Data,
                  Out_Last,
                  Ada.Streams.Stream_Element (Len and 16#FF#));
               Filter.Stored_Next := Emit_Len_1;

            when Emit_Len_1                =>
               Len := Interfaces.Unsigned_32 (Filter.Block_Count);
               Put_Compressed_Byte
                 (Out_Data,
                  Out_Last,
                  Ada.Streams.Stream_Element
                    (Interfaces.Shift_Right (Len, 8) and 16#FF#));
               Filter.Stored_Next := Emit_NLen_0;

            when Emit_NLen_0               =>
               Len := Interfaces.Unsigned_32 (Filter.Block_Count);
               NLen := (not Len) and 16#FFFF#;
               Put_Compressed_Byte
                 (Out_Data,
                  Out_Last,
                  Ada.Streams.Stream_Element (NLen and 16#FF#));
               Filter.Stored_Next := Emit_NLen_1;

            when Emit_NLen_1               =>
               Len := Interfaces.Unsigned_32 (Filter.Block_Count);
               NLen := (not Len) and 16#FFFF#;
               Put_Compressed_Byte
                 (Out_Data,
                  Out_Last,
                  Ada.Streams.Stream_Element
                    (Interfaces.Shift_Right (NLen, 8) and 16#FF#));
               if Filter.Block_Count = 0 then
                  if Filter.Current_Final then
                     Filter.Stored_Next := Trailer_Start_State (Filter);
                     if Filter.Stored_Next = Done then
                        Filter.State := Compression_Ended;
                     end if;
                  else
                     Filter.Stored_Next := First_Collecting_State (Filter);
                  end if;
               else
                  Filter.Stored_Next := Emit_Block_Data;
               end if;

            when Emit_Block_Data           =>
               Put_Compressed_Byte
                 (Out_Data, Out_Last, Filter.Block (Ada.Streams.Stream_Element_Offset (Filter.Data_Index)));
               Filter.Data_Index := Filter.Data_Index + 1;
               if Filter.Data_Index = Filter.Block_Count then
                  Filter.Block_Count := 0;
                  Filter.Data_Index := 0;
                  if Filter.Current_Final then
                     Filter.Stored_Next := Trailer_Start_State (Filter);
                     if Filter.Stored_Next = Done then
                        Filter.State := Compression_Ended;
                     end if;
                  elsif Filter.Flush_Marker_Pending then
                     Start_Empty_Stored_Flush_Marker (Filter);
                  else
                     Filter.Stored_Next := First_Collecting_State (Filter);
                  end if;
               end if;

            when Fixed_Collecting_Block    =>
               return;

            when Dynamic_Collecting_Block  =>
               return;

            when Dynamic_Emit_Pending_Bits =>
               while Filter.Dynamic_Bit_Index < Filter.Dynamic_Bit_Count loop
                  if not Write_Fixed_Bit
                           (Filter,
                            (if Filter.Dynamic_Bits (Filter.Dynamic_Bit_Index)
                             then 1
                             else 0),
                            Out_Data,
                            Out_Last)
                  then
                     return;
                  end if;

                  Filter.Dynamic_Bit_Index := Filter.Dynamic_Bit_Index + 1;
                  exit when Compression_Output_Full (Out_Data, Out_Last);
               end loop;

               if Filter.Dynamic_Bit_Index = Filter.Dynamic_Bit_Count then
                  Filter.Block_Count := 0;
                  Filter.Data_Index := 0;
                  Filter.Dynamic_Bit_Count := 0;
                  Filter.Dynamic_Bit_Index := 0;
                  if Filter.Current_Final then
                     Filter.Stored_Next := Dynamic_Flush_Final_Byte;
                  elsif Filter.Flush_Marker_Pending then
                     Start_Empty_Stored_Flush_Marker (Filter);
                  else
                     Filter.Stored_Next := First_Collecting_State (Filter);
                  end if;
               end if;

            when Dynamic_Flush_Final_Byte  =>
               if Flush_Fixed_Final_Byte (Filter, Out_Data, Out_Last) then
                  Filter.Stored_Next := Trailer_Start_State (Filter);
               else
                  return;
               end if;

            when Fixed_Emit_Block_Header   =>
               if Filter.Symbol_Bits_Left = 0 then
                  --  BFINAL followed by BTYPE=01, all emitted LSB-first.
                  if Filter.Current_Final then
                     Start_Fixed_Code (Filter, 2#011#, 3);
                  else
                     Start_Fixed_Code (Filter, 2#010#, 3);
                  end if;
               end if;

               if Emit_Current_Fixed_Code (Filter, Out_Data, Out_Last) then
                  Filter.Stored_Next := Fixed_Emit_Literals;
               else
                  return;
               end if;

            when Fixed_Emit_Literals       =>
               while Filter.Data_Index < Filter.Block_Count loop
                  if Filter.Symbol_Bits_Left = 0 then
                     Start_Fixed_Symbol
                       (Filter, Natural (Filter.Block (Ada.Streams.Stream_Element_Offset (Filter.Data_Index))));
                  end if;

                  if not Emit_Current_Fixed_Code (Filter, Out_Data, Out_Last)
                  then
                     return;
                  end if;

                  Filter.Data_Index := Filter.Data_Index + 1;
                  exit when Compression_Output_Full (Out_Data, Out_Last);
               end loop;

               if Filter.Data_Index = Filter.Block_Count then
                  Filter.Stored_Next := Fixed_Emit_EOB;
               end if;

            when Fixed_Emit_EOB            =>
               if Filter.Symbol_Bits_Left = 0 then
                  Start_Fixed_Symbol (Filter, 256);
               end if;

               if Emit_Current_Fixed_Code (Filter, Out_Data, Out_Last) then
                  Filter.Block_Count := 0;
                  Filter.Data_Index := 0;
                  if Filter.Current_Final then
                     Filter.Stored_Next := Fixed_Flush_Final_Byte;
                  elsif Filter.Flush_Marker_Pending then
                     Start_Empty_Stored_Flush_Marker (Filter);
                  else
                     Filter.Stored_Next := Fixed_Collecting_Block;
                  end if;
               else
                  return;
               end if;

            when Fixed_Flush_Final_Byte    =>
               if Flush_Fixed_Final_Byte (Filter, Out_Data, Out_Last) then
                  Filter.Stored_Next := Trailer_Start_State (Filter);
               else
                  return;
               end if;

            when Emit_Adler_0              =>
               Adler := Compression_Adler (Filter);
               Put_Compressed_Byte
                 (Out_Data,
                  Out_Last,
                  Ada.Streams.Stream_Element
                    (Interfaces.Shift_Right (Adler, 24) and 16#FF#));
               Filter.Stored_Next := Emit_Adler_1;

            when Emit_Adler_1              =>
               Adler := Compression_Adler (Filter);
               Put_Compressed_Byte
                 (Out_Data,
                  Out_Last,
                  Ada.Streams.Stream_Element
                    (Interfaces.Shift_Right (Adler, 16) and 16#FF#));
               Filter.Stored_Next := Emit_Adler_2;

            when Emit_Adler_2              =>
               Adler := Compression_Adler (Filter);
               Put_Compressed_Byte
                 (Out_Data,
                  Out_Last,
                  Ada.Streams.Stream_Element
                    (Interfaces.Shift_Right (Adler, 8) and 16#FF#));
               Filter.Stored_Next := Emit_Adler_3;

            when Emit_Adler_3              =>
               Adler := Compression_Adler (Filter);
               Put_Compressed_Byte
                 (Out_Data,
                  Out_Last,
                  Ada.Streams.Stream_Element (Adler and 16#FF#));
               Filter.Stored_Next := Done;
               Filter.State := Compression_Ended;

            when Emit_GZip_CRC_0           =>
               Adler := Compression_CRC32 (Filter);
               Put_Compressed_Byte
                 (Out_Data,
                  Out_Last,
                  Ada.Streams.Stream_Element (Adler and 16#FF#));
               Filter.Stored_Next := Emit_GZip_CRC_1;

            when Emit_GZip_CRC_1           =>
               Adler := Compression_CRC32 (Filter);
               Put_Compressed_Byte
                 (Out_Data,
                  Out_Last,
                  Ada.Streams.Stream_Element
                    (Interfaces.Shift_Right (Adler, 8) and 16#FF#));
               Filter.Stored_Next := Emit_GZip_CRC_2;

            when Emit_GZip_CRC_2           =>
               Adler := Compression_CRC32 (Filter);
               Put_Compressed_Byte
                 (Out_Data,
                  Out_Last,
                  Ada.Streams.Stream_Element
                    (Interfaces.Shift_Right (Adler, 16) and 16#FF#));
               Filter.Stored_Next := Emit_GZip_CRC_3;

            when Emit_GZip_CRC_3           =>
               Adler := Compression_CRC32 (Filter);
               Put_Compressed_Byte
                 (Out_Data,
                  Out_Last,
                  Ada.Streams.Stream_Element
                    (Interfaces.Shift_Right (Adler, 24) and 16#FF#));
               Filter.Stored_Next := Emit_GZip_ISIZE_0;

            when Emit_GZip_ISIZE_0         =>
               Put_Compressed_Byte
                 (Out_Data,
                  Out_Last,
                  Ada.Streams.Stream_Element (Filter.ISIZE and 16#FF#));
               Filter.Stored_Next := Emit_GZip_ISIZE_1;

            when Emit_GZip_ISIZE_1         =>
               Put_Compressed_Byte
                 (Out_Data,
                  Out_Last,
                  Ada.Streams.Stream_Element
                    (Interfaces.Shift_Right (Filter.ISIZE, 8) and 16#FF#));
               Filter.Stored_Next := Emit_GZip_ISIZE_2;

            when Emit_GZip_ISIZE_2         =>
               Put_Compressed_Byte
                 (Out_Data,
                  Out_Last,
                  Ada.Streams.Stream_Element
                    (Interfaces.Shift_Right (Filter.ISIZE, 16) and 16#FF#));
               Filter.Stored_Next := Emit_GZip_ISIZE_3;

            when Emit_GZip_ISIZE_3         =>
               Put_Compressed_Byte
                 (Out_Data,
                  Out_Last,
                  Ada.Streams.Stream_Element
                    (Interfaces.Shift_Right (Filter.ISIZE, 24) and 16#FF#));
               Filter.Stored_Next := Done;
               Filter.State := Compression_Ended;

            when Done                      =>
               Filter.State := Compression_Ended;
               return;
         end case;
      end loop;
   end Emit_Compression_Output;

   procedure Consume_Compression_Input
     (Filter  : in out Compression_Filter_Type;
      In_Data : Ada.Streams.Stream_Element_Array;
      In_Last : in out Ada.Streams.Stream_Element_Offset)
   is
      Next_Input : Ada.Streams.Stream_Element_Offset;
   begin
      if In_Data'Length = 0 then
         return;
      end if;

      if In_Last = Before_First (In_Data) then
         Next_Input := In_Data'First;
      else
         Next_Input := In_Last + 1;
      end if;

      while Next_Input <= In_Data'Last
        and then
          (Filter.Stored_Next = Collecting_Block
           or else Filter.Stored_Next = Fixed_Collecting_Block
           or else Filter.Stored_Next = Dynamic_Collecting_Block)
        and then not Filter.Finish_Requested
      loop
         Filter.Block (Ada.Streams.Stream_Element_Offset (Filter.Block_Count)) := In_Data (Next_Input);
         Update_Compression_Checksum (Filter, In_Data (Next_Input));
         Filter.Block_Count := Filter.Block_Count + 1;
         In_Last := Next_Input;

         if Filter.Block_Count = Max_Compress_Block_Size then
            Start_Compression_Block_Emission (Filter, Final => False);
            return;
         end if;

         if Next_Input = In_Data'Last then
            return;
         end if;

         Next_Input := Next_Input + 1;
      end loop;
   end Consume_Compression_Input;

   procedure Maybe_Start_Compression_Flush
     (Filter        : in out Compression_Filter_Type;
      Flush         : Flush_Mode;
      Flush_Started : in out Boolean) is
   begin
      if Flush = Finish then
         Filter.Finish_Requested := True;
      end if;

      if Filter.Finish_Requested and then Is_Compression_Collecting (Filter)
      then
         Start_Compression_Block_Emission (Filter, Final => True);
      elsif (Flush = Sync_Flush or else Flush = Full_Flush)
        and then not Flush_Started
        and then Is_Compression_Collecting (Filter)
      then
         Flush_Started := True;
         if Filter.Block_Count = 0 then
            Start_Empty_Stored_Flush_Marker (Filter);
         else
            Filter.Flush_Marker_Pending := True;
            Start_Compression_Block_Emission (Filter, Final => False);
         end if;
      end if;
   end Maybe_Start_Compression_Flush;

   procedure Compress
     (Filter   : in out Compression_Filter_Type;
      In_Data  : Ada.Streams.Stream_Element_Array;
      In_Last  : out Ada.Streams.Stream_Element_Offset;
      Out_Data : out Ada.Streams.Stream_Element_Array;
      Out_Last : out Ada.Streams.Stream_Element_Offset;
      Flush    : Flush_Mode := No_Flush)
   is
      Flush_Started : Boolean := False;
   begin
      In_Last := Before_First (In_Data);
      Out_Data := [others => 0];
      Out_Last := Before_First (Out_Data);

      Require_Compression_Usable (Filter);
      if Filter.State = Compression_Ended then
         if In_Data'Length = 0
           and then (Flush = No_Flush or else Flush = Finish)
         then
            return;
         else
            raise Status_Error;
         end if;
      end if;
      Require_Supported_Compression (Filter);

      loop
         declare
            Old_In   : constant Ada.Streams.Stream_Element_Offset := In_Last;
            Old_Out  : constant Ada.Streams.Stream_Element_Offset := Out_Last;
            Old_Next : constant Stored_Compress_State := Filter.Stored_Next;
         begin
            Emit_Compression_Output (Filter, Out_Data, Out_Last);
            exit when
              Compression_Output_Full (Out_Data, Out_Last)
              or else Filter.State = Compression_Ended;

            Consume_Compression_Input (Filter, In_Data, In_Last);
            exit when
              Compression_Output_Full (Out_Data, Out_Last)
              or else Filter.State = Compression_Ended;

            if (Flush = Finish
                or else Flush = Sync_Flush
                or else Flush = Full_Flush)
              and then (In_Data'Length = 0 or else In_Last >= In_Data'Last)
            then
               Maybe_Start_Compression_Flush (Filter, Flush, Flush_Started);
            else
               Maybe_Start_Compression_Flush (Filter, No_Flush, Flush_Started);
            end if;

            Emit_Compression_Output (Filter, Out_Data, Out_Last);

            exit when
              Compression_Output_Full (Out_Data, Out_Last)
              or else Filter.State = Compression_Ended;
            exit when
              Old_In = In_Last
              and then Old_Out = Out_Last
              and then Old_Next = Filter.Stored_Next;
         end;
      end loop;
   end Compress;

   procedure Compress_Flush
     (Filter   : in out Compression_Filter_Type;
      Out_Data : out Ada.Streams.Stream_Element_Array;
      Out_Last : out Ada.Streams.Stream_Element_Offset;
      Flush    : Flush_Mode := No_Flush)
   is
      Flush_Started : Boolean := False;
   begin
      Out_Data := [others => 0];
      Out_Last := Before_First (Out_Data);

      Require_Compression_Usable (Filter);
      if Filter.State = Compression_Ended then
         if Flush = Sync_Flush or else Flush = Full_Flush then
            raise Status_Error;
         end if;
         return;
      end if;
      Require_Supported_Compression (Filter);

      loop
         declare
            Old_Out  : constant Ada.Streams.Stream_Element_Offset := Out_Last;
            Old_Next : constant Stored_Compress_State := Filter.Stored_Next;
         begin
            Emit_Compression_Output (Filter, Out_Data, Out_Last);
            exit when
              Compression_Output_Full (Out_Data, Out_Last)
              or else Filter.State = Compression_Ended;

            Maybe_Start_Compression_Flush (Filter, Flush, Flush_Started);
            Emit_Compression_Output (Filter, Out_Data, Out_Last);

            exit when
              Compression_Output_Full (Out_Data, Out_Last)
              or else Filter.State = Compression_Ended;
            exit when
              Old_Out = Out_Last and then Old_Next = Filter.Stored_Next;
         end;
      end loop;
   end Compress_Flush;

   function Compress_Stream_End
     (Filter : Compression_Filter_Type) return Boolean is
   begin
      return
        Filter.State = Compression_Ended and then Filter.Stored_Next = Done;
   end Compress_Stream_End;

   procedure Compress_Close
     (Filter : in out Compression_Filter_Type; Ignore_Error : Boolean := False)
   is
      Complete : constant Boolean := Compress_Stream_End (Filter);
   begin
      case Filter.State is
         when Compression_Closed                                        =>
            if not Ignore_Error then
               raise Status_Error;
            end if;

         when Compression_Open | Compression_Failed | Compression_Ended =>
            Filter.State := Compression_Closed;
            Filter.Header := Zlib_Header;
            Filter.Mode := Auto;
            Filter.Level := Default_Level;
            Filter.Dictionary_Set := False;
            Filter.Dictionary_ID := 0;
            Reset_Compression_State (Filter);

            if not Complete and then not Ignore_Error then
               raise Zlib_Error;
            end if;
      end case;
   end Compress_Close;

   function To_Stream_Array
     (Input : Byte_Array) return Ada.Streams.Stream_Element_Array
   is
      Result :
        Ada.Streams.Stream_Element_Array
          (1 .. Ada.Streams.Stream_Element_Offset (Input'Length));
   begin
      for I in Input'Range loop
         Result (Ada.Streams.Stream_Element_Offset (I - Input'First + 1)) :=
           Ada.Streams.Stream_Element (Input (I));
      end loop;

      return Result;
   end To_Stream_Array;

   package Byte_Vectors is new
     Ada.Containers.Vectors (Index_Type => Natural, Element_Type => Byte);

   function To_Byte_Array (Data : Byte_Vectors.Vector) return Byte_Array is
   begin
      if Data.Is_Empty then
         declare
            Empty : constant Byte_Array (1 .. 0) := [others => 0];
         begin
            return Empty;
         end;
      end if;

      declare
         Result : Byte_Array (1 .. Natural (Data.Length));
         Out_I  : Natural := Result'First;
      begin
         for B of Data loop
            Result (Out_I) := B;
            Out_I := Out_I + 1;
         end loop;

         return Result;
      end;
   end To_Byte_Array;

   function Produced
     (Data : Ada.Streams.Stream_Element_Array;
      Last : Ada.Streams.Stream_Element_Offset) return Natural is
   begin
      if Data'Length = 0 or else Last = Before_First (Data) then
         return 0;
      else
         return Natural (Last - Data'First + 1);
      end if;
   end Produced;

   function Compress_With_Header
     (Input          : Byte_Array;
      Header         : Header_Type;
      Mode           : Compression_Mode;
      Status         : out Status_Code;
      Metadata       : GZip_Metadata := No_GZip_Metadata;
      Level          : Compression_Level := Default_Level;
      Dictionary_Set : Boolean := False;
      Dictionary_ID  : Interfaces.Unsigned_32 := 0) return Byte_Array
   is
      Filter     : Compression_Filter_Type;
      Output     : Byte_Vectors.Vector;
      In_Buffer  : constant Ada.Streams.Stream_Element_Array :=
        To_Stream_Array (Input);
      Next_Input : Ada.Streams.Stream_Element_Offset := In_Buffer'First;
      Out_Buffer : Ada.Streams.Stream_Element_Array (1 .. 8192);
      In_Last    : Ada.Streams.Stream_Element_Offset;
      Out_Last   : Ada.Streams.Stream_Element_Offset;
      Calls      : Natural := 0;

      procedure Append_Output
        (Buffer : Ada.Streams.Stream_Element_Array;
         Last   : Ada.Streams.Stream_Element_Offset)
      is
         Count : constant Natural := Produced (Buffer, Last);
      begin
         if Count = 0 then
            return;
         end if;

         for I in
           Buffer'First
           .. Buffer'First + Ada.Streams.Stream_Element_Offset (Count) - 1
         loop
            Output.Append (Byte (Buffer (I)));
         end loop;
      end Append_Output;

      function Empty_Result return Byte_Array is
         Empty : constant Byte_Array (1 .. 0) := [others => 0];
      begin
         return Empty;
      end Empty_Result;
   begin
      Status := Ok;
      Deflate_Init
        (Filter, Header => Header, Mode => Mode, Metadata => Metadata);
      Filter.Level := Level;
      if Dictionary_Set then
         if Header = Zlib.GZip or else Header = Raw_Deflate then
            raise Status_Error;
         end if;
         Filter.Dictionary_Set := True;
         Filter.Dictionary_ID := Dictionary_ID;
      end if;

      while In_Buffer'Length > 0 and then Next_Input <= In_Buffer'Last loop
         Compress
           (Filter   => Filter,
            In_Data  => In_Buffer (Next_Input .. In_Buffer'Last),
            In_Last  => In_Last,
            Out_Data => Out_Buffer,
            Out_Last => Out_Last,
            Flush    => No_Flush);
         Append_Output (Out_Buffer, Out_Last);

         if In_Last >= Next_Input then
            Next_Input := In_Last + 1;
         elsif Produced (Out_Buffer, Out_Last) = 0 then
            raise Zlib_Error;
         end if;

         Calls := Calls + 1;
         if Calls > 1_000_000 then
            raise Zlib_Error;
         end if;
      end loop;

      while not Compress_Stream_End (Filter) loop
         Compress_Flush
           (Filter   => Filter,
            Out_Data => Out_Buffer,
            Out_Last => Out_Last,
            Flush    => Finish);
         Append_Output (Out_Buffer, Out_Last);

         Calls := Calls + 1;
         if Calls > 1_000_000 then
            raise Zlib_Error;
         end if;
      end loop;

      Compress_Close (Filter, Ignore_Error => True);
      Status := Ok;
      return To_Byte_Array (Output);

   exception
      when Status_Error =>
         if Is_Open (Filter) then
            Compress_Close (Filter, Ignore_Error => True);
         end if;
         Status := Invalid_Header;
         return Empty_Result;

      when Zlib_Error =>
         if Is_Open (Filter) then
            Compress_Close (Filter, Ignore_Error => True);
         end if;
         Status := Unsupported_Method;
         return Empty_Result;

      when others =>
         if Is_Open (Filter) then
            Compress_Close (Filter, Ignore_Error => True);
         end if;
         Status := Unexpected_End_Of_Input;
         return Empty_Result;
   end Compress_With_Header;

   procedure Require_Usable (Filter : Filter_Type) is
   begin
      case Filter.State is
         when Open | Ended =>
            null;

         when Failed       =>
            raise Zlib_Error;

         when Closed       =>
            raise Status_Error;
      end case;
   end Require_Usable;

   procedure Inflate_Init
     (Filter : in out Filter_Type; Header : Header_Type := Default) is
   begin
      Inflate_Init
        (Filter => Filter, Header => Header, GZip_Mode => Single_Member);
   end Inflate_Init;

   procedure Inflate_Init
     (Filter    : in out Filter_Type;
      Header    : Header_Type;
      GZip_Mode : GZip_Member_Mode) is
   begin
      Zlib.Stream_Bits.Reset (Input_Bits (Filter).all);
      Zlib.Sliding_Window.Reset (Output_Window (Filter).all);
      Zlib.Stream_Inflate.Reset (Decoder_State (Filter).all);
      Filter.State := Open;
      Filter.Header := Header;
      Filter.GZip_Mode := GZip_Mode;
      Filter.Last_Status := Ok;
   end Inflate_Init;

   procedure Inflate_Set_Dictionary
     (Filter : in out Filter_Type; Dictionary : Byte_Array)
   is
      Effective_Header : constant Header_Type :=
        (if Filter.Header = Default then Zlib_Header else Filter.Header);
   begin
      if Filter.State /= Open then
         raise Status_Error;
      end if;

      if Effective_Header /= Zlib_Header
        or else
          not Zlib.Stream_Inflate.Can_Set_Dictionary
                (Decoder_State (Filter).all)
      then
         Filter.State := Failed;
         raise Status_Error;
      end if;

      declare
         Stream_Dictionary :
           Ada.Streams.Stream_Element_Array
             (1 .. Ada.Streams.Stream_Element_Offset (Dictionary'Length));
      begin
         for I in Dictionary'Range loop
            Stream_Dictionary
              (Ada.Streams.Stream_Element_Offset (I - Dictionary'First + 1)) :=
              Ada.Streams.Stream_Element (Dictionary (I));
         end loop;

         Zlib.Sliding_Window.Seed
           (Output_Window (Filter).all, Stream_Dictionary);
      end;

      Zlib.Stream_Inflate.Set_Dictionary_ID
        (Decoder_State (Filter).all, Zlib.Checksums.Adler32 (Dictionary));
   end Inflate_Set_Dictionary;

   function Is_Open (Filter : Filter_Type) return Boolean is
   begin
      return
        Filter.State = Open
        or else Filter.State = Failed
        or else Filter.State = Ended;
   end Is_Open;

   procedure Mark_Failed
     (Filter : in out Filter_Type;
      Status : Status_Code := Unexpected_End_Of_Input) is
   begin
      Filter.Last_Status := Status;
      Filter.State := Failed;
   end Mark_Failed;

   function Has_Buffered_Input (Filter : in out Filter_Type) return Boolean is
   begin
      return Zlib.Stream_Bits.Buffered_Bytes (Input_Bits (Filter).all) > 0;
   end Has_Buffered_Input;

   type Member_Finish_Action is
     (Return_To_Caller, Continue_Decoding, Logical_End);

   procedure Finish_GZip_Member
     (Filter              : in out Filter_Type;
      Flush               : Flush_Mode;
      Has_Input_To_Append : Boolean;
      Action              : out Member_Finish_Action) is
   begin
      Action := Return_To_Caller;

      if Filter.Header /= Zlib.GZip then
         Filter.State := Ended;
         Action := Logical_End;
         return;
      end if;

      case Filter.GZip_Mode is
         when Single_Member =>
            if Flush = Finish
              and then
                (Has_Buffered_Input (Filter) or else Has_Input_To_Append)
            then
               Mark_Failed (Filter, Invalid_Header);
               raise Zlib_Error;
            end if;

            Filter.State := Ended;
            Action := Logical_End;

         when Multi_Member  =>
            if Has_Buffered_Input (Filter) or else Has_Input_To_Append then
               Zlib.Stream_Inflate.Reset_GZip_Member
                 (Decoder_State (Filter).all);
               Action := Continue_Decoding;
            elsif Flush = Finish then
               Filter.State := Ended;
               Action := Logical_End;
            else
               --  A gzip member completed, but another member may arrive in a
               --  later Translate call.  Return to the caller instead of
               --  spinning on the internal Wrapper = Done state.
               Action := Return_To_Caller;
            end if;
      end case;
   end Finish_GZip_Member;

   procedure Translate
     (Filter   : in out Filter_Type;
      In_Data  : Ada.Streams.Stream_Element_Array;
      In_Last  : out Ada.Streams.Stream_Element_Offset;
      Out_Data : out Ada.Streams.Stream_Element_Array;
      Out_Last : out Ada.Streams.Stream_Element_Offset;
      Flush    : Flush_Mode := No_Flush)
   is
      Decode_Status : Zlib.Stream_Inflate.Decode_Status;
      Next_Input    : Ada.Streams.Stream_Element_Offset := In_Data'First;

      function Has_Input_To_Append return Boolean is
      begin
         return
           In_Data'Length > 0
           and then
             (In_Last = Before_First (In_Data) or else In_Last < In_Data'Last);
      end Has_Input_To_Append;

      function Output_Buffer_Full return Boolean is
      begin
         return Out_Data'Length > 0 and then Out_Last = Out_Data'Last;
      end Output_Buffer_Full;

      procedure Append_One_Input_Byte is
         One : Ada.Streams.Stream_Element_Array (1 .. 1);
      begin
         if In_Last /= Before_First (In_Data) then
            Next_Input := In_Last + 1;
         end if;

         One (1) := In_Data (Next_Input);
         Zlib.Stream_Bits.Append (Input_Bits (Filter).all, One);
         In_Last := Next_Input;

         if Next_Input < In_Data'Last then
            Next_Input := Next_Input + 1;
         else
            Next_Input := In_Data'Last;
         end if;
      end Append_One_Input_Byte;
   begin
      In_Last := Before_First (In_Data);
      Out_Data := [others => 0];
      Out_Last := Before_First (Out_Data);

      Require_Usable (Filter);

      if Out_Data'Length = 0 then
         if Flush = Finish and then not Stream_End (Filter) then
            Mark_Failed (Filter);
            raise Zlib_Error;
         end if;

         return;
      end if;

      loop
         Zlib.Sliding_Window.Drain_Append
           (Output_Window (Filter).all, Out_Data, Out_Last);

         if Output_Buffer_Full then
            return;
         end if;

         begin
            Zlib.Stream_Inflate.Decode
              (Decoder_State (Filter).all,
               Filter.Header,
               Input_Bits (Filter).all,
               Output_Window (Filter).all,
               Decode_Status);
         exception
            when others =>
               Mark_Failed
                 (Filter,
                  Zlib.Stream_Inflate.Last_Status
                    (Decoder_State (Filter).all));
               raise Zlib_Error;
         end;

         Zlib.Sliding_Window.Drain_Append
           (Output_Window (Filter).all, Out_Data, Out_Last);

         if Output_Buffer_Full then
            return;
         end if;

         case Decode_Status is
            when Zlib.Stream_Inflate.Member_End     =>
               declare
                  Action : Member_Finish_Action;
               begin
                  Finish_GZip_Member
                    (Filter              => Filter,
                     Flush               => Flush,
                     Has_Input_To_Append => Has_Input_To_Append,
                     Action              => Action);

                  case Action is
                     when Logical_End | Return_To_Caller =>
                        return;

                     when Continue_Decoding              =>
                        null;
                  end case;
               end;

            when Zlib.Stream_Inflate.Stream_End     =>
               Filter.State := Ended;
               return;

            when Zlib.Stream_Inflate.Need_Output    =>
               return;

            when Zlib.Stream_Inflate.Need_Input     =>
               if Has_Input_To_Append then
                  begin
                     Append_One_Input_Byte;
                  exception
                     when others =>
                        Mark_Failed (Filter, Unexpected_End_Of_Input);
                        raise Zlib_Error;
                  end;
               elsif Flush = Finish then
                  Mark_Failed (Filter, Unexpected_End_Of_Input);
                  raise Zlib_Error;
               else
                  return;
               end if;

            when Zlib.Stream_Inflate.Unsupported
               | Zlib.Stream_Inflate.Malformed
               | Zlib.Stream_Inflate.Checksum_Error =>
               Mark_Failed
                 (Filter,
                  Zlib.Stream_Inflate.Last_Status
                    (Decoder_State (Filter).all));
               raise Zlib_Error;

            when Zlib.Stream_Inflate.Ok             =>
               if Out_Last /= Before_First (Out_Data) then
                  return;
               end if;
         end case;
      end loop;
   end Translate;

   procedure Flush
     (Filter   : in out Filter_Type;
      Out_Data : out Ada.Streams.Stream_Element_Array;
      Out_Last : out Ada.Streams.Stream_Element_Offset;
      Flush    : Flush_Mode := No_Flush)
   is
      Decode_Status : Zlib.Stream_Inflate.Decode_Status;

      function Output_Buffer_Full return Boolean is
      begin
         return Out_Data'Length > 0 and then Out_Last = Out_Data'Last;
      end Output_Buffer_Full;

   begin
      Out_Data := [others => 0];
      Out_Last := Before_First (Out_Data);

      Require_Usable (Filter);

      if Out_Data'Length = 0 then
         if Flush = Finish and then not Stream_End (Filter) then
            Mark_Failed (Filter);
            raise Zlib_Error;
         end if;

         return;
      end if;

      loop
         Zlib.Sliding_Window.Drain_Append
           (Output_Window (Filter).all, Out_Data, Out_Last);

         if Output_Buffer_Full then
            return;
         end if;

         begin
            Zlib.Stream_Inflate.Decode
              (Decoder_State (Filter).all,
               Filter.Header,
               Input_Bits (Filter).all,
               Output_Window (Filter).all,
               Decode_Status);
         exception
            when others =>
               Mark_Failed
                 (Filter,
                  Zlib.Stream_Inflate.Last_Status
                    (Decoder_State (Filter).all));
               raise Zlib_Error;
         end;

         Zlib.Sliding_Window.Drain_Append
           (Output_Window (Filter).all, Out_Data, Out_Last);

         if Output_Buffer_Full then
            return;
         end if;

         case Decode_Status is
            when Zlib.Stream_Inflate.Member_End     =>
               declare
                  Action : Member_Finish_Action;
               begin
                  Finish_GZip_Member
                    (Filter              => Filter,
                     Flush               => Flush,
                     Has_Input_To_Append => False,
                     Action              => Action);

                  case Action is
                     when Logical_End | Return_To_Caller =>
                        return;

                     when Continue_Decoding              =>
                        null;
                  end case;
               end;

            when Zlib.Stream_Inflate.Stream_End     =>
               Filter.State := Ended;
               return;

            when Zlib.Stream_Inflate.Need_Output    =>
               return;

            when Zlib.Stream_Inflate.Need_Input     =>
               if Flush = Finish then
                  Mark_Failed (Filter, Unexpected_End_Of_Input);
                  raise Zlib_Error;
               else
                  return;
               end if;

            when Zlib.Stream_Inflate.Unsupported
               | Zlib.Stream_Inflate.Malformed
               | Zlib.Stream_Inflate.Checksum_Error =>
               Mark_Failed
                 (Filter,
                  Zlib.Stream_Inflate.Last_Status
                    (Decoder_State (Filter).all));
               raise Zlib_Error;

            when Zlib.Stream_Inflate.Ok             =>
               if Out_Last /= Before_First (Out_Data) then
                  return;
               end if;
         end case;
      end loop;
   end Flush;

   function Stream_End (Filter : Filter_Type) return Boolean is
   begin
      if Filter.State /= Ended then
         return False;
      end if;

      if Filter.Output /= System.Null_Address
        and then
          Zlib.Sliding_Window.Pending_Output
            (Window_Addresses.To_Pointer (Filter.Output).all)
          > 0
      then
         return False;
      end if;

      return True;
   end Stream_End;

   procedure Release_State (Filter : in out Filter_Type) is
   begin
      if Filter.Input_Bits /= System.Null_Address then
         declare
            Source : Bit_Source_Addresses.Object_Pointer :=
              Bit_Source_Addresses.To_Pointer (Filter.Input_Bits);
         begin
            Zlib.Stream_Bits.Reset (Source.all);
            Free (Source);
            Filter.Input_Bits := System.Null_Address;
         end;
      end if;

      if Filter.Output /= System.Null_Address then
         declare
            W : Window_Addresses.Object_Pointer :=
              Window_Addresses.To_Pointer (Filter.Output);
         begin
            Zlib.Sliding_Window.Reset (W.all);
            Free (W);
            Filter.Output := System.Null_Address;
         end;
      end if;

      if Filter.Decoder /= System.Null_Address then
         declare
            D : Decoder_Addresses.Object_Pointer :=
              Decoder_Addresses.To_Pointer (Filter.Decoder);
         begin
            Zlib.Stream_Inflate.Reset (D.all);
            Free (D);
            Filter.Decoder := System.Null_Address;
         end;
      end if;

      Filter.State := Closed;
      Filter.Header := Default;
      Filter.GZip_Mode := Single_Member;
      Filter.Last_Status := Ok;
   end Release_State;

   procedure Close
     (Filter : in out Filter_Type; Ignore_Error : Boolean := False)
   is
      Was_Incomplete : Boolean := False;
   begin
      case Filter.State is
         when Closed       =>
            if not Ignore_Error then
               raise Status_Error;
            end if;

         when Failed       =>
            Release_State (Filter);
            if not Ignore_Error then
               raise Zlib_Error;
            end if;

         when Open | Ended =>
            Was_Incomplete := not Stream_End (Filter);
            Release_State (Filter);

            if Was_Incomplete and then not Ignore_Error then
               raise Zlib_Error;
            end if;
      end case;
   end Close;

   function Status_Image (Status : Status_Code) return String
     with SPARK_Mode => On
   is
   begin
      case Status is
         when Ok                            =>
            return "ok";

         when Invalid_Header                =>
            return "invalid zlib header";

         when Unsupported_Method            =>
            return "unsupported compression method";

         when Unsupported_Preset_Dictionary =>
            return "unsupported preset dictionary";

         when Invalid_Checksum              =>
            return "invalid checksum";

         when Invalid_Block_Type            =>
            return "invalid or unsupported Deflate block type";

         when Invalid_Stored_Block          =>
            return "invalid stored Deflate block";

         when Invalid_Huffman_Code          =>
            return "invalid Huffman code";

         when Invalid_Distance              =>
            return "invalid LZ77 distance";

         when Unexpected_End_Of_Input       =>
            return "unexpected end of input";

         when Input_File_Error              =>
            return "input file error";

         when Output_File_Error             =>
            return "output file error";
      end case;
   end Status_Image;

   function Inflate_Internal
     (Input          : Byte_Array;
      Header         : Header_Type;
      GZip_Mode      : GZip_Member_Mode;
      Status         : out Status_Code;
      Dictionary     : Byte_Array;
      Use_Dictionary : Boolean;
      Require_All_Input : Boolean := False;
      Extra_Input_Status : Status_Code := Invalid_Header) return Byte_Array
   is
      Filter        : Filter_Type;
      Output        : Byte_Vectors.Vector;
      In_Buffer     : constant Ada.Streams.Stream_Element_Array :=
        To_Stream_Array (Input);
      Next_Input    : Ada.Streams.Stream_Element_Offset := In_Buffer'First;
      Out_Buffer    : Ada.Streams.Stream_Element_Array (1 .. 32_768);
      In_Last       : Ada.Streams.Stream_Element_Offset;
      Out_Last      : Ada.Streams.Stream_Element_Offset;
      Finished      : Boolean := False;
      Made_Progress : Boolean;

      procedure Append_Output
        (Buffer : Ada.Streams.Stream_Element_Array;
         Last   : Ada.Streams.Stream_Element_Offset)
      is
         Count : constant Natural := Produced (Buffer, Last);
      begin
         if Count = 0 then
            return;
         end if;

         for I in
           Buffer'First
           .. Buffer'First + Ada.Streams.Stream_Element_Offset (Count) - 1
         loop
            Output.Append (Byte (Buffer (I)));
         end loop;
      end Append_Output;

      function Empty_Result return Byte_Array is
         Empty : constant Byte_Array (1 .. 0) := [others => 0];
      begin
         return Empty;
      end Empty_Result;
   begin
      Status := Ok;
      Inflate_Init
        (Filter => Filter, Header => Header, GZip_Mode => GZip_Mode);

      if Use_Dictionary then
         Inflate_Set_Dictionary (Filter, Dictionary);
      end if;

      while not Finished loop
         Made_Progress := False;

         if In_Buffer'Length > 0 and then Next_Input <= In_Buffer'Last then
            declare
               Before_Input : constant Ada.Streams.Stream_Element_Offset :=
                 Next_Input;
               Before_Count : constant Ada.Containers.Count_Type :=
                 Output.Length;
            begin
               Translate
                 (Filter   => Filter,
                  In_Data  => In_Buffer (Next_Input .. In_Buffer'Last),
                  In_Last  => In_Last,
                  Out_Data => Out_Buffer,
                  Out_Last => Out_Last,
                  Flush    => No_Flush);

               Append_Output (Out_Buffer, Out_Last);

               if In_Last >= Before_Input then
                  Next_Input := In_Last + 1;
                  Made_Progress := True;
               end if;

               if Output.Length /= Before_Count then
                  Made_Progress := True;
               end if;
            end;
         else
            declare
               Before_Count : constant Ada.Containers.Count_Type :=
                 Output.Length;
            begin
               Flush
                 (Filter   => Filter,
                  Out_Data => Out_Buffer,
                  Out_Last => Out_Last,
                  Flush    => Finish);

               Append_Output (Out_Buffer, Out_Last);

               if Output.Length /= Before_Count then
                  Made_Progress := True;
               end if;
            end;
         end if;

         Finished := Stream_End (Filter);

         if not Finished and then not Made_Progress then
            Filter.Last_Status := Unexpected_End_Of_Input;
            raise Zlib_Error;
         end if;
      end loop;

      if Header = Zlib.GZip
        and then GZip_Mode = Single_Member
        and then In_Buffer'Length > 0
        and then Next_Input <= In_Buffer'Last
      then
         Close (Filter, Ignore_Error => True);
         Status := Invalid_Header;
         return To_Byte_Array (Output);
      end if;

      if Require_All_Input
        and then In_Buffer'Length > 0
        and then Next_Input <= In_Buffer'Last
      then
         Close (Filter, Ignore_Error => True);
         Status := Extra_Input_Status;
         return To_Byte_Array (Output);
      end if;

      Close (Filter, Ignore_Error => True);
      Status := Ok;
      return To_Byte_Array (Output);

   exception
      when Zlib_Error =>
         Status := Filter.Last_Status;
         if Status = Ok then
            Status := Unexpected_End_Of_Input;
         end if;

         if Is_Open (Filter) then
            Close (Filter, Ignore_Error => True);
         end if;

         return To_Byte_Array (Output);

      when Status_Error =>
         Status := Unexpected_End_Of_Input;
         if Is_Open (Filter) then
            Close (Filter, Ignore_Error => True);
         end if;
         return Empty_Result;

      when others =>
         Status := Unexpected_End_Of_Input;
         if Is_Open (Filter) then
            Close (Filter, Ignore_Error => True);
         end if;
         return Empty_Result;
   end Inflate_Internal;

   function Inflate
     (Input : Byte_Array; Status : out Status_Code) return Byte_Array is
   begin
      declare
         Empty : constant Byte_Array (1 .. 0) := [others => 0];
      begin
         return
           Inflate_Internal
             (Input, Zlib_Header, Single_Member, Status, Empty, False);
      end;
   end Inflate;

   function Inflate_With_Header
     (Input : Byte_Array; Header : Header_Type; Status : out Status_Code)
      return Byte_Array is
   begin
      declare
         Empty : constant Byte_Array (1 .. 0) := [others => 0];
      begin
         return
           Inflate_Internal
             (Input, Header, Single_Member, Status, Empty, False);
      end;
   end Inflate_With_Header;

   function Inflate_Auto
     (Input : Byte_Array; Status : out Status_Code) return Byte_Array is
   begin
      if Looks_Like_Zlib_Header (Input) then
         return Inflate_With_Header (Input, Zlib_Header, Status);
      elsif Looks_Like_GZip_Header (Input) then
         return Inflate_With_Header (Input, GZip, Multi_Member, Status);
      else
         return Inflate_Raw (Input, Status);
      end if;
   end Inflate_Auto;

   function Inflate_Raw
     (Input : Byte_Array; Status : out Status_Code) return Byte_Array is
   begin
      return
        Inflate_With_Header
          (Input => Input, Header => Raw_Deflate, Status => Status);
   end Inflate_Raw;

   function Inflate_Raw_Exact
     (Input : Byte_Array; Status : out Status_Code) return Byte_Array is
   begin
      declare
         Empty : constant Byte_Array (1 .. 0) := [others => 0];
      begin
         return
           Inflate_Internal
             (Input              => Input,
              Header             => Raw_Deflate,
              GZip_Mode          => Single_Member,
              Status             => Status,
              Dictionary         => Empty,
              Use_Dictionary     => False,
              Require_All_Input  => True,
              Extra_Input_Status => Unsupported_Method);
      end;
   end Inflate_Raw_Exact;

   function Inflate_With_Header
     (Input     : Byte_Array;
      Header    : Header_Type;
      GZip_Mode : GZip_Member_Mode;
      Status    : out Status_Code) return Byte_Array is
   begin
      declare
         Empty : constant Byte_Array (1 .. 0) := [others => 0];
      begin
         return
           Inflate_Internal (Input, Header, GZip_Mode, Status, Empty, False);
      end;
   end Inflate_With_Header;

   function Inflate_With_Dictionary
     (Input : Byte_Array; Dictionary : Byte_Array; Status : out Status_Code)
      return Byte_Array is
   begin
      return
        Inflate_Internal
          (Input          => Input,
           Header         => Zlib_Header,
           GZip_Mode      => Single_Member,
           Status         => Status,
           Dictionary     => Dictionary,
           Use_Dictionary => True);
   end Inflate_With_Dictionary;

   function Read_File
     (Path : String; Status : out Status_Code) return Byte_Array
   is
      File : SIO.File_Type;
   begin
      if not Ada.Directories.Exists (Path) then
         Status := Input_File_Error;
         declare
            Empty : constant Byte_Array (1 .. 0) := [others => 0];
         begin
            return Empty;
         end;
      end if;

      SIO.Open (File, SIO.In_File, Path);

      declare
         Size : constant Natural := Natural (SIO.Size (File));
      begin
         if Size = 0 then
            SIO.Close (File);
            Status := Ok;

            declare
               Empty : constant Byte_Array (1 .. 0) := [others => 0];
            begin
               return Empty;
            end;
         end if;

         declare
            Buffer :
              Ada.Streams.Stream_Element_Array
                (1 .. Ada.Streams.Stream_Element_Offset (Size));
            Last   : Ada.Streams.Stream_Element_Offset;
         begin
            SIO.Read (File, Buffer, Last);
            SIO.Close (File);

            declare
               Result : Byte_Array (1 .. Size);
            begin
               for I in Result'Range loop
                  Result (I) :=
                    Byte (Buffer (Ada.Streams.Stream_Element_Offset (I)));
               end loop;

               Status := Ok;
               return Result;
            end;
         end;
      end;

   exception
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;

         Status := Input_File_Error;

         declare
            Empty : constant Byte_Array (1 .. 0) := [others => 0];
         begin
            return Empty;
         end;
   end Read_File;

   procedure Write_File
     (Path : String; Data : Byte_Array; Status : out Status_Code)
   is
      File : SIO.File_Type;
   begin
      SIO.Create (File, SIO.Out_File, Path);

      if Data'Length > 0 then
         declare
            Buffer :
              Ada.Streams.Stream_Element_Array
                (1 .. Ada.Streams.Stream_Element_Offset (Data'Length));
         begin
            for I in Data'Range loop
               Buffer
                 (Ada.Streams.Stream_Element_Offset (I - Data'First + 1)) :=
                 Ada.Streams.Stream_Element (Data (I));
            end loop;

            SIO.Write (File, Buffer);
         end;
      end if;

      SIO.Close (File);
      Status := Ok;

   exception
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;

         Status := Output_File_Error;
   end Write_File;

   function Is_ZIP_External_Method
     (Method : Interfaces.Unsigned_16) return Boolean is
   begin
      return Method = 12
        or else Method = 14
        or else Method = 20
        or else Method = 93
        or else Method = 98;
   end Is_ZIP_External_Method;

   function ZIP_External_Method_Name
     (Method : Interfaces.Unsigned_16) return String is
   begin
      case Method is
         when 12 =>
            return "BZip2";
         when 14 =>
            return "LZMA";
         when 20 | 93 =>
            return "ZSTD";
         when 98 =>
            return "PPMd";
         when others =>
            return "";
      end case;
   end ZIP_External_Method_Name;

   function ZIP_U16_At
     (Data : Byte_Array;
      Pos  : Natural) return Interfaces.Unsigned_16;

   function ZIP_U32_At
     (Data : Byte_Array;
      Pos  : Natural) return Interfaces.Unsigned_32;

   function ZIP_U64_At
     (Data : Byte_Array;
      Pos  : Natural) return Interfaces.Unsigned_64;

   function ZIP_Name_Equals
     (Data       : Byte_Array;
      Name_First : Natural;
      Name_Len   : Natural;
      Name       : String) return Boolean
   is
   begin
      if Name_Len /= Name'Length then
         return False;
      end if;

      for I in 0 .. Name_Len - 1 loop
         if Character'Val (Data (Name_First + I)) /= Name (Name'First + I) then
            return False;
         end if;
      end loop;

      return True;
   exception
      when others =>
         return False;
   end ZIP_Name_Equals;

   function Resolve_ZIP64_Central_Fields
     (Data            : Byte_Array;
      Extra_First     : Natural;
      Extra_Len       : Natural;
      Compressed_32   : Interfaces.Unsigned_32;
      Uncompressed_32 : Interfaces.Unsigned_32;
      Local_Offset_32 : Interfaces.Unsigned_32;
      Compressed      : out Interfaces.Unsigned_64;
      Uncompressed    : out Interfaces.Unsigned_64;
      Local_Offset    : out Interfaces.Unsigned_64) return Boolean
   is
      Need_Compressed   : constant Boolean := Compressed_32 = 16#FFFF_FFFF#;
      Need_Uncompressed : constant Boolean := Uncompressed_32 = 16#FFFF_FFFF#;
      Need_Offset       : constant Boolean := Local_Offset_32 = 16#FFFF_FFFF#;
      Extra_After       : constant Natural := Extra_First + Extra_Len;
      Pos               : Natural := Extra_First;
   begin
      Compressed := Interfaces.Unsigned_64 (Compressed_32);
      Uncompressed := Interfaces.Unsigned_64 (Uncompressed_32);
      Local_Offset := Interfaces.Unsigned_64 (Local_Offset_32);

      if not Need_Compressed
        and then not Need_Uncompressed
        and then not Need_Offset
      then
         return True;
      end if;

      if Extra_Len = 0
        or else Extra_First < Data'First
        or else Extra_After - 1 > Data'Last
      then
         return False;
      end if;

      while Pos + 3 < Extra_After loop
         declare
            Header_ID : constant Interfaces.Unsigned_16 := ZIP_U16_At (Data, Pos);
            Field_Len : constant Natural := Natural (ZIP_U16_At (Data, Pos + 2));
            Field     : constant Natural := Pos + 4;
            Field_After : constant Natural := Field + Field_Len;
         begin
            if Field_After > Extra_After then
               return False;
            end if;

            if Header_ID = 16#0001# then
               declare
                  Cursor : Natural := Field;
               begin
                  if Need_Uncompressed then
                     if Cursor + 7 >= Field_After then
                        return False;
                     end if;
                     Uncompressed := ZIP_U64_At (Data, Cursor);
                     Cursor := Cursor + 8;
                  end if;

                  if Need_Compressed then
                     if Cursor + 7 >= Field_After then
                        return False;
                     end if;
                     Compressed := ZIP_U64_At (Data, Cursor);
                     Cursor := Cursor + 8;
                  end if;

                  if Need_Offset then
                     if Cursor + 7 >= Field_After then
                        return False;
                     end if;
                     Local_Offset := ZIP_U64_At (Data, Cursor);
                  end if;

                  return True;
               end;
            end if;

            Pos := Field_After;
         end;
      end loop;

      return False;
   exception
      when others =>
         return False;
   end Resolve_ZIP64_Central_Fields;

   function Extract_ZIP_Native_BZip2_Entry
     (Archive_Image : Byte_Array;
      Entry_Name    : String;
      Status        : out Status_Code) return Byte_Array
   is
      Empty : constant Byte_Array (1 .. 0) := [others => 0];
      Pos   : Natural := Archive_Image'First;
      Found_BZip2_Name : Boolean := False;
   begin
      Status := Unsupported_Method;

      if Entry_Name'Length = 0 or else Archive_Image'Length < 46 then
         return Empty;
      end if;

      while Pos <= Archive_Image'Last - 45 loop
         if ZIP_U32_At (Archive_Image, Pos) = 16#0201_4B50# then
            declare
               Flags            : constant Interfaces.Unsigned_16 :=
                 ZIP_U16_At (Archive_Image, Pos + 8);
               Method           : constant Interfaces.Unsigned_16 :=
                 ZIP_U16_At (Archive_Image, Pos + 10);
               Crc              : constant Interfaces.Unsigned_32 :=
                 ZIP_U32_At (Archive_Image, Pos + 16);
               Compressed_32    : constant Interfaces.Unsigned_32 :=
                 ZIP_U32_At (Archive_Image, Pos + 20);
               Uncompressed_32  : constant Interfaces.Unsigned_32 :=
                 ZIP_U32_At (Archive_Image, Pos + 24);
               Name_Len         : constant Natural :=
                 Natural (ZIP_U16_At (Archive_Image, Pos + 28));
               Extra_Len        : constant Natural :=
                 Natural (ZIP_U16_At (Archive_Image, Pos + 30));
               Comment_Len      : constant Natural :=
                 Natural (ZIP_U16_At (Archive_Image, Pos + 32));
               Local_Offset_32  : constant Interfaces.Unsigned_32 :=
                 ZIP_U32_At (Archive_Image, Pos + 42);
               Name_First       : constant Natural := Pos + 46;
               Record_After     : constant Natural :=
                 Name_First + Name_Len + Extra_Len + Comment_Len;
            begin
               if Record_After - 1 > Archive_Image'Last then
                  Status := Unexpected_End_Of_Input;
                  return Empty;
               end if;

               if ZIP_Name_Equals
                 (Archive_Image, Name_First, Name_Len, Entry_Name)
               then
                  if Method /= 12 then
                     return Empty;
                  end if;

                  Found_BZip2_Name := True;
                  if (Flags and 1) /= 0 then
                     Status := Unsupported_Method;
                     return Empty;
                  end if;

                  declare
                     Compressed   : Interfaces.Unsigned_64 := 0;
                     Uncompressed : Interfaces.Unsigned_64 := 0;
                     Local_Offset : Interfaces.Unsigned_64 := 0;
                  begin
                     if not Resolve_ZIP64_Central_Fields
                       (Archive_Image,
                        Name_First + Name_Len,
                        Extra_Len,
                        Compressed_32,
                        Uncompressed_32,
                        Local_Offset_32,
                        Compressed,
                        Uncompressed,
                        Local_Offset)
                       or else Compressed >
                         Interfaces.Unsigned_64 (Interfaces.C.unsigned'Last)
                       or else Uncompressed >
                         Interfaces.Unsigned_64 (Interfaces.C.unsigned'Last)
                       or else Local_Offset > Interfaces.Unsigned_64 (Natural'Last)
                     then
                        Status := Unsupported_Method;
                        return Empty;
                     end if;

                     declare
                        Local : constant Natural :=
                          Archive_Image'First + Natural (Local_Offset);
                     begin
                        if Local < Archive_Image'First
                          or else Local + 29 > Archive_Image'Last
                          or else ZIP_U32_At (Archive_Image, Local) /=
                            16#0403_4B50#
                          or else ZIP_U16_At (Archive_Image, Local + 8) /= 12
                        then
                           Status := Unexpected_End_Of_Input;
                           return Empty;
                        end if;

                        declare
                           Local_Name_Len  : constant Natural :=
                             Natural (ZIP_U16_At (Archive_Image, Local + 26));
                           Local_Extra_Len : constant Natural :=
                             Natural (ZIP_U16_At (Archive_Image, Local + 28));
                           Payload_First   : constant Natural :=
                             Local + 30 + Local_Name_Len + Local_Extra_Len;
                           Payload_Len     : constant Natural :=
                             Natural (Compressed);
                           Plain_Len       : constant Natural :=
                             Natural (Uncompressed);
                        begin
                           if Payload_Len = 0
                             or else Payload_First > Archive_Image'Last
                             or else Payload_Len - 1 >
                               Archive_Image'Last - Payload_First
                           then
                              Status := Unexpected_End_Of_Input;
                              return Empty;
                           end if;

                           declare
                              Output_Count : constant Positive :=
                                Natural'Max (1, Plain_Len);
                              Output       : Byte_Array (1 .. Output_Count);
                              Output_Len   : aliased Interfaces.C.unsigned :=
                                Interfaces.C.unsigned (Plain_Len);
                              Result       : Interfaces.C.int;
                           begin
                              Result :=
                                BZ2_bzBuffToBuffDecompress
                                  (Dest       => Output (Output'First)'Address,
                                   Dest_Len   => Output_Len'Access,
                                   Source     =>
                                     Archive_Image (Payload_First)'Address,
                                   Source_Len =>
                                     Interfaces.C.unsigned (Payload_Len),
                                   Small      => 0,
                                   Verbosity  => 0);

                              if Result /= 0
                                or else Natural (Output_Len) /= Plain_Len
                              then
                                 Status := Invalid_Block_Type;
                                 return Empty;
                              end if;

                              if Plain_Len = 0 then
                                 if Crc /= 0 then
                                    Status := Invalid_Checksum;
                                 else
                                    Status := Ok;
                                 end if;
                                 return Empty;
                              end if;

                              declare
                                 Plain : Byte_Array (1 .. Plain_Len);
                              begin
                                 for I in Plain'Range loop
                                    Plain (I) := Output (I);
                                 end loop;

                                 if Zlib.CRC32 (Plain) /= Crc then
                                    Status := Invalid_Checksum;
                                    return Empty;
                                 end if;

                                 Status := Ok;
                                 return Plain;
                              end;
                           end;
                        end;
                     end;
                  end;
               end if;

               Pos := Record_After;
            end;
         else
            Pos := Pos + 1;
         end if;
      end loop;

      Status := (if Found_BZip2_Name then Invalid_Block_Type else Unsupported_Method);
      return Empty;
   exception
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end Extract_ZIP_Native_BZip2_Entry;

   function Extract_ZIP_Native_Zstd_Entry
     (Archive_Image : Byte_Array;
      Entry_Name    : String;
      Status        : out Status_Code) return Byte_Array
   is
      Empty : constant Byte_Array (1 .. 0) := [others => 0];
      Pos   : Natural := Archive_Image'First;
      Found_Zstd_Name : Boolean := False;
   begin
      Status := Unsupported_Method;

      if Entry_Name'Length = 0 or else Archive_Image'Length < 46 then
         return Empty;
      end if;

      while Pos <= Archive_Image'Last - 45 loop
         if ZIP_U32_At (Archive_Image, Pos) = 16#0201_4B50# then
            declare
               Flags            : constant Interfaces.Unsigned_16 :=
                 ZIP_U16_At (Archive_Image, Pos + 8);
               Method           : constant Interfaces.Unsigned_16 :=
                 ZIP_U16_At (Archive_Image, Pos + 10);
               Crc              : constant Interfaces.Unsigned_32 :=
                 ZIP_U32_At (Archive_Image, Pos + 16);
               Compressed_32    : constant Interfaces.Unsigned_32 :=
                 ZIP_U32_At (Archive_Image, Pos + 20);
               Uncompressed_32  : constant Interfaces.Unsigned_32 :=
                 ZIP_U32_At (Archive_Image, Pos + 24);
               Name_Len         : constant Natural :=
                 Natural (ZIP_U16_At (Archive_Image, Pos + 28));
               Extra_Len        : constant Natural :=
                 Natural (ZIP_U16_At (Archive_Image, Pos + 30));
               Comment_Len      : constant Natural :=
                 Natural (ZIP_U16_At (Archive_Image, Pos + 32));
               Local_Offset_32  : constant Interfaces.Unsigned_32 :=
                 ZIP_U32_At (Archive_Image, Pos + 42);
               Name_First       : constant Natural := Pos + 46;
               Record_After     : constant Natural :=
                 Name_First + Name_Len + Extra_Len + Comment_Len;
            begin
               if Record_After - 1 > Archive_Image'Last then
                  Status := Unexpected_End_Of_Input;
                  return Empty;
               end if;

               if ZIP_Name_Equals
                 (Archive_Image, Name_First, Name_Len, Entry_Name)
               then
                  if Method /= 20 and then Method /= 93 then
                     return Empty;
                  end if;

                  Found_Zstd_Name := True;
                  if (Flags and 1) /= 0 then
                     Status := Unsupported_Method;
                     return Empty;
                  end if;

                  declare
                     Compressed   : Interfaces.Unsigned_64 := 0;
                     Uncompressed : Interfaces.Unsigned_64 := 0;
                     Local_Offset : Interfaces.Unsigned_64 := 0;
                  begin
                     if not Resolve_ZIP64_Central_Fields
                       (Archive_Image,
                        Name_First + Name_Len,
                        Extra_Len,
                        Compressed_32,
                        Uncompressed_32,
                        Local_Offset_32,
                       Compressed,
                       Uncompressed,
                       Local_Offset)
                       or else Compressed >
                         Interfaces.Unsigned_64 (Natural'Last)
                       or else Uncompressed >
                         Interfaces.Unsigned_64 (Natural'Last)
                       or else Local_Offset > Interfaces.Unsigned_64 (Natural'Last)
                     then
                        Status := Unsupported_Method;
                        return Empty;
                     end if;

                     declare
                        Local : constant Natural :=
                          Archive_Image'First + Natural (Local_Offset);
                     begin
                        if Local < Archive_Image'First
                          or else Local + 29 > Archive_Image'Last
                          or else ZIP_U32_At (Archive_Image, Local) /=
                            16#0403_4B50#
                          or else ZIP_U16_At (Archive_Image, Local + 8) /=
                            Method
                        then
                           Status := Unexpected_End_Of_Input;
                           return Empty;
                        end if;

                        declare
                           Local_Name_Len  : constant Natural :=
                             Natural (ZIP_U16_At (Archive_Image, Local + 26));
                           Local_Extra_Len : constant Natural :=
                             Natural (ZIP_U16_At (Archive_Image, Local + 28));
                           Payload_First   : constant Natural :=
                             Local + 30 + Local_Name_Len + Local_Extra_Len;
                           Payload_Len     : constant Natural :=
                             Natural (Compressed);
                           Plain_Len       : constant Natural :=
                             Natural (Uncompressed);
                        begin
                           if Payload_Len = 0
                             or else Payload_First > Archive_Image'Last
                             or else Payload_Len - 1 >
                               Archive_Image'Last - Payload_First
                           then
                              Status := Unexpected_End_Of_Input;
                              return Empty;
                           end if;

                           declare
                              Output_Count : constant Positive :=
                                Natural'Max (1, Plain_Len);
                              Output       : Byte_Array (1 .. Output_Count);
                              Result_Size  : Interfaces.C.size_t;
                           begin
                              Result_Size :=
                                ZSTD_decompress
                                  (Dst             =>
                                     Output (Output'First)'Address,
                                   Dst_Capacity    =>
                                     Interfaces.C.size_t (Plain_Len),
                                   Src             =>
                                     Archive_Image (Payload_First)'Address,
                                   Compressed_Size =>
                                     Interfaces.C.size_t (Payload_Len));

                              if ZSTD_isError (Result_Size) /= 0
                                or else Natural (Result_Size) /= Plain_Len
                              then
                                 Status := Invalid_Block_Type;
                                 return Empty;
                              end if;

                              if Plain_Len = 0 then
                                 if Crc /= 0 then
                                    Status := Invalid_Checksum;
                                 else
                                    Status := Ok;
                                 end if;
                                 return Empty;
                              end if;

                              declare
                                 Plain : Byte_Array (1 .. Plain_Len);
                              begin
                                 for I in Plain'Range loop
                                    Plain (I) := Output (I);
                                 end loop;

                                 if Zlib.CRC32 (Plain) /= Crc then
                                    Status := Invalid_Checksum;
                                    return Empty;
                                 end if;

                                 Status := Ok;
                                 return Plain;
                              end;
                           end;
                        end;
                     end;
                  end;
               end if;

               Pos := Record_After;
            end;
         else
            Pos := Pos + 1;
         end if;
      end loop;

      Status := (if Found_Zstd_Name then Invalid_Block_Type else Unsupported_Method);
      return Empty;
   exception
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end Extract_ZIP_Native_Zstd_Entry;

   LZMA_Bit_Model_Total : constant Interfaces.Unsigned_32 := 2 ** 11;
   LZMA_Move_Bits       : constant Natural := 5;
   LZMA_Top_Value       : constant Interfaces.Unsigned_32 := 2 ** 24;
   LZMA_Num_States      : constant Natural := 12;
   LZMA_Literal_Probs   : constant Natural := 16#300#;
   LZMA_Num_Pos_States_Max : constant Natural := 16;
   LZMA_Num_Len_To_Pos_States : constant Natural := 4;
   LZMA_Len_Low_Symbols : constant Natural := 8;
   LZMA_Len_Mid_Symbols : constant Natural := 8;
   LZMA_Len_High_Symbols : constant Natural := 256;
   LZMA_Min_Match_Length : constant Natural := 2;
   LZMA_Default_LC      : constant Natural := 3;
   LZMA_Default_LP      : constant Natural := 0;
   LZMA_Default_PB      : constant Natural := 2;
   LZMA_Default_Props   : constant Byte :=
     Byte ((LZMA_Default_PB * 5 + LZMA_Default_LP) * 9 + LZMA_Default_LC);
   LZMA_Default_Dict    : constant Interfaces.Unsigned_32 := 16#0080_0000#;
   LZMA_Start_Pos_Model_Index : constant Natural := 4;
   LZMA_End_Pos_Model_Index : constant Natural := 14;
   LZMA_Num_Full_Distances : constant Natural := 2 ** (LZMA_End_Pos_Model_Index / 2);
   LZMA_Num_Align_Bits : constant Natural := 4;
   LZMA_Align_Table_Size : constant Natural := 2 ** LZMA_Num_Align_Bits;

   type LZMA_Prob_Array is array (Natural range <>) of Interfaces.Unsigned_32;

   function Valid_LZMA_Props (Props : Byte) return Boolean is
      Props_Value : constant Natural := Natural (Props);
      LCLP        : constant Natural := Props_Value mod 9;
      Rest        : constant Natural := Props_Value / 9;
      LC          : constant Natural := LCLP;
      LP          : constant Natural := Rest mod 5;
      PB          : constant Natural := Rest / 5;
   begin
      return LC <= 8 and then LP <= 4 and then PB <= 4 and then LC + LP <= 4;
   end Valid_LZMA_Props;

   type LZMA_Len_Encoder is record
      Choice : LZMA_Prob_Array (0 .. 1);
      Low    : LZMA_Prob_Array
        (0 .. LZMA_Num_Pos_States_Max * LZMA_Len_Low_Symbols - 1);
      Mid    : LZMA_Prob_Array
        (0 .. LZMA_Num_Pos_States_Max * LZMA_Len_Mid_Symbols - 1);
      High   : LZMA_Prob_Array (0 .. LZMA_Len_High_Symbols - 1);
   end record;

   procedure LZMA_Init_Probs (Probs : out LZMA_Prob_Array) is
   begin
      for P of Probs loop
         P := LZMA_Bit_Model_Total / 2;
      end loop;
   end LZMA_Init_Probs;

   function LZMA_Literal_Context
     (LC        : Natural;
      LP        : Natural;
      Position  : Natural;
      Prev_Byte : Byte) return Natural
   is
      Pos_Part : constant Natural :=
        (if LP = 0 then 0 else (Position mod (2 ** LP)) * (2 ** LC));
      Prev_Part : constant Natural :=
        (if LC = 0 then 0 else Natural (Prev_Byte) / (2 ** (8 - LC)));
   begin
      return Pos_Part + Prev_Part;
   end LZMA_Literal_Context;

   function LZMA_Literal_State_After (State : Natural) return Natural is
   begin
      if State < 4 then
         return 0;
      elsif State < 10 then
         return State - 3;
      else
         return State - 6;
      end if;
   end LZMA_Literal_State_After;

   function LZMA_Match_State_After (State : Natural) return Natural is
   begin
      if State < 7 then
         return 7;
      else
         return 10;
      end if;
   end LZMA_Match_State_After;

   function LZMA_Rep_State_After (State : Natural) return Natural is
   begin
      if State < 7 then
         return 8;
      else
         return 11;
      end if;
   end LZMA_Rep_State_After;

   function LZMA_Short_Rep_State_After (State : Natural) return Natural is
   begin
      if State < 7 then
         return 9;
      else
         return 11;
      end if;
   end LZMA_Short_Rep_State_After;

   type LZMA_Range_Encoder is record
      Low        : Interfaces.Unsigned_64 := 0;
      Range_Code : Interfaces.Unsigned_32 := Interfaces.Unsigned_32'Last;
      Cache      : Interfaces.Unsigned_32 := 0;
      Cache_Size : Natural := 1;
      Writer     : Zlib.Bit_Writer.Writer;
   end record;

   procedure LZMA_Encoder_Shift_Low (E : in out LZMA_Range_Encoder) is
      Low_Hi : constant Interfaces.Unsigned_32 :=
        Interfaces.Unsigned_32 (Interfaces.Shift_Right (E.Low, 32));
      Temp   : Interfaces.Unsigned_32;
   begin
      if E.Low < 16#FF00_0000# or else Low_Hi /= 0 then
         Temp := E.Cache;
         loop
            Zlib.Bit_Writer.Write_Byte_Aligned
              (E.Writer, Byte ((Temp + Low_Hi) and 16#FF#));
            E.Cache_Size := E.Cache_Size - 1;
            exit when E.Cache_Size = 0;
            Temp := 16#FF#;
         end loop;
         E.Cache :=
           Interfaces.Unsigned_32 (Interfaces.Shift_Right (E.Low, 24) and 16#FF#);
      end if;

      E.Cache_Size := E.Cache_Size + 1;
      E.Low := Interfaces.Shift_Left (E.Low and 16#00FF_FFFF#, 8);
   end LZMA_Encoder_Shift_Low;

   procedure LZMA_Encode_Bit
     (E     : in out LZMA_Range_Encoder;
      Prob  : in out Interfaces.Unsigned_32;
      Bit   : Natural)
   is
      Bound : constant Interfaces.Unsigned_32 :=
        Interfaces.Shift_Right (E.Range_Code, 11) * Prob;
   begin
      if Bit = 0 then
         E.Range_Code := Bound;
         Prob := Prob + Interfaces.Shift_Right (LZMA_Bit_Model_Total - Prob,
                                                LZMA_Move_Bits);
      else
         E.Low :=
           E.Low + Interfaces.Unsigned_64 (Bound);
         E.Range_Code := E.Range_Code - Bound;
         Prob := Prob - Interfaces.Shift_Right (Prob, LZMA_Move_Bits);
      end if;

      if E.Range_Code < LZMA_Top_Value then
         E.Range_Code := Interfaces.Shift_Left (E.Range_Code, 8);
         LZMA_Encoder_Shift_Low (E);
      end if;
   end LZMA_Encode_Bit;

   procedure LZMA_Encode_Bit_Tree
     (E       : in out LZMA_Range_Encoder;
      Probs   : in out LZMA_Prob_Array;
      Offset  : Natural;
      Bits    : Natural;
      Symbol  : Natural)
   is
      Node : Natural := 1;
   begin
      for Bit_Index in reverse 0 .. Bits - 1 loop
         declare
            Bit : constant Natural := (Symbol / (2 ** Bit_Index)) mod 2;
         begin
            LZMA_Encode_Bit (E, Probs (Offset + Node), Bit);
            Node := Node * 2 + Bit;
         end;
      end loop;
   end LZMA_Encode_Bit_Tree;

   procedure LZMA_Encode_Reverse_Bit_Tree
     (E       : in out LZMA_Range_Encoder;
      Probs   : in out LZMA_Prob_Array;
      Offset  : Integer;
      Bits    : Natural;
      Symbol  : Natural)
   is
      Node : Natural := 1;
   begin
      for Bit_Index in 0 .. Bits - 1 loop
         declare
            Bit : constant Natural := (Symbol / (2 ** Bit_Index)) mod 2;
         begin
            LZMA_Encode_Bit (E, Probs (Natural (Offset + Node)), Bit);
            Node := Node * 2 + Bit;
         end;
      end loop;
   end LZMA_Encode_Reverse_Bit_Tree;

   procedure LZMA_Encode_Direct_Bits
     (E      : in out LZMA_Range_Encoder;
      Value  : Natural;
      Bits   : Natural)
   is
   begin
      if Bits = 0 then
         return;
      end if;

      for Bit_Index in reverse 0 .. Bits - 1 loop
         declare
            Bit : constant Natural := (Value / (2 ** Bit_Index)) mod 2;
         begin
            E.Range_Code := Interfaces.Shift_Right (E.Range_Code, 1);
            if Bit /= 0 then
               E.Low := E.Low + Interfaces.Unsigned_64 (E.Range_Code);
            end if;

            if E.Range_Code < LZMA_Top_Value then
               E.Range_Code := Interfaces.Shift_Left (E.Range_Code, 8);
               LZMA_Encoder_Shift_Low (E);
            end if;
         end;
      end loop;
   end LZMA_Encode_Direct_Bits;

   function LZMA_Pos_Slot (Distance_Code : Natural) return Natural is
   begin
      if Distance_Code < LZMA_Start_Pos_Model_Index then
         return Distance_Code;
      end if;

      for Slot in LZMA_Start_Pos_Model_Index .. 63 loop
         declare
            Footer_Bits : constant Natural := Slot / 2 - 1;
            Base        : constant Natural :=
              (2 + Slot mod 2) * (2 ** Footer_Bits);
         begin
            if Distance_Code < Base + 2 ** Footer_Bits then
               return Slot;
            end if;
         end;
      end loop;

      return 63;
   end LZMA_Pos_Slot;

   procedure LZMA_Encode_Distance
     (E             : in out LZMA_Range_Encoder;
      Pos_Slot      : in out LZMA_Prob_Array;
      Pos_Special   : in out LZMA_Prob_Array;
      Pos_Align     : in out LZMA_Prob_Array;
      Len           : Natural;
      Distance      : Natural)
   is
      Distance_Code     : constant Natural := Distance - 1;
      Pos_State_For_Len : constant Natural :=
        Natural'Min (Len - LZMA_Min_Match_Length,
                     LZMA_Num_Len_To_Pos_States - 1);
      Slot              : constant Natural := LZMA_Pos_Slot (Distance_Code);
   begin
      LZMA_Encode_Bit_Tree
        (E, Pos_Slot, Pos_State_For_Len * 64, 6, Slot);

      if Slot >= LZMA_Start_Pos_Model_Index then
         declare
            Footer_Bits : constant Natural := Slot / 2 - 1;
            Base        : constant Natural :=
              (2 + Slot mod 2) * (2 ** Footer_Bits);
            Reduced     : constant Natural := Distance_Code - Base;
            Offset      : constant Integer := Integer (Base) - Integer (Slot) - 1;
         begin
            if Slot < LZMA_End_Pos_Model_Index then
               LZMA_Encode_Reverse_Bit_Tree
                 (E, Pos_Special, Offset, Footer_Bits, Reduced);
            else
               LZMA_Encode_Direct_Bits
                 (E, Reduced / LZMA_Align_Table_Size,
                  Footer_Bits - LZMA_Num_Align_Bits);
               LZMA_Encode_Reverse_Bit_Tree
                 (E, Pos_Align, 0, LZMA_Num_Align_Bits,
                  Reduced mod LZMA_Align_Table_Size);
            end if;
         end;
      end if;
   end LZMA_Encode_Distance;

   procedure LZMA_Init_Len (Len : out LZMA_Len_Encoder) is
   begin
      LZMA_Init_Probs (Len.Choice);
      LZMA_Init_Probs (Len.Low);
      LZMA_Init_Probs (Len.Mid);
      LZMA_Init_Probs (Len.High);
   end LZMA_Init_Len;

   procedure LZMA_Encode_Len
     (E         : in out LZMA_Range_Encoder;
      Len       : in out LZMA_Len_Encoder;
      Pos_State : Natural;
      Symbol    : Natural)
   is
   begin
      if Symbol < LZMA_Len_Low_Symbols then
         LZMA_Encode_Bit (E, Len.Choice (0), 0);
         LZMA_Encode_Bit_Tree
           (E, Len.Low, Pos_State * LZMA_Len_Low_Symbols, 3, Symbol);
      elsif Symbol < LZMA_Len_Low_Symbols + LZMA_Len_Mid_Symbols then
         LZMA_Encode_Bit (E, Len.Choice (0), 1);
         LZMA_Encode_Bit (E, Len.Choice (1), 0);
         LZMA_Encode_Bit_Tree
           (E, Len.Mid, Pos_State * LZMA_Len_Mid_Symbols, 3,
            Symbol - LZMA_Len_Low_Symbols);
      else
         LZMA_Encode_Bit (E, Len.Choice (0), 1);
         LZMA_Encode_Bit (E, Len.Choice (1), 1);
         LZMA_Encode_Bit_Tree
           (E, Len.High, 0, 8,
            Symbol - LZMA_Len_Low_Symbols - LZMA_Len_Mid_Symbols);
      end if;
   end LZMA_Encode_Len;

   --  Bit-price table (LZMA SDK method): Prob_Prices (Prob >> 4) gives the
   --  cost, in 1/16-bit units, of coding a bit whose model probability of the
   --  coded symbol is Prob/2048. Used by the optimal parser to compare the
   --  cost of literals, matches, and repeated-distance matches.
   type Price_Table is array (0 .. 127) of Natural;

   function Compute_Prob_Prices return Price_Table is
      T : Price_Table;
   begin
      for I in 0 .. 127 loop
         declare
            W         : Interfaces.Unsigned_32 := Interfaces.Unsigned_32 (I) * 16;
            Bit_Count : Natural := 0;
         begin
            for J in 1 .. 4 loop
               pragma Unreferenced (J);
               W := W * W;
               Bit_Count := Bit_Count * 2;
               while W >= 2 ** 16 loop
                  W := Interfaces.Shift_Right (W, 1);
                  Bit_Count := Bit_Count + 1;
               end loop;
            end loop;
            T (I) := 176 - 15 - Bit_Count;
         end;
      end loop;
      return T;
   end Compute_Prob_Prices;

   Prob_Prices : constant Price_Table := Compute_Prob_Prices;

   function Bit_Price
     (Prob : Interfaces.Unsigned_32; Bit : Natural) return Natural
   is
     (Prob_Prices
        (Natural
           (Interfaces.Shift_Right
              ((if Bit = 0 then Prob else Prob xor 2047), 4))));

   function LZMA_Encode_Bounded (Plain : Byte_Array) return Byte_Array is
      E             : LZMA_Range_Encoder;
      Pos_States    : constant Natural := 2 ** LZMA_Default_PB;
      Literal_Ctxs  : constant Natural := 2 ** (LZMA_Default_LC + LZMA_Default_LP);
      Is_Match      : LZMA_Prob_Array (0 .. LZMA_Num_States * LZMA_Num_Pos_States_Max - 1);
      Is_Rep        : LZMA_Prob_Array (0 .. LZMA_Num_States - 1);
      Is_Rep_G0     : LZMA_Prob_Array (0 .. LZMA_Num_States - 1);
      Is_Rep_G1     : LZMA_Prob_Array (0 .. LZMA_Num_States - 1);
      Is_Rep_G2     : LZMA_Prob_Array (0 .. LZMA_Num_States - 1);
      Is_Rep0_Long  : LZMA_Prob_Array (0 .. LZMA_Num_States * LZMA_Num_Pos_States_Max - 1);
      Match_Len     : LZMA_Len_Encoder;
      Rep_Len       : LZMA_Len_Encoder;
      Pos_Slot      : LZMA_Prob_Array
        (0 .. LZMA_Num_Len_To_Pos_States * 64 - 1);
      Pos_Special   : LZMA_Prob_Array
        (0 .. LZMA_Num_Full_Distances - LZMA_End_Pos_Model_Index - 1);
      Pos_Align     : LZMA_Prob_Array (0 .. LZMA_Align_Table_Size - 1);
      Literals      : LZMA_Prob_Array (0 .. Literal_Ctxs * LZMA_Literal_Probs - 1);
      State         : Natural := 0;
      Prev          : Byte := 0;
      Position      : Natural := 0;
      In_Index      : Natural := Plain'First;
      Rep0          : Natural := 0;
      Rep1          : Natural := 0;
      Rep2          : Natural := 0;
      Rep3          : Natural := 0;

      --  Hash-chain (HC3) match finder. Each position is hashed on its next
      --  three bytes into Head/Chain; Find_Match walks the chain for the
      --  nearest longest match (extending to the LZMA maximum of 273), so long
      --  repeats compress to a single match. This replaces the previous
      --  brute-force scan that was both O(n*dict) and capped matches at 17.
      Max_Match : constant Natural := 273;
      Nice_Len  : constant Natural := 128;
      Max_Chain : constant Natural := 128;
      Hash_Bits : constant Natural := 16;
      Dict_Sz   : constant Natural := Natural (LZMA_Default_Dict);
      type Pos_Table is array (Natural range <>) of Natural;
      Head  : Pos_Table (0 .. 2 ** Hash_Bits - 1) := [others => 0];
      Chain : Pos_Table (1 .. Natural'Max (Plain'Length, 1)) := [others => 0];

      function Hash3 (I : Natural) return Natural is
         V : constant Interfaces.Unsigned_32 :=
           Interfaces.Unsigned_32 (Plain (I))
           or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Plain (I + 1)), 8)
           or Interfaces.Shift_Left
                (Interfaces.Unsigned_32 (Plain (I + 2)), 16);
      begin
         return Natural
           (Interfaces.Shift_Right (V * 16#9E37_79B1#, 32 - Hash_Bits));
      end Hash3;

      procedure Insert (I : Natural) is
      begin
         if I + 2 <= Plain'Last then
            declare
               H : constant Natural := Hash3 (I);
               S : constant Natural := I - Plain'First + 1;
            begin
               Chain (S) := Head (H);
               Head (H) := S;
            end;
         end if;
      end Insert;

      function Match_Length (I, D : Natural) return Natural is
         L : Natural := 0;
      begin
         while I + L <= Plain'Last and then L < Max_Match
           and then Plain (I + L) = Plain (I + L - D)
         loop
            L := L + 1;
         end loop;
         return L;
      end Match_Length;

      procedure Emit_Literal is
         B         : constant Byte := Plain (In_Index);
         Pos_State : constant Natural := Position mod Pos_States;
         Context   : constant Natural :=
           LZMA_Literal_Context
             (LZMA_Default_LC, LZMA_Default_LP, Position, Prev);
         Symbol    : Natural := 1;
      begin
         LZMA_Encode_Bit
           (E, Is_Match (State * LZMA_Num_Pos_States_Max + Pos_State), 0);
         if State >= 7 and then Rep0 > 0 and then Rep0 <= Position then
            declare
               Match_Byte : Natural := Natural (Plain (In_Index - Rep0));
               Matched    : Boolean := True;
            begin
               for Bit_Index in reverse 0 .. 7 loop
                  declare
                     Bit : constant Natural :=
                       (Natural (B) / (2 ** Bit_Index)) mod 2;
                  begin
                     if Matched then
                        Match_Byte := Match_Byte * 2;
                        declare
                           Match_Bit_Literal : constant Natural :=
                             ((Match_Byte / 16#100#) mod 2) * 16#100#;
                        begin
                           LZMA_Encode_Bit
                             (E,
                              Literals
                                (Context * LZMA_Literal_Probs
                                 + 16#100# + Match_Bit_Literal + Symbol),
                              Bit);
                           Symbol := Symbol * 2 + Bit;
                           if Match_Bit_Literal /= Bit * 16#100# then
                              Matched := False;
                           end if;
                        end;
                     else
                        LZMA_Encode_Bit
                          (E,
                           Literals (Context * LZMA_Literal_Probs + Symbol),
                           Bit);
                        Symbol := Symbol * 2 + Bit;
                     end if;
                  end;
               end loop;
            end;
         else
            for Bit_Index in reverse 0 .. 7 loop
               declare
                  Bit : constant Natural :=
                    (Natural (B) / (2 ** Bit_Index)) mod 2;
               begin
                  LZMA_Encode_Bit
                    (E, Literals (Context * LZMA_Literal_Probs + Symbol), Bit);
                  Symbol := Symbol * 2 + Bit;
               end;
            end loop;
         end if;
         State := LZMA_Literal_State_After (State);
         Prev := B;
         Position := Position + 1;
         In_Index := In_Index + 1;
      end Emit_Literal;

      ----------------------------------------------------------------------
      --  Optimal parser: price-based shortest-path over each segment.
      --  Pricing helpers mirror the encode routines exactly (in 1/16-bit
      --  units); emission reuses the proven encoders, so a wrong price only
      --  costs ratio, never correctness.
      ----------------------------------------------------------------------

      function Tree_Price
        (Probs : LZMA_Prob_Array; Offset, Bits, Symbol : Natural) return Natural
      is
         Node : Natural := 1;
         Pr   : Natural := 0;
      begin
         for Bit_Index in reverse 0 .. Bits - 1 loop
            declare
               Bit : constant Natural := (Symbol / (2 ** Bit_Index)) mod 2;
            begin
               Pr := Pr + Bit_Price (Probs (Offset + Node), Bit);
               Node := Node * 2 + Bit;
            end;
         end loop;
         return Pr;
      end Tree_Price;

      function Rev_Tree_Price
        (Probs : LZMA_Prob_Array; Offset : Integer; Bits, Symbol : Natural)
         return Natural
      is
         Node : Natural := 1;
         Pr   : Natural := 0;
      begin
         for Bit_Index in 0 .. Bits - 1 loop
            declare
               Bit : constant Natural := (Symbol / (2 ** Bit_Index)) mod 2;
            begin
               Pr := Pr + Bit_Price (Probs (Natural (Offset + Node)), Bit);
               Node := Node * 2 + Bit;
            end;
         end loop;
         return Pr;
      end Rev_Tree_Price;

      function Len_Price_Of
        (Len_Enc : LZMA_Len_Encoder; Pos_State, Symbol : Natural) return Natural
      is
      begin
         if Symbol < LZMA_Len_Low_Symbols then
            return Bit_Price (Len_Enc.Choice (0), 0)
              + Tree_Price
                  (Len_Enc.Low, Pos_State * LZMA_Len_Low_Symbols, 3, Symbol);
         elsif Symbol < LZMA_Len_Low_Symbols + LZMA_Len_Mid_Symbols then
            return Bit_Price (Len_Enc.Choice (0), 1)
              + Bit_Price (Len_Enc.Choice (1), 0)
              + Tree_Price
                  (Len_Enc.Mid, Pos_State * LZMA_Len_Mid_Symbols, 3,
                   Symbol - LZMA_Len_Low_Symbols);
         else
            return Bit_Price (Len_Enc.Choice (0), 1)
              + Bit_Price (Len_Enc.Choice (1), 1)
              + Tree_Price
                  (Len_Enc.High, 0, 8,
                   Symbol - LZMA_Len_Low_Symbols - LZMA_Len_Mid_Symbols);
         end if;
      end Len_Price_Of;

      function Dist_Price (Len, Distance : Natural) return Natural is
         Dcode : constant Natural := Distance - 1;
         PSL   : constant Natural :=
           Natural'Min (Len - LZMA_Min_Match_Length,
                        LZMA_Num_Len_To_Pos_States - 1);
         Slot  : constant Natural := LZMA_Pos_Slot (Dcode);
         Pr    : Natural := Tree_Price (Pos_Slot, PSL * 64, 6, Slot);
      begin
         if Slot >= LZMA_Start_Pos_Model_Index then
            declare
               Footer  : constant Natural := Slot / 2 - 1;
               Base    : constant Natural := (2 + Slot mod 2) * (2 ** Footer);
               Reduced : constant Natural := Dcode - Base;
            begin
               if Slot < LZMA_End_Pos_Model_Index then
                  Pr := Pr + Rev_Tree_Price
                    (Pos_Special, Integer (Base) - Integer (Slot) - 1,
                     Footer, Reduced);
               else
                  Pr := Pr + (Footer - LZMA_Num_Align_Bits) * 16
                    + Rev_Tree_Price
                        (Pos_Align, 0, LZMA_Num_Align_Bits,
                         Reduced mod LZMA_Align_Table_Size);
               end if;
            end;
         end if;
         return Pr;
      end Dist_Price;

      function Lit_Price_At
        (I : Natural; St : Natural; Rep0_D : Natural) return Natural
      is
         B       : constant Natural := Natural (Plain (I));
         Prev_B  : constant Byte :=
           (if I > Plain'First then Plain (I - 1) else 0);
         Context : constant Natural :=
           LZMA_Literal_Context
             (LZMA_Default_LC, LZMA_Default_LP, I - Plain'First, Prev_B);
         Symbol  : Natural := 1;
         Pr      : Natural := 0;
      begin
         if St >= 7 and then Rep0_D > 0
           and then I - Rep0_D >= Plain'First
         then
            declare
               Match_Byte : Natural := Natural (Plain (I - Rep0_D));
               Matched    : Boolean := True;
            begin
               for Bit_Index in reverse 0 .. 7 loop
                  declare
                     Bit : constant Natural := (B / (2 ** Bit_Index)) mod 2;
                  begin
                     if Matched then
                        Match_Byte := Match_Byte * 2;
                        declare
                           MBL : constant Natural :=
                             ((Match_Byte / 16#100#) mod 2) * 16#100#;
                        begin
                           Pr := Pr + Bit_Price
                             (Literals
                                (Context * LZMA_Literal_Probs
                                 + 16#100# + MBL + Symbol), Bit);
                           Symbol := Symbol * 2 + Bit;
                           if MBL /= Bit * 16#100# then
                              Matched := False;
                           end if;
                        end;
                     else
                        Pr := Pr + Bit_Price
                          (Literals (Context * LZMA_Literal_Probs + Symbol), Bit);
                        Symbol := Symbol * 2 + Bit;
                     end if;
                  end;
               end loop;
            end;
         else
            for Bit_Index in reverse 0 .. 7 loop
               declare
                  Bit : constant Natural := (B / (2 ** Bit_Index)) mod 2;
               begin
                  Pr := Pr + Bit_Price
                    (Literals (Context * LZMA_Literal_Probs + Symbol), Bit);
                  Symbol := Symbol * 2 + Bit;
               end;
            end loop;
         end if;
         return Pr;
      end Lit_Price_At;

      function Rep_Choice_Price
        (St, Idx, Pos_State : Natural) return Natural is
      begin
         case Idx is
            when 0 =>
               return Bit_Price (Is_Rep_G0 (St), 0)
                 + Bit_Price
                     (Is_Rep0_Long (St * LZMA_Num_Pos_States_Max + Pos_State), 1);
            when 1 =>
               return Bit_Price (Is_Rep_G0 (St), 1)
                 + Bit_Price (Is_Rep_G1 (St), 0);
            when 2 =>
               return Bit_Price (Is_Rep_G0 (St), 1)
                 + Bit_Price (Is_Rep_G1 (St), 1)
                 + Bit_Price (Is_Rep_G2 (St), 0);
            when others =>
               return Bit_Price (Is_Rep_G0 (St), 1)
                 + Bit_Price (Is_Rep_G1 (St), 1)
                 + Bit_Price (Is_Rep_G2 (St), 1);
         end case;
      end Rep_Choice_Price;

      Max_Pairs : constant := 64;
      type Len_Array is array (1 .. Max_Pairs) of Natural;

      procedure Find_All_Matches
        (I     : Natural;
         Count : out Natural;
         Lens  : out Len_Array;
         Dists : out Len_Array)
      is
         I_Pos : constant Natural := I - Plain'First;
         Cur   : Natural;
         Depth : Natural := 0;
         Best  : Natural := 0;
      begin
         Count := 0;
         Lens  := [others => 0];
         Dists := [others => 0];
         if I + 2 > Plain'Last then
            return;
         end if;
         Cur := Head (Hash3 (I));
         while Cur /= 0 and then Depth < Max_Chain loop
            declare
               D : constant Natural := I_Pos - (Cur - 1);
            begin
               exit when D > Dict_Sz;
               declare
                  L : constant Natural := Match_Length (I, D);
               begin
                  if L > Best then
                     Best := L;
                     if Count < Max_Pairs then
                        Count := Count + 1;
                        Lens (Count) := L;
                        Dists (Count) := D;
                     end if;
                     exit when L >= Nice_Len;
                  end if;
               end;
            end;
            Cur := Chain (Cur);
            Depth := Depth + 1;
         end loop;
      end Find_All_Matches;

      procedure Emit_Match (Dist, Len : Natural) is
         Pos_State : constant Natural := Position mod Pos_States;
      begin
         LZMA_Encode_Bit
           (E, Is_Match (State * LZMA_Num_Pos_States_Max + Pos_State), 1);
         LZMA_Encode_Bit (E, Is_Rep (State), 0);
         LZMA_Encode_Len
           (E, Match_Len, Pos_State, Len - LZMA_Min_Match_Length);
         LZMA_Encode_Distance
           (E, Pos_Slot, Pos_Special, Pos_Align, Len, Dist);
         Rep3 := Rep2;
         Rep2 := Rep1;
         Rep1 := Rep0;
         Rep0 := Dist;
         State := LZMA_Match_State_After (State);
         Prev := Plain (In_Index + Len - 1);
         Position := Position + Len;
         In_Index := In_Index + Len;
      end Emit_Match;

      procedure Emit_Rep (Idx, Len : Natural) is
         Pos_State : constant Natural := Position mod Pos_States;
      begin
         LZMA_Encode_Bit
           (E, Is_Match (State * LZMA_Num_Pos_States_Max + Pos_State), 1);
         LZMA_Encode_Bit (E, Is_Rep (State), 1);
         case Idx is
            when 0 =>
               LZMA_Encode_Bit (E, Is_Rep_G0 (State), 0);
               LZMA_Encode_Bit
                 (E,
                  Is_Rep0_Long (State * LZMA_Num_Pos_States_Max + Pos_State), 1);
            when 1 =>
               LZMA_Encode_Bit (E, Is_Rep_G0 (State), 1);
               LZMA_Encode_Bit (E, Is_Rep_G1 (State), 0);
               declare
                  D : constant Natural := Rep1;
               begin
                  Rep1 := Rep0;
                  Rep0 := D;
               end;
            when 2 =>
               LZMA_Encode_Bit (E, Is_Rep_G0 (State), 1);
               LZMA_Encode_Bit (E, Is_Rep_G1 (State), 1);
               LZMA_Encode_Bit (E, Is_Rep_G2 (State), 0);
               declare
                  D : constant Natural := Rep2;
               begin
                  Rep2 := Rep1;
                  Rep1 := Rep0;
                  Rep0 := D;
               end;
            when others =>
               LZMA_Encode_Bit (E, Is_Rep_G0 (State), 1);
               LZMA_Encode_Bit (E, Is_Rep_G1 (State), 1);
               LZMA_Encode_Bit (E, Is_Rep_G2 (State), 1);
               declare
                  D : constant Natural := Rep3;
               begin
                  Rep3 := Rep2;
                  Rep2 := Rep1;
                  Rep1 := Rep0;
                  Rep0 := D;
               end;
         end case;
         LZMA_Encode_Len (E, Rep_Len, Pos_State, Len - LZMA_Min_Match_Length);
         State := LZMA_Rep_State_After (State);
         Prev := Plain (In_Index + Len - 1);
         Position := Position + Len;
         In_Index := In_Index + Len;
      end Emit_Rep;

      type Rep_Quad is array (0 .. 3) of Natural;
      type Opt_Kind is (Op_Lit, Op_Match, Op_Rep);
      type Opt_Entry is record
         Price   : Natural := Natural'Last;
         From    : Natural := 0;
         Kind    : Opt_Kind := Op_Lit;
         Dist    : Natural := 0;
         Len     : Natural := 1;
         Rep_Idx : Natural := 0;
         St      : Natural := 0;
         Reps    : Rep_Quad := [others => 0];
      end record;
      --  Segment length for the optimal DP. Smaller segments refresh the
      --  price model more often (better ratio on real data); larger ones split
      --  fewer matches at segment boundaries (only helps degenerate inputs).
      Seg_Len : constant Natural := 2048;
      type Opt_Array is array (Natural range <>) of Opt_Entry;
      Opt : Opt_Array (0 .. Seg_Len);

      function Reorder_Reps (R : Rep_Quad; Idx : Natural) return Rep_Quad is
         N : Rep_Quad := R;
      begin
         case Idx is
            when 0 => null;
            when 1 => N (0) := R (1); N (1) := R (0);
            when 2 => N (0) := R (2); N (1) := R (0); N (2) := R (1);
            when others =>
               N (0) := R (3); N (1) := R (0); N (2) := R (1); N (3) := R (2);
         end case;
         return N;
      end Reorder_Reps;

      function Shift_Reps (R : Rep_Quad; Dist : Natural) return Rep_Quad is
        ([0 => Dist, 1 => R (0), 2 => R (1), 3 => R (2)]);
   begin
      Zlib.Bit_Writer.Reset (E.Writer);
      LZMA_Init_Probs (Is_Match);
      LZMA_Init_Probs (Is_Rep);
      LZMA_Init_Probs (Is_Rep_G0);
      LZMA_Init_Probs (Is_Rep_G1);
      LZMA_Init_Probs (Is_Rep_G2);
      LZMA_Init_Probs (Is_Rep0_Long);
      LZMA_Init_Len (Match_Len);
      LZMA_Init_Len (Rep_Len);
      LZMA_Init_Probs (Pos_Slot);
      LZMA_Init_Probs (Pos_Special);
      LZMA_Init_Probs (Pos_Align);
      LZMA_Init_Probs (Literals);

      while In_Index <= Plain'Last loop
         declare
            Base_Pos : constant Natural := Position;
            Cur      : constant Natural := In_Index;
            Span     : constant Natural :=
              Natural'Min (Seg_Len, Plain'Last - Cur + 1);
         begin
            --  Initialise the DP for this segment from the live coder state.
            Opt (0) :=
              (Price => 0, From => 0, Kind => Op_Lit, Dist => 0, Len => 1,
               Rep_Idx => 0, St => State, Reps => [Rep0, Rep1, Rep2, Rep3]);
            for J in 1 .. Span loop
               Opt (J).Price := Natural'Last;
            end loop;

            --  Forward relaxation over the segment.
            for I in 0 .. Span - 1 loop
               if Opt (I).Price < Natural'Last then
                  declare
                     S   : constant Natural := Opt (I).St;
                     R   : constant Rep_Quad := Opt (I).Reps;
                     P   : constant Natural := Opt (I).Price;
                     CI  : constant Natural := Cur + I;
                     Pos : constant Natural := Base_Pos + I;
                     PS  : constant Natural := Pos mod Pos_States;
                     Mbase : constant Natural :=
                       P + Bit_Price
                             (Is_Match (S * LZMA_Num_Pos_States_Max + PS), 1);

                     procedure Relax
                       (J, New_Price : Natural; Kind : Opt_Kind;
                        Dist, Len, Ridx, New_St : Natural; New_R : Rep_Quad) is
                     begin
                        if New_Price < Opt (J).Price then
                           Opt (J) :=
                             (Price => New_Price, From => I, Kind => Kind,
                              Dist => Dist, Len => Len, Rep_Idx => Ridx,
                              St => New_St, Reps => New_R);
                        end if;
                     end Relax;
                  begin
                     --  Literal.
                     Relax
                       (I + 1,
                        P + Bit_Price
                              (Is_Match (S * LZMA_Num_Pos_States_Max + PS), 0)
                          + Lit_Price_At (CI, S, R (0)),
                        Op_Lit, 0, 1, 0, LZMA_Literal_State_After (S), R);

                     --  Repeated-distance matches (every length).
                     for Idx in 0 .. 3 loop
                        if R (Idx) > 0 and then R (Idx) <= Pos then
                           declare
                              Max_L  : constant Natural :=
                                Natural'Min (Match_Length (CI, R (Idx)),
                                             Span - I);
                              Base   : constant Natural :=
                                Mbase + Bit_Price (Is_Rep (S), 1)
                                + Rep_Choice_Price (S, Idx, PS);
                              New_R  : constant Rep_Quad := Reorder_Reps (R, Idx);
                              New_St : constant Natural := LZMA_Rep_State_After (S);
                              --  A long match is taken whole; only short ones
                              --  need every length explored (keeps the DP fast
                              --  on repetitive data).
                              From_L : constant Natural :=
                                (if Max_L >= Nice_Len then Max_L
                                 else LZMA_Min_Match_Length);
                           begin
                              for Len in From_L .. Max_L loop
                                 Relax
                                   (I + Len,
                                    Base + Len_Price_Of
                                             (Rep_Len, PS,
                                              Len - LZMA_Min_Match_Length),
                                    Op_Rep, R (Idx), Len, Idx, New_St, New_R);
                              end loop;
                           end;
                        end if;
                     end loop;

                     --  Normal matches: each length at its shortest distance.
                     declare
                        Count       : Natural;
                        Lens, Dists : Len_Array;
                        Prev_L      : Natural := LZMA_Min_Match_Length - 1;
                     begin
                        Find_All_Matches (CI, Count, Lens, Dists);
                        for K in 1 .. Count loop
                           declare
                              D      : constant Natural := Dists (K);
                              Upto   : constant Natural :=
                                Natural'Min (Lens (K), Span - I);
                              New_R  : constant Rep_Quad := Shift_Reps (R, D);
                              New_St : constant Natural :=
                                LZMA_Match_State_After (S);
                              Base   : constant Natural :=
                                Mbase + Bit_Price (Is_Rep (S), 0);
                              From_L : constant Natural :=
                                (if Upto >= Nice_Len then Upto
                                 else Natural'Max
                                        (LZMA_Min_Match_Length, Prev_L + 1));
                           begin
                              for Len in From_L .. Upto loop
                                 Relax
                                   (I + Len,
                                    Base
                                    + Len_Price_Of
                                        (Match_Len, PS,
                                         Len - LZMA_Min_Match_Length)
                                    + Dist_Price (Len, D),
                                    Op_Match, D, Len, 0, New_St, New_R);
                              end loop;
                              Prev_L := Lens (K);
                           end;
                        end loop;
                     end;
                  end;
               end if;
               --  Insert the current position for subsequent match look-ups.
               Insert (Cur + I);
            end loop;

            --  Backtrack the cheapest path, then emit it forwards.
            declare
               type Op_Rec is record
                  Kind            : Opt_Kind;
                  Dist, Len, Ridx : Natural;
               end record;
               Ops : array (1 .. Span) of Op_Rec;
               N   : Natural := 0;
               J   : Natural := Span;
            begin
               while J > 0 loop
                  N := N + 1;
                  Ops (N) :=
                    (Opt (J).Kind, Opt (J).Dist, Opt (J).Len, Opt (J).Rep_Idx);
                  J := Opt (J).From;
               end loop;
               for M in reverse 1 .. N loop
                  case Ops (M).Kind is
                     when Op_Lit   => Emit_Literal;
                     when Op_Match => Emit_Match (Ops (M).Dist, Ops (M).Len);
                     when Op_Rep   => Emit_Rep (Ops (M).Ridx, Ops (M).Len);
                  end case;
               end loop;
            end;
         end;
      end loop;

      for I in 1 .. 5 loop
         LZMA_Encoder_Shift_Low (E);
      end loop;

      return Zlib.Bit_Writer.To_Array (E.Writer);
   end LZMA_Encode_Bounded;

   type LZMA_Range_Decoder is record
      Code       : Interfaces.Unsigned_32 := 0;
      Range_Code : Interfaces.Unsigned_32 := Interfaces.Unsigned_32'Last;
      Pos        : Natural := 0;
   end record;

   function LZMA_Read_Stream_Byte
     (D      : in out LZMA_Range_Decoder;
      Stream : Byte_Array;
      Status : in out Status_Code) return Interfaces.Unsigned_32
   is
   begin
      if D.Pos >= Stream'Length then
         Status := Unexpected_End_Of_Input;
         return 0;
      end if;

      D.Pos := D.Pos + 1;
      return Interfaces.Unsigned_32 (Stream (Stream'First + D.Pos - 1));
   end LZMA_Read_Stream_Byte;

   procedure LZMA_Decoder_Init
     (D      : in out LZMA_Range_Decoder;
      Stream : Byte_Array;
      Status : in out Status_Code)
   is
   begin
      D.Code := 0;
      D.Range_Code := Interfaces.Unsigned_32'Last;
      D.Pos := 0;

      for I in 1 .. 5 loop
         declare
            Next_Byte : constant Interfaces.Unsigned_32 :=
              LZMA_Read_Stream_Byte (D, Stream, Status);
         begin
            D.Code := Interfaces.Shift_Left (D.Code, 8) or Next_Byte;
         end;
         exit when Status /= Ok;
      end loop;
   end LZMA_Decoder_Init;

   function LZMA_Decode_Bit
     (D      : in out LZMA_Range_Decoder;
      Stream : Byte_Array;
      Prob   : in out Interfaces.Unsigned_32;
      Status : in out Status_Code) return Natural
   is
      Bound : constant Interfaces.Unsigned_32 :=
        Interfaces.Shift_Right (D.Range_Code, 11) * Prob;
      Bit   : Natural;
   begin
      if Status /= Ok then
         return 0;
      end if;

      if D.Code < Bound then
         D.Range_Code := Bound;
         Prob := Prob + Interfaces.Shift_Right (LZMA_Bit_Model_Total - Prob,
                                                LZMA_Move_Bits);
         Bit := 0;
      else
         D.Code := D.Code - Bound;
         D.Range_Code := D.Range_Code - Bound;
         Prob := Prob - Interfaces.Shift_Right (Prob, LZMA_Move_Bits);
         Bit := 1;
      end if;

      if D.Range_Code < LZMA_Top_Value then
         D.Range_Code := Interfaces.Shift_Left (D.Range_Code, 8);
         declare
            Next_Byte : constant Interfaces.Unsigned_32 :=
              LZMA_Read_Stream_Byte (D, Stream, Status);
         begin
            D.Code := Interfaces.Shift_Left (D.Code, 8) or Next_Byte;
         end;
      end if;

      return Bit;
   end LZMA_Decode_Bit;

   function LZMA_Decode_Bit_Tree
     (D       : in out LZMA_Range_Decoder;
      Stream  : Byte_Array;
      Probs   : in out LZMA_Prob_Array;
      Offset  : Natural;
      Bits    : Natural;
      Status  : in out Status_Code) return Natural
   is
      Node : Natural := 1;
   begin
      for I in 1 .. Bits loop
         Node :=
           Node * 2
           + LZMA_Decode_Bit (D, Stream, Probs (Offset + Node), Status);
         exit when Status /= Ok;
      end loop;

      return Node - 2 ** Bits;
   end LZMA_Decode_Bit_Tree;

   function LZMA_Decode_Reverse_Bit_Tree
     (D       : in out LZMA_Range_Decoder;
      Stream  : Byte_Array;
      Probs   : in out LZMA_Prob_Array;
      Offset  : Integer;
      Bits    : Natural;
      Status  : in out Status_Code) return Natural
   is
      Node   : Natural := 1;
      Symbol : Natural := 0;
   begin
      for Bit_Index in 0 .. Bits - 1 loop
         declare
            Bit : constant Natural :=
              LZMA_Decode_Bit
                (D, Stream, Probs (Natural (Offset + Node)), Status);
         begin
            Symbol := Symbol + Bit * (2 ** Bit_Index);
            Node := Node * 2 + Bit;
         end;
         exit when Status /= Ok;
      end loop;

      return Symbol;
   end LZMA_Decode_Reverse_Bit_Tree;

   function LZMA_Decode_Direct_Bits
     (D       : in out LZMA_Range_Decoder;
      Stream  : Byte_Array;
      Bits    : Natural;
      Status  : in out Status_Code) return Natural
   is
      Result : Natural := 0;
   begin
      if Bits = 0 then
         return 0;
      end if;

      for I in 1 .. Bits loop
         D.Range_Code := Interfaces.Shift_Right (D.Range_Code, 1);

         declare
            Bit : Natural := 0;
         begin
            if D.Code >= D.Range_Code then
               D.Code := D.Code - D.Range_Code;
               Bit := 1;
            end if;

            if D.Range_Code < LZMA_Top_Value then
               D.Range_Code := Interfaces.Shift_Left (D.Range_Code, 8);
               declare
                  Next_Byte : constant Interfaces.Unsigned_32 :=
                    LZMA_Read_Stream_Byte (D, Stream, Status);
               begin
                  D.Code := Interfaces.Shift_Left (D.Code, 8) or Next_Byte;
               end;
            end if;

            Result := Result * 2 + Bit;
         end;

         exit when Status /= Ok;
      end loop;

      return Result;
   end LZMA_Decode_Direct_Bits;

   function LZMA_Decode_Distance
     (D             : in out LZMA_Range_Decoder;
      Stream        : Byte_Array;
      Pos_Slot      : in out LZMA_Prob_Array;
      Pos_Special   : in out LZMA_Prob_Array;
      Pos_Align     : in out LZMA_Prob_Array;
      Len           : Natural;
      Status        : in out Status_Code) return Natural
   is
      Pos_State_For_Len : constant Natural :=
        Natural'Min (Len - LZMA_Min_Match_Length,
                     LZMA_Num_Len_To_Pos_States - 1);
      Slot              : constant Natural :=
        LZMA_Decode_Bit_Tree
          (D, Stream, Pos_Slot, Pos_State_For_Len * 64, 6, Status);
   begin
      if Status /= Ok then
         return 0;
      end if;

      if Slot < LZMA_Start_Pos_Model_Index then
         return Slot + 1;
      elsif Slot < LZMA_End_Pos_Model_Index then
         declare
            Footer_Bits : constant Natural := Slot / 2 - 1;
            Base        : constant Natural :=
              (2 + Slot mod 2) * (2 ** Footer_Bits);
            Offset      : constant Integer := Integer (Base) - Integer (Slot) - 1;
            Reduced     : constant Natural :=
              LZMA_Decode_Reverse_Bit_Tree
                (D, Stream, Pos_Special, Offset, Footer_Bits, Status);
         begin
            return Base + Reduced + 1;
         end;
      else
         declare
            Footer_Bits : constant Natural := Slot / 2 - 1;
            Base        : constant Natural :=
              (2 + Slot mod 2) * (2 ** Footer_Bits);
            Direct      : constant Natural :=
              LZMA_Decode_Direct_Bits
                (D, Stream, Footer_Bits - LZMA_Num_Align_Bits, Status);
            Align       : constant Natural :=
              LZMA_Decode_Reverse_Bit_Tree
                (D, Stream, Pos_Align, 0, LZMA_Num_Align_Bits, Status);
         begin
            return Base + Direct * LZMA_Align_Table_Size + Align + 1;
         end;
      end if;
   end LZMA_Decode_Distance;

   function LZMA_Decode_Len
     (D         : in out LZMA_Range_Decoder;
      Stream    : Byte_Array;
      Len       : in out LZMA_Len_Encoder;
      Pos_State : Natural;
      Status    : in out Status_Code) return Natural
   is
   begin
      if LZMA_Decode_Bit (D, Stream, Len.Choice (0), Status) = 0 then
         return
           LZMA_Decode_Bit_Tree
             (D, Stream, Len.Low, Pos_State * LZMA_Len_Low_Symbols, 3,
              Status);
      end if;

      if LZMA_Decode_Bit (D, Stream, Len.Choice (1), Status) = 0 then
         return
           LZMA_Len_Low_Symbols
           + LZMA_Decode_Bit_Tree
             (D, Stream, Len.Mid, Pos_State * LZMA_Len_Mid_Symbols, 3,
              Status);
      end if;

      return
        LZMA_Len_Low_Symbols + LZMA_Len_Mid_Symbols
        + LZMA_Decode_Bit_Tree (D, Stream, Len.High, 0, 8, Status);
   end LZMA_Decode_Len;

   function Decode_LZMA_Payload
     (Payload    : Byte_Array;
      Plain_Len  : Natural;
      Require_Full_Stream : Boolean;
      Initial_Rep_Distance : Natural;
      Use_Matched_Literals : Boolean;
      Status     : out Status_Code) return Byte_Array
   is
      Empty : constant Byte_Array (1 .. 0) := [others => 0];
   begin
      Status := Unsupported_Method;

      if Payload'Length < 9 then
         Status := Unexpected_End_Of_Input;
         return Empty;
      end if;

      declare
         Props_Size : constant Natural :=
           Natural (Payload (Payload'First + 2))
           + 256 * Natural (Payload (Payload'First + 3));
         Props_First : constant Natural := Payload'First + 4;
         Stream_First : constant Natural := Props_First + Props_Size;
      begin
         if Props_Size /= 5
           or else Stream_First > Payload'Last + 1
         then
            Status := Unsupported_Method;
            return Empty;
         end if;

         declare
            Props0 : constant Byte := Payload (Props_First);
            LCLP   : constant Natural := Natural (Props0) mod 9;
            Rest   : constant Natural := Natural (Props0) / 9;
            LC     : constant Natural := LCLP;
            LP     : constant Natural := Rest mod 5;
            PB     : constant Natural := Rest / 5;
         begin
            if not Valid_LZMA_Props (Props0) then
               Status := Unsupported_Method;
               return Empty;
            end if;

            declare
               Stream : constant Byte_Array :=
                 (if Stream_First > Payload'Last then Empty
                  else Payload (Stream_First .. Payload'Last));
               Pos_States   : constant Natural := 2 ** PB;
               Literal_Ctxs : constant Natural := 2 ** (LC + LP);
               Is_Match     : LZMA_Prob_Array
                 (0 .. LZMA_Num_States * LZMA_Num_Pos_States_Max - 1);
               Is_Rep       : LZMA_Prob_Array (0 .. LZMA_Num_States - 1);
               Is_Rep_G0    : LZMA_Prob_Array (0 .. LZMA_Num_States - 1);
               Is_Rep_G1    : LZMA_Prob_Array (0 .. LZMA_Num_States - 1);
               Is_Rep_G2    : LZMA_Prob_Array (0 .. LZMA_Num_States - 1);
               Is_Rep0_Long : LZMA_Prob_Array
                 (0 .. LZMA_Num_States * LZMA_Num_Pos_States_Max - 1);
               Match_Len    : LZMA_Len_Encoder;
               Rep_Len      : LZMA_Len_Encoder;
               Pos_Slot     : LZMA_Prob_Array
                 (0 .. LZMA_Num_Len_To_Pos_States * 64 - 1);
               Pos_Special  : LZMA_Prob_Array
                 (0 .. LZMA_Num_Full_Distances - LZMA_End_Pos_Model_Index - 1);
               Pos_Align    : LZMA_Prob_Array (0 .. LZMA_Align_Table_Size - 1);
               Literals     : LZMA_Prob_Array
                 (0 .. Literal_Ctxs * LZMA_Literal_Probs - 1);
               D            : LZMA_Range_Decoder;
               State        : Natural := 0;
               Prev         : Byte := 0;
               Rep0         : Natural := Initial_Rep_Distance;
               Rep1         : Natural := Initial_Rep_Distance;
               Rep2         : Natural := Initial_Rep_Distance;
               Rep3         : Natural := Initial_Rep_Distance;
               Plain        : Byte_Array (1 .. Natural'Max (1, Plain_Len)) :=
                 [others => 0];
               Out_Pos      : Natural := 0;
               Local_Status : Status_Code := Ok;
            begin
               if Stream'Length < 5 then
                  Status := Unexpected_End_Of_Input;
                  return Empty;
               end if;

               LZMA_Init_Probs (Is_Match);
               LZMA_Init_Probs (Is_Rep);
               LZMA_Init_Probs (Is_Rep_G0);
               LZMA_Init_Probs (Is_Rep_G1);
               LZMA_Init_Probs (Is_Rep_G2);
               LZMA_Init_Probs (Is_Rep0_Long);
               LZMA_Init_Len (Match_Len);
               LZMA_Init_Len (Rep_Len);
               LZMA_Init_Probs (Pos_Slot);
               LZMA_Init_Probs (Pos_Special);
               LZMA_Init_Probs (Pos_Align);
               LZMA_Init_Probs (Literals);
               LZMA_Decoder_Init (D, Stream, Local_Status);

               while Local_Status = Ok and then Out_Pos < Plain_Len loop
                  declare
                     Pos_State : constant Natural := Out_Pos mod Pos_States;
                     Match_Bit : constant Natural :=
                       LZMA_Decode_Bit
                         (D, Stream,
                          Is_Match (State * LZMA_Num_Pos_States_Max + Pos_State),
                          Local_Status);
                  begin
                     if Local_Status /= Ok then
                        exit;
                     end if;

                     if Match_Bit = 0 then
                        declare
                           Context : constant Natural :=
                             LZMA_Literal_Context (LC, LP, Out_Pos, Prev);
                           Symbol  : Natural := 1;
                        begin
                           if Use_Matched_Literals
                             and then State >= 7
                             and then Rep0 > 0
                             and then Rep0 <= Out_Pos
                           then
                              declare
                                 Match_Byte : Natural :=
                                   Natural (Plain (Out_Pos - Rep0 + 1));
                              begin
                                 while Symbol < 16#100# loop
                                    Match_Byte := Match_Byte * 2;
                                    declare
                                       Match_Bit_Literal : constant Natural :=
                                         ((Match_Byte / 16#100#) mod 2)
                                         * 16#100#;
                                       Decoded_Bit : constant Natural :=
                                         LZMA_Decode_Bit
                                           (D, Stream,
                                            Literals
                                              (Context * LZMA_Literal_Probs
                                               + 16#100# + Match_Bit_Literal
                                               + Symbol),
                                            Local_Status);
                                    begin
                                       Symbol := Symbol * 2 + Decoded_Bit;
                                       exit when Local_Status /= Ok
                                         or else Match_Bit_Literal /=
                                           Decoded_Bit * 16#100#;
                                    end;
                                 end loop;
                              end;
                           end if;

                           while Symbol < 16#100# loop
                              Symbol :=
                                Symbol * 2
                                + LZMA_Decode_Bit
                                  (D, Stream,
                                   Literals
                                     (Context * LZMA_Literal_Probs + Symbol),
                                   Local_Status);
                              exit when Local_Status /= Ok;
                           end loop;

                           if Local_Status /= Ok then
                              exit;
                           end if;

                           Out_Pos := Out_Pos + 1;
                           Plain (Out_Pos) := Byte (Symbol - 16#100#);
                           Prev := Plain (Out_Pos);
                           State := LZMA_Literal_State_After (State);
                        end;
                     else
                        if LZMA_Decode_Bit
                          (D, Stream, Is_Rep (State), Local_Status) /= 0
                        then
                           declare
                              Distance : Natural := Rep0;
                              Len      : Natural := LZMA_Min_Match_Length;
                           begin
                              if LZMA_Decode_Bit
                                (D, Stream, Is_Rep_G0 (State),
                                 Local_Status) = 0
                              then
                                 if LZMA_Decode_Bit
                                   (D, Stream,
                                    Is_Rep0_Long
                                      (State * LZMA_Num_Pos_States_Max + Pos_State),
                                    Local_Status) = 0
                                 then
                                    Len := 1;
                                    State := LZMA_Short_Rep_State_After (State);
                                 else
                                    Len :=
                                      LZMA_Decode_Len
                                        (D, Stream, Rep_Len, Pos_State,
                                         Local_Status)
                                      + LZMA_Min_Match_Length;
                                    State := LZMA_Rep_State_After (State);
                                 end if;
                              else
                                 if LZMA_Decode_Bit
                                   (D, Stream, Is_Rep_G1 (State),
                                    Local_Status) = 0
                                 then
                                    Distance := Rep1;
                                 else
                                    if LZMA_Decode_Bit
                                      (D, Stream, Is_Rep_G2 (State),
                                       Local_Status) = 0
                                    then
                                       Distance := Rep2;
                                    else
                                       Distance := Rep3;
                                       Rep3 := Rep2;
                                    end if;
                                    Rep2 := Rep1;
                                 end if;
                                 Rep1 := Rep0;
                                 Rep0 := Distance;
                                 Len :=
                                   LZMA_Decode_Len
                                     (D, Stream, Rep_Len, Pos_State,
                                      Local_Status)
                                   + LZMA_Min_Match_Length;
                                 State := LZMA_Rep_State_After (State);
                              end if;

                              if Local_Status /= Ok then
                                 exit;
                              end if;

                              if Distance = 0
                                or else Distance > Out_Pos
                                or else Len > Plain_Len - Out_Pos
                              then
                                 Status := Unsupported_Method;
                                 return Empty;
                              end if;

                              for I in 1 .. Len loop
                                 Out_Pos := Out_Pos + 1;
                                 Plain (Out_Pos) := Plain (Out_Pos - Distance);
                              end loop;

                              Prev := Plain (Out_Pos);
                           end;
                        else

                           declare
                              Len_Symbol : constant Natural :=
                                LZMA_Decode_Len
                                  (D, Stream, Match_Len, Pos_State,
                                   Local_Status);
                              Len        : constant Natural :=
                                Len_Symbol + LZMA_Min_Match_Length;
                              Distance   : constant Natural :=
                                LZMA_Decode_Distance
                                  (D, Stream, Pos_Slot, Pos_Special, Pos_Align,
                                   Len, Local_Status);
                           begin
                              if Local_Status /= Ok then
                                 exit;
                              end if;

                              if Distance > Out_Pos
                                or else Len > Plain_Len - Out_Pos
                              then
                                 Status := Unsupported_Method;
                                 return Empty;
                              end if;

                              for I in 1 .. Len loop
                                 Out_Pos := Out_Pos + 1;
                                 Plain (Out_Pos) := Plain (Out_Pos - Distance);
                              end loop;

                              Rep3 := Rep2;
                              Rep2 := Rep1;
                              Rep1 := Rep0;
                              Rep0 := Distance;
                              Prev := Plain (Out_Pos);
                              State := LZMA_Match_State_After (State);
                           end;
                        end if;
                     end if;
                  end;
               end loop;

               if Local_Status /= Ok then
                  Status := Local_Status;
                  return Empty;
               end if;

               if Require_Full_Stream and then D.Pos /= Stream'Length then
                  Status := Unsupported_Method;
                  return Empty;
               end if;

               if Plain_Len = 0 then
                  Status := Ok;
                  return Empty;
               end if;

               Status := Ok;
               return Plain (1 .. Plain_Len);
            end;
         end;
      end;
   exception
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end Decode_LZMA_Payload;

   function Decode_ZIP_LZMA_Payload
     (Payload    : Byte_Array;
      Plain_Len  : Natural;
      Status     : out Status_Code) return Byte_Array
   is
   begin
      return Decode_LZMA_Payload
        (Payload, Plain_Len, Require_Full_Stream => True,
         Initial_Rep_Distance => 1, Use_Matched_Literals => True,
         Status => Status);
   end Decode_ZIP_LZMA_Payload;

   function Extract_ZIP_Native_LZMA_Entry
     (Archive_Image : Byte_Array;
      Entry_Name    : String;
      Status        : out Status_Code) return Byte_Array
   is
      Empty : constant Byte_Array (1 .. 0) := [others => 0];
      Pos   : Natural := Archive_Image'First;
      Found_LZMA_Name : Boolean := False;
   begin
      Status := Unsupported_Method;

      if Entry_Name'Length = 0 or else Archive_Image'Length < 46 then
         return Empty;
      end if;

      while Pos <= Archive_Image'Last - 45 loop
         if ZIP_U32_At (Archive_Image, Pos) = 16#0201_4B50# then
            declare
               Flags            : constant Interfaces.Unsigned_16 :=
                 ZIP_U16_At (Archive_Image, Pos + 8);
               Method           : constant Interfaces.Unsigned_16 :=
                 ZIP_U16_At (Archive_Image, Pos + 10);
               Crc              : constant Interfaces.Unsigned_32 :=
                 ZIP_U32_At (Archive_Image, Pos + 16);
               Compressed_32    : constant Interfaces.Unsigned_32 :=
                 ZIP_U32_At (Archive_Image, Pos + 20);
               Uncompressed_32  : constant Interfaces.Unsigned_32 :=
                 ZIP_U32_At (Archive_Image, Pos + 24);
               Name_Len         : constant Natural :=
                 Natural (ZIP_U16_At (Archive_Image, Pos + 28));
               Extra_Len        : constant Natural :=
                 Natural (ZIP_U16_At (Archive_Image, Pos + 30));
               Comment_Len      : constant Natural :=
                 Natural (ZIP_U16_At (Archive_Image, Pos + 32));
               Local_Offset_32  : constant Interfaces.Unsigned_32 :=
                 ZIP_U32_At (Archive_Image, Pos + 42);
               Name_First       : constant Natural := Pos + 46;
               Record_After     : constant Natural :=
                 Name_First + Name_Len + Extra_Len + Comment_Len;
            begin
               if Record_After - 1 > Archive_Image'Last then
                  Status := Unexpected_End_Of_Input;
                  return Empty;
               end if;

               if ZIP_Name_Equals
                 (Archive_Image, Name_First, Name_Len, Entry_Name)
               then
                  if Method /= 14 then
                     return Empty;
                  end if;

                  Found_LZMA_Name := True;
                  if (Flags and 1) /= 0 then
                     Status := Unsupported_Method;
                     return Empty;
                  end if;

                  declare
                     Compressed   : Interfaces.Unsigned_64 := 0;
                     Uncompressed : Interfaces.Unsigned_64 := 0;
                     Local_Offset : Interfaces.Unsigned_64 := 0;
                  begin
                     if not Resolve_ZIP64_Central_Fields
                       (Archive_Image,
                        Name_First + Name_Len,
                        Extra_Len,
                        Compressed_32,
                        Uncompressed_32,
                        Local_Offset_32,
                        Compressed,
                        Uncompressed,
                        Local_Offset)
                       or else Compressed >
                         Interfaces.Unsigned_64 (Natural'Last)
                       or else Uncompressed >
                         Interfaces.Unsigned_64 (Natural'Last)
                       or else Local_Offset > Interfaces.Unsigned_64 (Natural'Last)
                     then
                        Status := Unsupported_Method;
                        return Empty;
                     end if;

                     declare
                        Local : constant Natural :=
                          Archive_Image'First + Natural (Local_Offset);
                     begin
                        if Local < Archive_Image'First
                          or else Local + 29 > Archive_Image'Last
                          or else ZIP_U32_At (Archive_Image, Local) /=
                            16#0403_4B50#
                          or else ZIP_U16_At (Archive_Image, Local + 8) /= 14
                        then
                           Status := Unexpected_End_Of_Input;
                           return Empty;
                        end if;

                        declare
                           Local_Name_Len  : constant Natural :=
                             Natural (ZIP_U16_At (Archive_Image, Local + 26));
                           Local_Extra_Len : constant Natural :=
                             Natural (ZIP_U16_At (Archive_Image, Local + 28));
                           Payload_First   : constant Natural :=
                             Local + 30 + Local_Name_Len + Local_Extra_Len;
                           Payload_Len     : constant Natural :=
                             Natural (Compressed);
                           Plain_Len       : constant Natural :=
                             Natural (Uncompressed);
                        begin
                           if Payload_First > Archive_Image'Last
                             or else (Payload_Len > 0
                                      and then Payload_Len - 1 >
                                        Archive_Image'Last - Payload_First)
                           then
                              Status := Unexpected_End_Of_Input;
                              return Empty;
                           end if;

                           declare
                              Payload : Byte_Array (1 .. Payload_Len);
                           begin
                              for I in Payload'Range loop
                                 Payload (I) := Archive_Image (Payload_First + I - 1);
                              end loop;

                              declare
                                 Plain : constant Byte_Array :=
                                   Decode_ZIP_LZMA_Payload
                                     (Payload, Plain_Len, Status);
                              begin
                                 if Status /= Ok then
                                    return Empty;
                                 end if;

                                 if Zlib.CRC32 (Plain) /= Crc then
                                    Status := Invalid_Checksum;
                                    return Empty;
                                 end if;

                                 Status := Ok;
                                 return Plain;
                              end;
                           end;
                        end;
                     end;
                  end;
               end if;

               Pos := Record_After;
            end;
         else
            Pos := Pos + 1;
         end if;
      end loop;

      Status := (if Found_LZMA_Name then Invalid_Block_Type else Unsupported_Method);
      return Empty;
   exception
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end Extract_ZIP_Native_LZMA_Entry;

   function Extract_ZIP_External_Entry
     (Archive_Image : Byte_Array;
      Temp_Base     : String;
      Entry_Name    : String;
      Password      : String;
      Status        : out Status_Code) return Byte_Array
   is
      Empty        : constant Byte_Array (1 .. 0) := [others => 0];
      pragma Unreferenced (Temp_Base);
   begin
      Status := Unsupported_Method;

      if Password'Length = 0 then
         declare
            Native_Status : Status_Code := Unsupported_Method;
            Native_Result : constant Byte_Array :=
              Extract_ZIP_Native_BZip2_Entry
                (Archive_Image, Entry_Name, Native_Status);
         begin
            if Native_Status /= Unsupported_Method then
               Status := Native_Status;
               return Native_Result;
            end if;
         end;
         declare
            Native_Status : Status_Code := Unsupported_Method;
            Native_Result : constant Byte_Array :=
              Extract_ZIP_Native_LZMA_Entry
                (Archive_Image, Entry_Name, Native_Status);
         begin
            if Native_Status /= Unsupported_Method then
               Status := Native_Status;
               return Native_Result;
            end if;
         end;
         declare
            Native_Status : Status_Code := Unsupported_Method;
            Native_Result : constant Byte_Array :=
              Extract_ZIP_Native_Zstd_Entry
                (Archive_Image, Entry_Name, Native_Status);
         begin
            if Native_Status /= Unsupported_Method then
               Status := Native_Status;
               return Native_Result;
            end if;
         end;
      end if;
      return Empty;
   exception
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end Extract_ZIP_External_Entry;

   function ZIP_U16_At
     (Data : Byte_Array;
      Pos  : Natural) return Interfaces.Unsigned_16
   is
   begin
      return Interfaces.Unsigned_16 (Data (Pos))
        or Interfaces.Shift_Left (Interfaces.Unsigned_16 (Data (Pos + 1)), 8);
   end ZIP_U16_At;

   function ZIP_U32_At
     (Data : Byte_Array;
      Pos  : Natural) return Interfaces.Unsigned_32
   is
   begin
      return Interfaces.Unsigned_32 (Data (Pos))
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (Pos + 1)), 8)
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (Pos + 2)), 16)
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (Pos + 3)), 24);
   end ZIP_U32_At;

   function ZIP_U64_At
     (Data : Byte_Array;
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
   end ZIP_U64_At;

   function ZIP_Method_Id (Method_Name : String) return Interfaces.Unsigned_16 is
   begin
      if Method_Name = "BZip2" or else Method_Name = "bzip2" then
         return 12;
      elsif Method_Name = "LZMA" or else Method_Name = "lzma" then
         return 14;
      elsif Method_Name = "PPMd" or else Method_Name = "ppmd" then
         return 98;
      elsif Method_Name = "ZSTD" or else Method_Name = "Zstd" or else Method_Name = "zstd" then
         return 93;
      else
         return 0;
      end if;
   end ZIP_Method_Id;

   --  Locate the central directory: scan back for the EOCD record (0x06054B50)
   --  and, when its fields are ZIP64-escaped, follow the ZIP64 locator to the
   --  ZIP64 EOCD. Returns the first CD record position and the entry count.
   function ZIP_Find_Central
     (Archive  : Byte_Array;
      CD_First : out Natural;
      CD_Count : out Natural) return Boolean
   is
      Last : constant Natural := Archive'Last;
   begin
      CD_First := 0;
      CD_Count := 0;
      if Archive'Length < 22 then
         return False;
      end if;
      for P in reverse Archive'First .. Last - 21 loop
         if ZIP_U32_At (Archive, P) = 16#0605_4B50# then
            declare
               Count16 : constant Interfaces.Unsigned_16 :=
                 ZIP_U16_At (Archive, P + 10);
               Off32   : constant Interfaces.Unsigned_32 :=
                 ZIP_U32_At (Archive, P + 16);
            begin
               if (Count16 = 16#FFFF# or else Off32 = 16#FFFF_FFFF#)
                 and then P - 20 >= Archive'First
                 and then ZIP_U32_At (Archive, P - 20) = 16#0706_4B50#
               then
                  declare
                     Z64_Off : constant Interfaces.Unsigned_64 :=
                       ZIP_U64_At (Archive, P - 20 + 8);
                  begin
                     if Z64_Off <= Interfaces.Unsigned_64 (Natural'Last) then
                        declare
                           Z64 : constant Natural :=
                             Archive'First + Natural (Z64_Off);
                        begin
                           if Z64 >= Archive'First
                             and then Z64 + 55 <= Last
                             and then ZIP_U32_At (Archive, Z64) = 16#0606_4B50#
                           then
                              if ZIP_U64_At (Archive, Z64 + 32) <=
                                   Interfaces.Unsigned_64 (Natural'Last)
                                and then ZIP_U64_At (Archive, Z64 + 48) <=
                                  Interfaces.Unsigned_64 (Natural'Last)
                              then
                                 CD_Count :=
                                   Natural (ZIP_U64_At (Archive, Z64 + 32));
                                 CD_First :=
                                   Archive'First +
                                   Natural (ZIP_U64_At (Archive, Z64 + 48));
                                 return CD_First <= Last + 1;
                              end if;
                           end if;
                        end;
                     end if;
                  end;
               end if;
               CD_Count := Natural (Count16);
               CD_First := Archive'First + Natural (Off32);
               return CD_First <= Last + 1;
            end;
         end if;
      end loop;
      return False;
   end ZIP_Find_Central;

   function List_ZIP_Entries
     (Archive_Image : Byte_Array;
      Status        : out Status_Code) return Archive_Entry_Array
   is
      No       : constant Archive_Entry_Array (1 .. 0) :=
        [others => (others => <>)];
      CD_First : Natural := 0;
      CD_Count : Natural := 0;
   begin
      Status := Invalid_Header;
      if not ZIP_Find_Central (Archive_Image, CD_First, CD_Count) then
         return No;
      end if;

      declare
         Result : Archive_Entry_Array (1 .. CD_Count);
         Pos    : Natural := CD_First;
      begin
         for I in 1 .. CD_Count loop
            if Pos < Archive_Image'First
              or else Pos + 45 > Archive_Image'Last
              or else ZIP_U32_At (Archive_Image, Pos) /= 16#0201_4B50#
            then
               return No;
            end if;
            declare
               Method   : constant Interfaces.Unsigned_16 :=
                 ZIP_U16_At (Archive_Image, Pos + 10);
               Crc      : constant Interfaces.Unsigned_32 :=
                 ZIP_U32_At (Archive_Image, Pos + 16);
               Comp_32  : constant Interfaces.Unsigned_32 :=
                 ZIP_U32_At (Archive_Image, Pos + 20);
               Unc_32   : constant Interfaces.Unsigned_32 :=
                 ZIP_U32_At (Archive_Image, Pos + 24);
               Name_Len : constant Natural :=
                 Natural (ZIP_U16_At (Archive_Image, Pos + 28));
               Extra_Len : constant Natural :=
                 Natural (ZIP_U16_At (Archive_Image, Pos + 30));
               Cmt_Len  : constant Natural :=
                 Natural (ZIP_U16_At (Archive_Image, Pos + 32));
               Off_32   : constant Interfaces.Unsigned_32 :=
                 ZIP_U32_At (Archive_Image, Pos + 42);
               Name_First : constant Natural := Pos + 46;
               Comp, Unc, Off : Interfaces.Unsigned_64 := 0;
            begin
               if Name_First + Name_Len + Extra_Len + Cmt_Len - 1 >
                    Archive_Image'Last
               then
                  return No;
               end if;
               if not Resolve_ZIP64_Central_Fields
                 (Archive_Image, Name_First + Name_Len, Extra_Len,
                  Comp_32, Unc_32, Off_32, Comp, Unc, Off)
               then
                  Comp := Interfaces.Unsigned_64 (Comp_32);
                  Unc  := Interfaces.Unsigned_64 (Unc_32);
               end if;
               declare
                  Name_Str : String (1 .. Name_Len);
               begin
                  for J in 1 .. Name_Len loop
                     Name_Str (J) :=
                       Character'Val
                         (Natural (Archive_Image (Name_First + J - 1)));
                  end loop;
                  Result (I) :=
                    (Name              =>
                       US.To_Unbounded_String (Name_Str),
                     Is_Directory      =>
                       Name_Len > 0 and then Name_Str (Name_Len) = '/',
                     Compression       => Method,
                     Uncompressed_Size => Unc,
                     Compressed_Size   => Comp,
                     CRC_32            => Crc);
               end;
               Pos := Name_First + Name_Len + Extra_Len + Cmt_Len;
            end;
         end loop;
         Status := Ok;
         return Result;
      end;
   exception
      when others =>
         Status := Invalid_Header;
         return No;
   end List_ZIP_Entries;

   function Extract_ZIP
     (Archive_Image : Byte_Array;
      Entry_Name    : String;
      Status        : out Status_Code) return Byte_Array
   is
      Empty    : constant Byte_Array (1 .. 0) := [others => 0];
      CD_First : Natural := 0;
      CD_Count : Natural := 0;
      Pos      : Natural := 0;
   begin
      Status := Unsupported_Method;
      if Entry_Name'Length = 0
        or else not ZIP_Find_Central (Archive_Image, CD_First, CD_Count)
      then
         Status := Invalid_Header;
         return Empty;
      end if;

      Pos := CD_First;
      for I in 1 .. CD_Count loop
         exit when Pos + 45 > Archive_Image'Last
           or else ZIP_U32_At (Archive_Image, Pos) /= 16#0201_4B50#;
         declare
            Flags    : constant Interfaces.Unsigned_16 :=
              ZIP_U16_At (Archive_Image, Pos + 8);
            Method   : constant Interfaces.Unsigned_16 :=
              ZIP_U16_At (Archive_Image, Pos + 10);
            Crc      : constant Interfaces.Unsigned_32 :=
              ZIP_U32_At (Archive_Image, Pos + 16);
            Comp_32  : constant Interfaces.Unsigned_32 :=
              ZIP_U32_At (Archive_Image, Pos + 20);
            Unc_32   : constant Interfaces.Unsigned_32 :=
              ZIP_U32_At (Archive_Image, Pos + 24);
            Name_Len : constant Natural :=
              Natural (ZIP_U16_At (Archive_Image, Pos + 28));
            Extra_Len : constant Natural :=
              Natural (ZIP_U16_At (Archive_Image, Pos + 30));
            Cmt_Len  : constant Natural :=
              Natural (ZIP_U16_At (Archive_Image, Pos + 32));
            Off_32   : constant Interfaces.Unsigned_32 :=
              ZIP_U32_At (Archive_Image, Pos + 42);
            Name_First : constant Natural := Pos + 46;
         begin
            exit when Name_First + Name_Len + Extra_Len + Cmt_Len - 1 >
              Archive_Image'Last;

            if ZIP_Name_Equals
              (Archive_Image, Name_First, Name_Len, Entry_Name)
            then
               if (Flags and 1) /= 0 then
                  Status := Unsupported_Method;   --  encrypted
                  return Empty;
               end if;
               if Method /= 0 and then Method /= 8 then
                  --  Non-Deflate methods go through the codec bridge.
                  return Extract_ZIP_External_Entry
                    (Archive_Image, "", Entry_Name, "", Status);
               end if;

               declare
                  Comp, Unc, Off : Interfaces.Unsigned_64 := 0;
               begin
                  if not Resolve_ZIP64_Central_Fields
                    (Archive_Image, Name_First + Name_Len, Extra_Len,
                     Comp_32, Unc_32, Off_32, Comp, Unc, Off)
                  then
                     Comp := Interfaces.Unsigned_64 (Comp_32);
                     Unc  := Interfaces.Unsigned_64 (Unc_32);
                     Off  := Interfaces.Unsigned_64 (Off_32);
                  end if;
                  if Off > Interfaces.Unsigned_64 (Natural'Last)
                    or else Comp > Interfaces.Unsigned_64 (Natural'Last)
                    or else Unc > Interfaces.Unsigned_64 (Natural'Last)
                  then
                     Status := Unsupported_Method;
                     return Empty;
                  end if;

                  declare
                     Local : constant Natural :=
                       Archive_Image'First + Natural (Off);
                  begin
                     if Local < Archive_Image'First
                       or else Local + 29 > Archive_Image'Last
                       or else ZIP_U32_At (Archive_Image, Local) /=
                         16#0403_4B50#
                     then
                        Status := Unexpected_End_Of_Input;
                        return Empty;
                     end if;
                     declare
                        L_Name : constant Natural :=
                          Natural (ZIP_U16_At (Archive_Image, Local + 26));
                        L_Extra : constant Natural :=
                          Natural (ZIP_U16_At (Archive_Image, Local + 28));
                        Data_First : constant Natural :=
                          Local + 30 + L_Name + L_Extra;
                        Comp_Len   : constant Natural := Natural (Comp);
                        Unc_Len    : constant Natural := Natural (Unc);
                     begin
                        if Data_First > Archive_Image'Last + 1
                          or else (Comp_Len > 0
                                   and then Comp_Len - 1 >
                                     Archive_Image'Last - Data_First)
                        then
                           Status := Unexpected_End_Of_Input;
                           return Empty;
                        end if;
                        declare
                           Payload : constant Byte_Array :=
                             (if Comp_Len = 0 then Empty
                              else Archive_Image
                                     (Data_First ..
                                      Data_First + Comp_Len - 1));
                           Dec_Status : Status_Code := Ok;
                           Plain : constant Byte_Array :=
                             (if Method = 0 then Payload
                              else Inflate_Raw (Payload, Dec_Status));
                        begin
                           if Method = 8 and then Dec_Status /= Ok then
                              Status := Dec_Status;
                              return Empty;
                           end if;
                           if Plain'Length /= Unc_Len
                             or else CRC32 (Plain) /= Crc
                           then
                              Status := Invalid_Checksum;
                              return Empty;
                           end if;
                           Status := Ok;
                           return Plain;
                        end;
                     end;
                  end;
               end;
            end if;
            Pos := Name_First + Name_Len + Extra_Len + Cmt_Len;
         end;
      end loop;

      Status := Unsupported_Method;
      return Empty;
   exception
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end Extract_ZIP;

   function Compress_ZIP_Native_BZip2_File
     (Input_Path        : String;
      Method            : out Interfaces.Unsigned_16;
      Crc32             : out Interfaces.Unsigned_32;
      Uncompressed_Size : out Interfaces.Unsigned_64;
      Status            : out Status_Code) return Byte_Array
   is
      Empty       : constant Byte_Array (1 .. 0) := [others => 0];
      Read_Status : Status_Code := Ok;
   begin
      Method := 0;
      Crc32 := 0;
      Uncompressed_Size := 0;
      Status := Unsupported_Method;

      if not Ada.Directories.Exists (Input_Path) then
         Status := Input_File_Error;
         return Empty;
      end if;

      declare
         Plain : constant Byte_Array := Read_File (Input_Path, Read_Status);
      begin
         if Read_Status /= Ok then
            Status := Read_Status;
            return Empty;
         end if;

         if Interfaces.Unsigned_64 (Plain'Length) >
           Interfaces.Unsigned_64 (Interfaces.C.unsigned'Last)
         then
            Status := Unsupported_Method;
            return Empty;
         end if;

         declare
            Bound : constant Natural := Plain'Length + Plain'Length / 100 + 601;
            Output : Byte_Array (1 .. Bound);
            Output_Len : aliased Interfaces.C.unsigned :=
              Interfaces.C.unsigned (Bound);
            Source_Address : constant System.Address :=
              (if Plain'Length = 0 then
                  System.Null_Address
               else
                  Plain (Plain'First)'Address);
            Result : Interfaces.C.int;
         begin
            Result :=
              BZ2_bzBuffToBuffCompress
                (Dest        => Output (Output'First)'Address,
                 Dest_Len    => Output_Len'Access,
                 Source      => Source_Address,
                 Source_Len  => Interfaces.C.unsigned (Plain'Length),
                 Block_Size  => 9,
                 Verbosity   => 0,
                 Work_Factor => 30);

            if Result /= 0 then
               Status := Unsupported_Method;
               return Empty;
            end if;

            declare
               Used : constant Natural := Natural (Output_Len);
               Compressed : Byte_Array (1 .. Used);
            begin
               for I in Compressed'Range loop
                  Compressed (I) := Output (I);
               end loop;

               Method := 12;
               Crc32 := Zlib.CRC32 (Plain);
               Uncompressed_Size := Interfaces.Unsigned_64 (Plain'Length);
               Status := Ok;
               return Compressed;
            end;
         end;
      end;
   exception
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end Compress_ZIP_Native_BZip2_File;

   function Compress_ZIP_Native_Zstd_File
     (Input_Path        : String;
      Method            : out Interfaces.Unsigned_16;
      Crc32             : out Interfaces.Unsigned_32;
      Uncompressed_Size : out Interfaces.Unsigned_64;
      Status            : out Status_Code) return Byte_Array
   is
      Empty       : constant Byte_Array (1 .. 0) := [others => 0];
      Read_Status : Status_Code := Ok;
   begin
      Method := 0;
      Crc32 := 0;
      Uncompressed_Size := 0;
      Status := Unsupported_Method;

      if not Ada.Directories.Exists (Input_Path) then
         Status := Input_File_Error;
         return Empty;
      end if;

      declare
         Plain : constant Byte_Array := Read_File (Input_Path, Read_Status);
      begin
         if Read_Status /= Ok then
            Status := Read_Status;
            return Empty;
         end if;

         declare
            Source_Size : constant Interfaces.C.size_t :=
              Interfaces.C.size_t (Plain'Length);
            Bound_Size  : constant Interfaces.C.size_t :=
              ZSTD_compressBound (Source_Size);
            Bound       : constant Natural := Natural (Bound_Size);
            Output      : Byte_Array (1 .. Bound);
            Source_Address : constant System.Address :=
              (if Plain'Length = 0 then
                  System.Null_Address
               else
                  Plain (Plain'First)'Address);
            Result_Size : Interfaces.C.size_t;
         begin
            Result_Size :=
              ZSTD_compress
                (Dst          => Output (Output'First)'Address,
                 Dst_Capacity => Bound_Size,
                 Src          => Source_Address,
                 Src_Size     => Source_Size,
                 Level        => 3);

            if ZSTD_isError (Result_Size) /= 0 then
               Status := Unsupported_Method;
               return Empty;
            end if;

            declare
               Used       : constant Natural := Natural (Result_Size);
               Compressed : Byte_Array (1 .. Used);
            begin
               for I in Compressed'Range loop
                  Compressed (I) := Output (I);
               end loop;

               Method := 93;
               Crc32 := Zlib.CRC32 (Plain);
               Uncompressed_Size := Interfaces.Unsigned_64 (Plain'Length);
               Status := Ok;
               return Compressed;
            end;
         end;
      end;
   exception
      when others =>
         Status := Unsupported_Method;
      return Empty;
   end Compress_ZIP_Native_Zstd_File;

   function Compress_ZIP_Native_LZMA_File
     (Input_Path        : String;
      Method            : out Interfaces.Unsigned_16;
      Crc32             : out Interfaces.Unsigned_32;
      Uncompressed_Size : out Interfaces.Unsigned_64;
      Status            : out Status_Code) return Byte_Array
   is
      Empty       : constant Byte_Array (1 .. 0) := [others => 0];
      Read_Status : Status_Code := Ok;
   begin
      Method := 0;
      Crc32 := 0;
      Uncompressed_Size := 0;
      Status := Unsupported_Method;

      if not Ada.Directories.Exists (Input_Path) then
         Status := Input_File_Error;
         return Empty;
      end if;

      declare
         Plain : constant Byte_Array := Read_File (Input_Path, Read_Status);
      begin
         if Read_Status /= Ok then
            Status := Read_Status;
            return Empty;
         end if;

         declare
            Raw_Output : constant Byte_Array := LZMA_Encode_Bounded (Plain);
            Props : constant Byte_Array (1 .. 5) :=
              [1 => Byte ((LZMA_Default_PB * 5 + LZMA_Default_LP) * 9
                          + LZMA_Default_LC),
               2 => Byte (LZMA_Default_Dict and 16#FF#),
               3 => Byte (Interfaces.Shift_Right (LZMA_Default_Dict, 8)
                          and 16#FF#),
               4 => Byte (Interfaces.Shift_Right (LZMA_Default_Dict, 16)
                          and 16#FF#),
               5 => Byte (Interfaces.Shift_Right (LZMA_Default_Dict, 24)
                          and 16#FF#)];
            Payload : Byte_Array (1 .. Raw_Output'Length + 9);
         begin
            Payload (1) := 9;
            Payload (2) := 4;
            Payload (3) := 5;
            Payload (4) := 0;
            for I in Props'Range loop
               Payload (I + 4) := Props (I);
            end loop;
            for I in Raw_Output'Range loop
               Payload (I - Raw_Output'First + 10) := Raw_Output (I);
            end loop;

            Method := 14;
            Crc32 := Zlib.CRC32 (Plain);
            Uncompressed_Size := Interfaces.Unsigned_64 (Plain'Length);
            Status := Ok;
            return Payload;
         end;
      end;
   exception
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end Compress_ZIP_Native_LZMA_File;

   function Compress_ZIP_External_File
     (Input_Path        : String;
      Temp_Base         : String;
      Method_Name       : String;
      Method            : out Interfaces.Unsigned_16;
      Crc32             : out Interfaces.Unsigned_32;
      Uncompressed_Size : out Interfaces.Unsigned_64;
      Status            : out Status_Code) return Byte_Array
   is
      Empty        : constant Byte_Array (1 .. 0) := [others => 0];
      pragma Unreferenced (Temp_Base);
      Expected     : constant Interfaces.Unsigned_16 := ZIP_Method_Id (Method_Name);
   begin
      Method := 0;
      Crc32 := 0;
      Uncompressed_Size := 0;
      Status := Unsupported_Method;

      if Expected = 12 then
         return
           Compress_ZIP_Native_BZip2_File
             (Input_Path, Method, Crc32, Uncompressed_Size, Status);
      elsif Expected = 93 then
         return
           Compress_ZIP_Native_Zstd_File
             (Input_Path, Method, Crc32, Uncompressed_Size, Status);
      elsif Expected = 14 then
         return
           Compress_ZIP_Native_LZMA_File
             (Input_Path, Method, Crc32, Uncompressed_Size, Status);
      end if;

      if Expected = 0 then
         return Empty;
      end if;
      return Empty;
   exception
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end Compress_ZIP_External_File;

   function Seven_Zip_Output_File_Writable (Output_Path : String) return Boolean;
   function Seven_Zip_Input_Path_Readable (Input_Path : String) return Boolean;

   procedure Seven_Zip_External_File
     (Input_Path  : String;
      Output_Path : String;
      Method_Name : String;
      Solid       : Boolean;
      Password    : String;
      Status      : out Status_Code)
   is
      pragma Unreferenced (Method_Name, Solid, Password);
   begin
      Status := Unsupported_Method;

      if not Ada.Directories.Exists (Input_Path) then
         Status := Input_File_Error;
         return;
      end if;

      if Ada.Directories.Exists (Output_Path) then
         if Ada.Directories.Kind (Output_Path) = Ada.Directories.Directory then
            Status := Output_File_Error;
            return;
         end if;
      end if;
   exception
      when others =>
         Status := Unsupported_Method;
   end Seven_Zip_External_File;

   function Seven_Zip_Source_Metadata
     (Input_Path : String) return Seven_Zip_Entry_Metadata
   is
      Unix_Epoch          : constant Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (1970, 1, 1, 0.0);
      Filetime_Unix_Epoch : constant Interfaces.Unsigned_64 :=
        116_444_736_000_000_000;
      Ticks_Per_Second    : constant Long_Long_Float := 10_000_000.0;
      Metadata            : Seven_Zip_Entry_Metadata :=
        No_Seven_Zip_Entry_Metadata;
      Is_Directory        : constant Boolean :=
        Ada.Directories.Kind (Input_Path) = Ada.Directories.Directory;
      Seconds             : Duration;
      Ticks               : Interfaces.Unsigned_64 := 0;
   begin
      Metadata.Is_Directory := Is_Directory;
      Seconds := Ada.Directories.Modification_Time (Input_Path) - Unix_Epoch;
      Metadata.Has_Modification_Time := True;

      if Seconds >= 0.0 then
         Ticks :=
           Interfaces.Unsigned_64
             (Long_Long_Integer (Long_Long_Float (Seconds) * Ticks_Per_Second));
         Metadata.Modification_Time := Filetime_Unix_Epoch + Ticks;
      else
         Ticks :=
           Interfaces.Unsigned_64
             (Long_Long_Integer (Long_Long_Float (-Seconds) * Ticks_Per_Second));
         if Ticks <= Filetime_Unix_Epoch then
            Metadata.Modification_Time := Filetime_Unix_Epoch - Ticks;
         else
            Metadata.Has_Modification_Time := False;
         end if;
      end if;

      Metadata.Has_Windows_Attributes := True;
      Metadata.Windows_Attributes :=
        (if Is_Directory then 16#0000_0010# else 16#0000_0020#);
      if not GNAT.OS_Lib.Is_Owner_Writable_File (Input_Path) then
         Metadata.Windows_Attributes := Metadata.Windows_Attributes or 16#0000_0001#;
      end if;

      return Metadata;
   exception
      when others =>
         return No_Seven_Zip_Entry_Metadata;
   end Seven_Zip_Source_Metadata;

   type Seven_Zip_Metadata_Array is
     array (Positive range <>) of Seven_Zip_Entry_Metadata;
   type Seven_Zip_Boolean_Array is array (Positive range <>) of Boolean;

   function Seven_Zip_Entry_Name_Valid (Entry_Name : String) return Boolean;

   procedure Seven_Zip_PPMd_File
     (Input_Path  : String;
      Output_Path : String;
      Status      : out Status_Code)
   is
   begin
      Status := Unsupported_Method;
      if not Seven_Zip_Output_File_Writable (Output_Path) then
         Status := Output_File_Error;
         return;
      end if;
      if not Seven_Zip_Input_Path_Readable (Input_Path) then
         Status := Input_File_Error;
         return;
      end if;

      Seven_Zip_PPMd_File
        (Input_Path, Output_Path, Ada.Directories.Simple_Name (Input_Path),
         Status);
   exception
      when others =>
         Status := Input_File_Error;
   end Seven_Zip_PPMd_File;

   procedure Seven_Zip_PPMd_File
     (Input_Path  : String;
      Output_Path : String;
      Entry_Name  : String;
      Status      : out Status_Code)
   is
      Read_Status  : Status_Code := Ok;
      Write_Status : Status_Code := Ok;
   begin
      Status := Unsupported_Method;
      if not Seven_Zip_Entry_Name_Valid (Entry_Name) then
         return;
      end if;
      if not Seven_Zip_Output_File_Writable (Output_Path) then
         Status := Output_File_Error;
         return;
      end if;
      if not Seven_Zip_Input_Path_Readable (Input_Path) then
         Status := Input_File_Error;
         return;
      end if;

      declare
         Metadata : constant Seven_Zip_Entry_Metadata :=
           Seven_Zip_Source_Metadata (Input_Path);
      begin
         if Metadata.Is_Directory then
            declare
               Empty_Input : constant Byte_Array := [1 .. 0 => 0];
               Archive     : constant Byte_Array :=
                 Seven_Zip_PPMd (Empty_Input, Entry_Name, Metadata, Status);
            begin
               if Status = Ok then
                  Write_File (Output_Path, Archive, Write_Status);
                  Status := Write_Status;
               end if;
            end;

         else
            declare
               Input_Data : constant Byte_Array :=
                 Read_File (Input_Path, Read_Status);
            begin
               if Read_Status /= Ok then
                  Status := Read_Status;
                  return;
               end if;

               declare
                  Archive : constant Byte_Array :=
                    Seven_Zip_PPMd (Input_Data, Entry_Name, Metadata, Status);
               begin
                  if Status = Ok then
                     Write_File (Output_Path, Archive, Write_Status);
                     Status := Write_Status;
                  end if;
               end;
            end;
         end if;
      end;
   exception
      when others =>
         Status := Output_File_Error;
   end Seven_Zip_PPMd_File;

   procedure Extract_Seven_Zip_External_File
     (Input_Path : String;
      Output_Dir : String;
      Password   : String;
      Status     : out Status_Code)
   is
      pragma Unreferenced (Password);
   begin
      Status := Unsupported_Method;

      if not Ada.Directories.Exists (Input_Path) then
         Status := Input_File_Error;
         return;
      end if;

      if Output_Dir'Length = 0 then
         Status := Output_File_Error;
         return;
      end if;
   exception
      when others =>
         Status := Unsupported_Method;
   end Extract_Seven_Zip_External_File;

   procedure Append_U32_LE
     (Output : in out Byte_Vectors.Vector;
      Value  : Interfaces.Unsigned_32)
   is
   begin
      Output.Append (Byte (Value and 16#FF#));
      Output.Append (Byte (Interfaces.Shift_Right (Value, 8) and 16#FF#));
      Output.Append (Byte (Interfaces.Shift_Right (Value, 16) and 16#FF#));
      Output.Append (Byte (Interfaces.Shift_Right (Value, 24) and 16#FF#));
   end Append_U32_LE;

   procedure Append_U16_LE
     (Output : in out Byte_Vectors.Vector;
      Value  : Interfaces.Unsigned_16)
   is
   begin
      Output.Append (Byte (Value and 16#FF#));
      Output.Append (Byte (Interfaces.Shift_Right (Value, 8) and 16#FF#));
   end Append_U16_LE;

   procedure Append_Bytes
     (Output : in out Byte_Vectors.Vector;
      Data   : Byte_Array)
   is
   begin
      for B of Data loop
         Output.Append (B);
      end loop;
   end Append_Bytes;

   procedure Append_ASCII
     (Output : in out Byte_Vectors.Vector;
      Text   : String)
   is
   begin
      for Ch of Text loop
         Output.Append (Byte (Character'Pos (Ch)));
      end loop;
   end Append_ASCII;

   function Safe_ZIP_Entry_Name (Entry_Name : String) return Boolean is
      Segment_Length : Natural := 0;
      Segment_Start  : Natural := Entry_Name'First;

      function Segment_Is_Dot return Boolean is
      begin
         return Segment_Length = 1
           and then Entry_Name (Segment_Start) = '.';
      end Segment_Is_Dot;

      function Segment_Is_Dot_Dot return Boolean is
      begin
         return Segment_Length = 2
           and then Entry_Name (Segment_Start) = '.'
           and then Entry_Name (Segment_Start + 1) = '.';
      end Segment_Is_Dot_Dot;

      function Finish_Segment return Boolean is
      begin
         return Segment_Length > 0
           and then not Segment_Is_Dot
           and then not Segment_Is_Dot_Dot;
      end Finish_Segment;
   begin
      if Entry_Name'Length = 0
        or else Contains_NUL (Entry_Name)
        or else Entry_Name (Entry_Name'First) = '/'
      then
         return False;
      end if;

      for I in Entry_Name'Range loop
         case Entry_Name (I) is
            when '/' =>
               if not Finish_Segment then
                  return False;
               end if;
               Segment_Length := 0;
               Segment_Start := I + 1;
            when '\' | ':' =>
               return False;
            when others =>
               Segment_Length := Segment_Length + 1;
         end case;
      end loop;

      return Finish_Segment;
   end Safe_ZIP_Entry_Name;

   function ZIP
     (Input      : Byte_Array;
      Entry_Name : String;
      Mode       : Compression_Mode := Auto;
      Status     : out Status_Code) return Byte_Array
   is
      Empty : constant Byte_Array (1 .. 0) := [others => 0];
   begin
      Status := Unsupported_Method;

      if not Safe_ZIP_Entry_Name (Entry_Name)
        or else Entry_Name'Length > Natural (Interfaces.Unsigned_16'Last)
      then
         return Empty;
      end if;

      declare
         Payload_Status : Status_Code := Ok;
         Payload        : constant Byte_Array :=
           (if Mode = Stored then Input else Deflate_Raw (Input, Mode, Payload_Status));
      begin
         if Payload_Status /= Ok then
            Status := Payload_Status;
            return Empty;
         end if;

         declare
            Method         : constant Interfaces.Unsigned_16 :=
              (if Mode = Stored then 0 else 8);
            Name_Length    : constant Interfaces.Unsigned_16 :=
              Interfaces.Unsigned_16 (Entry_Name'Length);
            CRC            : constant Interfaces.Unsigned_32 := CRC32 (Input);
            Compressed     : constant Interfaces.Unsigned_32 :=
              Interfaces.Unsigned_32 (Payload'Length);
            Uncompressed   : constant Interfaces.Unsigned_32 :=
              Interfaces.Unsigned_32 (Input'Length);
            Local_Offset   : constant Interfaces.Unsigned_32 := 0;
            Output         : Byte_Vectors.Vector;
            Central_Offset : Interfaces.Unsigned_32;
            Central_Size   : Interfaces.Unsigned_32;
         begin
            Append_U32_LE (Output, 16#0403_4B50#);
            Append_U16_LE (Output, 20);
            Append_U16_LE (Output, 0);
            Append_U16_LE (Output, Method);
            Append_U16_LE (Output, 0);
            Append_U16_LE (Output, 0);
            Append_U32_LE (Output, CRC);
            Append_U32_LE (Output, Compressed);
            Append_U32_LE (Output, Uncompressed);
            Append_U16_LE (Output, Name_Length);
            Append_U16_LE (Output, 0);
            Append_ASCII (Output, Entry_Name);
            Append_Bytes (Output, Payload);

            Central_Offset := Interfaces.Unsigned_32 (Output.Length);

            Append_U32_LE (Output, 16#0201_4B50#);
            Append_U16_LE (Output, 20);
            Append_U16_LE (Output, 20);
            Append_U16_LE (Output, 0);
            Append_U16_LE (Output, Method);
            Append_U16_LE (Output, 0);
            Append_U16_LE (Output, 0);
            Append_U32_LE (Output, CRC);
            Append_U32_LE (Output, Compressed);
            Append_U32_LE (Output, Uncompressed);
            Append_U16_LE (Output, Name_Length);
            Append_U16_LE (Output, 0);
            Append_U16_LE (Output, 0);
            Append_U16_LE (Output, 0);
            Append_U16_LE (Output, 0);
            Append_U32_LE (Output, 0);
            Append_U32_LE (Output, Local_Offset);
            Append_ASCII (Output, Entry_Name);

            Central_Size :=
              Interfaces.Unsigned_32 (Output.Length) - Central_Offset;

            Append_U32_LE (Output, 16#0605_4B50#);
            Append_U16_LE (Output, 0);
            Append_U16_LE (Output, 0);
            Append_U16_LE (Output, 1);
            Append_U16_LE (Output, 1);
            Append_U32_LE (Output, Central_Size);
            Append_U32_LE (Output, Central_Offset);
            Append_U16_LE (Output, 0);

            Status := Ok;
            return To_Byte_Array (Output);
         end;
      end;
   exception
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end ZIP;

   procedure Append_U64_LE
     (Output : in out Byte_Vectors.Vector;
      Value  : Interfaces.Unsigned_64)
   is
      Current : Interfaces.Unsigned_64 := Value;
   begin
      for I in 1 .. 8 loop
         pragma Unreferenced (I);
         Output.Append (Byte (Current and 16#FF#));
         Current := Interfaces.Shift_Right (Current, 8);
      end loop;
   end Append_U64_LE;

   function ZIP_U32_Field
     (Value     : Interfaces.Unsigned_64;
      Use_ZIP64 : Boolean) return Interfaces.Unsigned_32
   is
   begin
      if Use_ZIP64 then
         return 16#FFFF_FFFF#;
      else
         return Interfaces.Unsigned_32 (Value);
      end if;
   end ZIP_U32_Field;

   function ZIP_U16_Count
     (Value     : Natural;
      Use_ZIP64 : Boolean) return Interfaces.Unsigned_16
   is
   begin
      if Use_ZIP64 then
         return 16#FFFF#;
      else
         return Interfaces.Unsigned_16 (Value);
      end if;
   end ZIP_U16_Count;

   type ZIP_Entry_Info is record
      Method       : Interfaces.Unsigned_16 := 0;
      CRC          : Interfaces.Unsigned_32 := 0;
      Compressed   : Interfaces.Unsigned_64 := 0;
      Uncompressed : Interfaces.Unsigned_64 := 0;
      Local_Offset : Interfaces.Unsigned_64 := 0;
   end record;

   type ZIP_Entry_Info_Array is array (Positive range <>) of ZIP_Entry_Info;

   procedure Append_ZIP64_Local_Extra
     (Output       : in out Byte_Vectors.Vector;
      Uncompressed : Interfaces.Unsigned_64;
      Compressed   : Interfaces.Unsigned_64)
   is
   begin
      Append_U16_LE (Output, 16#0001#);
      Append_U16_LE (Output, 16);
      Append_U64_LE (Output, Uncompressed);
      Append_U64_LE (Output, Compressed);
   end Append_ZIP64_Local_Extra;

   procedure Append_ZIP64_Central_Extra
     (Output       : in out Byte_Vectors.Vector;
      Uncompressed : Interfaces.Unsigned_64;
      Compressed   : Interfaces.Unsigned_64;
      Local_Offset : Interfaces.Unsigned_64)
   is
   begin
      Append_U16_LE (Output, 16#0001#);
      Append_U16_LE (Output, 24);
      Append_U64_LE (Output, Uncompressed);
      Append_U64_LE (Output, Compressed);
      Append_U64_LE (Output, Local_Offset);
   end Append_ZIP64_Central_Extra;

   procedure ZIP_Files
     (Input_Paths : Text_Array;
      Output_Path : String;
      Entry_Names : Text_Array;
      Mode        : Compression_Mode := Auto;
      Force_ZIP64 : Boolean := False;
      Status      : out Status_Code)
   is
      Count        : constant Natural := Input_Paths'Length;
      Output       : Byte_Vectors.Vector;
      Read_Status  : Status_Code := Ok;
      Write_Status : Status_Code := Ok;
      Use_ZIP64    : constant Boolean := Force_ZIP64;
   begin
      Status := Unsupported_Method;

      if Count = 0
        or else Entry_Names'Length /= Count
        or else (not Use_ZIP64 and then Count > Natural (Interfaces.Unsigned_16'Last))
      then
         return;
      end if;

      for Offset in 0 .. Count - 1 loop
         declare
            Entry_Name : constant String :=
              US.To_String (Entry_Names (Entry_Names'First + Offset));
         begin
            if not Safe_ZIP_Entry_Name (Entry_Name)
              or else Entry_Name'Length > Natural (Interfaces.Unsigned_16'Last)
            then
               return;
            end if;

            if Offset > 0 then
               for Previous_Offset in 0 .. Offset - 1 loop
                  if Entry_Name =
                    US.To_String (Entry_Names (Entry_Names'First + Previous_Offset))
                  then
                     return;
                  end if;
               end loop;
            end if;
         end;
      end loop;

      declare
         Infos : ZIP_Entry_Info_Array (1 .. Count) := [others => <>];
      begin
         for Offset in 0 .. Count - 1 loop
            declare
               Input_Path : constant String :=
                 US.To_String (Input_Paths (Input_Paths'First + Offset));
               Entry_Name : constant String :=
                 US.To_String (Entry_Names (Entry_Names'First + Offset));
               Input_Data : constant Byte_Array :=
                 Read_File (Input_Path, Read_Status);
            begin
               if Read_Status /= Ok then
                  Status := Read_Status;
                  return;
               end if;

               declare
                  Payload_Status : Status_Code := Ok;
                  Payload        : constant Byte_Array :=
                    (if Mode = Stored
                     then Input_Data
                     else Deflate_Raw (Input_Data, Mode, Payload_Status));
                  Index          : constant Positive := Offset + 1;
                  Name_Length    : constant Interfaces.Unsigned_16 :=
                    Interfaces.Unsigned_16 (Entry_Name'Length);
                  Extra_Length   : constant Interfaces.Unsigned_16 :=
                    (if Use_ZIP64 then 20 else 0);
               begin
                  if Payload_Status /= Ok then
                     Status := Payload_Status;
                     return;
                  end if;

                  Infos (Index) :=
                    (Method       => (if Mode = Stored then 0 else 8),
                     CRC          => CRC32 (Input_Data),
                     Compressed   => Interfaces.Unsigned_64 (Payload'Length),
                     Uncompressed => Interfaces.Unsigned_64 (Input_Data'Length),
                     Local_Offset => Interfaces.Unsigned_64 (Output.Length));

                  Append_U32_LE (Output, 16#0403_4B50#);
                  Append_U16_LE (Output, (if Use_ZIP64 then 45 else 20));
                  Append_U16_LE (Output, 0);
                  Append_U16_LE (Output, Infos (Index).Method);
                  Append_U16_LE (Output, 0);
                  Append_U16_LE (Output, 0);
                  Append_U32_LE (Output, Infos (Index).CRC);
                  Append_U32_LE
                    (Output, ZIP_U32_Field (Infos (Index).Compressed, Use_ZIP64));
                  Append_U32_LE
                    (Output, ZIP_U32_Field (Infos (Index).Uncompressed, Use_ZIP64));
                  Append_U16_LE (Output, Name_Length);
                  Append_U16_LE (Output, Extra_Length);
                  Append_ASCII (Output, Entry_Name);
                  if Use_ZIP64 then
                     Append_ZIP64_Local_Extra
                       (Output,
                        Infos (Index).Uncompressed,
                        Infos (Index).Compressed);
                  end if;
                  Append_Bytes (Output, Payload);
               end;
            end;
         end loop;

         declare
            Central_Offset : constant Interfaces.Unsigned_64 :=
              Interfaces.Unsigned_64 (Output.Length);
         begin
            for Offset in 0 .. Count - 1 loop
               declare
                  Index        : constant Positive := Offset + 1;
                  Entry_Name   : constant String :=
                    US.To_String (Entry_Names (Entry_Names'First + Offset));
                  Name_Length  : constant Interfaces.Unsigned_16 :=
                    Interfaces.Unsigned_16 (Entry_Name'Length);
                  Extra_Length : constant Interfaces.Unsigned_16 :=
                    (if Use_ZIP64 then 28 else 0);
               begin
                  Append_U32_LE (Output, 16#0201_4B50#);
                  Append_U16_LE (Output, (if Use_ZIP64 then 45 else 20));
                  Append_U16_LE (Output, (if Use_ZIP64 then 45 else 20));
                  Append_U16_LE (Output, 0);
                  Append_U16_LE (Output, Infos (Index).Method);
                  Append_U16_LE (Output, 0);
                  Append_U16_LE (Output, 0);
                  Append_U32_LE (Output, Infos (Index).CRC);
                  Append_U32_LE
                    (Output, ZIP_U32_Field (Infos (Index).Compressed, Use_ZIP64));
                  Append_U32_LE
                    (Output, ZIP_U32_Field (Infos (Index).Uncompressed, Use_ZIP64));
                  Append_U16_LE (Output, Name_Length);
                  Append_U16_LE (Output, Extra_Length);
                  Append_U16_LE (Output, 0);
                  Append_U16_LE (Output, 0);
                  Append_U16_LE (Output, 0);
                  Append_U32_LE (Output, 0);
                  Append_U32_LE
                    (Output, ZIP_U32_Field (Infos (Index).Local_Offset, Use_ZIP64));
                  Append_ASCII (Output, Entry_Name);
                  if Use_ZIP64 then
                     Append_ZIP64_Central_Extra
                       (Output,
                        Infos (Index).Uncompressed,
                        Infos (Index).Compressed,
                        Infos (Index).Local_Offset);
                  end if;
               end;
            end loop;

            declare
               Central_Size : constant Interfaces.Unsigned_64 :=
                 Interfaces.Unsigned_64 (Output.Length) - Central_Offset;
               ZIP64_EOCD_Offset : constant Interfaces.Unsigned_64 :=
                 Interfaces.Unsigned_64 (Output.Length);
            begin
               if Use_ZIP64 then
                  Append_U32_LE (Output, 16#0606_4B50#);
                  Append_U64_LE (Output, 44);
                  Append_U16_LE (Output, 45);
                  Append_U16_LE (Output, 45);
                  Append_U32_LE (Output, 0);
                  Append_U32_LE (Output, 0);
                  Append_U64_LE (Output, Interfaces.Unsigned_64 (Count));
                  Append_U64_LE (Output, Interfaces.Unsigned_64 (Count));
                  Append_U64_LE (Output, Central_Size);
                  Append_U64_LE (Output, Central_Offset);

                  Append_U32_LE (Output, 16#0706_4B50#);
                  Append_U32_LE (Output, 0);
                  Append_U64_LE (Output, ZIP64_EOCD_Offset);
                  Append_U32_LE (Output, 1);
               end if;

               Append_U32_LE (Output, 16#0605_4B50#);
               Append_U16_LE (Output, 0);
               Append_U16_LE (Output, 0);
               Append_U16_LE (Output, ZIP_U16_Count (Count, Use_ZIP64));
               Append_U16_LE (Output, ZIP_U16_Count (Count, Use_ZIP64));
               Append_U32_LE (Output, ZIP_U32_Field (Central_Size, Use_ZIP64));
               Append_U32_LE (Output, ZIP_U32_Field (Central_Offset, Use_ZIP64));
               Append_U16_LE (Output, 0);

               Write_File (Output_Path, To_Byte_Array (Output), Write_Status);
               Status := Write_Status;
            end;
         end;
      end;
   exception
      when Constraint_Error =>
         Status := Unsupported_Method;
      when others =>
         Status := Unsupported_Method;
   end ZIP_Files;

   procedure Append_Seven_Zip_Number
     (Output : in out Byte_Vectors.Vector;
      Value  : Interfaces.Unsigned_64)
   is
      Extra_Bytes : Natural := 0;
      Limit       : Interfaces.Unsigned_64 := 2 ** 7;
   begin
      while Extra_Bytes < 8 and then Value >= Limit loop
         Extra_Bytes := Extra_Bytes + 1;
         if Extra_Bytes < 8 then
            Limit := Interfaces.Shift_Left (Limit, 7);
         end if;
      end loop;

      if Extra_Bytes = 0 then
         Output.Append (Byte (Value));
      elsif Extra_Bytes = 8 then
         Output.Append (16#FF#);
         Append_U64_LE (Output, Value);
      else
         declare
            Prefix : Natural := 0;
            High   : constant Natural :=
              Natural
                (Interfaces.Shift_Right
                   (Value, 8 * Extra_Bytes)
                 and Interfaces.Unsigned_64 (16#FF# / (2 ** Extra_Bytes)));
         begin
            for I in 0 .. Extra_Bytes - 1 loop
               Prefix := Prefix + 2 ** (7 - I);
            end loop;

            Output.Append (Byte (Prefix + High));
            for I in 0 .. Extra_Bytes - 1 loop
               Output.Append
                 (Byte
                    (Interfaces.Shift_Right (Value, 8 * I)
                     and Interfaces.Unsigned_64 (16#FF#)));
            end loop;
         end;
      end if;
   end Append_Seven_Zip_Number;

   function Seven_Zip_Header_CRC (Data : Byte_Array) return Interfaces.Unsigned_32
     renames CRC32;

   function Seven_Zip_U32_At
     (Data : Byte_Array;
      Pos  : Natural) return Interfaces.Unsigned_32
   is
   begin
      return Interfaces.Unsigned_32 (Data (Pos))
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (Pos + 1)), 8)
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (Pos + 2)), 16)
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (Pos + 3)), 24);
   end Seven_Zip_U32_At;

   function Seven_Zip_U64_At
     (Data : Byte_Array;
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
   end Seven_Zip_U64_At;

   function Read_Seven_Zip_Number
     (Data  : Byte_Array;
      Pos   : in out Natural;
      Last  : Natural;
      Value : out Interfaces.Unsigned_64) return Boolean
   is
      First : Natural;
      Extra : Natural := 0;
      Mask  : Natural := 16#80#;
   begin
      Value := 0;
      if Pos > Last then
         return False;
      end if;

      First := Natural (Data (Pos));
      Pos := Pos + 1;

      while Extra < 8 and then (First / Mask) mod 2 = 1 loop
         Extra := Extra + 1;
         Mask := Mask / 2;
      end loop;

      if Extra = 0 then
         Value := Interfaces.Unsigned_64 (First);
         return True;
      end if;

      if Pos > Last or else Last - Pos + 1 < Extra then
         return False;
      end if;

      if Extra = 8 then
         for I in 0 .. 7 loop
            Value :=
              Value
              or Interfaces.Shift_Left
                (Interfaces.Unsigned_64 (Data (Pos + I)), 8 * I);
         end loop;
         Pos := Pos + 8;
      else
         Value :=
           Interfaces.Shift_Left
             (Interfaces.Unsigned_64 (First mod Mask), 8 * Extra);
         for I in 0 .. Extra - 1 loop
            Value :=
              Value
              or Interfaces.Shift_Left
                (Interfaces.Unsigned_64 (Data (Pos + I)), 8 * I);
         end loop;
         Pos := Pos + Extra;
      end if;

      return True;
   exception
      when others =>
         Value := 0;
         return False;
   end Read_Seven_Zip_Number;

   function Seven_Zip_Read_Byte
     (Data : Byte_Array;
      Pos  : in out Natural;
      Last : Natural;
      B    : out Byte) return Boolean
   is
   begin
      if Pos > Last then
         B := 0;
         return False;
      end if;

      B := Data (Pos);
      Pos := Pos + 1;
      return True;
   end Seven_Zip_Read_Byte;

   function Seven_Zip_Expect_Byte
     (Data     : Byte_Array;
      Pos      : in out Natural;
      Last     : Natural;
      Expected : Byte) return Boolean
   is
      Actual : Byte := 0;
   begin
      return Seven_Zip_Read_Byte (Data, Pos, Last, Actual)
        and then Actual = Expected;
   end Seven_Zip_Expect_Byte;

   function Seven_Zip_Has_Bytes
     (Pos   : Natural;
      Last  : Natural;
      Count : Natural) return Boolean is
   begin
      return Count = 0
        or else (Pos <= Last and then Count <= Last - Pos + 1);
   end Seven_Zip_Has_Bytes;

   function Seven_Zip_Find_Signature
     (Data : Byte_Array;
      Pos  : out Natural) return Boolean
   is
   begin
      Pos := 0;

      if Data'Length < 33 then
         return False;
      end if;

      for I in Data'First .. Data'Last - 31 loop
         if Data (I) = 16#37#
           and then Data (I + 1) = 16#7A#
           and then Data (I + 2) = 16#BC#
           and then Data (I + 3) = 16#AF#
           and then Data (I + 4) = 16#27#
           and then Data (I + 5) = 16#1C#
           and then Data (I + 6) = 0
           and then Data (I + 7) = 4
           and then (I = Data'First
                     or else Seven_Zip_U32_At (Data, I + 8) =
                       CRC32 (Data (I + 12 .. I + 31)))
         then
            Pos := I;
            return True;
         end if;
      end loop;

      return False;
   end Seven_Zip_Find_Signature;

   function Seven_Zip_Skip_Properties
     (Data : Byte_Array;
      Pos  : in out Natural;
      Last : Natural) return Boolean
   is
      Property : Byte := 0;
      Size     : Interfaces.Unsigned_64 := 0;
   begin
      loop
         if not Seven_Zip_Read_Byte (Data, Pos, Last, Property) then
            return False;
         end if;

         exit when Property = 0;

         if not Read_Seven_Zip_Number (Data, Pos, Last, Size)
           or else Size > Interfaces.Unsigned_64 (Natural'Last)
           or else Size > Interfaces.Unsigned_64 (Last - Pos + 1)
         then
            return False;
         end if;

         Pos := Pos + Natural (Size);
      end loop;

      return True;
   end Seven_Zip_Skip_Properties;

   type Seven_Zip_U32_Array is array (Positive range <>) of Interfaces.Unsigned_32;
   type Seven_Zip_U64_Array is array (Positive range <>) of Interfaces.Unsigned_64;
   type Seven_Zip_Coder_Method is
     (Seven_Zip_Copy, Seven_Zip_Deflate_Method, Seven_Zip_BZip2_Method,
      Seven_Zip_LZMA_Method, Seven_Zip_LZMA2_Method,
      Seven_Zip_Delta_Method, Seven_Zip_BCJ_X86_Method,
      Seven_Zip_BCJ_ARM_Method, Seven_Zip_BCJ_ARMT_Method,
      Seven_Zip_BCJ_ARM64_Method,
      Seven_Zip_BCJ_PPC_Method, Seven_Zip_BCJ_SPARC_Method,
      Seven_Zip_BCJ_IA64_Method,
      Seven_Zip_BCJ2_Method, Seven_Zip_PPMd_Method,
      Seven_Zip_AES_Method);

   --  Map a branch-filter coder method to its filter architecture.
   function Branch_Arch_Of
     (Method : Seven_Zip_Coder_Method)
      return Zlib.Seven_Zip_Filters.Branch_Arch
   is (case Method is
          when Seven_Zip_BCJ_ARM_Method   => Zlib.Seven_Zip_Filters.ARM,
          when Seven_Zip_BCJ_ARMT_Method  => Zlib.Seven_Zip_Filters.ARMT,
          when Seven_Zip_BCJ_ARM64_Method => Zlib.Seven_Zip_Filters.ARM64,
          when Seven_Zip_BCJ_PPC_Method   => Zlib.Seven_Zip_Filters.PPC,
          when Seven_Zip_BCJ_SPARC_Method => Zlib.Seven_Zip_Filters.SPARC,
          when others                     => Zlib.Seven_Zip_Filters.IA64);
   --  @param Method a branch-filter coder method
   --  @return the corresponding Seven_Zip_Filters architecture
   type Seven_Zip_Coder_Method_Array is
     array (Positive range <>) of Seven_Zip_Coder_Method;
   type Seven_Zip_LZMA_Props is array (Positive range 1 .. 5) of Byte;
   type Seven_Zip_LZMA_Props_Array is
     array (Positive range <>) of Seven_Zip_LZMA_Props;
   type Seven_Zip_Entry_Kind is
     (Seven_Zip_File_Entry, Seven_Zip_Directory_Entry);
   function Seven_Zip_Valid_PPMd_Props
     (Order  : Natural;
      Memory : Interfaces.Unsigned_32) return Boolean is
   begin
      return Order in 2 .. 64
        and then Memory >= 2 ** 11
        and then Memory <= Interfaces.Unsigned_32'Last - 36;
   end Seven_Zip_Valid_PPMd_Props;

   PPMd_Default_Order  : constant Natural := 6;
   PPMd_Default_Memory : constant Interfaces.Unsigned_32 := 16#0100_0000#;

   function Seven_Zip_Bit_Is_Set
     (Data  : Byte_Array;
      First : Natural;
      Index : Natural) return Boolean
   is
      Byte_Pos : constant Natural := First + (Index - 1) / 8;
      Mask     : constant Byte :=
        Byte
          (Interfaces.Shift_Right
             (Interfaces.Unsigned_8'(16#80#), (Index - 1) mod 8));
   begin
      return (Data (Byte_Pos) and Mask) /= 0;
   exception
      when others =>
         return False;
   end Seven_Zip_Bit_Is_Set;

   function Seven_Zip_U64_LE
     (Data : Byte_Array;
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
   exception
      when others =>
         return 0;
   end Seven_Zip_U64_LE;

   function Seven_Zip_U32_LE
     (Data : Byte_Array;
      Pos  : Natural) return Interfaces.Unsigned_32
   is
      Result : Interfaces.Unsigned_32 := 0;
   begin
      for I in 0 .. 3 loop
         Result :=
           Result
           or Interfaces.Shift_Left
             (Interfaces.Unsigned_32 (Data (Pos + I)), 8 * I);
      end loop;
      return Result;
   exception
      when others =>
         return 0;
   end Seven_Zip_U32_LE;

   function Seven_Zip_Read_File_Time_Property
     (Data       : Byte_Array;
      First      : Natural;
      Count      : Natural;
      File_Count : Natural;
      Target     : Natural;
      Has_Time   : out Boolean;
      Time       : out Interfaces.Unsigned_64) return Boolean
   is
      Last        : constant Natural := First + Count - 1;
      Pos         : Natural := First;
      All_Defined : Boolean;
      Defined_Pos : Natural := 0;
   begin
      Has_Time := False;
      Time := 0;

      if Count = 0
        or else File_Count = 0
        or else Target not in 1 .. File_Count
      then
         return False;
      end if;

      All_Defined := Data (Pos) /= 0;
      Pos := Pos + 1;

      if not All_Defined then
         if Count < 1 + (File_Count + 7) / 8 then
            return False;
         end if;
         Defined_Pos := Pos;
         Pos := Pos + (File_Count + 7) / 8;
      end if;

      if Pos > Last or else Data (Pos) /= 0 then
         return False;
      end if;
      Pos := Pos + 1;

      for I in 1 .. File_Count loop
         declare
            Defined : constant Boolean :=
              All_Defined or else Seven_Zip_Bit_Is_Set (Data, Defined_Pos, I);
         begin
            if Defined then
               if Pos > Last or else Last - Pos + 1 < 8 then
                  return False;
               end if;

               if I = Target then
                  Has_Time := True;
                  Time := Seven_Zip_U64_LE (Data, Pos);
               end if;

               Pos := Pos + 8;
            elsif I = Target then
               Has_Time := False;
               Time := 0;
            end if;
         end;
      end loop;

      return Pos = Last + 1;
   exception
      when others =>
         Has_Time := False;
         Time := 0;
         return False;
   end Seven_Zip_Read_File_Time_Property;

   function Seven_Zip_Read_U32_Property
     (Data       : Byte_Array;
      First      : Natural;
      Count      : Natural;
      File_Count : Natural;
      Target     : Natural;
      Has_Value  : out Boolean;
      Value      : out Interfaces.Unsigned_32) return Boolean
   is
      Last        : constant Natural := First + Count - 1;
      Pos         : Natural := First;
      All_Defined : Boolean;
      Defined_Pos : Natural := 0;
      Defined_Count : Natural := 0;
   begin
      Has_Value := False;
      Value := 0;

      if Count = 0
        or else File_Count = 0
        or else Target not in 1 .. File_Count
      then
         return False;
      end if;

      All_Defined := Data (Pos) /= 0;
      Pos := Pos + 1;

      if not All_Defined then
         if Count < 1 + (File_Count + 7) / 8 then
            return False;
         end if;
         Defined_Pos := Pos;
         Pos := Pos + (File_Count + 7) / 8;
      end if;

      for I in 1 .. File_Count loop
         if All_Defined or else Seven_Zip_Bit_Is_Set (Data, Defined_Pos, I) then
            Defined_Count := Defined_Count + 1;
         end if;
      end loop;

      if Pos <= Last
        and then Data (Pos) = 0
        and then Last - Pos = 4 * Defined_Count
      then
         Pos := Pos + 1;
      end if;

      for I in 1 .. File_Count loop
         declare
            Defined : constant Boolean :=
              All_Defined or else Seven_Zip_Bit_Is_Set (Data, Defined_Pos, I);
         begin
            if Defined then
               if Pos > Last or else Last - Pos + 1 < 4 then
                  return False;
               end if;

               if I = Target then
                  Has_Value := True;
                  Value := Seven_Zip_U32_LE (Data, Pos);
               end if;

               Pos := Pos + 4;
            elsif I = Target then
               Has_Value := False;
               Value := 0;
            end if;
         end;
      end loop;

      return Pos = Last + 1;
   exception
      when others =>
         Has_Value := False;
         Value := 0;
         return False;
   end Seven_Zip_Read_U32_Property;

   function Seven_Zip_Leap_Year (Year : Natural) return Boolean is
   begin
      return (Year mod 4 = 0 and then Year mod 100 /= 0)
        or else Year mod 400 = 0;
   end Seven_Zip_Leap_Year;

   function Seven_Zip_Filetime_To_OS_Time
     (File_Time : Interfaces.Unsigned_64;
      OS_Time   : out GNAT.OS_Lib.OS_Time) return Boolean
   is
      Ticks_Per_Second : constant Interfaces.Unsigned_64 := 10_000_000;
      Unix_Epoch_Delta : constant Interfaces.Unsigned_64 := 11_644_473_600;
      Seconds          : Interfaces.Unsigned_64;
      Days             : Natural;
      Seconds_Of_Day   : Natural;
      Year             : Natural := 1970;
      Month            : Natural := 1;
      Day              : Natural;
      Month_Lengths    : constant array (1 .. 12) of Natural :=
        [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
   begin
      OS_Time := GNAT.OS_Lib.Invalid_Time;
      Seconds := File_Time / Ticks_Per_Second;
      if Seconds < Unix_Epoch_Delta then
         return False;
      end if;

      Seconds := Seconds - Unix_Epoch_Delta;
      if Seconds > Interfaces.Unsigned_64 (Natural'Last) then
         return False;
      end if;

      Days := Natural (Seconds / 86_400);
      Seconds_Of_Day := Natural (Seconds mod 86_400);

      loop
         declare
            Year_Days : constant Natural :=
              (if Seven_Zip_Leap_Year (Year) then 366 else 365);
         begin
            exit when Days < Year_Days;
            Days := Days - Year_Days;
            Year := Year + 1;
            if Year > GNAT.OS_Lib.Year_Type'Last then
               return False;
            end if;
         end;
      end loop;

      loop
         declare
            Month_Days : constant Natural :=
              (if Month = 2 and then Seven_Zip_Leap_Year (Year)
               then 29
               else Month_Lengths (Month));
         begin
            exit when Days < Month_Days;
            Days := Days - Month_Days;
            Month := Month + 1;
         end;
      end loop;

      Day := Days + 1;
      OS_Time :=
        GNAT.OS_Lib.GM_Time_Of
          (GNAT.OS_Lib.Year_Type (Year),
           GNAT.OS_Lib.Month_Type (Month),
           GNAT.OS_Lib.Day_Type (Day),
           GNAT.OS_Lib.Hour_Type (Seconds_Of_Day / 3_600),
           GNAT.OS_Lib.Minute_Type ((Seconds_Of_Day / 60) mod 60),
           GNAT.OS_Lib.Second_Type (Seconds_Of_Day mod 60));
      return OS_Time /= GNAT.OS_Lib.Invalid_Time;
   exception
      when others =>
         OS_Time := GNAT.OS_Lib.Invalid_Time;
         return False;
   end Seven_Zip_Filetime_To_OS_Time;

   procedure Seven_Zip_Apply_Metadata
     (Path     : String;
      Metadata : Seven_Zip_Entry_Metadata)
   is
      OS_Time : GNAT.OS_Lib.OS_Time := GNAT.OS_Lib.Invalid_Time;
   begin
      if Metadata.Has_Modification_Time
        and then Seven_Zip_Filetime_To_OS_Time
          (Metadata.Modification_Time, OS_Time)
      then
         GNAT.OS_Lib.Set_File_Last_Modify_Time_Stamp (Path, OS_Time);
      end if;

      if Metadata.Has_Windows_Attributes
        and then (Metadata.Windows_Attributes and 16#0000_0001#) /= 0
      then
         GNAT.OS_Lib.Set_Read_Only (Path);
      end if;
   end Seven_Zip_Apply_Metadata;

   function Seven_Zip_Name_Index
     (Data       : Byte_Array;
      First      : Natural;
      Count      : Natural;
      File_Count : Natural;
      Entry_Name : String;
      Index      : out Natural) return Boolean
   is
      Last : constant Natural := First + Count - 1;
      Pos  : Natural := First;
      Found : Boolean := False;
   begin
      Index := 0;

      if Count = 0 or else File_Count = 0 or else Data (Pos) /= 0 then
         return False;
      end if;
      Pos := Pos + 1;

      for File_Index in 1 .. File_Count loop
         declare
            Match    : Boolean := True;
            Name_Pos : Natural := Entry_Name'First;
         begin
            loop
               if Pos + 1 > Last then
                  return False;
               end if;

               exit when Data (Pos) = 0 and then Data (Pos + 1) = 0;

               if Name_Pos > Entry_Name'Last
                 or else Data (Pos) /=
                   Byte (Character'Pos (Entry_Name (Name_Pos)) mod 256)
                 or else Data (Pos + 1) /=
                   Byte (Character'Pos (Entry_Name (Name_Pos)) / 256)
               then
                  Match := False;
               end if;

               if Name_Pos <= Entry_Name'Last then
                  Name_Pos := Name_Pos + 1;
               end if;

               Pos := Pos + 2;
            end loop;

            if Match and then Name_Pos = Entry_Name'Last + 1 then
               if Found then
                  Index := 0;
                  return False;
               end if;
               Found := True;
               Index := File_Index;
            end if;

            Pos := Pos + 2;
         end;
      end loop;

      return Pos = Last + 1 and then Found;
   exception
      when others =>
         Index := 0;
         return False;
   end Seven_Zip_Name_Index;

   procedure Append_UTF16LE_NT
     (Output : in out Byte_Vectors.Vector;
      Text   : String)
   is
   begin
      for Ch of Text loop
         Output.Append (Byte (Character'Pos (Ch) mod 256));
         Output.Append (Byte (Character'Pos (Ch) / 256));
      end loop;

      Output.Append (0);
      Output.Append (0);
   end Append_UTF16LE_NT;

   procedure Append_Seven_Zip_Coder
     (Header : in out Byte_Vectors.Vector;
      Method : Seven_Zip_Coder_Method) is
   begin
      case Method is
         when Seven_Zip_Copy =>
            Header.Append (1);
            Header.Append (0);

         when Seven_Zip_Deflate_Method =>
            Header.Append (3);
            Header.Append (16#04#);
            Header.Append (16#01#);
            Header.Append (16#08#);

         when Seven_Zip_BZip2_Method =>
            Header.Append (3);
            Header.Append (16#04#);
            Header.Append (16#02#);
            Header.Append (16#02#);

         when Seven_Zip_LZMA_Method =>
            Header.Append (16#23#);
            Header.Append (16#03#);
            Header.Append (16#01#);
            Header.Append (16#01#);
            Header.Append (5);
            Header.Append (LZMA_Default_Props);
            Header.Append (Byte (LZMA_Default_Dict mod 256));
            Header.Append (Byte ((LZMA_Default_Dict / 256) mod 256));
            Header.Append (Byte ((LZMA_Default_Dict / 65_536) mod 256));
            Header.Append (Byte ((LZMA_Default_Dict / 16#0100_0000#) mod 256));

         when Seven_Zip_LZMA2_Method =>
            Header.Append (16#21#);
            Header.Append (16#21#);
            Header.Append (1);
            Header.Append (16#16#);

         when Seven_Zip_Delta_Method =>
            Header.Append (16#21#);
            Header.Append (16#03#);
            Header.Append (1);
            Header.Append (0);

         when Seven_Zip_BCJ_X86_Method =>
            Header.Append (4);
            Header.Append (16#03#);
            Header.Append (16#03#);
            Header.Append (16#01#);
            Header.Append (16#03#);

         when Seven_Zip_BCJ_ARM_Method | Seven_Zip_BCJ_ARMT_Method
            | Seven_Zip_BCJ_PPC_Method | Seven_Zip_BCJ_SPARC_Method
            | Seven_Zip_BCJ_IA64_Method =>
            --  Classic 4-byte BCJ branch-filter id, no streams, no props.
            Header.Append (4);
            Header.Append (16#03#);
            Header.Append (16#03#);
            case Method is
               when Seven_Zip_BCJ_ARM_Method =>
                  Header.Append (16#05#);
                  Header.Append (16#01#);
               when Seven_Zip_BCJ_ARMT_Method =>
                  Header.Append (16#07#);
                  Header.Append (16#01#);
               when Seven_Zip_BCJ_PPC_Method =>
                  Header.Append (16#02#);
                  Header.Append (16#05#);
               when Seven_Zip_BCJ_SPARC_Method =>
                  Header.Append (16#08#);
                  Header.Append (16#05#);
               when others =>  --  IA64 (03030401)
                  Header.Append (16#04#);
                  Header.Append (16#01#);
            end case;

         when Seven_Zip_BCJ_ARM64_Method =>
            --  ARM64 has only the compact 1-byte id 0A, no streams/props.
            Header.Append (1);
            Header.Append (16#0A#);

         when Seven_Zip_BCJ2_Method =>
            Header.Append (16#14#);
            Header.Append (16#03#);
            Header.Append (16#03#);
            Header.Append (16#01#);
            Header.Append (16#1B#);
            Header.Append (4);
            Header.Append (1);

         when Seven_Zip_PPMd_Method =>
            Header.Append (16#23#);
            Header.Append (16#03#);
            Header.Append (16#04#);
            Header.Append (16#01#);
            Header.Append (5);
            Header.Append (Byte (PPMd_Default_Order));
            Append_U32_LE (Header, PPMd_Default_Memory);

         when Seven_Zip_AES_Method =>
            --  AES coder bytes are emitted by the encryption writer, which
            --  carries the per-archive salt/iv/cycles props.
            null;
      end case;
   end Append_Seven_Zip_Coder;

   function Seven_Zip_Delta_Decode
     (Input    : Byte_Array;
      Distance : Natural;
      Status   : out Status_Code) return Byte_Array
   is
      Empty : constant Byte_Array (1 .. 0) := [others => 0];
   begin
      if Distance = 0 or else Distance > 256 then
         Status := Unsupported_Method;
         return Empty;
      end if;

      declare
         Output : Byte_Array (1 .. Input'Length) := [others => 0];
      begin
         for Offset in 0 .. Input'Length - 1 loop
            declare
               Previous : constant Byte :=
                 (if Offset >= Distance
                  then Output (Output'First + Offset - Distance)
                  else 0);
            begin
               Output (Output'First + Offset) :=
                 Byte ((Natural (Input (Input'First + Offset))
                       + Natural (Previous)) mod 256);
            end;
         end loop;

         Status := Ok;
         return Output;
      end;
   end Seven_Zip_Delta_Decode;

   --  PPMd decode now delegates to the real Zlib.PPMd7 codec. These thin
   --  shims preserve the historic signatures used across the extractor.
   Seven_Zip_PPMd_Decode_Mode_Count : constant Positive := 8;

   function PPMd_Decode_Shim
     (Input       : Byte_Array;
      Output_Size : Natural;
      Order       : Natural;
      Memory      : Interfaces.Unsigned_32;
      Status      : out Status_Code) return Byte_Array is
   begin
      if Order < 2 or else Order > 64 then
         Status := Invalid_Block_Type;
         return [1 .. 0 => 0];
      end if;
      return Zlib.PPMd7.Decompress (Input, Output_Size, Order, Memory, Status);
   end PPMd_Decode_Shim;

   function Seven_Zip_PPMd_Decode
     (Input       : Byte_Array;
      Output_Size : Natural;
      Order       : Natural;
      Memory      : Interfaces.Unsigned_32;
      Remaining_Symbols_From_Root : Boolean;
      General_Root : Boolean;
      Full_Update_Model : Boolean;
      Status      : out Status_Code;
      Use_State_Blocks : Boolean := False) return Byte_Array
   is
      pragma Unreferenced
        (Remaining_Symbols_From_Root, General_Root, Full_Update_Model,
         Use_State_Blocks);
   begin
      return PPMd_Decode_Shim (Input, Output_Size, Order, Memory, Status);
   end Seven_Zip_PPMd_Decode;

   function Seven_Zip_PPMd_Decode_Mode
     (Input       : Byte_Array;
      Output_Size : Natural;
      Order       : Natural;
      Memory      : Interfaces.Unsigned_32;
      Mode        : Positive;
      Status      : out Status_Code) return Byte_Array
   is
      pragma Unreferenced (Mode);
   begin
      return PPMd_Decode_Shim (Input, Output_Size, Order, Memory, Status);
   end Seven_Zip_PPMd_Decode_Mode;

   function Seven_Zip_PPMd_Decode_Verified
     (Input        : Byte_Array;
      Output_Size  : Natural;
      Order        : Natural;
      Memory       : Interfaces.Unsigned_32;
      Verify_CRC   : Boolean;
      Expected_CRC : Interfaces.Unsigned_32;
      Status       : out Status_Code) return Byte_Array
   is
      Result : constant Byte_Array :=
        PPMd_Decode_Shim (Input, Output_Size, Order, Memory, Status);
   begin
      if Status = Ok and then Verify_CRC
        and then CRC32 (Result) /= Expected_CRC
      then
         Status := Invalid_Checksum;
         return [1 .. 0 => 0];
      end if;
      return Result;
   end Seven_Zip_PPMd_Decode_Verified;

   function Seven_Zip_BCJ_X86_Decode
     (Input  : Byte_Array;
      Status : out Status_Code) return Byte_Array is
   begin
      --  Use the full masked x86 BCJ converter (interop-correct with stock
      --  7z); the previous inline version was a simplified non-masked variant
      --  that mis-decoded real archives.
      Status := Ok;
      return Zlib.Seven_Zip_Filters.Branch_Convert
        (Zlib.Seven_Zip_Filters.X86, Input, Encoding => False);
   end Seven_Zip_BCJ_X86_Decode;

   function Seven_Zip_BCJ2_Decode
     (Main_Stream : Byte_Array;
      Call_Stream : Byte_Array;
      Jump_Stream : Byte_Array;
      RC_Stream   : Byte_Array;
      Expected    : Natural;
      Status      : out Status_Code) return Byte_Array
   is
      Empty : constant Byte_Array (1 .. 0) := [others => 0];

      subtype Prob_Index is Natural range 0 .. 257;
      type Prob_Array is array (Prob_Index) of Interfaces.Unsigned_16;

      Top_Value       : constant Interfaces.Unsigned_32 := 16#0100_0000#;
      Bit_Model_Total : constant Interfaces.Unsigned_32 := 2048;
      Move_Bits       : constant Natural := 5;

      Output : Byte_Array (1 .. Expected) := [others => 0];
      Probs  : Prob_Array := [others => 1024];
      RC_Range : Interfaces.Unsigned_32 := Interfaces.Unsigned_32'Last;
      Code   : Interfaces.Unsigned_32 := 0;
      IP     : Interfaces.Unsigned_32 := 0;
      V      : Interfaces.Unsigned_32 := 0;
      Main_Pos : Natural := Main_Stream'First;
      Call_Pos : Natural := Call_Stream'First;
      Jump_Pos : Natural := Jump_Stream'First;
      RC_Pos   : Natural := RC_Stream'First;
      Out_Pos  : Natural := Output'First;

      function Has_Byte (Pos : Natural; Data : Byte_Array) return Boolean is
      begin
         return Pos in Data'Range;
      end Has_Byte;

      function Read_RC_Byte return Boolean is
      begin
         if not Has_Byte (RC_Pos, RC_Stream) then
            return False;
         end if;

         Code :=
           Interfaces.Shift_Left (Code, 8)
           or Interfaces.Unsigned_32 (RC_Stream (RC_Pos));
         RC_Pos := RC_Pos + 1;
         return True;
      end Read_RC_Byte;

      function Read_BE32
        (Data : Byte_Array;
         Pos  : in out Natural;
         Value : out Interfaces.Unsigned_32) return Boolean is
      begin
         if Pos not in Data'Range
           or else Pos + 3 > Data'Last
         then
            Value := 0;
            return False;
         end if;

         Value :=
           Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (Pos)), 24)
           or Interfaces.Shift_Left
             (Interfaces.Unsigned_32 (Data (Pos + 1)), 16)
           or Interfaces.Shift_Left
             (Interfaces.Unsigned_32 (Data (Pos + 2)), 8)
           or Interfaces.Unsigned_32 (Data (Pos + 3));
         Pos := Pos + 4;
         return True;
      end Read_BE32;

      procedure Put_Byte (B : Byte) is
      begin
         Output (Out_Pos) := B;
         Out_Pos := Out_Pos + 1;
         IP := IP + 1;
      end Put_Byte;

      function Candidate (Value : Interfaces.Unsigned_32) return Boolean is
         B : constant Interfaces.Unsigned_32 := Value and 16#FF#;
      begin
         return ((B + 16#18#) and 16#FE#) = 0
           or else
             ((Value - 16#0F00_0080#) and 16#FFFFFFF0#) = 0;
      end Candidate;

      function Prob_For
        (Value : Interfaces.Unsigned_32) return Prob_Index
      is
         C : constant Interfaces.Unsigned_32 :=
           Interfaces.Shift_Right (Value + 16#17#, 6) and 1;
         High : constant Interfaces.Unsigned_32 :=
           Interfaces.Shift_Right (Value, 24) and 16#FF#;
         Low  : constant Interfaces.Unsigned_32 :=
           Interfaces.Shift_Right (Value, 5) and 1;
      begin
         return Prob_Index (((0 - C) and High) + C + Low);
      end Prob_For;

      function Jump_Stream_For
        (Value : Interfaces.Unsigned_32) return Natural
      is
      begin
         return Natural
           ((Interfaces.Shift_Right (Value + 16#57#, 6) and 1));
      end Jump_Stream_For;
   begin
      Status := Unexpected_End_Of_Input;

      for I in 1 .. 5 loop
         if not Read_RC_Byte then
            return Empty;
         end if;

         if I = 2 and then Code /= Interfaces.Unsigned_32 (RC_Stream (RC_Pos - 1))
         then
            return Empty;
         end if;
      end loop;

      if Code = Interfaces.Unsigned_32'Last then
         Status := Invalid_Block_Type;
         return Empty;
      end if;

      while Out_Pos <= Output'Last loop
         if RC_Range < Top_Value then
            if not Read_RC_Byte then
               return Empty;
            end if;
            RC_Range := Interfaces.Shift_Left (RC_Range, 8);
         end if;

         if not Has_Byte (Main_Pos, Main_Stream) then
            return Empty;
         end if;

         declare
            B : constant Byte := Main_Stream (Main_Pos);
         begin
            Main_Pos := Main_Pos + 1;
            Put_Byte (B);
            V :=
              (Interfaces.Shift_Left (V, 24)
               or Interfaces.Unsigned_32 (B));
         end;

         if Out_Pos <= Output'Last and then Candidate (V) then
            declare
               P_Index : constant Prob_Index := Prob_For (V);
               Prob    : constant Interfaces.Unsigned_32 :=
                 Interfaces.Unsigned_32 (Probs (P_Index));
               Bound   : constant Interfaces.Unsigned_32 :=
                 Interfaces.Shift_Right (RC_Range, 11) * Prob;
            begin
               if Code < Bound then
                  RC_Range := Bound;
                  Probs (P_Index) :=
                    Interfaces.Unsigned_16
                      (Prob + Interfaces.Shift_Right
                         (Bit_Model_Total - Prob, Move_Bits));
               else
                  RC_Range := RC_Range - Bound;
                  Code := Code - Bound;
                  Probs (P_Index) :=
                    Interfaces.Unsigned_16
                      (Prob - Interfaces.Shift_Right (Prob, Move_Bits));

                  declare
                     Encoded : Interfaces.Unsigned_32 := 0;
                     Source  : constant Natural := Jump_Stream_For (V);
                     Ok_Read : Boolean;
                  begin
                     if Source = 0 then
                        Ok_Read := Read_BE32
                          (Call_Stream, Call_Pos, Encoded);
                     else
                        Ok_Read := Read_BE32
                          (Jump_Stream, Jump_Pos, Encoded);
                     end if;

                     if not Ok_Read or else Out_Pos + 3 > Output'Last + 1 then
                        return Empty;
                     end if;

                     Encoded := Encoded - (IP + 4);
                     for I in 0 .. 3 loop
                        Output (Out_Pos + I) :=
                          Byte
                            (Interfaces.Shift_Right
                               (Encoded, 8 * I) and 16#FF#);
                     end loop;
                     Out_Pos := Out_Pos + 4;
                     IP := IP + 4;
                     V := Interfaces.Shift_Right (Encoded, 24);
                  end;
               end if;
            end;
         end if;
      end loop;

      if Main_Pos /= Main_Stream'Last + 1
        or else Call_Pos /= Call_Stream'Last + 1
        or else Jump_Pos /= Jump_Stream'Last + 1
      then
         Status := Invalid_Checksum;
         return Empty;
      end if;

      Status := Ok;
      return Output;
   end Seven_Zip_BCJ2_Decode;

   --  Inverse of Seven_Zip_BCJ2_Decode: split x86 code into the four BCJ2
   --  streams (main, call, jump, range-coded control). Converts an E8/E9/0F8x
   --  branch when its 4-byte displacement's high byte passes the x86 BCJ test
   --  (0x00 or 0xFF); the decision is range-coded so any policy round-trips.
   procedure Seven_Zip_BCJ2_Encode
     (Input : Byte_Array;
      Main  : out Byte_Vectors.Vector;
      Call  : out Byte_Vectors.Vector;
      Jump  : out Byte_Vectors.Vector;
      RC    : out Byte_Vectors.Vector)
   is
      subtype Prob_Index is Natural range 0 .. 257;
      type Prob_Array is array (Prob_Index) of Interfaces.Unsigned_32;

      Top_Value       : constant Interfaces.Unsigned_32 := 16#0100_0000#;
      Bit_Model_Total : constant Interfaces.Unsigned_32 := 2048;
      Move_Bits       : constant Natural := 5;

      Probs      : Prob_Array := [others => 1024];
      Rng        : Interfaces.Unsigned_32 := Interfaces.Unsigned_32'Last;
      Low        : Interfaces.Unsigned_64 := 0;
      Cache      : Byte := 0;
      Cache_Size : Interfaces.Unsigned_64 := 1;

      Total : constant Natural := Input'Length;
      IP    : Interfaces.Unsigned_32 := 0;
      V     : Interfaces.Unsigned_32 := 0;
      I     : Natural := Input'First;

      function Candidate (Value : Interfaces.Unsigned_32) return Boolean is
         B : constant Interfaces.Unsigned_32 := Value and 16#FF#;
      begin
         return ((B + 16#18#) and 16#FE#) = 0
           or else ((Value - 16#0F00_0080#) and 16#FFFFFFF0#) = 0;
      end Candidate;

      function Prob_For (Value : Interfaces.Unsigned_32) return Prob_Index is
         C    : constant Interfaces.Unsigned_32 :=
           Interfaces.Shift_Right (Value + 16#17#, 6) and 1;
         High : constant Interfaces.Unsigned_32 :=
           Interfaces.Shift_Right (Value, 24) and 16#FF#;
         Lo   : constant Interfaces.Unsigned_32 :=
           Interfaces.Shift_Right (Value, 5) and 1;
      begin
         return Prob_Index (((0 - C) and High) + C + Lo);
      end Prob_For;

      function Jump_Stream_For (Value : Interfaces.Unsigned_32) return Natural is
        (Natural (Interfaces.Shift_Right (Value + 16#57#, 6) and 1));

      procedure Shift_Low is
      begin
         if Low < 16#FF00_0000#
           or else Low > 16#FFFF_FFFF#
         then
            declare
               Temp : Byte := Cache;
            begin
               loop
                  RC.Append
                    (Byte ((Interfaces.Unsigned_64 (Temp) +
                            Interfaces.Shift_Right (Low, 32)) and 16#FF#));
                  Temp := 16#FF#;
                  Cache_Size := Cache_Size - 1;
                  exit when Cache_Size = 0;
               end loop;
               Cache :=
                 Byte (Interfaces.Shift_Right (Low, 24) and 16#FF#);
            end;
         end if;
         Cache_Size := Cache_Size + 1;
         Low := Interfaces.Shift_Left (Low and 16#00FF_FFFF#, 8);
      end Shift_Low;

      procedure Encode_Bit (Idx : Prob_Index; Bit : Natural) is
         Prob  : constant Interfaces.Unsigned_32 := Probs (Idx);
         Bound : constant Interfaces.Unsigned_32 :=
           Interfaces.Shift_Right (Rng, 11) * Prob;
      begin
         if Bit = 0 then
            Rng := Bound;
            Probs (Idx) :=
              Prob + Interfaces.Shift_Right (Bit_Model_Total - Prob, Move_Bits);
         else
            Low := Low + Interfaces.Unsigned_64 (Bound);
            Rng := Rng - Bound;
            Probs (Idx) := Prob - Interfaces.Shift_Right (Prob, Move_Bits);
         end if;
         if Rng < Top_Value then
            Rng := Interfaces.Shift_Left (Rng, 8);
            Shift_Low;
         end if;
      end Encode_Bit;

      procedure Append_BE32
        (To : in out Byte_Vectors.Vector; Value : Interfaces.Unsigned_32) is
      begin
         To.Append (Byte (Interfaces.Shift_Right (Value, 24) and 16#FF#));
         To.Append (Byte (Interfaces.Shift_Right (Value, 16) and 16#FF#));
         To.Append (Byte (Interfaces.Shift_Right (Value, 8) and 16#FF#));
         To.Append (Byte (Value and 16#FF#));
      end Append_BE32;
   begin
      while I <= Input'Last loop
         declare
            B : constant Byte := Input (I);
         begin
            I := I + 1;
            Main.Append (B);
            IP := IP + 1;
            V := Interfaces.Shift_Left (V, 24) or Interfaces.Unsigned_32 (B);
         end;

         if Natural (IP) < Total and then Candidate (V) then
            declare
               P_Idx   : constant Prob_Index := Prob_For (V);
               Convert : Boolean := False;
               Rel     : Interfaces.Unsigned_32 := 0;
            begin
               --  Need 4 displacement bytes to convert.
               if I + 3 <= Input'Last then
                  Rel :=
                    Interfaces.Unsigned_32 (Input (I))
                    or Interfaces.Shift_Left
                         (Interfaces.Unsigned_32 (Input (I + 1)), 8)
                    or Interfaces.Shift_Left
                         (Interfaces.Unsigned_32 (Input (I + 2)), 16)
                    or Interfaces.Shift_Left
                         (Interfaces.Unsigned_32 (Input (I + 3)), 24);
                  Convert := Input (I + 3) = 0 or else Input (I + 3) = 16#FF#;
               end if;

               if Convert then
                  Encode_Bit (P_Idx, 1);
                  declare
                     Abs_Addr : constant Interfaces.Unsigned_32 :=
                       Rel + IP + 4;
                  begin
                     if Jump_Stream_For (V) = 0 then
                        Append_BE32 (Call, Abs_Addr);
                     else
                        Append_BE32 (Jump, Abs_Addr);
                     end if;
                  end;
                  I := I + 4;
                  IP := IP + 4;
                  V := Interfaces.Shift_Right (Rel, 24);
               else
                  Encode_Bit (P_Idx, 0);
               end if;
            end;
         end if;
      end loop;

      for K in 1 .. 5 loop
         Shift_Low;
      end loop;
   end Seven_Zip_BCJ2_Encode;

   function BZip2_Compress (Plain : Byte_Array; Status : out Status_Code)
                            return Byte_Array
   is
      Empty : constant Byte_Array (1 .. 0) := [others => 0];
   begin
      Status := Unsupported_Method;

      if Interfaces.Unsigned_64 (Plain'Length) >
        Interfaces.Unsigned_64 (Interfaces.C.unsigned'Last)
      then
         return Empty;
      end if;

      declare
         Bound          : constant Natural :=
           Plain'Length + Plain'Length / 100 + 601;
         Output         : Byte_Array (1 .. Bound);
         Output_Len     : aliased Interfaces.C.unsigned :=
           Interfaces.C.unsigned (Bound);
         Empty_Source   : aliased Byte := 0;
         Source_Address : constant System.Address :=
           (if Plain'Length = 0 then Empty_Source'Address
            else Plain (Plain'First)'Address);
         Result         : Interfaces.C.int;
      begin
         Result :=
           BZ2_bzBuffToBuffCompress
             (Dest        => Output (Output'First)'Address,
              Dest_Len    => Output_Len'Access,
              Source      => Source_Address,
              Source_Len  => Interfaces.C.unsigned (Plain'Length),
              Block_Size  => 9,
              Verbosity   => 0,
              Work_Factor => 30);

         if Result /= 0 then
            return Empty;
         end if;

         declare
            Used       : constant Natural := Natural (Output_Len);
            Compressed : Byte_Array (1 .. Used);
         begin
            for I in Compressed'Range loop
               Compressed (I) := Output (I);
            end loop;

            Status := Ok;
            return Compressed;
         end;
      end;
   exception
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end BZip2_Compress;

   function BZip2_Decompress
     (Payload   : Byte_Array;
      Plain_Len : Natural;
      Status    : out Status_Code) return Byte_Array
   is
      Empty : constant Byte_Array (1 .. 0) := [others => 0];
      BZ_OK : constant Interfaces.C.int := 0;
      BZ_STREAM_END : constant Interfaces.C.int := 4;
   begin
      Status := Unsupported_Method;

      if Payload'Length = 0 then
         Status := Unexpected_End_Of_Input;
         return Empty;
      end if;

      declare
         Output_Count : constant Positive := Natural'Max (1, Plain_Len);
         Output       : Byte_Array (1 .. Output_Count);
         Stream       : aliased BZ_Stream;
         Result       : Interfaces.C.int := BZ_OK;
         Finished     : Boolean := False;
      begin
         Stream.Next_In := Payload (Payload'First)'Address;
         Stream.Avail_In := Interfaces.C.unsigned (Payload'Length);
         Stream.Next_Out := Output (Output'First)'Address;
         Stream.Avail_Out := Interfaces.C.unsigned (Output_Count);

         Result := BZ2_bzDecompressInit (Stream'Access, 0, 0);
         if Result /= BZ_OK then
            Status := Invalid_Block_Type;
            return Empty;
         end if;

         while not Finished loop
            Result := BZ2_bzDecompress (Stream'Access);

            if Result = BZ_STREAM_END then
               Finished := True;
            elsif Result /= BZ_OK then
               declare
                  Ignored : constant Interfaces.C.int :=
                    BZ2_bzDecompressEnd (Stream'Access);
                  pragma Unreferenced (Ignored);
               begin
                  Status := Invalid_Block_Type;
                  return Empty;
               end;
            elsif Stream.Avail_Out = 0 then
               declare
                  Ignored : constant Interfaces.C.int :=
                    BZ2_bzDecompressEnd (Stream'Access);
                  pragma Unreferenced (Ignored);
               begin
                  Status := Invalid_Block_Type;
                  return Empty;
               end;
            end if;
         end loop;

         if Stream.Avail_In /= 0
           or else Natural (Stream.Total_Out_Lo32) /= Plain_Len
           or else Stream.Total_Out_Hi32 /= 0
         then
            declare
               Ignored : constant Interfaces.C.int :=
                 BZ2_bzDecompressEnd (Stream'Access);
               pragma Unreferenced (Ignored);
            begin
               Status := Unsupported_Method;
               return Empty;
            end;
         end if;

         declare
            Ignored : constant Interfaces.C.int :=
              BZ2_bzDecompressEnd (Stream'Access);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;

         if Plain_Len = 0 then
            Status := Ok;
            return Empty;
         end if;

         declare
            Plain : Byte_Array (1 .. Plain_Len);
         begin
            for I in Plain'Range loop
               Plain (I) := Output (I);
            end loop;

            Status := Ok;
            return Plain;
         end;
      end;
   exception
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end BZip2_Decompress;

   LZMA2_Default_Props : constant Byte := LZMA_Default_Props;
   LZMA2_Max_Chunk     : constant Natural := 4096;

   procedure LZMA2_Append_Uncompressed_Chunk
     (Output    : in out Byte_Vectors.Vector;
      Chunk     : Byte_Array;
      First     : Boolean)
   is
      Stored : constant Natural := Chunk'Length - 1;
   begin
      Output.Append (if First then 16#01# else 16#02#);
      Output.Append (Byte (Stored / 256));
      Output.Append (Byte (Stored mod 256));
      for B of Chunk loop
         Output.Append (B);
      end loop;
   end LZMA2_Append_Uncompressed_Chunk;

   procedure LZMA2_Append_Compressed_Chunk
     (Output : in out Byte_Vectors.Vector;
      Plain  : Byte_Array;
      Coded  : Byte_Array)
   is
      Unpacked_Size : constant Natural := Plain'Length - 1;
      Packed_Size   : constant Natural := Coded'Length - 1;
   begin
      Output.Append (Byte (16#E0# + Unpacked_Size / 65_536));
      Output.Append (Byte ((Unpacked_Size / 256) mod 256));
      Output.Append (Byte (Unpacked_Size mod 256));
      Output.Append (Byte (Packed_Size / 256));
      Output.Append (Byte (Packed_Size mod 256));
      Output.Append (LZMA2_Default_Props);
      for B of Coded loop
         Output.Append (B);
      end loop;
   end LZMA2_Append_Compressed_Chunk;

   function LZMA2_Encode (Plain : Byte_Array) return Byte_Array is
      Output : Byte_Vectors.Vector;
      Pos    : Natural := Plain'First;
   begin
      while Pos <= Plain'Last loop
         declare
            Remaining : constant Natural := Plain'Last - Pos + 1;
            Chunk_Len : constant Natural :=
              Natural'Min (Remaining, LZMA2_Max_Chunk);
            Chunk     : constant Byte_Array := Plain (Pos .. Pos + Chunk_Len - 1);
            Coded     : constant Byte_Array := LZMA_Encode_Bounded (Chunk);
         begin
            if Coded'Length + 6 < Chunk'Length + 3 then
               LZMA2_Append_Compressed_Chunk (Output, Chunk, Coded);
            else
               LZMA2_Append_Uncompressed_Chunk
                 (Output, Chunk, Pos = Plain'First);
            end if;
            Pos := Pos + Chunk_Len;
         end;
      end loop;

      Output.Append (0);
      return To_Byte_Array (Output);
   end LZMA2_Encode;

   function LZMA_Decode_Raw
     (Stream    : Byte_Array;
      Props     : Seven_Zip_LZMA_Props;
      Plain_Len : Natural;
      Status    : out Status_Code) return Byte_Array;

   function LZMA_Decode_Raw_With
     (Stream    : Byte_Array;
      Props     : Seven_Zip_LZMA_Props;
      Plain_Len : Natural;
      Require_Full_Stream : Boolean;
      Initial_Rep_Distance : Natural;
      Use_Matched_Literals : Boolean;
      Status    : out Status_Code) return Byte_Array;

   function LZMA_Decode_Raw_Encoded_Header
     (Stream    : Byte_Array;
      Props     : Seven_Zip_LZMA_Props;
      Plain_Len : Natural;
      Status    : out Status_Code) return Byte_Array;

   function LZMA_Decode_Raw
     (Stream    : Byte_Array;
      Props     : Seven_Zip_LZMA_Props;
      Plain_Len : Natural;
      Status    : out Status_Code) return Byte_Array
   is
   begin
      return LZMA_Decode_Raw_With
        (Stream, Props, Plain_Len,
         Require_Full_Stream => True,
         Initial_Rep_Distance => 1,
         Use_Matched_Literals => True,
         Status => Status);
   end LZMA_Decode_Raw;

   function LZMA_Decode_Raw_With
     (Stream    : Byte_Array;
      Props     : Seven_Zip_LZMA_Props;
      Plain_Len : Natural;
      Require_Full_Stream : Boolean;
      Initial_Rep_Distance : Natural;
      Use_Matched_Literals : Boolean;
      Status    : out Status_Code) return Byte_Array
   is
      Header : Byte_Vectors.Vector;
   begin
      Header.Append (0);
      Header.Append (0);
      Header.Append (5);
      Header.Append (0);
      for B of Props loop
         Header.Append (B);
      end loop;
      for B of Stream loop
         Header.Append (B);
      end loop;
      return Decode_LZMA_Payload
        (To_Byte_Array (Header), Plain_Len,
         Require_Full_Stream => Require_Full_Stream,
         Initial_Rep_Distance => Initial_Rep_Distance,
         Use_Matched_Literals => Use_Matched_Literals,
         Status => Status);
   end LZMA_Decode_Raw_With;

   function LZMA_Decode_Raw_Encoded_Header
     (Stream    : Byte_Array;
      Props     : Seven_Zip_LZMA_Props;
      Plain_Len : Natural;
      Status    : out Status_Code) return Byte_Array
   is
      Local_Status : Status_Code := Ok;
      Strict_Default : constant Byte_Array :=
        LZMA_Decode_Raw_With
          (Stream, Props, Plain_Len,
           Require_Full_Stream => True,
           Initial_Rep_Distance => 1,
           Use_Matched_Literals => True,
           Status => Local_Status);
   begin
      if Local_Status = Ok then
         Status := Ok;
         return Strict_Default;
      end if;

      declare
         Strict_Seven_Zip : constant Byte_Array :=
           LZMA_Decode_Raw_With
             (Stream, Props, Plain_Len,
              Require_Full_Stream => True,
              Initial_Rep_Distance => 1,
              Use_Matched_Literals => True,
              Status => Local_Status);
      begin
         if Local_Status = Ok then
            Status := Ok;
            return Strict_Seven_Zip;
         end if;
      end;

      return LZMA_Decode_Raw_With
        (Stream, Props, Plain_Len,
         Require_Full_Stream => False,
         Initial_Rep_Distance => 1,
         Use_Matched_Literals => True,
         Status => Status);
   end LZMA_Decode_Raw_Encoded_Header;

   type LZMA2_Decode_Context is record
      LC           : Natural := LZMA_Default_LC;
      LP           : Natural := LZMA_Default_LP;
      PB           : Natural := LZMA_Default_PB;
      Props_Seen   : Boolean := False;
      Dict_Base    : Natural := 0;
      State        : Natural := 0;
      Prev         : Byte := 0;
      Rep0         : Natural := 0;
      Rep1         : Natural := 0;
      Rep2         : Natural := 0;
      Rep3         : Natural := 0;
      Is_Match     : LZMA_Prob_Array
        (0 .. LZMA_Num_States * LZMA_Num_Pos_States_Max - 1);
      Is_Rep       : LZMA_Prob_Array (0 .. LZMA_Num_States - 1);
      Is_Rep_G0    : LZMA_Prob_Array (0 .. LZMA_Num_States - 1);
      Is_Rep_G1    : LZMA_Prob_Array (0 .. LZMA_Num_States - 1);
      Is_Rep_G2    : LZMA_Prob_Array (0 .. LZMA_Num_States - 1);
      Is_Rep0_Long : LZMA_Prob_Array
        (0 .. LZMA_Num_States * LZMA_Num_Pos_States_Max - 1);
      Match_Len    : LZMA_Len_Encoder;
      Rep_Len      : LZMA_Len_Encoder;
      Pos_Slot     : LZMA_Prob_Array
        (0 .. LZMA_Num_Len_To_Pos_States * 64 - 1);
      Pos_Special  : LZMA_Prob_Array
        (0 .. LZMA_Num_Full_Distances - LZMA_End_Pos_Model_Index - 1);
      Pos_Align    : LZMA_Prob_Array (0 .. LZMA_Align_Table_Size - 1);
      Literals     : LZMA_Prob_Array
        (0 .. (2 ** 4) * LZMA_Literal_Probs - 1);
   end record;

   function LZMA2_Set_Properties
     (Ctx   : in out LZMA2_Decode_Context;
      Props : Byte) return Boolean
   is
      Props_Value : constant Natural := Natural (Props);
      LCLP        : constant Natural := Props_Value mod 9;
      Rest        : constant Natural := Props_Value / 9;
      LC          : constant Natural := LCLP;
      LP          : constant Natural := Rest mod 5;
      PB          : constant Natural := Rest / 5;
   begin
      if not Valid_LZMA_Props (Props) then
         return False;
      end if;

      Ctx.LC := LC;
      Ctx.LP := LP;
      Ctx.PB := PB;
      Ctx.Props_Seen := True;
      return True;
   end LZMA2_Set_Properties;

   procedure LZMA2_Reset_State (Ctx : in out LZMA2_Decode_Context) is
   begin
      Ctx.State := 0;
      Ctx.Prev := 0;
      --  Standard LZMA initial reps: 0-based 0 == distance 1 (our 1-based
      --  convention). Only used by an early rep before any normal match.
      Ctx.Rep0 := 1;
      Ctx.Rep1 := 1;
      Ctx.Rep2 := 1;
      Ctx.Rep3 := 1;
      LZMA_Init_Probs (Ctx.Is_Match);
      LZMA_Init_Probs (Ctx.Is_Rep);
      LZMA_Init_Probs (Ctx.Is_Rep_G0);
      LZMA_Init_Probs (Ctx.Is_Rep_G1);
      LZMA_Init_Probs (Ctx.Is_Rep_G2);
      LZMA_Init_Probs (Ctx.Is_Rep0_Long);
      LZMA_Init_Len (Ctx.Match_Len);
      LZMA_Init_Len (Ctx.Rep_Len);
      LZMA_Init_Probs (Ctx.Pos_Slot);
      LZMA_Init_Probs (Ctx.Pos_Special);
      LZMA_Init_Probs (Ctx.Pos_Align);
      LZMA_Init_Probs (Ctx.Literals);
   end LZMA2_Reset_State;

   procedure LZMA2_Decode_Compressed_Chunk
     (Ctx       : in out LZMA2_Decode_Context;
      Stream    : Byte_Array;
      Plain     : in out Byte_Array;
      Out_Pos   : in out Natural;
      Chunk_Len : Natural;
      Status    : in out Status_Code)
   is
      D          : LZMA_Range_Decoder;
      Target_Pos : constant Natural := Out_Pos + Chunk_Len;
      Pos_States : constant Natural := 2 ** Ctx.PB;
   begin
      if Status /= Ok then
         return;
      end if;

      if not Ctx.Props_Seen or else Stream'Length < 5 then
         Status := Unexpected_End_Of_Input;
         return;
      end if;

      LZMA_Decoder_Init (D, Stream, Status);

      while Status = Ok and then Out_Pos < Target_Pos loop
         declare
            Pos_State : constant Natural := Out_Pos mod Pos_States;
            Match_Bit : constant Natural :=
              LZMA_Decode_Bit
                (D, Stream,
                 Ctx.Is_Match (Ctx.State * LZMA_Num_Pos_States_Max
                               + Pos_State),
                 Status);
         begin
            if Status /= Ok then
               exit;
            end if;

            if Match_Bit = 0 then
               declare
                  Context : constant Natural :=
                    LZMA_Literal_Context (Ctx.LC, Ctx.LP, Out_Pos, Ctx.Prev);
                  Symbol  : Natural := 1;
               begin
                  if Ctx.State >= 7
                    and then Ctx.Rep0 > 0
                    and then Ctx.Rep0 <= Out_Pos - Ctx.Dict_Base
                  then
                     --  Matched literal (standard LZMA): decode bits against
                     --  the byte Rep0 back until they diverge.
                     declare
                        Match_Byte : Natural :=
                          Natural (Plain (Out_Pos - Ctx.Rep0 + 1));
                     begin
                        while Symbol < 16#100# loop
                           Match_Byte := Match_Byte * 2;
                           declare
                              Match_Bit_Literal : constant Natural :=
                                ((Match_Byte / 16#100#) mod 2) * 16#100#;
                              Decoded_Bit : constant Natural :=
                                LZMA_Decode_Bit
                                  (D, Stream,
                                   Ctx.Literals
                                     (Context * LZMA_Literal_Probs
                                      + 16#100# + Match_Bit_Literal + Symbol),
                                   Status);
                           begin
                              Symbol := Symbol * 2 + Decoded_Bit;
                              exit when Status /= Ok
                                or else Match_Bit_Literal /=
                                  Decoded_Bit * 16#100#;
                           end;
                        end loop;
                     end;
                  end if;

                  while Symbol < 16#100# loop
                     Symbol :=
                       Symbol * 2
                       + LZMA_Decode_Bit
                         (D, Stream,
                          Ctx.Literals
                            (Context * LZMA_Literal_Probs + Symbol),
                          Status);
                     exit when Status /= Ok;
                  end loop;

                  if Status /= Ok then
                     exit;
                  end if;

                  Out_Pos := Out_Pos + 1;
                  Plain (Out_Pos) := Byte (Symbol - 16#100#);
                  Ctx.Prev := Plain (Out_Pos);
                  Ctx.State := LZMA_Literal_State_After (Ctx.State);
               end;
            else
               if LZMA_Decode_Bit
                 (D, Stream, Ctx.Is_Rep (Ctx.State), Status) /= 0
               then
                  declare
                     Distance : Natural := Ctx.Rep0;
                     Len      : Natural := LZMA_Min_Match_Length;
                  begin
                     if LZMA_Decode_Bit
                       (D, Stream, Ctx.Is_Rep_G0 (Ctx.State), Status) = 0
                     then
                        if LZMA_Decode_Bit
                          (D, Stream,
                           Ctx.Is_Rep0_Long
                             (Ctx.State * LZMA_Num_Pos_States_Max
                              + Pos_State),
                           Status) = 0
                        then
                           Len := 1;
                           Ctx.State := LZMA_Short_Rep_State_After (Ctx.State);
                        else
                           Len :=
                             LZMA_Decode_Len
                               (D, Stream, Ctx.Rep_Len, Pos_State, Status)
                             + LZMA_Min_Match_Length;
                           Ctx.State := LZMA_Rep_State_After (Ctx.State);
                        end if;
                     else
                        if LZMA_Decode_Bit
                          (D, Stream, Ctx.Is_Rep_G1 (Ctx.State),
                           Status) = 0
                        then
                           Distance := Ctx.Rep1;
                        else
                           if LZMA_Decode_Bit
                             (D, Stream, Ctx.Is_Rep_G2 (Ctx.State),
                              Status) = 0
                           then
                              Distance := Ctx.Rep2;
                           else
                              Distance := Ctx.Rep3;
                              Ctx.Rep3 := Ctx.Rep2;
                           end if;
                           Ctx.Rep2 := Ctx.Rep1;
                        end if;
                        Ctx.Rep1 := Ctx.Rep0;
                        Ctx.Rep0 := Distance;
                        Len :=
                          LZMA_Decode_Len
                            (D, Stream, Ctx.Rep_Len, Pos_State, Status)
                          + LZMA_Min_Match_Length;
                        Ctx.State := LZMA_Rep_State_After (Ctx.State);
                     end if;

                     if Status /= Ok then
                        exit;
                     end if;

                     if Distance = 0
                       or else Distance > Out_Pos - Ctx.Dict_Base
                       or else Len > Target_Pos - Out_Pos
                     then
                        Status := Unsupported_Method;
                        return;
                     end if;

                     for I in 1 .. Len loop
                        Out_Pos := Out_Pos + 1;
                        Plain (Out_Pos) := Plain (Out_Pos - Distance);
                     end loop;

                     Ctx.Prev := Plain (Out_Pos);
                  end;
               else
                  declare
                     Len_Symbol : constant Natural :=
                       LZMA_Decode_Len
                         (D, Stream, Ctx.Match_Len, Pos_State, Status);
                     Len        : constant Natural :=
                       Len_Symbol + LZMA_Min_Match_Length;
                     Distance   : constant Natural :=
                       LZMA_Decode_Distance
                         (D, Stream, Ctx.Pos_Slot, Ctx.Pos_Special,
                          Ctx.Pos_Align, Len, Status);
                  begin
                     if Status /= Ok then
                        exit;
                     end if;

                     if Distance > Out_Pos - Ctx.Dict_Base
                       or else Len > Target_Pos - Out_Pos
                     then
                        Status := Unsupported_Method;
                        return;
                     end if;

                     for I in 1 .. Len loop
                        Out_Pos := Out_Pos + 1;
                        Plain (Out_Pos) := Plain (Out_Pos - Distance);
                     end loop;

                     Ctx.Rep3 := Ctx.Rep2;
                     Ctx.Rep2 := Ctx.Rep1;
                     Ctx.Rep1 := Ctx.Rep0;
                     Ctx.Rep0 := Distance;
                     Ctx.Prev := Plain (Out_Pos);
                     Ctx.State := LZMA_Match_State_After (Ctx.State);
                  end;
               end if;
            end if;
         end;
      end loop;

      if Status = Ok and then D.Pos /= Stream'Length then
         Status := Unsupported_Method;
      end if;
   end LZMA2_Decode_Compressed_Chunk;

   function LZMA2_Decode
     (Payload   : Byte_Array;
      Plain_Len : Natural;
      Status    : out Status_Code) return Byte_Array
   is
      Empty   : constant Byte_Array (1 .. 0) := [others => 0];
      Plain   : Byte_Array (1 .. Natural'Max (1, Plain_Len));
      Pos     : Natural := Payload'First;
      Out_Pos : Natural := 0;
      First   : Boolean := True;
      Ctx     : LZMA2_Decode_Context;
   begin
      Status := Unsupported_Method;
      LZMA2_Reset_State (Ctx);

      loop
         if Pos > Payload'Last then
            Status := Unexpected_End_Of_Input;
            return Empty;
         end if;

         declare
            Control : constant Byte := Payload (Pos);
         begin
            Pos := Pos + 1;
            if Control = 0 then
               exit;
            end if;

            if Control = 16#01# or else Control = 16#02# then
               if (First and then Control /= 16#01#)
                 or else Pos + 1 > Payload'Last
               then
                  Status := Unsupported_Method;
                  return Empty;
               end if;

               declare
                  Chunk_Len : constant Natural :=
                    Natural (Payload (Pos)) * 256
                    + Natural (Payload (Pos + 1)) + 1;
               begin
                  Pos := Pos + 2;
                  if Chunk_Len > Plain_Len - Out_Pos
                    or else Pos + Chunk_Len - 1 > Payload'Last
                  then
                     Status := Unexpected_End_Of_Input;
                     return Empty;
                  end if;

                  for I in 1 .. Chunk_Len loop
                     Plain (Out_Pos + I) := Payload (Pos + I - 1);
                  end loop;
                  Out_Pos := Out_Pos + Chunk_Len;
                  Pos := Pos + Chunk_Len;
                  if Control = 16#01# then
                     Ctx.Dict_Base := Out_Pos;
                  end if;
                  First := False;
               end;
            elsif Control >= 16#80# then
               declare
                  Need_Props : constant Boolean := Control >= 16#C0#;
               begin
                  if Pos + 3 + (if Need_Props then 1 else 0) > Payload'Last then
                     Status := Unexpected_End_Of_Input;
                     return Empty;
                  end if;
               end;

               declare
                  Need_Props : constant Boolean := Control >= 16#C0#;
                  Reset_State : constant Boolean := Control >= 16#A0#;
                  Reset_Dict  : constant Boolean := Control >= 16#E0#;
                  Chunk_Len   : constant Natural :=
                    Natural (Control and 16#1F#) * 65_536
                    + Natural (Payload (Pos)) * 256
                    + Natural (Payload (Pos + 1)) + 1;
                  Packed_Len  : constant Natural :=
                    Natural (Payload (Pos + 2)) * 256
                    + Natural (Payload (Pos + 3)) + 1;
                  Props       : Byte := 0;
                  Local_Status : Status_Code := Ok;
               begin
                  Pos := Pos + 4;

                  if Reset_Dict then
                     Ctx.Dict_Base := Out_Pos;
                  end if;

                  if Reset_State then
                     LZMA2_Reset_State (Ctx);
                  end if;

                  if Need_Props then
                     Props := Payload (Pos);
                     Pos := Pos + 1;
                     if not LZMA2_Set_Properties (Ctx, Props) then
                        Status := Unsupported_Method;
                        return Empty;
                     end if;
                  elsif not Ctx.Props_Seen then
                     Status := Unsupported_Method;
                     return Empty;
                  end if;

                  if Chunk_Len > Plain_Len - Out_Pos
                    or else Pos + Packed_Len - 1 > Payload'Last
                  then
                     Status := Unexpected_End_Of_Input;
                     return Empty;
                  end if;

                  LZMA2_Decode_Compressed_Chunk
                    (Ctx, Payload (Pos .. Pos + Packed_Len - 1),
                     Plain, Out_Pos, Chunk_Len, Local_Status);

                  if Local_Status /= Ok then
                     Status := Local_Status;
                     return Empty;
                  end if;

                  Pos := Pos + Packed_Len;
                  First := False;
               end;
            else
               Status := Unsupported_Method;
               return Empty;
            end if;
         end;
      end loop;

      if Out_Pos /= Plain_Len or else Pos /= Payload'Last + 1 then
         Status := Unsupported_Method;
         return Empty;
      end if;

      Status := Ok;
      if Plain_Len = 0 then
         return Empty;
      end if;
      return Plain (1 .. Plain_Len);
   exception
      when Constraint_Error =>
         Status := Unexpected_End_Of_Input;
         return Empty;
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end LZMA2_Decode;

   function Seven_Zip_Entry_Name_Valid (Entry_Name : String) return Boolean is
   begin
      return Entry_Name'Length > 0 and then not Contains_NUL (Entry_Name);
   exception
      when others =>
         return False;
   end Seven_Zip_Entry_Name_Valid;

   function Seven_Zip_Output_File_Writable (Output_Path : String) return Boolean is
   begin
      if Output_Path'Length = 0 then
         return False;
      end if;

      if Ada.Directories.Exists (Output_Path)
        and then Ada.Directories.Kind (Output_Path) = Ada.Directories.Directory
      then
         return False;
      end if;

      declare
         Parent_Path : constant String :=
           Ada.Directories.Containing_Directory (Output_Path);
      begin
         return not Ada.Directories.Exists (Parent_Path)
           or else Ada.Directories.Kind (Parent_Path) = Ada.Directories.Directory;
      end;
   exception
      when others =>
         return False;
   end Seven_Zip_Output_File_Writable;

   function Seven_Zip_Input_Path_Readable (Input_Path : String) return Boolean is
   begin
      return Input_Path'Length > 0
        and then Ada.Directories.Exists (Input_Path)
        and then Ada.Directories.Kind (Input_Path) in
          Ada.Directories.Ordinary_File | Ada.Directories.Directory;
   exception
      when others =>
         return False;
   end Seven_Zip_Input_Path_Readable;

   function Seven_Zip_Output_Directory_Writable
     (Output_Dir : String) return Boolean
   is
   begin
      if Output_Dir'Length = 0 then
         return False;
      end if;

      if Ada.Directories.Exists (Output_Dir) then
         return Ada.Directories.Kind (Output_Dir) = Ada.Directories.Directory;
      end if;

      declare
         Parent_Path : constant String :=
           Ada.Directories.Containing_Directory (Output_Dir);
      begin
         return not Ada.Directories.Exists (Parent_Path)
           or else Ada.Directories.Kind (Parent_Path) = Ada.Directories.Directory;
      end;
   exception
      when others =>
      return False;
   end Seven_Zip_Output_Directory_Writable;

   function Seven_Zip_Input_Paths_Readable
     (Input_Paths : Text_Array) return Boolean
   is
   begin
      for Input_Path_Text of Input_Paths loop
         declare
            Input_Path : constant String := US.To_String (Input_Path_Text);
         begin
            if Input_Path'Length = 0
              or else not Ada.Directories.Exists (Input_Path)
              or else Ada.Directories.Kind (Input_Path) not in
                Ada.Directories.Ordinary_File | Ada.Directories.Directory
            then
               return False;
            end if;
         end;
      end loop;

      return True;
   exception
      when others =>
         return False;
   end Seven_Zip_Input_Paths_Readable;

   procedure Append_Seven_Zip_File_Metadata
     (Header   : in out Byte_Vectors.Vector;
      Metadata : Seven_Zip_Entry_Metadata);

   procedure Append_Seven_Zip_Bits
     (Data  : in out Byte_Vectors.Vector;
      Bits  : Seven_Zip_Boolean_Array;
      Count : Natural)
   is
      Byte_Value : Natural := 0;
   begin
      if Count = 0 then
         return;
      end if;

      for I in 1 .. Count loop
         if Bits (Bits'First + I - 1) then
            Byte_Value := Byte_Value + 2 ** (7 - ((I - 1) mod 8));
         end if;

         if I mod 8 = 0 then
            Data.Append (Byte (Byte_Value));
            Byte_Value := 0;
         end if;
      end loop;

      if Count mod 8 /= 0 then
         Data.Append (Byte (Byte_Value));
      end if;
   end Append_Seven_Zip_Bits;

   function Seven_Zip_Header_Only_Entry
     (Entry_Name : String;
      Metadata   : Seven_Zip_Entry_Metadata;
      Status     : out Status_Code) return Byte_Array
   is
      Empty      : constant Byte_Array (1 .. 0) := [others => 0];
      Header     : Byte_Vectors.Vector;
      Name_Field : Byte_Vectors.Vector;
   begin
      Status := Unsupported_Method;

      if not Seven_Zip_Entry_Name_Valid (Entry_Name)
        or else not Metadata.Is_Directory
      then
         return Empty;
      end if;

      Header.Append (16#01#); --  Header
      Header.Append (16#05#); --  FilesInfo
      Append_Seven_Zip_Number (Header, 1);
      Header.Append (16#11#); --  Name
      Name_Field.Append (0);
      Append_UTF16LE_NT (Name_Field, Entry_Name);
      Append_Seven_Zip_Number
        (Header, Interfaces.Unsigned_64 (Name_Field.Length));
      Header.Append_Vector (Name_Field);
      Header.Append (16#0E#); --  EmptyStream
      Append_Seven_Zip_Number (Header, 1);
      Header.Append (16#80#);
      Header.Append (16#0F#); --  EmptyFile
      Append_Seven_Zip_Number (Header, 1);
      Header.Append (0);
      Append_Seven_Zip_File_Metadata (Header, Metadata);
      Header.Append (0);
      Header.Append (0);

      declare
         Header_Image : constant Byte_Array := To_Byte_Array (Header);
         Header_CRC   : constant Interfaces.Unsigned_32 :=
           Seven_Zip_Header_CRC (Header_Image);
         Start_Header : Byte_Vectors.Vector;
      begin
         Append_U64_LE (Start_Header, 0);
         Append_U64_LE
           (Start_Header, Interfaces.Unsigned_64 (Header_Image'Length));
         Append_U32_LE (Start_Header, Header_CRC);

         declare
            Start_Header_Image : constant Byte_Array :=
              To_Byte_Array (Start_Header);
            Start_CRC          : constant Interfaces.Unsigned_32 :=
              Seven_Zip_Header_CRC (Start_Header_Image);
            Archive            : Byte_Vectors.Vector;
         begin
            Archive.Append (16#37#);
            Archive.Append (16#7A#);
            Archive.Append (16#BC#);
            Archive.Append (16#AF#);
            Archive.Append (16#27#);
            Archive.Append (16#1C#);
            Archive.Append (0);
            Archive.Append (4);
            Append_U32_LE (Archive, Start_CRC);
            Archive.Append_Vector (Start_Header);
            Archive.Append_Vector (Header);

            Status := Ok;
            return To_Byte_Array (Archive);
         end;
      end;
   exception
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end Seven_Zip_Header_Only_Entry;

   function Seven_Zip_Single_File
     (Packed_Data   : Byte_Array;
      Unpacked_Data : Byte_Array;
      Entry_Name    : String;
      Method        : Seven_Zip_Coder_Method;
      Metadata      : Seven_Zip_Entry_Metadata;
      Status        : out Status_Code) return Byte_Array
   is
      Empty : constant Byte_Array (1 .. 0) := [others => 0];
   begin
      Status := Unsupported_Method;

      if not Seven_Zip_Entry_Name_Valid (Entry_Name)
      then
         return Empty;
      end if;

      if Metadata.Is_Directory then
         return Seven_Zip_Header_Only_Entry (Entry_Name, Metadata, Status);
      end if;

      declare
         Packed_CRC   : constant Interfaces.Unsigned_32 := CRC32 (Packed_Data);
         Unpacked_CRC : constant Interfaces.Unsigned_32 := CRC32 (Unpacked_Data);
         Header       : Byte_Vectors.Vector;
         Name_Field   : Byte_Vectors.Vector;
      begin
         Header.Append (16#01#); --  Header

         Header.Append (16#04#); --  MainStreamsInfo
         Header.Append (16#06#); --  PackInfo
         Append_Seven_Zip_Number (Header, 0);
         Append_Seven_Zip_Number (Header, 1);
         Header.Append (16#09#); --  Size
         Append_Seven_Zip_Number
           (Header, Interfaces.Unsigned_64 (Packed_Data'Length));
         Header.Append (16#0A#); --  CRC
         Header.Append (1);
         Append_U32_LE (Header, Packed_CRC);
         Header.Append (0);

         Header.Append (16#07#); --  UnPackInfo
         Header.Append (16#0B#); --  Folder
         Append_Seven_Zip_Number (Header, 1);
         Header.Append (0);
         Append_Seven_Zip_Number (Header, 1);
         Append_Seven_Zip_Coder (Header, Method);
         Header.Append (16#0C#); --  CodersUnPackSize
         Append_Seven_Zip_Number
           (Header, Interfaces.Unsigned_64 (Unpacked_Data'Length));
         Header.Append (16#0A#); --  CRC
         Header.Append (1);
         Append_U32_LE (Header, Unpacked_CRC);
         Header.Append (0);
         Header.Append (0);

         Header.Append (16#05#); --  FilesInfo
         Append_Seven_Zip_Number (Header, 1);
         Header.Append (16#11#); --  Name
         Name_Field.Append (0);
         Append_UTF16LE_NT (Name_Field, Entry_Name);
         Append_Seven_Zip_Number
           (Header, Interfaces.Unsigned_64 (Name_Field.Length));
         Header.Append_Vector (Name_Field);
         Append_Seven_Zip_File_Metadata (Header, Metadata);
         Header.Append (0);
         Header.Append (0);

         declare
            Header_Image : constant Byte_Array := To_Byte_Array (Header);
            Header_CRC   : constant Interfaces.Unsigned_32 :=
              Seven_Zip_Header_CRC (Header_Image);
            Start_Header : Byte_Vectors.Vector;
         begin
            Append_U64_LE
              (Start_Header, Interfaces.Unsigned_64 (Packed_Data'Length));
            Append_U64_LE
              (Start_Header, Interfaces.Unsigned_64 (Header_Image'Length));
            Append_U32_LE (Start_Header, Header_CRC);

            declare
               Start_Header_Image : constant Byte_Array :=
                 To_Byte_Array (Start_Header);
               Start_CRC          : constant Interfaces.Unsigned_32 :=
                 Seven_Zip_Header_CRC (Start_Header_Image);
               Archive            : Byte_Vectors.Vector;
            begin
               Archive.Append (16#37#);
               Archive.Append (16#7A#);
               Archive.Append (16#BC#);
               Archive.Append (16#AF#);
               Archive.Append (16#27#);
               Archive.Append (16#1C#);
               Archive.Append (0);
               Archive.Append (4);
               Append_U32_LE (Archive, Start_CRC);
               Archive.Append_Vector (Start_Header);
               for B of Packed_Data loop
                  Archive.Append (B);
               end loop;
               Archive.Append_Vector (Header);

               Status := Ok;
               return To_Byte_Array (Archive);
            end;
         end;
      end;
   exception
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end Seven_Zip_Single_File;

   --  Build a one-file .7z whose data is LZMA-compressed then AES-256
   --  encrypted (method 06F10701). Folder is [AES -> LZMA] with bind pair
   --  LZMA.in <- AES.out; the AES coder props carry numCyclesPower=19, no
   --  salt, and a 16-byte IV.
   function Seven_Zip_LZMA_Encrypted
     (Input      : Byte_Array;
      Entry_Name : String;
      Password   : String;
      Status     : out Status_Code) return Byte_Array
   is
      Empty : constant Byte_Array (1 .. 0) := [others => 0];
      Num_Cycles_Power : constant := 19;
   begin
      Status := Unsupported_Method;
      if not Seven_Zip_Entry_Name_Valid (Entry_Name) then
         return Empty;
      end if;

      declare
         Compressed : constant Byte_Array := LZMA_Encode_Bounded (Input);
         Padded     : constant Byte_Array :=
           Zlib.Seven_Zip_AES.Pad_To_Block (Compressed);
         Key        : constant Byte_Array :=
           Zlib.Seven_Zip_AES.Derive_Key (Password, Empty, Num_Cycles_Power);
         IV         : constant Byte_Array := Zlib.Seven_Zip_AES.Random_IV;
      begin
         declare
            Pack_V : constant Byte_Array :=
              Zlib.Seven_Zip_AES.Encrypt_CBC (Key, IV, Padded);
            Unpacked_CRC : constant Interfaces.Unsigned_32 := CRC32 (Input);
            Header     : Byte_Vectors.Vector;
            Name_Field : Byte_Vectors.Vector;
         begin
            if Pack_V'Length = 0 then
               return Empty;
            end if;

            Header.Append (16#01#);
            Header.Append (16#04#); --  MainStreamsInfo
            Header.Append (16#06#); --  PackInfo
            Append_Seven_Zip_Number (Header, 0);
            Append_Seven_Zip_Number (Header, 1);
            Header.Append (16#09#); --  Size
            Append_Seven_Zip_Number
              (Header, Interfaces.Unsigned_64 (Pack_V'Length));
            Header.Append (0);      --  end PackInfo

            Header.Append (16#07#); --  UnPackInfo
            Header.Append (16#0B#); --  Folder
            Append_Seven_Zip_Number (Header, 1);  --  one folder
            Header.Append (0);                    --  external
            Append_Seven_Zip_Number (Header, 2);  --  two coders
            --  Coder 0: AES (06F10701) with 18-byte props (control + IV).
            Header.Append (16#24#);
            Header.Append (16#06#);
            Header.Append (16#F1#);
            Header.Append (16#07#);
            Header.Append (16#01#);
            Append_Seven_Zip_Number (Header, 18);
            Header.Append (16#53#); --  numCyclesPower=19, ivSize bit
            Header.Append (16#0F#); --  ivSize low nibble (=> ivSize 16)
            for B of IV loop
               Header.Append (B);
            end loop;
            --  Coder 1: LZMA.
            Append_Seven_Zip_Coder (Header, Seven_Zip_LZMA_Method);
            --  Bind pair: LZMA.in (1) <- AES.out (0).
            Append_Seven_Zip_Number (Header, 1);
            Append_Seven_Zip_Number (Header, 0);
            Header.Append (16#0C#); --  CodersUnPackSize
            Append_Seven_Zip_Number
              (Header, Interfaces.Unsigned_64 (Compressed'Length));
            Append_Seven_Zip_Number
              (Header, Interfaces.Unsigned_64 (Input'Length));
            Header.Append (0);      --  end UnPackInfo

            Header.Append (16#08#); --  SubStreamsInfo
            Header.Append (16#0A#); --  CRC
            Header.Append (1);
            Append_U32_LE (Header, Unpacked_CRC);
            Header.Append (0);      --  end SubStreamsInfo
            Header.Append (0);      --  end MainStreamsInfo

            Header.Append (16#05#); --  FilesInfo
            Append_Seven_Zip_Number (Header, 1);
            Header.Append (16#11#); --  Name
            Name_Field.Append (0);
            Append_UTF16LE_NT (Name_Field, Entry_Name);
            Append_Seven_Zip_Number
              (Header, Interfaces.Unsigned_64 (Name_Field.Length));
            Header.Append_Vector (Name_Field);
            Header.Append (0);
            Header.Append (0);

            declare
               Header_Image : constant Byte_Array := To_Byte_Array (Header);
               Header_CRC   : constant Interfaces.Unsigned_32 :=
                 Seven_Zip_Header_CRC (Header_Image);
               Start_Header : Byte_Vectors.Vector;
            begin
               Append_U64_LE
                 (Start_Header, Interfaces.Unsigned_64 (Pack_V'Length));
               Append_U64_LE
                 (Start_Header, Interfaces.Unsigned_64 (Header_Image'Length));
               Append_U32_LE (Start_Header, Header_CRC);
               declare
                  Start_Image : constant Byte_Array :=
                    To_Byte_Array (Start_Header);
                  Start_CRC   : constant Interfaces.Unsigned_32 :=
                    Seven_Zip_Header_CRC (Start_Image);
                  Archive     : Byte_Vectors.Vector;
               begin
                  Archive.Append (16#37#);
                  Archive.Append (16#7A#);
                  Archive.Append (16#BC#);
                  Archive.Append (16#AF#);
                  Archive.Append (16#27#);
                  Archive.Append (16#1C#);
                  Archive.Append (0);
                  Archive.Append (4);
                  Append_U32_LE (Archive, Start_CRC);
                  Archive.Append_Vector (Start_Header);
                  for B of Pack_V loop
                     Archive.Append (B);
                  end loop;
                  Archive.Append_Vector (Header);
                  Status := Ok;
                  return To_Byte_Array (Archive);
               end;
            end;
         end;
      end;
   exception
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end Seven_Zip_LZMA_Encrypted;

   --  Build a one-file .7z whose data is BCJ2-filtered (method 0303011B): a
   --  single BCJ2 coder with four packed streams (main, call, jump, range),
   --  stored uncompressed, exactly as stock "7z a -m0=BCJ2" lays it out.
   function Seven_Zip_BCJ2
     (Input      : Byte_Array;
      Entry_Name : String;
      Status     : out Status_Code) return Byte_Array
   is
      Empty : constant Byte_Array (1 .. 0) := [others => 0];
   begin
      Status := Unsupported_Method;
      if not Seven_Zip_Entry_Name_Valid (Entry_Name) then
         return Empty;
      end if;

      declare
         Main_V, Call_V, Jump_V, RC_V : Byte_Vectors.Vector;
      begin
         Seven_Zip_BCJ2_Encode (Input, Main_V, Call_V, Jump_V, RC_V);
         declare
            Main_B : constant Byte_Array := To_Byte_Array (Main_V);
            Call_B : constant Byte_Array := To_Byte_Array (Call_V);
            Jump_B : constant Byte_Array := To_Byte_Array (Jump_V);
            RC_B   : constant Byte_Array := To_Byte_Array (RC_V);
            Unpacked_CRC : constant Interfaces.Unsigned_32 := CRC32 (Input);
            Header     : Byte_Vectors.Vector;
            Name_Field : Byte_Vectors.Vector;
         begin
            Header.Append (16#01#);
            Header.Append (16#04#); --  MainStreamsInfo
            Header.Append (16#06#); --  PackInfo
            Append_Seven_Zip_Number (Header, 0);
            Append_Seven_Zip_Number (Header, 4);  --  four packed streams
            Header.Append (16#09#); --  Size
            Append_Seven_Zip_Number
              (Header, Interfaces.Unsigned_64 (Main_B'Length));
            Append_Seven_Zip_Number
              (Header, Interfaces.Unsigned_64 (Call_B'Length));
            Append_Seven_Zip_Number
              (Header, Interfaces.Unsigned_64 (Jump_B'Length));
            Append_Seven_Zip_Number
              (Header, Interfaces.Unsigned_64 (RC_B'Length));
            Header.Append (16#00#); --  end PackInfo

            Header.Append (16#07#); --  UnPackInfo
            Header.Append (16#0B#); --  Folder
            Append_Seven_Zip_Number (Header, 1);  --  one folder
            Header.Append (16#00#);               --  external
            Append_Seven_Zip_Number (Header, 1);  --  one coder
            Header.Append (16#14#);  --  flag: idSize 4, complex coder
            Header.Append (16#03#);
            Header.Append (16#03#);
            Header.Append (16#01#);
            Header.Append (16#1B#);  --  BCJ2 id (0303011B)
            Append_Seven_Zip_Number (Header, 4);  --  four in streams
            Append_Seven_Zip_Number (Header, 1);  --  one out stream
            --  No bind pairs (out-1 = 0); list the four packed-stream indices.
            Append_Seven_Zip_Number (Header, 0);
            Append_Seven_Zip_Number (Header, 1);
            Append_Seven_Zip_Number (Header, 2);
            Append_Seven_Zip_Number (Header, 3);
            Header.Append (16#0C#); --  CodersUnPackSize
            Append_Seven_Zip_Number
              (Header, Interfaces.Unsigned_64 (Input'Length));
            Header.Append (16#00#); --  end UnPackInfo

            Header.Append (16#08#); --  SubStreamsInfo
            Header.Append (16#0A#); --  CRC
            Header.Append (1);
            Append_U32_LE (Header, Unpacked_CRC);
            Header.Append (16#00#); --  end SubStreamsInfo
            Header.Append (16#00#); --  end MainStreamsInfo

            Header.Append (16#05#); --  FilesInfo
            Append_Seven_Zip_Number (Header, 1);
            Header.Append (16#11#); --  Name
            Name_Field.Append (0);
            Append_UTF16LE_NT (Name_Field, Entry_Name);
            Append_Seven_Zip_Number
              (Header, Interfaces.Unsigned_64 (Name_Field.Length));
            Header.Append_Vector (Name_Field);
            Header.Append (16#00#);
            Header.Append (16#00#);

            declare
               Pack_Len : constant Natural :=
                 Main_B'Length + Call_B'Length + Jump_B'Length + RC_B'Length;
               Header_Image : constant Byte_Array := To_Byte_Array (Header);
               Header_CRC   : constant Interfaces.Unsigned_32 :=
                 Seven_Zip_Header_CRC (Header_Image);
               Start_Header : Byte_Vectors.Vector;
            begin
               Append_U64_LE
                 (Start_Header, Interfaces.Unsigned_64 (Pack_Len));
               Append_U64_LE
                 (Start_Header, Interfaces.Unsigned_64 (Header_Image'Length));
               Append_U32_LE (Start_Header, Header_CRC);
               declare
                  Start_Image : constant Byte_Array :=
                    To_Byte_Array (Start_Header);
                  Start_CRC   : constant Interfaces.Unsigned_32 :=
                    Seven_Zip_Header_CRC (Start_Image);
                  Archive     : Byte_Vectors.Vector;
               begin
                  Archive.Append (16#37#);
                  Archive.Append (16#7A#);
                  Archive.Append (16#BC#);
                  Archive.Append (16#AF#);
                  Archive.Append (16#27#);
                  Archive.Append (16#1C#);
                  Archive.Append (0);
                  Archive.Append (4);
                  Append_U32_LE (Archive, Start_CRC);
                  Archive.Append_Vector (Start_Header);
                  for B of Main_B loop
                     Archive.Append (B);
                  end loop;
                  for B of Call_B loop
                     Archive.Append (B);
                  end loop;
                  for B of Jump_B loop
                     Archive.Append (B);
                  end loop;
                  for B of RC_B loop
                     Archive.Append (B);
                  end loop;
                  Archive.Append_Vector (Header);
                  Status := Ok;
                  return To_Byte_Array (Archive);
               end;
            end;
         end;
      end;
   exception
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end Seven_Zip_BCJ2;

   procedure Append_Seven_Zip_File_Metadata
     (Header   : in out Byte_Vectors.Vector;
      Metadata : Seven_Zip_Entry_Metadata)
   is
   begin
      if Metadata.Has_Modification_Time then
         Header.Append (16#14#); --  MTime
         Append_Seven_Zip_Number (Header, 10);
         Header.Append (1); --  all entries defined
         Header.Append (0); --  inline values, not external
         Append_U64_LE (Header, Metadata.Modification_Time);
      end if;

      if Metadata.Has_Windows_Attributes then
         Header.Append (16#15#); --  WinAttributes
         Append_Seven_Zip_Number (Header, 5);
         Header.Append (1); --  all entries defined
         Append_U32_LE (Header, Metadata.Windows_Attributes);
      end if;
   end Append_Seven_Zip_File_Metadata;

   procedure Append_Seven_Zip_Files_Metadata
     (Header   : in out Byte_Vectors.Vector;
      Metadata : Seven_Zip_Metadata_Array)
   is
      All_Have_MTime      : Boolean := Metadata'Length > 0;
      All_Have_Attributes : Boolean := Metadata'Length > 0;
   begin
      for Item of Metadata loop
         All_Have_MTime :=
           All_Have_MTime and then Item.Has_Modification_Time;
         All_Have_Attributes :=
           All_Have_Attributes and then Item.Has_Windows_Attributes;
      end loop;

      if All_Have_MTime then
         Header.Append (16#14#); --  MTime
         Append_Seven_Zip_Number
           (Header, Interfaces.Unsigned_64 (2 + 8 * Metadata'Length));
         Header.Append (1); --  all entries defined
         Header.Append (0); --  inline values, not external
         for Item of Metadata loop
            Append_U64_LE (Header, Item.Modification_Time);
         end loop;
      end if;

      if All_Have_Attributes then
         Header.Append (16#15#); --  WinAttributes
         Append_Seven_Zip_Number
           (Header, Interfaces.Unsigned_64 (2 + 4 * Metadata'Length));
         Header.Append (1); --  all entries defined
         Header.Append (0); --  inline values, not external
         for Item of Metadata loop
            Append_U32_LE (Header, Item.Windows_Attributes);
         end loop;
      end if;
   end Append_Seven_Zip_Files_Metadata;

   function Seven_Zip_Stored_With_Metadata
     (Input      : Byte_Array;
      Entry_Name : String;
      Metadata   : Seven_Zip_Entry_Metadata;
      Status     : out Status_Code) return Byte_Array
   is
      Empty : constant Byte_Array (1 .. 0) := [others => 0];
   begin
      Status := Unsupported_Method;

      if not Seven_Zip_Entry_Name_Valid (Entry_Name)
      then
         return Empty;
      end if;

      if Metadata.Is_Directory then
         return Seven_Zip_Header_Only_Entry (Entry_Name, Metadata, Status);
      end if;

      declare
         Payload_CRC : constant Interfaces.Unsigned_32 := CRC32 (Input);
         Header      : Byte_Vectors.Vector;
         Name_Field  : Byte_Vectors.Vector;
      begin
         Header.Append (16#01#); --  Header

         Header.Append (16#04#); --  MainStreamsInfo
         Header.Append (16#06#); --  PackInfo
         Append_Seven_Zip_Number (Header, 0);
         Append_Seven_Zip_Number (Header, 1);
         Header.Append (16#09#); --  Size
         Append_Seven_Zip_Number (Header, Interfaces.Unsigned_64 (Input'Length));
         Header.Append (16#0A#); --  CRC
         Header.Append (1);
         Append_U32_LE (Header, Payload_CRC);
         Header.Append (0);

         Header.Append (16#07#); --  UnPackInfo
         Header.Append (16#0B#); --  Folder
         Append_Seven_Zip_Number (Header, 1);
         Header.Append (0);
         Append_Seven_Zip_Number (Header, 1);
         Header.Append (1);
         Header.Append (0); --  Copy coder
         Header.Append (16#0C#); --  CodersUnPackSize
         Append_Seven_Zip_Number (Header, Interfaces.Unsigned_64 (Input'Length));
         Header.Append (16#0A#); --  CRC
         Header.Append (1);
         Append_U32_LE (Header, Payload_CRC);
         Header.Append (0);
         Header.Append (0);

         Header.Append (16#05#); --  FilesInfo
         Append_Seven_Zip_Number (Header, 1);
         Header.Append (16#11#); --  Name
         Name_Field.Append (0);
         Append_UTF16LE_NT (Name_Field, Entry_Name);
         Append_Seven_Zip_Number
           (Header, Interfaces.Unsigned_64 (Name_Field.Length));
         Header.Append_Vector (Name_Field);
         Append_Seven_Zip_File_Metadata (Header, Metadata);
         Header.Append (0);
         Header.Append (0);

         declare
            Header_Image     : constant Byte_Array := To_Byte_Array (Header);
            Header_CRC       : constant Interfaces.Unsigned_32 :=
              Seven_Zip_Header_CRC (Header_Image);
            Start_Header     : Byte_Vectors.Vector;
         begin
            Append_U64_LE (Start_Header, Interfaces.Unsigned_64 (Input'Length));
            Append_U64_LE
              (Start_Header, Interfaces.Unsigned_64 (Header_Image'Length));
            Append_U32_LE (Start_Header, Header_CRC);

            declare
               Start_Header_Image : constant Byte_Array :=
                 To_Byte_Array (Start_Header);
               Start_CRC          : constant Interfaces.Unsigned_32 :=
                 Seven_Zip_Header_CRC (Start_Header_Image);
               Archive            : Byte_Vectors.Vector;
            begin
               Archive.Append (16#37#);
               Archive.Append (16#7A#);
               Archive.Append (16#BC#);
               Archive.Append (16#AF#);
               Archive.Append (16#27#);
               Archive.Append (16#1C#);
               Archive.Append (0);
               Archive.Append (4);
               Append_U32_LE (Archive, Start_CRC);
               Archive.Append_Vector (Start_Header);
               for B of Input loop
                  Archive.Append (B);
               end loop;
               Archive.Append_Vector (Header);

               Status := Ok;
               return To_Byte_Array (Archive);
            end;
         end;
      end;
   exception
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end Seven_Zip_Stored_With_Metadata;

   function Seven_Zip_Stored
     (Input      : Byte_Array;
      Entry_Name : String;
      Status     : out Status_Code) return Byte_Array
   is
   begin
      return
        Seven_Zip_Stored_With_Metadata
          (Input, Entry_Name, No_Seven_Zip_Entry_Metadata, Status);
   end Seven_Zip_Stored;

   function Seven_Zip_Stored
     (Input      : Byte_Array;
      Entry_Name : String;
      Metadata   : Seven_Zip_Entry_Metadata;
      Status     : out Status_Code) return Byte_Array
   is
   begin
      return Seven_Zip_Stored_With_Metadata (Input, Entry_Name, Metadata, Status);
   end Seven_Zip_Stored;

   function Seven_Zip_Deflate
     (Input      : Byte_Array;
      Entry_Name : String;
      Mode       : Compression_Mode;
      Status     : out Status_Code) return Byte_Array
   is
   begin
      return
        Seven_Zip_Deflate
          (Input, Entry_Name, Mode, No_Seven_Zip_Entry_Metadata, Status);
   end Seven_Zip_Deflate;

   function Seven_Zip_Deflate
     (Input      : Byte_Array;
      Entry_Name : String;
      Mode       : Compression_Mode;
      Metadata   : Seven_Zip_Entry_Metadata;
      Status     : out Status_Code) return Byte_Array
   is
      Empty           : constant Byte_Array (1 .. 0) := [others => 0];
      Compress_Status : Status_Code := Ok;
   begin
      Status := Unsupported_Method;
      if not Seven_Zip_Entry_Name_Valid (Entry_Name) then
         return Empty;
      end if;

      if Metadata.Is_Directory then
         return Seven_Zip_Header_Only_Entry (Entry_Name, Metadata, Status);
      end if;

      declare
         Packed_Data : constant Byte_Array :=
           Deflate_Raw (Input, Mode, Compress_Status);
      begin
         if Compress_Status /= Ok then
            Status := Compress_Status;
            return Empty;
         end if;

         return
           Seven_Zip_Single_File
             (Packed_Data, Input, Entry_Name, Seven_Zip_Deflate_Method,
              Metadata, Status);
      end;
   exception
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end Seven_Zip_Deflate;

   function Seven_Zip_Deflate
     (Input      : Byte_Array;
      Entry_Name : String;
      Level      : Compression_Level;
      Status     : out Status_Code) return Byte_Array
   is
   begin
      return
        Seven_Zip_Deflate
          (Input, Entry_Name, Level, No_Seven_Zip_Entry_Metadata, Status);
   end Seven_Zip_Deflate;

   function Seven_Zip_Deflate
     (Input      : Byte_Array;
      Entry_Name : String;
      Level      : Compression_Level;
      Metadata   : Seven_Zip_Entry_Metadata;
      Status     : out Status_Code) return Byte_Array
   is
      Empty           : constant Byte_Array (1 .. 0) := [others => 0];
      Compress_Status : Status_Code := Ok;
   begin
      Status := Unsupported_Method;
      if not Seven_Zip_Entry_Name_Valid (Entry_Name) then
         return Empty;
      end if;

      if Metadata.Is_Directory then
         return Seven_Zip_Header_Only_Entry (Entry_Name, Metadata, Status);
      end if;

      declare
         Packed_Data : constant Byte_Array :=
           Deflate_Raw (Input, Level, Compress_Status);
      begin
         if Compress_Status /= Ok then
            Status := Compress_Status;
            return Empty;
         end if;

         return
           Seven_Zip_Single_File
             (Packed_Data, Input, Entry_Name, Seven_Zip_Deflate_Method,
              Metadata, Status);
      end;
   exception
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end Seven_Zip_Deflate;

   function Seven_Zip_Deflate
     (Input      : Byte_Array;
      Entry_Name : String;
      Status     : out Status_Code) return Byte_Array is
   begin
      return Seven_Zip_Deflate (Input, Entry_Name, Auto, Status);
   end Seven_Zip_Deflate;

   function Seven_Zip_Deflate
     (Input      : Byte_Array;
      Entry_Name : String;
      Metadata   : Seven_Zip_Entry_Metadata;
      Status     : out Status_Code) return Byte_Array is
   begin
      return Seven_Zip_Deflate (Input, Entry_Name, Auto, Metadata, Status);
   end Seven_Zip_Deflate;

   function Seven_Zip_BZip2
     (Input      : Byte_Array;
      Entry_Name : String;
      Status     : out Status_Code) return Byte_Array
   is
   begin
      return
        Seven_Zip_BZip2
          (Input, Entry_Name, No_Seven_Zip_Entry_Metadata, Status);
   end Seven_Zip_BZip2;

   function Seven_Zip_BZip2
     (Input      : Byte_Array;
      Entry_Name : String;
      Metadata   : Seven_Zip_Entry_Metadata;
      Status     : out Status_Code) return Byte_Array
   is
      Compress_Status : Status_Code := Ok;
   begin
      Status := Unsupported_Method;
      if not Seven_Zip_Entry_Name_Valid (Entry_Name) then
         return [1 .. 0 => 0];
      end if;

      if Metadata.Is_Directory then
         return Seven_Zip_Header_Only_Entry (Entry_Name, Metadata, Status);
      end if;

      declare
         Packed_Data : constant Byte_Array :=
           BZip2_Compress (Input, Compress_Status);
      begin
         if Compress_Status /= Ok then
            Status := Compress_Status;
            return [1 .. 0 => 0];
         end if;

         return
           Seven_Zip_Single_File
             (Packed_Data, Input, Entry_Name, Seven_Zip_BZip2_Method,
              Metadata, Status);
      end;
   exception
      when others =>
         Status := Unsupported_Method;
         return [1 .. 0 => 0];
   end Seven_Zip_BZip2;

   function Seven_Zip_LZMA
     (Input      : Byte_Array;
      Entry_Name : String;
      Status     : out Status_Code) return Byte_Array
   is
   begin
      return
        Seven_Zip_LZMA
          (Input, Entry_Name, No_Seven_Zip_Entry_Metadata, Status);
   end Seven_Zip_LZMA;

   function Seven_Zip_LZMA
     (Input      : Byte_Array;
      Entry_Name : String;
      Metadata   : Seven_Zip_Entry_Metadata;
      Status     : out Status_Code) return Byte_Array
   is
   begin
      Status := Unsupported_Method;
      if not Seven_Zip_Entry_Name_Valid (Entry_Name) then
         return [1 .. 0 => 0];
      end if;

      if Metadata.Is_Directory then
         return Seven_Zip_Header_Only_Entry (Entry_Name, Metadata, Status);
      end if;

      declare
         Packed_Data : constant Byte_Array := LZMA_Encode_Bounded (Input);
      begin
         return
           Seven_Zip_Single_File
             (Packed_Data, Input, Entry_Name, Seven_Zip_LZMA_Method,
              Metadata, Status);
      end;
   exception
      when others =>
         Status := Unsupported_Method;
         return [1 .. 0 => 0];
   end Seven_Zip_LZMA;

   function Seven_Zip_LZMA2
     (Input      : Byte_Array;
      Entry_Name : String;
      Status     : out Status_Code) return Byte_Array
   is
   begin
      return
        Seven_Zip_LZMA2
          (Input, Entry_Name, No_Seven_Zip_Entry_Metadata, Status);
   end Seven_Zip_LZMA2;

   function Seven_Zip_LZMA2
     (Input      : Byte_Array;
      Entry_Name : String;
      Metadata   : Seven_Zip_Entry_Metadata;
      Status     : out Status_Code) return Byte_Array
   is
   begin
      Status := Unsupported_Method;
      if not Seven_Zip_Entry_Name_Valid (Entry_Name) then
         return [1 .. 0 => 0];
      end if;

      if Metadata.Is_Directory then
         return Seven_Zip_Header_Only_Entry (Entry_Name, Metadata, Status);
      end if;

      declare
         Packed_Data : constant Byte_Array := LZMA2_Encode (Input);
      begin
         return
           Seven_Zip_Single_File
             (Packed_Data, Input, Entry_Name, Seven_Zip_LZMA2_Method,
              Metadata, Status);
      end;
   exception
      when others =>
         Status := Unsupported_Method;
         return [1 .. 0 => 0];
   end Seven_Zip_LZMA2;


   function Seven_Zip_PPMd
     (Input      : Byte_Array;
      Entry_Name : String;
      Status     : out Status_Code) return Byte_Array
   is
   begin
      return
        Seven_Zip_PPMd
          (Input, Entry_Name, No_Seven_Zip_Entry_Metadata, Status);
   end Seven_Zip_PPMd;

   function Seven_Zip_PPMd
     (Input      : Byte_Array;
      Entry_Name : String;
      Metadata   : Seven_Zip_Entry_Metadata;
      Status     : out Status_Code) return Byte_Array
   is
   begin
      Status := Unsupported_Method;
      if not Seven_Zip_Entry_Name_Valid (Entry_Name) then
         return [1 .. 0 => 0];
      end if;

      if Metadata.Is_Directory then
         return Seven_Zip_Header_Only_Entry (Entry_Name, Metadata, Status);
      end if;

      declare
         Packed_Data : constant Byte_Array :=
           Zlib.PPMd7.Compress
             (Input, PPMd_Default_Order, PPMd_Default_Memory);
         Archive : constant Byte_Array :=
           Seven_Zip_Single_File
             (Packed_Data, Input, Entry_Name, Seven_Zip_PPMd_Method,
              Metadata, Status);
      begin
         if Status /= Ok then
            return [1 .. 0 => 0];
         end if;
         return Archive;
      end;
   exception
      when others =>
         Status := Unsupported_Method;
         return [1 .. 0 => 0];
   end Seven_Zip_PPMd;

   procedure Seven_Zip_Stored_File
     (Input_Path  : String;
      Output_Path : String;
      Entry_Name  : String;
      Status      : out Status_Code)
   is
      Read_Status  : Status_Code := Ok;
      Write_Status : Status_Code := Ok;
   begin
      Status := Unsupported_Method;
      if not Seven_Zip_Entry_Name_Valid (Entry_Name) then
         return;
      end if;
      if not Seven_Zip_Output_File_Writable (Output_Path) then
         Status := Output_File_Error;
         return;
      end if;
      if not Seven_Zip_Input_Path_Readable (Input_Path) then
         Status := Input_File_Error;
         return;
      end if;

      declare
         Metadata : constant Seven_Zip_Entry_Metadata :=
           Seven_Zip_Source_Metadata (Input_Path);
      begin
         if Metadata.Is_Directory then
            declare
               Empty_Input : constant Byte_Array := [1 .. 0 => 0];
               Archive     : constant Byte_Array :=
                 Seven_Zip_Stored (Empty_Input, Entry_Name, Metadata, Status);
            begin
               if Status /= Ok then
                  return;
               end if;

               Write_File (Output_Path, Archive, Write_Status);
               Status := Write_Status;
            end;

         else
            declare
               Input_Data : constant Byte_Array :=
                 Read_File (Input_Path, Read_Status);
            begin
               if Read_Status /= Ok then
                  Status := Read_Status;
                  return;
               end if;

               declare
                  Archive : constant Byte_Array :=
                    Seven_Zip_Stored (Input_Data, Entry_Name, Metadata, Status);
               begin
                  if Status /= Ok then
                     return;
                  end if;

                  Write_File (Output_Path, Archive, Write_Status);
                  Status := Write_Status;
               end;
            end;
         end if;
      end;
   exception
      when others =>
         Status := Output_File_Error;
   end Seven_Zip_Stored_File;

   procedure Seven_Zip_Deflate_File
     (Input_Path  : String;
      Output_Path : String;
      Entry_Name  : String;
      Mode        : Compression_Mode;
      Status      : out Status_Code)
   is
      Read_Status  : Status_Code := Ok;
      Write_Status : Status_Code := Ok;
   begin
      Status := Unsupported_Method;
      if not Seven_Zip_Entry_Name_Valid (Entry_Name) then
         return;
      end if;
      if not Seven_Zip_Output_File_Writable (Output_Path) then
         Status := Output_File_Error;
         return;
      end if;
      if not Seven_Zip_Input_Path_Readable (Input_Path) then
         Status := Input_File_Error;
         return;
      end if;

      declare
         Metadata : constant Seven_Zip_Entry_Metadata :=
           Seven_Zip_Source_Metadata (Input_Path);
      begin
         if Metadata.Is_Directory then
            declare
               Empty_Input : constant Byte_Array := [1 .. 0 => 0];
               Archive     : constant Byte_Array :=
                 Seven_Zip_Deflate
                   (Empty_Input, Entry_Name, Mode, Metadata, Status);
            begin
               if Status /= Ok then
                  return;
               end if;

               Write_File (Output_Path, Archive, Write_Status);
               Status := Write_Status;
            end;

         else
            declare
               Input_Data : constant Byte_Array :=
                 Read_File (Input_Path, Read_Status);
            begin
               if Read_Status /= Ok then
                  Status := Read_Status;
                  return;
               end if;

               declare
                  Archive : constant Byte_Array :=
                    Seven_Zip_Deflate
                      (Input_Data, Entry_Name, Mode, Metadata, Status);
               begin
                  if Status /= Ok then
                     return;
                  end if;

                  Write_File (Output_Path, Archive, Write_Status);
                  Status := Write_Status;
               end;
            end;
         end if;
      end;
   exception
      when others =>
         Status := Output_File_Error;
   end Seven_Zip_Deflate_File;

   procedure Seven_Zip_Deflate_File
     (Input_Path  : String;
      Output_Path : String;
      Entry_Name  : String;
      Level       : Compression_Level;
      Status      : out Status_Code)
   is
      Read_Status  : Status_Code := Ok;
      Write_Status : Status_Code := Ok;
   begin
      Status := Unsupported_Method;
      if not Seven_Zip_Entry_Name_Valid (Entry_Name) then
         return;
      end if;
      if not Seven_Zip_Output_File_Writable (Output_Path) then
         Status := Output_File_Error;
         return;
      end if;
      if not Seven_Zip_Input_Path_Readable (Input_Path) then
         Status := Input_File_Error;
         return;
      end if;

      declare
         Metadata : constant Seven_Zip_Entry_Metadata :=
           Seven_Zip_Source_Metadata (Input_Path);
      begin
         if Metadata.Is_Directory then
            declare
               Empty_Input : constant Byte_Array := [1 .. 0 => 0];
               Archive     : constant Byte_Array :=
                 Seven_Zip_Deflate
                   (Empty_Input, Entry_Name, Level, Metadata, Status);
            begin
               if Status /= Ok then
                  return;
               end if;

               Write_File (Output_Path, Archive, Write_Status);
               Status := Write_Status;
            end;

         else
            declare
               Input_Data : constant Byte_Array :=
                 Read_File (Input_Path, Read_Status);
            begin
               if Read_Status /= Ok then
                  Status := Read_Status;
                  return;
               end if;

               declare
                  Archive : constant Byte_Array :=
                    Seven_Zip_Deflate
                      (Input_Data, Entry_Name, Level, Metadata, Status);
               begin
                  if Status /= Ok then
                     return;
                  end if;

                  Write_File (Output_Path, Archive, Write_Status);
                  Status := Write_Status;
               end;
            end;
         end if;
      end;
   exception
      when others =>
         Status := Output_File_Error;
   end Seven_Zip_Deflate_File;

   procedure Seven_Zip_Deflate_File
     (Input_Path  : String;
      Output_Path : String;
      Entry_Name  : String;
      Status      : out Status_Code) is
   begin
      Seven_Zip_Deflate_File
        (Input_Path, Output_Path, Entry_Name, Auto, Status);
   end Seven_Zip_Deflate_File;

   procedure Seven_Zip_BZip2_File
     (Input_Path  : String;
      Output_Path : String;
      Entry_Name  : String;
      Status      : out Status_Code)
   is
      Read_Status  : Status_Code := Ok;
      Write_Status : Status_Code := Ok;
   begin
      Status := Unsupported_Method;
      if not Seven_Zip_Entry_Name_Valid (Entry_Name) then
         return;
      end if;
      if not Seven_Zip_Output_File_Writable (Output_Path) then
         Status := Output_File_Error;
         return;
      end if;
      if not Seven_Zip_Input_Path_Readable (Input_Path) then
         Status := Input_File_Error;
         return;
      end if;

      declare
         Metadata : constant Seven_Zip_Entry_Metadata :=
           Seven_Zip_Source_Metadata (Input_Path);
      begin
         if Metadata.Is_Directory then
            declare
               Empty_Input : constant Byte_Array := [1 .. 0 => 0];
               Archive     : constant Byte_Array :=
                 Seven_Zip_BZip2 (Empty_Input, Entry_Name, Metadata, Status);
            begin
               if Status /= Ok then
                  return;
               end if;

               Write_File (Output_Path, Archive, Write_Status);
               Status := Write_Status;
            end;

         else
            declare
               Input_Data : constant Byte_Array :=
                 Read_File (Input_Path, Read_Status);
            begin
               if Read_Status /= Ok then
                  Status := Read_Status;
                  return;
               end if;

               declare
                  Archive : constant Byte_Array :=
                    Seven_Zip_BZip2 (Input_Data, Entry_Name, Metadata, Status);
               begin
                  if Status /= Ok then
                     return;
                  end if;

                  Write_File (Output_Path, Archive, Write_Status);
                  Status := Write_Status;
               end;
            end;
         end if;
      end;
   exception
      when others =>
         Status := Output_File_Error;
   end Seven_Zip_BZip2_File;

   procedure Seven_Zip_LZMA_File
     (Input_Path  : String;
      Output_Path : String;
      Entry_Name  : String;
      Status      : out Status_Code)
   is
      Read_Status  : Status_Code := Ok;
      Write_Status : Status_Code := Ok;
   begin
      Status := Unsupported_Method;
      if not Seven_Zip_Entry_Name_Valid (Entry_Name) then
         return;
      end if;
      if not Seven_Zip_Output_File_Writable (Output_Path) then
         Status := Output_File_Error;
         return;
      end if;
      if not Seven_Zip_Input_Path_Readable (Input_Path) then
         Status := Input_File_Error;
         return;
      end if;

      declare
         Metadata : constant Seven_Zip_Entry_Metadata :=
           Seven_Zip_Source_Metadata (Input_Path);
      begin
         if Metadata.Is_Directory then
            declare
               Empty_Input : constant Byte_Array := [1 .. 0 => 0];
               Archive     : constant Byte_Array :=
                 Seven_Zip_LZMA (Empty_Input, Entry_Name, Metadata, Status);
            begin
               if Status /= Ok then
                  return;
               end if;

               Write_File (Output_Path, Archive, Write_Status);
               Status := Write_Status;
            end;

         else
            declare
               Input_Data : constant Byte_Array :=
                 Read_File (Input_Path, Read_Status);
            begin
               if Read_Status /= Ok then
                  Status := Read_Status;
                  return;
               end if;

               declare
                  Archive : constant Byte_Array :=
                    Seven_Zip_LZMA (Input_Data, Entry_Name, Metadata, Status);
               begin
                  if Status /= Ok then
                     return;
                  end if;

                  Write_File (Output_Path, Archive, Write_Status);
                  Status := Write_Status;
               end;
            end;
         end if;
      end;
   exception
      when others =>
         Status := Output_File_Error;
   end Seven_Zip_LZMA_File;

   procedure Seven_Zip_LZMA2_File
     (Input_Path  : String;
      Output_Path : String;
      Entry_Name  : String;
      Status      : out Status_Code)
   is
      Read_Status  : Status_Code := Ok;
      Write_Status : Status_Code := Ok;
   begin
      Status := Unsupported_Method;
      if not Seven_Zip_Entry_Name_Valid (Entry_Name) then
         return;
      end if;
      if not Seven_Zip_Output_File_Writable (Output_Path) then
         Status := Output_File_Error;
         return;
      end if;
      if not Seven_Zip_Input_Path_Readable (Input_Path) then
         Status := Input_File_Error;
         return;
      end if;

      declare
         Metadata : constant Seven_Zip_Entry_Metadata :=
           Seven_Zip_Source_Metadata (Input_Path);
      begin
         if Metadata.Is_Directory then
            declare
               Empty_Input : constant Byte_Array := [1 .. 0 => 0];
               Archive     : constant Byte_Array :=
                 Seven_Zip_LZMA2 (Empty_Input, Entry_Name, Metadata, Status);
            begin
               if Status /= Ok then
                  return;
               end if;

               Write_File (Output_Path, Archive, Write_Status);
               Status := Write_Status;
            end;

         else
            declare
               Input_Data : constant Byte_Array :=
                 Read_File (Input_Path, Read_Status);
            begin
               if Read_Status /= Ok then
                  Status := Read_Status;
                  return;
               end if;

               declare
                  Archive : constant Byte_Array :=
                    Seven_Zip_LZMA2 (Input_Data, Entry_Name, Metadata, Status);
               begin
                  if Status /= Ok then
                     return;
                  end if;

                  Write_File (Output_Path, Archive, Write_Status);
                  Status := Write_Status;
               end;
            end;
         end if;
      end;
   exception
      when others =>
         Status := Output_File_Error;
   end Seven_Zip_LZMA2_File;

   procedure Seven_Zip_Stored_Files
     (Input_Paths : Text_Array;
      Output_Path : String;
      Entry_Names : Text_Array;
      Status      : out Status_Code)
   is
      Count        : constant Natural := Input_Paths'Length;
      Payloads     : Byte_Vectors.Vector;
      Read_Status  : Status_Code := Ok;
      Write_Status : Status_Code := Ok;
   begin
      Status := Unsupported_Method;

      if Count = 0 or else Entry_Names'Length /= Count then
         return;
      end if;

      declare
         Sizes              : Seven_Zip_U64_Array (1 .. Count) := [others => 0];
         CRCs               : Seven_Zip_U32_Array (1 .. Count) := [others => 0];
         Metadata           : Seven_Zip_Metadata_Array (1 .. Count) :=
           [others => No_Seven_Zip_Entry_Metadata];
         Entry_Is_Directory : Seven_Zip_Boolean_Array (1 .. Count) :=
           [others => False];
         Empty_File_Bits    : constant Seven_Zip_Boolean_Array (1 .. Count) :=
           [others => False];
         Stream_Count       : Natural := 0;
      begin
         for Offset in 0 .. Count - 1 loop
            declare
               Entry_Name : constant String :=
                 US.To_String (Entry_Names (Entry_Names'First + Offset));
            begin
               if not Seven_Zip_Entry_Name_Valid (Entry_Name) then
                  return;
               end if;

               if Offset > 0 then
                  for Previous_Offset in 0 .. Offset - 1 loop
                     if Entry_Name =
                       US.To_String
                         (Entry_Names (Entry_Names'First + Previous_Offset))
                     then
                        return;
                     end if;
                  end loop;
               end if;
            end;
         end loop;

         if not Seven_Zip_Output_File_Writable (Output_Path) then
            Status := Output_File_Error;
            return;
         end if;

         if not Seven_Zip_Input_Paths_Readable (Input_Paths) then
            Status := Input_File_Error;
            return;
         end if;

         for Offset in 0 .. Count - 1 loop
            declare
               Input_Path : constant String :=
                 US.To_String (Input_Paths (Input_Paths'First + Offset));
            begin
               Metadata (Offset + 1) := Seven_Zip_Source_Metadata (Input_Path);
               Entry_Is_Directory (Offset + 1) :=
                 Metadata (Offset + 1).Is_Directory;
               if Entry_Is_Directory (Offset + 1) then
                  null;
               else
                  Stream_Count := Stream_Count + 1;
                  declare
                     Input_Data : constant Byte_Array :=
                       Read_File (Input_Path, Read_Status);
                  begin
                     if Read_Status /= Ok then
                        Status := Read_Status;
                        return;
                     end if;

                     Sizes (Stream_Count) :=
                       Interfaces.Unsigned_64 (Input_Data'Length);
                     CRCs (Stream_Count) := CRC32 (Input_Data);
                     for B of Input_Data loop
                        Payloads.Append (B);
                     end loop;
                  end;
               end if;
            end;
         end loop;

         declare
            Header     : Byte_Vectors.Vector;
            Name_Field : Byte_Vectors.Vector;
         begin
            Header.Append (16#01#); --  Header

            if Stream_Count > 0 then
               Header.Append (16#04#); --  MainStreamsInfo
               Header.Append (16#06#); --  PackInfo
               Append_Seven_Zip_Number (Header, 0);
               Append_Seven_Zip_Number (Header, 1);
               Header.Append (16#09#); --  Size
               Append_Seven_Zip_Number
                 (Header, Interfaces.Unsigned_64 (Payloads.Length));
               Header.Append (16#0A#); --  CRC
               Header.Append (1);
               Append_U32_LE (Header, CRC32 (To_Byte_Array (Payloads)));
               Header.Append (0);

               Header.Append (16#07#); --  UnPackInfo
               Header.Append (16#0B#); --  Folder
               Append_Seven_Zip_Number (Header, 1);
               Header.Append (0);
               Append_Seven_Zip_Number (Header, 1);
               Header.Append (1);
               Header.Append (0); --  Copy coder
               Header.Append (16#0C#); --  CodersUnPackSize
               Append_Seven_Zip_Number
                 (Header, Interfaces.Unsigned_64 (Payloads.Length));
               Header.Append (16#0A#); --  CRC
               Header.Append (1);
               Append_U32_LE (Header, CRC32 (To_Byte_Array (Payloads)));
               Header.Append (0);

               Header.Append (16#08#); --  SubStreamsInfo
               Header.Append (16#0D#); --  NumUnPackStream
               Append_Seven_Zip_Number
                 (Header, Interfaces.Unsigned_64 (Stream_Count));
               if Stream_Count > 1 then
                  Header.Append (16#09#); --  Size
                  for I in 1 .. Stream_Count - 1 loop
                     Append_Seven_Zip_Number (Header, Sizes (I));
                  end loop;
               end if;
               Header.Append (16#0A#); --  CRC
               Header.Append (1);
               for I in 1 .. Stream_Count loop
                  Append_U32_LE (Header, CRCs (I));
               end loop;
               Header.Append (0);
               Header.Append (0);
            end if;

            Header.Append (16#05#); --  FilesInfo
            Append_Seven_Zip_Number
              (Header, Interfaces.Unsigned_64 (Count));
            Header.Append (16#11#); --  Name
            Name_Field.Append (0);
            for Offset in 0 .. Count - 1 loop
               Append_UTF16LE_NT
                 (Name_Field,
                  US.To_String (Entry_Names (Entry_Names'First + Offset)));
            end loop;
            Append_Seven_Zip_Number
              (Header, Interfaces.Unsigned_64 (Name_Field.Length));
            Header.Append_Vector (Name_Field);
            if Stream_Count < Count then
               declare
                  Bits : Byte_Vectors.Vector;
               begin
                  Append_Seven_Zip_Bits (Bits, Entry_Is_Directory, Count);
                  Header.Append (16#0E#); --  EmptyStream
                  Append_Seven_Zip_Number
                    (Header, Interfaces.Unsigned_64 (Bits.Length));
                  Header.Append_Vector (Bits);
               end;

               declare
                  Bits : Byte_Vectors.Vector;
               begin
                  Append_Seven_Zip_Bits (Bits, Empty_File_Bits, Count - Stream_Count);
                  Header.Append (16#0F#); --  EmptyFile
                  Append_Seven_Zip_Number
                    (Header, Interfaces.Unsigned_64 (Bits.Length));
                  Header.Append_Vector (Bits);
               end;
            end if;
            Append_Seven_Zip_Files_Metadata (Header, Metadata);
            Header.Append (0);
            Header.Append (0);

            declare
               Header_Image : constant Byte_Array := To_Byte_Array (Header);
               Header_CRC   : constant Interfaces.Unsigned_32 :=
                 Seven_Zip_Header_CRC (Header_Image);
               Payload_Image : constant Byte_Array := To_Byte_Array (Payloads);
               Start_Header  : Byte_Vectors.Vector;
            begin
               Append_U64_LE
                 (Start_Header,
                  Interfaces.Unsigned_64 (Payload_Image'Length));
               Append_U64_LE
                 (Start_Header,
                  Interfaces.Unsigned_64 (Header_Image'Length));
               Append_U32_LE (Start_Header, Header_CRC);

               declare
                  Start_Header_Image : constant Byte_Array :=
                    To_Byte_Array (Start_Header);
                  Start_CRC          : constant Interfaces.Unsigned_32 :=
                    Seven_Zip_Header_CRC (Start_Header_Image);
                  Archive            : Byte_Vectors.Vector;
               begin
                  Archive.Append (16#37#);
                  Archive.Append (16#7A#);
                  Archive.Append (16#BC#);
                  Archive.Append (16#AF#);
                  Archive.Append (16#27#);
                  Archive.Append (16#1C#);
                  Archive.Append (0);
                  Archive.Append (4);
                  Append_U32_LE (Archive, Start_CRC);
                  Archive.Append_Vector (Start_Header);
                  Archive.Append_Vector (Payloads);
                  Archive.Append_Vector (Header);

                  Write_File (Output_Path, To_Byte_Array (Archive), Write_Status);
                  Status := Write_Status;
               end;
            end;
         end;
      end;
   exception
      when others =>
         Status := Output_File_Error;
   end Seven_Zip_Stored_Files;

   procedure Seven_Zip_Compressed_Files_Internal
     (Input_Paths : Text_Array;
      Output_Path : String;
      Entry_Names : Text_Array;
      Method      : Seven_Zip_Coder_Method;
      Mode        : Compression_Mode;
      Level       : Compression_Level;
      Use_Level   : Boolean;
      Solid       : Boolean;
      Password    : String;
      Status      : out Status_Code)
   is
      Count        : constant Natural := Input_Paths'Length;
      Payloads     : Byte_Vectors.Vector;
      Solid_Input  : Byte_Vectors.Vector;
      Read_Status  : Status_Code := Ok;
      Write_Status : Status_Code := Ok;
      Encrypt      : constant Boolean := Password /= "";
      Solid_Compressed_Len : Natural := 0;
      AES_IV       : Byte_Array (1 .. 16) := [others => 0];

      function Pack_Input
        (Input_Data : Byte_Array;
         Pack_Status : out Status_Code) return Byte_Array
      is
         Empty : constant Byte_Array (1 .. 0) := [others => 0];
      begin
         case Method is
            when Seven_Zip_Deflate_Method =>
               if Use_Level then
                  return Deflate_Raw (Input_Data, Level, Pack_Status);
               else
                  return Deflate_Raw (Input_Data, Mode, Pack_Status);
               end if;

            when Seven_Zip_BZip2_Method =>
               return BZip2_Compress (Input_Data, Pack_Status);

            when Seven_Zip_LZMA_Method =>
               Pack_Status := Ok;
               return LZMA_Encode_Bounded (Input_Data);

            when Seven_Zip_LZMA2_Method =>
               Pack_Status := Ok;
               return LZMA2_Encode (Input_Data);

            when Seven_Zip_PPMd_Method =>
               Pack_Status := Ok;
               return Zlib.PPMd7.Compress
                 (Input_Data, PPMd_Default_Order, PPMd_Default_Memory);

            when others =>
               Pack_Status := Unsupported_Method;
               return Empty;
         end case;
      end Pack_Input;
   begin
      Status := Unsupported_Method;

      if Count = 0 or else Entry_Names'Length /= Count then
         return;
      end if;

      declare
         Pack_Sizes         : Seven_Zip_U64_Array (1 .. Count) := [others => 0];
         Pack_CRCs          : Seven_Zip_U32_Array (1 .. Count) := [others => 0];
         Unpack_Sizes       : Seven_Zip_U64_Array (1 .. Count) := [others => 0];
         Unpack_CRCs        : Seven_Zip_U32_Array (1 .. Count) := [others => 0];
         Metadata           : Seven_Zip_Metadata_Array (1 .. Count) :=
           [others => No_Seven_Zip_Entry_Metadata];
         Entry_Is_Directory : Seven_Zip_Boolean_Array (1 .. Count) :=
           [others => False];
         Empty_File_Bits    : constant Seven_Zip_Boolean_Array (1 .. Count) :=
           [others => False];
         Stream_Count       : Natural := 0;
      begin
         for Offset in 0 .. Count - 1 loop
            declare
               Entry_Name : constant String :=
                 US.To_String (Entry_Names (Entry_Names'First + Offset));
            begin
               if not Seven_Zip_Entry_Name_Valid (Entry_Name) then
                  return;
               end if;

               if Offset > 0 then
                  for Previous_Offset in 0 .. Offset - 1 loop
                     if Entry_Name =
                       US.To_String
                         (Entry_Names (Entry_Names'First + Previous_Offset))
                     then
                        return;
                     end if;
                  end loop;
               end if;
            end;
         end loop;

         if not Seven_Zip_Output_File_Writable (Output_Path) then
            Status := Output_File_Error;
            return;
         end if;

         if not Seven_Zip_Input_Paths_Readable (Input_Paths) then
            Status := Input_File_Error;
            return;
         end if;

         for Offset in 0 .. Count - 1 loop
            declare
               Input_Path : constant String :=
                 US.To_String (Input_Paths (Input_Paths'First + Offset));
            begin
               Metadata (Offset + 1) := Seven_Zip_Source_Metadata (Input_Path);
               Entry_Is_Directory (Offset + 1) :=
                 Metadata (Offset + 1).Is_Directory;
               if Entry_Is_Directory (Offset + 1) then
                  null;
               else
                  Stream_Count := Stream_Count + 1;
                  declare
                     Input_Data : constant Byte_Array :=
                       Read_File (Input_Path, Read_Status);
                  begin
                     if Read_Status /= Ok then
                        Status := Read_Status;
                        return;
                     end if;

                     Unpack_Sizes (Stream_Count) :=
                       Interfaces.Unsigned_64 (Input_Data'Length);
                     Unpack_CRCs (Stream_Count) := CRC32 (Input_Data);

                     if Solid then
                        --  Defer compression: concatenate into one stream.
                        for B of Input_Data loop
                           Solid_Input.Append (B);
                        end loop;
                     else
                        declare
                           Compress_Status : Status_Code := Ok;
                           Packed_Data     : constant Byte_Array :=
                             Pack_Input (Input_Data, Compress_Status);
                        begin
                           if Compress_Status /= Ok then
                              Status := Compress_Status;
                              return;
                           end if;

                           Pack_Sizes (Stream_Count) :=
                             Interfaces.Unsigned_64 (Packed_Data'Length);
                           Pack_CRCs (Stream_Count) := CRC32 (Packed_Data);

                           for B of Packed_Data loop
                              Payloads.Append (B);
                           end loop;
                        end;
                     end if;
                  end;
               end if;
            end;
         end loop;

         if Solid and then Stream_Count > 0 then
            declare
               Solid_Data      : constant Byte_Array :=
                 To_Byte_Array (Solid_Input);
               Compress_Status : Status_Code := Ok;
               Packed_Data     : constant Byte_Array :=
                 Pack_Input (Solid_Data, Compress_Status);
            begin
               if Compress_Status /= Ok then
                  Status := Compress_Status;
                  return;
               end if;
               Solid_Compressed_Len := Packed_Data'Length;
               if Encrypt then
                  AES_IV := Zlib.Seven_Zip_AES.Random_IV;
                  declare
                     Pack : constant Byte_Array :=
                       Zlib.Seven_Zip_AES.Encrypt_CBC
                         (Zlib.Seven_Zip_AES.Derive_Key
                            (Password, [1 .. 0 => 0], 19),
                          AES_IV,
                          Zlib.Seven_Zip_AES.Pad_To_Block (Packed_Data));
                  begin
                     Pack_Sizes (1) := Interfaces.Unsigned_64 (Pack'Length);
                     for B of Pack loop
                        Payloads.Append (B);
                     end loop;
                  end;
               else
                  Pack_Sizes (1) :=
                    Interfaces.Unsigned_64 (Packed_Data'Length);
                  for B of Packed_Data loop
                     Payloads.Append (B);
                  end loop;
               end if;
            end;
         end if;

         declare
            Header     : Byte_Vectors.Vector;
            Name_Field : Byte_Vectors.Vector;
            Total_Unpack_Size : Interfaces.Unsigned_64 := 0;
         begin
            for I in 1 .. Stream_Count loop
               Total_Unpack_Size := Total_Unpack_Size + Unpack_Sizes (I);
            end loop;

            Header.Append (16#01#); --  Header

            if Stream_Count > 0 and then Solid then
               Header.Append (16#04#); --  MainStreamsInfo
               Header.Append (16#06#); --  PackInfo
               Append_Seven_Zip_Number (Header, 0);
               Append_Seven_Zip_Number (Header, 1);
               Header.Append (16#09#); --  Size
               Append_Seven_Zip_Number (Header, Pack_Sizes (1));
               Header.Append (0);      --  end PackInfo

               Header.Append (16#07#); --  UnPackInfo
               Header.Append (16#0B#); --  Folder
               Append_Seven_Zip_Number (Header, 1);  --  one folder
               Header.Append (0);                    --  external
               if Encrypt then
                  Append_Seven_Zip_Number (Header, 2);  --  AES + inner coder
                  Header.Append (16#24#);
                  Header.Append (16#06#);
                  Header.Append (16#F1#);
                  Header.Append (16#07#);
                  Header.Append (16#01#);
                  Append_Seven_Zip_Number (Header, 18);
                  Header.Append (16#53#);
                  Header.Append (16#0F#);
                  for B of AES_IV loop
                     Header.Append (B);
                  end loop;
                  Append_Seven_Zip_Coder (Header, Method);
                  Append_Seven_Zip_Number (Header, 1);  --  bind In=1 (inner.in)
                  Append_Seven_Zip_Number (Header, 0);  --  bind Out=0 (AES.out)
                  Header.Append (16#0C#); --  CodersUnPackSize
                  Append_Seven_Zip_Number
                    (Header, Interfaces.Unsigned_64 (Solid_Compressed_Len));
                  Append_Seven_Zip_Number (Header, Total_Unpack_Size);
               else
                  Append_Seven_Zip_Number (Header, 1);  --  one coder
                  Append_Seven_Zip_Coder (Header, Method);
                  Header.Append (16#0C#); --  CodersUnPackSize
                  Append_Seven_Zip_Number (Header, Total_Unpack_Size);
               end if;
               Header.Append (0);      --  end UnPackInfo (no folder CRC)

               Header.Append (16#08#); --  SubStreamsInfo
               Header.Append (16#0D#); --  NumUnPackStream
               Append_Seven_Zip_Number
                 (Header, Interfaces.Unsigned_64 (Stream_Count));
               if Stream_Count > 1 then
                  Header.Append (16#09#); --  Size (all but last substream)
                  for I in 1 .. Stream_Count - 1 loop
                     Append_Seven_Zip_Number (Header, Unpack_Sizes (I));
                  end loop;
               end if;
               Header.Append (16#0A#); --  CRC
               Header.Append (1);
               for I in 1 .. Stream_Count loop
                  Append_U32_LE (Header, Unpack_CRCs (I));
               end loop;
               Header.Append (0);      --  end SubStreamsInfo
               Header.Append (0);      --  end MainStreamsInfo
            elsif Stream_Count > 0 then
               Header.Append (16#04#); --  MainStreamsInfo
               Header.Append (16#06#); --  PackInfo
               Append_Seven_Zip_Number (Header, 0);
               Append_Seven_Zip_Number
                 (Header, Interfaces.Unsigned_64 (Stream_Count));
               Header.Append (16#09#); --  Size
               for I in 1 .. Stream_Count loop
                  Append_Seven_Zip_Number (Header, Pack_Sizes (I));
               end loop;
               Header.Append (16#0A#); --  CRC
               Header.Append (1);
               for I in 1 .. Stream_Count loop
                  Append_U32_LE (Header, Pack_CRCs (I));
               end loop;
               Header.Append (0);

               Header.Append (16#07#); --  UnPackInfo
               Header.Append (16#0B#); --  Folder
               Append_Seven_Zip_Number
                 (Header, Interfaces.Unsigned_64 (Stream_Count));
               Header.Append (0);
               for I in 1 .. Stream_Count loop
                  Append_Seven_Zip_Number (Header, 1);
                  Append_Seven_Zip_Coder (Header, Method);
               end loop;
               Header.Append (16#0C#); --  CodersUnPackSize
               for I in 1 .. Stream_Count loop
                  Append_Seven_Zip_Number (Header, Unpack_Sizes (I));
               end loop;
               Header.Append (16#0A#); --  CRC
               Header.Append (1);
               for I in 1 .. Stream_Count loop
                  Append_U32_LE (Header, Unpack_CRCs (I));
               end loop;
               Header.Append (0);
               Header.Append (0);
            end if;

            Header.Append (16#05#); --  FilesInfo
            Append_Seven_Zip_Number
              (Header, Interfaces.Unsigned_64 (Count));
            Header.Append (16#11#); --  Name
            Name_Field.Append (0);
            for Offset in 0 .. Count - 1 loop
               Append_UTF16LE_NT
                 (Name_Field,
                  US.To_String (Entry_Names (Entry_Names'First + Offset)));
            end loop;
            Append_Seven_Zip_Number
              (Header, Interfaces.Unsigned_64 (Name_Field.Length));
            Header.Append_Vector (Name_Field);
            if Stream_Count < Count then
               declare
                  Bits : Byte_Vectors.Vector;
               begin
                  Append_Seven_Zip_Bits (Bits, Entry_Is_Directory, Count);
                  Header.Append (16#0E#); --  EmptyStream
                  Append_Seven_Zip_Number
                    (Header, Interfaces.Unsigned_64 (Bits.Length));
                  Header.Append_Vector (Bits);
               end;

               declare
                  Bits : Byte_Vectors.Vector;
               begin
                  Append_Seven_Zip_Bits (Bits, Empty_File_Bits, Count - Stream_Count);
                  Header.Append (16#0F#); --  EmptyFile
                  Append_Seven_Zip_Number
                    (Header, Interfaces.Unsigned_64 (Bits.Length));
                  Header.Append_Vector (Bits);
               end;
            end if;
            Append_Seven_Zip_Files_Metadata (Header, Metadata);
            Header.Append (0);
            Header.Append (0);

            declare
               Header_Image  : constant Byte_Array := To_Byte_Array (Header);
               Header_CRC    : constant Interfaces.Unsigned_32 :=
                 Seven_Zip_Header_CRC (Header_Image);
               Payload_Image : constant Byte_Array := To_Byte_Array (Payloads);
               Start_Header  : Byte_Vectors.Vector;
            begin
               Append_U64_LE
                 (Start_Header,
                  Interfaces.Unsigned_64 (Payload_Image'Length));
               Append_U64_LE
                 (Start_Header,
                  Interfaces.Unsigned_64 (Header_Image'Length));
               Append_U32_LE (Start_Header, Header_CRC);

               declare
                  Start_Header_Image : constant Byte_Array :=
                    To_Byte_Array (Start_Header);
                  Start_CRC          : constant Interfaces.Unsigned_32 :=
                    Seven_Zip_Header_CRC (Start_Header_Image);
                  Archive            : Byte_Vectors.Vector;
               begin
                  Archive.Append (16#37#);
                  Archive.Append (16#7A#);
                  Archive.Append (16#BC#);
                  Archive.Append (16#AF#);
                  Archive.Append (16#27#);
                  Archive.Append (16#1C#);
                  Archive.Append (0);
                  Archive.Append (4);
                  Append_U32_LE (Archive, Start_CRC);
                  Archive.Append_Vector (Start_Header);
                  Archive.Append_Vector (Payloads);
                  Archive.Append_Vector (Header);

                  Write_File (Output_Path, To_Byte_Array (Archive), Write_Status);
                  Status := Write_Status;
               end;
            end;
         end;
      end;
   exception
      when others =>
         Status := Output_File_Error;
   end Seven_Zip_Compressed_Files_Internal;

   procedure Seven_Zip_Deflate_Files
     (Input_Paths : Text_Array;
      Output_Path : String;
      Entry_Names : Text_Array;
      Mode        : Compression_Mode;
      Status      : out Status_Code) is
   begin
      Seven_Zip_Compressed_Files_Internal
        (Input_Paths, Output_Path, Entry_Names, Seven_Zip_Deflate_Method,
         Mode, Default_Level, False, False, "", Status);
   end Seven_Zip_Deflate_Files;

   procedure Seven_Zip_Deflate_Files
     (Input_Paths : Text_Array;
      Output_Path : String;
      Entry_Names : Text_Array;
      Level       : Compression_Level;
      Status      : out Status_Code) is
   begin
      Seven_Zip_Compressed_Files_Internal
        (Input_Paths, Output_Path, Entry_Names, Seven_Zip_Deflate_Method,
         Auto, Level, True, False, "", Status);
   end Seven_Zip_Deflate_Files;

   procedure Seven_Zip_Deflate_Files
     (Input_Paths : Text_Array;
      Output_Path : String;
      Entry_Names : Text_Array;
      Status      : out Status_Code) is
   begin
      Seven_Zip_Deflate_Files
        (Input_Paths, Output_Path, Entry_Names, Auto, Status);
   end Seven_Zip_Deflate_Files;

   procedure Seven_Zip_BZip2_Files
     (Input_Paths : Text_Array;
      Output_Path : String;
      Entry_Names : Text_Array;
      Status      : out Status_Code) is
   begin
      Seven_Zip_Compressed_Files_Internal
        (Input_Paths, Output_Path, Entry_Names, Seven_Zip_BZip2_Method,
         Auto, Default_Level, False, False, "", Status);
   end Seven_Zip_BZip2_Files;

   procedure Seven_Zip_LZMA_Files
     (Input_Paths : Text_Array;
      Output_Path : String;
      Entry_Names : Text_Array;
      Status      : out Status_Code) is
   begin
      Seven_Zip_Compressed_Files_Internal
        (Input_Paths, Output_Path, Entry_Names, Seven_Zip_LZMA_Method,
         Auto, Default_Level, False, False, "", Status);
   end Seven_Zip_LZMA_Files;

   procedure Seven_Zip_LZMA2_Files
     (Input_Paths : Text_Array;
      Output_Path : String;
      Entry_Names : Text_Array;
      Status      : out Status_Code) is
   begin
      Seven_Zip_Compressed_Files_Internal
        (Input_Paths, Output_Path, Entry_Names, Seven_Zip_LZMA2_Method,
         Auto, Default_Level, False, False, "", Status);
   end Seven_Zip_LZMA2_Files;

   procedure Seven_Zip_PPMd_Files
     (Input_Paths : Text_Array;
      Output_Path : String;
      Entry_Names : Text_Array;
      Status      : out Status_Code) is
   begin
      Seven_Zip_Compressed_Files_Internal
        (Input_Paths, Output_Path, Entry_Names, Seven_Zip_PPMd_Method,
         Auto, Default_Level, False, False, "", Status);
   end Seven_Zip_PPMd_Files;

   procedure Seven_Zip_LZMA_Solid_Files
     (Input_Paths : Text_Array;
      Output_Path : String;
      Entry_Names : Text_Array;
      Status      : out Status_Code) is
   begin
      Seven_Zip_Compressed_Files_Internal
        (Input_Paths, Output_Path, Entry_Names, Seven_Zip_LZMA_Method,
         Auto, Default_Level, False, True, "", Status);
   end Seven_Zip_LZMA_Solid_Files;

   procedure Seven_Zip_LZMA2_Solid_Files
     (Input_Paths : Text_Array;
      Output_Path : String;
      Entry_Names : Text_Array;
      Status      : out Status_Code) is
   begin
      Seven_Zip_Compressed_Files_Internal
        (Input_Paths, Output_Path, Entry_Names, Seven_Zip_LZMA2_Method,
         Auto, Default_Level, False, True, "", Status);
   end Seven_Zip_LZMA2_Solid_Files;

   procedure Seven_Zip_PPMd_Solid_Files
     (Input_Paths : Text_Array;
      Output_Path : String;
      Entry_Names : Text_Array;
      Status      : out Status_Code) is
   begin
      Seven_Zip_Compressed_Files_Internal
        (Input_Paths, Output_Path, Entry_Names, Seven_Zip_PPMd_Method,
         Auto, Default_Level, False, True, "", Status);
   end Seven_Zip_PPMd_Solid_Files;

   procedure Seven_Zip_LZMA_Encrypted_Files
     (Input_Paths : Text_Array;
      Output_Path : String;
      Entry_Names : Text_Array;
      Password    : String;
      Status      : out Status_Code) is
   begin
      Seven_Zip_Compressed_Files_Internal
        (Input_Paths, Output_Path, Entry_Names, Seven_Zip_LZMA_Method,
         Auto, Default_Level, False, True, Password, Status);
   end Seven_Zip_LZMA_Encrypted_Files;

   procedure Seven_Zip_LZMA2_Encrypted_Files
     (Input_Paths : Text_Array;
      Output_Path : String;
      Entry_Names : Text_Array;
      Password    : String;
      Status      : out Status_Code) is
   begin
      Seven_Zip_Compressed_Files_Internal
        (Input_Paths, Output_Path, Entry_Names, Seven_Zip_LZMA2_Method,
         Auto, Default_Level, False, True, Password, Status);
   end Seven_Zip_LZMA2_Encrypted_Files;

   procedure Seven_Zip_PPMd_Encrypted_Files
     (Input_Paths : Text_Array;
      Output_Path : String;
      Entry_Names : Text_Array;
      Password    : String;
      Status      : out Status_Code) is
   begin
      Seven_Zip_Compressed_Files_Internal
        (Input_Paths, Output_Path, Entry_Names, Seven_Zip_PPMd_Method,
         Auto, Default_Level, False, True, Password, Status);
   end Seven_Zip_PPMd_Encrypted_Files;

   function Extract_Seven_Zip_Entry
     (Archive_Image : Byte_Array;
      Entry_Name    : String;
      Status        : out Status_Code;
      Kind          : out Seven_Zip_Entry_Kind;
      Metadata      : out Seven_Zip_Entry_Metadata) return Byte_Array
   is
      Empty : constant Byte_Array (1 .. 0) := [others => 0];
   begin
      Status := Unsupported_Method;
      Kind := Seven_Zip_File_Entry;
      Metadata := No_Seven_Zip_Entry_Metadata;

      if not Seven_Zip_Entry_Name_Valid (Entry_Name)
        or else Archive_Image'Length < 33
      then
         return Empty;
      end if;

      declare
         F : Natural := 0;
      begin
         if not Seven_Zip_Find_Signature (Archive_Image, F)
           or else Archive_Image'Last - F + 1 < 33
         then
            return Empty;
         end if;

         declare
            Start_First : constant Natural := F + 12;
            Start_Last  : constant Natural := F + 31;
            Start       : constant Byte_Array := Archive_Image (Start_First .. Start_Last);
            Start_CRC   : constant Interfaces.Unsigned_32 :=
              Seven_Zip_U32_At (Archive_Image, F + 8);
            Offset      : constant Interfaces.Unsigned_64 :=
              Seven_Zip_U64_At (Archive_Image, F + 12);
            Header_Size : constant Interfaces.Unsigned_64 :=
              Seven_Zip_U64_At (Archive_Image, F + 20);
            Header_CRC  : constant Interfaces.Unsigned_32 :=
              Seven_Zip_U32_At (Archive_Image, F + 28);
         begin
            if Start_CRC /= CRC32 (Start) then
               Status := Invalid_Checksum;
               return Empty;
            end if;

            declare
               Payload_First : constant Natural := F + 32;
            begin
               if Offset > Interfaces.Unsigned_64 (Natural'Last)
                 or else Header_Size > Interfaces.Unsigned_64 (Natural'Last)
                 or else Offset >
                   Interfaces.Unsigned_64 (Natural'Last - Payload_First)
               then
                  Status := Unsupported_Method;
                  return Empty;
               end if;
            end;

            declare
               Payload_Count : constant Natural := Natural (Offset);
               Header_Count  : constant Natural := Natural (Header_Size);
               Payload_First : constant Natural := F + 32;
               Header_First  : constant Natural := Payload_First + Payload_Count;
            begin
               if Header_Count = 0
                 or else Header_First > Archive_Image'Last
                 or else Header_Count > Natural'Last - Header_First + 1
               then
                  Status := Unexpected_End_Of_Input;
                  return Empty;
               end if;

               declare
                  Header_Last : constant Natural := Header_First + Header_Count - 1;
                  Pos    : Natural := Header_First;
                  Value  : Interfaces.Unsigned_64 := 0;
                  B      : Byte := 0;
               begin
                  if Header_Last > Archive_Image'Last then
                     Status := Unexpected_End_Of_Input;
                     return Empty;
                  end if;

                  if Header_Last /= Archive_Image'Last then
                     Status := Unsupported_Method;
                     return Empty;
                  end if;

                  if Header_CRC /=
                    CRC32 (Archive_Image (Header_First .. Header_Last))
                  then
                     Status := Invalid_Checksum;
                     return Empty;
                  end if;

                  if Archive_Image (Header_First) = 16#17# then
                     declare
                        Encoded_Header_Pack_Pos : Natural := 0;

                        --  Decode a 2-coder [AES -> LZMA] encoded header (7z
                        --  "mhe=on"): parse the AES + LZMA coders, AES-decrypt
                        --  the pack with the active password, then LZMA-decode
                        --  to the real (plain) header bytes.
                        function Decode_AES_Encoded_Header
                          (Decode_Status : out Status_Code) return Byte_Array
                        is
                           P         : Natural := Header_First;
                           V         : Interfaces.Unsigned_64 := 0;
                           B         : Byte := 0;
                           Pack_Pos  : Interfaces.Unsigned_64 := 0;
                           Pack_Size : Interfaces.Unsigned_64 := 0;
                           HC_Size   : Interfaces.Unsigned_64 := 0;
                           Hdr_Size  : Interfaces.Unsigned_64 := 0;
                           Cycles    : Natural := 0;
                           Salt_Len  : Natural := 0;
                           IV_Len    : Natural := 0;
                           Salt      : Byte_Array (1 .. 16) := [others => 0];
                           IV        : Byte_Array (1 .. 16) := [others => 0];
                           LZMA_P    : Seven_Zip_LZMA_Props := [others => 0];
                           Num_Coders : Natural := 0;
                        begin
                           Decode_Status := Unsupported_Method;
                           if not Seven_Zip_Expect_Byte
                             (Archive_Image, P, Header_Last, 16#17#)
                           then
                              return Empty;
                           end if;
                           if P <= Header_Last
                             and then Archive_Image (P) = 16#04#
                           then
                              P := P + 1;
                           end if;
                           --  PackInfo
                           if not Seven_Zip_Expect_Byte
                                (Archive_Image, P, Header_Last, 16#06#)
                             or else not Read_Seven_Zip_Number
                               (Archive_Image, P, Header_Last, Pack_Pos)
                             or else not Read_Seven_Zip_Number
                               (Archive_Image, P, Header_Last, V)
                             or else V /= 1
                             or else not Seven_Zip_Expect_Byte
                               (Archive_Image, P, Header_Last, 16#09#)
                             or else not Read_Seven_Zip_Number
                               (Archive_Image, P, Header_Last, Pack_Size)
                           then
                              return Empty;
                           end if;
                           if P <= Header_Last
                             and then Archive_Image (P) = 16#0A#
                           then
                              P := P + 1;
                              if not Seven_Zip_Expect_Byte
                                   (Archive_Image, P, Header_Last, 1)
                                or else not Seven_Zip_Has_Bytes
                                  (P, Header_Last, 4)
                              then
                                 return Empty;
                              end if;
                              P := P + 4;
                           end if;
                           --  end PackInfo, UnpackInfo, Folder, 2 coders
                           if not Seven_Zip_Expect_Byte
                                (Archive_Image, P, Header_Last, 0)
                             or else not Seven_Zip_Expect_Byte
                               (Archive_Image, P, Header_Last, 16#07#)
                             or else not Seven_Zip_Expect_Byte
                               (Archive_Image, P, Header_Last, 16#0B#)
                             or else not Read_Seven_Zip_Number
                               (Archive_Image, P, Header_Last, V)
                             or else V /= 1
                             or else not Seven_Zip_Expect_Byte
                               (Archive_Image, P, Header_Last, 0)
                             or else not Read_Seven_Zip_Number
                               (Archive_Image, P, Header_Last, V)
                             or else V not in 1 | 2
                           then
                              return Empty;
                           end if;
                           Num_Coders := Natural (V);
                           --  Coder 0: AES (id 06 F1 07 01, has props)
                           if not Seven_Zip_Read_Byte
                                (Archive_Image, P, Header_Last, B)
                             or else (B and 16#0F#) /= 4
                             or else (B and 16#20#) = 0
                             or else not Seven_Zip_Expect_Byte
                               (Archive_Image, P, Header_Last, 16#06#)
                             or else not Seven_Zip_Expect_Byte
                               (Archive_Image, P, Header_Last, 16#F1#)
                             or else not Seven_Zip_Expect_Byte
                               (Archive_Image, P, Header_Last, 16#07#)
                             or else not Seven_Zip_Expect_Byte
                               (Archive_Image, P, Header_Last, 16#01#)
                           then
                              return Empty;
                           end if;
                           declare
                              Prop_Size : Interfaces.Unsigned_64 := 0;
                           begin
                              if not Read_Seven_Zip_Number
                                   (Archive_Image, P, Header_Last, Prop_Size)
                                or else Prop_Size < 1
                                or else not Seven_Zip_Has_Bytes
                                  (P, Header_Last, Natural (Prop_Size))
                              then
                                 return Empty;
                              end if;
                              declare
                                 PB : Byte_Array (1 .. Natural (Prop_Size));
                                 B0, B1, PP : Natural := 0;
                              begin
                                 for J in PB'Range loop
                                    PB (J) := Archive_Image (P);
                                    P := P + 1;
                                 end loop;
                                 B0 := Natural (PB (1));
                                 Cycles := B0 mod 64;
                                 if (B0 / 64) /= 0
                                   and then Natural (Prop_Size) >= 2
                                 then
                                    B1 := Natural (PB (2));
                                    PP := 3;
                                 else
                                    PP := 2;
                                 end if;
                                 Salt_Len := ((B0 / 128) mod 2) + (B1 / 16);
                                 IV_Len := ((B0 / 64) mod 2) + (B1 mod 16);
                                 if Salt_Len > 16 or else IV_Len > 16
                                   or else Natural (Prop_Size) <
                                     (PP - 1) + Salt_Len + IV_Len
                                 then
                                    return Empty;
                                 end if;
                                 for J in 1 .. Salt_Len loop
                                    Salt (J) := PB (PP + J - 1);
                                 end loop;
                                 for J in 1 .. IV_Len loop
                                    IV (J) := PB (PP + Salt_Len + J - 1);
                                 end loop;
                              end;
                           end;
                           --  Coder 1: LZMA (only present when 2 coders; a
                           --  small header is AES-only, NumCoders = 1).
                           if Num_Coders = 2 then
                              if not Seven_Zip_Expect_Byte
                                   (Archive_Image, P, Header_Last, 16#23#)
                                or else not Seven_Zip_Expect_Byte
                                  (Archive_Image, P, Header_Last, 16#03#)
                                or else not Seven_Zip_Expect_Byte
                                  (Archive_Image, P, Header_Last, 16#01#)
                                or else not Seven_Zip_Expect_Byte
                                  (Archive_Image, P, Header_Last, 16#01#)
                                or else not Seven_Zip_Expect_Byte
                                  (Archive_Image, P, Header_Last, 5)
                              then
                                 return Empty;
                              end if;
                              for J in LZMA_P'Range loop
                                 if not Seven_Zip_Read_Byte
                                   (Archive_Image, P, Header_Last, LZMA_P (J))
                                 then
                                    return Empty;
                                 end if;
                              end loop;
                              if not Valid_LZMA_Props (LZMA_P (1)) then
                                 return Empty;
                              end if;
                              --  bind pair In=1 (LZMA.in) Out=0 (AES.out)
                              if not Read_Seven_Zip_Number
                                   (Archive_Image, P, Header_Last, V)
                                or else V /= 1
                                or else not Read_Seven_Zip_Number
                                  (Archive_Image, P, Header_Last, V)
                                or else V /= 0
                              then
                                 return Empty;
                              end if;
                           end if;
                           --  CodersUnPackSize: AES.out (=HC); LZMA.out (=hdr)
                           --  for 2 coders.
                           if not Seven_Zip_Expect_Byte
                                (Archive_Image, P, Header_Last, 16#0C#)
                             or else not Read_Seven_Zip_Number
                               (Archive_Image, P, Header_Last, HC_Size)
                           then
                              return Empty;
                           end if;
                           if Num_Coders = 2 then
                              if not Read_Seven_Zip_Number
                                   (Archive_Image, P, Header_Last, Hdr_Size)
                              then
                                 return Empty;
                              end if;
                           else
                              Hdr_Size := HC_Size;
                           end if;
                           --  optional folder CRC
                           if P <= Header_Last
                             and then Archive_Image (P) = 16#0A#
                           then
                              P := P + 1;
                              if not Seven_Zip_Expect_Byte
                                   (Archive_Image, P, Header_Last, 1)
                                or else not Seven_Zip_Has_Bytes
                                  (P, Header_Last, 4)
                              then
                                 return Empty;
                              end if;
                              P := P + 4;
                           end if;
                           if not Seven_Zip_Expect_Byte
                                (Archive_Image, P, Header_Last, 0)
                             or else not Seven_Zip_Expect_Byte
                               (Archive_Image, P, Header_Last, 0)
                           then
                              return Empty;
                           end if;

                           if Pack_Pos >
                                Interfaces.Unsigned_64 (Natural'Last)
                             or else Pack_Size >
                               Interfaces.Unsigned_64 (Natural'Last)
                             or else Pack_Pos >
                               Interfaces.Unsigned_64 (Payload_Count)
                             or else Pack_Size >
                               Interfaces.Unsigned_64 (Payload_Count) - Pack_Pos
                             or else Natural (Pack_Size) mod 16 /= 0
                             or else Natural (Pack_Size) = 0
                             or else US.Length (Active_Seven_Zip_Password) = 0
                           then
                              return Empty;
                           end if;

                           Encoded_Header_Pack_Pos := Natural (Pack_Pos);
                           declare
                              Enc_First : constant Natural :=
                                Payload_First + Natural (Pack_Pos);
                              Enc : constant Byte_Array :=
                                Archive_Image
                                  (Enc_First ..
                                   Enc_First + Natural (Pack_Size) - 1);
                              Key : constant Byte_Array :=
                                Zlib.Seven_Zip_AES.Derive_Key
                                  (US.To_String (Active_Seven_Zip_Password),
                                   Salt (1 .. Salt_Len), Cycles);
                              Dec : constant Byte_Array :=
                                Zlib.Seven_Zip_AES.Decrypt_CBC (Key, IV, Enc);
                              LS  : Status_Code := Ok;
                           begin
                              if Natural (HC_Size) > Dec'Length then
                                 return Empty;
                              end if;
                              declare
                                 Trunc : constant Byte_Array :=
                                   Dec (Dec'First ..
                                        Dec'First + Natural (HC_Size) - 1);
                                 Plain : constant Byte_Array :=
                                   (if Num_Coders = 2
                                    then LZMA_Decode_Raw_Encoded_Header
                                           (Trunc, LZMA_P,
                                            Natural (Hdr_Size), LS)
                                    else Trunc);
                              begin
                                 if LS /= Ok then
                                    Decode_Status := LS;
                                    return Empty;
                                 end if;
                                 Decode_Status := Ok;
                                 return Plain;
                              end;
                           end;
                        exception
                           when others =>
                              Decode_Status := Unsupported_Method;
                              return Empty;
                        end Decode_AES_Encoded_Header;

                        function Decode_Encoded_Header
                          (Decode_Status : out Status_Code) return Byte_Array
                        is
                           Enc_Pos      : Natural := Header_First;
                           Enc_Value    : Interfaces.Unsigned_64 := 0;
                           Enc_B        : Byte := 0;
                           Pack_Pos     : Interfaces.Unsigned_64 := 0;
                           Pack_Size    : Interfaces.Unsigned_64 := 0;
                           Pack_CRC     : Interfaces.Unsigned_32 := 0;
                           Pack_CRC_OK  : Boolean := False;
                           Method       : Seven_Zip_Coder_Method := Seven_Zip_Copy;
                           Delta_Distance : Natural := 1;
                           PPMd_Memory  : Interfaces.Unsigned_32 := 0;
                           LZMA_Prop    : Seven_Zip_LZMA_Props :=
                             [1 => LZMA_Default_Props,
                              2 => Byte (LZMA_Default_Dict mod 256),
                              3 => Byte ((LZMA_Default_Dict / 256) mod 256),
                              4 => Byte ((LZMA_Default_Dict / 65_536) mod 256),
                              5 => Byte
                                ((LZMA_Default_Dict / 16#0100_0000#) mod 256)];
                           Unpack_Size  : Interfaces.Unsigned_64 := 0;
                           Unpack_CRC   : Interfaces.Unsigned_32 := 0;
                           Unpack_CRC_OK : Boolean := False;
                        begin
                           Decode_Status := Unsupported_Method;

                           if not Seven_Zip_Expect_Byte
                             (Archive_Image, Enc_Pos, Header_Last, 16#17#)
                           then
                              return Empty;
                           end if;

                           if Enc_Pos <= Header_Last
                             and then Archive_Image (Enc_Pos) = 16#04#
                           then
                              Enc_Pos := Enc_Pos + 1;
                           end if;

                           if not Seven_Zip_Expect_Byte
                             (Archive_Image, Enc_Pos, Header_Last, 16#06#)
                             or else not Read_Seven_Zip_Number
                               (Archive_Image, Enc_Pos, Header_Last, Pack_Pos)
                             or else not Read_Seven_Zip_Number
                               (Archive_Image, Enc_Pos, Header_Last, Enc_Value)
                             or else Enc_Value /= 1
                             or else not Seven_Zip_Expect_Byte
                               (Archive_Image, Enc_Pos, Header_Last, 16#09#)
                             or else not Read_Seven_Zip_Number
                               (Archive_Image, Enc_Pos, Header_Last, Pack_Size)
                           then
                              return Empty;
                           end if;

                           if Enc_Pos <= Header_Last
                             and then Archive_Image (Enc_Pos) = 16#0A#
                           then
                              Enc_Pos := Enc_Pos + 1;
                              if not Seven_Zip_Expect_Byte
                                (Archive_Image, Enc_Pos, Header_Last, 1)
                                or else not Seven_Zip_Has_Bytes
                                  (Enc_Pos, Header_Last, 4)
                              then
                                 return Empty;
                              end if;
                              Pack_CRC := Seven_Zip_U32_At
                                (Archive_Image, Enc_Pos);
                              Pack_CRC_OK := True;
                              Enc_Pos := Enc_Pos + 4;
                           end if;

                           if not Seven_Zip_Expect_Byte
                             (Archive_Image, Enc_Pos, Header_Last, 0)
                             or else not Seven_Zip_Expect_Byte
                               (Archive_Image, Enc_Pos, Header_Last, 16#07#)
                             or else not Seven_Zip_Expect_Byte
                               (Archive_Image, Enc_Pos, Header_Last, 16#0B#)
                             or else not Read_Seven_Zip_Number
                               (Archive_Image, Enc_Pos, Header_Last, Enc_Value)
                             or else Enc_Value /= 1
                             or else not Seven_Zip_Expect_Byte
                               (Archive_Image, Enc_Pos, Header_Last, 0)
                             or else not Read_Seven_Zip_Number
                               (Archive_Image, Enc_Pos, Header_Last, Enc_Value)
                             or else Enc_Value /= 1
                             or else not Seven_Zip_Read_Byte
                               (Archive_Image, Enc_Pos, Header_Last, Enc_B)
                           then
                              return Empty;
                           end if;

                           if Enc_B = 1 then
                              if not Seven_Zip_Expect_Byte
                                (Archive_Image, Enc_Pos, Header_Last, 0)
                              then
                                 return Empty;
                              end if;
                              Method := Seven_Zip_Copy;
                           elsif Enc_B = 3 then
                              if not Seven_Zip_Expect_Byte
                                (Archive_Image, Enc_Pos, Header_Last, 16#04#)
                                or else not Seven_Zip_Read_Byte
                                  (Archive_Image, Enc_Pos, Header_Last, Enc_B)
                              then
                                 return Empty;
                              end if;

                              if Enc_B = 16#01# then
                                 if not Seven_Zip_Expect_Byte
                                   (Archive_Image, Enc_Pos, Header_Last, 16#08#)
                                 then
                                    return Empty;
                                 end if;
                                 Method := Seven_Zip_Deflate_Method;
                              elsif Enc_B = 16#02# then
                                 if not Seven_Zip_Expect_Byte
                                   (Archive_Image, Enc_Pos, Header_Last, 16#02#)
                                 then
                                    return Empty;
                                 end if;
                                 Method := Seven_Zip_BZip2_Method;
                              else
                                 return Empty;
                              end if;
                           elsif Enc_B = 16#23# then
                              if not Seven_Zip_Expect_Byte
                                (Archive_Image, Enc_Pos, Header_Last, 16#03#)
                                or else not Seven_Zip_Read_Byte
                                  (Archive_Image, Enc_Pos, Header_Last, Enc_B)
                              then
                                 return Empty;
                              end if;

                              if Enc_B = 16#01# then
                                 if not Seven_Zip_Expect_Byte
                                   (Archive_Image, Enc_Pos, Header_Last, 16#01#)
                                   or else not Seven_Zip_Expect_Byte
                                     (Archive_Image, Enc_Pos, Header_Last, 5)
                                 then
                                    return Empty;
                                 end if;

                                 for J in LZMA_Prop'Range loop
                                    if not Seven_Zip_Read_Byte
                                      (Archive_Image, Enc_Pos, Header_Last,
                                       LZMA_Prop (J))
                                    then
                                       return Empty;
                                    end if;
                                 end loop;

                                 if not Valid_LZMA_Props (LZMA_Prop (1)) then
                                    return Empty;
                                 end if;
                                 Method := Seven_Zip_LZMA_Method;
                              elsif Enc_B = 16#04# then
                                 if not Seven_Zip_Expect_Byte
                                   (Archive_Image, Enc_Pos, Header_Last, 16#01#)
                                   or else not Seven_Zip_Expect_Byte
                                     (Archive_Image, Enc_Pos, Header_Last, 5)
                                   or else not Seven_Zip_Read_Byte
                                     (Archive_Image, Enc_Pos, Header_Last, Enc_B)
                                   or else not Seven_Zip_Has_Bytes
                                     (Enc_Pos, Header_Last, 4)
                                 then
                                    return Empty;
                                 end if;

                                 PPMd_Memory :=
                                   Seven_Zip_U32_At (Archive_Image, Enc_Pos);
                                 if not Seven_Zip_Valid_PPMd_Props
                                   (Natural (Enc_B), PPMd_Memory)
                                 then
                                    return Empty;
                                 end if;
                                 Enc_Pos := Enc_Pos + 4;
                                 Method := Seven_Zip_PPMd_Method;
                              else
                                 return Empty;
                              end if;
                           elsif Enc_B = 16#21# then
                              if not Seven_Zip_Read_Byte
                                (Archive_Image, Enc_Pos, Header_Last, Enc_B)
                              then
                                 return Empty;
                              end if;

                              if Enc_B = 16#21# then
                                 if not Seven_Zip_Expect_Byte
                                   (Archive_Image, Enc_Pos, Header_Last, 1)
                                   or else not Seven_Zip_Read_Byte
                                     (Archive_Image, Enc_Pos, Header_Last, Enc_B)
                                   or else Enc_B > 40
                                 then
                                    return Empty;
                                 end if;
                                 Method := Seven_Zip_LZMA2_Method;
                              elsif Enc_B = 16#03# then
                                 if not Seven_Zip_Expect_Byte
                                   (Archive_Image, Enc_Pos, Header_Last, 1)
                                   or else not Seven_Zip_Read_Byte
                                     (Archive_Image, Enc_Pos, Header_Last, Enc_B)
                                 then
                                    return Empty;
                                 end if;
                                 Delta_Distance := Natural (Enc_B) + 1;
                                 Method := Seven_Zip_Delta_Method;
                              else
                                 return Empty;
                              end if;
                           else
                              return Empty;
                           end if;

                           if not Seven_Zip_Expect_Byte
                             (Archive_Image, Enc_Pos, Header_Last, 16#0C#)
                             or else not Read_Seven_Zip_Number
                               (Archive_Image, Enc_Pos, Header_Last, Unpack_Size)
                           then
                              return Empty;
                           end if;

                           if Enc_Pos <= Header_Last
                             and then Archive_Image (Enc_Pos) = 16#0A#
                           then
                              Enc_Pos := Enc_Pos + 1;
                              if not Seven_Zip_Expect_Byte
                                (Archive_Image, Enc_Pos, Header_Last, 1)
                                or else not Seven_Zip_Has_Bytes
                                  (Enc_Pos, Header_Last, 4)
                              then
                                 return Empty;
                              end if;
                              Unpack_CRC := Seven_Zip_U32_At
                                (Archive_Image, Enc_Pos);
                              Unpack_CRC_OK := True;
                              Enc_Pos := Enc_Pos + 4;
                           end if;

                           if not Seven_Zip_Expect_Byte
                             (Archive_Image, Enc_Pos, Header_Last, 0)
                           then
                              return Empty;
                           end if;

                           if not Seven_Zip_Expect_Byte
                             (Archive_Image, Enc_Pos, Header_Last, 0)
                           then
                              return Empty;
                           end if;

                           if Enc_Pos /= Header_Last + 1
                             or else Pack_Pos >
                               Interfaces.Unsigned_64 (Natural'Last)
                             or else Pack_Size >
                               Interfaces.Unsigned_64 (Natural'Last)
                             or else Unpack_Size >
                               Interfaces.Unsigned_64 (Natural'Last)
                             or else Pack_Pos >
                               Interfaces.Unsigned_64 (Payload_Count)
                             or else Pack_Size >
                               Interfaces.Unsigned_64 (Payload_Count) - Pack_Pos
                           then
                              return Empty;
                           end if;

                           Encoded_Header_Pack_Pos := Natural (Pack_Pos);

                           declare
                              Enc_First : constant Natural :=
                                Payload_First + Natural (Pack_Pos);
                              Enc_Size  : constant Natural := Natural (Pack_Size);
                              Enc_Last  : constant Natural :=
                                (if Enc_Size = 0
                                 then Enc_First - 1
                                 else Enc_First + Enc_Size - 1);
                              Encoded   : constant Byte_Array :=
                                (if Enc_Size = 0
                                 then Empty
                                 else Archive_Image (Enc_First .. Enc_Last));
                              Local_Status : Status_Code := Ok;

                              function Decode_Payload return Byte_Array is
                              begin
                                 case Method is
                                    when Seven_Zip_Copy =>
                                       return Encoded;

                                    when Seven_Zip_Deflate_Method =>
                                       return Inflate_Raw_Exact
                                         (Encoded, Local_Status);

                                    when Seven_Zip_BZip2_Method =>
                                       return BZip2_Decompress
                                         (Encoded, Natural (Unpack_Size),
                                          Local_Status);

                                    when Seven_Zip_LZMA_Method =>
                                       return LZMA_Decode_Raw_Encoded_Header
                                         (Encoded, LZMA_Prop,
                                          Natural (Unpack_Size),
                                          Local_Status);

                                    when Seven_Zip_LZMA2_Method =>
                                       return LZMA2_Decode
                                         (Encoded, Natural (Unpack_Size),
                                          Local_Status);

                                    when Seven_Zip_Delta_Method =>
                                       return Seven_Zip_Delta_Decode
                                         (Encoded, Delta_Distance,
                                          Local_Status);

                                    when Seven_Zip_BCJ_X86_Method =>
                                       return Seven_Zip_BCJ_X86_Decode
                                         (Encoded, Local_Status);

                                    when Seven_Zip_BCJ_ARM_Method
                                       | Seven_Zip_BCJ_ARMT_Method
                                       | Seven_Zip_BCJ_PPC_Method
                                       | Seven_Zip_BCJ_SPARC_Method
                                       | Seven_Zip_BCJ_ARM64_Method
                                       | Seven_Zip_BCJ_IA64_Method =>
                                       return
                                         Zlib.Seven_Zip_Filters.Branch_Convert
                                           (Branch_Arch_Of (Method), Encoded,
                                            Encoding => False);

                                    when Seven_Zip_BCJ2_Method =>
                                       Local_Status := Unsupported_Method;
                                       return Empty;

                                    when Seven_Zip_PPMd_Method =>
                                       declare
                                          Out_B : constant Byte_Array :=
                                            Zlib.PPMd7.Decompress
                                              (Encoded,
                                               Natural (Unpack_Size),
                                               Natural (Enc_B), PPMd_Memory,
                                               Local_Status);
                                       begin
                                          if Local_Status = Ok
                                            and then Unpack_CRC_OK
                                            and then CRC32 (Out_B) /= Unpack_CRC
                                          then
                                             Local_Status := Invalid_Checksum;
                                             return Empty;
                                          end if;
                                          return Out_B;
                                       end;

                                    when Seven_Zip_AES_Method =>
                                       Local_Status := Unsupported_Method;
                                       return Empty;
                                 end case;
                              end Decode_Payload;

                              Decoded : constant Byte_Array := Decode_Payload;
                           begin
                              if Pack_CRC_OK and then CRC32 (Encoded) /= Pack_CRC
                              then
                                 Decode_Status := Invalid_Checksum;
                                 return Empty;
                              end if;

                              if Local_Status /= Ok then
                                 Decode_Status := Local_Status;
                                 return Empty;
                              end if;

                              if Decoded'Length /= Natural (Unpack_Size)
                                or else
                                  (Unpack_CRC_OK
                                   and then CRC32 (Decoded) /= Unpack_CRC)
                              then
                                 Decode_Status := Invalid_Checksum;
                                 return Empty;
                              end if;

                              Decode_Status := Ok;
                              return Decoded;
                           end;
                        end Decode_Encoded_Header;

                        AES_Status     : Status_Code := Ok;
                        AES_Header     : constant Byte_Array :=
                          Decode_AES_Encoded_Header (AES_Status);
                        Encoded_Status : Status_Code := Ok;
                        Decoded_Header : constant Byte_Array :=
                          (if AES_Status = Ok then AES_Header
                           else Decode_Encoded_Header (Encoded_Status));
                     begin
                        if AES_Status /= Ok and then Encoded_Status /= Ok then
                           Status := Encoded_Status;
                           return Empty;
                        end if;

                        if Decoded_Header'Length = 0
                          or else Decoded_Header (Decoded_Header'First) not in
                            16#01# | 16#04#
                        then
                           Status := Unsupported_Method;
                           return Empty;
                        end if;

                        declare
                           Normalized_Header : constant Byte_Array :=
                             (if Decoded_Header (Decoded_Header'First) = 16#01#
                              then Decoded_Header
                              else [16#01#] & Decoded_Header);
                           Synthetic    : Byte_Vectors.Vector;
                           Start_Header : Byte_Vectors.Vector;

                           procedure Append_Array (Data : Byte_Array) is
                           begin
                              for Byte_Value of Data loop
                                 Synthetic.Append (Byte_Value);
                              end loop;
                           end Append_Array;
                        begin
                           Append_U64_LE
                             (Start_Header,
                              Interfaces.Unsigned_64
                                (Encoded_Header_Pack_Pos));
                           Append_U64_LE
                             (Start_Header,
                              Interfaces.Unsigned_64
                                (Normalized_Header'Length));
                           Append_U32_LE
                             (Start_Header, CRC32 (Normalized_Header));

                           Append_Array (Archive_Image (F .. F + 7));
                           Append_U32_LE
                             (Synthetic,
                              Seven_Zip_Header_CRC
                                (To_Byte_Array (Start_Header)));
                           Synthetic.Append_Vector (Start_Header);
                           if Encoded_Header_Pack_Pos > 0 then
                              Append_Array
                                (Archive_Image
                                   (Payload_First ..
                                    Payload_First
                                    + Encoded_Header_Pack_Pos - 1));
                           end if;
                           Append_Array (Normalized_Header);

                           declare
                              Synthetic_Image : constant Byte_Array :=
                                To_Byte_Array (Synthetic);
                           begin
                              return Extract_Seven_Zip_Entry
                                (Synthetic_Image, Entry_Name, Status, Kind,
                                 Metadata);
                           end;
                        end;
                     end;
                  end if;

                  if not Seven_Zip_Expect_Byte (Archive_Image, Pos, Header_Last, 16#01#)
                  then
                     return Empty;
                  end if;

                  if Pos <= Header_Last
                    and then Archive_Image (Pos) = 16#02#
                  then
                     Pos := Pos + 1;
                     if not Seven_Zip_Skip_Properties
                       (Archive_Image, Pos, Header_Last)
                     then
                        return Empty;
                     end if;
                  end if;

                  if Pos <= Header_Last
                    and then Archive_Image (Pos) = 16#05#
                  then
                     Pos := Pos + 1;
                     if not Read_Seven_Zip_Number
                       (Archive_Image, Pos, Header_Last, Value)
                       or else Value = 0
                       or else Value > Interfaces.Unsigned_64 (Natural'Last)
                     then
                        return Empty;
                     end if;

                     declare
                        File_Count        : constant Natural := Natural (Value);
                        File_Has_Stream   : array (1 .. File_Count) of Boolean :=
                          [others => True];
                        File_Is_Directory : array (1 .. File_Count) of Boolean :=
                          [others => False];
                        File_Has_MTime    : array (1 .. File_Count) of Boolean :=
                          [others => False];
                        File_MTime        : Seven_Zip_U64_Array (1 .. File_Count) :=
                          [others => 0];
                        File_Has_Attributes : array (1 .. File_Count) of Boolean :=
                          [others => False];
                        File_Attributes   : Seven_Zip_U32_Array (1 .. File_Count) :=
                          [others => 0];
                        Empty_Count       : Natural := 0;
                        Target_File_Index : Natural := 0;
                        Name_Found        : Boolean := False;
                     begin
                        loop
                           if not Seven_Zip_Read_Byte
                             (Archive_Image, Pos, Header_Last, B)
                           then
                              return Empty;
                           end if;

                           exit when B = 0;

                           if not Read_Seven_Zip_Number
                             (Archive_Image, Pos, Header_Last, Value)
                             or else Value >
                               Interfaces.Unsigned_64 (Natural'Last)
                             or else Value >
                               Interfaces.Unsigned_64 (Header_Last - Pos + 1)
                           then
                              return Empty;
                           end if;

                           declare
                              Prop_Size  : constant Natural := Natural (Value);
                              Prop_First : constant Natural := Pos;
                              Prop_Last  : constant Natural :=
                                (if Prop_Size = 0
                                 then Prop_First - 1
                                 else Prop_First + Prop_Size - 1);
                           begin
                              case B is
                                 when 16#11# =>
                                    if Prop_Size = 0
                                      or else Prop_Size mod 2 = 0
                                      or else Prop_Size < 1 + 2 * File_Count
                                      or else not Seven_Zip_Name_Index
                                        (Archive_Image, Prop_First, Prop_Size,
                                         File_Count, Entry_Name,
                                         Target_File_Index)
                                    then
                                       return Empty;
                                    end if;
                                    Name_Found := True;

                                 when 16#0E# =>
                                    if Prop_Size < (File_Count + 7) / 8 then
                                       return Empty;
                                    end if;

                                    Empty_Count := 0;
                                    for I in 1 .. File_Count loop
                                       if Seven_Zip_Bit_Is_Set
                                         (Archive_Image, Prop_First, I)
                                       then
                                          File_Has_Stream (I) := False;
                                          File_Is_Directory (I) := True;
                                          Empty_Count := Empty_Count + 1;
                                       else
                                          File_Has_Stream (I) := True;
                                          File_Is_Directory (I) := False;
                                       end if;
                                    end loop;

                                 when 16#0F# =>
                                    if Empty_Count = 0
                                      or else Prop_Size < (Empty_Count + 7) / 8
                                    then
                                       return Empty;
                                    end if;

                                    declare
                                       Empty_Index : Natural := 0;
                                    begin
                                       for I in 1 .. File_Count loop
                                          if not File_Has_Stream (I) then
                                             Empty_Index := Empty_Index + 1;
                                             File_Is_Directory (I) :=
                                               not Seven_Zip_Bit_Is_Set
                                                 (Archive_Image, Prop_First,
                                                  Empty_Index);
                                          end if;
                                       end loop;
                                    end;

                                 when 16#10# =>
                                    for I in 1 .. File_Count loop
                                       if Seven_Zip_Bit_Is_Set
                                         (Archive_Image, Prop_First, I)
                                       then
                                          return Empty;
                                       end if;
                                    end loop;

                                 when 16#14# =>
                                    for I in 1 .. File_Count loop
                                       if not Seven_Zip_Read_File_Time_Property
                                         (Archive_Image, Prop_First, Prop_Size,
                                          File_Count, I, File_Has_MTime (I),
                                          File_MTime (I))
                                       then
                                          return Empty;
                                       end if;
                                    end loop;

                                 when 16#15# =>
                                    for I in 1 .. File_Count loop
                                       if not Seven_Zip_Read_U32_Property
                                         (Archive_Image, Prop_First, Prop_Size,
                                          File_Count, I,
                                          File_Has_Attributes (I),
                                          File_Attributes (I))
                                       then
                                          return Empty;
                                       end if;
                                    end loop;

                                 when others =>
                                    null;
                              end case;

                              Pos := Prop_Last + 1;
                           end;
                        end loop;

                        if not Name_Found
                          or else Target_File_Index = 0
                          or else not Seven_Zip_Read_Byte
                            (Archive_Image, Pos, Header_Last, B)
                          or else B /= 0
                          or else Pos /= Header_Last + 1
                          or else File_Has_Stream (Target_File_Index)
                        then
                           return Empty;
                        end if;

                        if File_Is_Directory (Target_File_Index) then
                           Kind := Seven_Zip_Directory_Entry;
                        else
                           Kind := Seven_Zip_File_Entry;
                        end if;

                        Metadata.Is_Directory :=
                          File_Is_Directory (Target_File_Index);
                        Metadata.Has_Modification_Time :=
                          File_Has_MTime (Target_File_Index);
                        Metadata.Modification_Time :=
                          File_MTime (Target_File_Index);
                        Metadata.Has_Windows_Attributes :=
                          File_Has_Attributes (Target_File_Index);
                        Metadata.Windows_Attributes :=
                          File_Attributes (Target_File_Index);

                        Status := Ok;
                        return Empty;
                     end;
                  end if;

                  if not Seven_Zip_Expect_Byte (Archive_Image, Pos, Header_Last, 16#04#)
                    or else not Seven_Zip_Expect_Byte (Archive_Image, Pos, Header_Last, 16#06#)
                    or else not Read_Seven_Zip_Number (Archive_Image, Pos, Header_Last, Value)
                    or else Value /= 0
                    or else not Read_Seven_Zip_Number (Archive_Image, Pos, Header_Last, Value)
                    or else Value = 0
                    or else Value > Interfaces.Unsigned_64 (Natural'Last)
                    or else Value > Interfaces.Unsigned_64 (Header_Count)
                  then
                     return Empty;
                  end if;

                  declare
                     Max_Folder_Coders : constant := 8;
                     type Seven_Zip_Folder_Method_Table is
                       array (Positive range <>, Positive range <>)
                         of Seven_Zip_Coder_Method;
                     type Seven_Zip_Folder_LZMA_Props_Table is
                       array (Positive range <>, Positive range <>)
                         of Seven_Zip_LZMA_Props;
                     type Seven_Zip_Folder_Natural_Table is
                       array (Positive range <>, Positive range <>) of Natural;
                     type Seven_Zip_Folder_U32_Table is
                       array (Positive range <>, Positive range <>)
                         of Interfaces.Unsigned_32;
                     type Seven_Zip_Folder_U64_Table is
                       array (Positive range <>, Positive range <>)
                         of Interfaces.Unsigned_64;
                     type Seven_Zip_AES_Block is array (1 .. 16) of Byte;
                     type Seven_Zip_Folder_AES_Block_Table is
                       array (Positive range <>, Positive range <>)
                         of Seven_Zip_AES_Block;
                     Stream_Count : constant Natural := Natural (Value);
                     Pack_Sizes   : Seven_Zip_U64_Array (1 .. Stream_Count);
                     Pack_CRCs    : Seven_Zip_U32_Array (1 .. Stream_Count);
                     Pack_CRC_Defined : array (1 .. Stream_Count) of Boolean :=
                       [others => False];
                     Methods      : Seven_Zip_Coder_Method_Array (1 .. Stream_Count);
                     Folder_Coder_Count : array (1 .. Stream_Count) of Natural :=
                       [others => 1];
                     Folder_Packed_Coder : array (1 .. Stream_Count) of Natural :=
                       [others => 1];
                     Folder_Terminal_Coder : array (1 .. Stream_Count) of Natural :=
                       [others => 1];
                     Folder_Next_Coder : Seven_Zip_Folder_Natural_Table
                       (1 .. Stream_Count, 1 .. Max_Folder_Coders) :=
                         [others => [others => 0]];
                     Folder_Reverse_Chain : array (1 .. Stream_Count) of Boolean :=
                       [others => False];
                     Folder_Methods : Seven_Zip_Folder_Method_Table
                       (1 .. Stream_Count, 1 .. Max_Folder_Coders) :=
                         [others => [others => Seven_Zip_Copy]];
                     Folder_LZMA_Props : Seven_Zip_Folder_LZMA_Props_Table
                       (1 .. Stream_Count, 1 .. Max_Folder_Coders) :=
                         [others =>
                            [others =>
                               [1 => LZMA_Default_Props,
                                2 => Byte (LZMA_Default_Dict mod 256),
                                3 => Byte ((LZMA_Default_Dict / 256) mod 256),
                                4 => Byte ((LZMA_Default_Dict / 65_536) mod 256),
                                5 => Byte
                                  ((LZMA_Default_Dict / 16#0100_0000#) mod 256)]]];
                     Folder_Delta_Distances : Seven_Zip_Folder_Natural_Table
                       (1 .. Stream_Count, 1 .. Max_Folder_Coders) :=
                         [others => [others => 1]];
                     Folder_PPMd_Orders : Seven_Zip_Folder_Natural_Table
                       (1 .. Stream_Count, 1 .. Max_Folder_Coders) :=
                         [others => [others => 0]];
                     Folder_AES_Cycles : Seven_Zip_Folder_Natural_Table
                       (1 .. Stream_Count, 1 .. Max_Folder_Coders) :=
                         [others => [others => 0]];
                     Folder_AES_Salt_Len : Seven_Zip_Folder_Natural_Table
                       (1 .. Stream_Count, 1 .. Max_Folder_Coders) :=
                         [others => [others => 0]];
                     Folder_AES_IV_Len : Seven_Zip_Folder_Natural_Table
                       (1 .. Stream_Count, 1 .. Max_Folder_Coders) :=
                         [others => [others => 0]];
                     Folder_AES_Salt : Seven_Zip_Folder_AES_Block_Table
                       (1 .. Stream_Count, 1 .. Max_Folder_Coders) :=
                         [others => [others => [others => 0]]];
                     Folder_AES_IV : Seven_Zip_Folder_AES_Block_Table
                       (1 .. Stream_Count, 1 .. Max_Folder_Coders) :=
                         [others => [others => [others => 0]]];
                     Folder_PPMd_Memories : Seven_Zip_Folder_U32_Table
                       (1 .. Stream_Count, 1 .. Max_Folder_Coders) :=
                         [others => [others => 0]];
                     Folder_Unpack_Sizes : Seven_Zip_Folder_U64_Table
                       (1 .. Stream_Count, 1 .. Max_Folder_Coders) :=
                         [others => [others => 0]];
                     Folder_Count : Natural := Stream_Count;
                     Folder_Pack_First : array (1 .. Stream_Count) of Natural :=
                       [others => 0];
                     Folder_Pack_Count : array (1 .. Stream_Count) of Natural :=
                       [others => 1];
                     Folder_Pack_Indices_Read : array (1 .. Stream_Count) of Boolean :=
                       [others => False];
                     Delta_Distances : array (1 .. Stream_Count) of Natural :=
                       [others => 1];
                     PPMd_Orders : array (1 .. Stream_Count) of Natural :=
                       [others => 0];
                     PPMd_Memories : Seven_Zip_U32_Array (1 .. Stream_Count) :=
                       [others => 0];
                     LZMA_Props   : Seven_Zip_LZMA_Props_Array (1 .. Stream_Count) :=
                       [others =>
                          [1 => LZMA_Default_Props,
                           2 => Byte (LZMA_Default_Dict mod 256),
                           3 => Byte ((LZMA_Default_Dict / 256) mod 256),
                           4 => Byte ((LZMA_Default_Dict / 65_536) mod 256),
                           5 => Byte
                             ((LZMA_Default_Dict / 16#0100_0000#) mod 256)]];
                     Unpack_Sizes : Seven_Zip_U64_Array (1 .. Stream_Count);
                     Unpack_CRCs  : Seven_Zip_U32_Array (1 .. Stream_Count);
                     Unpack_CRC_Defined : array (1 .. Stream_Count) of Boolean :=
                       [others => False];
                     Substream_Count : Natural := Stream_Count;
                     Substream_Sizes : Seven_Zip_U64_Array (1 .. Header_Count) :=
                       [others => 0];
                     Substream_Folders : array (1 .. Header_Count) of Natural :=
                       [others => 0];
                     Substream_CRCs : Seven_Zip_U32_Array (1 .. Header_Count) :=
                       [others => 0];
                     Substream_CRC_Defined : array (1 .. Header_Count) of Boolean :=
                       [others => False];
                     Total_Size   : Interfaces.Unsigned_64 := 0;
                     Target_Index : Natural := 0;
                  begin
                     if not Seven_Zip_Expect_Byte
                       (Archive_Image, Pos, Header_Last, 16#09#)
                     then
                        return Empty;
                     end if;

                     for I in Pack_Sizes'Range loop
                        if not Read_Seven_Zip_Number
                          (Archive_Image, Pos, Header_Last, Pack_Sizes (I))
                        then
                           return Empty;
                        end if;
                        if Pack_Sizes (I) >
                          Interfaces.Unsigned_64'Last - Total_Size
                        then
                           return Empty;
                        end if;
                        Total_Size := Total_Size + Pack_Sizes (I);
                     end loop;

                     if Total_Size /= Interfaces.Unsigned_64 (Payload_Count)
                     then
                        return Empty;
                     end if;

                     if Pos <= Header_Last
                       and then Archive_Image (Pos) = 16#0A#
                     then
                        Pos := Pos + 1;
                        if not Seven_Zip_Expect_Byte
                          (Archive_Image, Pos, Header_Last, 1)
                          or else Stream_Count > Natural'Last / 4
                          or else not Seven_Zip_Has_Bytes
                            (Pos, Header_Last, 4 * Stream_Count)
                        then
                           return Empty;
                        end if;

                        for I in Pack_CRCs'Range loop
                           Pack_CRCs (I) := Seven_Zip_U32_At (Archive_Image, Pos);
                           Pack_CRC_Defined (I) := True;
                           Pos := Pos + 4;
                        end loop;
                     end if;

                     if not Seven_Zip_Expect_Byte
                       (Archive_Image, Pos, Header_Last, 0)
                       or else not Seven_Zip_Expect_Byte
                         (Archive_Image, Pos, Header_Last, 16#07#)
                       or else not Seven_Zip_Expect_Byte
                         (Archive_Image, Pos, Header_Last, 16#0B#)
                       or else not Read_Seven_Zip_Number
                         (Archive_Image, Pos, Header_Last, Value)
                       or else Value = 0
                       or else Value > Interfaces.Unsigned_64 (Stream_Count)
                       or else not Seven_Zip_Expect_Byte
                         (Archive_Image, Pos, Header_Last, 0)
                     then
                        return Empty;
                     end if;

                     Folder_Count := Natural (Value);

                     declare
                        Next_Pack_Index : Natural := 1;
                     begin
                        for I in 1 .. Folder_Count loop
                           if not Read_Seven_Zip_Number
                             (Archive_Image, Pos, Header_Last, Value)
                             or else Value < 1
                             or else Value >
                               Interfaces.Unsigned_64 (Max_Folder_Coders)
                           then
                              return Empty;
                           end if;

                           declare
                              Coder_Count : constant Natural := Natural (Value);
                           begin
                              Folder_Coder_Count (I) := Coder_Count;

                              for Coder_Index in 1 .. Coder_Count loop
                                 declare
                                    Flags       : Byte := 0;
                                    ID_Size     : Natural;
                                    Has_Streams : Boolean;
                                    Has_Props   : Boolean;
                                    In_Streams  : Interfaces.Unsigned_64 := 1;
                                    Out_Streams : Interfaces.Unsigned_64 := 1;
                                    Prop_Size   : Interfaces.Unsigned_64 := 0;
                                    ID          : Byte_Array (1 .. 15) :=
                                      [others => 0];
                                 begin
                                    if not Seven_Zip_Read_Byte
                                      (Archive_Image, Pos, Header_Last, Flags)
                                    then
                                       return Empty;
                                    end if;

                                    ID_Size := Natural (Flags and 16#0F#);
                                    Has_Streams := (Flags and 16#10#) /= 0;
                                    Has_Props := (Flags and 16#20#) /= 0;

                                    if ID_Size = 0
                                      or else ID_Size > ID'Length
                                      or else (Flags and 16#C0#) /= 0
                                      or else not Seven_Zip_Has_Bytes
                                        (Pos, Header_Last, ID_Size)
                                    then
                                       return Empty;
                                    end if;

                                    for J in 1 .. ID_Size loop
                                       ID (J) := Archive_Image (Pos);
                                       Pos := Pos + 1;
                                    end loop;

                                    if Has_Streams then
                                       if not Read_Seven_Zip_Number
                                         (Archive_Image, Pos, Header_Last,
                                          In_Streams)
                                         or else not Read_Seven_Zip_Number
                                           (Archive_Image, Pos, Header_Last,
                                            Out_Streams)
                                       then
                                          return Empty;
                                       end if;
                                    end if;

                                    if ID_Size = 1 and then ID (1) = 0 then
                                       if Has_Streams
                                         or else Has_Props
                                       then
                                          return Empty;
                                       end if;
                                       Folder_Methods (I, Coder_Index) :=
                                         Seven_Zip_Copy;
                                    elsif ID_Size = 3
                                      and then ID (1) = 16#04#
                                      and then ID (2) = 16#01#
                                      and then ID (3) = 16#08#
                                    then
                                       if Has_Streams
                                         or else Has_Props
                                       then
                                          return Empty;
                                       end if;
                                       Folder_Methods (I, Coder_Index) :=
                                         Seven_Zip_Deflate_Method;
                                    elsif ID_Size = 3
                                      and then ID (1) = 16#04#
                                      and then ID (2) = 16#02#
                                      and then ID (3) = 16#02#
                                    then
                                       if Has_Streams
                                         or else Has_Props
                                       then
                                          return Empty;
                                       end if;
                                       Folder_Methods (I, Coder_Index) :=
                                         Seven_Zip_BZip2_Method;
                                    elsif ID_Size = 3
                                      and then ID (1) = 16#03#
                                      and then ID (2) = 16#01#
                                      and then ID (3) = 16#01#
                                    then
                                       if Has_Streams
                                         or else not Has_Props
                                         or else not Read_Seven_Zip_Number
                                           (Archive_Image, Pos, Header_Last,
                                            Prop_Size)
                                         or else Prop_Size /= 5
                                       then
                                          return Empty;
                                       end if;

                                       for J in 1 .. 5 loop
                                          if not Seven_Zip_Read_Byte
                                            (Archive_Image, Pos, Header_Last,
                                             Folder_LZMA_Props
                                               (I, Coder_Index) (J))
                                          then
                                             return Empty;
                                          end if;
                                       end loop;
                                       if not Valid_LZMA_Props
                                         (Folder_LZMA_Props (I, Coder_Index) (1))
                                       then
                                          return Empty;
                                       end if;
                                       Folder_Methods (I, Coder_Index) :=
                                         Seven_Zip_LZMA_Method;
                                    elsif ID_Size = 3
                                      and then ID (1) = 16#03#
                                      and then ID (2) = 16#04#
                                      and then ID (3) = 16#01#
                                    then
                                       if Has_Streams
                                         or else not Has_Props
                                         or else not Read_Seven_Zip_Number
                                           (Archive_Image, Pos, Header_Last,
                                            Prop_Size)
                                         or else Prop_Size /= 5
                                         or else not Seven_Zip_Read_Byte
                                           (Archive_Image, Pos, Header_Last, B)
                                         or else not Seven_Zip_Has_Bytes
                                           (Pos, Header_Last, 4)
                                       then
                                          return Empty;
                                       end if;

                                       Folder_PPMd_Orders (I, Coder_Index) :=
                                         Natural (B);
                                       Folder_PPMd_Memories (I, Coder_Index) :=
                                         Seven_Zip_U32_At (Archive_Image, Pos);
                                       if not Seven_Zip_Valid_PPMd_Props
                                         (Folder_PPMd_Orders (I, Coder_Index),
                                          Folder_PPMd_Memories (I, Coder_Index))
                                       then
                                          return Empty;
                                       end if;
                                       Pos := Pos + 4;
                                       Folder_Methods (I, Coder_Index) :=
                                         Seven_Zip_PPMd_Method;
                                    elsif ID_Size = 1 and then ID (1) = 16#21# then
                                       if Has_Streams
                                         or else not Has_Props
                                         or else not Read_Seven_Zip_Number
                                           (Archive_Image, Pos, Header_Last,
                                            Prop_Size)
                                         or else Prop_Size /= 1
                                         or else not Seven_Zip_Read_Byte
                                           (Archive_Image, Pos, Header_Last, B)
                                         or else B > 40
                                       then
                                          return Empty;
                                       end if;
                                       Folder_Methods (I, Coder_Index) :=
                                         Seven_Zip_LZMA2_Method;
                                    elsif ID_Size = 1 and then ID (1) = 16#03# then
                                       if Has_Streams
                                         or else not Has_Props
                                         or else not Read_Seven_Zip_Number
                                           (Archive_Image, Pos, Header_Last,
                                            Prop_Size)
                                         or else Prop_Size /= 1
                                         or else not Seven_Zip_Read_Byte
                                           (Archive_Image, Pos, Header_Last, B)
                                       then
                                          return Empty;
                                       end if;
                                       Folder_Delta_Distances
                                         (I, Coder_Index) := Natural (B) + 1;
                                       Folder_Methods (I, Coder_Index) :=
                                         Seven_Zip_Delta_Method;
                                    elsif ID_Size = 4
                                      and then ID (1) = 16#06#
                                      and then ID (2) = 16#F1#
                                      and then ID (3) = 16#07#
                                      and then ID (4) = 16#01#
                                    then
                                       --  7zAES (AES-256 + SHA-256).
                                       if Has_Streams
                                         or else not Has_Props
                                         or else not Read_Seven_Zip_Number
                                           (Archive_Image, Pos, Header_Last,
                                            Prop_Size)
                                         or else Prop_Size < 1
                                         or else not Seven_Zip_Has_Bytes
                                           (Pos, Header_Last, Natural (Prop_Size))
                                       then
                                          return Empty;
                                       end if;
                                       declare
                                          PB : Byte_Array (1 .. Natural (Prop_Size));
                                          B0, B1 : Natural := 0;
                                          Salt_Sz, IV_Sz, PP : Natural := 0;
                                       begin
                                          for J in PB'Range loop
                                             PB (J) := Archive_Image (Pos);
                                             Pos := Pos + 1;
                                          end loop;
                                          B0 := Natural (PB (1));
                                          Folder_AES_Cycles (I, Coder_Index) :=
                                            B0 mod 64;
                                          if (B0 / 64) /= 0
                                            and then Natural (Prop_Size) >= 2
                                          then
                                             B1 := Natural (PB (2));
                                             PP := 3;
                                          else
                                             PP := 2;
                                          end if;
                                          Salt_Sz := ((B0 / 128) mod 2) + (B1 / 16);
                                          IV_Sz := ((B0 / 64) mod 2) + (B1 mod 16);
                                          if Salt_Sz > 16 or else IV_Sz > 16
                                            or else Natural (Prop_Size) <
                                              (PP - 1) + Salt_Sz + IV_Sz
                                          then
                                             return Empty;
                                          end if;
                                          Folder_AES_Salt_Len (I, Coder_Index) :=
                                            Salt_Sz;
                                          Folder_AES_IV_Len (I, Coder_Index) := IV_Sz;
                                          for J in 1 .. Salt_Sz loop
                                             Folder_AES_Salt (I, Coder_Index) (J) :=
                                               PB (PP + J - 1);
                                          end loop;
                                          for J in 1 .. IV_Sz loop
                                             Folder_AES_IV (I, Coder_Index) (J) :=
                                               PB (PP + Salt_Sz + J - 1);
                                          end loop;
                                       end;
                                       Folder_Methods (I, Coder_Index) :=
                                         Seven_Zip_AES_Method;
                                    elsif ID_Size = 4
                                      and then ID (1) = 16#03#
                                      and then ID (2) = 16#03#
                                      and then ID (3) = 16#01#
                                      and then ID (4) = 16#03#
                                    then
                                       if Has_Streams
                                         or else Has_Props
                                       then
                                          return Empty;
                                       end if;
                                       Folder_Methods (I, Coder_Index) :=
                                         Seven_Zip_BCJ_X86_Method;
                                    elsif ID_Size = 4
                                      and then ID (1) = 16#03#
                                      and then ID (2) = 16#03#
                                      and then
                                        ((ID (3) = 16#05#
                                            and then ID (4) = 16#01#)
                                         or else (ID (3) = 16#07#
                                            and then ID (4) = 16#01#)
                                         or else (ID (3) = 16#02#
                                            and then ID (4) = 16#05#)
                                         or else (ID (3) = 16#08#
                                            and then ID (4) = 16#05#)
                                         or else (ID (3) = 16#04#
                                            and then ID (4) = 16#01#))
                                    then
                                       --  Classic 4-byte BCJ branch filters:
                                       --  ARM 03030501, ARMT 03030701,
                                       --  PPC 03030205, SPARC 03030805,
                                       --  IA64 03030401. No streams, no props.
                                       if Has_Streams or else Has_Props then
                                          return Empty;
                                       end if;
                                       Folder_Methods (I, Coder_Index) :=
                                         (if ID (3) = 16#05#
                                          then Seven_Zip_BCJ_ARM_Method
                                          elsif ID (3) = 16#07#
                                          then Seven_Zip_BCJ_ARMT_Method
                                          elsif ID (3) = 16#02#
                                          then Seven_Zip_BCJ_PPC_Method
                                          elsif ID (3) = 16#08#
                                          then Seven_Zip_BCJ_SPARC_Method
                                          else Seven_Zip_BCJ_IA64_Method);
                                    elsif ID_Size = 1
                                      and then ID (1) in
                                        16#05# | 16#06# | 16#07#
                                        | 16#08# | 16#09# | 16#0A#
                                    then
                                       --  Compact 1-byte BCJ ids: 05 PPC,
                                       --  06 IA64, 07 ARM, 08 ARMT, 09 SPARC,
                                       --  0A ARM64.
                                       if Has_Streams or else Has_Props then
                                          return Empty;
                                       end if;
                                       Folder_Methods (I, Coder_Index) :=
                                         (case ID (1) is
                                             when 16#05# =>
                                               Seven_Zip_BCJ_PPC_Method,
                                             when 16#06# =>
                                               Seven_Zip_BCJ_IA64_Method,
                                             when 16#07# =>
                                               Seven_Zip_BCJ_ARM_Method,
                                             when 16#08# =>
                                               Seven_Zip_BCJ_ARMT_Method,
                                             when 16#09# =>
                                               Seven_Zip_BCJ_SPARC_Method,
                                             when others =>
                                               Seven_Zip_BCJ_ARM64_Method);
                                    elsif ID_Size = 4
                                      and then ID (1) = 16#03#
                                      and then ID (2) = 16#03#
                                      and then ID (3) = 16#01#
                                      and then ID (4) = 16#1B#
                                    then
                                       if not Has_Streams
                                         or else Has_Props
                                         or else In_Streams /= 4
                                         or else Out_Streams /= 1
                                         or else (Coder_Count /= 1
                                                  and then
                                                    (Coder_Index /=
                                                       Coder_Count
                                                     or else Coder_Count /= 5))
                                       then
                                          return Empty;
                                       end if;
                                       Folder_Methods (I, Coder_Index) :=
                                         Seven_Zip_BCJ2_Method;
                                    else
                                       return Empty;
                                    end if;

                                    if Folder_Methods (I, Coder_Index) /=
                                      Seven_Zip_BCJ2_Method
                                      and then (In_Streams /= 1
                                                or else Out_Streams /= 1)
                                    then
                                       return Empty;
                                    end if;
                                 end;
                              end loop;

                              if Folder_Methods (I, 1) =
                                Seven_Zip_BCJ2_Method
                              then
                                 Folder_Pack_Count (I) := 4;
                                 Folder_Terminal_Coder (I) := 1;
                              elsif Coder_Count > 1 then
                                 declare
                                    Forward_Binds : Boolean := True;
                                    Reverse_Binds : Boolean := True;
                                    Standard_Linear_Binds : Boolean := True;
                                    Generic_Binds : Boolean := True;
                                    Legacy_Generic_Binds : Boolean := True;
                                    Next_Coder : array (1 .. Max_Folder_Coders) of Natural :=
                                      [others => 0];
                                    Legacy_Next_Coder : array (1 .. Max_Folder_Coders) of Natural :=
                                      [others => 0];
                                    Input_Bound : array (1 .. Max_Folder_Coders) of Boolean :=
                                      [others => False];
                                    Output_Bound : array (1 .. Max_Folder_Coders) of Boolean :=
                                      [others => False];
                                    Legacy_Input_Bound : array (1 .. Max_Folder_Coders) of Boolean :=
                                      [others => False];
                                    Legacy_Output_Bound : array (1 .. Max_Folder_Coders) of Boolean :=
                                      [others => False];
                                 begin
                                    for Bind_Index in 1 .. Coder_Count - 1 loop
                                       declare
                                          Bind_Out : Interfaces.Unsigned_64 := 0;
                                          Bind_In  : Interfaces.Unsigned_64 := 0;
                                          Out_Coder : Natural := 0;
                                          In_Coder  : Natural := 0;
                                       begin
                                          if not Read_Seven_Zip_Number
                                            (Archive_Image, Pos, Header_Last,
                                             Bind_Out)
                                            or else not Read_Seven_Zip_Number
                                              (Archive_Image, Pos, Header_Last,
                                               Bind_In)
                                          then
                                             return Empty;
                                          end if;

                                          if Generic_Binds
                                            and then Bind_Out <
                                              Interfaces.Unsigned_64
                                                (Coder_Count)
                                            and then Bind_In <
                                              Interfaces.Unsigned_64
                                                (Coder_Count)
                                          then
                                             --  7z BindPair is (InIndex, OutIndex);
                                             --  this reader stores them as
                                             --  Bind_Out := InIndex, Bind_In := OutIndex.
                                             --  The coder whose OUTPUT is bound is
                                             --  OutIndex's coder (Bind_In); the coder
                                             --  whose INPUT is bound is InIndex's coder
                                             --  (Bind_Out). (Matches the Legacy path.)
                                             Out_Coder := Natural (Bind_In) + 1;
                                             In_Coder := Natural (Bind_Out) + 1;
                                             if Output_Bound (Out_Coder)
                                               or else Input_Bound (In_Coder)
                                             then
                                                Generic_Binds := False;
                                             else
                                                Output_Bound (Out_Coder) := True;
                                                Input_Bound (In_Coder) := True;
                                                Next_Coder (Out_Coder) := In_Coder;
                                             end if;
                                          else
                                             Generic_Binds := False;
                                          end if;

                                          if Legacy_Generic_Binds
                                            and then Bind_Out in
                                              1 .. Interfaces.Unsigned_64
                                                (Coder_Count)
                                            and then Bind_In in
                                              1 .. Interfaces.Unsigned_64
                                                (Coder_Count)
                                          then
                                             Out_Coder := Natural (Bind_In);
                                             In_Coder := Natural (Bind_Out);
                                             if Legacy_Output_Bound (Out_Coder)
                                               or else Legacy_Input_Bound (In_Coder)
                                             then
                                                Legacy_Generic_Binds := False;
                                             else
                                                Legacy_Output_Bound (Out_Coder) := True;
                                                Legacy_Input_Bound (In_Coder) := True;
                                                Legacy_Next_Coder (Out_Coder) := In_Coder;
                                             end if;
                                          else
                                             Legacy_Generic_Binds := False;
                                          end if;

                                          if Bind_Out /=
                                            Interfaces.Unsigned_64
                                              (Bind_Index + 1)
                                            or else Bind_In /=
                                              Interfaces.Unsigned_64 (Bind_Index)
                                          then
                                             Forward_Binds := False;
                                          end if;

                                          if Bind_Out /=
                                            Interfaces.Unsigned_64 (Bind_Index)
                                            or else Bind_In /=
                                              Interfaces.Unsigned_64
                                                (Bind_Index - 1)
                                          then
                                             Reverse_Binds := False;
                                          end if;

                                          if Bind_Out /=
                                            Interfaces.Unsigned_64
                                              (Bind_Index - 1)
                                            or else Bind_In /=
                                              Interfaces.Unsigned_64
                                                (Bind_Index)
                                          then
                                             Standard_Linear_Binds := False;
                                          end if;
                                       end;
                                    end loop;

                                    if Reverse_Binds
                                      and then Coder_Count = 5
                                      and then Folder_Methods (I, Coder_Count) =
                                        Seven_Zip_BCJ2_Method
                                    then
                                       for Coder_Index in 1 .. Coder_Count - 1 loop
                                          case Folder_Methods (I, Coder_Index) is
                                             when Seven_Zip_Copy
                                                | Seven_Zip_Deflate_Method
                                                | Seven_Zip_BZip2_Method
                                                | Seven_Zip_LZMA_Method
                                                | Seven_Zip_LZMA2_Method
                                                | Seven_Zip_Delta_Method
                                                | Seven_Zip_BCJ_X86_Method
                                                | Seven_Zip_BCJ_ARM_Method
                                                | Seven_Zip_BCJ_ARMT_Method
                                                | Seven_Zip_BCJ_PPC_Method
                                                | Seven_Zip_BCJ_SPARC_Method
                                                | Seven_Zip_BCJ_ARM64_Method
                                                | Seven_Zip_BCJ_IA64_Method
                                                | Seven_Zip_PPMd_Method =>
                                                null;
                                             when others =>
                                                return Empty;
                                          end case;
                                       end loop;

                                       Folder_Packed_Coder (I) := Coder_Count;
                                       Folder_Terminal_Coder (I) := Coder_Count;
                                       Folder_Pack_Count (I) := 4;
                                       Folder_Pack_Indices_Read (I) := True;
                                       Generic_Binds := False;
                                       Legacy_Generic_Binds := False;

                                       for Relative_Index in 0 .. 3 loop
                                          if not Read_Seven_Zip_Number
                                            (Archive_Image, Pos, Header_Last,
                                             Value)
                                          then
                                             return Empty;
                                          end if;

                                          if (Relative_Index = 0
                                              and then Value /= 0)
                                            or else
                                              (Relative_Index > 0
                                               and then Value /=
                                                 Interfaces.Unsigned_64
                                                   (Coder_Count
                                                    + Relative_Index - 1))
                                          then
                                             return Empty;
                                          end if;
                                       end loop;
                                    elsif Reverse_Binds
                                      or else Forward_Binds
                                      or else Standard_Linear_Binds
                                    then
                                       if not Generic_Binds then
                                          if Reverse_Binds then
                                             Folder_Packed_Coder (I) :=
                                               Coder_Count;
                                             Folder_Terminal_Coder (I) := 1;
                                             Folder_Reverse_Chain (I) := True;
                                             for Coder_Index in
                                               2 .. Coder_Count
                                             loop
                                                Folder_Next_Coder
                                                  (I, Coder_Index) :=
                                                    Coder_Index - 1;
                                             end loop;
                                          else
                                             Folder_Packed_Coder (I) := 1;
                                             Folder_Terminal_Coder (I) :=
                                               Coder_Count;
                                             for Coder_Index in
                                               1 .. Coder_Count - 1
                                             loop
                                                Folder_Next_Coder
                                                  (I, Coder_Index) :=
                                                    Coder_Index + 1;
                                             end loop;
                                          end if;
                                       end if;
                                    else
                                       if not Generic_Binds
                                         and then not Legacy_Generic_Binds
                                       then
                                          return Empty;
                                       end if;
                                    end if;

                                    if Generic_Binds or else Legacy_Generic_Binds then
                                       declare
                                          Packed_Coder   : Natural := 0;
                                          Terminal_Coder : Natural := 0;
                                          Visited        : array (1 .. Max_Folder_Coders) of Boolean :=
                                            [others => False];
                                          Current        : Natural := 0;
                                          Visited_Count  : Natural := 0;
                                       begin
                                          for Coder_Index in 1 .. Coder_Count loop
                                             if not
                                               (if Generic_Binds
                                                then Input_Bound (Coder_Index)
                                                else Legacy_Input_Bound
                                                  (Coder_Index))
                                             then
                                                if Packed_Coder /= 0 then
                                                   return Empty;
                                                end if;
                                                Packed_Coder := Coder_Index;
                                             end if;

                                             if not
                                               (if Generic_Binds
                                                then Output_Bound (Coder_Index)
                                                else Legacy_Output_Bound
                                                  (Coder_Index))
                                             then
                                                if Terminal_Coder /= 0 then
                                                   return Empty;
                                                end if;
                                                Terminal_Coder := Coder_Index;
                                             end if;
                                          end loop;

                                          if Packed_Coder = 0
                                            or else Terminal_Coder = 0
                                          then
                                             return Empty;
                                          end if;

                                          Current := Packed_Coder;
                                          loop
                                             if Current = 0
                                               or else Current > Coder_Count
                                               or else Visited (Current)
                                             then
                                                return Empty;
                                             end if;

                                             Visited (Current) := True;
                                             Visited_Count := Visited_Count + 1;
                                             exit when Current = Terminal_Coder;
                                             Current :=
                                               (if Generic_Binds
                                                then Next_Coder (Current)
                                                else Legacy_Next_Coder
                                                  (Current));
                                          end loop;

                                          if Visited_Count /= Coder_Count then
                                             return Empty;
                                          end if;

                                          Folder_Packed_Coder (I) := Packed_Coder;
                                          Folder_Terminal_Coder (I) := Terminal_Coder;
                                          Folder_Reverse_Chain (I) := Reverse_Binds;

                                          for Coder_Index in 1 .. Coder_Count loop
                                             Folder_Next_Coder (I, Coder_Index) :=
                                               (if Generic_Binds
                                                then Next_Coder (Coder_Index)
                                                else Legacy_Next_Coder
                                                  (Coder_Index));
                                          end loop;
                                       end;
                                    end if;
                                 end;
                              else
                                 Folder_Terminal_Coder (I) := 1;
                              end if;

                              declare
                                 Packed_Coder : constant Natural :=
                                   Folder_Packed_Coder (I);
                              begin
                                 Methods (I) :=
                                   Folder_Methods (I, Packed_Coder);
                                 LZMA_Props (I) :=
                                   Folder_LZMA_Props (I, Packed_Coder);
                                 PPMd_Orders (I) :=
                                   Folder_PPMd_Orders (I, Packed_Coder);
                                 PPMd_Memories (I) :=
                                   Folder_PPMd_Memories (I, Packed_Coder);
                                 Delta_Distances (I) :=
                                   Folder_Delta_Distances (I, Packed_Coder);
                              end;

                              Folder_Pack_First (I) := Next_Pack_Index;
                              if Folder_Pack_Count (I) >
                                Stream_Count - Next_Pack_Index + 1
                              then
                                 return Empty;
                              end if;

                              if Folder_Pack_Count (I) > 1
                                and then not Folder_Pack_Indices_Read (I)
                              then
                                 for J in 0 .. Folder_Pack_Count (I) - 1 loop
                                    if not Read_Seven_Zip_Number
                                      (Archive_Image, Pos, Header_Last, Value)
                                      or else Value /=
                                        Interfaces.Unsigned_64
                                          (Next_Pack_Index + J - 1)
                                    then
                                       return Empty;
                                    end if;
                                 end loop;
                              end if;

                              Next_Pack_Index :=
                                Next_Pack_Index + Folder_Pack_Count (I);
                           end;
                        end loop;

                        if Next_Pack_Index /= Stream_Count + 1 then
                           return Empty;
                        end if;
                     end;

                     if not Seven_Zip_Expect_Byte
                       (Archive_Image, Pos, Header_Last, 16#0C#)
                     then
                        return Empty;
                     end if;

                     for I in 1 .. Folder_Count loop
                        for Coder_Index in 1 .. Folder_Coder_Count (I) loop
                           if not Read_Seven_Zip_Number
                             (Archive_Image, Pos, Header_Last,
                              Folder_Unpack_Sizes (I, Coder_Index))
                           then
                              return Empty;
                           end if;
                        end loop;

                        Unpack_Sizes (I) :=
                          Folder_Unpack_Sizes (I, Folder_Terminal_Coder (I));
                     end loop;

                     if Pos <= Header_Last
                       and then Archive_Image (Pos) = 16#0A#
                     then
                        Pos := Pos + 1;
                        if not Seven_Zip_Expect_Byte
                          (Archive_Image, Pos, Header_Last, 1)
                          or else Folder_Count > Natural'Last / 4
                          or else not Seven_Zip_Has_Bytes
                            (Pos, Header_Last, 4 * Folder_Count)
                        then
                           return Empty;
                        end if;

                        for I in 1 .. Folder_Count loop
                           Unpack_CRCs (I) :=
                             Seven_Zip_U32_At (Archive_Image, Pos);
                           Unpack_CRC_Defined (I) := True;
                           Pos := Pos + 4;
                        end loop;
                     end if;

                     if not Seven_Zip_Expect_Byte
                       (Archive_Image, Pos, Header_Last, 0)
                     then
                        return Empty;
                     end if;

                     Substream_Count := Folder_Count;
                     for I in 1 .. Folder_Count loop
                        Substream_Sizes (I) := Unpack_Sizes (I);
                        Substream_Folders (I) := I;
                     end loop;

                     if Pos <= Header_Last
                       and then Archive_Image (Pos) = 16#08#
                     then
                        Pos := Pos + 1;

                        declare
                           Streams_Per_Folder : array (1 .. Stream_Count) of Natural :=
                             [others => 1];
                           Need_Size_Property : Boolean := False;
                           Seen_Size_Property : Boolean := False;

                           procedure Rebuild_Default_Substreams is
                              Out_Index : Natural := 0;
                           begin
                              for Folder in 1 .. Folder_Count loop
                                 for J in 1 .. Streams_Per_Folder (Folder) loop
                                    Out_Index := Out_Index + 1;
                                    Substream_Folders (Out_Index) := Folder;
                                    if Streams_Per_Folder (Folder) = 1 then
                                       Substream_Sizes (Out_Index) :=
                                         Unpack_Sizes (Folder);
                                    else
                                       Substream_Sizes (Out_Index) := 0;
                                    end if;
                                 end loop;
                              end loop;
                              Substream_Count := Out_Index;
                           end Rebuild_Default_Substreams;
                        begin
                           loop
                              if not Seven_Zip_Read_Byte
                                (Archive_Image, Pos, Header_Last, B)
                              then
                                 return Empty;
                              end if;

                              exit when B = 0;

                              case B is
                                 when 16#0D# =>
                                    Substream_Count := 0;
                                    Need_Size_Property := False;
                                    for Folder in 1 .. Folder_Count loop
                                       if not Read_Seven_Zip_Number
                                         (Archive_Image, Pos, Header_Last, Value)
                                         or else Value = 0
                                         or else Value >
                                           Interfaces.Unsigned_64 (Header_Count)
                                         or else Substream_Count >
                                           Header_Count - Natural (Value)
                                       then
                                          return Empty;
                                       end if;

                                       Streams_Per_Folder (Folder) :=
                                         Natural (Value);
                                       Substream_Count :=
                                         Substream_Count + Natural (Value);
                                       if Value > 1 then
                                          Need_Size_Property := True;
                                       end if;
                                    end loop;

                                    Rebuild_Default_Substreams;

                                 when 16#09# =>
                                    declare
                                       Out_Index : Natural := 0;
                                    begin
                                       for Folder in 1 .. Folder_Count loop
                                          declare
                                             Folder_Total : Interfaces.Unsigned_64 := 0;
                                          begin
                                             for J in 1 .. Streams_Per_Folder (Folder) loop
                                                Out_Index := Out_Index + 1;
                                                Substream_Folders (Out_Index) := Folder;

                                                if J < Streams_Per_Folder (Folder) then
                                                   if not Read_Seven_Zip_Number
                                                     (Archive_Image, Pos,
                                                      Header_Last, Value)
                                                     or else Value >
                                                       Unpack_Sizes (Folder)
                                                     or else Folder_Total >
                                                       Unpack_Sizes (Folder) - Value
                                                   then
                                                      return Empty;
                                                   end if;

                                                   Substream_Sizes (Out_Index) :=
                                                     Value;
                                                   Folder_Total :=
                                                     Folder_Total + Value;
                                                else
                                                   Substream_Sizes (Out_Index) :=
                                                     Unpack_Sizes (Folder) -
                                                       Folder_Total;
                                                end if;
                                             end loop;
                                          end;
                                       end loop;

                                       Seen_Size_Property := True;
                                    end;

                                 when 16#0A# =>
                                    declare
                                       All_Defined : Byte := 0;
                                       Defined : array (1 .. Header_Count) of Boolean :=
                                         [others => False];
                                    begin
                                       if not Seven_Zip_Read_Byte
                                         (Archive_Image, Pos, Header_Last,
                                          All_Defined)
                                       then
                                          return Empty;
                                       end if;

                                       if All_Defined = 0 then
                                          if not Seven_Zip_Has_Bytes
                                            (Pos, Header_Last,
                                             (Substream_Count + 7) / 8)
                                          then
                                             return Empty;
                                          end if;

                                          declare
                                             Bits_First : constant Natural := Pos;
                                          begin
                                             Pos :=
                                               Pos + (Substream_Count + 7) / 8;
                                             for I in 1 .. Substream_Count loop
                                                if Seven_Zip_Bit_Is_Set
                                                  (Archive_Image, Bits_First, I)
                                                then
                                                   Defined (I) := True;
                                                end if;
                                             end loop;
                                          end;
                                       elsif All_Defined = 1 then
                                          for I in 1 .. Substream_Count loop
                                             Defined (I) := True;
                                          end loop;
                                       else
                                          return Empty;
                                       end if;

                                       for I in 1 .. Substream_Count loop
                                          Substream_CRC_Defined (I) :=
                                            Defined (I);

                                          if Defined (I) then
                                             if not Seven_Zip_Has_Bytes
                                               (Pos, Header_Last, 4)
                                             then
                                                return Empty;
                                             end if;

                                             Substream_CRCs (I) :=
                                               Seven_Zip_U32_At
                                                 (Archive_Image, Pos);
                                             Pos := Pos + 4;
                                          end if;
                                       end loop;
                                    end;

                                 when others =>
                                    if not Read_Seven_Zip_Number
                                      (Archive_Image, Pos, Header_Last, Value)
                                      or else Value >
                                        Interfaces.Unsigned_64 (Natural'Last)
                                      or else Value >
                                        Interfaces.Unsigned_64
                                          (Header_Last - Pos + 1)
                                    then
                                       return Empty;
                                    end if;

                                    Pos := Pos + Natural (Value);
                              end case;
                           end loop;

                           if Need_Size_Property and then not Seen_Size_Property then
                              return Empty;
                           end if;
                        end;
                     end if;

                     if not Seven_Zip_Expect_Byte
                       (Archive_Image, Pos, Header_Last, 0)
                       or else not Seven_Zip_Expect_Byte
                         (Archive_Image, Pos, Header_Last, 16#05#)
                       or else not Read_Seven_Zip_Number
                         (Archive_Image, Pos, Header_Last, Value)
                       or else Value > Interfaces.Unsigned_64 (Natural'Last)
                     then
                        return Empty;
                     end if;

                     declare
                        File_Count        : constant Natural := Natural (Value);
                        File_Has_Stream   : array (1 .. File_Count) of Boolean :=
                          [others => True];
                        File_Is_Directory : array (1 .. File_Count) of Boolean :=
                          [others => False];
                        File_Has_MTime    : array (1 .. File_Count) of Boolean :=
                          [others => False];
                        File_MTime        : Seven_Zip_U64_Array (1 .. File_Count) :=
                          [others => 0];
                        File_Has_Attributes : array (1 .. File_Count) of Boolean :=
                          [others => False];
                        File_Attributes   : Seven_Zip_U32_Array (1 .. File_Count) :=
                          [others => 0];
                        Target_File_Index : Natural := 0;
                        Stream_Index      : Natural := 0;
                        Empty_Count       : Natural := 0;
                        Name_Found        : Boolean := False;
                     begin
                        if File_Count = 0 then
                           return Empty;
                        end if;

                        loop
                           if not Seven_Zip_Read_Byte
                             (Archive_Image, Pos, Header_Last, B)
                           then
                              return Empty;
                           end if;

                           exit when B = 0;

                           if not Read_Seven_Zip_Number
                             (Archive_Image, Pos, Header_Last, Value)
                             or else Value >
                               Interfaces.Unsigned_64 (Natural'Last)
                             or else Value >
                               Interfaces.Unsigned_64 (Header_Last - Pos + 1)
                           then
                              return Empty;
                           end if;

                           declare
                              Prop_Size  : constant Natural := Natural (Value);
                              Prop_First : constant Natural := Pos;
                              Prop_Last  : constant Natural :=
                                (if Prop_Size = 0
                                 then Prop_First - 1
                                 else Prop_First + Prop_Size - 1);
                           begin
                              case B is
                                 when 16#11# =>
                                    if Prop_Size = 0
                                      or else Prop_Size mod 2 = 0
                                      or else Prop_Size < 1 + 2 * File_Count
                                      or else not Seven_Zip_Name_Index
                                        (Archive_Image, Prop_First, Prop_Size,
                                         File_Count, Entry_Name,
                                         Target_File_Index)
                                    then
                                       return Empty;
                                    end if;
                                    Name_Found := True;

                                 when 16#0E# =>
                                    if Prop_Size < (File_Count + 7) / 8 then
                                       return Empty;
                                    end if;

                                    Empty_Count := 0;
                                    for I in 1 .. File_Count loop
                                       if Seven_Zip_Bit_Is_Set
                                         (Archive_Image, Prop_First, I)
                                       then
                                          File_Has_Stream (I) := False;
                                          File_Is_Directory (I) := True;
                                          Empty_Count := Empty_Count + 1;
                                       else
                                          File_Has_Stream (I) := True;
                                          File_Is_Directory (I) := False;
                                       end if;
                                    end loop;

                                 when 16#0F# =>
                                    if Empty_Count = 0
                                      or else Prop_Size < (Empty_Count + 7) / 8
                                    then
                                       return Empty;
                                    end if;

                                    declare
                                       Empty_Index : Natural := 0;
                                    begin
                                       for I in 1 .. File_Count loop
                                          if not File_Has_Stream (I) then
                                             Empty_Index := Empty_Index + 1;
                                             File_Is_Directory (I) :=
                                               not Seven_Zip_Bit_Is_Set
                                                 (Archive_Image, Prop_First,
                                                  Empty_Index);
                                          end if;
                                       end loop;
                                    end;

                                 when 16#10# =>
                                    for I in 1 .. File_Count loop
                                       if Seven_Zip_Bit_Is_Set
                                         (Archive_Image, Prop_First, I)
                                       then
                                          return Empty;
                                       end if;
                                    end loop;

                                 when 16#14# =>
                                    for I in 1 .. File_Count loop
                                       if not Seven_Zip_Read_File_Time_Property
                                         (Archive_Image, Prop_First, Prop_Size,
                                          File_Count, I, File_Has_MTime (I),
                                          File_MTime (I))
                                       then
                                          return Empty;
                                       end if;
                                    end loop;

                                 when 16#15# =>
                                    for I in 1 .. File_Count loop
                                       if not Seven_Zip_Read_U32_Property
                                         (Archive_Image, Prop_First, Prop_Size,
                                          File_Count, I,
                                          File_Has_Attributes (I),
                                          File_Attributes (I))
                                       then
                                          return Empty;
                                       end if;
                                    end loop;

                                 when others =>
                                    null;
                              end case;

                              Pos := Prop_Last + 1;
                           end;
                        end loop;

                        if not Name_Found or else Target_File_Index = 0 then
                           return Empty;
                        end if;

                        Metadata.Has_Modification_Time :=
                          File_Has_MTime (Target_File_Index);
                        Metadata.Modification_Time :=
                          File_MTime (Target_File_Index);
                        Metadata.Has_Windows_Attributes :=
                          File_Has_Attributes (Target_File_Index);
                        Metadata.Windows_Attributes :=
                          File_Attributes (Target_File_Index);
                        Metadata.Is_Directory :=
                          File_Is_Directory (Target_File_Index);

                        for I in 1 .. File_Count loop
                           if File_Has_Stream (I) then
                              Stream_Index := Stream_Index + 1;
                              if I = Target_File_Index then
                                 Target_Index := Stream_Index;
                              end if;
                           elsif I = Target_File_Index then
                              if File_Is_Directory (I) then
                                 Kind := Seven_Zip_Directory_Entry;
                              else
                                 Kind := Seven_Zip_File_Entry;
                              end if;

                              Status := Ok;
                              return Empty;
                           end if;
                        end loop;

                        if Stream_Index /= Substream_Count
                          or else Target_Index = 0
                          or else not Seven_Zip_Read_Byte
                            (Archive_Image, Pos, Header_Last, B)
                          or else B /= 0
                          or else Pos /= Header_Last + 1
                        then
                           return Empty;
                        end if;
                     end;

                     declare
                        Target_Folder_Index : constant Natural :=
                          Substream_Folders (Target_Index);
                        Target_Pack_Index   : Natural := 0;
                        Target_Offset       : Natural := 0;
                     begin
                        if Target_Folder_Index = 0
                          or else Target_Folder_Index > Folder_Count
                        then
                           return Empty;
                        end if;

                        Target_Pack_Index :=
                          Folder_Pack_First (Target_Folder_Index);

                        for I in 1 .. Folder_Pack_First (Target_Folder_Index) - 1 loop
                           if Pack_Sizes (I) >
                             Interfaces.Unsigned_64 (Natural'Last - Target_Offset)
                           then
                              Status := Unsupported_Method;
                              return Empty;
                           end if;
                           Target_Offset :=
                             Target_Offset + Natural (Pack_Sizes (I));
                        end loop;

                        if Pack_Sizes (Target_Pack_Index) >
                          Interfaces.Unsigned_64 (Natural'Last)
                          or else Unpack_Sizes (Target_Folder_Index) >
                            Interfaces.Unsigned_64 (Natural'Last)
                          or else Substream_Sizes (Target_Index) >
                            Interfaces.Unsigned_64 (Natural'Last)
                        then
                           Status := Unsupported_Method;
                           return Empty;
                        end if;

                        declare
                           Target_Size  : constant Natural :=
                             Natural
                               (Pack_Sizes
                                  (Target_Pack_Index));
                           Target_First : constant Natural :=
                             Payload_First + Target_Offset;
                           Target_Last  : constant Natural :=
                             (if Target_Size = 0
                              then Target_First - 1
                              else Target_First + Target_Size - 1);
                           Payload      : constant Byte_Array :=
                             (if Target_Size = 0
                              then Empty
                              else Archive_Image (Target_First .. Target_Last));

                           function Slice_Substream
                             (Plain : Byte_Array) return Byte_Array
                           is
                              Sub_Offset : Natural := 0;
                              Sub_Size   : constant Natural :=
                                Natural (Substream_Sizes (Target_Index));
                           begin
                              for I in 1 .. Target_Index - 1 loop
                                 if Substream_Folders (I) = Target_Folder_Index then
                                    if Substream_Sizes (I) >
                                      Interfaces.Unsigned_64
                                        (Natural'Last - Sub_Offset)
                                    then
                                       Status := Unsupported_Method;
                                       return Empty;
                                    end if;
                                    Sub_Offset :=
                                      Sub_Offset + Natural (Substream_Sizes (I));
                                 end if;
                              end loop;

                              if Sub_Offset > Plain'Length
                                or else Sub_Size > Plain'Length - Sub_Offset
                              then
                                 Status := Invalid_Checksum;
                                 return Empty;
                              end if;

                              if Sub_Size = 0 then
                                 if Substream_CRC_Defined (Target_Index)
                                   and then CRC32 (Empty) /=
                                     Substream_CRCs (Target_Index)
                                 then
                                    Status := Invalid_Checksum;
                                 end if;
                                 return Empty;
                              end if;

                              declare
                                 Result : constant Byte_Array :=
                                   Plain
                                     (Plain'First + Sub_Offset ..
                                      Plain'First + Sub_Offset + Sub_Size - 1);
                              begin
                                 if Substream_CRC_Defined (Target_Index)
                                   and then CRC32 (Result) /=
                                     Substream_CRCs (Target_Index)
                                 then
                                    Status := Invalid_Checksum;
                                    return Empty;
                                 end if;

                                 return Result;
                              end;
                           end Slice_Substream;

                           function Validate_And_Slice
                             (Plain : Byte_Array) return Byte_Array is
                           begin
                              if Plain'Length /=
                                Natural (Unpack_Sizes (Target_Folder_Index))
                                or else
                                  (Unpack_CRC_Defined (Target_Folder_Index)
                                   and then CRC32 (Plain) /=
                                     Unpack_CRCs (Target_Folder_Index))
                              then
                                 Status := Invalid_Checksum;
                                 return Empty;
                              end if;

                              Status := Ok;
                              return Slice_Substream (Plain);
                           end Validate_And_Slice;

                           function Finish_Decoded_Payload
                             (Payload_Plain : Byte_Array;
                              First_Coder   : Natural :=
                                Folder_Next_Coder
                                  (Target_Folder_Index,
                                   Folder_Packed_Coder
                                     (Target_Folder_Index));
                              Last_Coder    : Natural :=
                                Folder_Terminal_Coder (Target_Folder_Index))
                              return Byte_Array
                           is
                              pragma Unreferenced (Last_Coder);

                              function Run_Post_Coders
                                (Coder_Index : Natural;
                                 Input       : Byte_Array) return Byte_Array;

                              function Run_Post_Coders
                                (Coder_Index : Natural;
                                 Input       : Byte_Array) return Byte_Array
                              is
                                 Filter_Status : Status_Code := Ok;

                                 function Done return Boolean is
                                 begin
                                    return Coder_Index = 0;
                                 end Done;

                                 function Next_Coder return Natural is
                                 begin
                                    return Folder_Next_Coder
                                      (Target_Folder_Index, Coder_Index);
                                 end Next_Coder;
                              begin
                                 if Done then
                                    return Validate_And_Slice (Input);
                                 end if;

                                 case Folder_Methods
                                   (Target_Folder_Index, Coder_Index)
                                 is
                                    when Seven_Zip_Copy =>
                                       return Run_Post_Coders
                                         (Next_Coder, Input);

                                    when Seven_Zip_Delta_Method =>
                                       declare
                                          Decoded : constant Byte_Array :=
                                            Seven_Zip_Delta_Decode
                                              (Input,
                                               Folder_Delta_Distances
                                                 (Target_Folder_Index,
                                                  Coder_Index),
                                               Filter_Status);
                                       begin
                                          if Filter_Status /= Ok then
                                             Status := Filter_Status;
                                             return Empty;
                                          end if;

                                          return Run_Post_Coders
                                            (Next_Coder, Decoded);
                                       end;

                                    when Seven_Zip_AES_Method =>
                                       declare
                                          Salt_Len : constant Natural :=
                                            Folder_AES_Salt_Len
                                              (Target_Folder_Index, Coder_Index);
                                          IV_Len : constant Natural :=
                                            Folder_AES_IV_Len
                                              (Target_Folder_Index, Coder_Index);
                                          Salt : Byte_Array (1 .. Salt_Len);
                                          IV   : Byte_Array (1 .. 16) :=
                                            [others => 0];
                                       begin
                                          for J in 1 .. Salt_Len loop
                                             Salt (J) := Folder_AES_Salt
                                               (Target_Folder_Index,
                                                Coder_Index) (J);
                                          end loop;
                                          for J in 1 .. IV_Len loop
                                             IV (J) := Folder_AES_IV
                                               (Target_Folder_Index,
                                                Coder_Index) (J);
                                          end loop;
                                          if US.Length
                                               (Active_Seven_Zip_Password) = 0
                                            or else Input'Length mod 16 /= 0
                                          then
                                             Status := Unsupported_Method;
                                             return Empty;
                                          end if;
                                          return Run_Post_Coders
                                            (Next_Coder,
                                             Zlib.Seven_Zip_AES.Decrypt_CBC
                                               (Zlib.Seven_Zip_AES.Derive_Key
                                                  (US.To_String
                                                     (Active_Seven_Zip_Password),
                                                   Salt,
                                                   Folder_AES_Cycles
                                                     (Target_Folder_Index,
                                                      Coder_Index)),
                                                IV, Input));
                                       end;

                                    when Seven_Zip_BCJ_X86_Method =>
                                       declare
                                          Decoded : constant Byte_Array :=
                                            Seven_Zip_BCJ_X86_Decode
                                              (Input, Filter_Status);
                                       begin
                                          if Filter_Status /= Ok then
                                             Status := Filter_Status;
                                             return Empty;
                                          end if;

                                          return Run_Post_Coders
                                            (Next_Coder, Decoded);
                                       end;

                                    when Seven_Zip_BCJ_ARM_Method
                                       | Seven_Zip_BCJ_ARMT_Method
                                       | Seven_Zip_BCJ_PPC_Method
                                       | Seven_Zip_BCJ_SPARC_Method
                                       | Seven_Zip_BCJ_ARM64_Method
                                       | Seven_Zip_BCJ_IA64_Method =>
                                       return Run_Post_Coders
                                         (Next_Coder,
                                          Zlib.Seven_Zip_Filters.Branch_Convert
                                            (Branch_Arch_Of
                                               (Folder_Methods
                                                  (Target_Folder_Index,
                                                   Coder_Index)),
                                             Input, Encoding => False));

                                    when Seven_Zip_Deflate_Method =>
                                       declare
                                          Decoded : constant Byte_Array :=
                                            Inflate_Raw_Exact
                                              (Input, Filter_Status);
                                       begin
                                          if Filter_Status /= Ok then
                                             Status := Filter_Status;
                                             return Empty;
                                          end if;

                                          return Run_Post_Coders
                                            (Next_Coder, Decoded);
                                       end;

                                    when Seven_Zip_BZip2_Method =>
                                       declare
                                          Decoded : constant Byte_Array :=
                                            BZip2_Decompress
                                              (Input,
                                               Natural
                                                 (Folder_Unpack_Sizes
                                                    (Target_Folder_Index,
                                                     Coder_Index)),
                                               Filter_Status);
                                       begin
                                          if Filter_Status /= Ok then
                                             Status := Filter_Status;
                                             return Empty;
                                          end if;

                                          return Run_Post_Coders
                                            (Next_Coder, Decoded);
                                       end;

                                    when Seven_Zip_LZMA_Method =>
                                       declare
                                          Decoded : constant Byte_Array :=
                                            LZMA_Decode_Raw
                                              (Input,
                                               Folder_LZMA_Props
                                                 (Target_Folder_Index,
                                                  Coder_Index),
                                               Natural
                                                 (Folder_Unpack_Sizes
                                                    (Target_Folder_Index,
                                                     Coder_Index)),
                                               Filter_Status);
                                       begin
                                          if Filter_Status /= Ok then
                                             Status := Filter_Status;
                                             return Empty;
                                          end if;

                                          return Run_Post_Coders
                                            (Next_Coder, Decoded);
                                       end;

                                    when Seven_Zip_LZMA2_Method =>
                                       declare
                                          Decoded : constant Byte_Array :=
                                            LZMA2_Decode
                                              (Input,
                                               Natural
                                                 (Folder_Unpack_Sizes
                                                    (Target_Folder_Index,
                                                     Coder_Index)),
                                               Filter_Status);
                                       begin
                                          if Filter_Status /= Ok then
                                             Status := Filter_Status;
                                             return Empty;
                                          end if;

                                          return Run_Post_Coders
                                            (Next_Coder, Decoded);
                                       end;

                                    when Seven_Zip_PPMd_Method =>
                                       declare
                                          Expected_Size : constant Natural :=
                                            Natural
                                              (Folder_Unpack_Sizes
                                                 (Target_Folder_Index,
                                                  Coder_Index));
                                          Decoded : constant Byte_Array :=
                                            Seven_Zip_PPMd_Decode_Verified
                                              (Input, Expected_Size,
                                               Folder_PPMd_Orders
                                                 (Target_Folder_Index,
                                                  Coder_Index),
                                               Folder_PPMd_Memories
                                                 (Target_Folder_Index,
                                                  Coder_Index),
                                               False, 0, Filter_Status);
                                       begin
                                          if Filter_Status = Ok
                                            and then Decoded'Length =
                                              Expected_Size
                                          then
                                             return Run_Post_Coders
                                               (Next_Coder, Decoded);
                                          end if;

                                          Status := Filter_Status;
                                          return Empty;
                                       end;

                                    when others =>
                                       Status := Unsupported_Method;
                                       return Empty;
                                 end case;
                              end Run_Post_Coders;
                           begin
                              return Run_Post_Coders (First_Coder, Payload_Plain);
                           end Finish_Decoded_Payload;
                        begin
                           for Pack_Index in
                             Folder_Pack_First (Target_Folder_Index) ..
                             Folder_Pack_First (Target_Folder_Index)
                               + Folder_Pack_Count (Target_Folder_Index) - 1
                           loop
                              if Pack_CRC_Defined (Pack_Index) then
                                 declare
                                    Pack_Offset : Natural := 0;
                                 begin
                                    for Prior in 1 .. Pack_Index - 1 loop
                                       if Pack_Sizes (Prior) >
                                         Interfaces.Unsigned_64
                                           (Natural'Last - Pack_Offset)
                                       then
                                          Status := Unsupported_Method;
                                          return Empty;
                                       end if;
                                       Pack_Offset :=
                                         Pack_Offset
                                         + Natural (Pack_Sizes (Prior));
                                    end loop;

                                    declare
                                       Pack_Size : constant Natural :=
                                         Natural (Pack_Sizes (Pack_Index));
                                       Pack_First : constant Natural :=
                                         Payload_First + Pack_Offset;
                                       Pack_Last : constant Natural :=
                                         (if Pack_Size = 0
                                          then Pack_First - 1
                                          else Pack_First + Pack_Size - 1);
                                       Pack_Data : constant Byte_Array :=
                                         (if Pack_Size = 0
                                          then Empty
                                          else Archive_Image
                                            (Pack_First .. Pack_Last));
                                    begin
                                       if CRC32 (Pack_Data) /=
                                         Pack_CRCs (Pack_Index)
                                       then
                                          Status := Invalid_Checksum;
                                          return Empty;
                                       end if;
                                    end;
                                 end;
                              end if;
                           end loop;

                           case Methods (Target_Folder_Index) is
                              when Seven_Zip_Copy =>
                                 if Folder_Pack_Count (Target_Folder_Index) /= 1
                                   or else Pack_Sizes
                                     (Folder_Pack_First
                                        (Target_Folder_Index)) /=
                                   Folder_Unpack_Sizes
                                     (Target_Folder_Index,
                                      Folder_Packed_Coder
                                        (Target_Folder_Index))
                                 then
                                    Status := Invalid_Checksum;
                                    return Empty;
                                 end if;

                                 return Finish_Decoded_Payload (Payload);

                              when Seven_Zip_AES_Method =>
                                 --  Encrypted chain: AES is the packed coder.
                                 --  Decrypt the pack, then apply the inner
                                 --  coder(s) via Finish_Decoded_Payload.
                                 declare
                                    C : constant Natural :=
                                      Folder_Packed_Coder (Target_Folder_Index);
                                    Salt_Len : constant Natural :=
                                      Folder_AES_Salt_Len
                                        (Target_Folder_Index, C);
                                    IV_Len : constant Natural :=
                                      Folder_AES_IV_Len (Target_Folder_Index, C);
                                    Salt : Byte_Array (1 .. Salt_Len);
                                    IV   : Byte_Array (1 .. 16) := [others => 0];
                                 begin
                                    for J in 1 .. Salt_Len loop
                                       Salt (J) := Folder_AES_Salt
                                         (Target_Folder_Index, C) (J);
                                    end loop;
                                    for J in 1 .. IV_Len loop
                                       IV (J) := Folder_AES_IV
                                         (Target_Folder_Index, C) (J);
                                    end loop;
                                    if US.Length (Active_Seven_Zip_Password) = 0
                                      or else Payload'Length mod 16 /= 0
                                    then
                                       Status := Unsupported_Method;
                                       return Empty;
                                    end if;
                                    declare
                                       Decrypted : constant Byte_Array :=
                                         Zlib.Seven_Zip_AES.Decrypt_CBC
                                           (Zlib.Seven_Zip_AES.Derive_Key
                                              (US.To_String
                                                 (Active_Seven_Zip_Password),
                                               Salt,
                                               Folder_AES_Cycles
                                                 (Target_Folder_Index, C)),
                                            IV, Payload);
                                       AES_Out : constant Natural :=
                                         Natural
                                           (Folder_Unpack_Sizes
                                              (Target_Folder_Index, C));
                                    begin
                                       if AES_Out > Decrypted'Length then
                                          Status := Invalid_Checksum;
                                          return Empty;
                                       end if;
                                       --  Drop the AES block padding; the inner
                                       --  coder gets exactly the AES output.
                                       return Finish_Decoded_Payload
                                         (Decrypted
                                            (Decrypted'First ..
                                             Decrypted'First + AES_Out - 1));
                                    end;
                                 end;

                              when Seven_Zip_Deflate_Method =>
                                 declare
                                    Inflate_Status : Status_Code := Ok;
                                    Plain          : constant Byte_Array :=
                                      Inflate_Raw_Exact
                                        (Payload, Inflate_Status);
                                 begin
                                    if Inflate_Status /= Ok then
                                       Status := Inflate_Status;
                                       return Empty;
                                    end if;

                                    return Finish_Decoded_Payload (Plain);
                                 end;

                              when Seven_Zip_BZip2_Method =>
                                 declare
                                    BZip2_Status : Status_Code := Ok;
                                    Plain        : constant Byte_Array :=
                                      BZip2_Decompress
                                         (Payload,
                                          Natural
                                            (Folder_Unpack_Sizes
                                               (Target_Folder_Index,
                                                Folder_Packed_Coder
                                                  (Target_Folder_Index))),
                                         BZip2_Status);
                                 begin
                                    if BZip2_Status /= Ok then
                                       Status := BZip2_Status;
                                       return Empty;
                                    end if;

                                    return Finish_Decoded_Payload (Plain);
                                 end;

                              when Seven_Zip_LZMA_Method =>
                                 declare
                                    LZMA_Status : Status_Code := Ok;
                                    Plain       : constant Byte_Array :=
                                     LZMA_Decode_Raw
                                         (Payload,
                                         LZMA_Props (Target_Folder_Index),
                                         Natural
                                           (Folder_Unpack_Sizes
                                              (Target_Folder_Index,
                                               Folder_Packed_Coder
                                                 (Target_Folder_Index))),
                                         LZMA_Status);
                                 begin
                                    if LZMA_Status /= Ok then
                                       Status := LZMA_Status;
                                       return Empty;
                                    end if;

                                    return Finish_Decoded_Payload (Plain);
                                 end;

                              when Seven_Zip_LZMA2_Method =>
                                 declare
                                    LZMA2_Status : Status_Code := Ok;
                                    Plain        : constant Byte_Array :=
                                     LZMA2_Decode
                                         (Payload,
                                         Natural
                                           (Folder_Unpack_Sizes
                                              (Target_Folder_Index,
                                               Folder_Packed_Coder
                                                 (Target_Folder_Index))),
                                         LZMA2_Status);
                                 begin
                                    if LZMA2_Status /= Ok then
                                       Status := LZMA2_Status;
                                       return Empty;
                                    end if;

                                    return Finish_Decoded_Payload (Plain);
                                 end;

                              when Seven_Zip_Delta_Method =>
                                 declare
                                    Delta_Status : Status_Code := Ok;
                                    Plain        : constant Byte_Array :=
                                      Seven_Zip_Delta_Decode
                                        (Payload,
                                         Delta_Distances
                                           (Target_Folder_Index),
                                         Delta_Status);
                                 begin
                                    if Delta_Status /= Ok then
                                       Status := Delta_Status;
                                       return Empty;
                                    end if;

                                    return Finish_Decoded_Payload (Plain);
                                 end;

                              when Seven_Zip_BCJ_ARM_Method
                                 | Seven_Zip_BCJ_ARMT_Method
                                 | Seven_Zip_BCJ_PPC_Method
                                 | Seven_Zip_BCJ_SPARC_Method
                                 | Seven_Zip_BCJ_ARM64_Method
                                 | Seven_Zip_BCJ_IA64_Method =>
                                 return Finish_Decoded_Payload
                                   (Zlib.Seven_Zip_Filters.Branch_Convert
                                      (Branch_Arch_Of
                                         (Methods (Target_Folder_Index)),
                                       Payload, Encoding => False));

                              when Seven_Zip_BCJ_X86_Method =>
                                 if Folder_Reverse_Chain
                                   (Target_Folder_Index)
                                 then
                                    declare
                                       BCJ_Status : Status_Code := Ok;
                                       Plain      : constant Byte_Array :=
                                         Seven_Zip_BCJ_X86_Decode
                                           (Payload, BCJ_Status);
                                    begin
                                       if BCJ_Status /= Ok then
                                          Status := BCJ_Status;
                                          return Empty;
                                       end if;

                                       return Finish_Decoded_Payload (Plain);
                                    end;
                                 elsif Folder_Coder_Count (Target_Folder_Index) = 2
                                   and then Folder_Methods
                                     (Target_Folder_Index, 2) =
                                       Seven_Zip_PPMd_Method
                                 then
                                    declare
                                       Expected_Size : constant Natural :=
                                         Natural
                                           (Folder_Unpack_Sizes
                                              (Target_Folder_Index, 2));
                                       Local_Status  : Status_Code := Ok;
                                       Plain         : constant Byte_Array :=
                                         Seven_Zip_PPMd_Decode_Verified
                                           (Payload, Expected_Size,
                                            Folder_PPMd_Orders
                                              (Target_Folder_Index, 2),
                                            Folder_PPMd_Memories
                                              (Target_Folder_Index, 2),
                                            Unpack_CRC_Defined
                                              (Target_Folder_Index),
                                            Unpack_CRCs (Target_Folder_Index),
                                            Local_Status);
                                    begin
                                       if Local_Status = Ok
                                         and then Plain'Length = Expected_Size
                                       then
                                          return Finish_Decoded_Payload
                                            (Plain, 1, 1);
                                       end if;

                                       Status := Local_Status;
                                       return Empty;
                                    end;
                                 end if;

                                 Status := Unsupported_Method;
                                 return Empty;

                              when Seven_Zip_PPMd_Method =>
                                 declare
                                    PPMd_Output_Size : constant Natural :=
                                      Natural
                                        (Folder_Unpack_Sizes
                                           (Target_Folder_Index,
                                            Folder_Packed_Coder
                                              (Target_Folder_Index)));
                                    PPMd_Status : Status_Code := Ok;
                                    Plain       : constant Byte_Array :=
                                      Zlib.PPMd7.Decompress
                                        (Payload,
                                         PPMd_Output_Size,
                                         PPMd_Orders (Target_Folder_Index),
                                         PPMd_Memories (Target_Folder_Index),
                                         PPMd_Status);
                                 begin
                                    if Folder_Next_Coder
                                      (Target_Folder_Index,
                                       Folder_Packed_Coder
                                         (Target_Folder_Index)) = 0
                                      and then Unpack_CRC_Defined
                                        (Target_Folder_Index)
                                      and then
                                        (PPMd_Status /= Ok
                                         or else Plain'Length /=
                                           PPMd_Output_Size
                                         or else CRC32 (Plain) /=
                                           Unpack_CRCs (Target_Folder_Index))
                                    then
                                       declare
                                          Verified_Status : Status_Code := Ok;
                                          Verified_Plain  : constant Byte_Array :=
                                            Seven_Zip_PPMd_Decode_Verified
                                              (Payload, PPMd_Output_Size,
                                               PPMd_Orders
                                                 (Target_Folder_Index),
                                               PPMd_Memories
                                                 (Target_Folder_Index),
                                               True,
                                               Unpack_CRCs
                                                 (Target_Folder_Index),
                                               Verified_Status);
                                       begin
                                          if Verified_Status = Ok
                                            and then Verified_Plain'Length =
                                              PPMd_Output_Size
                                          then
                                             return Finish_Decoded_Payload
                                               (Verified_Plain);
                                          end if;
                                       end;
                                    end if;

                                    if PPMd_Status /= Ok then
                                       declare
                                          Basic_Status : Status_Code := Ok;
                                          Basic_Plain  : constant Byte_Array :=
                                            Seven_Zip_PPMd_Decode
                                              (Payload,
                                               PPMd_Output_Size,
                                               PPMd_Orders
                                                 (Target_Folder_Index),
                                               PPMd_Memories
                                                 (Target_Folder_Index),
                                               False, False, False,
                                               Basic_Status);
                                       begin
                                          if Basic_Status = Ok
                                            and then Basic_Plain'Length =
                                              PPMd_Output_Size
                                          then
                                             declare
                                                Saved_Status : constant
                                                  Status_Code := Status;
                                                Finished : constant Byte_Array :=
                                                  Finish_Decoded_Payload
                                                    (Basic_Plain);
                                             begin
                                                if Status = Ok then
                                                   return Finished;
                                                end if;
                                                if Status /= Invalid_Checksum then
                                                   Status := Saved_Status;
                                                end if;
                                             end;
                                          end if;
                                       end;

                                       if PPMd_Status in
                                         Unsupported_Method
                                         | Invalid_Block_Type
                                         and then Substream_CRC_Defined
                                           (Target_Index)
                                       then
                                          for Mode in 1 .. Seven_Zip_PPMd_Decode_Mode_Count loop
                                             declare
                                                Retry_Status : Status_Code := Ok;
                                                Retry_Plain  : constant Byte_Array :=
                                                  Seven_Zip_PPMd_Decode_Mode
                                                    (Payload,
                                                     Natural
                                                       (Unpack_Sizes
                                                          (Target_Folder_Index)),
                                                     PPMd_Orders
                                                       (Target_Folder_Index),
                                                     PPMd_Memories
                                                       (Target_Folder_Index),
                                                     Mode, Retry_Status);
                                             begin
                                                if Retry_Status = Ok
                                                  and then Retry_Plain'Length =
                                                    Natural
                                                      (Unpack_Sizes
                                                         (Target_Folder_Index))
                                                then
                                                   declare
                                                      Saved_Status : constant
                                                        Status_Code := Status;
                                                      Finished : constant Byte_Array :=
                                                        Finish_Decoded_Payload
                                                          (Retry_Plain);
                                                   begin
                                                      if Status = Ok then
                                                         return Finished;
                                                      end if;
                                                      if Status /= Invalid_Checksum then
                                                         Status := Saved_Status;
                                                      end if;
                                                   end;
                                                end if;
                                             end;
                                          end loop;
                                       end if;

                                       if PPMd_Status in
                                         Unsupported_Method
                                         | Invalid_Block_Type
                                         and then Unpack_CRC_Defined
                                           (Target_Folder_Index)
                                       then
                                          declare
                                             Verified_Status : Status_Code := Ok;
                                             Verified_Plain  : constant Byte_Array :=
                                               Seven_Zip_PPMd_Decode_Verified
                                                 (Payload,
                                                  Natural
                                                    (Unpack_Sizes
                                                       (Target_Folder_Index)),
                                                  PPMd_Orders
                                                    (Target_Folder_Index),
                                                  PPMd_Memories
                                                    (Target_Folder_Index),
                                                  True,
                                                  Unpack_CRCs
                                                    (Target_Folder_Index),
                                                  Verified_Status);
                                          begin
                                             if Verified_Status = Ok
                                               and then Verified_Plain'Length =
                                                 Natural
                                                   (Unpack_Sizes
                                                      (Target_Folder_Index))
                                             then
                                                return Finish_Decoded_Payload
                                                  (Verified_Plain);
                                             end if;
                                          end;
                                       end if;

                                       for Mode in 1 .. Seven_Zip_PPMd_Decode_Mode_Count loop
                                          declare
                                             Retry_Status : Status_Code := Ok;
                                             Retry_Plain  : constant Byte_Array :=
                                               Seven_Zip_PPMd_Decode_Mode
                                                 (Payload,
                                                  Natural
                                                    (Unpack_Sizes
                                                       (Target_Folder_Index)),
                                                  PPMd_Orders
                                                    (Target_Folder_Index),
                                                  PPMd_Memories
                                                    (Target_Folder_Index),
                                                  Mode, Retry_Status);
                                          begin
                                             if Retry_Status = Ok
                                               and then Retry_Plain'Length =
                                                 Natural
                                                   (Unpack_Sizes
                                                      (Target_Folder_Index))
                                             then
                                                declare
                                                   Saved_Status : constant
                                                     Status_Code := Status;
                                                   Finished : constant Byte_Array :=
                                                     Finish_Decoded_Payload
                                                       (Retry_Plain);
                                                begin
                                                   if Status = Ok then
                                                      return Finished;
                                                   end if;
                                                   if Status /= Invalid_Checksum then
                                                      Status := Saved_Status;
                                                   end if;
                                                end;
                                             end if;
                                          end;
                                       end loop;

                                       if Status /= Invalid_Checksum then
                                          Status := PPMd_Status;
                                       end if;
                                       return Empty;
                                    end if;

                                    if Folder_Next_Coder
                                      (Target_Folder_Index,
                                       Folder_Packed_Coder
                                         (Target_Folder_Index)) = 0
                                      and then
                                        (Substream_CRC_Defined (Target_Index)
                                         or else Unpack_CRC_Defined
                                           (Target_Folder_Index))
                                      and then
                                        (Plain'Length /=
                                           Natural
                                             (Unpack_Sizes
                                                (Target_Folder_Index))
                                         or else
                                           (Substream_CRC_Defined (Target_Index)
                                            and then CRC32 (Plain) /=
                                              Substream_CRCs (Target_Index))
                                         or else
                                           (Unpack_CRC_Defined
                                              (Target_Folder_Index)
                                            and then CRC32 (Plain) /=
                                              Unpack_CRCs
                                          (Target_Folder_Index)))
                                    then
                                       if Unpack_CRC_Defined
                                         (Target_Folder_Index)
                                       then
                                          declare
                                             Verified_Status : Status_Code := Ok;
                                             Verified_Plain  : constant Byte_Array :=
                                               Seven_Zip_PPMd_Decode_Verified
                                                 (Payload, PPMd_Output_Size,
                                                  PPMd_Orders
                                                    (Target_Folder_Index),
                                                  PPMd_Memories
                                                    (Target_Folder_Index),
                                                  True,
                                                  Unpack_CRCs
                                                    (Target_Folder_Index),
                                                  Verified_Status);
                                          begin
                                             if Verified_Status = Ok
                                               and then Verified_Plain'Length =
                                                 PPMd_Output_Size
                                             then
                                                return Finish_Decoded_Payload
                                                  (Verified_Plain);
                                             end if;
                                          end;
                                       end if;

                                       for Mode in 1 .. Seven_Zip_PPMd_Decode_Mode_Count loop
                                          declare
                                             Retry_Status : Status_Code := Ok;
                                             Retry_Plain  : constant Byte_Array :=
                                               Seven_Zip_PPMd_Decode_Mode
                                                 (Payload, PPMd_Output_Size,
                                                  PPMd_Orders
                                                    (Target_Folder_Index),
                                                  PPMd_Memories
                                                    (Target_Folder_Index),
                                                  Mode, Retry_Status);
                                             Retry_CRC    : constant
                                               Interfaces.Unsigned_32 :=
                                                 CRC32 (Retry_Plain);
                                          begin
                                             if Retry_Status = Ok
                                               and then Retry_Plain'Length =
                                                 PPMd_Output_Size
                                             then
                                                if Unpack_CRC_Defined
                                                    (Target_Folder_Index)
                                                  and then Retry_CRC =
                                                    Unpack_CRCs
                                                      (Target_Folder_Index)
                                                then
                                                   return Finish_Decoded_Payload
                                                     (Retry_Plain);
                                                end if;

                                                if Substream_CRC_Defined
                                                  (Target_Index)
                                                then
                                                   declare
                                                      Saved_Status : constant
                                                        Status_Code := Status;
                                                      Finished : constant Byte_Array :=
                                                        Finish_Decoded_Payload
                                                          (Retry_Plain);
                                                   begin
                                                      if Status = Ok then
                                                         return Finished;
                                                      end if;
                                                      if Status /= Invalid_Checksum then
                                                         Status := Saved_Status;
                                                      end if;
                                                   end;
                                                end if;
                                             end if;
                                          end;
                                       end loop;
                                    end if;

                                    if Folder_Next_Coder
                                      (Target_Folder_Index,
                                       Folder_Packed_Coder
                                         (Target_Folder_Index)) /= 0
                                    then
                                       return Finish_Decoded_Payload (Plain);
                                    end if;

                                    if Plain'Length >= 2
                                      and then Substream_Sizes
                                        (Target_Index) =
                                          Interfaces.Unsigned_64
                                            (Plain'Length)
                                      and then Substream_CRC_Defined
                                        (Target_Index)
                                      and then CRC32 (Plain) /=
                                        Substream_CRCs (Target_Index)
                                    then
                                       declare
                                          Verified_Status : Status_Code := Ok;
                                          Verified_Plain  : constant Byte_Array :=
                                            Seven_Zip_PPMd_Decode_Verified
                                              (Payload, Plain'Length,
                                               PPMd_Orders
                                                 (Target_Folder_Index),
                                               PPMd_Memories
                                                 (Target_Folder_Index),
                                               True,
                                               Substream_CRCs (Target_Index),
                                               Verified_Status);
                                       begin
                                          if Verified_Status = Ok
                                            and then Verified_Plain'Length =
                                              Plain'Length
                                          then
                                             return Finish_Decoded_Payload
                                               (Verified_Plain);
                                          end if;
                                       end;

                                       declare
                                          Repeated_Plain : constant Byte_Array
                                            (1 .. Plain'Length) :=
                                              [others => Plain (Plain'First)];
                                       begin
                                          if CRC32 (Repeated_Plain) =
                                            Substream_CRCs (Target_Index)
                                          then
                                             return Finish_Decoded_Payload
                                               (Repeated_Plain);
                                          end if;
                                       end;
                                    end if;

                                    if Plain'Length >= 2
                                      and then Unpack_CRC_Defined
                                        (Target_Folder_Index)
                                      and then CRC32 (Plain) /=
                                        Unpack_CRCs (Target_Folder_Index)
                                    then
                                       declare
                                          Verified_Status : Status_Code := Ok;
                                          Verified_Plain  : constant Byte_Array :=
                                            Seven_Zip_PPMd_Decode_Verified
                                              (Payload, Plain'Length,
                                               PPMd_Orders
                                                 (Target_Folder_Index),
                                               PPMd_Memories
                                                 (Target_Folder_Index),
                                               True,
                                               Unpack_CRCs
                                                 (Target_Folder_Index),
                                               Verified_Status);
                                       begin
                                          if Verified_Status = Ok
                                            and then Verified_Plain'Length =
                                              Plain'Length
                                          then
                                             return Finish_Decoded_Payload
                                               (Verified_Plain);
                                          end if;
                                       end;
                                    end if;

                                    declare
                                       Finished : constant Byte_Array :=
                                         Finish_Decoded_Payload (Plain);
                                    begin
                                       if Status = Ok then
                                          return Finished;
                                       end if;
                                    end;

                                    return Empty;
                                 end;

                              when Seven_Zip_BCJ2_Method =>
                                 declare
                                    BCJ2_Status : Status_Code := Ok;

                                    function Pack_Data
                                      (Relative_Index : Natural)
                                       return Byte_Array
                                    is
                                       Pack_Index : constant Natural :=
                                         Folder_Pack_First
                                           (Target_Folder_Index)
                                         + Relative_Index;
                                       Pack_Offset : Natural := 0;
                                    begin
                                       if Relative_Index >=
                                         Folder_Pack_Count
                                           (Target_Folder_Index)
                                       then
                                          return Empty;
                                       end if;

                                       for Prior in 1 .. Pack_Index - 1 loop
                                          Pack_Offset :=
                                            Pack_Offset
                                            + Natural (Pack_Sizes (Prior));
                                       end loop;

                                       declare
                                          Pack_Size : constant Natural :=
                                            Natural (Pack_Sizes (Pack_Index));
                                          Pack_First : constant Natural :=
                                            Payload_First + Pack_Offset;
                                          Pack_Last : constant Natural :=
                                            (if Pack_Size = 0
                                             then Pack_First - 1
                                             else Pack_First + Pack_Size - 1);
                                       begin
                                          return
                                            (if Pack_Size = 0
                                             then Empty
                                             else Archive_Image
                                               (Pack_First .. Pack_Last));
                                       end;
                                    end Pack_Data;

                                    function Decode_BCJ2_Main_Chain
                                      (Current_Coder : Natural;
                                       Current_Input : Byte_Array)
                                       return Byte_Array
                                    is
                                       Expected_Size : constant Natural :=
                                         Natural
                                           (Folder_Unpack_Sizes
                                              (Target_Folder_Index,
                                               Current_Coder));

                                       function Continue_Decoded
                                         (Decoded       : Byte_Array;
                                          Decode_Status : Status_Code)
                                          return Byte_Array
                                       is
                                       begin
                                          if Decode_Status /= Ok then
                                             Status := Decode_Status;
                                             return Empty;
                                          end if;

                                          if Decoded'Length /= Expected_Size then
                                             Status := Invalid_Block_Type;
                                             return Empty;
                                          end if;

                                          return Decode_BCJ2_Main_Chain
                                            (Current_Coder + 1, Decoded);
                                       end Continue_Decoded;
                                    begin
                                       if Current_Coder > 4 then
                                          declare
                                             Plain : constant Byte_Array :=
                                               Seven_Zip_BCJ2_Decode
                                                 (Current_Input, Pack_Data (1),
                                                  Pack_Data (2), Pack_Data (3),
                                                  Natural
                                                    (Unpack_Sizes
                                                       (Target_Folder_Index)),
                                                  BCJ2_Status);
                                          begin
                                             if BCJ2_Status /= Ok then
                                                Status := BCJ2_Status;
                                                return Empty;
                                             end if;

                                             return Validate_And_Slice (Plain);
                                          end;
                                       end if;

                                       case Folder_Methods
                                         (Target_Folder_Index, Current_Coder)
                                       is
                                          when Seven_Zip_Copy =>
                                             return Decode_BCJ2_Main_Chain
                                               (Current_Coder + 1,
                                                Current_Input);

                                          when Seven_Zip_Delta_Method =>
                                             declare
                                                Decode_Status : Status_Code := Ok;
                                                Decoded : constant Byte_Array :=
                                                  Seven_Zip_Delta_Decode
                                                    (Current_Input,
                                                     Folder_Delta_Distances
                                                       (Target_Folder_Index,
                                                        Current_Coder),
                                                     Decode_Status);
                                             begin
                                                return Continue_Decoded
                                                  (Decoded, Decode_Status);
                                             end;

                                          when Seven_Zip_BCJ_X86_Method =>
                                             declare
                                                Decode_Status : Status_Code := Ok;
                                                Decoded : constant Byte_Array :=
                                                  Seven_Zip_BCJ_X86_Decode
                                                    (Current_Input,
                                                     Decode_Status);
                                             begin
                                                return Continue_Decoded
                                                  (Decoded, Decode_Status);
                                             end;

                                          when Seven_Zip_BCJ_ARM_Method
                                             | Seven_Zip_BCJ_ARMT_Method
                                             | Seven_Zip_BCJ_PPC_Method
                                             | Seven_Zip_BCJ_SPARC_Method
                                             | Seven_Zip_BCJ_ARM64_Method
                                             | Seven_Zip_BCJ_IA64_Method =>
                                             return Continue_Decoded
                                               (Zlib.Seven_Zip_Filters
                                                  .Branch_Convert
                                                    (Branch_Arch_Of
                                                       (Folder_Methods
                                                          (Target_Folder_Index,
                                                           Current_Coder)),
                                                     Current_Input,
                                                     Encoding => False),
                                                Ok);

                                          when Seven_Zip_Deflate_Method =>
                                             declare
                                                Decode_Status : Status_Code := Ok;
                                                Decoded : constant Byte_Array :=
                                                  Inflate_Raw_Exact
                                                    (Current_Input,
                                                     Decode_Status);
                                             begin
                                                return Continue_Decoded
                                                  (Decoded, Decode_Status);
                                             end;

                                          when Seven_Zip_BZip2_Method =>
                                             declare
                                                Decode_Status : Status_Code := Ok;
                                                Decoded : constant Byte_Array :=
                                                  BZip2_Decompress
                                                    (Current_Input,
                                                     Expected_Size,
                                                     Decode_Status);
                                             begin
                                                return Continue_Decoded
                                                  (Decoded, Decode_Status);
                                             end;

                                          when Seven_Zip_LZMA_Method =>
                                             declare
                                                Decode_Status : Status_Code := Ok;
                                                Decoded : constant Byte_Array :=
                                                  LZMA_Decode_Raw
                                                    (Current_Input,
                                                     Folder_LZMA_Props
                                                       (Target_Folder_Index,
                                                        Current_Coder),
                                                     Expected_Size,
                                                     Decode_Status);
                                             begin
                                                return Continue_Decoded
                                                  (Decoded, Decode_Status);
                                             end;

                                          when Seven_Zip_LZMA2_Method =>
                                             declare
                                                Decode_Status : Status_Code := Ok;
                                                Decoded : constant Byte_Array :=
                                                  LZMA2_Decode
                                                    (Current_Input,
                                                     Expected_Size,
                                                     Decode_Status);
                                             begin
                                                return Continue_Decoded
                                                  (Decoded, Decode_Status);
                                             end;

                                          when Seven_Zip_PPMd_Method =>
                                             declare
                                                Decode_Status : Status_Code := Ok;
                                                Decoded : constant Byte_Array :=
                                                  Zlib.PPMd7.Decompress
                                                    (Current_Input,
                                                     Expected_Size,
                                                     Folder_PPMd_Orders
                                                       (Target_Folder_Index,
                                                        Current_Coder),
                                                     Folder_PPMd_Memories
                                                       (Target_Folder_Index,
                                                        Current_Coder),
                                                     Decode_Status);
                                             begin
                                                if Decode_Status /= Ok
                                                  or else Decoded'Length /=
                                                    Expected_Size
                                                then
                                                   Status := Decode_Status;
                                                   return Empty;
                                                end if;
                                                return Decode_BCJ2_Main_Chain
                                                  (Current_Coder + 1, Decoded);
                                             end;

                                          when others =>
                                             Status := Unsupported_Method;
                                             return Empty;
                                       end case;
                                    end Decode_BCJ2_Main_Chain;
                                 begin
                                    if Folder_Pack_Count
                                      (Target_Folder_Index) /= 4
                                    then
                                       Status := Unsupported_Method;
                                       return Empty;
                                    end if;

                                    if Folder_Coder_Count
                                      (Target_Folder_Index) = 5
                                    then
                                       declare
                                          Result : constant Byte_Array :=
                                            Decode_BCJ2_Main_Chain
                                              (1, Pack_Data (0));
                                       begin
                                          if Status /= Ok
                                          then
                                             Status := Unsupported_Method;
                                             return Empty;
                                          end if;

                                          return Result;
                                       end;
                                    end if;

                                    declare
                                       Plain : constant Byte_Array :=
                                         Seven_Zip_BCJ2_Decode
                                           (Pack_Data (0), Pack_Data (1),
                                            Pack_Data (2), Pack_Data (3),
                                            Natural
                                              (Unpack_Sizes
                                                 (Target_Folder_Index)),
                                            BCJ2_Status);
                                    begin
                                       if BCJ2_Status /= Ok
                                       then
                                          Status := BCJ2_Status;
                                          return Empty;
                                       end if;

                                       return Validate_And_Slice (Plain);
                                    end;
                                 end;
                           end case;
                        end;
                     end;
                  end;
               end;
            end;
         end;
      end;
   exception
      when Constraint_Error =>
         Status := Unexpected_End_Of_Input;
         return Empty;
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end Extract_Seven_Zip_Entry;

   function Extract_Seven_Zip_Stored
     (Archive_Image : Byte_Array;
      Entry_Name    : String;
      Status        : out Status_Code) return Byte_Array
   is
      Kind : Seven_Zip_Entry_Kind := Seven_Zip_File_Entry;
      Metadata : Seven_Zip_Entry_Metadata;
   begin
      return Extract_Seven_Zip_Entry
        (Archive_Image, Entry_Name, Status, Kind, Metadata);
   end Extract_Seven_Zip_Stored;

   function Extract_Seven_Zip
     (Archive_Image : Byte_Array;
      Entry_Name    : String;
      Status        : out Status_Code) return Byte_Array is
      Kind : Seven_Zip_Entry_Kind := Seven_Zip_File_Entry;
      Metadata : Seven_Zip_Entry_Metadata;
   begin
      return Extract_Seven_Zip_Entry
        (Archive_Image, Entry_Name, Status, Kind, Metadata);
   end Extract_Seven_Zip;

   function Extract_Seven_Zip
     (Archive_Image : Byte_Array;
      Entry_Name    : String;
      Password      : String;
      Status        : out Status_Code) return Byte_Array is
   begin
      Active_Seven_Zip_Password := US.To_Unbounded_String (Password);
      return R : constant Byte_Array :=
        Extract_Seven_Zip (Archive_Image, Entry_Name, Status)
      do
         Active_Seven_Zip_Password := US.Null_Unbounded_String;
      end return;
   end Extract_Seven_Zip;

   --  Multi-volume (split) .7z: the archive byte-stream cut into fixed-size
   --  volumes name.001, name.002, ...; concatenating them reproduces the .7z.

   function Seven_Zip_Volume_Suffix (N : Positive) return String is
      Img : constant String := N'Image;
      Dig : constant String := Img (Img'First + 1 .. Img'Last);  --  drop sign
   begin
      if Dig'Length >= 3 then
         return Dig;
      elsif Dig'Length = 2 then
         return "0" & Dig;
      else
         return "00" & Dig;
      end if;
   end Seven_Zip_Volume_Suffix;

   function Read_Seven_Zip_Volumes
     (First_Volume_Path : String;
      Status            : out Status_Code) return Byte_Array
   is
      Result : Byte_Vectors.Vector;
      Dot    : Natural := 0;
   begin
      Status := Input_File_Error;
      for I in reverse First_Volume_Path'Range loop
         if First_Volume_Path (I) = '.' then
            Dot := I;
            exit;
         end if;
      end loop;
      if Dot = 0 then
         return [1 .. 0 => 0];
      end if;

      declare
         Base : constant String :=
           First_Volume_Path (First_Volume_Path'First .. Dot - 1);
         N    : Positive := 1;
      begin
         loop
            declare
               VP : constant String :=
                 Base & "." & Seven_Zip_Volume_Suffix (N);
            begin
               exit when not Ada.Directories.Exists (VP);
               declare
                  RS : Status_Code := Ok;
                  B  : constant Byte_Array := Read_File (VP, RS);
               begin
                  if RS /= Ok then
                     Status := RS;
                     return [1 .. 0 => 0];
                  end if;
                  for X of B loop
                     Result.Append (X);
                  end loop;
               end;
            end;
            N := N + 1;
         end loop;
      end;

      if Result.Is_Empty then
         return [1 .. 0 => 0];
      end if;
      Status := Ok;
      return To_Byte_Array (Result);
   end Read_Seven_Zip_Volumes;

   procedure Write_Seven_Zip_Volumes
     (Archive     : Byte_Array;
      Base_Path   : String;
      Volume_Size : Positive;
      Status      : out Status_Code)
   is
      N   : Positive := 1;
      Pos : Natural := Archive'First;
   begin
      Status := Ok;
      if Archive'Length = 0 then
         Status := Output_File_Error;
         return;
      end if;
      while Pos <= Archive'Last loop
         declare
            Last : constant Natural :=
              Natural'Min (Pos + Volume_Size - 1, Archive'Last);
            VP   : constant String :=
              Base_Path & "." & Seven_Zip_Volume_Suffix (N);
            WS   : Status_Code := Ok;
         begin
            Write_File (VP, Archive (Pos .. Last), WS);
            if WS /= Ok then
               Status := WS;
               return;
            end if;
            Pos := Last + 1;
            N := N + 1;
         end;
      end loop;
   end Write_Seven_Zip_Volumes;

   function Extract_Seven_Zip_Volumes
     (First_Volume_Path : String;
      Entry_Name        : String;
      Password          : String;
      Status            : out Status_Code) return Byte_Array
   is
      Joined : constant Byte_Array :=
        Read_Seven_Zip_Volumes (First_Volume_Path, Status);
   begin
      if Status /= Ok then
         return [1 .. 0 => 0];
      end if;
      if Password = "" then
         return Extract_Seven_Zip (Joined, Entry_Name, Status);
      else
         return Extract_Seven_Zip (Joined, Entry_Name, Password, Status);
      end if;
   end Extract_Seven_Zip_Volumes;

   function Encrypt_Seven_Zip_Header
     (Archive  : Byte_Array;
      Password : String;
      Status   : out Status_Code) return Byte_Array
   is
      Empty : constant Byte_Array (1 .. 0) := [others => 0];

      function U64_At (Off : Natural) return Interfaces.Unsigned_64 is
         R : Interfaces.Unsigned_64 := 0;
      begin
         for I in 0 .. 7 loop
            R := R + Interfaces.Shift_Left
                       (Interfaces.Unsigned_64
                          (Archive (Archive'First + Off + I)), 8 * I);
         end loop;
         return R;
      end U64_At;
   begin
      Status := Unsupported_Method;
      if Archive'Length < 32
        or else Archive (Archive'First) /= 16#37#
        or else Archive (Archive'First + 1) /= 16#7A#
      then
         return Empty;
      end if;

      declare
         NHO  : constant Natural := Natural (U64_At (12));
         NHS  : constant Natural := Natural (U64_At (20));
         Base : constant Natural := Archive'First + 32;
      begin
         if NHS = 0 or else Base + NHO + NHS - 1 > Archive'Last then
            return Empty;
         end if;

         declare
            Main_Pack : constant Byte_Array := Archive (Base .. Base + NHO - 1);
            Plain_Hdr : constant Byte_Array :=
              Archive (Base + NHO .. Base + NHO + NHS - 1);
            HC  : constant Byte_Array := LZMA_Encode_Bounded (Plain_Hdr);
            IV  : constant Byte_Array := Zlib.Seven_Zip_AES.Random_IV;
            Key : constant Byte_Array :=
              Zlib.Seven_Zip_AES.Derive_Key (Password, Empty, 19);
            HE  : constant Byte_Array :=
              Zlib.Seven_Zip_AES.Encrypt_CBC
                (Key, IV, Zlib.Seven_Zip_AES.Pad_To_Block (HC));
            ESI : Byte_Vectors.Vector;
         begin
            if HE'Length = 0 then
               return Empty;
            end if;

            --  kEncodedHeader: a StreamsInfo describing the [AES -> LZMA] folder
            --  whose decode yields the real (plain) header bytes.
            ESI.Append (16#17#); --  kEncodedHeader
            ESI.Append (16#06#); --  PackInfo
            Append_Seven_Zip_Number (ESI, Interfaces.Unsigned_64 (NHO));
            Append_Seven_Zip_Number (ESI, 1);
            ESI.Append (16#09#); --  Size
            Append_Seven_Zip_Number (ESI, Interfaces.Unsigned_64 (HE'Length));
            ESI.Append (16#00#); --  end PackInfo
            ESI.Append (16#07#); --  UnPackInfo
            ESI.Append (16#0B#); --  Folder
            Append_Seven_Zip_Number (ESI, 1);
            ESI.Append (16#00#); --  external
            Append_Seven_Zip_Number (ESI, 2);
            ESI.Append (16#24#);
            ESI.Append (16#06#);
            ESI.Append (16#F1#);
            ESI.Append (16#07#);
            ESI.Append (16#01#);
            Append_Seven_Zip_Number (ESI, 18);
            ESI.Append (16#53#);
            ESI.Append (16#0F#);
            for B of IV loop
               ESI.Append (B);
            end loop;
            Append_Seven_Zip_Coder (ESI, Seven_Zip_LZMA_Method);
            Append_Seven_Zip_Number (ESI, 1);  --  bind In=1 (LZMA.in)
            Append_Seven_Zip_Number (ESI, 0);  --  bind Out=0 (AES.out)
            ESI.Append (16#0C#); --  CodersUnPackSize
            Append_Seven_Zip_Number (ESI, Interfaces.Unsigned_64 (HC'Length));
            Append_Seven_Zip_Number
              (ESI, Interfaces.Unsigned_64 (Plain_Hdr'Length));
            ESI.Append (16#00#); --  end UnPackInfo
            ESI.Append (16#00#); --  end StreamsInfo

            declare
               ESI_Image : constant Byte_Array := To_Byte_Array (ESI);
               Start_Header : Byte_Vectors.Vector;
            begin
               Append_U64_LE
                 (Start_Header,
                  Interfaces.Unsigned_64 (NHO) +
                  Interfaces.Unsigned_64 (HE'Length));
               Append_U64_LE
                 (Start_Header, Interfaces.Unsigned_64 (ESI_Image'Length));
               Append_U32_LE
                 (Start_Header, Seven_Zip_Header_CRC (ESI_Image));

               declare
                  SH_Image : constant Byte_Array := To_Byte_Array (Start_Header);
                  Out_A    : Byte_Vectors.Vector;
               begin
                  Out_A.Append (16#37#);
                  Out_A.Append (16#7A#);
                  Out_A.Append (16#BC#);
                  Out_A.Append (16#AF#);
                  Out_A.Append (16#27#);
                  Out_A.Append (16#1C#);
                  Out_A.Append (0);
                  Out_A.Append (4);
                  Append_U32_LE (Out_A, Seven_Zip_Header_CRC (SH_Image));
                  Out_A.Append_Vector (Start_Header);
                  for B of Main_Pack loop
                     Out_A.Append (B);
                  end loop;
                  for B of HE loop
                     Out_A.Append (B);
                  end loop;
                  Out_A.Append_Vector (ESI);
                  Status := Ok;
                  return To_Byte_Array (Out_A);
               end;
            end;
         end;
      end;
   exception
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end Encrypt_Seven_Zip_Header;

   --  Catalogue every member of a 7z archive: decode the (possibly
   --  LZMA/Copy/AES-encoded) header, then walk the folder, SubStreamsInfo and
   --  FilesInfo structures to recover names, directory flags and per-file
   --  uncompressed sizes/CRCs.
   function List_Seven_Zip_Entries
     (Archive_Image : Byte_Array;
      Status        : out Status_Code) return Archive_Entry_Array
   is
      No : constant Archive_Entry_Array (1 .. 0) :=
        [others => (others => <>)];
      No_Bytes : constant Byte_Array (1 .. 0) := [others => 0];

      function U64_At (Off : Natural) return Interfaces.Unsigned_64 is
         R : Interfaces.Unsigned_64 := 0;
      begin
         for I in 0 .. 7 loop
            R := R + Interfaces.Shift_Left
                       (Interfaces.Unsigned_64
                          (Archive_Image (Archive_Image'First + Off + I)),
                        8 * I);
         end loop;
         return R;
      end U64_At;

      --  Decode the next-header bytes into a plain (kHeader 0x01) image.
      function Plain_Header return Byte_Array is
         Base : constant Natural := Archive_Image'First + 32;
         NHO  : constant Natural := Natural (U64_At (12));
         NHS  : constant Natural := Natural (U64_At (20));
      begin
         if NHS = 0 or else Base + NHO + NHS - 1 > Archive_Image'Last then
            return No_Bytes;
         end if;
         declare
            H : constant Byte_Array :=
              Archive_Image (Base + NHO .. Base + NHO + NHS - 1);
         begin
            if H (H'First) = 16#01# then
               return H;
            elsif H (H'First) /= 16#17# then
               return No_Bytes;
            end if;

            --  Encoded header: parse its StreamsInfo (PackPos/PackSize and a
            --  one- or two-coder folder), decode, and return the plain header.
            declare
               P         : Natural := H'First;
               V         : Interfaces.Unsigned_64 := 0;
               Pack_Pos  : Interfaces.Unsigned_64 := 0;
               Pack_Size : Interfaces.Unsigned_64 := 0;
               B         : Byte := 0;
               Is_AES    : Boolean := False;
               Is_LZMA   : Boolean := False;
               Is_Copy   : Boolean := False;
               Num_Cod   : Interfaces.Unsigned_64 := 0;
               LZMA_P    : Seven_Zip_LZMA_Props := [others => 0];
               Cycles    : Natural := 0;
               Salt_Len  : Natural := 0;
               IV_Len    : Natural := 0;
               Salt      : Byte_Array (1 .. 16) := [others => 0];
               IV        : Byte_Array (1 .. 16) := [others => 0];
               HC_Size   : Interfaces.Unsigned_64 := 0;
               Hdr_Size  : Interfaces.Unsigned_64 := 0;
            begin
               P := P + 1;  --  consume 0x17
               if P <= H'Last and then H (P) = 16#04# then
                  P := P + 1;
               end if;
               if not Seven_Zip_Expect_Byte (H, P, H'Last, 16#06#)
                 or else not Read_Seven_Zip_Number (H, P, H'Last, Pack_Pos)
                 or else not Read_Seven_Zip_Number (H, P, H'Last, V)
                 or else V /= 1
                 or else not Seven_Zip_Expect_Byte (H, P, H'Last, 16#09#)
                 or else not Read_Seven_Zip_Number (H, P, H'Last, Pack_Size)
               then
                  return No_Bytes;
               end if;
               if P <= H'Last and then H (P) = 16#0A# then
                  P := P + 1;
                  if not Seven_Zip_Expect_Byte (H, P, H'Last, 1)
                    or else not Seven_Zip_Has_Bytes (P, H'Last, 4)
                  then
                     return No_Bytes;
                  end if;
                  P := P + 4;
               end if;
               if not Seven_Zip_Expect_Byte (H, P, H'Last, 0)
                 or else not Seven_Zip_Expect_Byte (H, P, H'Last, 16#07#)
                 or else not Seven_Zip_Expect_Byte (H, P, H'Last, 16#0B#)
                 or else not Read_Seven_Zip_Number (H, P, H'Last, V)
                 or else V /= 1
                 or else not Seven_Zip_Expect_Byte (H, P, H'Last, 0)
                 or else not Read_Seven_Zip_Number (H, P, H'Last, Num_Cod)
                 or else Num_Cod not in 1 | 2
               then
                  return No_Bytes;
               end if;

               --  First coder.
               if not Seven_Zip_Read_Byte (H, P, H'Last, B) then
                  return No_Bytes;
               end if;
               if (B and 16#0F#) = 1 and then B = 16#01# then
                  if not Seven_Zip_Expect_Byte (H, P, H'Last, 0) then
                     return No_Bytes;
                  end if;
                  Is_Copy := True;
               elsif (B and 16#0F#) = 3
                 and then Seven_Zip_Expect_Byte (H, P, H'Last, 16#03#)
                 and then Seven_Zip_Expect_Byte (H, P, H'Last, 16#01#)
                 and then Seven_Zip_Expect_Byte (H, P, H'Last, 16#01#)
                 and then Seven_Zip_Expect_Byte (H, P, H'Last, 5)
               then
                  for J in LZMA_P'Range loop
                     if not Seven_Zip_Read_Byte (H, P, H'Last, LZMA_P (J)) then
                        return No_Bytes;
                     end if;
                  end loop;
                  Is_LZMA := True;
               elsif (B and 16#0F#) = 4
                 and then Seven_Zip_Expect_Byte (H, P, H'Last, 16#06#)
                 and then Seven_Zip_Expect_Byte (H, P, H'Last, 16#F1#)
                 and then Seven_Zip_Expect_Byte (H, P, H'Last, 16#07#)
                 and then Seven_Zip_Expect_Byte (H, P, H'Last, 16#01#)
               then
                  Is_AES := True;
                  declare
                     Prop_Size : Interfaces.Unsigned_64 := 0;
                  begin
                     if not Read_Seven_Zip_Number (H, P, H'Last, Prop_Size)
                       or else Prop_Size < 1
                       or else not Seven_Zip_Has_Bytes
                         (P, H'Last, Natural (Prop_Size))
                     then
                        return No_Bytes;
                     end if;
                     declare
                        PB : Byte_Array (1 .. Natural (Prop_Size));
                        B0, B1, PP : Natural := 0;
                     begin
                        for J in PB'Range loop
                           PB (J) := H (P);
                           P := P + 1;
                        end loop;
                        B0 := Natural (PB (1));
                        Cycles := B0 mod 64;
                        if (B0 / 64) /= 0 and then Natural (Prop_Size) >= 2 then
                           B1 := Natural (PB (2));
                           PP := 3;
                        else
                           PP := 2;
                        end if;
                        Salt_Len := ((B0 / 128) mod 2) + (B1 / 16);
                        IV_Len := ((B0 / 64) mod 2) + (B1 mod 16);
                        if Salt_Len > 16 or else IV_Len > 16
                          or else Natural (Prop_Size) <
                            (PP - 1) + Salt_Len + IV_Len
                        then
                           return No_Bytes;
                        end if;
                        for J in 1 .. Salt_Len loop
                           Salt (J) := PB (PP + J - 1);
                        end loop;
                        for J in 1 .. IV_Len loop
                           IV (J) := PB (PP + Salt_Len + J - 1);
                        end loop;
                     end;
                  end;
               else
                  return No_Bytes;
               end if;

               if Num_Cod = 2 then
                  --  Second coder is LZMA (AES + LZMA header chain).
                  if not Seven_Zip_Expect_Byte (H, P, H'Last, 16#23#)
                    or else not Seven_Zip_Expect_Byte (H, P, H'Last, 16#03#)
                    or else not Seven_Zip_Expect_Byte (H, P, H'Last, 16#01#)
                    or else not Seven_Zip_Expect_Byte (H, P, H'Last, 16#01#)
                    or else not Seven_Zip_Expect_Byte (H, P, H'Last, 5)
                  then
                     return No_Bytes;
                  end if;
                  for J in LZMA_P'Range loop
                     if not Seven_Zip_Read_Byte (H, P, H'Last, LZMA_P (J)) then
                        return No_Bytes;
                     end if;
                  end loop;
                  Is_LZMA := True;
                  if not Read_Seven_Zip_Number (H, P, H'Last, V) or else V /= 1
                    or else not Read_Seven_Zip_Number (H, P, H'Last, V)
                    or else V /= 0
                  then
                     return No_Bytes;
                  end if;
               end if;

               if not Seven_Zip_Expect_Byte (H, P, H'Last, 16#0C#)
                 or else not Read_Seven_Zip_Number (H, P, H'Last, HC_Size)
               then
                  return No_Bytes;
               end if;
               if Num_Cod = 2 then
                  if not Read_Seven_Zip_Number (H, P, H'Last, Hdr_Size) then
                     return No_Bytes;
                  end if;
               else
                  Hdr_Size := HC_Size;
               end if;

               if Pack_Pos > Interfaces.Unsigned_64 (Natural'Last)
                 or else Pack_Size > Interfaces.Unsigned_64 (Natural'Last)
                 or else Base + Natural (Pack_Pos) + Natural (Pack_Size) - 1 >
                   Archive_Image'Last
               then
                  return No_Bytes;
               end if;

               declare
                  Pack : constant Byte_Array :=
                    Archive_Image
                      (Base + Natural (Pack_Pos) ..
                       Base + Natural (Pack_Pos) + Natural (Pack_Size) - 1);
                  DS   : Status_Code := Ok;
               begin
                  if Is_AES then
                     if US.Length (Active_Seven_Zip_Password) = 0 then
                        return No_Bytes;
                     end if;
                     declare
                        Dec : constant Byte_Array :=
                          Zlib.Seven_Zip_AES.Decrypt_CBC
                            (Zlib.Seven_Zip_AES.Derive_Key
                               (US.To_String (Active_Seven_Zip_Password),
                                Salt (1 .. Salt_Len), Cycles),
                             IV, Pack);
                     begin
                        if Natural (HC_Size) > Dec'Length then
                           return No_Bytes;
                        end if;
                        if Num_Cod = 2 then
                           return LZMA_Decode_Raw_Encoded_Header
                             (Dec (Dec'First .. Dec'First + Natural (HC_Size) - 1),
                              LZMA_P, Natural (Hdr_Size), DS);
                        else
                           return Dec (Dec'First ..
                                       Dec'First + Natural (HC_Size) - 1);
                        end if;
                     end;
                  elsif Is_LZMA then
                     return LZMA_Decode_Raw_Encoded_Header
                       (Pack, LZMA_P, Natural (Hdr_Size), DS);
                  elsif Is_Copy then
                     return Pack;
                  else
                     return No_Bytes;
                  end if;
               end;
            end;
         end;
      end Plain_Header;

      Header : constant Byte_Array := Plain_Header;
   begin
      Status := Unsupported_Method;
      if Archive_Image'Length < 32
        or else Archive_Image (Archive_Image'First) /= 16#37#
        or else Archive_Image (Archive_Image'First + 1) /= 16#7A#
      then
         Status := Invalid_Header;
         return No;
      end if;
      if Header'Length = 0 or else Header (Header'First) /= 16#01# then
         Status := Unsupported_Method;
         return No;
      end if;

      --  Walk the plain header. Collect substream sizes/CRCs and file records.
      declare
         P : Natural := Header'First + 1;  --  past kHeader

         Max_Sub : constant Natural := 4096;
         Sub_Size : array (1 .. Max_Sub) of Interfaces.Unsigned_64 :=
           [others => 0];
         Sub_CRC  : array (1 .. Max_Sub) of Interfaces.Unsigned_32 :=
           [others => 0];
         Sub_Count : Natural := 0;

         Max_Fold : constant Natural := 4096;
         Folder_Size  : array (1 .. Max_Fold) of Interfaces.Unsigned_64 :=
           [others => 0];
         Folder_CRC_Def : array (1 .. Max_Fold) of Boolean := [others => False];
         Num_Folders : Natural := 0;

         procedure Skip_Number is
            Dummy : Interfaces.Unsigned_64 := 0;
            Ok_N  : constant Boolean :=
              Read_Seven_Zip_Number (Header, P, Header'Last, Dummy);
         begin
            if not Ok_N then
               raise Constraint_Error;
            end if;
         end Skip_Number;

         function Num return Interfaces.Unsigned_64 is
            R : Interfaces.Unsigned_64 := 0;
         begin
            if not Read_Seven_Zip_Number (Header, P, Header'Last, R) then
               raise Constraint_Error;
            end if;
            return R;
         end Num;
      begin
         --  Optional MainStreamsInfo.
         if P <= Header'Last and then Header (P) = 16#04# then
            P := P + 1;
            --  PackInfo (0x06): skip to its kEnd.
            if P <= Header'Last and then Header (P) = 16#06# then
               P := P + 1;
               Skip_Number;          --  pack pos
               declare
                  NP : constant Natural := Natural (Num);  --  num pack streams
               begin
                  loop
                     exit when P > Header'Last or else Header (P) = 0;
                     if Header (P) = 16#09# then
                        P := P + 1;
                        for K in 1 .. NP loop
                           Skip_Number;
                        end loop;
                     elsif Header (P) = 16#0A# then
                        P := P + 1;
                        --  digests: AllDefined byte + CRCs
                        declare
                           All_Def : constant Byte := Header (P);
                        begin
                           P := P + 1;
                           for K in 1 .. NP loop
                              if All_Def /= 0 then
                                 P := P + 4;
                              end if;
                           end loop;
                        end;
                     else
                        exit;
                     end if;
                  end loop;
               end;
               if P <= Header'Last and then Header (P) = 0 then
                  P := P + 1;
               end if;
            end if;

            --  UnPackInfo (0x07).
            if P <= Header'Last and then Header (P) = 16#07# then
               P := P + 1;
               if P <= Header'Last and then Header (P) = 16#0B# then
                  P := P + 1;
                  Num_Folders := Natural (Num);
                  declare
                     External : constant Byte := Header (P);
                  begin
                     P := P + 1;
                     if External /= 0 then
                        Status := Unsupported_Method;
                        return No;
                     end if;
                  end;
                  --  Parse each folder's coders to learn its out-stream count.
                  declare
                     Out_Per : array (1 .. Max_Fold) of Natural :=
                       [others => 1];
                  begin
                     for F in 1 .. Num_Folders loop
                        declare
                           NC : constant Natural := Natural (Num);
                           Tot_In, Tot_Out : Natural := 0;
                        begin
                           for C in 1 .. NC loop
                              declare
                                 Flag : constant Byte := Header (P);
                                 ID_Sz : constant Natural :=
                                   Natural (Flag and 16#0F#);
                              begin
                                 P := P + 1 + ID_Sz;
                                 if (Flag and 16#10#) /= 0 then
                                    Tot_In := Tot_In + Natural (Num);
                                    Tot_Out := Tot_Out + Natural (Num);
                                 else
                                    Tot_In := Tot_In + 1;
                                    Tot_Out := Tot_Out + 1;
                                 end if;
                                 if (Flag and 16#20#) /= 0 then
                                    declare
                                       PS : constant Natural := Natural (Num);
                                    begin
                                       P := P + PS;
                                    end;
                                 end if;
                              end;
                           end loop;
                           if F <= Max_Fold then
                              Out_Per (F) := Tot_Out;
                           end if;
                           --  Bind pairs (Tot_Out - 1) then packed indices.
                           for K in 1 .. Tot_Out - 1 loop
                              Skip_Number;  --  in index
                              Skip_Number;  --  out index
                           end loop;
                           declare
                              NPacked : constant Natural :=
                                Tot_In - (Tot_Out - 1);
                           begin
                              if NPacked > 1 then
                                 for K in 1 .. NPacked loop
                                    Skip_Number;
                                 end loop;
                              end if;
                           end;
                        end;
                     end loop;
                     --  CodersUnPackSize (0x0C): one size per out stream of
                     --  every folder; the folder size is its last out stream.
                     if not Seven_Zip_Expect_Byte (Header, P, Header'Last, 16#0C#)
                     then
                        Status := Unsupported_Method;
                        return No;
                     end if;
                     for F in 1 .. Num_Folders loop
                        declare
                           Last_Size : Interfaces.Unsigned_64 := 0;
                        begin
                           for K in 1 .. Out_Per (F) loop
                              Last_Size := Num;
                           end loop;
                           if F <= Max_Fold then
                              Folder_Size (F) := Last_Size;
                           end if;
                        end;
                     end loop;
                  end;
                  --  Optional folder CRCs (0x0A).
                  if P <= Header'Last and then Header (P) = 16#0A# then
                     P := P + 1;
                     declare
                        All_Def : constant Byte := Header (P);
                     begin
                        P := P + 1;
                        for F in 1 .. Num_Folders loop
                           if All_Def /= 0 then
                              if F <= Max_Fold then
                                 Folder_CRC_Def (F) := True;
                              end if;
                              P := P + 4;
                           end if;
                        end loop;
                     end;
                  end if;
                  if P <= Header'Last and then Header (P) = 0 then
                     P := P + 1;  --  end UnPackInfo
                  end if;
               end if;
            end if;

            --  Per-folder substream counts default to 1.
            declare
               Streams_Per : array (1 .. Max_Fold) of Natural :=
                 [others => 1];
            begin
               if P <= Header'Last and then Header (P) = 16#08# then
                  P := P + 1;  --  SubStreamsInfo
                  if P <= Header'Last and then Header (P) = 16#0D# then
                     P := P + 1;
                     for F in 1 .. Num_Folders loop
                        Streams_Per (F) := Natural (Num);
                     end loop;
                  end if;
                  --  Sizes (0x09): for folders with >1 stream, all but last.
                  if P <= Header'Last and then Header (P) = 16#09# then
                     P := P + 1;
                     for F in 1 .. Num_Folders loop
                        declare
                           Sum : Interfaces.Unsigned_64 := 0;
                        begin
                           for K in 1 .. Streams_Per (F) - 1 loop
                              declare
                                 S : constant Interfaces.Unsigned_64 := Num;
                              begin
                                 Sum := Sum + S;
                                 Sub_Count := Sub_Count + 1;
                                 if Sub_Count <= Max_Sub then
                                    Sub_Size (Sub_Count) := S;
                                 end if;
                              end;
                           end loop;
                           Sub_Count := Sub_Count + 1;  --  last stream
                           if Sub_Count <= Max_Sub then
                              Sub_Size (Sub_Count) :=
                                (if Folder_Size (F) >= Sum
                                 then Folder_Size (F) - Sum else 0);
                           end if;
                        end;
                     end loop;
                  else
                     --  No explicit sizes: each folder is one substream.
                     for F in 1 .. Num_Folders loop
                        for K in 1 .. Streams_Per (F) loop
                           Sub_Count := Sub_Count + 1;
                           if Sub_Count <= Max_Sub and then K = 1 then
                              Sub_Size (Sub_Count) := Folder_Size (F);
                           end if;
                        end loop;
                     end loop;
                  end if;
                  --  CRCs (0x0A): digests for streams lacking a folder CRC.
                  if P <= Header'Last and then Header (P) = 16#0A# then
                     P := P + 1;
                     declare
                        All_Def : constant Byte := Header (P);
                     begin
                        P := P + 1;
                        for I in 1 .. Sub_Count loop
                           if All_Def /= 0 then
                              if Seven_Zip_Has_Bytes (P, Header'Last, 4) then
                                 Sub_CRC (I) := Seven_Zip_U32_At (Header, P);
                                 P := P + 4;
                              end if;
                           end if;
                        end loop;
                     end;
                  end if;
                  --  consume to SubStreamsInfo kEnd
                  while P <= Header'Last and then Header (P) /= 0 loop
                     P := P + 1;
                  end loop;
                  if P <= Header'Last then
                     P := P + 1;
                  end if;
               else
                  --  No SubStreamsInfo: one substream per folder.
                  for F in 1 .. Num_Folders loop
                     Sub_Count := Sub_Count + 1;
                     if Sub_Count <= Max_Sub then
                        Sub_Size (Sub_Count) := Folder_Size (F);
                     end if;
                  end loop;
               end if;
            end;

            if P <= Header'Last and then Header (P) = 0 then
               P := P + 1;  --  end MainStreamsInfo
            end if;
         end if;

         --  FilesInfo (0x05).
         if P > Header'Last or else Header (P) /= 16#05# then
            Status := Unsupported_Method;
            return No;
         end if;
         P := P + 1;
         declare
            File_Count : constant Natural := Natural (Num);
            Has_Stream : array (1 .. Natural'Max (File_Count, 1)) of Boolean :=
              [others => True];
            Is_Dir     : array (1 .. Natural'Max (File_Count, 1)) of Boolean :=
              [others => False];
            Names      : array (1 .. Natural'Max (File_Count, 1)) of
              US.Unbounded_String := [others => US.Null_Unbounded_String];
            Empty_Seen : Natural := 0;
         begin
            if File_Count = 0 or else File_Count > Max_Sub then
               Status := Unsupported_Method;
               return No;
            end if;
            --  Property loop.
            loop
               exit when P > Header'Last or else Header (P) = 0;
               declare
                  Prop_Id   : constant Byte := Header (P);
                  Prop_Size : Interfaces.Unsigned_64 := 0;
               begin
                  P := P + 1;
                  if not Read_Seven_Zip_Number (Header, P, Header'Last, Prop_Size)
                  then
                     Status := Unsupported_Method;
                     return No;
                  end if;
                  declare
                     Prop_First : constant Natural := P;
                     Prop_Last  : constant Natural :=
                       P + Natural (Prop_Size) - 1;
                  begin
                     if Prop_Last > Header'Last then
                        Status := Unsupported_Method;
                        return No;
                     end if;
                     case Prop_Id is
                        when 16#0E# =>  --  kEmptyStream
                           for I in 1 .. File_Count loop
                              if Seven_Zip_Bit_Is_Set (Header, Prop_First, I) then
                                 Has_Stream (I) := False;
                                 Is_Dir (I) := True;
                              end if;
                           end loop;
                        when 16#0F# =>  --  kEmptyFile
                           Empty_Seen := 0;
                           for I in 1 .. File_Count loop
                              if not Has_Stream (I) then
                                 Empty_Seen := Empty_Seen + 1;
                                 if Seven_Zip_Bit_Is_Set
                                   (Header, Prop_First, Empty_Seen)
                                 then
                                    Is_Dir (I) := False;  --  empty file
                                 end if;
                              end if;
                           end loop;
                        when 16#11# =>  --  kName
                           declare
                              NP : Natural := Prop_First + 1;  --  skip external
                              FI : Natural := 1;
                           begin
                              while NP + 1 <= Prop_Last and then FI <= File_Count
                              loop
                                 declare
                                    S : US.Unbounded_String :=
                                      US.Null_Unbounded_String;
                                 begin
                                    while NP + 1 <= Prop_Last
                                      and then not (Header (NP) = 0
                                                    and then Header (NP + 1) = 0)
                                    loop
                                       US.Append
                                         (S,
                                          Character'Val
                                            (Natural (Header (NP)) +
                                             Natural (Header (NP + 1)) * 256));
                                       NP := NP + 2;
                                    end loop;
                                    Names (FI) := S;
                                    NP := NP + 2;
                                    FI := FI + 1;
                                 end;
                              end loop;
                           end;
                        when others =>
                           null;  --  MTime/Attributes/etc. not needed here
                     end case;
                     P := Prop_Last + 1;
                  end;
               end;
            end loop;

            --  Build the catalogue, mapping streamed files to substreams.
            return Result : Archive_Entry_Array (1 .. File_Count) do
               declare
                  Sub_Idx : Natural := 0;
               begin
                  for I in 1 .. File_Count loop
                     declare
                        USz : Interfaces.Unsigned_64 := 0;
                        Crc : Interfaces.Unsigned_32 := 0;
                     begin
                        if Has_Stream (I) then
                           Sub_Idx := Sub_Idx + 1;
                           if Sub_Idx <= Sub_Count then
                              USz := Sub_Size (Sub_Idx);
                              Crc := Sub_CRC (Sub_Idx);
                           end if;
                        end if;
                        Result (I) :=
                          (Name              => Names (I),
                           Is_Directory      => Is_Dir (I),
                           Compression       => 0,
                           Uncompressed_Size => USz,
                           Compressed_Size   => 0,
                           CRC_32            => Crc);
                     end;
                  end loop;
                  Status := Ok;
               end;
            end return;
         end;
      end;
   exception
      when others =>
         Status := Unsupported_Method;
         return No;
   end List_Seven_Zip_Entries;

   procedure Extract_Archive_To_Directory
     (Archive_Image   : Byte_Array;
      Destination_Dir : String;
      Password        : String;
      Status          : out Status_Code)
   is
      Is_7z : constant Boolean :=
        Archive_Image'Length >= 6
        and then Archive_Image (Archive_Image'First) = 16#37#
        and then Archive_Image (Archive_Image'First + 1) = 16#7A#
        and then Archive_Image (Archive_Image'First + 2) = 16#BC#
        and then Archive_Image (Archive_Image'First + 3) = 16#AF#;
   begin
      Status := Unsupported_Method;
      if Is_7z then
         Active_Seven_Zip_Password := US.To_Unbounded_String (Password);
      end if;
      declare
         List_Status : Status_Code := Ok;
         Entries     : constant Archive_Entry_Array :=
           (if Is_7z then List_Seven_Zip_Entries (Archive_Image, List_Status)
            else List_ZIP_Entries (Archive_Image, List_Status));
      begin
         Active_Seven_Zip_Password := US.Null_Unbounded_String;
         if List_Status /= Ok then
            Status := List_Status;
            return;
         end if;

         for E of Entries loop
            declare
               Name : constant String := US.To_String (E.Name);
               Rel  : constant String :=
                 (if Name'Length > 0 and then Name (Name'Last) = '/'
                  then Name (Name'First .. Name'Last - 1) else Name);
            begin
               --  Reject unsafe paths (absolute, "..", drive, backslash).
               if Rel'Length = 0 or else not Safe_ZIP_Entry_Name (Rel) then
                  Status := Unsupported_Method;
                  return;
               end if;
               declare
                  Target : constant String := Destination_Dir & "/" & Rel;
               begin
                  if E.Is_Directory then
                     Ada.Directories.Create_Path (Target);
                  else
                     Ada.Directories.Create_Path
                       (Ada.Directories.Containing_Directory (Target));
                     declare
                        XS   : Status_Code := Ok;
                        Data : constant Byte_Array :=
                          (if Is_7z
                           then Extract_Seven_Zip
                                  (Archive_Image, Name, Password, XS)
                           else Extract_ZIP (Archive_Image, Name, XS));
                        WS   : Status_Code := Ok;
                     begin
                        if XS /= Ok then
                           Status := XS;
                           return;
                        end if;
                        Write_File (Target, Data, WS);
                        if WS /= Ok then
                           Status := WS;
                           return;
                        end if;
                     end;
                  end if;
               end;
            end;
         end loop;
         Status := Ok;
      end;
   exception
      when others =>
         Active_Seven_Zip_Password := US.Null_Unbounded_String;
         Status := Unsupported_Method;
   end Extract_Archive_To_Directory;

   procedure Extract_Archive_File_To_Directory
     (Archive_Path    : String;
      Destination_Dir : String;
      Password        : String;
      Status          : out Status_Code)
   is
      Read_Status : Status_Code := Ok;
      Image       : constant Byte_Array := Read_File (Archive_Path, Read_Status);
   begin
      if Read_Status /= Ok then
         Status := Read_Status;
         return;
      end if;
      Extract_Archive_To_Directory
        (Image, Destination_Dir, Password, Status);
   end Extract_Archive_File_To_Directory;

   function List_Archive_Entries
     (Archive_Image : Byte_Array;
      Password      : String;
      Status        : out Status_Code) return Archive_Entry_Array
   is
      Is_7z : constant Boolean :=
        Archive_Image'Length >= 6
        and then Archive_Image (Archive_Image'First) = 16#37#
        and then Archive_Image (Archive_Image'First + 1) = 16#7A#
        and then Archive_Image (Archive_Image'First + 2) = 16#BC#
        and then Archive_Image (Archive_Image'First + 3) = 16#AF#;
   begin
      if Is_7z then
         Active_Seven_Zip_Password := US.To_Unbounded_String (Password);
         return R : constant Archive_Entry_Array :=
           List_Seven_Zip_Entries (Archive_Image, Status)
         do
            Active_Seven_Zip_Password := US.Null_Unbounded_String;
         end return;
      else
         return List_ZIP_Entries (Archive_Image, Status);
      end if;
   end List_Archive_Entries;

   function Extract_Seven_Zip_Metadata
     (Archive_Image : Byte_Array;
      Entry_Name    : String;
      Status        : out Status_Code) return Seven_Zip_Entry_Metadata
   is
      Kind     : Seven_Zip_Entry_Kind := Seven_Zip_File_Entry;
      Metadata : Seven_Zip_Entry_Metadata := No_Seven_Zip_Entry_Metadata;
      Payload  : constant Byte_Array :=
        Extract_Seven_Zip_Entry
          (Archive_Image, Entry_Name, Status, Kind, Metadata);
      pragma Unreferenced (Payload);
   begin
      if Status /= Ok then
         return No_Seven_Zip_Entry_Metadata;
      end if;

      Metadata.Is_Directory := Kind = Seven_Zip_Directory_Entry;
      return Metadata;
   exception
      when others =>
         Status := Unsupported_Method;
         return No_Seven_Zip_Entry_Metadata;
   end Extract_Seven_Zip_Metadata;

   procedure Extract_Seven_Zip_Stored_File
     (Input_Path  : String;
      Output_Path : String;
      Entry_Name  : String;
      Status      : out Status_Code)
   is
      Read_Status  : Status_Code := Ok;
      Write_Status : Status_Code := Ok;
   begin
      Status := Unsupported_Method;
      if not Seven_Zip_Entry_Name_Valid (Entry_Name) then
         return;
      end if;
      if not Seven_Zip_Output_File_Writable (Output_Path) then
         Status := Output_File_Error;
         return;
      end if;

      declare
         Archive : constant Byte_Array := Read_File (Input_Path, Read_Status);
      begin
         if Read_Status /= Ok then
            Status := Read_Status;
            return;
         end if;

         declare
            Entry_Kind : Seven_Zip_Entry_Kind := Seven_Zip_File_Entry;
            Metadata : Seven_Zip_Entry_Metadata;
            Payload : constant Byte_Array :=
              Extract_Seven_Zip_Entry
                (Archive, Entry_Name, Status, Entry_Kind, Metadata);
         begin
            if Status /= Ok then
               return;
            end if;

            if Entry_Kind = Seven_Zip_Directory_Entry then
               begin
                  Ada.Directories.Create_Path
                    (Ada.Directories.Containing_Directory (Output_Path));
                  Ada.Directories.Create_Path (Output_Path);
               exception
                  when others =>
                     Status := Output_File_Error;
                     return;
               end;

               Seven_Zip_Apply_Metadata (Output_Path, Metadata);
               Status := Ok;
               return;
            end if;

            begin
               Ada.Directories.Create_Path
                 (Ada.Directories.Containing_Directory (Output_Path));
            exception
               when others =>
                  Status := Output_File_Error;
                  return;
            end;

            Write_File (Output_Path, Payload, Write_Status);
            if Write_Status /= Ok then
               Status := Write_Status;
               return;
            end if;

            Seven_Zip_Apply_Metadata (Output_Path, Metadata);
            Status := Ok;
         end;
      end;
   exception
      when others =>
         Status := Output_File_Error;
   end Extract_Seven_Zip_Stored_File;

   procedure Extract_Seven_Zip_File
     (Input_Path  : String;
      Output_Path : String;
      Entry_Name  : String;
      Status      : out Status_Code)
   is
      Read_Status  : Status_Code := Ok;
      Write_Status : Status_Code := Ok;
   begin
      Status := Unsupported_Method;
      if not Seven_Zip_Entry_Name_Valid (Entry_Name) then
         return;
      end if;
      if not Seven_Zip_Output_File_Writable (Output_Path) then
         Status := Output_File_Error;
         return;
      end if;

      declare
         Archive : constant Byte_Array := Read_File (Input_Path, Read_Status);
      begin
         if Read_Status /= Ok then
            Status := Read_Status;
            return;
         end if;

         declare
            Entry_Kind : Seven_Zip_Entry_Kind := Seven_Zip_File_Entry;
            Metadata : Seven_Zip_Entry_Metadata;
            Payload : constant Byte_Array :=
              Extract_Seven_Zip_Entry
                (Archive, Entry_Name, Status, Entry_Kind, Metadata);
         begin
            if Status /= Ok then
               return;
            end if;

            if Entry_Kind = Seven_Zip_Directory_Entry then
               begin
                  Ada.Directories.Create_Path
                    (Ada.Directories.Containing_Directory (Output_Path));
                  Ada.Directories.Create_Path (Output_Path);
               exception
                  when others =>
                     Status := Output_File_Error;
                     return;
               end;

               Seven_Zip_Apply_Metadata (Output_Path, Metadata);
               Status := Ok;
               return;
            end if;

            begin
               Ada.Directories.Create_Path
                 (Ada.Directories.Containing_Directory (Output_Path));
            exception
               when others =>
                  Status := Output_File_Error;
                  return;
            end;

            Write_File (Output_Path, Payload, Write_Status);
            if Write_Status /= Ok then
               Status := Write_Status;
               return;
            end if;

            Seven_Zip_Apply_Metadata (Output_Path, Metadata);
            Status := Ok;
         end;
      end;
   exception
      when others =>
         Status := Output_File_Error;
   end Extract_Seven_Zip_File;

   function Safe_Seven_Zip_Output_Name (Entry_Name : String) return Boolean is
      Segment_Length : Natural := 0;
      Segment_Start  : Natural := Entry_Name'First;

      function Segment_Is_Dot return Boolean is
      begin
         return Segment_Length = 1
           and then Entry_Name (Segment_Start) = '.';
      end Segment_Is_Dot;

      function Segment_Is_Dot_Dot return Boolean is
      begin
         return Segment_Length = 2
           and then Entry_Name (Segment_Start) = '.'
           and then Entry_Name (Segment_Start + 1) = '.';
      end Segment_Is_Dot_Dot;

      function Finish_Segment return Boolean is
      begin
         return Segment_Length > 0
           and then not Segment_Is_Dot
           and then not Segment_Is_Dot_Dot;
      end Finish_Segment;
   begin
      if Entry_Name'Length = 0
        or else Contains_NUL (Entry_Name)
        or else Entry_Name (Entry_Name'First) = '/'
      then
         return False;
      end if;

      for I in Entry_Name'Range loop
         case Entry_Name (I) is
            when '/' =>
               if not Finish_Segment then
                  return False;
               end if;
               Segment_Length := 0;
               Segment_Start := I + 1;
            when '\' | ':' =>
               return False;
            when others =>
               Segment_Length := Segment_Length + 1;
         end case;
      end loop;

      return Finish_Segment
        or else (Entry_Name (Entry_Name'Last) = '/'
                 and then Segment_Length = 0);
   exception
      when others =>
         return False;
   end Safe_Seven_Zip_Output_Name;

   function Seven_Zip_Output_Path
     (Output_Dir : String;
      Entry_Name : String) return String
   is
      Raw : constant String :=
        (if Output_Dir'Length > 0 and then Output_Dir (Output_Dir'Last) = '/'
         then Output_Dir & Entry_Name
         else Output_Dir & "/" & Entry_Name);
   begin
      if Raw'Length > 1 and then Raw (Raw'Last) = '/' then
         return Raw (Raw'First .. Raw'Last - 1);
      end if;

      return Raw;
   end Seven_Zip_Output_Path;

   procedure Extract_Seven_Zip_Files_Impl
     (Input_Path   : String;
      Output_Dir   : String;
      Entry_Names  : Text_Array;
      Status       : out Status_Code)
   is
      Read_Status  : Status_Code := Ok;
      Write_Status : Status_Code := Ok;
      type Payload_Vector_Array is array (Positive range <>) of Byte_Vectors.Vector;
      type Entry_Kind_Array is array (Positive range <>) of Seven_Zip_Entry_Kind;
   begin
      Status := Unsupported_Method;

      if Output_Dir'Length = 0 or else Entry_Names'Length = 0 then
         return;
      end if;

      for Offset in 0 .. Entry_Names'Length - 1 loop
         declare
            Entry_Name : constant String :=
              US.To_String (Entry_Names (Entry_Names'First + Offset));
         begin
            if not Safe_Seven_Zip_Output_Name (Entry_Name) then
               return;
            end if;

            if Offset > 0 then
               for Previous_Offset in 0 .. Offset - 1 loop
                  if Entry_Name =
                    US.To_String
                      (Entry_Names (Entry_Names'First + Previous_Offset))
                  then
                     return;
                  end if;
               end loop;
            end if;
         end;
      end loop;

      if not Seven_Zip_Output_Directory_Writable (Output_Dir) then
         Status := Output_File_Error;
         return;
      end if;

      declare
         Archive : constant Byte_Array := Read_File (Input_Path, Read_Status);
      begin
         if Read_Status /= Ok then
            Status := Read_Status;
            return;
         end if;

         declare
            Payloads : Payload_Vector_Array (1 .. Entry_Names'Length);
            Entry_Kinds : Entry_Kind_Array (1 .. Entry_Names'Length) :=
              [others => Seven_Zip_File_Entry];
            Entry_Metadata : array (1 .. Entry_Names'Length)
              of Seven_Zip_Entry_Metadata :=
                [others => No_Seven_Zip_Entry_Metadata];
         begin
            for Offset in 0 .. Entry_Names'Length - 1 loop
               declare
                  Entry_Name : constant String :=
                    US.To_String (Entry_Names (Entry_Names'First + Offset));
                  Entry_Kind : Seven_Zip_Entry_Kind := Seven_Zip_File_Entry;
                  Metadata : Seven_Zip_Entry_Metadata;
                  Payload : constant Byte_Array :=
                    Extract_Seven_Zip_Entry
                      (Archive, Entry_Name, Status, Entry_Kind, Metadata);
               begin
                  if Status /= Ok then
                     return;
                  end if;

                  Entry_Kinds (Offset + 1) := Entry_Kind;
                  Entry_Metadata (Offset + 1) := Metadata;
                  for B of Payload loop
                     Payloads (Offset + 1).Append (B);
                  end loop;
               end;
            end loop;

            begin
               Ada.Directories.Create_Path (Output_Dir);
            exception
               when others =>
                  Status := Output_File_Error;
                  return;
            end;

            for Offset in 0 .. Entry_Names'Length - 1 loop
               declare
                  Entry_Name : constant String :=
                    US.To_String (Entry_Names (Entry_Names'First + Offset));
                  Output_Path : constant String :=
                    Seven_Zip_Output_Path (Output_Dir, Entry_Name);
                  Parent_Path : constant String :=
                    Ada.Directories.Containing_Directory (Output_Path);
               begin
                  begin
                     if Ada.Directories.Exists (Output_Path)
                       and then
                        Ada.Directories.Kind (Output_Path) =
                           Ada.Directories.Directory
                       and then Entry_Kinds (Offset + 1) /=
                         Seven_Zip_Directory_Entry
                     then
                        Status := Output_File_Error;
                        return;
                     end if;

                     if Ada.Directories.Exists (Parent_Path)
                       and then
                         Ada.Directories.Kind (Parent_Path) /=
                           Ada.Directories.Directory
                     then
                        Status := Output_File_Error;
                        return;
                     end if;
                  exception
                     when others =>
                        Status := Output_File_Error;
                        return;
                  end;
               end;
            end loop;

            for Offset in 0 .. Entry_Names'Length - 1 loop
               declare
                  Entry_Name : constant String :=
                    US.To_String (Entry_Names (Entry_Names'First + Offset));
               begin
                  declare
                     Output_Path : constant String :=
                       Seven_Zip_Output_Path (Output_Dir, Entry_Name);
                     Payload : constant Byte_Array :=
                       To_Byte_Array (Payloads (Offset + 1));
                  begin
                     if Entry_Kinds (Offset + 1) =
                       Seven_Zip_Directory_Entry
                     then
                        begin
                           Ada.Directories.Create_Path (Output_Path);
                        exception
                           when others =>
                              Status := Output_File_Error;
                              return;
                        end;
                        Seven_Zip_Apply_Metadata
                          (Output_Path, Entry_Metadata (Offset + 1));
                     else
                        begin
                           Ada.Directories.Create_Path
                             (Ada.Directories.Containing_Directory
                                (Output_Path));
                        exception
                           when others =>
                              Status := Output_File_Error;
                              return;
                        end;

                        Write_File (Output_Path, Payload, Write_Status);
                        if Write_Status /= Ok then
                           Status := Write_Status;
                           return;
                        end if;

                        Seven_Zip_Apply_Metadata
                          (Output_Path, Entry_Metadata (Offset + 1));
                     end if;
                  end;
               end;
            end loop;
         end;

         Status := Ok;
      end;
   exception
      when others =>
         Status := Output_File_Error;
   end Extract_Seven_Zip_Files_Impl;

   procedure Extract_Seven_Zip_Stored_Files
     (Input_Path   : String;
      Output_Dir   : String;
      Entry_Names  : Text_Array;
      Status       : out Status_Code) is
   begin
      Extract_Seven_Zip_Files_Impl
        (Input_Path, Output_Dir, Entry_Names, Status);
   end Extract_Seven_Zip_Stored_Files;

   procedure Extract_Seven_Zip_Files
     (Input_Path   : String;
      Output_Dir   : String;
      Entry_Names  : Text_Array;
      Status       : out Status_Code) is
   begin
      Extract_Seven_Zip_Files_Impl
        (Input_Path, Output_Dir, Entry_Names, Status);
   end Extract_Seven_Zip_Files;

   function U32_To_Byte
     (Value : Interfaces.Unsigned_32; Shift : Natural) return Byte is
   begin
      return Byte (Interfaces.Shift_Right (Value, Shift) and 16#FF#);
   end U32_To_Byte;

   function Deflate_Stored
     (Input : Byte_Array; Status : out Status_Code) return Byte_Array
   is
      Max_Block_Size : constant Natural := Max_Compress_Block_Size;
      Block_Count    : constant Natural :=
        (if Input'Length = 0
         then 1
         else (Input'Length + Max_Block_Size - 1) / Max_Block_Size);

      Output_Length : constant Natural :=
        2 + Block_Count * 5 + Input'Length + 4;

      Output : Byte_Array (1 .. Output_Length);
      Out_I  : Natural := Output'First;
      In_I   : Natural := Input'First;
      Adler  : constant Interfaces.Unsigned_32 :=
        Zlib.Checksums.Adler32 (Input);

      Remaining : Natural := Input'Length;
      This_Len  : Natural;
      Final     : Boolean;
      Len       : Natural;
      NLen      : Natural;
   begin
      Output (Out_I) := 16#78#;
      Out_I := Out_I + 1;

      Output (Out_I) := 16#01#;
      Out_I := Out_I + 1;

      for Block in 1 .. Block_Count loop
         if Remaining > Max_Block_Size then
            This_Len := Max_Block_Size;
         else
            This_Len := Remaining;
         end if;

         Final := Block = Block_Count;

         Output (Out_I) := (if Final then 16#01# else 16#00#);
         Out_I := Out_I + 1;

         Len := This_Len;
         NLen := 16#FFFF# - Len;

         Output (Out_I) := Byte (Len mod 256);
         Out_I := Out_I + 1;

         Output (Out_I) := Byte (Len / 256);
         Out_I := Out_I + 1;

         Output (Out_I) := Byte (NLen mod 256);
         Out_I := Out_I + 1;

         Output (Out_I) := Byte (NLen / 256);
         Out_I := Out_I + 1;

         for J in 1 .. This_Len loop
            Output (Out_I) := Input (In_I);
            Out_I := Out_I + 1;
            In_I := In_I + 1;
         end loop;

         Remaining := Remaining - This_Len;
      end loop;

      Output (Out_I) := U32_To_Byte (Adler, 24);
      Out_I := Out_I + 1;

      Output (Out_I) := U32_To_Byte (Adler, 16);
      Out_I := Out_I + 1;

      Output (Out_I) := U32_To_Byte (Adler, 8);
      Out_I := Out_I + 1;

      Output (Out_I) := U32_To_Byte (Adler, 0);

      Status := Ok;
      return Output;
   end Deflate_Stored;

   function Deflate_Fixed
     (Input : Byte_Array; Status : out Status_Code) return Byte_Array is
   begin
      return Zlib.Fixed_Compress.Deflate_Fixed (Input, Status);
   end Deflate_Fixed;

   function Deflate_Dynamic
     (Input : Byte_Array; Status : out Status_Code) return Byte_Array is
   begin
      return
        Compress_With_Header
          (Input  => Input,
           Header => Zlib_Header,
           Mode   => Dynamic,
           Status => Status);
   end Deflate_Dynamic;

   function Deflate
     (Input  : Byte_Array;
      Mode   : Compression_Mode := Auto;
      Status : out Status_Code) return Byte_Array
   is
      function Empty_Result return Byte_Array is
         Empty : constant Byte_Array (1 .. 0) := [others => 0];
      begin
         return Empty;
      end Empty_Result;
   begin
      case Mode is
         when Stored  =>
            return Deflate_Stored (Input, Status);

         when Fixed   =>
            return Deflate_Fixed (Input, Status);

         when Dynamic =>
            return Deflate_Dynamic (Input, Status);

         when Auto    =>
            return
              Compress_With_Header
                (Input  => Input,
                 Header => Zlib_Header,
                 Mode   => Auto,
                 Status => Status);
      end case;
   exception
      when others =>
         Status := Unexpected_End_Of_Input;
         return Empty_Result;
   end Deflate;

   function Deflate
     (Input : Byte_Array; Level : Compression_Level; Status : out Status_Code)
      return Byte_Array is
   begin
      return
        Compress_With_Header
          (Input  => Input,
           Header => Zlib_Header,
           Mode   => Mode_For_Level (Level),
           Status => Status,
           Level  => Level);
   end Deflate;

   function Deflate_With_Dictionary
     (Input      : Byte_Array;
      Dictionary : Byte_Array;
      Mode       : Compression_Mode := Auto;
      Status     : out Status_Code) return Byte_Array is
   begin
      return
        Compress_With_Header
          (Input          => Input,
           Header         => Zlib_Header,
           Mode           => Mode,
           Status         => Status,
           Dictionary_Set => True,
           Dictionary_ID  => Zlib.Checksums.Adler32 (Dictionary));
   end Deflate_With_Dictionary;

   function Deflate_Raw
     (Input  : Byte_Array;
      Mode   : Compression_Mode := Auto;
      Status : out Status_Code) return Byte_Array is
   begin
      return
        Compress_With_Header
          (Input  => Input,
           Header => Raw_Deflate,
           Mode   => Mode,
           Status => Status);
   end Deflate_Raw;

   function Deflate_Raw
     (Input : Byte_Array; Level : Compression_Level; Status : out Status_Code)
      return Byte_Array is
   begin
      return
        Compress_With_Header
          (Input  => Input,
           Header => Raw_Deflate,
           Mode   => Mode_For_Level (Level),
           Status => Status,
           Level  => Level);
   end Deflate_Raw;

   function GZip
     (Input  : Byte_Array;
      Mode   : Compression_Mode := Auto;
      Status : out Status_Code) return Byte_Array is
   begin
      return
        GZip
          (Input    => Input,
           Mode     => Mode,
           Metadata => No_GZip_Metadata,
           Status   => Status);
   end GZip;

   function GZip
     (Input    : Byte_Array;
      Mode     : Compression_Mode;
      Metadata : GZip_Metadata;
      Status   : out Status_Code) return Byte_Array
   is
      function Empty_Result return Byte_Array is
         Empty : constant Byte_Array (1 .. 0) := [others => 0];
      begin
         return Empty;
      end Empty_Result;
   begin
      if not Metadata.Valid then
         Status := Invalid_Header;
         return Empty_Result;
      end if;

      return
        Compress_With_Header
          (Input    => Input,
           Header   => Zlib.GZip,
           Mode     => Mode,
           Status   => Status,
           Metadata => Metadata);

   exception
      when others =>
         Status := Unexpected_End_Of_Input;
         return Empty_Result;
   end GZip;

   function GZip
     (Input : Byte_Array; Level : Compression_Level; Status : out Status_Code)
      return Byte_Array is
   begin
      return
        Compress_With_Header
          (Input  => Input,
           Header => Zlib.GZip,
           Mode   => Mode_For_Level (Level),
           Status => Status,
           Level  => Level);
   end GZip;

   function GZip
     (Input    : Byte_Array;
      Level    : Compression_Level;
      Metadata : GZip_Metadata;
      Status   : out Status_Code) return Byte_Array is
   begin
      return
        Compress_With_Header
          (Input    => Input,
           Header   => Zlib.GZip,
           Mode     => Mode_For_Level (Level),
           Status   => Status,
           Metadata => Metadata,
           Level    => Level);
   end GZip;

   function Text_Bytes (Text : String) return Byte_Array is
   begin
      if Text'Length = 0 then
         declare
            Empty : constant Byte_Array (1 .. 0) := [others => 0];
         begin
            return Empty;
         end;
      end if;

      declare
         Result : Byte_Array (1 .. Text'Length);
      begin
         for I in Text'Range loop
            Result (I - Text'First + 1) :=
              Byte (Character'Pos (Text (I)));
         end loop;
         return Result;
      end;
   end Text_Bytes;

   function GZip_Members
     (Inputs : Text_Array;
      Mode   : Compression_Mode := Auto;
      Status : out Status_Code) return Byte_Array
   is
      Output : Byte_Vectors.Vector;

      function Empty_Result return Byte_Array is
         Empty : constant Byte_Array (1 .. 0) := [others => 0];
      begin
         return Empty;
      end Empty_Result;
   begin
      if Inputs'Length = 0 then
         Status := Unsupported_Method;
         return Empty_Result;
      end if;

      for I in Inputs'Range loop
         declare
            Member : constant Byte_Array :=
              GZip (Text_Bytes (US.To_String (Inputs (I))), Mode, Status);
         begin
            if Status /= Ok then
               return Empty_Result;
            end if;
            Append_Bytes (Output, Member);
         end;
      end loop;

      Status := Ok;
      return To_Byte_Array (Output);
   exception
      when others =>
         Status := Unsupported_Method;
         return Empty_Result;
   end GZip_Members;

   Streaming_File_Buffer_Size : constant Ada.Streams.Stream_Element_Offset :=
     65_536;

   procedure Write_Produced
     (File   : in out SIO.File_Type;
      Buffer : Ada.Streams.Stream_Element_Array;
      Last   : Ada.Streams.Stream_Element_Offset)
   is
      Count : constant Natural := Produced (Buffer, Last);
   begin
      if Count > 0 then
         SIO.Write
           (File,
            Buffer
              (Buffer'First
               ..
                 Buffer'First
                 + Ada.Streams.Stream_Element_Offset (Count)
                 - 1));
      end if;
   end Write_Produced;

   procedure Inflate_File_Streaming_Internal
     (Input_Path      : String;
      Output_Path     : String;
      Header          : Header_Type := Zlib_Header;
      Dictionary      : Byte_Array;
      Use_Dictionary  : Boolean;
      Status          : out Status_Code)
   is
      Input_File    : SIO.File_Type;
      Output_File   : SIO.File_Type;
      Filter        : Filter_Type;
      In_Buffer     :
        Ada.Streams.Stream_Element_Array (1 .. Streaming_File_Buffer_Size);
      Out_Buffer    :
        Ada.Streams.Stream_Element_Array (1 .. Streaming_File_Buffer_Size);
      Last_Read     : Ada.Streams.Stream_Element_Offset;
      In_Last       : Ada.Streams.Stream_Element_Offset;
      Out_Last      : Ada.Streams.Stream_Element_Offset;
      Operation     : Status_Code := Input_File_Error;
      Finished      : Boolean := False;
      Made_Progress : Boolean;
   begin
      Status := Ok;

      begin
         SIO.Open (Input_File, SIO.In_File, Input_Path);
      exception
         when others =>
            Status := Input_File_Error;
            return;
      end;

      begin
         SIO.Create (Output_File, SIO.Out_File, Output_Path);
      exception
         when others =>
            if SIO.Is_Open (Input_File) then
               SIO.Close (Input_File);
            end if;
            Status := Output_File_Error;
            return;
      end;

      Inflate_Init (Filter, Header);

      if Use_Dictionary then
         Inflate_Set_Dictionary (Filter, Dictionary);
      end if;

      while not Finished and then not SIO.End_Of_File (Input_File) loop
         Operation := Input_File_Error;
         SIO.Read (Input_File, In_Buffer, Last_Read);

         if Last_Read >= In_Buffer'First then
            declare
               Next_Input : Ada.Streams.Stream_Element_Offset :=
                 In_Buffer'First;
            begin
               while not Finished and then Next_Input <= Last_Read loop
                  Made_Progress := False;

                  declare
                     Before_Input :
                       constant Ada.Streams.Stream_Element_Offset :=
                         Next_Input;
                  begin
                     Translate
                       (Filter   => Filter,
                        In_Data  => In_Buffer (Next_Input .. Last_Read),
                        In_Last  => In_Last,
                        Out_Data => Out_Buffer,
                        Out_Last => Out_Last,
                        Flush    => No_Flush);

                     Operation := Output_File_Error;
                     Write_Produced (Output_File, Out_Buffer, Out_Last);

                     if Produced (Out_Buffer, Out_Last) > 0 then
                        Made_Progress := True;
                     end if;

                     if In_Last >= Before_Input then
                        Next_Input := In_Last + 1;
                        Made_Progress := True;
                     end if;
                  end;

                  Finished := Stream_End (Filter);

                  if Finished
                    and then Header = GZip
                    and then
                      (Next_Input <= Last_Read
                       or else not SIO.End_Of_File (Input_File))
                  then
                     Status := Invalid_Header;
                     Close (Filter, Ignore_Error => True);
                     SIO.Close (Input_File);
                     SIO.Close (Output_File);
                     return;
                  end if;

                  if not Finished and then not Made_Progress then
                     Filter.Last_Status := Unexpected_End_Of_Input;
                     raise Zlib_Error;
                  end if;
               end loop;
            end;
         end if;
      end loop;

      while not Stream_End (Filter) loop
         Made_Progress := False;
         Flush
           (Filter   => Filter,
            Out_Data => Out_Buffer,
            Out_Last => Out_Last,
            Flush    => Finish);

         Operation := Output_File_Error;
         Write_Produced (Output_File, Out_Buffer, Out_Last);

         if Produced (Out_Buffer, Out_Last) > 0 then
            Made_Progress := True;
         end if;

         if not Stream_End (Filter) and then not Made_Progress then
            Filter.Last_Status := Unexpected_End_Of_Input;
            raise Zlib_Error;
         end if;
      end loop;

      Close (Filter, Ignore_Error => True);
      SIO.Close (Input_File);
      SIO.Close (Output_File);
      Status := Ok;

   exception
      when Zlib_Error =>
         Status := Filter.Last_Status;
         if Status = Ok then
            Status := Unexpected_End_Of_Input;
         end if;
         if Is_Open (Filter) then
            Close (Filter, Ignore_Error => True);
         end if;
         if SIO.Is_Open (Input_File) then
            SIO.Close (Input_File);
         end if;
         if SIO.Is_Open (Output_File) then
            SIO.Close (Output_File);
         end if;

      when Status_Error =>
         Status := Unexpected_End_Of_Input;
         if Is_Open (Filter) then
            Close (Filter, Ignore_Error => True);
         end if;
         if SIO.Is_Open (Input_File) then
            SIO.Close (Input_File);
         end if;
         if SIO.Is_Open (Output_File) then
            SIO.Close (Output_File);
         end if;

      when others =>
         Status := Operation;
         if Is_Open (Filter) then
            Close (Filter, Ignore_Error => True);
         end if;
         if SIO.Is_Open (Input_File) then
            SIO.Close (Input_File);
         end if;
         if SIO.Is_Open (Output_File) then
            SIO.Close (Output_File);
         end if;
   end Inflate_File_Streaming_Internal;

   procedure Inflate_File_Streaming
     (Input_Path  : String;
      Output_Path : String;
      Header      : Header_Type := Zlib_Header;
      Status      : out Status_Code)
   is
      Empty : constant Byte_Array (1 .. 0) := [others => 0];
   begin
      Inflate_File_Streaming_Internal
        (Input_Path     => Input_Path,
         Output_Path    => Output_Path,
         Header         => Header,
         Dictionary     => Empty,
         Use_Dictionary => False,
         Status         => Status);
   end Inflate_File_Streaming;

   procedure Inflate_File_With_Dictionary_Streaming
     (Input_Path  : String;
      Output_Path : String;
      Dictionary  : Byte_Array;
      Status      : out Status_Code) is
   begin
      Inflate_File_Streaming_Internal
        (Input_Path     => Input_Path,
         Output_Path    => Output_Path,
         Header         => Zlib_Header,
         Dictionary     => Dictionary,
         Use_Dictionary => True,
         Status         => Status);
   end Inflate_File_With_Dictionary_Streaming;

   procedure Deflate_File_Streaming_Internal
     (Input_Path     : String;
      Output_Path    : String;
      Header         : Header_Type := Zlib_Header;
      Mode           : Compression_Mode := Auto;
      Dictionary     : Byte_Array;
      Use_Dictionary : Boolean;
      Status         : out Status_Code)
   is
      Input_File    : SIO.File_Type;
      Output_File   : SIO.File_Type;
      Filter        : Compression_Filter_Type;
      In_Buffer     :
        Ada.Streams.Stream_Element_Array (1 .. Streaming_File_Buffer_Size);
      Out_Buffer    :
        Ada.Streams.Stream_Element_Array (1 .. Streaming_File_Buffer_Size);
      Last_Read     : Ada.Streams.Stream_Element_Offset;
      In_Last       : Ada.Streams.Stream_Element_Offset;
      Out_Last      : Ada.Streams.Stream_Element_Offset;
      Operation     : Status_Code := Input_File_Error;
      Made_Progress : Boolean;
   begin
      Status := Ok;

      begin
         SIO.Open (Input_File, SIO.In_File, Input_Path);
      exception
         when others =>
            Status := Input_File_Error;
            return;
      end;

      begin
         SIO.Create (Output_File, SIO.Out_File, Output_Path);
      exception
         when others =>
            if SIO.Is_Open (Input_File) then
               SIO.Close (Input_File);
            end if;
            Status := Output_File_Error;
            return;
      end;

      Deflate_Init (Filter, Header, Mode);

      if Use_Dictionary then
         Deflate_Set_Dictionary (Filter, Dictionary);
      end if;

      while not SIO.End_Of_File (Input_File) loop
         Operation := Input_File_Error;
         SIO.Read (Input_File, In_Buffer, Last_Read);

         if Last_Read >= In_Buffer'First then
            declare
               Next_Input : Ada.Streams.Stream_Element_Offset :=
                 In_Buffer'First;
            begin
               while Next_Input <= Last_Read loop
                  Made_Progress := False;

                  declare
                     Before_Input :
                       constant Ada.Streams.Stream_Element_Offset :=
                         Next_Input;
                  begin
                     Compress
                       (Filter   => Filter,
                        In_Data  => In_Buffer (Next_Input .. Last_Read),
                        In_Last  => In_Last,
                        Out_Data => Out_Buffer,
                        Out_Last => Out_Last,
                        Flush    => No_Flush);

                     Operation := Output_File_Error;
                     Write_Produced (Output_File, Out_Buffer, Out_Last);

                     if Produced (Out_Buffer, Out_Last) > 0 then
                        Made_Progress := True;
                     end if;

                     if In_Last >= Before_Input then
                        Next_Input := In_Last + 1;
                        Made_Progress := True;
                     end if;
                  end;

                  if not Made_Progress then
                     raise Status_Error;
                  end if;
               end loop;
            end;
         end if;
      end loop;

      while not Compress_Stream_End (Filter) loop
         Made_Progress := False;

         Compress_Flush
           (Filter   => Filter,
            Out_Data => Out_Buffer,
            Out_Last => Out_Last,
            Flush    => Finish);

         Operation := Output_File_Error;
         Write_Produced (Output_File, Out_Buffer, Out_Last);

         if Produced (Out_Buffer, Out_Last) > 0 then
            Made_Progress := True;
         end if;

         if not Compress_Stream_End (Filter) and then not Made_Progress then
            raise Status_Error;
         end if;
      end loop;

      Compress_Close (Filter, Ignore_Error => True);
      SIO.Close (Input_File);
      SIO.Close (Output_File);
      Status := Ok;

   exception
      when Zlib_Error | Status_Error =>
         Status := Unexpected_End_Of_Input;
         if Is_Open (Filter) then
            Compress_Close (Filter, Ignore_Error => True);
         end if;
         if SIO.Is_Open (Input_File) then
            SIO.Close (Input_File);
         end if;
         if SIO.Is_Open (Output_File) then
            SIO.Close (Output_File);
         end if;

      when others =>
         Status := Operation;
         if Is_Open (Filter) then
            Compress_Close (Filter, Ignore_Error => True);
         end if;
         if SIO.Is_Open (Input_File) then
            SIO.Close (Input_File);
         end if;
         if SIO.Is_Open (Output_File) then
            SIO.Close (Output_File);
         end if;
   end Deflate_File_Streaming_Internal;

   procedure Deflate_File_Streaming
     (Input_Path  : String;
      Output_Path : String;
      Header      : Header_Type := Zlib_Header;
      Mode        : Compression_Mode := Auto;
      Status      : out Status_Code)
   is
      Empty : constant Byte_Array (1 .. 0) := [others => 0];
   begin
      Deflate_File_Streaming_Internal
        (Input_Path     => Input_Path,
         Output_Path    => Output_Path,
         Header         => Header,
         Mode           => Mode,
         Dictionary     => Empty,
         Use_Dictionary => False,
         Status         => Status);
   end Deflate_File_Streaming;

   procedure Deflate_File_With_Dictionary_Streaming
     (Input_Path  : String;
      Output_Path : String;
      Dictionary  : Byte_Array;
      Mode        : Compression_Mode := Auto;
      Status      : out Status_Code) is
   begin
      Deflate_File_Streaming_Internal
        (Input_Path     => Input_Path,
         Output_Path    => Output_Path,
         Header         => Zlib_Header,
         Mode           => Mode,
         Dictionary     => Dictionary,
         Use_Dictionary => True,
         Status         => Status);
   end Deflate_File_With_Dictionary_Streaming;

   procedure GZip_File_Streaming
     (Input_Path  : String;
      Output_Path : String;
      Mode        : Compression_Mode := Auto;
      Status      : out Status_Code) is
   begin
      Deflate_File_Streaming
        (Input_Path  => Input_Path,
         Output_Path => Output_Path,
         Header      => GZip,
         Mode        => Mode,
         Status      => Status);
   end GZip_File_Streaming;

   procedure Deflate_Raw_File_Streaming
     (Input_Path  : String;
      Output_Path : String;
      Mode        : Compression_Mode := Auto;
      Status      : out Status_Code) is
   begin
      Deflate_File_Streaming
        (Input_Path  => Input_Path,
         Output_Path => Output_Path,
         Header      => Raw_Deflate,
         Mode        => Mode,
         Status      => Status);
   end Deflate_Raw_File_Streaming;

   procedure Deflate_Raw_File_To_Stream_Internal
     (Input_Path      : String;
      Output          : in out Ada.Streams.Stream_IO.File_Type;
      Write_Output    : Boolean;
      Mode            : Compression_Mode;
      Compressed_Size : out Interfaces.Unsigned_64;
      Status          : out Status_Code)
   is
      Input_File    : SIO.File_Type;
      Filter        : Compression_Filter_Type;
      In_Buffer     :
        Ada.Streams.Stream_Element_Array (1 .. Streaming_File_Buffer_Size);
      Out_Buffer    :
        Ada.Streams.Stream_Element_Array (1 .. Streaming_File_Buffer_Size);
      Last_Read     : Ada.Streams.Stream_Element_Offset;
      In_Last       : Ada.Streams.Stream_Element_Offset;
      Out_Last      : Ada.Streams.Stream_Element_Offset;
      Operation     : Status_Code := Input_File_Error;
      Made_Progress : Boolean;

      procedure Account_Produced is
         Count : constant Natural := Produced (Out_Buffer, Out_Last);
      begin
         if Count > 0 then
            if Write_Output then
               Operation := Output_File_Error;
               Write_Produced (Output, Out_Buffer, Out_Last);
            end if;
            if Compressed_Size > Interfaces.Unsigned_64'Last - Interfaces.Unsigned_64 (Count) then
               raise Constraint_Error;
            end if;
            Compressed_Size := Compressed_Size + Interfaces.Unsigned_64 (Count);
         end if;
      end Account_Produced;
   begin
      Status := Ok;
      Compressed_Size := 0;

      begin
         SIO.Open (Input_File, SIO.In_File, Input_Path);
      exception
         when others =>
            Status := Input_File_Error;
            return;
      end;

      Deflate_Init (Filter, Raw_Deflate, Mode);

      while not SIO.End_Of_File (Input_File) loop
         Operation := Input_File_Error;
         SIO.Read (Input_File, In_Buffer, Last_Read);

         if Last_Read >= In_Buffer'First then
            declare
               Next_Input : Ada.Streams.Stream_Element_Offset :=
                 In_Buffer'First;
            begin
               while Next_Input <= Last_Read loop
                  Made_Progress := False;

                  declare
                     Before_Input :
                       constant Ada.Streams.Stream_Element_Offset :=
                         Next_Input;
                  begin
                     Compress
                       (Filter   => Filter,
                        In_Data  => In_Buffer (Next_Input .. Last_Read),
                        In_Last  => In_Last,
                        Out_Data => Out_Buffer,
                        Out_Last => Out_Last,
                        Flush    => No_Flush);

                     Account_Produced;

                     if Produced (Out_Buffer, Out_Last) > 0 then
                        Made_Progress := True;
                     end if;

                     if In_Last >= Before_Input then
                        Next_Input := In_Last + 1;
                        Made_Progress := True;
                     end if;
                  end;

                  if not Made_Progress then
                     raise Status_Error;
                  end if;
               end loop;
            end;
         end if;
      end loop;

      while not Compress_Stream_End (Filter) loop
         Made_Progress := False;

         Compress_Flush
           (Filter   => Filter,
            Out_Data => Out_Buffer,
            Out_Last => Out_Last,
            Flush    => Finish);

         Account_Produced;

         if Produced (Out_Buffer, Out_Last) > 0 then
            Made_Progress := True;
         end if;

         if not Compress_Stream_End (Filter) and then not Made_Progress then
            raise Status_Error;
         end if;
      end loop;

      Compress_Close (Filter, Ignore_Error => True);
      SIO.Close (Input_File);
      Status := Ok;

   exception
      when Zlib_Error | Status_Error =>
         Status := Unexpected_End_Of_Input;
         Compressed_Size := 0;
         if Is_Open (Filter) then
            Compress_Close (Filter, Ignore_Error => True);
         end if;
         if SIO.Is_Open (Input_File) then
            SIO.Close (Input_File);
         end if;

      when others =>
         Status := Operation;
         Compressed_Size := 0;
         if Is_Open (Filter) then
            Compress_Close (Filter, Ignore_Error => True);
         end if;
         if SIO.Is_Open (Input_File) then
            SIO.Close (Input_File);
         end if;
   end Deflate_Raw_File_To_Stream_Internal;

   procedure Deflate_Raw_File_Size
     (Input_Path      : String;
      Mode            : Compression_Mode := Auto;
      Compressed_Size : out Interfaces.Unsigned_64;
      Status          : out Status_Code)
   is
      Dummy : SIO.File_Type;
   begin
      Deflate_Raw_File_To_Stream_Internal
        (Input_Path      => Input_Path,
         Output          => Dummy,
         Write_Output    => False,
         Mode            => Mode,
         Compressed_Size => Compressed_Size,
         Status          => Status);
   end Deflate_Raw_File_Size;

   procedure Deflate_Raw_File_To_Stream
     (Input_Path      : String;
      Output          : in out Ada.Streams.Stream_IO.File_Type;
      Mode            : Compression_Mode := Auto;
      Compressed_Size : out Interfaces.Unsigned_64;
      Status          : out Status_Code)
   is
   begin
      Deflate_Raw_File_To_Stream_Internal
        (Input_Path      => Input_Path,
         Output          => Output,
         Write_Output    => True,
         Mode            => Mode,
         Compressed_Size => Compressed_Size,
         Status          => Status);
   end Deflate_Raw_File_To_Stream;

   procedure Deflate_Raw_Stored_File_To_Stream
     (Input_Path       : String;
      Output           : in out Ada.Streams.Stream_IO.File_Type;
      Compressed_Size  : out Interfaces.Unsigned_64;
      Status           : out Status_Code)
   is
   begin
      Deflate_Raw_File_To_Stream
        (Input_Path      => Input_Path,
         Output          => Output,
         Mode            => Stored,
         Compressed_Size => Compressed_Size,
         Status          => Status);
   end Deflate_Raw_Stored_File_To_Stream;

   procedure Inflate_Raw_File_Streaming
     (Input_Path : String; Output_Path : String; Status : out Status_Code) is
   begin
      Inflate_File_Streaming
        (Input_Path  => Input_Path,
         Output_Path => Output_Path,
         Header      => Raw_Deflate,
         Status      => Status);
   end Inflate_Raw_File_Streaming;

   procedure Inflate_File
     (Input_Path : String; Output_Path : String; Status : out Status_Code)
   is
      Input_Status  : Status_Code;
      Output_Status : Status_Code;
      Input         : constant Byte_Array :=
        Read_File (Input_Path, Input_Status);
   begin
      if Input_Status /= Ok then
         Status := Input_Status;
         return;
      end if;

      declare
         Output : constant Byte_Array := Inflate (Input, Status);
      begin
         if Status /= Ok then
            return;
         end if;

         Write_File (Output_Path, Output, Output_Status);
         Status := Output_Status;
      end;
   end Inflate_File;

   procedure Inflate_Raw_File
     (Input_Path : String; Output_Path : String; Status : out Status_Code)
   is
      Input_Status  : Status_Code;
      Output_Status : Status_Code;
      Input         : constant Byte_Array :=
        Read_File (Input_Path, Input_Status);
   begin
      if Input_Status /= Ok then
         Status := Input_Status;
         return;
      end if;

      declare
         Output : constant Byte_Array := Inflate_Raw (Input, Status);
      begin
         if Status /= Ok then
            return;
         end if;

         Write_File (Output_Path, Output, Output_Status);
         Status := Output_Status;
      end;
   end Inflate_Raw_File;

   procedure Deflate_Stored_File
     (Input_Path : String; Output_Path : String; Status : out Status_Code)
   is
      Input_Status  : Status_Code;
      Output_Status : Status_Code;
      Input         : constant Byte_Array :=
        Read_File (Input_Path, Input_Status);
   begin
      if Input_Status /= Ok then
         Status := Input_Status;
         return;
      end if;

      declare
         Output : constant Byte_Array := Deflate_Stored (Input, Status);
      begin
         if Status /= Ok then
            return;
         end if;

         Write_File (Output_Path, Output, Output_Status);
         Status := Output_Status;
      end;
   end Deflate_Stored_File;

   procedure Deflate_Fixed_File
     (Input_Path : String; Output_Path : String; Status : out Status_Code)
   is
      Input_Status  : Status_Code;
      Output_Status : Status_Code;
      Input         : constant Byte_Array :=
        Read_File (Input_Path, Input_Status);
   begin
      if Input_Status /= Ok then
         Status := Input_Status;
         return;
      end if;

      declare
         Output : constant Byte_Array := Deflate_Fixed (Input, Status);
      begin
         if Status /= Ok then
            return;
         end if;

         Write_File (Output_Path, Output, Output_Status);
         Status := Output_Status;
      end;
   end Deflate_Fixed_File;

   procedure Deflate_Dynamic_File
     (Input_Path : String; Output_Path : String; Status : out Status_Code)
   is
      Input_Status  : Status_Code;
      Output_Status : Status_Code;
      Input         : constant Byte_Array :=
        Read_File (Input_Path, Input_Status);
   begin
      if Input_Status /= Ok then
         Status := Input_Status;
         return;
      end if;

      declare
         Output : constant Byte_Array := Deflate_Dynamic (Input, Status);
      begin
         if Status /= Ok then
            return;
         end if;

         Write_File (Output_Path, Output, Output_Status);
         Status := Output_Status;
      end;
   end Deflate_Dynamic_File;

   procedure Deflate_File
     (Input_Path  : String;
      Output_Path : String;
      Level       : Compression_Level;
      Status      : out Status_Code)
   is
      Input_Status  : Status_Code;
      Output_Status : Status_Code;
      Input         : constant Byte_Array :=
        Read_File (Input_Path, Input_Status);
   begin
      if Input_Status /= Ok then
         Status := Input_Status;
         return;
      end if;

      declare
         Output : constant Byte_Array := Deflate (Input, Level, Status);
      begin
         if Status /= Ok then
            return;
         end if;

         Write_File (Output_Path, Output, Output_Status);
         Status := Output_Status;
      end;
   end Deflate_File;

   procedure Deflate_File
     (Input_Path  : String;
      Output_Path : String;
      Mode        : Compression_Mode := Auto;
      Status      : out Status_Code)
   is
      Input_Status  : Status_Code;
      Output_Status : Status_Code;
      Input         : constant Byte_Array :=
        Read_File (Input_Path, Input_Status);
   begin
      if Input_Status /= Ok then
         Status := Input_Status;
         return;
      end if;

      declare
         Output : constant Byte_Array := Deflate (Input, Mode, Status);
      begin
         if Status /= Ok then
            return;
         end if;

         Write_File (Output_Path, Output, Output_Status);
         Status := Output_Status;
      end;
   end Deflate_File;

   procedure Deflate_Raw_File
     (Input_Path  : String;
      Output_Path : String;
      Level       : Compression_Level;
      Status      : out Status_Code)
   is
      Input_Status  : Status_Code;
      Output_Status : Status_Code;
      Input         : constant Byte_Array :=
        Read_File (Input_Path, Input_Status);
   begin
      if Input_Status /= Ok then
         Status := Input_Status;
         return;
      end if;

      declare
         Output : constant Byte_Array := Deflate_Raw (Input, Level, Status);
      begin
         if Status /= Ok then
            return;
         end if;

         Write_File (Output_Path, Output, Output_Status);
         Status := Output_Status;
      end;
   end Deflate_Raw_File;

   procedure Deflate_Raw_File
     (Input_Path  : String;
      Output_Path : String;
      Mode        : Compression_Mode := Auto;
      Status      : out Status_Code)
   is
      Input_Status  : Status_Code;
      Output_Status : Status_Code;
      Input         : constant Byte_Array :=
        Read_File (Input_Path, Input_Status);
   begin
      if Input_Status /= Ok then
         Status := Input_Status;
         return;
      end if;

      declare
         Output : constant Byte_Array := Deflate_Raw (Input, Mode, Status);
      begin
         if Status /= Ok then
            return;
         end if;

         Write_File (Output_Path, Output, Output_Status);
         Status := Output_Status;
      end;
   end Deflate_Raw_File;

   procedure ZIP_File
     (Input_Path  : String;
      Output_Path : String;
      Entry_Name  : String;
      Mode        : Compression_Mode := Auto;
      Status      : out Status_Code)
   is
      Input_Status  : Status_Code;
      Output_Status : Status_Code;
      Input         : constant Byte_Array :=
        Read_File (Input_Path, Input_Status);
   begin
      if Input_Status /= Ok then
         Status := Input_Status;
         return;
      end if;

      declare
         Archive : constant Byte_Array := ZIP (Input, Entry_Name, Mode, Status);
      begin
         if Status /= Ok then
            return;
         end if;

         Write_File (Output_Path, Archive, Output_Status);
         Status := Output_Status;
      end;
   end ZIP_File;

   procedure GZip_File
     (Input_Path  : String;
      Output_Path : String;
      Level       : Compression_Level;
      Status      : out Status_Code) is
   begin
      GZip_File
        (Input_Path  => Input_Path,
         Output_Path => Output_Path,
         Level       => Level,
         Metadata    => No_GZip_Metadata,
         Status      => Status);
   end GZip_File;

   procedure GZip_File
     (Input_Path  : String;
      Output_Path : String;
      Level       : Compression_Level;
      Metadata    : GZip_Metadata;
      Status      : out Status_Code)
   is
      Input_Status  : Status_Code;
      Output_Status : Status_Code;
      Input         : constant Byte_Array :=
        Read_File (Input_Path, Input_Status);
   begin
      if Input_Status /= Ok then
         Status := Input_Status;
         return;
      end if;

      declare
         Output : constant Byte_Array := GZip (Input, Level, Metadata, Status);
      begin
         if Status /= Ok then
            return;
         end if;

         Write_File (Output_Path, Output, Output_Status);
         Status := Output_Status;
      end;
   end GZip_File;

   procedure GZip_File
     (Input_Path  : String;
      Output_Path : String;
      Mode        : Compression_Mode := Auto;
      Status      : out Status_Code) is
   begin
      GZip_File
        (Input_Path  => Input_Path,
         Output_Path => Output_Path,
         Mode        => Mode,
         Metadata    => No_GZip_Metadata,
         Status      => Status);
   end GZip_File;

   procedure GZip_File
     (Input_Path  : String;
      Output_Path : String;
      Mode        : Compression_Mode;
      Metadata    : GZip_Metadata;
      Status      : out Status_Code)
   is
      Input_Status  : Status_Code;
      Output_Status : Status_Code;
      Input         : constant Byte_Array :=
        Read_File (Input_Path, Input_Status);
   begin
      if Input_Status /= Ok then
         Status := Input_Status;
         return;
      end if;

      declare
         Output : constant Byte_Array := GZip (Input, Mode, Metadata, Status);
      begin
         if Status /= Ok then
            return;
         end if;

         Write_File (Output_Path, Output, Output_Status);
         Status := Output_Status;
      end;
   end GZip_File;

   procedure GZip_File_Members
     (Input_Paths : Text_Array;
      Output_Path : String;
      Mode        : Compression_Mode := Auto;
      Status      : out Status_Code)
   is
      Output        : Byte_Vectors.Vector;
      Read_Status   : Status_Code := Ok;
      Member_Status : Status_Code := Ok;
      Write_Status  : Status_Code := Ok;
   begin
      if Input_Paths'Length = 0 then
         Status := Unsupported_Method;
         return;
      end if;

      for I in Input_Paths'Range loop
         declare
            Input : constant Byte_Array :=
              Read_File (US.To_String (Input_Paths (I)), Read_Status);
         begin
            if Read_Status /= Ok then
               Status := Read_Status;
               return;
            end if;

            declare
               Member : constant Byte_Array := GZip (Input, Mode, Member_Status);
            begin
               if Member_Status /= Ok then
                  Status := Member_Status;
                  return;
               end if;
               Append_Bytes (Output, Member);
            end;
         end;
      end loop;

      Write_File (Output_Path, To_Byte_Array (Output), Write_Status);
      Status := Write_Status;
   exception
      when others =>
         Status := Output_File_Error;
   end GZip_File_Members;

end Zlib;
