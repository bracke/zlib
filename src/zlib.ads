with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;
with Interfaces;
with System;

package Zlib is
   --  Support level: stable production API.
   --  Standalone public API for explicit zlib, gzip, and raw Deflate handling.
   --
   --  All byte-oriented APIs are binary-safe: data is represented as bytes
   --  and no text encoding, NUL termination, or character conversion is
   --  applied by the library. One-shot operations report failures through
   --  Status_Code. Streaming operations report malformed data through
   --  Zlib_Error and lifecycle misuse through Status_Error.
   --
   --  This root package owns all shared public types. Child packages are
   --  implementation details and the root spec must not depend on them.

   type Byte is mod 2 ** 8;
   --  One octet of binary compressed data or inflated payload data.

   type Byte_Array is array (Natural range <>) of Byte;
   --  Contiguous binary byte buffer used by one-shot APIs and fixtures.
   --  The caller owns the input buffer. Returned arrays are new values owned
   --  by the caller.

   type Text_Array is
     array (Positive range <>) of Ada.Strings.Unbounded.Unbounded_String;
   --  Parallel list of text values used by file-list container helpers.
   --  Convert ordinary strings with Ada.Strings.Unbounded.To_Unbounded_String.

   type Status_Code is
     (Ok,
      --  Operation completed successfully.
      Invalid_Header,
      --  Wrapper or gzip header is malformed or inconsistent.
      Unsupported_Method,
      --  Compression method or public mode is unsupported for this operation.
      Unsupported_Preset_Dictionary,
      --  Input requires a preset dictionary that was not supplied.
      Invalid_Checksum,
      --  Adler-32, CRC32, ISIZE, or header CRC validation failed.
      Invalid_Block_Type,
      --  Deflate block type is invalid or unsupported by the decoder.
      Invalid_Stored_Block,
      --  Stored Deflate block length and one's-complement length disagree.
      Invalid_Huffman_Code,
      --  Huffman metadata or decoded symbol stream is invalid.
      Invalid_Distance,
      --  Length/distance copy refers outside the available Deflate history.
      Unexpected_End_Of_Input,
      --  Input ended before the selected stream or wrapper was complete.
      Input_File_Error,
      --  Input file could not be opened, read, or represented as bytes.
      Output_File_Error);
      --  Output file could not be created or written.
   --  Deterministic result code returned by public operations.

   type Compression_Mode is
     (Stored,
      --  Emit stored Deflate blocks without LZ77/Huffman compression.
      Fixed,
      --  Emit fixed-Huffman Deflate blocks with bounded matching.
      Dynamic,
      --  Emit dynamic-Huffman Deflate blocks with bounded matching.
      Auto);
      --  Choose the smallest valid Stored, Fixed, or Dynamic block output.
   --  Public compression policy selector. Stored, Fixed, and Dynamic select
   --  the matching Deflate block policy. Auto is block-local for wrapped,
   --  gzip, and raw output: each pending block chooses the smallest valid
   --  Stored, Fixed, or Dynamic candidate by deterministic size scoring.
   --  Equal scored blocks use the tie-breaker Stored, then Fixed, then Dynamic.

   type Compression_Level is range 0 .. 9;
   --  Public broad compression-effort selector. Level 0 maps to Stored,
   --  level 1 maps to Fixed, levels 2 .. 3 map to greedy Auto, levels
   --  4 .. 7 map to lazy Auto, and levels 8 .. 9 map to bounded-optimal
   --  Auto with progressively higher bounded hash-chain effort.
   --  Levels are a convenience policy and do not replace Compression_Mode.

   Default_Level : constant Compression_Level := 6;
   --  Default broad compression-effort level used by consumers that want a
   --  stable conventional default instead of exact block-strategy control.

   type Header_Type is
     (Default,
      --  Alias for Zlib_Header; not a wrapper-probing mode.
      Zlib_Header,
      --  zlib wrapper with Deflate payload and Adler-32 trailer.
      GZip,
      --  gzip member syntax with CRC32 and ISIZE trailer validation.
      Raw_Deflate);
      --  Bare Deflate payload with no wrapper or trailer checksum.
   --  Wrapper/header mode selected for explicit inflate operations. Default is
   --  exactly Zlib_Header. Zlib_Header expects a zlib wrapper, Deflate payload, and
   --  Adler-32 trailer. GZip expects gzip member syntax and validates CRC32/ISIZE.
   --  Raw_Deflate expects only a Deflate payload and performs no wrapper,
   --  trailer, or checksum validation.

   type GZip_Member_Mode is
     (Single_Member,
      --  Accept exactly one gzip member and reject trailing gzip members.
      Multi_Member);
      --  Accept concatenated gzip members and concatenate decoded payloads.
   --  Gzip member handling policy. Single_Member is the strict default and
   --  accepts exactly one gzip member. Multi_Member explicitly enables
   --  concatenated gzip members and concatenates their decoded payloads.

   function Status_Image (Status : Status_Code) return String
     with SPARK_Mode => On;
   --  Return release-contract human-readable text for Status.
   --  @param Status status code to format
   --  @return release-contract status text

   function Adler32 (Input : Byte_Array) return Interfaces.Unsigned_32;
   --  Compute standard zlib Adler-32 over Input. This is the checksum
   --  used by zlib stream trailers and preset-dictionary DICTID values.
   --  The function is binary-safe and treats Input as bytes, not text.
   --  @param Input bytes to checksum
   --  @return standard Adler-32 value

   function CRC32 (Input : Byte_Array) return Interfaces.Unsigned_32;
   --  Compute standard gzip CRC-32 over Input using polynomial
   --  0xEDB88320. This is the checksum used by gzip trailers and FHCRC
   --  calculation. The function is binary-safe and treats Input as bytes,
   --  not text.
   --  @param Input bytes to checksum
   --  @return standard finalized CRC-32 value

   type CRC32_State is private;
   --  Incremental standard gzip CRC-32 state.

   procedure CRC32_Reset (State : out CRC32_State);
   --  Reset State to the initial CRC-32 value.
   --   State state to reset

   procedure CRC32_Update
     (State : in out CRC32_State;
      B     : Ada.Streams.Stream_Element);
   --  Incorporate one byte into State.
   --   State running CRC-32 state
   --   B byte to incorporate

   procedure CRC32_Update
     (State : in out CRC32_State;
      Data  : Ada.Streams.Stream_Element_Array);
   --  Incorporate Data into State in order.
   --   State running CRC-32 state
   --   Data bytes to incorporate

   function CRC32_Value (State : CRC32_State) return Interfaces.Unsigned_32;
   --  Return the finalized CRC-32 value for State.
   --   State running CRC-32 state
   --   standard finalized CRC-32 value

   function Looks_Like_Zlib_Header (Input : Byte_Array) return Boolean
     with SPARK_Mode => On;
   --  Return True when Input starts with a syntactically valid zlib CMF/FLG
   --  header for the Deflate compression method. This is a lightweight header
   --  discriminator for callers that need to distinguish zlib-wrapped Deflate
   --  from raw Deflate before attempting full decode; it does not validate the
   --  compressed payload or trailer checksum.
   --  @param Input bytes whose first two octets may be a zlib header
   --  @return True when the first two bytes satisfy zlib CMF/FLG checks

   function Looks_Like_GZip_Header (Input : Byte_Array) return Boolean
     with SPARK_Mode => On;
   --  Return True when Input starts with a syntactically valid minimal gzip
   --  member header prefix for the Deflate compression method. This lightweight
   --  discriminator checks ID1, ID2, CM, and reserved FLG bits only; it does not
   --  validate optional header fields, payload bytes, CRC32, ISIZE, or member
   --  completeness.
   --  @param Input bytes whose first four octets may be a gzip member header
   --  @return True when the gzip magic, method, and reserved flags are valid

   function Inflate
     (Input : Byte_Array; Status : out Status_Code) return Byte_Array;
   --  Decode one complete zlib-wrapped Deflate stream. This is exactly
   --  equivalent to Inflate_With_Header with Header => Zlib_Header. It does
   --  not auto-detect gzip or raw Deflate input.
   --  @param Input complete zlib stream: header, Deflate payload, Adler-32
   --  @param Status set to Ok on success or a deterministic failure code
   --  @return inflated bytes when Status is Ok; otherwise invalid partial data

   function Inflate_With_Header
     (Input : Byte_Array; Header : Header_Type; Status : out Status_Code)
      return Byte_Array;
   --  Decode one complete compressed stream using an explicit wrapper mode.
   --  Header selects zlib, gzip single-member, or raw Deflate decoding. This
   --  strict API does not perform wrapper auto-detection.
   --  @param Input complete compressed stream for the selected Header
   --  @param Header wrapper/header mode to decode
   --  @param Status set to Ok on success or a deterministic failure code
   --  @return inflated bytes when Status is Ok; otherwise invalid partial data

   function Inflate_Auto
     (Input : Byte_Array; Status : out Status_Code) return Byte_Array;
   --  Decode one complete compressed stream by lightweight wrapper
   --  discrimination. Syntactic zlib headers select Zlib_Header, syntactic
   --  gzip headers select GZip with Multi_Member policy, and all other input
   --  is attempted as Raw_Deflate. Call Inflate_With_Header for strict wrapper
   --  boundaries.
   --  @param Input complete compressed stream
   --  @param Status set to Ok on success or a deterministic failure code
   --  @return inflated bytes when Status is Ok; otherwise invalid partial data

   function Inflate_Raw
     (Input : Byte_Array; Status : out Status_Code) return Byte_Array;
   --  Decode one complete raw Deflate payload. This is exactly equivalent
   --  to Inflate_With_Header with Header => Raw_Deflate. It does not
   --  auto-detect zlib or gzip wrappers.
   --  @param Input complete raw Deflate payload with no wrapper or trailer
   --  @param Status set to Ok on success or a deterministic failure code
   --  @return inflated bytes when Status is Ok; otherwise invalid partial data

   function Inflate_With_Header
     (Input     : Byte_Array;
      Header    : Header_Type;
      GZip_Mode : GZip_Member_Mode;
      Status    : out Status_Code) return Byte_Array;
   --  Decode one complete compressed stream using an explicit wrapper mode
   --  and explicit gzip member policy. GZip_Mode is used only for Header => GZip.
   --  @param Input complete compressed stream for the selected Header
   --  @param Header wrapper/header mode to decode
   --  @param GZip_Mode gzip single-member or multi-member policy
   --  @param Status set to Ok on success or a deterministic failure code
   --  @return inflated bytes when Status is Ok; otherwise invalid partial data

   function Inflate_With_Dictionary
     (Input : Byte_Array; Dictionary : Byte_Array; Status : out Status_Code)
      return Byte_Array;
   --  Decode one complete zlib-wrapped Deflate stream that may use the
   --  zlib FDICT preset dictionary mechanism. Dictionary is explicit,
   --  zlib-only, and its Adler-32 DICTID must match the stream when FDICT
   --  is set.
   --  @param Input complete zlib stream to decode
   --  @param Dictionary preset dictionary bytes supplied by the caller
   --  @param Status set to Ok on success or a deterministic failure code
   --  @return inflated bytes when Status is Ok; otherwise invalid partial data

   procedure Inflate_File
     (Input_Path : String; Output_Path : String; Status : out Status_Code);
   --  Decode one complete zlib stream from a file into another file.
   --  @param Input_Path path to the zlib stream
   --  @param Output_Path path that receives inflated bytes
   --  @param Status set to Ok or a deterministic failure code

   procedure Inflate_Raw_File
     (Input_Path : String; Output_Path : String; Status : out Status_Code);
   --  Decode one complete raw Deflate payload from a file into another
   --  file. This is a convenience wrapper over Inflate_Raw and does not
   --  auto-detect zlib or gzip wrappers.
   --  @param Input_Path path to the raw Deflate payload
   --  @param Output_Path path that receives inflated bytes
   --  @param Status set to Ok or a deterministic failure code

   function Deflate_Stored
     (Input : Byte_Array; Status : out Status_Code) return Byte_Array;
   --  Encode bytes as a valid zlib stream using stored Deflate blocks.
   --  @param Input uncompressed bytes
   --  @param Status set to Ok or a deterministic failure code
   --  @return zlib stream containing stored Deflate blocks

   procedure Deflate_Stored_File
     (Input_Path : String; Output_Path : String; Status : out Status_Code);
   --  Encode a file as a stored-block zlib stream.
   --  @param Input_Path path to the uncompressed input file
   --  @param Output_Path path that receives the zlib stream
   --  @param Status set to Ok or a deterministic failure code

   function Deflate_Fixed
     (Input : Byte_Array; Status : out Status_Code) return Byte_Array;
   --  Encode bytes as a valid zlib stream using fixed-Huffman Deflate.
   --  The fixed-Huffman writer uses a conservative bounded LZ77 matcher and
   --  emits valid fixed-Huffman literals and length/distance pairs.
   --  @param Input uncompressed bytes
   --  @param Status set to Ok or a deterministic failure code
   --  @return zlib stream containing one fixed-Huffman Deflate block

   procedure Deflate_Fixed_File
     (Input_Path : String; Output_Path : String; Status : out Status_Code);
   --  Encode a file as a fixed-Huffman zlib stream.
   --  @param Input_Path path to the uncompressed input file
   --  @param Output_Path path that receives the zlib stream
   --  @param Status set to Ok or a deterministic failure code

   function Deflate_Dynamic
     (Input : Byte_Array; Status : out Status_Code) return Byte_Array;
   --  Encode bytes as a valid zlib stream using dynamic-Huffman Deflate.
   --  The dynamic-Huffman writer uses a conservative bounded LZ77 matcher;
   --  default level policy enables conservative lazy matching internally. It
   --  does not expose optimal parsing, gzip wrapping through this
   --  Deflate_Dynamic API, or ZIP output.
   --  @param Input uncompressed bytes
   --  @param Status set to Ok or a deterministic failure code
   --  @return zlib stream containing one dynamic-Huffman Deflate block

   procedure Deflate_Dynamic_File
     (Input_Path : String; Output_Path : String; Status : out Status_Code);
   --  Encode a file as a dynamic-Huffman zlib stream.
   --  @param Input_Path path to the uncompressed input file
   --  @param Output_Path path that receives the zlib stream
   --  @param Status set to Ok or a deterministic failure code

   function Deflate
     (Input  : Byte_Array;
      Mode   : Compression_Mode := Auto;
      Status : out Status_Code) return Byte_Array;
   --  Encode bytes as a valid zlib stream using a public compression policy.
   --  Stored, Fixed, and Dynamic are exact aliases for the corresponding
   --  explicit APIs. Auto compares successful outputs, chooses the smallest
   --  valid stream, and never returns corrupt or partial compressed output.
   --  Equal-size valid streams use the deterministic tie-breaker Stored,
   --  then Fixed, then Dynamic.
   --  @param Input uncompressed bytes
   --  @param Mode compression mode or Auto policy
   --  @param Status set to Ok or a deterministic failure code
   --  @return zlib stream when Status is Ok; otherwise empty array

   function Deflate
     (Input : Byte_Array; Level : Compression_Level; Status : out Status_Code)
      return Byte_Array;
   --  Encode bytes as a zlib stream using broad compression Level.
   --  Level 0 maps to Stored, level 1 maps to Fixed, levels 2 .. 3 map to
   --  greedy Auto, levels 4 .. 7 map to lazy Auto, and levels 8 .. 9 map to
   --  bounded-optimal Auto.
   --  @param Input uncompressed bytes
   --  @param Level broad compression-effort policy
   --  @param Status set to Ok or a deterministic failure code
   --  @return zlib stream when Status is Ok; otherwise empty array

   function Deflate_With_Dictionary
     (Input      : Byte_Array;
      Dictionary : Byte_Array;
      Mode       : Compression_Mode := Auto;
      Status     : out Status_Code) return Byte_Array;
   --  Encode bytes as a zlib-wrapped Deflate stream with FDICT set and a
   --  big-endian DICTID equal to Adler-32(Dictionary). Raw Deflate and gzip
   --  do not use this zlib wrapper mechanism.
   --  @param Input uncompressed bytes
   --  @param Dictionary preset dictionary bytes advertised by the zlib wrapper
   --  @param Mode compression mode or Auto policy
   --  @param Status set to Ok or a deterministic failure code
   --  @return zlib stream when Status is Ok; otherwise empty array
   procedure Deflate_File
     (Input_Path  : String;
      Output_Path : String;
      Level       : Compression_Level;
      Status      : out Status_Code);
   --  Encode a file as a zlib stream using broad compression Level.
   --  @param Input_Path path to the uncompressed input file
   --  @param Output_Path path that receives the zlib stream
   --  @param Level broad compression-effort policy
   --  @param Status set to Ok or a deterministic failure code
   procedure Deflate_File
     (Input_Path  : String;
      Output_Path : String;
      Mode        : Compression_Mode := Auto;
      Status      : out Status_Code);
   --  Encode a file as a zlib stream using Deflate with Mode.
   --  @param Input_Path path to the uncompressed input file
   --  @param Output_Path path that receives the zlib stream
   --  @param Mode compression mode or Auto policy
   --  @param Status set to Ok or a deterministic failure code

   type GZip_Metadata is private;
   --  Optional gzip header metadata. No_GZip_Metadata preserves the exact
   --  deterministic minimal gzip header used by existing GZip APIs.

   function No_GZip_Metadata return GZip_Metadata;
   --  Return the default empty gzip metadata value.
   --  @return metadata that emits the deterministic minimal gzip header
   procedure Set_Name (Metadata : in out GZip_Metadata; Name : String);
   --  Set gzip FNAME metadata. Name must not contain NUL.
   --  @param Metadata metadata object to update
   --  @param Name file-name metadata encoded in the gzip header
   procedure Set_Comment (Metadata : in out GZip_Metadata; Comment : String);
   --  Set gzip FCOMMENT metadata. Comment must not contain NUL.
   --  @param Metadata metadata object to update
   --  @param Comment comment metadata encoded in the gzip header
   procedure Set_MTime
     (Metadata : in out GZip_Metadata; MTime : Interfaces.Unsigned_32);
   --  Set gzip MTIME metadata.
   --  @param Metadata metadata object to update
   --  @param MTime Unix timestamp value to encode in the gzip header
   procedure Set_OS (Metadata : in out GZip_Metadata; OS : Byte);
   --  Set gzip OS metadata byte.
   --  @param Metadata metadata object to update
   --  @param OS gzip operating-system identifier byte
   procedure Set_XFL (Metadata : in out GZip_Metadata; XFL : Byte);
   --  Set gzip XFL metadata byte. The default deterministic value is 0.
   --  @param Metadata metadata object to update
   --  @param XFL gzip extra-flags byte
   procedure Set_Extra (Metadata : in out GZip_Metadata; Extra : Byte_Array);
   --  Set gzip FEXTRA metadata. Extra may contain arbitrary bytes, including
   --  NUL. Lengths above 65_535 mark Metadata invalid deterministically.
   --  @param Metadata metadata object to update
   --  @param Extra raw FEXTRA field bytes to encode in the gzip header
   procedure Set_Header_CRC
     (Metadata : in out GZip_Metadata; Enabled : Boolean);
   --  Enable or disable gzip FHCRC output.
   --  @param Metadata metadata object to update
   --  @param Enabled True to emit and validate a gzip header CRC field
   function GZip
     (Input  : Byte_Array;
      Mode   : Compression_Mode := Auto;
      Status : out Status_Code) return Byte_Array;
   --  Encode bytes as a deterministic minimal gzip stream using Mode.
   --  The gzip member has no optional metadata fields, MTIME is zero, OS is
   --  255, and the trailer contains CRC32 and ISIZE for Input. Stored, Fixed,
   --  Dynamic, and Auto use the same Deflate payload policy as Deflate.
   --  @param Input uncompressed bytes
   --  @param Mode compression mode or Auto policy
   --  @param Status set to Ok or a deterministic failure code
   --  @return gzip stream when Status is Ok; otherwise empty array

   function GZip
     (Input    : Byte_Array;
      Mode     : Compression_Mode;
      Metadata : GZip_Metadata;
      Status   : out Status_Code) return Byte_Array;
   --  Encode bytes as a gzip stream with optional header metadata.
   --  @param Input uncompressed bytes
   --  @param Mode compression mode or Auto policy
   --  @param Metadata optional gzip header fields to emit
   --  @param Status set to Ok or a deterministic failure code
   --  @return gzip stream when Status is Ok; otherwise empty array
   function GZip
     (Input : Byte_Array; Level : Compression_Level; Status : out Status_Code)
      return Byte_Array;
   --  Encode bytes as a deterministic minimal gzip stream using broad
   --  compression Level. Level mapping does not alter gzip wrapper semantics.
   --  @param Input uncompressed bytes
   --  @param Level broad compression-effort policy
   --  @param Status set to Ok or a deterministic failure code
   --  @return gzip stream when Status is Ok; otherwise empty array
   function GZip_Members
     (Inputs : Text_Array;
      Mode   : Compression_Mode := Auto;
      Status : out Status_Code) return Byte_Array;
   --  Encode each Text_Array element as an independent deterministic gzip
   --  member and concatenate the members. Text is encoded as byte values of
   --  each Character in order; use GZip_File_Members for file payloads.
   --  @param Inputs text payloads to encode as separate gzip members
   --  @param Mode compression mode or Auto policy for each member
   --  @param Status set to Ok or a deterministic failure code
   --  @return concatenated gzip members when Status is Ok; otherwise empty array
   function GZip
     (Input    : Byte_Array;
      Level    : Compression_Level;
      Metadata : GZip_Metadata;
      Status   : out Status_Code) return Byte_Array;
   --  Encode bytes as a gzip stream with optional metadata and broad
   --  compression Level.
   --  @param Input uncompressed bytes
   --  @param Level broad compression-effort policy
   --  @param Metadata optional gzip header fields to emit
   --  @param Status set to Ok or a deterministic failure code
   --  @return gzip stream when Status is Ok; otherwise empty array
   procedure GZip_File
     (Input_Path  : String;
      Output_Path : String;
      Level       : Compression_Level;
      Status      : out Status_Code);
   --  Encode a file as a deterministic minimal gzip stream using broad
   --  compression Level.
   --  @param Input_Path path to the uncompressed input file
   --  @param Output_Path path that receives the gzip stream
   --  @param Level broad compression-effort policy
   --  @param Status set to Ok or a deterministic failure code

   procedure GZip_File
     (Input_Path  : String;
      Output_Path : String;
      Level       : Compression_Level;
      Metadata    : GZip_Metadata;
      Status      : out Status_Code);
   --  Encode a file as a gzip stream using broad compression Level and
   --  optional header metadata.
   --  @param Input_Path path to the uncompressed input file
   --  @param Output_Path path that receives the gzip stream
   --  @param Level broad compression-effort policy
   --  @param Metadata optional gzip header fields to emit
   --  @param Status set to Ok or a deterministic failure code

   procedure GZip_File
     (Input_Path  : String;
      Output_Path : String;
      Mode        : Compression_Mode := Auto;
      Status      : out Status_Code);
   --  Encode a file as a deterministic minimal gzip stream using Mode.
   --  @param Input_Path path to the uncompressed input file
   --  @param Output_Path path that receives the gzip stream
   --  @param Mode compression mode or Auto policy
   --  @param Status set to Ok or a deterministic failure code

   procedure GZip_File
     (Input_Path  : String;
      Output_Path : String;
      Mode        : Compression_Mode;
      Metadata    : GZip_Metadata;
      Status      : out Status_Code);
   --  Encode a file as a gzip stream using Mode and optional header metadata.
   --  @param Input_Path path to the uncompressed input file
   --  @param Output_Path path that receives the gzip stream
   --  @param Mode compression mode or Auto policy
   --  @param Metadata optional gzip header fields to emit
   --  @param Status set to Ok or a deterministic failure code
   procedure GZip_File_Members
     (Input_Paths : Text_Array;
      Output_Path : String;
      Mode        : Compression_Mode := Auto;
      Status      : out Status_Code);
   --  Encode each input file as one gzip member and concatenate the members
   --  into Output_Path. Missing inputs fail before writing output.
   --  @param Input_Paths file paths to encode as separate gzip members
   --  @param Output_Path path that receives concatenated gzip members
   --  @param Mode compression mode or Auto policy for each member
   --  @param Status set to Ok or a deterministic failure code
   function Deflate_Raw
     (Input  : Byte_Array;
      Mode   : Compression_Mode := Auto;
      Status : out Status_Code) return Byte_Array;
   --  Encode bytes as raw Deflate output when Mode => Stored, Fixed,
   --  Dynamic, or Auto. The output contains Deflate blocks only: no zlib
   --  header, no Adler-32 footer, no gzip header, no CRC32 trailer, and no
   --  ISIZE trailer. Auto uses the same deterministic block-local
   --  Stored/Fixed/Dynamic size-scoring policy as wrapped compression.
   --  @param Input uncompressed bytes
   --  @param Mode Stored, Fixed, Dynamic, or Auto for raw output
   --  @param Status set to Ok on success
   --  @return raw Deflate stream when Status is Ok; otherwise empty array

   function Deflate_Raw
     (Input : Byte_Array; Level : Compression_Level; Status : out Status_Code)
      return Byte_Array;
   --  Encode bytes as raw Deflate using broad compression Level. Level 0
   --  emits stored-compatible raw Deflate, level 1 emits fixed-Huffman raw
   --  Deflate, levels 2 .. 3 use greedy raw Auto, levels 4 .. 7 use
   --  conservative lazy raw Auto, and levels 8 .. 9 use bounded-optimal raw
   --  Auto.
   --  @param Input uncompressed bytes
   --  @param Level broad compression-effort policy
   --  @param Status set to Ok or a deterministic failure code
   --  @return raw Deflate stream when Status is Ok; otherwise empty array
   procedure Deflate_Raw_File
     (Input_Path  : String;
      Output_Path : String;
      Level       : Compression_Level;
      Status      : out Status_Code);
   --  Encode a file as raw Deflate output using broad compression Level.
   --  @param Input_Path path to the uncompressed input file
   --  @param Output_Path path that receives raw Deflate output
   --  @param Level broad compression-effort policy
   --  @param Status set to Ok, file error, or Unsupported_Method

   procedure Deflate_Raw_File
     (Input_Path  : String;
      Output_Path : String;
      Mode        : Compression_Mode := Auto;
      Status      : out Status_Code);
   --  Encode a file as raw Deflate Stored, Fixed, Dynamic, or Auto output.
   --  Compression failures are reported through Status and do not write output.
   --  @param Input_Path path to the uncompressed input file
   --  @param Output_Path path that receives raw Deflate output
   --  @param Mode Stored, Fixed, Dynamic, or Auto for raw output
   --  @param Status set to Ok, file error, or Unsupported_Method

   procedure Inflate_File_Streaming
     (Input_Path  : String;
      Output_Path : String;
      Header      : Header_Type := Zlib_Header;
      Status      : out Status_Code);
   --  Decode a compressed file through the streaming inflate API using
   --  bounded internal buffers. Header selects zlib, gzip, or raw Deflate.
   --  Existing Inflate_File remains available as a whole-file convenience
   --  helper. Use Inflate_File_With_Dictionary_Streaming for zlib streams that
   --  require the preset-dictionary FDICT mechanism.
   --  @param Input_Path path to the compressed input file
   --  @param Output_Path path that receives inflated bytes
   --  @param Header wrapper/header mode to decode
   --  @param Status set to Ok or a deterministic failure code
   procedure Inflate_File_With_Dictionary_Streaming
     (Input_Path  : String;
      Output_Path : String;
      Dictionary  : Byte_Array;
      Status      : out Status_Code);
   --  Decode a zlib-wrapped compressed file through the streaming inflate API
   --  with an explicit preset dictionary. The helper is zlib-header-only;
   --  gzip and raw Deflate do not use the zlib FDICT wrapper mechanism.
   --  @param Input_Path path to the zlib stream requiring a preset dictionary
   --  @param Output_Path path that receives inflated bytes
   --  @param Dictionary preset dictionary bytes supplied by the caller
   --  @param Status set to Ok or a deterministic failure code
   procedure Inflate_Raw_File_Streaming
     (Input_Path : String; Output_Path : String; Status : out Status_Code);
   --  Decode a raw Deflate file through Inflate_File_Streaming with
   --  Header => Raw_Deflate, preserving bounded-memory behavior.
   --  @param Input_Path path to the raw Deflate input file
   --  @param Output_Path path that receives inflated bytes
   --  @param Status set to Ok or a deterministic failure code
   procedure Deflate_File_Streaming
     (Input_Path  : String;
      Output_Path : String;
      Header      : Header_Type := Zlib_Header;
      Mode        : Compression_Mode := Auto;
      Status      : out Status_Code);
   --  Encode a file through the streaming compression API using bounded
   --  internal buffers. Header selects zlib, gzip, or raw Deflate output.
   --  @param Input_Path path to the uncompressed input file
   --  @param Output_Path path that receives compressed output
   --  @param Header wrapper/header mode to emit
   --  @param Mode compression mode or Auto policy
   --  @param Status set to Ok or a deterministic failure code
   procedure Deflate_File_With_Dictionary_Streaming
     (Input_Path  : String;
      Output_Path : String;
      Dictionary  : Byte_Array;
      Mode        : Compression_Mode := Auto;
      Status      : out Status_Code);
   --  Encode a file as a zlib-wrapped Deflate stream with the FDICT preset
   --  dictionary mechanism through the streaming compression API.
   --  @param Input_Path path to the uncompressed input file
   --  @param Output_Path path that receives zlib-wrapped compressed output
   --  @param Dictionary preset dictionary bytes advertised by the zlib wrapper
   --  @param Mode compression mode or Auto policy
   --  @param Status set to Ok or a deterministic failure code
   procedure GZip_File_Streaming
     (Input_Path  : String;
      Output_Path : String;
      Mode        : Compression_Mode := Auto;
      Status      : out Status_Code);
   --  Encode a file as gzip through Deflate_File_Streaming.
   --  @param Input_Path path to the uncompressed input file
   --  @param Output_Path path that receives the gzip stream
   --  @param Mode compression mode or Auto policy
   --  @param Status set to Ok or a deterministic failure code
   procedure Deflate_Raw_File_Streaming
     (Input_Path  : String;
      Output_Path : String;
      Mode        : Compression_Mode := Auto;
      Status      : out Status_Code);
   --  Encode a file as raw Deflate through Deflate_File_Streaming.
   --  @param Input_Path path to the uncompressed input file
   --  @param Output_Path path that receives raw Deflate output
   --  @param Mode compression mode or Auto policy
   --  @param Status set to Ok or a deterministic failure code

   procedure Deflate_Raw_File_Size
     (Input_Path      : String;
      Mode            : Compression_Mode := Auto;
      Compressed_Size : out Interfaces.Unsigned_64;
      Status          : out Status_Code);
   --  Encode a file as raw Deflate and report the exact byte count without
   --  writing the compressed bytes. This is intended for container metadata
   --  planning when a format needs sizes before payload emission.
   --  @param Input_Path path to the uncompressed input file
   --  @param Mode Stored, Fixed, Dynamic, or Auto for raw output
   --  @param Compressed_Size exact raw Deflate byte count when Ok
   --  @param Status set to Ok, Input_File_Error, or deterministic compression failure

   function Stored_Raw_Deflate_Size
     (Uncompressed_Size : Interfaces.Unsigned_64;
      Compressed_Size   : out Interfaces.Unsigned_64) return Boolean;
   --  Predict the exact byte count emitted by
   --  Deflate_Raw_Stored_File_To_Stream for an input of Uncompressed_Size
   --  bytes. The result includes Deflate stored-block headers only; there is
   --  no zlib or gzip wrapper.
   --  @param Uncompressed_Size uncompressed input byte count
   --  @param Compressed_Size exact raw stored-Deflate byte count when True
   --  @return False if the size cannot be represented

   procedure Deflate_Raw_File_To_Stream
     (Input_Path      : String;
      Output          : in out Ada.Streams.Stream_IO.File_Type;
      Mode            : Compression_Mode := Auto;
      Compressed_Size : out Interfaces.Unsigned_64;
      Status          : out Status_Code);
   --  Encode a file as raw Deflate into an already-open stream. This helper
   --  is intended for container formats such as ZIP that own the surrounding
   --  file layout and need the exact emitted payload size.
   --  @param Input_Path path to the uncompressed input file
   --  @param Output open output stream that receives raw Deflate bytes
   --  @param Mode Stored, Fixed, Dynamic, or Auto for raw output
   --  @param Compressed_Size number of raw Deflate bytes written when Ok
   --  @param Status set to Ok, Input_File_Error, Output_File_Error, or a
   --  deterministic compression failure code

   procedure Deflate_Raw_Stored_File_To_Stream
     (Input_Path       : String;
      Output           : in out Ada.Streams.Stream_IO.File_Type;
      Compressed_Size  : out Interfaces.Unsigned_64;
      Status           : out Status_Code);
   --  Encode a file as raw stored Deflate into an already-open stream. This
   --  helper is intended for container formats such as ZIP that own the
   --  surrounding file layout and need the exact emitted payload size.
   --  @param Input_Path path to the uncompressed input file
   --  @param Output open output stream that receives raw Deflate bytes
   --  @param Compressed_Size number of raw Deflate bytes written when Ok
   --  @param Status set to Ok, Input_File_Error, Output_File_Error, or a
   --  deterministic compression failure code

   function ZIP
     (Input      : Byte_Array;
      Entry_Name : String;
      Mode       : Compression_Mode := Auto;
      Status     : out Status_Code) return Byte_Array;
   --  Encode bytes as a single-entry ZIP32 archive using method 0 Stored or
   --  method 8 Deflate. Entry_Name must be a safe relative ZIP path: non-empty,
   --  no NUL, no absolute path, no "." or ".." segment, no backslash, and no
   --  drive-style colon. The archive uses deterministic zero DOS timestamps.
   --  @param Input uncompressed entry bytes
   --  @param Entry_Name safe relative ZIP entry name
   --  @param Mode Stored, Fixed, Dynamic, or Auto compression policy
   --  @param Status set to Ok on success, otherwise a deterministic failure code
   --  @return complete ZIP archive when Status is Ok; otherwise an empty array

   procedure ZIP_File
     (Input_Path  : String;
      Output_Path : String;
      Entry_Name  : String;
      Mode        : Compression_Mode := Auto;
      Status      : out Status_Code);
   --  Encode one input file as a single-entry ZIP32 archive.
   --  @param Input_Path path to the uncompressed input file
   --  @param Output_Path path that receives the ZIP archive
   --  @param Entry_Name safe relative ZIP entry name
   --  @param Mode Stored, Fixed, Dynamic, or Auto compression policy
   --  @param Status set to Ok, file error, or deterministic compression failure

   procedure ZIP_Files
     (Input_Paths : Text_Array;
      Output_Path : String;
      Entry_Names : Text_Array;
      Mode        : Compression_Mode := Auto;
      Force_ZIP64 : Boolean := False;
      Status      : out Status_Code);
   --  Encode several files as one deterministic ZIP archive. Input_Paths and
   --  Entry_Names are parallel arrays and must have the same nonzero length.
   --  Entry names must be safe relative ZIP paths and distinct. The archive
   --  uses method 0 Stored or method 8 Deflate with deterministic zero DOS
   --  timestamps. When Force_ZIP64 is True, ZIP64 local/central extra fields
   --  plus ZIP64 end-of-central-directory records are emitted even for small
   --  test archives; otherwise ZIP32 records are emitted while values fit the
   --  public in-memory/file-size limits of this implementation.
   --  @param Input_Paths source files to archive
   --  @param Output_Path path that receives the ZIP archive
   --  @param Entry_Names safe relative ZIP entry names
   --  @param Mode Stored, Fixed, Dynamic, or Auto compression policy
   --  @param Force_ZIP64 force ZIP64 metadata emission
   --  @param Status set to Ok on success, otherwise a deterministic failure code

   type Filter_Type is limited private;
   --  Streaming inflate filter state. The lifecycle contract is:
   --  Closed before initialization, Open after Inflate_Init, Failed after a
   --  fatal decompression error, and Ended after wrapper-validated stream end.
   --  Failed and Ended filters remain open until Close is called.

   type Flush_Mode is
     (No_Flush,
      --  Make normal progress without forcing a stream boundary.
      Sync_Flush,
      --  For compression, emit a byte-aligned sync flush marker.
      Full_Flush,
      --  For compression, emit a byte-aligned full flush marker.
      Finish);
      --  Require or emit final stream completion and wrapper validation.
   --  Streaming flush request. No_Flush never treats missing additional input as an
   --  error. Sync_Flush and Full_Flush force pending compression output to a byte
   --  boundary without ending the stream; streaming inflate treats them like
   --  No_Flush. Finish requires the stream to complete through wrapper trailer
   --  validation and raises Zlib_Error for truncated input.

   Zlib_Error : exception;
   --  Streaming exception for malformed, truncated, unsupported, or
   --  checksum/size-invalid compressed data.

   Status_Error : exception;
   --  Streaming exception for public API lifecycle misuse, such as using a
   --  closed filter or closing an unopened filter without Ignore_Error.

   procedure Inflate_Init
     (Filter : in out Filter_Type; Header : Header_Type := Default);
   --  Reset and open Filter for a streaming inflate session. Header selects
   --  zlib, gzip single-member, or raw Deflate decoding.
   --  @param Filter inflate filter object to initialize
   --  @param Header wrapper/header mode to decode

   procedure Inflate_Init
     (Filter    : in out Filter_Type;
      Header    : Header_Type;
      GZip_Mode : GZip_Member_Mode);
   --  Reset and open Filter for a streaming inflate session with explicit
   --  gzip member policy. GZip_Mode is used only for Header => GZip.
   --  @param Filter inflate filter object to initialize
   --  @param Header wrapper/header mode to decode
   --  @param GZip_Mode gzip single-member or multi-member policy

   procedure Inflate_Set_Dictionary
     (Filter : in out Filter_Type; Dictionary : Byte_Array);
   --  Provide the preset dictionary required by a streaming zlib inflate
   --  session that reached Unsupported_Preset_Dictionary.
   --  @param Filter open streaming inflate filter awaiting a dictionary
   --  @param Dictionary preset dictionary bytes to validate and seed

   function Is_Open (Filter : Filter_Type) return Boolean;
   --  Return True after Inflate_Init and before Close, including Failed and
   --  Ended states that still require explicit Close.
   --  @param Filter filter object to inspect
   --  @return True when Filter is open

   procedure Translate
     (Filter   : in out Filter_Type;
      In_Data  : Ada.Streams.Stream_Element_Array;
      In_Last  : out Ada.Streams.Stream_Element_Offset;
      Out_Data : out Ada.Streams.Stream_Element_Array;
      Out_Last : out Ada.Streams.Stream_Element_Offset;
      Flush    : Flush_Mode := No_Flush);
   --  Feed input and receive inflated output. This procedure always
   --  initializes In_Last and Out_Last before any exception. It consumes as
   --  much input as useful, produces at most Out_Data'Length bytes, and may
   --  return with no progress when more input or more output space is needed.
   --  Zlib_Error denotes invalid/truncated compressed data or validation
   --  failure; Status_Error denotes lifecycle misuse.
   --  @param Filter open filter
   --  @param In_Data input bytes
   --  @param In_Last last consumed input index, or the no-consumption marker
   --  @param Out_Data output buffer
   --  @param Out_Last last produced output index, or the no-output marker
   --  @param Flush flush request

   procedure Flush
     (Filter   : in out Filter_Type;
      Out_Data : out Ada.Streams.Stream_Element_Array;
      Out_Last : out Ada.Streams.Stream_Element_Offset;
      Flush    : Flush_Mode := No_Flush);
   --  Drain pending decoded output without adding new input. No_Flush may
   --  return normally before stream end. Finish requires Stream_End to be
   --  reached after pending output is drained and raises Zlib_Error otherwise.
   --  @param Filter open filter
   --  @param Out_Data output buffer
   --  @param Out_Last last produced output index, or the no-output marker
   --  @param Flush flush request

   function Stream_End (Filter : Filter_Type) return Boolean;
   --  Return True after the Deflate final block, all pending output, and any
   --  active wrapper trailer are complete. For GZip with Multi_Member, this
   --  means the complete logical concatenated gzip stream is complete, not
   --  merely that one member trailer has been validated.
   --  @param Filter filter object to inspect
   --  @return True only for a completed and validated streaming inflate session

   procedure Close
     (Filter : in out Filter_Type; Ignore_Error : Boolean := False);
   --  Close a filter and release/reset owned state. Unopened/closed filters
   --  raise Status_Error unless Ignore_Error is True. Open incomplete or Failed
   --  filters raise Zlib_Error unless Ignore_Error is True. State is cleared
   --  even when Close reports Zlib_Error.
   --  @param Filter filter object to close
   --  @param Ignore_Error suppress close-time lifecycle/data completion
   --  errors when True; useful during exception cleanup

   type Compression_Filter_Type is limited private;
   --  Streaming compression filter state. Supports zlib-wrapped and
   --  gzip-wrapped stored-block, fixed-Huffman, and dynamic-Huffman Deflate
   --  output for Header => Default/Zlib_Header/GZip. Header => Raw_Deflate
   --  supports Mode => Stored/Fixed/Dynamic/Auto and emits Deflate blocks only.
   --  Mode => Auto is deterministic and uses block-local Stored/Fixed/Dynamic
   --  size scoring with the documented Stored, Fixed, Dynamic tie-breaker. Level-based
   --  initialization maps level 0 to Stored, level 1 to Fixed, levels 2 .. 3
   --  to greedy Auto, levels 4 .. 7 to lazy Auto, and levels 8 .. 9 to
   --  bounded-optimal Auto without changing wrapper semantics.

   procedure Deflate_Init
     (Filter : in out Compression_Filter_Type;
      Header : Header_Type := Zlib_Header;
      Mode   : Compression_Mode := Auto);
   --  Reset and open Filter for a streaming compression session using Mode.
   --  Header selects zlib, gzip, or raw Deflate output.
   --  @param Filter compression filter object to initialize
   --  @param Header wrapper/header mode to emit
   --  @param Mode compression mode or Auto policy

   procedure Deflate_Init
     (Filter : in out Compression_Filter_Type;
      Header : Header_Type := Zlib_Header;
      Level  : Compression_Level);
   --  Reset and open Filter for a streaming compression session using broad
   --  compression Level. Header selects zlib, gzip, or raw Deflate output.
   --  @param Filter compression filter object to initialize
   --  @param Header wrapper/header mode to emit
   --  @param Level broad compression-effort policy

   procedure Deflate_Init
     (Filter   : in out Compression_Filter_Type;
      Header   : Header_Type := Zlib_Header;
      Mode     : Compression_Mode := Auto;
      Metadata : GZip_Metadata);
   --  Reset and open Filter for a streaming compression session using Mode
   --  and optional gzip metadata. Metadata is used only for Header => GZip.
   --  @param Filter compression filter object to initialize
   --  @param Header wrapper/header mode to emit
   --  @param Mode compression mode or Auto policy
   --  @param Metadata optional gzip header fields for Header => GZip

   procedure Deflate_Set_Dictionary
     (Filter : in out Compression_Filter_Type; Dictionary : Byte_Array);
   --  Provide a preset dictionary for a streaming zlib compression session.
   --  The dictionary must be set before input data is compressed.
   --  @param Filter open compression filter before compressed data starts
   --  @param Dictionary preset dictionary bytes advertised by the zlib wrapper

   procedure Deflate_Init
     (Filter   : in out Compression_Filter_Type;
      Header   : Header_Type := Zlib_Header;
      Level    : Compression_Level;
      Metadata : GZip_Metadata);
   --  Reset and open Filter for a streaming compression session using a
   --  broad compression-effort Level and optional gzip metadata.
   --  @param Filter compression filter object to initialize
   --  @param Header wrapper/header mode to prepare for
   --  @param Level broad compression-effort policy to map onto a strategy
   --  @param Metadata optional gzip metadata for Header => GZip

   function Is_Open (Filter : Compression_Filter_Type) return Boolean;
   --  Return True after Deflate_Init and before Compress_Close, including a
   --  failed compression filter that still requires explicit close.
   --  @param Filter compression filter object to inspect
   --  @return True when Filter is open

   procedure Compress
     (Filter   : in out Compression_Filter_Type;
      In_Data  : Ada.Streams.Stream_Element_Array;
      In_Last  : out Ada.Streams.Stream_Element_Offset;
      Out_Data : out Ada.Streams.Stream_Element_Array;
      Out_Last : out Ada.Streams.Stream_Element_Offset;
      Flush    : Flush_Mode := No_Flush);
   --  Feed input and receive compressed output. Supported zlib modes emit a
   --  zlib header, Deflate blocks, and a big-endian Adler-32 footer. Supported
   --  gzip modes emit the deterministic minimal gzip header, raw Deflate
   --  blocks, and a little-endian CRC32/ISIZE trailer. Stored mode emits
   --  stored blocks; Fixed mode emits fixed-Huffman blocks with bounded matches;
   --  Dynamic mode emits bounded dynamic-Huffman blocks using the internal
   --  LZ77 matcher. Raw Stored, Raw Fixed, Raw Dynamic, and Raw Auto emit Deflate blocks only
   --  with no wrapper checksum. Auto
   --  finalizes each pending block by choosing the smallest valid Stored, Fixed,
   --  or Dynamic representation; it never changes zlib/gzip wrapper semantics and does
   --  not imply compression levels or whole-stream buffering. The compressor
   --  is resumable with small input and output buffers,
   --  including one-byte output buffers. After Compress_Stream_End is True,
   --  empty input is idempotent and non-empty input raises Status_Error.
   --  @param Filter open compression filter
   --  @param In_Data input bytes
   --  @param In_Last last consumed input index, or the no-consumption marker
   --  @param Out_Data output buffer
   --  @param Out_Last last produced output index, or the no-output marker
   --  @param Flush flush request

   procedure Compress_Flush
     (Filter   : in out Compression_Filter_Type;
      Out_Data : out Ada.Streams.Stream_Element_Array;
      Out_Last : out Ada.Streams.Stream_Element_Offset;
      Flush    : Flush_Mode := No_Flush);
   --  Drain pending compressed output without adding input. No_Flush does not
   --  force a partial block. Sync_Flush and Full_Flush emit a non-final Deflate
   --  flush marker and keep the stream open. Finish emits the final Deflate
   --  block and the active wrapper trailer: Adler-32 for zlib, CRC32/ISIZE for
   --  gzip, or no trailer for raw Deflate. After Compress_Stream_End is True,
   --  No_Flush/Finish are idempotent and Sync_Flush/Full_Flush raise
   --  Status_Error.
   --  @param Filter open compression filter
   --  @param Out_Data output buffer
   --  @param Out_Last last produced output index, or the no-output marker
   --  @param Flush flush request

   function Compress_Stream_End
     (Filter : Compression_Filter_Type) return Boolean;
   --  Return True only after the final Deflate block and any active wrapper
   --  trailer have been fully emitted and drained to caller output by a
   --  streaming compression session.
   --  @param Filter compression filter object to inspect
   --  @return True only for a completed streaming compression session

   procedure Compress_Close
     (Filter       : in out Compression_Filter_Type;
      Ignore_Error : Boolean := False);
   --  Close a compression filter. Unopened/closed filters raise Status_Error
   --  unless Ignore_Error is True. Open incomplete or failed filters raise
   --  Zlib_Error unless Ignore_Error is True. State is cleared even when
   --  Compress_Close reports Zlib_Error.
   --  @param Filter compression filter object to close
   --  @param Ignore_Error suppress close-time lifecycle/finalization errors
   --  when True; useful during exception cleanup

   function Is_ZIP_External_Method
     (Method : Interfaces.Unsigned_16) return Boolean;
   --  Return True for ZIP compression method ids handled by the non-Deflate
   --  ZIP codec bridge: bzip2 (12), LZMA (14), Zstandard (20/93), and PPMd
   --  (98). BZip2 ZIP creation and unencrypted extraction, ZIP-LZMA
   --  normal-distance creation/extraction, and Zstandard ZIP creation and
   --  unencrypted extraction, including ZIP64 size metadata, are handled
   --  in-process. Encrypted entries and ZIP PPMd are recognized by this
   --  bridge but fail closed with Unsupported_Method.
   --  @param Method ZIP compression method id
   --  @return True when Extract_ZIP_External_Entry can attempt this method

   function ZIP_External_Method_Name
     (Method : Interfaces.Unsigned_16) return String;
   --  Return the canonical method name for a ZIP method id handled by the
   --  non-Deflate ZIP codec bridge: "BZip2" for 12, "LZMA" for 14, "ZSTD"
   --  for 20/93, and "PPMd" for 98. Return the empty string for methods
   --  outside this bridge.
   --  @param Method ZIP compression method id
   --  @return canonical method name for Compress_ZIP_External_File, or ""

   function Extract_ZIP_External_Entry
     (Archive_Image : Byte_Array;
      Temp_Base     : String;
      Entry_Name    : String;
      Password      : String;
      Status        : out Status_Code) return Byte_Array;
   --  Extract one ZIP entry for ZIP methods that are outside Deflate. BZip2
   --  entries are decoded in-process when they are not encrypted and use
   --  classic or ZIP64 size metadata. ZIP-LZMA entries emitted by this
   --  library and Zstandard entries are also decoded in-process when they are
   --  not encrypted and use classic or ZIP64 size metadata. Other LZMA
   --  streams, ZIP PPMd, and encrypted entries fail closed with
   --  Unsupported_Method. Temp_Base is accepted for compatibility and is not
   --  used by the in-process paths.
   --  @param Archive_Image complete logical ZIP archive image
   --  @param Temp_Base filesystem path prefix for temporary files/directories
   --  @param Entry_Name archive entry path to extract
   --  @param Password optional ZIP password for encrypted entries
   --  @param Status set to Ok on success, otherwise a deterministic failure code
   --  @return extracted bytes when Status is Ok; otherwise an empty array

   function Compress_ZIP_External_File
     (Input_Path        : String;
      Temp_Base         : String;
      Method_Name       : String;
      Method            : out Interfaces.Unsigned_16;
      Crc32             : out Interfaces.Unsigned_32;
      Uncompressed_Size : out Interfaces.Unsigned_64;
      Status            : out Status_Code) return Byte_Array;
   --  Compress Input_Path as one ZIP entry and return only the compressed
   --  member payload. BZip2, ZIP-LZMA normal-distance streams, and Zstandard
   --  are compressed in-process. ZIP PPMd and unsupported method names fail
   --  closed with Unsupported_Method. Temp_Base is accepted for compatibility
   --  and is not used by the in-process paths. Method_Name is the ZIP method
   --  name, for example BZip2.
   --  @param Input_Path source file to compress
   --  @param Temp_Base filesystem path prefix for temporary files
   --  @param Method_Name ZIP method name
   --  @param Method parsed ZIP compression method id
   --  @param Crc32 parsed ZIP CRC32 for the uncompressed payload
   --  @param Uncompressed_Size parsed uncompressed payload size
   --  @param Status set to Ok on success, otherwise a deterministic failure code
   --  @return compressed ZIP member payload when Status is Ok

   procedure Seven_Zip_External_File
     (Input_Path  : String;
      Output_Path : String;
      Method_Name : String;
      Solid       : Boolean;
      Password    : String;
      Status      : out Status_Code);
   --  Compatibility placeholder for the former external .7z bridge. This
   --  procedure does not invoke a local 7z executable. Native
   --  Seven_Zip_Stored/Deflate/BZip2/LZMA/LZMA2/PPMd APIs remain in-process;
   --  unsupported broader 7z creation fails closed with Unsupported_Method
   --  after deterministic input/output path checks.
   --  @param Input_Path source file or directory to archive
   --  @param Output_Path path that receives the .7z archive
   --  @param Method_Name 7z compression method name
   --  @param Solid True for solid archives, False for independent streams
   --  @param Password optional 7z password
   --  @param Status set to Ok on success, otherwise a deterministic failure code

   procedure Seven_Zip_PPMd_File
     (Input_Path  : String;
      Output_Path : String;
      Status      : out Status_Code);
   --  Create a .7z archive using the PPMd method. This helper is native-only:
   --  it reads the input file or emits a header-only directory entry and writes
   --  a deterministic in-process PPMd stream selected from verified candidates
   --  accepted by this crate's native extractor. It does not call a local 7z
   --  executable.
   --  @param Input_Path source file or directory to archive
   --  @param Output_Path path that receives the .7z archive
   --  @param Status set to Ok on success, otherwise a deterministic failure code

   procedure Seven_Zip_PPMd_File
     (Input_Path  : String;
      Output_Path : String;
      Entry_Name  : String;
      Status      : out Status_Code);
   --  Create a .7z archive using the PPMd method and an explicit entry name.
   --  This helper is native-only: it reads the input file or emits a
   --  header-only directory entry and writes a deterministic in-process PPMd
   --  stream selected from verified candidates accepted by this crate's native
   --  extractor. It does not call a local 7z executable.
   --  @param Input_Path source file or directory to archive
   --  @param Output_Path path that receives the .7z archive
   --  @param Entry_Name archive entry name, without NUL characters
   --  @param Status set to Ok on success, otherwise a deterministic failure code

   procedure Extract_Seven_Zip_External_File
     (Input_Path : String;
      Output_Dir : String;
      Password   : String;
      Status     : out Status_Code);
   --  Compatibility placeholder for the former external .7z extraction
   --  bridge. This procedure does not invoke a local 7z executable. Broader
   --  unsupported 7z archives and password-protected archives fail closed
   --  with Unsupported_Method after deterministic input/output path checks.
   --  Neutral Extract_Seven_Zip APIs do not use an external fallback. The
   --  native extractor may skip an SFX prefix and common archive/file
   --  metadata while extracting supported payload layouts, but does not
   --  preserve metadata.
   --  @param Input_Path source .7z archive
   --  @param Output_Dir directory that receives extracted entries
   --  @param Password optional 7z password
   --  @param Status set to Ok on success, otherwise a deterministic failure code

   type Seven_Zip_Entry_Metadata is record
      Is_Directory           : Boolean := False;
      Has_Modification_Time  : Boolean := False;
      Modification_Time      : Interfaces.Unsigned_64 := 0;
      Has_Windows_Attributes : Boolean := False;
      Windows_Attributes     : Interfaces.Unsigned_32 := 0;
   end record;
   --  Metadata decoded for a selected 7z entry. Modification_Time is the
   --  raw Windows FILETIME value from the archive. Windows_Attributes is the
   --  raw attribute mask; file extraction currently applies the read-only
   --  bit when it is present.

   No_Seven_Zip_Entry_Metadata : constant Seven_Zip_Entry_Metadata :=
     (Is_Directory           => False,
      Has_Modification_Time  => False,
      Modification_Time      => 0,
      Has_Windows_Attributes => False,
      Windows_Attributes     => 0);
   --  Empty 7z metadata value.

   function Seven_Zip_Stored
     (Input      : Byte_Array;
      Entry_Name : String;
      Status     : out Status_Code) return Byte_Array;
   --  Encode Input as a native .7z archive containing one stored file entry.
   --  This writer is fully in-process and does not invoke a local 7z
   --  executable. This release supports the 7z container with the Copy coder,
   --  Deflate coder, BZip2 coder, LZMA coder, LZMA2 chunks, and the native
   --  native PPMd writer. Explicit metadata overloads emit supported
   --  modification times and Windows attributes for file entries; the stored
   --  metadata overload also emits header-only directory entries. Solid
   --  blocks and encryption are not emitted yet.
   --  @param Input uncompressed file payload
   --  @param Entry_Name archive entry name, without NUL characters
   --  @param Status set to Ok on success, otherwise a deterministic failure code
   --  @return .7z archive image when Status is Ok

   function Seven_Zip_Deflate
     (Input      : Byte_Array;
      Entry_Name : String;
      Mode       : Compression_Mode;
      Status     : out Status_Code) return Byte_Array;
   --  Encode Input as a native .7z archive containing one Deflate-compressed
   --  file entry. The archive container is written in-process and the payload
   --  uses the library raw-Deflate compressor. This is not LZMA/LZMA2. Solid
   --  blocks and encryption are not emitted. Metadata overloads emit
   --  header-only directory entries when Metadata.Is_Directory is True.
   --  @param Input uncompressed file payload
   --  @param Entry_Name archive entry name, without NUL characters
   --  @param Mode raw-Deflate compression mode for the packed payload
   --  @param Status set to Ok on success, otherwise a deterministic failure code
   --  @return .7z archive image when Status is Ok

   function Seven_Zip_Deflate
     (Input      : Byte_Array;
      Entry_Name : String;
      Mode       : Compression_Mode;
      Metadata   : Seven_Zip_Entry_Metadata;
      Status     : out Status_Code) return Byte_Array;
   --  Encode Input as a native .7z Deflate archive and emit supported file
   --  metadata. When Metadata.Is_Directory is True, Input is ignored and a
   --  header-only directory entry is emitted.
   --  @param Input uncompressed file payload
   --  @param Entry_Name archive entry name, without NUL characters
   --  @param Mode raw-Deflate compression mode for the packed payload
   --  @param Metadata optional file metadata emitted into the 7z file record
   --  @param Status set to Ok on success, otherwise a deterministic failure code
   --  @return .7z archive image when Status is Ok

   function Seven_Zip_Deflate
     (Input      : Byte_Array;
      Entry_Name : String;
      Level      : Compression_Level;
      Status     : out Status_Code) return Byte_Array;
   --  Encode Input as a native .7z archive containing one Deflate-compressed
   --  file entry using broad compression Level.
   --  @param Input uncompressed file payload
   --  @param Entry_Name archive entry name, without NUL characters
   --  @param Level broad raw-Deflate compression-effort policy
   --  @param Status set to Ok on success, otherwise a deterministic failure code
   --  @return .7z archive image when Status is Ok

   function Seven_Zip_Deflate
     (Input      : Byte_Array;
      Entry_Name : String;
      Level      : Compression_Level;
      Metadata   : Seven_Zip_Entry_Metadata;
      Status     : out Status_Code) return Byte_Array;
   --  Encode Input as a native .7z Deflate archive using broad compression
   --  Level and emit supported file metadata. When Metadata.Is_Directory is
   --  True, Input is ignored and a header-only directory entry is emitted.
   --  @param Input uncompressed file payload
   --  @param Entry_Name archive entry name, without NUL characters
   --  @param Level broad raw-Deflate compression-effort policy
   --  @param Metadata optional file metadata emitted into the 7z file record
   --  @param Status set to Ok on success, otherwise a deterministic failure code
   --  @return .7z archive image when Status is Ok

   function Seven_Zip_Deflate
     (Input      : Byte_Array;
      Entry_Name : String;
      Status     : out Status_Code) return Byte_Array;
   --  Encode Input as a native .7z archive containing one Deflate-compressed
   --  file entry using Auto compression mode.
   --  @param Input uncompressed file payload
   --  @param Entry_Name archive entry name, without NUL characters
   --  @param Status set to Ok on success, otherwise a deterministic failure code
   --  @return .7z archive image when Status is Ok

   function Seven_Zip_Deflate
     (Input      : Byte_Array;
      Entry_Name : String;
      Metadata   : Seven_Zip_Entry_Metadata;
      Status     : out Status_Code) return Byte_Array;
   --  Encode Input as a native .7z Deflate archive using Auto compression mode
   --  and emit supported file metadata. When Metadata.Is_Directory is True,
   --  Input is ignored and a header-only directory entry is emitted.
   --  @param Input uncompressed file payload
   --  @param Entry_Name archive entry name, without NUL characters
   --  @param Metadata optional file metadata emitted into the 7z file record
   --  @param Status set to Ok on success, otherwise a deterministic failure code
   --  @return .7z archive image when Status is Ok

   function Seven_Zip_LZMA
     (Input      : Byte_Array;
      Entry_Name : String;
      Status     : out Status_Code) return Byte_Array;
   --  Encode Input as a native .7z archive containing one LZMA-coded file
   --  entry. The archive container and LZMA payload are written in-process
   --  using the native LZMA coder with the library default lc/lp/pb and
   --  dictionary properties.
   --  @param Input uncompressed file payload
   --  @param Entry_Name archive entry name, without NUL characters
   --  @param Status set to Ok on success, otherwise a deterministic failure code
   --  @return .7z archive image when Status is Ok

   function Seven_Zip_LZMA
     (Input      : Byte_Array;
      Entry_Name : String;
      Metadata   : Seven_Zip_Entry_Metadata;
      Status     : out Status_Code) return Byte_Array;
   --  Encode Input as a native .7z LZMA archive and emit supported file
   --  metadata. When Metadata.Is_Directory is True, Input is ignored and a
   --  header-only directory entry is emitted.
   --  @param Input uncompressed file payload
   --  @param Entry_Name archive entry name, without NUL characters
   --  @param Metadata optional file metadata emitted into the 7z file record
   --  @param Status set to Ok on success, otherwise a deterministic failure code
   --  @return .7z archive image when Status is Ok

   function Seven_Zip_BZip2
     (Input      : Byte_Array;
      Entry_Name : String;
      Status     : out Status_Code) return Byte_Array;
   --  Encode Input as a native .7z archive containing one BZip2-coded file
   --  entry. The archive container and BZip2 payload are written in-process
   --  without a local 7z executable.
   --  @param Input uncompressed file payload
   --  @param Entry_Name archive entry name, without NUL characters
   --  @param Status set to Ok on success, otherwise a deterministic failure code
   --  @return .7z archive image when Status is Ok

   function Seven_Zip_BZip2
     (Input      : Byte_Array;
      Entry_Name : String;
      Metadata   : Seven_Zip_Entry_Metadata;
      Status     : out Status_Code) return Byte_Array;
   --  Encode Input as a native .7z BZip2 archive and emit supported file
   --  metadata. When Metadata.Is_Directory is True, Input is ignored and a
   --  header-only directory entry is emitted.
   --  @param Input uncompressed file payload
   --  @param Entry_Name archive entry name, without NUL characters
   --  @param Metadata optional file metadata emitted into the 7z file record
   --  @param Status set to Ok on success, otherwise a deterministic failure code
   --  @return .7z archive image when Status is Ok

   function Seven_Zip_LZMA2
     (Input      : Byte_Array;
      Entry_Name : String;
      Status     : out Status_Code) return Byte_Array;
   --  Encode Input as a native .7z archive containing one LZMA2-coded file
   --  entry. The LZMA2 stream is written in-process using valid LZMA2 chunks,
   --  including compressed chunks for payloads that benefit from them, so the
   --  archive uses the native LZMA2 coder without a local 7z executable. The
   --  native extractor accepts reset/properties, state-reset, and
   --  state-continuing LZMA2 chunks with supported lc/lp/pb properties in the
   --  single-folder layout. The native extractor skips common archive/file
   --  metadata while extracting supported payload layouts. Explicit metadata
   --  overloads emit supported modification times and Windows attributes for
   --  file entries and header-only directory entries. Solid blocks and
   --  encryption are not emitted.
   --  @param Input uncompressed file payload
   --  @param Entry_Name archive entry name, without NUL characters
   --  @param Status set to Ok on success, otherwise a deterministic failure code
   --  @return .7z archive image when Status is Ok

   function Seven_Zip_LZMA2
     (Input      : Byte_Array;
      Entry_Name : String;
      Metadata   : Seven_Zip_Entry_Metadata;
      Status     : out Status_Code) return Byte_Array;
   --  Encode Input as a native .7z LZMA2 archive and emit supported file
   --  metadata. When Metadata.Is_Directory is True, Input is ignored and a
   --  header-only directory entry is emitted.
   --  @param Input uncompressed file payload
   --  @param Entry_Name archive entry name, without NUL characters
   --  @param Metadata optional file metadata emitted into the 7z file record
   --  @param Status set to Ok on success, otherwise a deterministic failure code
   --  @return .7z archive image when Status is Ok

   function Seven_Zip_PPMd
     (Input      : Byte_Array;
      Entry_Name : String;
      Status     : out Status_Code) return Byte_Array;
   --  Encode Input as a native .7z archive containing one PPMd-coded file
   --  entry. The archive container and PPMd payload are written in-process
   --  using a deterministic PPMd stream selected from verified candidates
   --  accepted by this crate's native extractor. The generated archive is self-verified with the
   --  native extractor before Ok is returned. This function does not call a
   --  local 7z executable.
   --  Explicit metadata overloads emit supported modification times and
   --  Windows attributes for file entries and header-only directory entries.
   --  Solid blocks and encryption are not emitted.
   --  @param Input uncompressed file payload
   --  @param Entry_Name archive entry name, without NUL characters
   --  @param Status set to Ok on success, otherwise a deterministic failure code
   --  @return .7z archive image when Status is Ok

   function Seven_Zip_PPMd
     (Input      : Byte_Array;
      Entry_Name : String;
      Metadata   : Seven_Zip_Entry_Metadata;
      Status     : out Status_Code) return Byte_Array;
   --  Encode Input as a native .7z PPMd archive and emit supported file
   --  metadata. When Metadata.Is_Directory is True, Input is ignored and a
   --  header-only directory entry is emitted.
   --  @param Input uncompressed file payload
   --  @param Entry_Name archive entry name, without NUL characters
   --  @param Metadata optional file metadata emitted into the 7z file record
   --  @param Status set to Ok on success, otherwise a deterministic failure code
   --  @return .7z archive image when Status is Ok

   procedure Seven_Zip_Stored_File
     (Input_Path  : String;
      Output_Path : String;
      Entry_Name  : String;
      Status      : out Status_Code);
   --  Encode one file or directory as a native .7z archive containing a stored
   --  file entry or a header-only directory entry.
   --  The archive is written in-process with the same Copy-coder limitations
   --  as Seven_Zip_Stored.
   --  @param Input_Path source file or directory to archive
   --  @param Output_Path path that receives the .7z archive
   --  @param Entry_Name archive entry name, without NUL characters
   --  @param Status set to Ok on success, otherwise a deterministic failure code

   procedure Seven_Zip_Deflate_File
     (Input_Path  : String;
      Output_Path : String;
      Entry_Name  : String;
      Mode        : Compression_Mode;
      Status      : out Status_Code);
   --  Encode one file or directory as a native .7z archive containing a
   --  Deflate-compressed file entry or a header-only directory entry.
   --  @param Input_Path source file or directory to archive
   --  @param Output_Path path that receives the .7z archive
   --  @param Entry_Name archive entry name, without NUL characters
   --  @param Mode raw-Deflate compression mode for the packed payload
   --  @param Status set to Ok on success, otherwise a deterministic failure code

   procedure Seven_Zip_Deflate_File
     (Input_Path  : String;
      Output_Path : String;
      Entry_Name  : String;
      Level       : Compression_Level;
      Status      : out Status_Code);
   --  Encode one file or directory as a native .7z archive containing a
   --  Deflate-compressed file entry or a header-only directory entry using
   --  broad compression Level.
   --  @param Input_Path source file or directory to archive
   --  @param Output_Path path that receives the .7z archive
   --  @param Entry_Name archive entry name, without NUL characters
   --  @param Level broad raw-Deflate compression-effort policy
   --  @param Status set to Ok on success, otherwise a deterministic failure code

   procedure Seven_Zip_Deflate_File
     (Input_Path  : String;
      Output_Path : String;
      Entry_Name  : String;
      Status      : out Status_Code);
   --  Encode one file or directory as a native .7z archive containing a
   --  Deflate-compressed file entry or a header-only directory entry using Auto
   --  compression mode.
   --  @param Input_Path source file or directory to archive
   --  @param Output_Path path that receives the .7z archive
   --  @param Entry_Name archive entry name, without NUL characters
   --  @param Status set to Ok on success, otherwise a deterministic failure code

   procedure Seven_Zip_LZMA_File
     (Input_Path  : String;
      Output_Path : String;
      Entry_Name  : String;
      Status      : out Status_Code);
   --  Encode one file or directory as a native .7z archive containing an
   --  LZMA-coded file entry or a header-only directory entry.
   --  @param Input_Path source file or directory to archive
   --  @param Output_Path path that receives the .7z archive
   --  @param Entry_Name archive entry name, without NUL characters
   --  @param Status set to Ok on success, otherwise a deterministic failure code

   procedure Seven_Zip_BZip2_File
     (Input_Path  : String;
      Output_Path : String;
      Entry_Name  : String;
      Status      : out Status_Code);
   --  Encode one file or directory as a native .7z archive containing a
   --  BZip2-coded file entry or a header-only directory entry.
   --  @param Input_Path source file or directory to archive
   --  @param Output_Path path that receives the .7z archive
   --  @param Entry_Name archive entry name, without NUL characters
   --  @param Status set to Ok on success, otherwise a deterministic failure code

   procedure Seven_Zip_LZMA2_File
     (Input_Path  : String;
      Output_Path : String;
      Entry_Name  : String;
      Status      : out Status_Code);
   --  Encode one file or directory as a native .7z archive containing an
   --  LZMA2-coded file entry or a header-only directory entry using valid LZMA2
   --  chunks, including compressed chunks when useful.
   --  @param Input_Path source file or directory to archive
   --  @param Output_Path path that receives the .7z archive
   --  @param Entry_Name archive entry name, without NUL characters
   --  @param Status set to Ok on success, otherwise a deterministic failure code

   procedure Seven_Zip_Stored_Files
     (Input_Paths : Text_Array;
      Output_Path : String;
      Entry_Names : Text_Array;
      Status      : out Status_Code);
   --  Encode several paths as one native .7z archive containing stored file
   --  entries and no-stream directory entries. Input_Paths and Entry_Names
   --  are parallel arrays and must have the same nonzero length, and entry
   --  names must be distinct. Ordinary files are written in-process as one
   --  solid 7z Copy-coder folder with one substream per file; compressed
   --  LZMA/LZMA2 and encryption are not emitted by this writer. Supported
   --  source modification times and Windows attributes are preserved when
   --  available.
   --  @param Input_Paths source files or directories to archive
   --  @param Output_Path path that receives the .7z archive
   --  @param Entry_Names archive entry names, without NUL characters
   --  @param Status set to Ok on success, otherwise a deterministic failure code

   procedure Seven_Zip_Deflate_Files
     (Input_Paths : Text_Array;
      Output_Path : String;
      Entry_Names : Text_Array;
      Mode        : Compression_Mode;
      Status      : out Status_Code);
   --  Encode several paths as one native .7z archive containing Deflate-packed
   --  file entries and no-stream directory entries. Input_Paths and
   --  Entry_Names are parallel arrays and must have the same nonzero length,
   --  and entry names must be distinct. Each ordinary file is packed
   --  independently with raw Deflate; solid compression and encryption are
   --  not emitted. Supported source modification times and Windows attributes
   --  are preserved when available.
   --  @param Input_Paths source files or directories to archive
   --  @param Output_Path path that receives the .7z archive
   --  @param Entry_Names archive entry names, without NUL characters
   --  @param Mode raw-Deflate compression mode for each packed payload
   --  @param Status set to Ok on success, otherwise a deterministic failure code

   procedure Seven_Zip_Deflate_Files
     (Input_Paths : Text_Array;
      Output_Path : String;
      Entry_Names : Text_Array;
      Level       : Compression_Level;
      Status      : out Status_Code);
   --  Encode several paths as one native .7z archive containing Deflate-packed
   --  file entries and no-stream directory entries using broad compression
   --  Level. Supported source metadata is preserved like the Compression_Mode
   --  overload.
   --  @param Input_Paths source files or directories to archive
   --  @param Output_Path path that receives the .7z archive
   --  @param Entry_Names archive entry names, without NUL characters
   --  @param Level broad raw-Deflate compression-effort policy
   --  @param Status set to Ok on success, otherwise a deterministic failure code

   procedure Seven_Zip_Deflate_Files
     (Input_Paths : Text_Array;
      Output_Path : String;
      Entry_Names : Text_Array;
      Status      : out Status_Code);
   --  Encode several paths as one native .7z archive containing Deflate-packed
   --  file entries and no-stream directory entries using Auto compression
   --  mode. Supported source metadata is preserved like the Compression_Mode
   --  overload.
   --  @param Input_Paths source files or directories to archive
   --  @param Output_Path path that receives the .7z archive
   --  @param Entry_Names archive entry names, without NUL characters
   --  @param Status set to Ok on success, otherwise a deterministic failure code

   procedure Seven_Zip_BZip2_Files
     (Input_Paths : Text_Array;
      Output_Path : String;
      Entry_Names : Text_Array;
      Status      : out Status_Code);
   --  Encode several paths as one native .7z archive containing BZip2-packed
   --  file entries and no-stream directory entries. Input_Paths and
   --  Entry_Names are parallel arrays and must have the same nonzero length,
   --  and entry names must be distinct. Each ordinary file is packed
   --  independently with BZip2; solid compression and encryption are not
   --  emitted. Supported source modification times and Windows attributes are
   --  preserved when available.
   --  @param Input_Paths source files or directories to archive
   --  @param Output_Path path that receives the .7z archive
   --  @param Entry_Names archive entry names, without NUL characters
   --  @param Status set to Ok on success, otherwise a deterministic failure code

   procedure Seven_Zip_LZMA_Files
     (Input_Paths : Text_Array;
      Output_Path : String;
      Entry_Names : Text_Array;
      Status      : out Status_Code);
   --  Encode several paths as one native .7z archive containing LZMA-coded
   --  file entries and no-stream directory entries. Input_Paths and
   --  Entry_Names are parallel arrays and must have the same nonzero length,
   --  and entry names must be distinct. Each ordinary file is packed
   --  independently with the native LZMA coder using the library default
   --  lc/lp/pb and dictionary properties; solid compression and encryption
   --  are not emitted. Supported source modification times and Windows
   --  attributes are preserved when available.
   --  @param Input_Paths source files or directories to archive
   --  @param Output_Path path that receives the .7z archive
   --  @param Entry_Names archive entry names, without NUL characters
   --  @param Status set to Ok on success, otherwise a deterministic failure code

   procedure Seven_Zip_LZMA2_Files
     (Input_Paths : Text_Array;
      Output_Path : String;
      Entry_Names : Text_Array;
      Status      : out Status_Code);
   --  Encode several paths as one native .7z archive containing LZMA2-coded
   --  file entries and no-stream directory entries. Input_Paths and
   --  Entry_Names are parallel arrays and must have the same nonzero length,
   --  and entry names must be distinct. Each ordinary file is packed
   --  independently with valid LZMA2 chunks, including compressed chunks when
   --  useful; solid compression and encryption are not emitted. Supported
   --  source modification times and Windows attributes are preserved when
   --  available.
   --  @param Input_Paths source files or directories to archive
   --  @param Output_Path path that receives the .7z archive
   --  @param Entry_Names archive entry names, without NUL characters
   --  @param Status set to Ok on success, otherwise a deterministic failure code

   procedure Seven_Zip_PPMd_Files
     (Input_Paths : Text_Array;
      Output_Path : String;
      Entry_Names : Text_Array;
      Status      : out Status_Code);
   --  Encode several paths as one native .7z archive containing PPMd-coded
   --  file entries and no-stream directory entries. Input_Paths and
   --  Entry_Names are parallel arrays and must have the same nonzero length,
   --  and entry names must be distinct. Each ordinary file is packed
   --  independently with the deterministic verified PPMd writer accepted by this
   --  crate's extractor. The writer selects among verified stock-compatible
   --  PPMd candidates, repeated/periodic PPMd forms, and a verified native root
   --  context fallback; solid compression and encryption are not emitted.
   --  Supported source modification times and
   --  Windows attributes are preserved when available.
   --  @param Input_Paths source files or directories to archive
   --  @param Output_Path path that receives the .7z archive
   --  @param Entry_Names archive entry names, without NUL characters
   --  @param Status set to Ok on success, otherwise a deterministic failure code

   procedure Seven_Zip_LZMA_Solid_Files
     (Input_Paths : Text_Array;
      Output_Path : String;
      Entry_Names : Text_Array;
      Status      : out Status_Code);
   --  Like Seven_Zip_LZMA_Files but SOLID: all ordinary files are
   --  concatenated and compressed into a single LZMA folder, with per-file
   --  substream sizes and CRCs, for a better ratio across many small files.
   --  Stock 7z reads the result and our extractor round-trips it.
   --  @param Input_Paths source files or directories to archive
   --  @param Output_Path path that receives the .7z archive
   --  @param Entry_Names archive entry names, without NUL characters
   --  @param Status set to Ok on success, otherwise a deterministic failure code

   procedure Seven_Zip_LZMA2_Solid_Files
     (Input_Paths : Text_Array;
      Output_Path : String;
      Entry_Names : Text_Array;
      Status      : out Status_Code);
   --  Solid LZMA2 multi-file archive (see Seven_Zip_LZMA_Solid_Files).
   --  @param Input_Paths source files or directories to archive
   --  @param Output_Path path that receives the .7z archive
   --  @param Entry_Names archive entry names, without NUL characters
   --  @param Status set to Ok on success, otherwise a deterministic failure code

   procedure Seven_Zip_PPMd_Solid_Files
     (Input_Paths : Text_Array;
      Output_Path : String;
      Entry_Names : Text_Array;
      Status      : out Status_Code);
   --  Solid PPMd multi-file archive (see Seven_Zip_LZMA_Solid_Files). PPMd
   --  benefits most from solid mode since its model carries across files.
   --  @param Input_Paths source files or directories to archive
   --  @param Output_Path path that receives the .7z archive
   --  @param Entry_Names archive entry names, without NUL characters
   --  @param Status set to Ok on success, otherwise a deterministic failure code

   procedure Seven_Zip_LZMA_Encrypted_Files
     (Input_Paths : Text_Array;
      Output_Path : String;
      Entry_Names : Text_Array;
      Password    : String;
      Status      : out Status_Code);
   --  Solid, AES-256-encrypted multi-file .7z: all ordinary files are
   --  concatenated, LZMA-compressed, and AES-256 encrypted into one
   --  [AES -> LZMA] folder with per-file substream sizes and CRCs. Read by
   --  stock 7z (and Extract_Seven_Zip) with the password.
   --  @param Input_Paths source files or directories to archive
   --  @param Output_Path path that receives the .7z archive
   --  @param Entry_Names archive entry names, without NUL characters
   --  @param Password the archive password
   --  @param Status set to Ok on success, otherwise a deterministic failure code

   function Seven_Zip_Stored
     (Input      : Byte_Array;
      Entry_Name : String;
      Metadata   : Seven_Zip_Entry_Metadata;
      Status     : out Status_Code) return Byte_Array;
   --  Encode Input as a native .7z Copy-coder entry with supported per-entry
   --  metadata. This overload emits modification FILETIME and raw Windows
   --  attributes when the corresponding Has_* fields are True. When
   --  Metadata.Is_Directory is True, it emits a header-only directory entry
   --  and ignores Input.
   --  @param Input uncompressed file payload
   --  @param Entry_Name archive entry name, without NUL characters
   --  @param Metadata metadata to emit for the file entry
   --  @param Status set to Ok on success, otherwise a deterministic failure code
   --  @return .7z archive image when Status is Ok

   function Extract_Seven_Zip_Stored
     (Archive_Image : Byte_Array;
      Entry_Name    : String;
      Status        : out Status_Code) return Byte_Array;
   --  Extract one file from a native .7z archive that uses the Copy-coder
   --  layout emitted by Seven_Zip_Stored/Seven_Zip_Stored_Files or the
   --  Deflate layout emitted by Seven_Zip_Deflate/Seven_Zip_Deflate_Files,
   --  native BZip2 streams, native LZMA streams, native LZMA2
   --  compressed/uncompressed chunk streams, and the supported native PPMd
   --  extraction subset for empty streams with or without range headers,
   --  repeated-symbol, simple root-symbol, periodic-prefix, stock-7z
   --  non-solid multi-block streams with LZMA encoded headers, stock-7z
   --  no-stream empty-file entries, stock-7z BCJ+PPMd filter chains, and
   --  BCJ2 graphs with Copy, PPMd, or supported main pre-coders. Broader PPMd entries
   --  fail closed with a non-Ok status. The PPMd model table is allocated
   --  from the archive's declared PPMd memory and requested output size rather
   --  than a fixed stream-independent context cap. Supported extraction
   --  also accepts encoded headers, solid substreams, BCJ2 graph layouts with
   --  supported main-stream pre-coders, and bounded linear filter chains made
   --  from supported single-input coders and x86 BCJ/Delta filters, including
   --  standard zero-based,
   --  reverse-linear, reordered zero-based, and legacy one-based linear bind
   --  pairs.
   --  Header CRC, packed CRC, unpacked CRC, method, size, and UTF-16LE entry
   --  names are verified.
   --  Archives with duplicate matching entry names are rejected. Broader non-PPMd
   --  7z archives fail closed with a non-Ok status. Byte-array extraction
   --  returns payload bytes only; file helpers restore supported per-entry
   --  directories, modification times, and read-only attributes.
   --  @param Archive_Image complete .7z archive image
   --  @param Entry_Name expected archive entry name, without NUL characters
   --  @param Status set to Ok on success, otherwise a deterministic failure code
   --  @return extracted payload when Status is Ok

   function Extract_Seven_Zip
     (Archive_Image : Byte_Array;
      Entry_Name    : String;
      Status        : out Status_Code) return Byte_Array;
   --  Neutral extractor name. It extracts the supported native Copy-coder,
   --  Deflate, BZip2, LZMA, LZMA2, supported native PPMd, solid substream,
   --  BCJ2 graph layouts with supported main-stream pre-coders, and bounded
   --  supported linear filter-chain layouts recognized by the native 7z extractor, including
   --  standard zero-based, reverse-linear, reordered zero-based, and legacy
   --  one-based linear bind pairs. Broader
   --  unsupported 7z methods fail closed with a non-Ok status.
   --  @param Archive_Image complete .7z archive image
   --  @param Entry_Name expected archive entry name, without NUL characters
   --  @param Status set to Ok on success, otherwise a deterministic failure code
   --  @return extracted payload when Status is Ok

   function Seven_Zip_LZMA_Encrypted
     (Input      : Byte_Array;
      Entry_Name : String;
      Password   : String;
      Status     : out Status_Code) return Byte_Array;
   --  Encode Input as a one-file .7z whose payload is LZMA-compressed then
   --  AES-256 (7zAES) encrypted with the given password. The result is read by
   --  stock 7z (and by Extract_Seven_Zip with the password).
   --  @param Input uncompressed file payload
   --  @param Entry_Name archive entry name, without NUL characters
   --  @param Password the archive password
   --  @param Status set to Ok on success, otherwise a deterministic failure code
   --  @return .7z archive image when Status is Ok

   function Extract_Seven_Zip
     (Archive_Image : Byte_Array;
      Entry_Name    : String;
      Password      : String;
      Status        : out Status_Code) return Byte_Array;
   --  As Extract_Seven_Zip, but supplies a password for AES-256 (7zAES)
   --  encrypted folders. A wrong password surfaces as Invalid_Checksum.
   --  @param Archive_Image complete .7z archive image
   --  @param Entry_Name expected archive entry name, without NUL characters
   --  @param Password the archive password
   --  @param Status set to Ok on success, otherwise a deterministic failure code
   --  @return extracted payload when Status is Ok

   function Extract_Seven_Zip_Metadata
     (Archive_Image : Byte_Array;
      Entry_Name    : String;
      Status        : out Status_Code) return Seven_Zip_Entry_Metadata;
   --  Decode metadata for one selected entry using the same native 7z parser
   --  and verification policy as Extract_Seven_Zip. Status is Ok only when
   --  the entry is supported and verified. On failure, return
   --  No_Seven_Zip_Entry_Metadata.
   --  @param Archive_Image complete .7z archive image
   --  @param Entry_Name expected archive entry name, without NUL characters
   --  @param Status set to Ok on success, otherwise a deterministic failure code
   --  @return decoded 7z entry metadata when Status is Ok

   procedure Extract_Seven_Zip_Stored_File
     (Input_Path  : String;
      Output_Path : String;
      Entry_Name  : String;
      Status      : out Status_Code);
   --  Extract one file from a supported native Copy-coder, Deflate, BZip2,
   --  LZMA, LZMA2, or supported native PPMd .7z archive into Output_Path. This
   --  is the file helper for Extract_Seven_Zip_Stored. Directory entries
   --  create Output_Path as a directory. Missing parent directories for
   --  Output_Path are created before writing files or directories. If the
   --  archive entry has supported modification time or read-only metadata,
   --  Output_Path receives it.
   --  @param Input_Path source .7z archive
   --  @param Output_Path path that receives the extracted payload
   --  @param Entry_Name expected archive entry name, without NUL characters
   --  @param Status set to Ok on success, otherwise a deterministic failure code

   procedure Extract_Seven_Zip_Stored_Files
     (Input_Path   : String;
      Output_Dir   : String;
      Entry_Names  : Text_Array;
      Status       : out Status_Code);
   --  Extract selected entries from a supported native Copy-coder, Deflate,
   --  BZip2, LZMA, LZMA2, or supported native PPMd .7z archive into Output_Dir.
   --  Output_Dir must be non-empty.
   --  Entry_Names are interpreted as relative output paths and must be distinct; absolute
   --  paths, empty path segments, "." segments, ".." segments, backslashes,
   --  and drive-style names are rejected before any extraction. Requested
   --  payloads are all verified before any output file is written. Needed
   --  parent directories below Output_Dir are created. Supported per-entry
   --  directories, modification times, and read-only attributes are restored
   --  after each output path is created.
   --  @param Input_Path source .7z archive
   --  @param Output_Dir destination directory
   --  @param Entry_Names archive entry names to extract
   --  @param Status set to Ok on success, otherwise a deterministic failure code

   procedure Extract_Seven_Zip_File
     (Input_Path  : String;
      Output_Path : String;
      Entry_Name  : String;
      Status      : out Status_Code);
   --  Neutral file extractor name. It uses Extract_Seven_Zip semantics;
   --  missing parent directories for Output_Path are created before writing
   --  files or directories. Unsupported 7z methods fail closed with a non-Ok
   --  status.
   --  @param Input_Path source .7z archive
   --  @param Output_Path path that receives the extracted payload
   --  @param Entry_Name expected archive entry name, without NUL characters
   --  @param Status set to Ok on success, otherwise a deterministic failure code

   procedure Extract_Seven_Zip_Files
     (Input_Path   : String;
      Output_Dir   : String;
      Entry_Names  : Text_Array;
      Status       : out Status_Code);
   --  Neutral file-list extractor name. It uses Extract_Seven_Zip semantics
   --  for each selected entry; unsupported 7z methods fail closed with a
   --  non-Ok status.
   --  @param Input_Path source .7z archive
   --  @param Output_Dir destination directory
   --  @param Entry_Names archive entry names to extract
   --  @param Status set to Ok on success, otherwise a deterministic failure code

private
   type CRC32_State is record
      CRC : Interfaces.Unsigned_32 := 16#FFFF_FFFF#;
   end record;

   type GZip_Metadata is record
      Has_Name    : Boolean := False;
      Has_Comment : Boolean := False;
      Has_MTime   : Boolean := False;
      Has_OS      : Boolean := False;
      Has_XFL     : Boolean := False;
      Has_Extra   : Boolean := False;
      Header_CRC  : Boolean := False;
      Name        : Ada.Strings.Unbounded.Unbounded_String;
      Comment     : Ada.Strings.Unbounded.Unbounded_String;
      Extra       : Ada.Strings.Unbounded.Unbounded_String;
      MTime       : Interfaces.Unsigned_32 := 0;
      OS          : Byte := 255;
      XFL         : Byte := 0;
      Valid       : Boolean := True;
   end record;

   type Compression_Filter_State is
     (Compression_Closed,
      Compression_Open,
      Compression_Failed,
      Compression_Ended);

   Max_Compress_Block_Size  : constant Natural := 65_535;
   Max_Dynamic_Pending_Bits : constant Natural := 700_000;

   type Dynamic_Bit_Buffer is
     array (Natural range 0 .. Max_Dynamic_Pending_Bits - 1) of Boolean;

   type Stored_Compress_State is
     (Need_Zlib_Header_0,
      Need_Zlib_Header_1,
      Need_Zlib_DICTID_0,
      Need_Zlib_DICTID_1,
      Need_Zlib_DICTID_2,
      Need_Zlib_DICTID_3,
      Need_GZip_ID1,
      Need_GZip_ID2,
      Need_GZip_CM,
      Need_GZip_FLG,
      Need_GZip_MTIME_0,
      Need_GZip_MTIME_1,
      Need_GZip_MTIME_2,
      Need_GZip_MTIME_3,
      Need_GZip_XFL,
      Need_GZip_OS,
      Need_GZip_XLEN_0,
      Need_GZip_XLEN_1,
      Need_GZip_Extra,
      Need_GZip_Name,
      Need_GZip_Name_NUL,
      Need_GZip_Comment,
      Need_GZip_Comment_NUL,
      Need_GZip_HCRC_0,
      Need_GZip_HCRC_1,
      Collecting_Block,
      Emit_Block_Header,
      Emit_Flush_Block_Header,
      Emit_Len_0,
      Emit_Len_1,
      Emit_NLen_0,
      Emit_NLen_1,
      Emit_Block_Data,
      Fixed_Collecting_Block,
      Fixed_Emit_Block_Header,
      Fixed_Emit_Literals,
      Fixed_Emit_EOB,
      Fixed_Flush_Final_Byte,
      Dynamic_Collecting_Block,
      Dynamic_Emit_Pending_Bits,
      Dynamic_Flush_Final_Byte,
      Emit_Adler_0,
      Emit_Adler_1,
      Emit_Adler_2,
      Emit_Adler_3,
      Emit_GZip_CRC_0,
      Emit_GZip_CRC_1,
      Emit_GZip_CRC_2,
      Emit_GZip_CRC_3,
      Emit_GZip_ISIZE_0,
      Emit_GZip_ISIZE_1,
      Emit_GZip_ISIZE_2,
      Emit_GZip_ISIZE_3,
      Done);

   type Compression_Filter_Type is limited record
      State                : Compression_Filter_State := Compression_Closed;
      Header               : Header_Type := Zlib_Header;
      Mode                 : Compression_Mode := Auto;
      Level                : Compression_Level := Default_Level;
      Stored_Next          : Stored_Compress_State := Need_Zlib_Header_0;
      Block                :
        Ada.Streams.Stream_Element_Array
          (Ada.Streams.Stream_Element_Offset (0) ..
           Ada.Streams.Stream_Element_Offset (Max_Compress_Block_Size - 1)) :=
          [others => 0];
      Block_Count          : Natural := 0;
      Data_Index           : Natural := 0;
      Current_Final        : Boolean := False;
      Finish_Requested     : Boolean := False;
      Flush_Marker_Pending : Boolean := False;
      Adler_A              : Interfaces.Unsigned_32 := 1;
      Adler_B              : Interfaces.Unsigned_32 := 0;
      Dictionary_Set       : Boolean := False;
      Dictionary_ID        : Interfaces.Unsigned_32 := 0;
      CRC                  : Interfaces.Unsigned_32 := 16#FFFF_FFFF#;
      ISIZE                : Interfaces.Unsigned_32 := 0;
      Metadata             : GZip_Metadata :=
        (Has_Name    => False,
         Has_Comment => False,
         Has_MTime   => False,
         Has_OS      => False,
         Has_XFL     => False,
         Has_Extra   => False,
         Header_CRC  => False,
         Name        => Ada.Strings.Unbounded.Null_Unbounded_String,
         Comment     => Ada.Strings.Unbounded.Null_Unbounded_String,
         Extra       => Ada.Strings.Unbounded.Null_Unbounded_String,
         MTime       => 0,
         OS          => 255,
         XFL         => 0,
         Valid       => True);
      GZip_Header_CRC      : Interfaces.Unsigned_32 := 16#FFFF_FFFF#;
      Metadata_Index       : Natural := 1;
      Bit_Byte             : Ada.Streams.Stream_Element := 0;
      Bit_Index            : Natural range 0 .. 7 := 0;
      Pending_Bit_Byte     : Ada.Streams.Stream_Element := 0;
      Pending_Bit_Valid    : Boolean := False;
      Symbol_Code          : Natural := 0;
      Symbol_Bits_Left     : Natural := 0;
      Dynamic_Bits         : Dynamic_Bit_Buffer := [others => False];
      Dynamic_Bit_Count    : Natural := 0;
      Dynamic_Bit_Index    : Natural := 0;
   end record;

   type Filter_State is (Closed, Open, Failed, Ended);

   type Filter_Type is limited record
      State       : Filter_State := Closed;
      Header      : Header_Type := Default;
      Input_Bits  : System.Address := System.Null_Address;
      Output      : System.Address := System.Null_Address;
      Decoder     : System.Address := System.Null_Address;
      GZip_Mode   : GZip_Member_Mode := Single_Member;
      Last_Status : Status_Code := Ok;
   end record;
end Zlib;
