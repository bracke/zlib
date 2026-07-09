with Ada.Containers.Vectors;
with Ada.Directories;
with Ada.Streams; use Ada.Streams;
with Ada.Streams.Stream_IO; use Ada.Streams.Stream_IO;
with Ada.Unchecked_Deallocation;
with Ada.Containers; use Ada.Containers;
with Interfaces.C;
with System.Address_To_Access_Conversions;

with CryptoLib.Checksums;
with Zlib.Block_Chooser; use Zlib.Block_Chooser;
with Zlib.Fixed_Compress;
with Zlib.Deflate_Tables;
with Zlib.Huffman_Builder;
with Zlib.LZ77_Matcher;
with Zlib.LZMA_Core;
with Zlib.LZMA2_Decoder;
with Zlib.LZMA2_Encoder;
with Zlib.LZMA_Decoder;
with Zlib.LZMA_Encoder;
with Zlib.LZMA_Encoder_Selection;
with Zlib.LZMA_Properties;
with Zlib.LZMA_Raw;
with Zlib.Stream_Bits;
with Zlib.Stream_Inflate;
with Zlib.Sliding_Window;
with Zlib.Archive_Listing;
with Zlib.Archive_Directory_Extraction;
with Zlib.Seven_Zip_BCJ2_Writing;
with Zlib.Seven_Zip_Codec_Packing;
with Zlib.Seven_Zip_Codec_Writing;
with Zlib.Seven_Zip_Filters;
with Zlib.Seven_Zip_Container;
with Zlib.Seven_Zip_Encrypted_Writing;
with Zlib.Seven_Zip_File_Extraction;
with Zlib.Seven_Zip_File_Writing;
with Zlib.Seven_Zip_Filtered_Writing;
with Zlib.Seven_Zip_Folder_Decoding;
with Zlib.Seven_Zip_Header_Encryption;
with Zlib.Seven_Zip_Header_Reading;
with Zlib.Seven_Zip_Listing;
with Zlib.Seven_Zip_Volumes;
with Zlib.PPMd7;
with Zlib.Seven_Zip_AES;
with Zlib.Seven_Zip_Methods; use Zlib.Seven_Zip_Methods;
with Zlib.Seven_Zip_Numbers;
with Zlib.Seven_Zip_Paths;
with Zlib.Seven_Zip_Properties;

package body Zlib is
   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned;
   use type System.Address;

   pragma Linker_Options ("-lbz2");
   pragma Linker_Options ("-lzstd");

   package SIO renames Ada.Streams.Stream_IO;
   package US renames Ada.Strings.Unbounded;

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

   function Contains_NUL (Text : String) return Boolean
     with SPARK_Mode => On
   is
   begin
      for Ch of Text loop
         if Character'Pos (Ch) = 0 then
            return True;
         end if;
      end loop;
      return False;
   end Contains_NUL;

   function Compute_Adler32 (Input : Byte_Array) return Interfaces.Unsigned_32 is
      State : CryptoLib.Checksums.Adler32_State;
   begin
      CryptoLib.Checksums.Adler32_Reset (State);
      for B of Input loop
         CryptoLib.Checksums.Adler32_Update (State, Ada.Streams.Stream_Element (B));
      end loop;
      return CryptoLib.Checksums.Adler32_Value (State);
   end Compute_Adler32;

   function Compute_CRC32 (Input : Byte_Array) return Interfaces.Unsigned_32 is
      State : CryptoLib.Checksums.CRC32_State;
   begin
      CryptoLib.Checksums.CRC32_Reset (State);
      for B of Input loop
         CryptoLib.Checksums.CRC32_Update (State, Ada.Streams.Stream_Element (B));
      end loop;
      return CryptoLib.Checksums.CRC32_Value (State);
   end Compute_CRC32;

   function Saturating_Compression_Bound
     (Input_Length : Natural;
      Wrapper_Size : Natural) return Natural
     with SPARK_Mode => On
   is
      Blocks : constant Natural :=
        (if Input_Length = 0
         then 1
         else Input_Length / Max_Compress_Block_Size
           + (if Input_Length mod Max_Compress_Block_Size = 0 then 0 else 1));
   begin
      if Input_Length > (Natural'Last - Wrapper_Size) / 2 then
         return Natural'Last;
      end if;

      declare
         Doubled : constant Natural := Input_Length * 2;
      begin
         if Blocks > (Natural'Last - Wrapper_Size - Doubled) / 512 then
            return Natural'Last;
         end if;

         return Doubled + Blocks * 512 + Wrapper_Size;
      end;
   end Saturating_Compression_Bound;

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
     (Metadata : in out GZip_Metadata; MTime : Interfaces.Unsigned_32)
     with SPARK_Mode => On
   is
   begin
      Metadata.Has_MTime := True;
      Metadata.MTime := MTime;
   end Set_MTime;

   procedure Set_OS (Metadata : in out GZip_Metadata; OS : Byte)
     with SPARK_Mode => On
   is
   begin
      Metadata.Has_OS := True;
      Metadata.OS := OS;
   end Set_OS;

   procedure Set_XFL (Metadata : in out GZip_Metadata; XFL : Byte)
     with SPARK_Mode => On
   is
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
     (Metadata : in out GZip_Metadata; Enabled : Boolean)
     with SPARK_Mode => On
   is
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

   function Has_Metadata (Metadata : GZip_Metadata) return Boolean
     with SPARK_Mode => On
   is
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
      return Ada.Streams.Stream_Element_Offset
     with SPARK_Mode => On
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

   function Mode_For_Level (Level : Compression_Level) return Compression_Mode
     with SPARK_Mode => On
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

      Filter.Dictionary_ID := Compute_Adler32 (Dictionary);
      Filter.Dictionary_Set := True;
   end Deflate_Set_Dictionary;

   function Is_Open (Filter : Compression_Filter_Type) return Boolean
     with SPARK_Mode => On
   is
   begin
      return
        Filter.State = Compression_Open
        or else Filter.State = Compression_Failed
        or else Filter.State = Compression_Ended;
   end Is_Open;

   function Compression_Mode_Supported
     (Filter : Compression_Filter_Type) return Boolean
     with SPARK_Mode => On
   is
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
     with SPARK_Mode => On
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
         CryptoLib.Checksums.CRC32_Update_Raw (Filter.CRC, B);
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
     (Filter : Compression_Filter_Type) return Interfaces.Unsigned_32
     with SPARK_Mode => On
   is
   begin
      return Filter.CRC xor 16#FFFF_FFFF#;
   end Compression_CRC32;

   function Compression_Adler
     (Filter : Compression_Filter_Type) return Interfaces.Unsigned_32
     with SPARK_Mode => On
   is
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
      Out_Last : Ada.Streams.Stream_Element_Offset) return Boolean
     with SPARK_Mode => On
   is
   begin
      return Out_Data'Length > 0 and then Out_Last = Out_Data'Last;
   end Compression_Output_Full;

   function Effective_Compression_Mode
     (Filter : Compression_Filter_Type) return Compression_Mode
     with SPARK_Mode => On
   is
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
     (Filter : Compression_Filter_Type) return Boolean
     with SPARK_Mode => On
   is
   begin
      return Effective_Compression_Mode (Filter) = Fixed;
   end Using_Fixed_Compression;

   function Using_Dynamic_Compression
     (Filter : Compression_Filter_Type) return Boolean
     with SPARK_Mode => On
   is
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

   function Reverse_Bits (Value : Natural; Count : Natural) return Natural
     with SPARK_Mode => On
   is
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

   function Length_Symbol_For (Length : Natural) return Natural
     with SPARK_Mode => On
   is
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

   function Distance_Symbol_For (Distance : Natural) return Natural
     with SPARK_Mode => On
   is
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
     (Filter : Compression_Filter_Type) return Stored_Compress_State
     with SPARK_Mode => On
   is
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
     (Filter : Compression_Filter_Type) return Boolean
     with SPARK_Mode => On
   is
   begin
      return
        Filter.Stored_Next = Collecting_Block
        or else Filter.Stored_Next = Fixed_Collecting_Block
        or else Filter.Stored_Next = Dynamic_Collecting_Block;
   end Is_Compression_Collecting;

   function Trailer_Start_State
     (Filter : Compression_Filter_Type) return Stored_Compress_State
     with SPARK_Mode => On
   is
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
     with SPARK_Mode => On
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
      CryptoLib.Checksums.CRC32_Update_Raw (Filter.GZip_Header_CRC, B);
   end Put_GZip_Header_Byte;

   function GZip_Header_CRC16
     (Filter : Compression_Filter_Type) return Interfaces.Unsigned_32
     with SPARK_Mode => On
   is
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
     (Filter : Compression_Filter_Type) return Boolean
     with SPARK_Mode => On
   is
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
      Last : Ada.Streams.Stream_Element_Offset) return Natural
     with SPARK_Mode => On
   is
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
      Mode : constant GZip_Member_Mode :=
        (if Header = GZip or else Header = Default then Multi_Member else Single_Member);
   begin
      Inflate_Init
        (Filter => Filter, Header => Header, GZip_Mode => Mode);
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
        (Decoder_State (Filter).all, Compute_Adler32 (Dictionary));
   end Inflate_Set_Dictionary;

   function Is_Open (Filter : Filter_Type) return Boolean
     with SPARK_Mode => On
   is
   begin
      return
        Filter.State = Open
        or else Filter.State = Failed
        or else Filter.State = Ended;
   end Is_Open;

   procedure Mark_Failed
     (Filter : in out Filter_Type;
      Status : Status_Code := Unexpected_End_Of_Input)
     with SPARK_Mode => On
   is
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

      if Zlib.Stream_Inflate.Active_Header (Decoder_State (Filter).all) /= Zlib.GZip then
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
      return Inflate_Auto (Input, Status);
   end Inflate;

   function Inflate_With_Header
     (Input : Byte_Array; Header : Header_Type; Status : out Status_Code)
      return Byte_Array is
   begin
      if Header = Default then
         return Inflate_Auto (Input, Status);
      end if;

      declare
         Empty : constant Byte_Array (1 .. 0) := [others => 0];
         Mode  : constant GZip_Member_Mode :=
           (if Header = GZip then Multi_Member else Single_Member);
      begin
         return
           Inflate_Internal
             (Input, Header, Mode, Status, Empty, False);
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
      if Header = Default then
         if Looks_Like_Zlib_Header (Input) then
            return Inflate_With_Header (Input, Zlib_Header, GZip_Mode, Status);
         elsif Looks_Like_GZip_Header (Input) then
            return Inflate_With_Header (Input, GZip, GZip_Mode, Status);
         else
            return Inflate_With_Header (Input, Raw_Deflate, GZip_Mode, Status);
         end if;
      end if;

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
     (Method : Interfaces.Unsigned_16) return Boolean
     with SPARK_Mode => On
   is
   begin
      return Method = 12
        or else Method = 14
        or else Method = 20
        or else Method = 93
        or else Method = 98;
   end Is_ZIP_External_Method;

   function ZIP_External_Method_Name
     (Method : Interfaces.Unsigned_16) return String
     with SPARK_Mode => On
   is
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

                                 if Compute_CRC32 (Plain) /= Crc then
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

                                 if Compute_CRC32 (Plain) /= Crc then
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

   LZMA_Default_Props   : constant Byte := Zlib.LZMA_Core.Default_Props;
   LZMA_Default_Dict    : constant Interfaces.Unsigned_32 := Zlib.LZMA_Core.Default_Dict;

   function Valid_LZMA_Props (Props : Byte) return Boolean
     renames Zlib.LZMA_Properties.Valid_Props;

   function LZMA_Encode_Selected_Impl is new
     Zlib.LZMA_Encoder_Selection (Zlib.LZMA_Encoder.Encode_Bounded);

   function LZMA_Encode_Selected
     (Plain : Byte_Array; Props : out Byte) return Byte_Array
     renames LZMA_Encode_Selected_Impl;

   function Decode_ZIP_LZMA_Payload
     (Payload    : Byte_Array;
      Plain_Len  : Natural;
      Status     : out Status_Code) return Byte_Array
   is
   begin
      return Zlib.LZMA_Decoder.Decode_Payload
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

                                 if Compute_CRC32 (Plain) /= Crc then
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
      Entry_Name    : String;
      Password      : String;
      Status        : out Status_Code) return Byte_Array
   is
      Empty        : constant Byte_Array (1 .. 0) := [others => 0];
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

   function ZIP_Method_Id (Method_Name : String) return Interfaces.Unsigned_16
     with SPARK_Mode => On
   is
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
                    (Archive_Image, Entry_Name, "", Status);
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
                             or else Compute_CRC32 (Plain) /= Crc
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
               Crc32 := Compute_CRC32 (Plain);
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
               Crc32 := Compute_CRC32 (Plain);
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
            LZMA_Props : Byte := LZMA_Default_Props;
            Raw_Output : constant Byte_Array :=
              LZMA_Encode_Selected (Plain, LZMA_Props);
            Props : constant Byte_Array (1 .. 5) :=
              [1 => LZMA_Props,
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
            Crc32 := Compute_CRC32 (Plain);
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
      Method_Name       : String;
      Method            : out Interfaces.Unsigned_16;
      Crc32             : out Interfaces.Unsigned_32;
      Uncompressed_Size : out Interfaces.Unsigned_64;
      Status            : out Status_Code) return Byte_Array
   is
      Empty        : constant Byte_Array (1 .. 0) := [others => 0];
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

   function Seven_Zip_Entry_Name_Valid (Entry_Name : String) return Boolean
     with SPARK_Mode => On;

   procedure Seven_Zip_PPMd_File
     (Input_Path  : String;
      Output_Path : String;
      Status      : out Status_Code)
   is
   begin
      Zlib.Seven_Zip_File_Writing.Write_PPMd_File_With_Basename
        (Input_Path, Output_Path, Read_File'Access, Write_File'Access,
         Zlib.Seven_Zip_Properties.Source_Metadata'Access, Status);
   end Seven_Zip_PPMd_File;

   procedure Seven_Zip_PPMd_File
     (Input_Path  : String;
      Output_Path : String;
      Entry_Name  : String;
      Status      : out Status_Code)
   is
   begin
      Zlib.Seven_Zip_File_Writing.Write_PPMd_File_Archive
        (Input_Path, Output_Path, Entry_Name, Read_File'Access,
         Write_File'Access, Zlib.Seven_Zip_Properties.Source_Metadata'Access,
         Status);
   end Seven_Zip_PPMd_File;

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
            CRC            : constant Interfaces.Unsigned_32 := Compute_CRC32 (Input);
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
                     CRC          => Compute_CRC32 (Input_Data),
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

   function Seven_Zip_U32_At
     (Data : Byte_Array;
      Pos  : Natural) return Interfaces.Unsigned_32
      renames Zlib.Seven_Zip_Numbers.U32_At;

   function Read_Seven_Zip_Number
     (Data  : Byte_Array;
      Pos   : in out Natural;
      Last  : Natural;
      Value : out Interfaces.Unsigned_64) return Boolean
      renames Zlib.Seven_Zip_Numbers.Read_Number;

   function Seven_Zip_Read_Byte
     (Data : Byte_Array;
      Pos  : in out Natural;
      Last : Natural;
      B    : out Byte) return Boolean
      renames Zlib.Seven_Zip_Container.Read_Byte;

   function Seven_Zip_Expect_Byte
     (Data     : Byte_Array;
      Pos      : in out Natural;
      Last     : Natural;
      Expected : Byte) return Boolean
      renames Zlib.Seven_Zip_Container.Expect_Byte;

   function Seven_Zip_Has_Bytes
     (Pos   : Natural;
      Last  : Natural;
      Count : Natural) return Boolean is
     (Zlib.Seven_Zip_Container.Has_Bytes (Pos, Last, Count))
     with SPARK_Mode => On;

   function Seven_Zip_Find_Signature
     (Data : Byte_Array;
      Pos  : out Natural) return Boolean
      renames Zlib.Seven_Zip_Container.Find_Signature;

   function Seven_Zip_Skip_Properties
     (Data : Byte_Array;
      Pos  : in out Natural;
      Last : Natural) return Boolean
      renames Zlib.Seven_Zip_Container.Skip_Properties;

   subtype Seven_Zip_U32_Array is Zlib.Seven_Zip_Container.U32_Array;
   subtype Seven_Zip_U64_Array is Zlib.Seven_Zip_Container.U64_Array;
   type Seven_Zip_Coder_Method_Array is
     array (Positive range <>) of Seven_Zip_Coder_Method;
   type Seven_Zip_LZMA_Props is array (Positive range 1 .. 5) of Byte;
   type Seven_Zip_LZMA_Props_Array is
     array (Positive range <>) of Seven_Zip_LZMA_Props;
   type Seven_Zip_Entry_Kind is
     (Seven_Zip_File_Entry, Seven_Zip_Directory_Entry);
   function Seven_Zip_Valid_PPMd_Props
     (Order  : Natural;
      Memory : Interfaces.Unsigned_32) return Boolean
     with SPARK_Mode => On
   is
   begin
      return Order in 2 .. 64
        and then Memory >= 2 ** 11
        and then Memory <= Interfaces.Unsigned_32'Last - 36;
   end Seven_Zip_Valid_PPMd_Props;

   function Seven_Zip_Bit_Is_Set
     (Data  : Byte_Array;
      First : Natural;
      Index : Natural) return Boolean
      renames Zlib.Seven_Zip_Properties.Bit_Is_Set;

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

   function LZMA2_Encode is new
     Zlib.LZMA2_Encoder (LZMA_Encode_Selected);

   function LZMA_Decode_Raw
     (Stream    : Byte_Array;
      Props     : Seven_Zip_LZMA_Props;
      Plain_Len : Natural;
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
      return Zlib.LZMA_Raw.Decode
        (Stream, Zlib.LZMA_Properties.LZMA_Properties (Props),
         Plain_Len, Status);
   end LZMA_Decode_Raw;

   function LZMA_Decode_Raw_Encoded_Header
     (Stream    : Byte_Array;
      Props     : Seven_Zip_LZMA_Props;
      Plain_Len : Natural;
      Status    : out Status_Code) return Byte_Array
   is
   begin
      return Zlib.LZMA_Raw.Decode_Encoded_Header
        (Stream, Zlib.LZMA_Properties.LZMA_Properties (Props),
         Plain_Len, Status);
   end LZMA_Decode_Raw_Encoded_Header;

   function LZMA2_Decode
     (Payload   : Byte_Array;
      Plain_Len : Natural;
      Status    : out Status_Code) return Byte_Array
     renames Zlib.LZMA2_Decoder.Decode;

   function Seven_Zip_Entry_Name_Valid (Entry_Name : String) return Boolean is
     (Zlib.Seven_Zip_Paths.Entry_Name_Valid (Entry_Name))
     with SPARK_Mode => On;

   function Seven_Zip_Output_File_Writable (Output_Path : String) return Boolean
      renames Zlib.Seven_Zip_Paths.Output_File_Writable;

   function Seven_Zip_Input_Path_Readable (Input_Path : String) return Boolean
      renames Zlib.Seven_Zip_Paths.Input_Path_Readable;

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
      function Encode_LZMA
        (Input_Data : Byte_Array;
         LZMA_Props : in out Byte) return Byte_Array is
      begin
         return LZMA_Encode_Selected (Input_Data, LZMA_Props);
      end Encode_LZMA;
   begin
      return
        Zlib.Seven_Zip_Encrypted_Writing.Build_AES_LZMA
          (Input, Entry_Name, Password, Encode_LZMA'Access, Status);
   end Seven_Zip_LZMA_Encrypted;

   --  Build a one-file .7z whose data is BCJ2-filtered (method 0303011B): a
   --  single BCJ2 coder with four packed streams (main, call, jump, range),
   --  stored uncompressed, exactly as stock "7z a -m0=BCJ2" lays it out.
   function Seven_Zip_BCJ2
     (Input      : Byte_Array;
      Entry_Name : String;
      Status     : out Status_Code) return Byte_Array
   is
   begin
      return Zlib.Seven_Zip_BCJ2_Writing.Build_BCJ2
        (Input, Entry_Name, Status);
   end Seven_Zip_BCJ2;

   function Seven_Zip_Stored_With_Metadata
     (Input      : Byte_Array;
      Entry_Name : String;
      Metadata   : Seven_Zip_Entry_Metadata;
      Status     : out Status_Code) return Byte_Array
   is
   begin
      return
        Zlib.Seven_Zip_Codec_Writing.Build_Copy
          (Input, Entry_Name, Metadata, Status);
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
      function Compress_Deflate
        (Input_Data : Byte_Array;
         Status     : out Status_Code) return Byte_Array
      is
      begin
         return Deflate_Raw (Input_Data, Mode, Status);
      end Compress_Deflate;
   begin
      return
        Zlib.Seven_Zip_Codec_Writing.Build_Deflate
          (Input, Entry_Name, Metadata, Compress_Deflate'Access, Status);
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
      function Compress_Deflate
        (Input_Data : Byte_Array;
         Status     : out Status_Code) return Byte_Array
      is
      begin
         return Deflate_Raw (Input_Data, Level, Status);
      end Compress_Deflate;
   begin
      return
        Zlib.Seven_Zip_Codec_Writing.Build_Deflate
          (Input, Entry_Name, Metadata, Compress_Deflate'Access, Status);
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
      function Compress_BZip2
        (Input_Data : Byte_Array;
         Status     : out Status_Code) return Byte_Array
      is
      begin
         return BZip2_Compress (Input_Data, Status);
      end Compress_BZip2;
   begin
      return
        Zlib.Seven_Zip_Codec_Writing.Build_BZip2
          (Input, Entry_Name, Metadata, Compress_BZip2'Access, Status);
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
      function Encode_LZMA
        (Input_Data : Byte_Array;
         LZMA_Props : in out Byte) return Byte_Array
      is
      begin
         return LZMA_Encode_Selected (Input_Data, LZMA_Props);
      end Encode_LZMA;
   begin
      return
        Zlib.Seven_Zip_Codec_Writing.Build_LZMA
          (Input, Entry_Name, Metadata, Encode_LZMA'Access, Status);
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
      return
        Zlib.Seven_Zip_Codec_Writing.Build_LZMA2
          (Input, Entry_Name, Metadata, LZMA2_Encode'Access, Status);
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
      return
        Zlib.Seven_Zip_Codec_Writing.Build_PPMd
          (Input, Entry_Name, Metadata, Status);
   end Seven_Zip_PPMd;

   function Seven_Zip_Pack_Filtered
     (Input  : Byte_Array;
      Codec  : Seven_Zip_Codec_Method;
      LZMA_Props : out Byte;
      Status : out Status_Code) return Byte_Array
   is
      function Pack_Deflate
        (Input_Data : Byte_Array;
         Status     : out Status_Code) return Byte_Array is
      begin
         return Deflate_Raw (Input_Data, Auto, Status);
      end Pack_Deflate;

      function Pack_BZip2
        (Input_Data : Byte_Array;
         Status     : out Status_Code) return Byte_Array is
      begin
         return BZip2_Compress (Input_Data, Status);
      end Pack_BZip2;

      function Pack_LZMA
        (Input_Data : Byte_Array;
         Props      : in out Byte) return Byte_Array is
      begin
         return LZMA_Encode_Selected (Input_Data, Props);
      end Pack_LZMA;

      function Pack_LZMA2 (Input_Data : Byte_Array) return Byte_Array is
      begin
         return LZMA2_Encode (Input_Data);
      end Pack_LZMA2;
   begin
      return
        Zlib.Seven_Zip_Codec_Packing.Pack_Filtered
          (Input, Codec, LZMA_Default_Props, Pack_Deflate'Access,
           Pack_BZip2'Access, Pack_LZMA'Access, Pack_LZMA2'Access,
           LZMA_Props, Status);
   end Seven_Zip_Pack_Filtered;

   function Seven_Zip_Filtered
     (Input      : Byte_Array;
      Entry_Name : String;
      Filter     : Seven_Zip_Filter_Method;
      Codec      : Seven_Zip_Codec_Method := Seven_Zip_Codec_LZMA;
      Status     : out Status_Code) return Byte_Array
   is
   begin
      return
        Seven_Zip_Filtered
          (Input, Entry_Name, Filter, Codec, 1,
           No_Seven_Zip_Entry_Metadata, Status);
   end Seven_Zip_Filtered;

   function Seven_Zip_Filtered
     (Input          : Byte_Array;
      Entry_Name     : String;
      Filter         : Seven_Zip_Filter_Method;
      Codec          : Seven_Zip_Codec_Method;
      Delta_Distance : Positive;
      Metadata       : Seven_Zip_Entry_Metadata;
      Status         : out Status_Code) return Byte_Array
   is
   begin
      return
        Zlib.Seven_Zip_Filtered_Writing.Build_Filtered
          (Input, Entry_Name, Filter, Codec, Delta_Distance, Metadata,
           Seven_Zip_Pack_Filtered'Access, Status);
   end Seven_Zip_Filtered;

   function Seven_Zip_Method_Graph
     (Packed_Data    : Byte_Array;
      Entry_Name     : String;
      Coders         : Seven_Zip_Graph_Coder_Array;
      Bind_Pairs     : Seven_Zip_Bind_Pair_Array;
      Packed_Streams : Seven_Zip_Stream_Index_Array;
      Pack_Sizes     : Seven_Zip_Size_Array;
      Unpack_Sizes   : Seven_Zip_Size_Array;
      Unpacked_CRC   : Interfaces.Unsigned_32;
      Metadata       : Seven_Zip_Entry_Metadata;
      Status         : out Status_Code) return Byte_Array is
   begin
      return
        Zlib.Seven_Zip_Codec_Writing.Build_Method_Graph
          (Packed_Data, Entry_Name, Coders, Bind_Pairs, Packed_Streams,
           Pack_Sizes, Unpack_Sizes, Unpacked_CRC, Metadata, Status);
   end Seven_Zip_Method_Graph;

   procedure Seven_Zip_Stored_File
     (Input_Path  : String;
      Output_Path : String;
      Entry_Name  : String;
      Status      : out Status_Code)
   is
   begin
      Zlib.Seven_Zip_File_Writing.Write_Stored_File_Archive
        (Input_Path, Output_Path, Entry_Name, Read_File'Access,
         Write_File'Access, Zlib.Seven_Zip_Properties.Source_Metadata'Access,
         Status);
   end Seven_Zip_Stored_File;

   procedure Seven_Zip_Deflate_File
     (Input_Path  : String;
      Output_Path : String;
      Entry_Name  : String;
      Mode        : Compression_Mode;
      Status      : out Status_Code)
   is
      function Compress_Deflate
        (Input  : Byte_Array;
         Status : out Status_Code) return Byte_Array is
      begin
         return Deflate_Raw (Input, Mode, Status);
      end Compress_Deflate;
   begin
      Zlib.Seven_Zip_File_Writing.Write_Deflate_File_Archive
        (Input_Path, Output_Path, Entry_Name, Read_File'Access,
         Write_File'Access, Zlib.Seven_Zip_Properties.Source_Metadata'Access,
         Compress_Deflate'Access, Status);
   end Seven_Zip_Deflate_File;

   procedure Seven_Zip_Deflate_File
     (Input_Path  : String;
      Output_Path : String;
      Entry_Name  : String;
      Level       : Compression_Level;
      Status      : out Status_Code)
   is
      function Compress_Deflate
        (Input  : Byte_Array;
         Status : out Status_Code) return Byte_Array is
      begin
         return Deflate_Raw (Input, Level, Status);
      end Compress_Deflate;
   begin
      Zlib.Seven_Zip_File_Writing.Write_Deflate_File_Archive
        (Input_Path, Output_Path, Entry_Name, Read_File'Access,
         Write_File'Access, Zlib.Seven_Zip_Properties.Source_Metadata'Access,
         Compress_Deflate'Access, Status);
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
      function Compress_BZip2
        (Input  : Byte_Array;
         Status : out Status_Code) return Byte_Array is
      begin
         return BZip2_Compress (Input, Status);
      end Compress_BZip2;
   begin
      Zlib.Seven_Zip_File_Writing.Write_BZip2_File_Archive
        (Input_Path, Output_Path, Entry_Name, Read_File'Access,
         Write_File'Access, Zlib.Seven_Zip_Properties.Source_Metadata'Access,
         Compress_BZip2'Access, Status);
   end Seven_Zip_BZip2_File;

   procedure Seven_Zip_LZMA_File
     (Input_Path  : String;
      Output_Path : String;
      Entry_Name  : String;
      Status      : out Status_Code)
   is
      function Encode_LZMA
        (Input      : Byte_Array;
         LZMA_Props : in out Byte) return Byte_Array is
      begin
         return LZMA_Encode_Selected (Input, LZMA_Props);
      end Encode_LZMA;
   begin
      Zlib.Seven_Zip_File_Writing.Write_LZMA_File_Archive
        (Input_Path, Output_Path, Entry_Name, Read_File'Access,
         Write_File'Access, Zlib.Seven_Zip_Properties.Source_Metadata'Access,
         Encode_LZMA'Access, Status);
   end Seven_Zip_LZMA_File;

   procedure Seven_Zip_LZMA2_File
     (Input_Path  : String;
      Output_Path : String;
      Entry_Name  : String;
      Status      : out Status_Code)
   is
   begin
      Zlib.Seven_Zip_File_Writing.Write_LZMA2_File_Archive
        (Input_Path, Output_Path, Entry_Name, Read_File'Access,
         Write_File'Access, Zlib.Seven_Zip_Properties.Source_Metadata'Access,
         LZMA2_Encode'Access, Status);
   end Seven_Zip_LZMA2_File;

   procedure Seven_Zip_Stored_Files
     (Input_Paths : Text_Array;
      Output_Path : String;
      Entry_Names : Text_Array;
      Status      : out Status_Code)
   is
   begin
      Zlib.Seven_Zip_File_Writing.Write_Stored_File_List
        (Input_Paths, Output_Path, Entry_Names, Read_File'Access,
         Write_File'Access, Zlib.Seven_Zip_Properties.Source_Metadata'Access,
         Status);
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
      function Pack_Deflate_Mode
        (Input       : Byte_Array;
         Mode        : Compression_Mode;
         Pack_Status : out Status_Code) return Byte_Array is
      begin
         return Deflate_Raw (Input, Mode, Pack_Status);
      end Pack_Deflate_Mode;

      function Pack_Deflate_Level
        (Input       : Byte_Array;
         Level       : Compression_Level;
         Pack_Status : out Status_Code) return Byte_Array is
      begin
         return Deflate_Raw (Input, Level, Pack_Status);
      end Pack_Deflate_Level;

      function Pack_BZip2
        (Input       : Byte_Array;
         Pack_Status : out Status_Code) return Byte_Array is
      begin
         return BZip2_Compress (Input, Pack_Status);
      end Pack_BZip2;

      function Pack_LZMA
        (Input : Byte_Array;
         Props : in out Byte) return Byte_Array is
      begin
         return LZMA_Encode_Selected (Input, Props);
      end Pack_LZMA;

      function Pack_LZMA2 (Input : Byte_Array) return Byte_Array is
      begin
         return LZMA2_Encode (Input);
      end Pack_LZMA2;
   begin
      Zlib.Seven_Zip_File_Writing.Write_Compressed_File_List_Selected
        (Input_Paths, Output_Path, Entry_Names, Method, Mode, Level, Use_Level,
         Solid, Password, Read_File'Access, Write_File'Access,
         Zlib.Seven_Zip_Properties.Source_Metadata'Access,
         Pack_Deflate_Mode'Access, Pack_Deflate_Level'Access,
         Pack_BZip2'Access, Pack_LZMA'Access, Pack_LZMA2'Access,
         LZMA_Default_Props, Status);
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
      Password      : String;
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
            Info : Zlib.Seven_Zip_Container.Start_Header_Info;
         begin
            if not Zlib.Seven_Zip_Container.Read_Start_Header
              (Archive_Image, F, Info, Status)
            then
               return Empty;
            end if;

            declare
               Payload_First : constant Natural := Info.Payload_First;
               Payload_Count : constant Natural := Info.Payload_Count;
               Header_First  : constant Natural := Info.Header_First;
               Header_Last   : constant Natural := Info.Header_Last;
               Header_Count  : constant Natural := Info.Header_Count;
               Pos           : Natural := Header_First;
               Value         : Interfaces.Unsigned_64 := 0;
               B             : Byte := 0;
            begin
                  if Archive_Image (Header_First) = 16#17# then
                     declare
                        function Decode_Header_Payload
                          (Input          : Byte_Array;
                           Method         : Seven_Zip_Coder_Method;
                           LZMA_Props     : Byte_Array;
                           Expected_Size  : Natural;
                           Delta_Distance : Positive;
                           PPMd_Order     : Natural;
                           PPMd_Memory    : Interfaces.Unsigned_32;
                           Decode_Status  : out Status_Code) return Byte_Array
                        is
                           Props : Seven_Zip_LZMA_Props := [others => 0];
                        begin
                           Decode_Status := Ok;

                           case Method is
                              when Seven_Zip_Copy =>
                                 return Input;

                              when Seven_Zip_Deflate_Method =>
                                 return Inflate_Raw_Exact (Input, Decode_Status);

                              when Seven_Zip_BZip2_Method =>
                                 return BZip2_Decompress
                                   (Input, Expected_Size, Decode_Status);

                              when Seven_Zip_LZMA_Method =>
                                 if LZMA_Props'Length /= Props'Length then
                                    Decode_Status := Unsupported_Method;
                                    return Empty;
                                 end if;

                                 for Offset in 0 .. Props'Length - 1 loop
                                    Props (Props'First + Offset) :=
                                      LZMA_Props (LZMA_Props'First + Offset);
                                 end loop;

                                 return LZMA_Decode_Raw_Encoded_Header
                                   (Input, Props, Expected_Size, Decode_Status);

                              when Seven_Zip_LZMA2_Method =>
                                 return LZMA2_Decode
                                   (Input, Expected_Size, Decode_Status);

                              when Seven_Zip_Delta_Method =>
                                 return Zlib.Seven_Zip_Filters.Delta_Decode_Checked
                                   (Input, Delta_Distance, Decode_Status);

                              when Seven_Zip_BCJ_X86_Method =>
                                 return Zlib.Seven_Zip_Filters.X86_BCJ_Decode
                                   (Input, Decode_Status);

                              when Seven_Zip_BCJ_ARM_Method
                                 | Seven_Zip_BCJ_ARMT_Method
                                 | Seven_Zip_BCJ_PPC_Method
                                 | Seven_Zip_BCJ_SPARC_Method
                                 | Seven_Zip_BCJ_ARM64_Method
                                 | Seven_Zip_BCJ_IA64_Method
                                 | Seven_Zip_BCJ_RISCV_Method =>
                                 return Zlib.Seven_Zip_Filters.Branch_Convert
                                   (Branch_Arch_Of (Method), Input,
                                    Encoding => False);

                              when Seven_Zip_PPMd_Method =>
                                 return Zlib.PPMd7.Decompress
                                   (Input, Expected_Size, PPMd_Order,
                                    PPMd_Memory, Decode_Status);

                              when Seven_Zip_BCJ2_Method | Seven_Zip_AES_Method =>
                                 Decode_Status := Unsupported_Method;
                                 return Empty;
                           end case;
                        end Decode_Header_Payload;

                        Encoded_Header_Pack_Pos : Natural := 0;
                        Header_Status           : Status_Code := Ok;
                        Decoded_Header          : constant Byte_Array :=
                          Zlib.Seven_Zip_Header_Reading.Decode_Encoded_Header
                            (Archive_Image, Password, Info,
                             Decode_Header_Payload'Access,
                             Encoded_Header_Pack_Pos, Header_Status);
                     begin
                        if Header_Status /= Ok then
                           Status := Header_Status;
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
                           Synthetic_Payload : constant Byte_Array :=
                             (if Encoded_Header_Pack_Pos = 0
                              then Empty
                              else Archive_Image
                                (Payload_First ..
                                 Payload_First + Encoded_Header_Pack_Pos - 1));
                           Synthetic_Image : constant Byte_Array :=
                             Zlib.Seven_Zip_Container.Build_Archive
                               (Normalized_Header, Synthetic_Payload);
                        begin
                           return Extract_Seven_Zip_Entry
                             (Synthetic_Image, Entry_Name, Password, Status, Kind,
                              Metadata);
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
                        File_Count : constant Natural := Natural (Value);
                        Target_File : Zlib.Seven_Zip_Properties.Files_Info_Target;
                        Stream_Count : Natural := 0;
                     begin
                        if not Zlib.Seven_Zip_Properties.Read_Target_Entry
                          (Archive_Image, Pos, Header_Last, File_Count,
                           Entry_Name, Target_File, Stream_Count)
                          or else Stream_Count > File_Count
                          or else not Seven_Zip_Read_Byte
                            (Archive_Image, Pos, Header_Last, B)
                          or else B /= 0
                          or else Pos /= Header_Last + 1
                          or else Target_File.Has_Stream
                        then
                           return Empty;
                        end if;

                        if Target_File.Is_Directory then
                           Kind := Seven_Zip_Directory_Entry;
                        else
                           Kind := Seven_Zip_File_Entry;
                        end if;

                        Metadata := Target_File.Metadata;

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
                     Max_Folder_Coders : constant :=
                       Zlib.Seven_Zip_Folder_Decoding.Max_Folder_Coders;
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
                               Seven_Zip_LZMA_Props
                                 (Zlib.LZMA_Properties.Default_Dict_Properties
                                    (LZMA_Default_Props))]];
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
                          Seven_Zip_LZMA_Props
                            (Zlib.LZMA_Properties.Default_Dict_Properties
                               (LZMA_Default_Props))];
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
                                    Parsed_Method : Seven_Zip_Coder_Method :=
                                      Seven_Zip_Copy;
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

                                    if not Method_For_ID
                                      (ID, ID_Size, Parsed_Method)
                                    then
                                       return Empty;
                                    end if;

                                    if Is_Propertyless_Coder (Parsed_Method) then
                                       if Has_Streams or else Has_Props then
                                          return Empty;
                                       end if;
                                    else
                                       case Parsed_Method is
                                          when Seven_Zip_LZMA_Method =>
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
                                            (Folder_LZMA_Props
                                               (I, Coder_Index) (1))
                                          then
                                             return Empty;
                                          end if;

                                          when Seven_Zip_PPMd_Method =>
                                          if Has_Streams
                                            or else not Has_Props
                                            or else not Read_Seven_Zip_Number
                                              (Archive_Image, Pos, Header_Last,
                                               Prop_Size)
                                            or else Prop_Size /= 5
                                            or else not Seven_Zip_Read_Byte
                                              (Archive_Image, Pos, Header_Last,
                                               B)
                                            or else not Seven_Zip_Has_Bytes
                                              (Pos, Header_Last, 4)
                                          then
                                             return Empty;
                                          end if;

                                          Folder_PPMd_Orders (I, Coder_Index) :=
                                            Natural (B);
                                          Folder_PPMd_Memories
                                            (I, Coder_Index) :=
                                            Seven_Zip_U32_At
                                              (Archive_Image, Pos);
                                          if not Seven_Zip_Valid_PPMd_Props
                                            (Folder_PPMd_Orders
                                               (I, Coder_Index),
                                             Folder_PPMd_Memories
                                               (I, Coder_Index))
                                          then
                                             return Empty;
                                          end if;
                                          Pos := Pos + 4;

                                          when Seven_Zip_LZMA2_Method =>
                                          if Has_Streams
                                            or else not Has_Props
                                            or else not Read_Seven_Zip_Number
                                              (Archive_Image, Pos, Header_Last,
                                               Prop_Size)
                                            or else Prop_Size /= 1
                                            or else not Seven_Zip_Read_Byte
                                              (Archive_Image, Pos, Header_Last,
                                               B)
                                            or else B > 40
                                          then
                                             return Empty;
                                          end if;

                                          when Seven_Zip_Delta_Method =>
                                          if Has_Streams
                                            or else not Has_Props
                                            or else not Read_Seven_Zip_Number
                                              (Archive_Image, Pos, Header_Last,
                                               Prop_Size)
                                            or else Prop_Size /= 1
                                            or else not Seven_Zip_Read_Byte
                                              (Archive_Image, Pos, Header_Last,
                                               B)
                                          then
                                             return Empty;
                                          end if;
                                          Folder_Delta_Distances
                                            (I, Coder_Index) := Natural (B) + 1;

                                          when Seven_Zip_AES_Method =>
                                          --  7zAES (AES-256 + SHA-256).
                                          if Has_Streams
                                            or else not Has_Props
                                            or else not Read_Seven_Zip_Number
                                              (Archive_Image, Pos, Header_Last,
                                               Prop_Size)
                                            or else Prop_Size < 1
                                            or else not Seven_Zip_Has_Bytes
                                              (Pos, Header_Last,
                                               Natural (Prop_Size))
                                          then
                                             return Empty;
                                          end if;

                                          declare
                                             PB : Byte_Array
                                               (1 .. Natural (Prop_Size));
                                             B0, B1 : Natural := 0;
                                             Salt_Sz : Natural := 0;
                                             IV_Sz   : Natural := 0;
                                             PP      : Natural := 0;
                                          begin
                                             for J in PB'Range loop
                                                PB (J) := Archive_Image (Pos);
                                                Pos := Pos + 1;
                                             end loop;

                                             B0 := Natural (PB (1));
                                             Folder_AES_Cycles
                                               (I, Coder_Index) := B0 mod 64;
                                             if (B0 / 64) /= 0
                                               and then Natural (Prop_Size) >= 2
                                             then
                                                B1 := Natural (PB (2));
                                                PP := 3;
                                             else
                                                PP := 2;
                                             end if;

                                             Salt_Sz :=
                                               ((B0 / 128) mod 2) + (B1 / 16);
                                             IV_Sz :=
                                               ((B0 / 64) mod 2) + (B1 mod 16);
                                             if Salt_Sz > 16
                                               or else IV_Sz > 16
                                               or else Natural (Prop_Size) <
                                                 (PP - 1) + Salt_Sz + IV_Sz
                                             then
                                                return Empty;
                                             end if;

                                             Folder_AES_Salt_Len
                                               (I, Coder_Index) := Salt_Sz;
                                             Folder_AES_IV_Len
                                               (I, Coder_Index) := IV_Sz;
                                             for J in 1 .. Salt_Sz loop
                                                Folder_AES_Salt
                                                  (I, Coder_Index) (J) :=
                                                  PB (PP + J - 1);
                                             end loop;
                                             for J in 1 .. IV_Sz loop
                                                Folder_AES_IV
                                                  (I, Coder_Index) (J) :=
                                                  PB (PP + Salt_Sz + J - 1);
                                             end loop;
                                          end;

                                       when Seven_Zip_BCJ2_Method =>
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

                                          when others =>
                                             return Empty;
                                       end case;
                                    end if;

                                    Folder_Methods (I, Coder_Index) :=
                                      Parsed_Method;

                                    if Folder_Methods (I, Coder_Index) /=
                                      Seven_Zip_BCJ2_Method
                                      and then (In_Streams /= 1
                                                or else Out_Streams /= 1)
                                    then
                                       return Empty;
                                    end if;
                                 end;
                              end loop;

                              declare
                                 Graph_Methods :
                                   Zlib.Seven_Zip_Folder_Decoding
                                     .Folder_Method_Array (1 .. Coder_Count);
                                 Graph_Info :
                                   Zlib.Seven_Zip_Folder_Decoding
                                     .Folder_Graph_Info;
                              begin
                                 for Coder_Index in 1 .. Coder_Count loop
                                    Graph_Methods (Coder_Index) :=
                                      Folder_Methods (I, Coder_Index);
                                 end loop;

                                 if not Zlib.Seven_Zip_Folder_Decoding
                                   .Analyze_Bind_Pairs
                                     (Archive_Image, Pos, Header_Last,
                                      Coder_Count, Graph_Methods, Graph_Info)
                                 then
                                    return Empty;
                                 end if;

                                 Folder_Packed_Coder (I) :=
                                   Graph_Info.Packed_Coder;
                                 Folder_Terminal_Coder (I) :=
                                   Graph_Info.Terminal_Coder;
                                 Folder_Reverse_Chain (I) :=
                                   Graph_Info.Reverse_Chain;
                                 Folder_Pack_Count (I) := Graph_Info.Pack_Count;
                                 Folder_Pack_Indices_Read (I) :=
                                   Graph_Info.Pack_Indices_Read;

                                 for Coder_Index in 1 .. Coder_Count loop
                                    Folder_Next_Coder (I, Coder_Index) :=
                                      Graph_Info.Next_Coder (Coder_Index);
                                 end loop;
                              end;

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
                        File_Count : constant Natural := Natural (Value);
                        Target_File : Zlib.Seven_Zip_Properties.Files_Info_Target;
                        File_Stream_Count : Natural := 0;
                     begin
                        if not Zlib.Seven_Zip_Properties.Read_Target_Entry
                          (Archive_Image, Pos, Header_Last, File_Count,
                           Entry_Name, Target_File, File_Stream_Count)
                        then
                           return Empty;
                        end if;

                        Metadata := Target_File.Metadata;

                        if not Target_File.Has_Stream then
                           if Target_File.Is_Directory then
                              Kind := Seven_Zip_Directory_Entry;
                           else
                              Kind := Seven_Zip_File_Entry;
                           end if;

                           Status := Ok;
                           return Empty;
                        end if;

                        Target_Index := Target_File.Stream_Index;

                        if File_Stream_Count /= Substream_Count
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

                           function Substream_Folder_At
                             (Index : Natural) return Natural is
                             (Substream_Folders (Index));

                           function Substream_Size_At
                             (Index : Natural) return Interfaces.Unsigned_64 is
                             (Substream_Sizes (Index));

                           function Substream_CRC_Defined_At
                             (Index : Natural) return Boolean is
                             (Substream_CRC_Defined (Index));

                           function Substream_CRC_At
                             (Index : Natural) return Interfaces.Unsigned_32 is
                             (Substream_CRCs (Index));

                           function Validate_And_Slice
                             (Plain : Byte_Array) return Byte_Array
                           is
                              Slice_Status : Status_Code := Ok;
                              Result       : constant Byte_Array :=
                                Zlib.Seven_Zip_Folder_Decoding
                                  .Validate_And_Slice_Substream
                                    (Plain, Target_Folder_Index, Target_Index,
                                     Unpack_Sizes (Target_Folder_Index),
                                     Unpack_CRC_Defined (Target_Folder_Index),
                                     Unpack_CRCs (Target_Folder_Index),
                                     Substream_Folder_At'Access,
                                     Substream_Size_At'Access,
                                     Substream_CRC_Defined_At'Access,
                                     Substream_CRC_At'Access,
                                     Slice_Status);
                           begin
                              if Slice_Status /= Ok then
                                 Status := Slice_Status;
                                 return Empty;
                              end if;

                              Status := Ok;
                              return Result;
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

                              Coder_Count : constant Natural :=
                                Folder_Coder_Count (Target_Folder_Index);
                              Coders :
                                Zlib.Seven_Zip_Folder_Decoding
                                  .Folder_Coder_Array (1 .. Coder_Count);
                              Links :
                                Zlib.Seven_Zip_Folder_Decoding
                                  .Coder_Link_Array := [others => 0];

                              function Decode_Core_Coder
                                (Input         : Byte_Array;
                                 Method        : Seven_Zip_Coder_Method;
                                 Props_In      : Byte_Array;
                                 Expected_Size : Natural;
                                 Decode_Status : out Status_Code)
                                 return Byte_Array
                              is
                                 Props : Seven_Zip_LZMA_Props := [others => 0];
                              begin
                                 case Method is
                                    when Seven_Zip_Deflate_Method =>
                                       return Inflate_Raw_Exact
                                         (Input, Decode_Status);

                                    when Seven_Zip_BZip2_Method =>
                                       return BZip2_Decompress
                                         (Input, Expected_Size, Decode_Status);

                                    when Seven_Zip_LZMA_Method =>
                                       if Props_In'Length /= Props'Length then
                                          Decode_Status := Unsupported_Method;
                                          return Empty;
                                       end if;

                                       for Offset in 0 .. Props'Length - 1 loop
                                          Props (Props'First + Offset) :=
                                            Props_In (Props_In'First + Offset);
                                       end loop;

                                       return LZMA_Decode_Raw
                                         (Input, Props, Expected_Size,
                                          Decode_Status);

                                    when Seven_Zip_LZMA2_Method =>
                                       return LZMA2_Decode
                                         (Input, Expected_Size, Decode_Status);

                                    when others =>
                                       Decode_Status := Unsupported_Method;
                                       return Empty;
                                 end case;
                              end Decode_Core_Coder;

                              Chain_Status : Status_Code := Ok;
                           begin
                              for Coder_Index in 1 .. Coder_Count loop
                                 Coders (Coder_Index) :=
                                   (Method         => Folder_Methods
                                                        (Target_Folder_Index,
                                                         Coder_Index),
                                    LZMA_Props     =>
                                      Zlib.Seven_Zip_Folder_Decoding
                                        .LZMA_Props
                                          (Folder_LZMA_Props
                                             (Target_Folder_Index,
                                              Coder_Index)),
                                    Expected_Size  => Natural
                                      (Folder_Unpack_Sizes
                                         (Target_Folder_Index, Coder_Index)),
                                    Delta_Distance => Folder_Delta_Distances
                                                        (Target_Folder_Index,
                                                         Coder_Index),
                                    PPMd_Order     => Folder_PPMd_Orders
                                                        (Target_Folder_Index,
                                                         Coder_Index),
                                    PPMd_Memory    => Folder_PPMd_Memories
                                                        (Target_Folder_Index,
                                                         Coder_Index),
                                    AES_Cycles     => Folder_AES_Cycles
                                                        (Target_Folder_Index,
                                                         Coder_Index),
                                    AES_Salt_Len   => Folder_AES_Salt_Len
                                                        (Target_Folder_Index,
                                                         Coder_Index),
                                    AES_IV_Len     => Folder_AES_IV_Len
                                                        (Target_Folder_Index,
                                                         Coder_Index),
                                    AES_Salt       =>
                                      Zlib.Seven_Zip_Folder_Decoding.AES_Block
                                        (Folder_AES_Salt
                                           (Target_Folder_Index, Coder_Index)),
                                    AES_IV         =>
                                      Zlib.Seven_Zip_Folder_Decoding.AES_Block
                                        (Folder_AES_IV
                                           (Target_Folder_Index, Coder_Index)));
                                 Links (Coder_Index) :=
                                   Folder_Next_Coder
                                     (Target_Folder_Index, Coder_Index);
                              end loop;

                              declare
                                 Plain : constant Byte_Array :=
                                   Zlib.Seven_Zip_Folder_Decoding
                                     .Decode_Coder_Chain
                                       (Payload_Plain, Password, Coders,
                                        First_Coder, Links,
                                        Decode_Core_Coder'Access,
                                        Chain_Status);
                              begin
                                 if Chain_Status /= Ok then
                                    Status := Chain_Status;
                                    return Empty;
                                 end if;

                                 return Validate_And_Slice (Plain);
                              end;
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
                                       if Compute_CRC32 (Pack_Data) /=
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
                                    if Password'Length = 0
                                      or else Payload'Length mod 16 /= 0
                                    then
                                       Status := Unsupported_Method;
                                       return Empty;
                                    end if;
                                    declare
                                       Decrypted : constant Byte_Array :=
                                         Zlib.Seven_Zip_AES.Decrypt_CBC
                                           (Zlib.Seven_Zip_AES.Derive_Key
                                              (Password, Salt,
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
                                      Zlib.Seven_Zip_Filters
                                        .Delta_Decode_Checked
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

                              when Seven_Zip_BCJ_X86_Method =>
                                 if Folder_Reverse_Chain
                                   (Target_Folder_Index)
                                 then
                                    declare
                                       BCJ_Status : Status_Code := Ok;
                                       Plain      : constant Byte_Array :=
                                         Zlib.Seven_Zip_Filters
                                           .X86_BCJ_Decode
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
                                         Zlib.PPMd7.Decompress
                                           (Payload, Expected_Size,
                                            Folder_PPMd_Orders
                                              (Target_Folder_Index, 2),
                                            Folder_PPMd_Memories
                                              (Target_Folder_Index, 2),
                                            Local_Status);
                                    begin
                                       if Local_Status = Ok
                                         and then Plain'Length = Expected_Size
                                       then
                                          if not Unpack_CRC_Defined
                                              (Target_Folder_Index)
                                            or else Compute_CRC32 (Plain) =
                                              Unpack_CRCs (Target_Folder_Index)
                                          then
                                             return Finish_Decoded_Payload
                                               (Plain, 1, 1);
                                          end if;
                                          Local_Status := Invalid_Checksum;
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
                                    PPMd_Final_Status : Status_Code := Ok;

                                    function Finish_PPMd_Plain
                                      (Plain         : Byte_Array;
                                       Finish_Status : out Status_Code)
                                       return Byte_Array
                                    is
                                       Result : constant Byte_Array :=
                                         Finish_Decoded_Payload (Plain);
                                    begin
                                       Finish_Status := Status;
                                       return Result;
                                    end Finish_PPMd_Plain;
                                 begin
                                    declare
                                       Result : constant Byte_Array :=
                                         Zlib.Seven_Zip_Folder_Decoding
                                           .Decode_PPMd_With_Fallback
                                             (Payload,
                                              PPMd_Output_Size,
                                              Natural
                                                (Unpack_Sizes
                                                   (Target_Folder_Index)),
                                              PPMd_Orders (Target_Folder_Index),
                                              PPMd_Memories
                                                (Target_Folder_Index),
                                              Folder_Next_Coder
                                                (Target_Folder_Index,
                                                 Folder_Packed_Coder
                                                   (Target_Folder_Index)) /= 0,
                                              Unpack_CRC_Defined
                                                (Target_Folder_Index),
                                              Unpack_CRCs (Target_Folder_Index),
                                              Substream_CRC_Defined
                                                (Target_Index),
                                              Substream_CRCs (Target_Index),
                                              Substream_Sizes (Target_Index),
                                              Finish_PPMd_Plain'Access,
                                              PPMd_Final_Status);
                                    begin
                                       if PPMd_Final_Status /= Ok then
                                          Status := PPMd_Final_Status;
                                       end if;

                                       return Result;
                                    end;
                                 end;

                              when Seven_Zip_BCJ2_Method =>
                                 declare
                                    BCJ2_Status : Status_Code := Ok;
                                    Coder_Count : constant Natural :=
                                      Folder_Coder_Count (Target_Folder_Index);
                                    Coders :
                                      Zlib.Seven_Zip_Folder_Decoding
                                        .Folder_Coder_Array (1 .. Coder_Count);

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

                                    function Decode_Core_Coder
                                      (Input         : Byte_Array;
                                       Method        : Seven_Zip_Coder_Method;
                                       Props_In      : Byte_Array;
                                       Expected_Size : Natural;
                                       Decode_Status : out Status_Code)
                                       return Byte_Array
                                    is
                                       Props : Seven_Zip_LZMA_Props :=
                                         [others => 0];
                                    begin
                                       case Method is
                                          when Seven_Zip_Deflate_Method =>
                                             return Inflate_Raw_Exact
                                               (Input, Decode_Status);

                                          when Seven_Zip_BZip2_Method =>
                                             return BZip2_Decompress
                                               (Input, Expected_Size,
                                                Decode_Status);

                                          when Seven_Zip_LZMA_Method =>
                                             if Props_In'Length /=
                                               Props'Length
                                             then
                                                Decode_Status :=
                                                  Unsupported_Method;
                                                return Empty;
                                             end if;

                                             for Offset in
                                               0 .. Props'Length - 1
                                             loop
                                                Props (Props'First + Offset) :=
                                                  Props_In
                                                    (Props_In'First + Offset);
                                             end loop;

                                             return LZMA_Decode_Raw
                                               (Input, Props, Expected_Size,
                                                Decode_Status);

                                          when Seven_Zip_LZMA2_Method =>
                                             return LZMA2_Decode
                                               (Input, Expected_Size,
                                                Decode_Status);

                                          when others =>
                                             Status := Unsupported_Method;
                                             Decode_Status := Unsupported_Method;
                                             return Empty;
                                       end case;
                                    end Decode_Core_Coder;
                                 begin
                                    if Folder_Pack_Count
                                      (Target_Folder_Index) /= 4
                                    then
                                       Status := Unsupported_Method;
                                       return Empty;
                                    end if;

                                    for Coder_Index in 1 .. Coder_Count loop
                                       Coders (Coder_Index) :=
                                         (Method         => Folder_Methods
                                            (Target_Folder_Index, Coder_Index),
                                          LZMA_Props     =>
                                            Zlib.Seven_Zip_Folder_Decoding
                                              .LZMA_Props
                                                (Folder_LZMA_Props
                                                   (Target_Folder_Index,
                                                    Coder_Index)),
                                          Expected_Size  => Natural
                                            (Folder_Unpack_Sizes
                                               (Target_Folder_Index,
                                                Coder_Index)),
                                          Delta_Distance =>
                                            Folder_Delta_Distances
                                              (Target_Folder_Index,
                                               Coder_Index),
                                          PPMd_Order     => Folder_PPMd_Orders
                                            (Target_Folder_Index,
                                             Coder_Index),
                                          PPMd_Memory    => Folder_PPMd_Memories
                                            (Target_Folder_Index,
                                             Coder_Index),
                                          AES_Cycles     => 0,
                                          AES_Salt_Len   => 0,
                                          AES_IV_Len     => 0,
                                          AES_Salt       => [others => 0],
                                          AES_IV         => [others => 0]);
                                    end loop;

                                    declare
                                       Plain : constant Byte_Array :=
                                         Zlib.Seven_Zip_Folder_Decoding
                                           .Decode_BCJ2_Graph
                                             (Pack_Data (0), Pack_Data (1),
                                              Pack_Data (2), Pack_Data (3),
                                              Coders,
                                              Natural
                                                (Unpack_Sizes
                                                   (Target_Folder_Index)),
                                              Decode_Core_Coder'Access,
                                              BCJ2_Status);
                                    begin
                                       if BCJ2_Status /= Ok then
                                          if Coder_Count = 5 then
                                             Status := Unsupported_Method;
                                          else
                                             Status := BCJ2_Status;
                                          end if;
                                          return Empty;
                                       end if;

                                       return Validate_And_Slice (Plain);
                                    end;
                                 end;

                                          when others =>
                                             if Is_Branch_Converter
                                               (Methods (Target_Folder_Index))
                                             then
                                                return Finish_Decoded_Payload
                                                  (Zlib.Seven_Zip_Filters
                                                     .Branch_Convert
                                                       (Branch_Arch_Of
                                                          (Methods
                                                             (Target_Folder_Index)),
                                                        Payload,
                                                        Encoding => False));
                                             end if;

                                             Status := Unsupported_Method;
                                             return Empty;
                           end case;
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
        (Archive_Image, Entry_Name, "", Status, Kind, Metadata);
   end Extract_Seven_Zip_Stored;

   function Extract_Seven_Zip
     (Archive_Image : Byte_Array;
      Entry_Name    : String;
      Status        : out Status_Code) return Byte_Array is
      Kind : Seven_Zip_Entry_Kind := Seven_Zip_File_Entry;
      Metadata : Seven_Zip_Entry_Metadata;
   begin
      return Extract_Seven_Zip_Entry
        (Archive_Image, Entry_Name, "", Status, Kind, Metadata);
   end Extract_Seven_Zip;

   function Extract_Seven_Zip
     (Archive_Image : Byte_Array;
      Entry_Name    : String;
      Password      : String;
      Status        : out Status_Code) return Byte_Array is
   begin
      declare
         Kind     : Seven_Zip_Entry_Kind := Seven_Zip_File_Entry;
         Metadata : Seven_Zip_Entry_Metadata;
      begin
         return Extract_Seven_Zip_Entry
           (Archive_Image, Entry_Name, Password, Status, Kind, Metadata);
      end;
   end Extract_Seven_Zip;

   --  Multi-volume (split) .7z: the archive byte-stream cut into fixed-size
   --  volumes name.001, name.002, ...; concatenating them reproduces the .7z.

   function Read_Seven_Zip_Volumes
     (First_Volume_Path : String;
      Status            : out Status_Code) return Byte_Array
   is
   begin
      return
        Zlib.Seven_Zip_Volumes.Read
          (First_Volume_Path, Read_File'Access, Status);
   end Read_Seven_Zip_Volumes;

   procedure Write_Seven_Zip_Volumes
     (Archive     : Byte_Array;
      Base_Path   : String;
      Volume_Size : Positive;
      Status      : out Status_Code)
   is
   begin
      Zlib.Seven_Zip_Volumes.Write
        (Archive, Base_Path, Volume_Size, Write_File'Access, Status);
   end Write_Seven_Zip_Volumes;

   function Extract_Seven_Zip_Volumes
     (First_Volume_Path : String;
      Entry_Name        : String;
      Password          : String;
      Status            : out Status_Code) return Byte_Array
   is
   begin
      return
        Zlib.Seven_Zip_Volumes.Extract
          (First_Volume_Path, Entry_Name, Password, Read_File'Access,
           Extract_Seven_Zip'Access, Extract_Seven_Zip'Access, Status);
   end Extract_Seven_Zip_Volumes;

   function Encrypt_Seven_Zip_Header
     (Archive  : Byte_Array;
      Password : String;
      Status   : out Status_Code) return Byte_Array
   is
      function Encode_Header
        (Input      : Byte_Array;
         LZMA_Props : in out Byte) return Byte_Array is
      begin
         return LZMA_Encode_Selected (Input, LZMA_Props);
      end Encode_Header;
   begin
      return
        Zlib.Seven_Zip_Header_Encryption.Encrypt_Header
          (Archive, Password, Encode_Header'Access, Status);
   end Encrypt_Seven_Zip_Header;

   --  Catalogue every member of a 7z archive through the internal native
   --  listing package. Root-only LZMA encoded-header decoding remains a
   --  callback because it depends on root-body codec entry points.
   function List_Seven_Zip_Entries_With_Password
     (Archive_Image : Byte_Array;
      Password      : String;
      Status        : out Status_Code) return Archive_Entry_Array
   is
      function Decode_LZMA_Listing_Header
        (Input         : Byte_Array;
         LZMA_Props    : Byte_Array;
         Expected_Size : Natural;
         Decode_Status : out Status_Code) return Byte_Array
      is
         Empty : constant Byte_Array (1 .. 0) := [others => 0];
         Props : Seven_Zip_LZMA_Props := [others => 0];
      begin
         if LZMA_Props'Length /= Props'Length then
            Decode_Status := Unsupported_Method;
            return Empty;
         end if;

         for Offset in 0 .. Props'Length - 1 loop
            Props (Props'First + Offset) :=
              LZMA_Props (LZMA_Props'First + Offset);
         end loop;

         return
           LZMA_Decode_Raw_Encoded_Header
             (Input, Props, Expected_Size, Decode_Status);
      end Decode_LZMA_Listing_Header;
   begin
      return
        Zlib.Seven_Zip_Listing.List
          (Archive_Image, Password, Decode_LZMA_Listing_Header'Access, Status);
   end List_Seven_Zip_Entries_With_Password;

   function List_Seven_Zip_Entries
     (Archive_Image : Byte_Array;
      Status        : out Status_Code) return Archive_Entry_Array
   is
   begin
      return List_Seven_Zip_Entries_With_Password (Archive_Image, "", Status);
   end List_Seven_Zip_Entries;

   procedure Extract_Archive_To_Directory
     (Archive_Image   : Byte_Array;
      Destination_Dir : String;
      Password        : String;
      Status          : out Status_Code)
   is
      Is_7z : constant Boolean :=
        Zlib.Seven_Zip_Container.Has_Archive_Signature (Archive_Image);

      function List_Seven_Zip_With_Password
        (Image       : Byte_Array;
         Password_In : String;
         Status      : out Status_Code) return Archive_Entry_Array
      is
         No : constant Archive_Entry_Array (1 .. 0) :=
           [others => (others => <>)];
      begin
         return List_Seven_Zip_Entries_With_Password (Image, Password_In, Status);
      exception
         when others =>
            Status := Unsupported_Method;
            return No;
      end List_Seven_Zip_With_Password;

      function Extract_Seven_Zip_With_Password
        (Image       : Byte_Array;
         Entry_Name  : String;
         Password_In : String;
         Status      : out Status_Code) return Byte_Array
      is
      begin
         return Extract_Seven_Zip (Image, Entry_Name, Password_In, Status);
      end Extract_Seven_Zip_With_Password;
   begin
      Zlib.Archive_Directory_Extraction.Extract_To_Directory
        (Archive_Image       => Archive_Image,
         Destination_Dir     => Destination_Dir,
         Password            => Password,
         Is_Seven_Zip        => Is_7z,
         List_Seven_Zip      => List_Seven_Zip_With_Password'Access,
         List_ZIP            => List_ZIP_Entries'Access,
         Extract_Seven_Zip   => Extract_Seven_Zip_With_Password'Access,
         Extract_ZIP         => Extract_ZIP'Access,
         Safe_Entry_Name     => Safe_ZIP_Entry_Name'Access,
         Write_File          => Write_File'Access,
         Status              => Status);
   exception
      when others =>
         Status := Unsupported_Method;
   end Extract_Archive_To_Directory;

   procedure Extract_Archive_File_To_Directory
     (Archive_Path    : String;
      Destination_Dir : String;
      Password        : String;
      Status          : out Status_Code)
   is
   begin
      Zlib.Archive_Directory_Extraction.Extract_File_To_Directory
        (Archive_Path, Destination_Dir, Password, Read_File'Access,
         Extract_Archive_To_Directory'Access, Status);
   end Extract_Archive_File_To_Directory;

   function List_Archive_Entries
     (Archive_Image : Byte_Array;
      Password      : String;
      Status        : out Status_Code) return Archive_Entry_Array
   is
      Is_7z : constant Boolean :=
        Zlib.Seven_Zip_Container.Has_Archive_Signature (Archive_Image);

      function List_Seven_Zip_With_Password
        (Image       : Byte_Array;
         Password_In : String;
         Status      : out Status_Code) return Archive_Entry_Array
      is
         No : constant Archive_Entry_Array (1 .. 0) :=
           [others => (others => <>)];
      begin
         return List_Seven_Zip_Entries_With_Password (Image, Password_In, Status);
      exception
         when others =>
            Status := Unsupported_Method;
            return No;
      end List_Seven_Zip_With_Password;
   begin
      return
        Zlib.Archive_Listing.List_Entries
          (Archive_Image, Password, Is_7z, List_Seven_Zip_With_Password'Access,
           List_ZIP_Entries'Access, Status);
   end List_Archive_Entries;

   function Extract_Seven_Zip_File_Callback
     (Archive      : Byte_Array;
      Entry_Name   : String;
      Status       : out Status_Code;
      Is_Directory : out Boolean;
      Metadata     : out Seven_Zip_Entry_Metadata) return Byte_Array;

   function Extract_Seven_Zip_Metadata
     (Archive_Image : Byte_Array;
      Entry_Name    : String;
      Status        : out Status_Code) return Seven_Zip_Entry_Metadata
   is
   begin
      return
        Zlib.Seven_Zip_File_Extraction.Extract_Metadata
          (Archive_Image, Entry_Name, Extract_Seven_Zip_File_Callback'Access,
           Status);
   end Extract_Seven_Zip_Metadata;

   function Extract_Seven_Zip_File_Callback
     (Archive      : Byte_Array;
      Entry_Name   : String;
      Status       : out Status_Code;
      Is_Directory : out Boolean;
      Metadata     : out Seven_Zip_Entry_Metadata) return Byte_Array
   is
      Entry_Kind : Seven_Zip_Entry_Kind := Seven_Zip_File_Entry;
      Payload    : constant Byte_Array :=
        Extract_Seven_Zip_Entry (Archive, Entry_Name, "", Status, Entry_Kind, Metadata);
   begin
      Is_Directory := Entry_Kind = Seven_Zip_Directory_Entry;
      return Payload;
   end Extract_Seven_Zip_File_Callback;

   procedure Extract_Seven_Zip_Stored_File
     (Input_Path  : String;
      Output_Path : String;
      Entry_Name  : String;
      Status      : out Status_Code) is
   begin
      Zlib.Seven_Zip_File_Extraction.Extract_File
        (Input_Path, Output_Path, Entry_Name, Read_File'Access,
         Write_File'Access, Extract_Seven_Zip_File_Callback'Access, Status);
   end Extract_Seven_Zip_Stored_File;

   procedure Extract_Seven_Zip_File
     (Input_Path  : String;
      Output_Path : String;
      Entry_Name  : String;
      Status      : out Status_Code) is
   begin
      Zlib.Seven_Zip_File_Extraction.Extract_File
        (Input_Path, Output_Path, Entry_Name, Read_File'Access,
         Write_File'Access, Extract_Seven_Zip_File_Callback'Access, Status);
   end Extract_Seven_Zip_File;

   procedure Extract_Seven_Zip_Files_Impl
     (Input_Path   : String;
      Output_Dir   : String;
      Entry_Names  : Text_Array;
      Status       : out Status_Code)
   is
   begin
      Zlib.Seven_Zip_File_Extraction.Extract_Files
        (Input_Path, Output_Dir, Entry_Names, Read_File'Access,
         Write_File'Access, Extract_Seven_Zip_File_Callback'Access, Status);
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
     (Value : Interfaces.Unsigned_32; Shift : Natural) return Byte
     with
       SPARK_Mode => On,
       Pre        => Shift <= 31
   is
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
      Adler  : constant Interfaces.Unsigned_32 := Compute_Adler32 (Input);

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

   function Deflate_Bound (Input_Length : Natural) return Natural
     with SPARK_Mode => On
   is
   begin
      return Saturating_Compression_Bound (Input_Length, Wrapper_Size => 6);
   end Deflate_Bound;

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
           Dictionary_ID  => Compute_Adler32 (Dictionary));
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

   function Deflate_Raw_Bound (Input_Length : Natural) return Natural
     with SPARK_Mode => On
   is
   begin
      return Saturating_Compression_Bound (Input_Length, Wrapper_Size => 0);
   end Deflate_Raw_Bound;

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

   function GZip_Bound (Input_Length : Natural) return Natural
     with SPARK_Mode => On
   is
   begin
      return Saturating_Compression_Bound (Input_Length, Wrapper_Size => 18);
   end GZip_Bound;

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

   function Text_Bytes (Text : String) return Byte_Array
     with SPARK_Mode => On
   is
   begin
      if Text'Length = 0 then
         declare
            Empty : constant Byte_Array (1 .. 0) := [others => 0];
         begin
            return Empty;
         end;
      end if;

      declare
         Result : Byte_Array (Text'Range);
      begin
         for I in Text'Range loop
            Result (I) :=
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
