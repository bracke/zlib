# Public API

The root package `Zlib` is the public API entry point. Implementation
child packages are internal details and are not part of the consumer contract.

## Binary data types

```ada
type Byte is mod 2 ** 8;
type Byte_Array is array (Natural range <>) of Byte;
```

The API is binary-safe. It does not treat input as text, require NUL
termination, or modify payload bytes through character conversion.

## One-shot API

```ada
type Status_Code is
  (Ok,
   Invalid_Header,
   Unsupported_Method,
   Unsupported_Preset_Dictionary,
   Invalid_Checksum,
   Invalid_Block_Type,
   Invalid_Stored_Block,
   Invalid_Huffman_Code,
   Invalid_Distance,
   Unexpected_End_Of_Input,
   Input_File_Error,
   Output_File_Error);

function Status_Image (Status : Status_Code) return String;
function Looks_Like_Zlib_Header (Input : Byte_Array) return Boolean;
function Looks_Like_GZip_Header (Input : Byte_Array) return Boolean;
function Inflate (Input : Byte_Array; Status : out Status_Code) return Byte_Array;
function Inflate_With_Header
  (Input  : Byte_Array;
   Header : Header_Type;
   Status : out Status_Code)
   return Byte_Array;
function Inflate_Raw
  (Input  : Byte_Array;
   Status : out Status_Code)
   return Byte_Array;
procedure Inflate_File (Input_Path, Output_Path : String; Status : out Status_Code);
procedure Inflate_Raw_File (Input_Path, Output_Path : String; Status : out Status_Code);
function Deflate_Stored (Input : Byte_Array; Status : out Status_Code) return Byte_Array;
procedure Deflate_Stored_File (Input_Path, Output_Path : String; Status : out Status_Code);
function Deflate_Fixed (Input : Byte_Array; Status : out Status_Code) return Byte_Array;
procedure Deflate_Fixed_File (Input_Path, Output_Path : String; Status : out Status_Code);
function Deflate_Dynamic (Input : Byte_Array; Status : out Status_Code) return Byte_Array;
procedure Deflate_Dynamic_File (Input_Path, Output_Path : String; Status : out Status_Code);

type Compression_Mode is (Stored, Fixed, Dynamic, Auto);
function GZip
  (Input  : Byte_Array;
   Mode   : Compression_Mode := Auto;
   Status : out Status_Code)
   return Byte_Array;
procedure GZip_File
  (Input_Path, Output_Path : String;
   Mode   : Compression_Mode := Auto;
   Status : out Status_Code);

function Deflate
  (Input  : Byte_Array;
   Mode   : Compression_Mode := Auto;
   Status : out Status_Code)
   return Byte_Array;
procedure Deflate_File
  (Input_Path, Output_Path : String;
   Mode   : Compression_Mode := Auto;
   Status : out Status_Code);

function Deflate_Raw
  (Input  : Byte_Array;
   Mode   : Compression_Mode := Auto;
   Status : out Status_Code)
   return Byte_Array;
procedure Deflate_Raw_File
  (Input_Path, Output_Path : String;
   Mode   : Compression_Mode := Auto;
   Status : out Status_Code);
function ZIP
  (Input      : Byte_Array;
   Entry_Name : String;
   Mode       : Compression_Mode := Auto;
   Status     : out Status_Code)
   return Byte_Array;
procedure ZIP_File
  (Input_Path, Output_Path, Entry_Name : String;
   Mode   : Compression_Mode := Auto;
   Status : out Status_Code);
procedure ZIP_Files
  (Input_Paths : Text_Array;
   Output_Path : String;
   Entry_Names : Text_Array;
   Mode        : Compression_Mode := Auto;
   Force_ZIP64 : Boolean := False;
   Status      : out Status_Code);
function Seven_Zip_Stored
  (Input      : Byte_Array;
   Entry_Name : String;
   Status     : out Status_Code)
   return Byte_Array;
function Seven_Zip_Stored
  (Input      : Byte_Array;
   Entry_Name : String;
   Metadata   : Seven_Zip_Entry_Metadata;
   Status     : out Status_Code)
   return Byte_Array;
function Seven_Zip_Deflate
  (Input      : Byte_Array;
   Entry_Name : String;
   Mode       : Compression_Mode := Auto;
   Status     : out Status_Code)
   return Byte_Array;
function Seven_Zip_Deflate
  (Input      : Byte_Array;
   Entry_Name : String;
   Mode       : Compression_Mode;
   Metadata   : Seven_Zip_Entry_Metadata;
   Status     : out Status_Code)
   return Byte_Array;
function Seven_Zip_Deflate
  (Input      : Byte_Array;
   Entry_Name : String;
   Level      : Compression_Level;
   Status     : out Status_Code)
   return Byte_Array;
function Seven_Zip_Deflate
  (Input      : Byte_Array;
   Entry_Name : String;
   Level      : Compression_Level;
   Metadata   : Seven_Zip_Entry_Metadata;
   Status     : out Status_Code)
   return Byte_Array;
function Seven_Zip_Deflate
  (Input      : Byte_Array;
   Entry_Name : String;
   Metadata   : Seven_Zip_Entry_Metadata;
   Status     : out Status_Code)
   return Byte_Array;
procedure Seven_Zip_Stored_File
  (Input_Path, Output_Path, Entry_Name : String;
   Status : out Status_Code);
procedure Seven_Zip_Deflate_File
  (Input_Path, Output_Path, Entry_Name : String;
   Mode   : Compression_Mode := Auto;
   Status : out Status_Code);
procedure Seven_Zip_Deflate_File
  (Input_Path, Output_Path, Entry_Name : String;
   Level  : Compression_Level;
   Status : out Status_Code);
procedure Seven_Zip_Stored_Files
  (Input_Paths : Text_Array;
   Output_Path : String;
   Entry_Names : Text_Array;
   Status      : out Status_Code);
procedure Seven_Zip_Deflate_Files
  (Input_Paths : Text_Array;
   Output_Path : String;
   Entry_Names : Text_Array;
   Mode        : Compression_Mode := Auto;
   Status      : out Status_Code);
procedure Seven_Zip_Deflate_Files
  (Input_Paths : Text_Array;
   Output_Path : String;
   Entry_Names : Text_Array;
   Level       : Compression_Level;
   Status      : out Status_Code);
procedure Seven_Zip_BZip2_Files
  (Input_Paths : Text_Array;
   Output_Path : String;
   Entry_Names : Text_Array;
   Status      : out Status_Code);
procedure Seven_Zip_LZMA_Files
  (Input_Paths : Text_Array;
   Output_Path : String;
   Entry_Names : Text_Array;
   Status      : out Status_Code);
procedure Seven_Zip_LZMA2_Files
  (Input_Paths : Text_Array;
   Output_Path : String;
   Entry_Names : Text_Array;
   Status      : out Status_Code);
procedure Seven_Zip_PPMd_Files
  (Input_Paths : Text_Array;
   Output_Path : String;
   Entry_Names : Text_Array;
   Status      : out Status_Code);
function Seven_Zip_BZip2
  (Input      : Byte_Array;
   Entry_Name : String;
   Status     : out Status_Code) return Byte_Array;
function Seven_Zip_BZip2
  (Input      : Byte_Array;
   Entry_Name : String;
   Metadata   : Seven_Zip_Entry_Metadata;
   Status     : out Status_Code) return Byte_Array;
function Seven_Zip_LZMA
  (Input      : Byte_Array;
   Entry_Name : String;
   Status     : out Status_Code) return Byte_Array;
function Seven_Zip_LZMA
  (Input      : Byte_Array;
   Entry_Name : String;
   Metadata   : Seven_Zip_Entry_Metadata;
   Status     : out Status_Code) return Byte_Array;
function Seven_Zip_LZMA2
  (Input      : Byte_Array;
   Entry_Name : String;
   Status     : out Status_Code) return Byte_Array;
function Seven_Zip_LZMA2
  (Input      : Byte_Array;
   Entry_Name : String;
   Metadata   : Seven_Zip_Entry_Metadata;
   Status     : out Status_Code) return Byte_Array;
function Seven_Zip_PPMd
  (Input      : Byte_Array;
   Entry_Name : String;
   Status     : out Status_Code) return Byte_Array;
function Seven_Zip_PPMd
  (Input      : Byte_Array;
   Entry_Name : String;
   Metadata   : Seven_Zip_Entry_Metadata;
   Status     : out Status_Code) return Byte_Array;
procedure Seven_Zip_External_File
  (Input_Path  : String;
   Output_Path : String;
   Method_Name : String;
   Solid       : Boolean;
   Password    : String;
   Status      : out Status_Code);
procedure Seven_Zip_PPMd_File
  (Input_Path  : String;
   Output_Path : String;
   Status      : out Status_Code);
procedure Seven_Zip_PPMd_File
  (Input_Path, Output_Path, Entry_Name : String;
   Status : out Status_Code);
function ZIP_External_Method_Name
  (Method : Interfaces.Unsigned_16) return String;
function Is_ZIP_External_Method
  (Method : Interfaces.Unsigned_16) return Boolean;
function Compress_ZIP_External_File
  (Input_Path        : String;
   Temp_Base         : String;
   Method_Name       : String;
   Method            : out Interfaces.Unsigned_16;
   Crc32             : out Interfaces.Unsigned_32;
   Uncompressed_Size : out Interfaces.Unsigned_64;
   Status            : out Status_Code) return Byte_Array;
function Extract_ZIP_External_Entry
  (Archive_Image : Byte_Array;
   Temp_Base     : String;
   Entry_Name    : String;
   Password      : String;
   Status        : out Status_Code) return Byte_Array;
procedure Extract_Seven_Zip_External_File
  (Input_Path : String;
   Output_Dir : String;
   Password   : String;
   Status     : out Status_Code);
function Extract_Seven_Zip_Stored
  (Archive_Image : Byte_Array;
   Entry_Name    : String;
   Status        : out Status_Code)
   return Byte_Array;
function Extract_Seven_Zip
  (Archive_Image : Byte_Array;
   Entry_Name    : String;
   Status        : out Status_Code)
   return Byte_Array;
function Extract_Seven_Zip_Metadata
  (Archive_Image : Byte_Array;
   Entry_Name    : String;
   Status        : out Status_Code)
   return Seven_Zip_Entry_Metadata;
procedure Extract_Seven_Zip_Stored_File
  (Input_Path, Output_Path, Entry_Name : String;
   Status : out Status_Code);
procedure Extract_Seven_Zip_File
  (Input_Path, Output_Path, Entry_Name : String;
   Status : out Status_Code);
procedure Extract_Seven_Zip_Stored_Files
  (Input_Path  : String;
   Output_Dir  : String;
   Entry_Names : Text_Array;
   Status      : out Status_Code);
procedure Extract_Seven_Zip_Files
  (Input_Path  : String;
   Output_Dir  : String;
   Entry_Names : Text_Array;
   Status      : out Status_Code);
```

`Looks_Like_Zlib_Header` and `Looks_Like_GZip_Header` are lightweight wrapper-prefix predicates for callers that need to select an explicit mode before decode. They do not validate payload bytes, trailers, checksums, or member completeness, and they do not change the no-auto-detection inflate contract.

`Inflate` accepts complete zlib streams and supports stored, fixed-Huffman, and
dynamic-Huffman Deflate blocks. It validates the zlib header and Adler-32
footer. It is exactly equivalent to `Inflate_With_Header` with
`Header => Zlib_Header`; it does not auto-detect gzip or raw Deflate input.

`Inflate_With_Header` accepts complete compressed buffers with explicit wrapper
selection: `Default` and `Zlib_Header` mean zlib wrapper plus Adler-32
validation, `GZip` means a gzip member plus CRC32/ISIZE validation, and
`Raw_Deflate` means a raw Deflate payload with no wrapper, trailer, or checksum
validation. Wrong-wrapper inputs return deterministic non-`Ok` statuses.
`Inflate_Raw` is a convenience wrapper for complete raw Deflate payloads and is
exactly equivalent to `Inflate_With_Header (Input, Raw_Deflate, Status)`. It
does not auto-detect zlib or gzip wrappers. `Inflate` remains zlib-wrapper-only,
and `Inflate_With_Header` remains the general explicit wrapper API.

`Deflate_Stored` emits valid zlib streams using stored Deflate blocks
and remains the compatibility/no-compression output path. `Deflate_Fixed` emits
valid zlib streams using fixed-Huffman Deflate. `Deflate_Dynamic` emits valid
zlib streams using dynamic-Huffman Deflate. Dynamic output uses bounded LZ77 matching with conservative lazy matching at the default level and bounded optimal parsing at levels 8 and 9 and does not provide gzip output through the `Deflate_Dynamic` API. Public compression levels map onto bounded matcher effort and strategy. Its compression ratio is not comparable to a default `zlib` compressor. `Deflate` is the policy-based compression entry point. `Stored`, `Fixed`, and
`Dynamic` modes are exact aliases for `Deflate_Stored`, `Deflate_Fixed`, and
`Deflate_Dynamic`. One-shot and streaming `Auto` are block-local: each pending block is scored as Stored, Fixed, and Dynamic, Dynamic header cost is included, and the smallest valid candidate is emitted. Equal scores use the tie-breaker Stored, then Fixed, then Dynamic. If no one-shot mode succeeds, it returns an empty array and a non-`Ok` status. Because `Mode`
has a default before the output status parameter, callers that want default
`Auto` should use named status syntax: `Deflate (Input, Status => Status)`.

`Deflate_File` is a thin file wrapper around `Deflate`: read input file, compress
using `Mode`, then write output file. `GZip` and `GZip_File` produce
deterministic minimal gzip output using the same block modes. The `Deflate_*`
APIs remain zlib-wrapped. Missing input is reported as
`Input_File_Error`; output write failure is reported as `Output_File_Error`;
compression failure preserves the compression `Status_Code`.

`Deflate_Raw` is the explicit raw Deflate compression entry point. `Mode => Stored` emits raw Deflate stored blocks, `Mode => Fixed` emits fixed-Huffman Deflate blocks, `Mode => Dynamic` emits dynamic-Huffman Deflate blocks, and `Mode => Auto` uses the same deterministic block-local Stored/Fixed/Dynamic size-scoring policy as wrapped streaming compression. Raw output has no zlib CMF/FLG header, no Adler-32 footer, no gzip header, no gzip CRC32 trailer, and no gzip ISIZE trailer. `Deflate_Raw_File` provides the same Stored/Fixed/Dynamic/Auto behavior for files. The existing `Deflate_*` APIs remain
zlib-wrapped, and `GZip`/`GZip_File` remain gzip-wrapped.

`ZIP` and `ZIP_File` emit deterministic single-entry ZIP archives with Stored
or Deflate entries. `ZIP_Files` emits deterministic multi-entry ZIP archives
from parallel path/name arrays and can force ZIP64 local, central, and
end-of-central-directory metadata through `Force_ZIP64`. Entry names are safe
relative paths only.

`Seven_Zip_Stored` emits a native `.7z` archive image containing one file stored
with the 7z Copy coder, or a header-only directory entry when metadata marks a
directory. It writes the 7z signature header, packed stream, main-stream
metadata, UTF-16LE file name, and CRC32 fields in process; it does not shell out
to `7z`. The single-entry 7z metadata overloads emit supported
modification FILETIME and raw Windows attributes for file entries.
The file and file-list 7z helpers preserve source modification time and
read-only state when those platform attributes are available. Single-entry file
helpers accept an ordinary file or a directory path; directory paths become
header-only directory entries.
`Seven_Zip_Stored_File` is the file-or-directory helper for the same
single-entry format.
`Seven_Zip_Deflate` emits a native `.7z` archive image containing one file
packed with the 7z Deflate coder and the library raw-Deflate compressor, or a
header-only directory entry when metadata marks a directory; it accepts either
`Compression_Mode` or `Compression_Level`.
`Seven_Zip_Deflate_File` is its file-or-directory helper. `Seven_Zip_LZMA`
emits a native single-entry `.7z` archive using the LZMA coder, and
`Seven_Zip_LZMA_File` is its file-or-directory helper. `Seven_Zip_BZip2` emits
a native single-entry `.7z` archive using the BZip2 coder, and
`Seven_Zip_BZip2_File` is its file-or-directory helper.
`Seven_Zip_LZMA2` emits a native single-entry `.7z` archive using valid LZMA2
chunks, including compressed chunks for payloads that benefit from them, and
`Seven_Zip_LZMA2_File` is its file-or-directory helper. `Seven_Zip_PPMd` and
`Seven_Zip_PPMd_File` write native single-entry `.7z` archives using a
deterministic in-process PPMd stream accepted by this crate's native extractor
for ordinary-file inputs. The writer selects among verified stock-compatible
PPMd candidates, repeated/periodic PPMd forms, and a verified native root context
fallback, or emits a header-only directory entry for directory inputs. The file
helper accepts either the input basename or an
explicit entry name. They self-verify the generated archive with the native
extractor before returning `Ok`. They do not call a local `7z` executable.
Metadata overloads for stored and compressed native 7z writers emit
header-only directory entries when `Metadata.Is_Directory` is true.
`Seven_Zip_Stored_Files` writes a
multi-entry solid Copy-coder archive from parallel `Text_Array` input-path and
distinct entry-name lists. Ordinary files become packed substreams and
directory input paths become no-stream directory entries.
`Seven_Zip_Deflate_Files` writes the same file-list shape with independently
Deflate-packed entries and accepts either `Compression_Mode` or
`Compression_Level`. `Seven_Zip_BZip2_Files` writes the same file-list shape
with independently BZip2-packed entries.
`Seven_Zip_LZMA_Files` writes the same file-list shape with independently
LZMA-coded entries using the library default properties.
`Seven_Zip_LZMA2_Files` writes the same file-list shape with independently
LZMA2-coded entries using valid LZMA2 chunks. `Seven_Zip_PPMd_Files` writes
the same file-list shape with independently packed deterministic PPMd entries
using the same verified candidate selection.
File-list writers preserve supported
per-entry source metadata for files and directories.
`Extract_Seven_Zip_Stored` verifies and extracts one named entry from those
Copy-coder, Deflate, BZip2, LZMA, or LZMA2 layouts as the compatibility name,
and also accepts the native PPMd extraction subset for empty streams with or
without range headers, repeated-symbol, simple root-symbol, periodic-prefix,
stock-7z non-solid multi-block streams with LZMA encoded headers, stock-7z
no-stream empty-file entries, stock-7z BCJ+PPMd filter chains, and BCJ2 graphs
with Copy, PPMd, or supported main pre-coders. The PPMd model table is
allocated from the archive's declared PPMd memory and requested output size
rather than a fixed stream-independent context cap. The supported PPMd decode
mode ladder is used for payloads, encoded headers, BCJ+x86 chains, and BCJ2
graphs. Broader PPMd entries fail closed with a non-Ok status. `Extract_Seven_Zip` is the neutral
extractor name with the same native-only supported method set.
Both names validate start-header CRC, next-header CRC, packed CRC, unpacked CRC,
method, size, and entry name. Native LZMA extraction accepts stored lc/lp/pb and
dictionary metadata for supported property combinations. Native LZMA2
extraction accepts compressed, uncompressed, reset/properties, state-reset, and
state-continuing chunks for supported lc/lp/pb properties in the single-folder
layout. Supported extraction also accepts covered solid substreams, BCJ2 graph
layouts with Copy or supported main pre-coders, and bounded linear
filter-chain layouts made from supported single-input coders and x86 BCJ/Delta
filters, including standard zero-based, reverse-linear, reordered zero-based,
and legacy one-based linear bind pairs.
Archives with duplicate matching entry names are rejected.
Common archive/file metadata fields and SFX prefixes are skipped while
extracting supported payload layouts. Byte-array extraction returns payload
bytes only; file and file-list helpers restore supported per-entry directories,
modification times, and read-only attributes after writing output paths. Broader
non-PPMd 7z archives fail closed with a non-Ok status.
`Extract_Seven_Zip_Metadata` exposes the decoded entry kind, modification
FILETIME, and Windows attribute mask for one selected verified entry.
Native 7z metadata overloads can emit a header-only directory entry when
`Metadata.Is_Directory` is true. Single-entry file helpers create missing
parent directories for their
`Output_Path` before writing file or directory entries.
`Extract_Seven_Zip_Files` is the neutral file-list extractor name;
`Extract_Seven_Zip_Stored_Files` remains as the compatibility name. Both extract
selected entries into an output directory, create needed parent directories,
and require a non-empty destination directory. They prevalidate distinct output
names before writing and reject absolute paths, empty path segments, `.`
segments, `..` segments, backslashes, and drive-style entry names. They verify
all requested payloads before writing any output file. The neutral name returns
`Unsupported_Method` when native extraction cannot handle the requested method.

The native 7z APIs are intentionally not a full 7z compression stack.
General 7z method graph encoding and 7z encryption are not emitted in process;
encrypted 7z payloads are not decoded. `Seven_Zip_PPMd`,
`Seven_Zip_PPMd_File`, and `Seven_Zip_PPMd_Files` emit verified PPMd output
without calling a local `7z` executable; empty PPMd output uses a
range-initialized empty stream, modeled stock-compatible candidates use
generated bytes, repeated and periodic data use specialized verified coding,
and other supported payloads use a verified native root-context
fallback.
Broader unsupported 7z method extraction through the neutral names fails closed
with a non-Ok status.
ZIP method 12 BZip2,
method 14 ZIP-LZMA streams, and method 20/93 Zstandard
creation and unencrypted extraction for classic and ZIP64 metadata are separate
in-process ZIP member-payload paths. The ZIP-LZMA path is an in-tree range
coder/literal coder with normal-match distance coding including pos-special,
direct-bit, align-bit, and rep-match distances emitted by this library.
`Seven_Zip_External_File` and `Extract_Seven_Zip_External_File` are
compatibility placeholders for the former external bridge. They do not invoke
a local `7z` executable; unsupported broader creation, extraction, unsupported
solid layouts, and password-protected archives fail
closed with deterministic status codes.

The one-shot API reports failures through `Status_Code`, not exceptions.
Returned output after a non-`Ok` status must be treated as invalid partial data.

## Streaming API

```ada
type Filter_Type is limited private;
type Header_Type is (Default, Zlib_Header, GZip, Raw_Deflate);
type Flush_Mode is (No_Flush, Sync_Flush, Full_Flush, Finish);

Zlib_Error   : exception;
Status_Error : exception;

procedure Inflate_Init
  (Filter : in out Filter_Type;
   Header : Header_Type := Default);
procedure Inflate_Raw_File_Streaming
  (Input_Path, Output_Path : String;
   Status : out Status_Code);

function Is_Open
  (Filter : Filter_Type)
   return Boolean;

procedure Translate
  (Filter   : in out Filter_Type;
   In_Data  : Ada.Streams.Stream_Element_Array;
   In_Last  : out Ada.Streams.Stream_Element_Offset;
   Out_Data : out Ada.Streams.Stream_Element_Array;
   Out_Last : out Ada.Streams.Stream_Element_Offset;
   Flush    : Flush_Mode := No_Flush);

procedure Flush
  (Filter   : in out Filter_Type;
   Out_Data : out Ada.Streams.Stream_Element_Array;
   Out_Last : out Ada.Streams.Stream_Element_Offset;
   Flush    : Flush_Mode := No_Flush);

function Stream_End
  (Filter : Filter_Type)
   return Boolean;

procedure Close
  (Filter       : in out Filter_Type;
   Ignore_Error : Boolean := False);
```

`Default` is exactly `Zlib_Header`; it never auto-detects gzip or raw streams.
`Zlib_Header` accepts a zlib wrapper, Deflate payload, and Adler-32 trailer.
`GZip` accepts one gzip member and validates CRC32/ISIZE. `Raw_Deflate`
accepts a Deflate payload with no wrapper, no trailer, and no checksum
validation. It is available through both `Inflate_With_Header` for complete
buffers and `Inflate_Init` for streaming input. Plain one-shot `Inflate`
remains zlib-wrapper-only. `Deflate_Stored`, `Deflate_Fixed`,
`Deflate_Dynamic`, and `Deflate` all produce zlib-wrapped output.

`Status_Error` means lifecycle misuse. `Zlib_Error` means malformed,
truncated, unsupported, or validation-failed compressed data. See
`docs/STREAMING.md` and `docs/ERRORS.md` for the complete contract.


## Streaming compression API

The frozen compression-side streaming output contract covers zlib-wrapped and
gzip-wrapped stored Deflate blocks, fixed-Huffman Deflate blocks,
dynamic-Huffman Deflate blocks, and Auto-selected blocks. Supported headers are
`Header => Default`, `Header => Zlib_Header`, and `Header => GZip` with
`Mode => Stored`, `Mode => Fixed`, `Mode => Dynamic`, or `Mode => Auto`.
`Mode => Auto` is deterministic and block-local: each buffered block is scored
as Stored, Fixed, and, for levels 2 through 9, Dynamic before any bytes for that
block are emitted. The smallest valid candidate is emitted, with equal scores
resolved by the Stored, then Fixed, then Dynamic tie-breaker.

The one-shot wrapped and raw Auto APIs are routed through the same bounded
streaming compression engine, so they use the same block-local scoring policy
instead of a whole-stream smallest-output search.

`Deflate_Dynamic` also uses this maintained streaming compression engine for
explicit Dynamic output, so large one-shot Dynamic inputs are emitted as a
bounded dynamic-Huffman block sequence instead of through the older single-block
Dynamic encoder.

```ada
type Compression_Filter_Type is limited private;

procedure Deflate_Init
  (Filter : in out Compression_Filter_Type;
   Header : Header_Type := Zlib_Header;
   Mode   : Compression_Mode := Auto);

function Is_Open
  (Filter : Compression_Filter_Type)
   return Boolean;

procedure Compress
  (Filter   : in out Compression_Filter_Type;
   In_Data  : Ada.Streams.Stream_Element_Array;
   In_Last  : out Ada.Streams.Stream_Element_Offset;
   Out_Data : out Ada.Streams.Stream_Element_Array;
   Out_Last : out Ada.Streams.Stream_Element_Offset;
   Flush    : Flush_Mode := No_Flush);

procedure Compress_Flush
  (Filter   : in out Compression_Filter_Type;
   Out_Data : out Ada.Streams.Stream_Element_Array;
   Out_Last : out Ada.Streams.Stream_Element_Offset;
   Flush    : Flush_Mode := No_Flush);

function Compress_Stream_End
  (Filter : Compression_Filter_Type)
   return Boolean;

procedure Compress_Close
  (Filter       : in out Compression_Filter_Type;
   Ignore_Error : Boolean := False);
```

`Compress` consumes input incrementally. Zlib output emits a zlib header,
Deflate blocks, and a big-endian Adler-32 footer. Gzip output emits the
deterministic minimal gzip header, raw Deflate blocks, and a little-endian
CRC32/ISIZE trailer. Stored mode emits stored blocks. Fixed mode emits
fixed-Huffman blocks with low-effort bounded LZ77 matches. Dynamic mode emits
dynamic-Huffman blocks using default-effort bounded LZ77 matches and per-block
Huffman tables. All supported streaming modes support one-byte output buffers.
`Compress_Flush` drains pending output and finalizes the stream when called with
`Flush => Finish`.

Supported streaming compression combinations are `Header => Default/Zlib_Header/GZip/Raw_Deflate`
with `Mode => Stored/Fixed/Dynamic/Auto`. Raw Deflate emits payload bytes only,
with no wrapper or trailer. Calls before initialization or after
`Compress_Close` raise `Status_Error`. After `Compress_Stream_End = True`,
`Compress_Flush` with `No_Flush` or `Finish` is idempotent and returns no output;
`Compress_Flush` with `Sync_Flush` or `Full_Flush` raises `Status_Error`.
`Compress` with empty input and `No_Flush` or `Finish` is also idempotent, while
`Compress` with additional non-empty input, `Sync_Flush`, or `Full_Flush` raises
`Status_Error`. `Deflate_Init` is always a full reset and may be used to recover
from open, failed, completed, or closed compression state.
`Compress_Stream_End` returns `True` only after the final Deflate block,
active wrapper trailer, and all pending output bytes are fully emitted and
drained. See `docs/STREAMING_COMPRESSION.md` for the complete lifecycle
contract.

## Release boundary notes

Consumers should depend on `with Zlib;` only. The following child packages are
implementation units and may change without a public API bump:

```text
Zlib.Bits
Zlib.Bit_Writer
Zlib.Checksums
Zlib.CRC32_Internal
Zlib.Deflate_Tables
Zlib.Dynamic_Compress
Zlib.Fixed_Compress
Zlib.Huffman
Zlib.Huffman_Builder
Zlib.Raw_Inflate
Zlib.Sliding_Window
Zlib.Stream_Bits
Zlib.Stream_Inflate
Zlib.Wrapper
```

## Wrapper contract

Strict inflate APIs do not perform wrapper auto-detection. `Default` is a
synonym for `Zlib_Header`, not a probing mode. `Inflate` accepts only
zlib-wrapped input and is equivalent to `Inflate_With_Header (Input,
Zlib_Header, Status)`. Use `Inflate_Auto` only when lightweight one-shot wrapper
discrimination is wanted.

Use `Inflate_With_Header` when a caller knows it has gzip or raw Deflate data:

```ada
Decoded := Zlib.Inflate_With_Header (Input, Zlib.GZip, Status);
Decoded := Zlib.Inflate_With_Header (Input, Zlib.Raw_Deflate, Status);
```

The `Deflate_*`, `Deflate`, and matching `Deflate_*_File` APIs produce
zlib-wrapped streams. `GZip` and `GZip_File` produce gzip-wrapped streams. No
one-shot API produces raw Deflate output.

## Streaming compression public API

Streaming compression is exposed only through the root `Zlib` package:

- `Compression_Filter_Type`
- `Deflate_Init`
- `Is_Open`
- `Compress`
- `Compress_Flush`
- `Compress_Stream_End`
- `Compress_Close`

`Deflate_Init` opens or resets a compression filter. It accepts a
`Header_Type` and `Compression_Mode`. Supported zlib/gzip compression wrappers
are `Default`, `Zlib_Header`, and `GZip`. `Default` means exactly
`Zlib_Header`. `Raw_Deflate` supports `Mode => Stored`, `Mode => Fixed`, `Mode => Dynamic`, and `Mode => Auto`.

`Compress` feeds uncompressed input and emits compressed output. `In_Last` is
the last consumed input index. `Out_Last` is the last produced output index.
Callers must continue with any unconsumed input suffix when an output buffer is
small.

`Compress_Flush` drains pending compressed output. `Flush => Finish` emits the
final Deflate block and the active wrapper trailer; raw Deflate has no trailer.
Call it until
`Compress_Stream_End` returns true.

`Compress_Close` closes the filter. It reports incomplete or failed streams via
`Zlib_Error` unless `Ignore_Error => True` is used. Exception cleanup should use
`Ignore_Error => True`.

No internal child package is part of the release contract for streaming
compression consumers.


## Raw dynamic compression note

Raw_Deflate compression now supports `Stored`, `Fixed`, `Dynamic`, and `Auto`. Raw output is Deflate block data only: it has no zlib header, no Adler-32 footer, no gzip header, no CRC32 trailer, and no ISIZE trailer. Raw `Auto` uses the same deterministic block-local policy as zlib/gzip Auto. `Deflate_*` APIs remain zlib-wrapped, and `GZip*` APIs remain gzip-wrapped.

## Raw one-shot bridge

`Deflate_Raw` is the public one-shot raw Deflate compression bridge. It supports `Mode => Stored`, `Mode => Fixed`, `Mode => Dynamic`, and `Mode => Auto` and is internally routed through the same raw streaming compression engine used by `Deflate_Init (Header => Raw_Deflate, Mode => ...)`. Its output is Deflate block data only: no zlib CMF/FLG bytes, no Adler-32 footer, no gzip header, no CRC32 trailer, and no ISIZE trailer. The output is intended only for containers or protocols that provide their own framing and integrity checks.

`Deflate_Raw_File` is intentionally thin: it reads the input file, calls `Deflate_Raw`, and writes the returned bytes only when compression succeeds. Missing inputs report `Input_File_Error`; output failures report `Output_File_Error`; compression failures remain status-based and do not leak streaming exceptions. `Deflate`, `Deflate_Stored`, `Deflate_Fixed`, `Deflate_Dynamic`, and `Deflate_File` remain zlib-wrapped APIs. `GZip` and `GZip_File` remain gzip-wrapped APIs.

`Deflate_Raw_File_Size` runs the selected raw compression mode without writing output and reports the exact byte count that would be emitted. `Deflate_Raw_File_To_Stream` writes raw `Stored`, `Fixed`, `Dynamic`, or `Auto` Deflate into an already-open `Ada.Streams.Stream_IO.File_Type` and reports the number of payload bytes written. `Stored_Raw_Deflate_Size` and `Deflate_Raw_Stored_File_To_Stream` remain compatibility helpers for stored-block container writers. These helpers are intended for container formats such as ZIP that own the surrounding file layout and need raw Deflate payloads after their own headers.

## Raw Deflate public API

Raw Deflate compression is exposed only through the root `Zlib` package:

- `Deflate_Raw (Input, Mode, Status)`
- `Deflate_Raw_File (Input_Path, Output_Path, Mode, Status)`
- `Deflate_Raw_File_Size (Input_Path, Mode, Compressed_Size, Status)`
- `Deflate_Raw_File_To_Stream (Input_Path, Output, Mode, Compressed_Size, Status)`
- `Stored_Raw_Deflate_Size (Uncompressed_Size, Compressed_Size)`
- `Deflate_Raw_Stored_File_To_Stream (Input_Path, Output, Compressed_Size, Status)`
- `Deflate_Init (Filter, Header => Raw_Deflate, Mode => ...)`
- `Inflate_Raw (Input, Status)`
- `Inflate_Raw_File (Input_Path, Output_Path, Status)`
- `Inflate_Raw_File_Streaming (Input_Path, Output_Path, Status)`
- `Inflate_With_Header (Input, Header => Raw_Deflate, Status)`
- `Inflate_Init (Filter, Header => Raw_Deflate)`

`Raw_Deflate` is wrapper-strict. Raw output has no checksum trailer and must not
be passed to zlib or gzip inflate paths. `Default` remains exactly
`Zlib_Header`; strict APIs do not auto-detect wrappers. `Inflate_Auto` is the
explicit convenience API for lightweight wrapper discrimination.


## Raw Deflate release hardening

Raw Deflate compression is release-hardened by `zlib_raw_release_tests`, `zlib_raw_cross_wrapper_conformance_tests`, the raw examples, and the raw tools. Raw Deflate inflate convenience APIs are covered by `zlib_inflate_raw_api_tests`. The contract remains unchanged: `Deflate_*` APIs emit zlib-wrapped streams, `GZip*` APIs emit gzip-wrapped streams, `Deflate_Raw*` APIs emit raw Deflate blocks only, `Inflate_Raw*` APIs consume raw Deflate payloads only, `Seven_Zip_Stored*` APIs emit Copy-coder `.7z` archives including header-only directory entries and solid stored file-list archives with no-stream directory entries, `Seven_Zip_Deflate*` APIs emit Deflate `.7z` archives, `Seven_Zip_BZip2*` APIs emit BZip2 `.7z` archives, `Seven_Zip_LZMA*` APIs emit LZMA `.7z` archives, `Seven_Zip_LZMA2*` APIs emit LZMA2 `.7z` archives with valid compressed or uncompressed chunks, `Extract_Seven_Zip*` APIs extract those supported native 7z layouts including LZMA2 reset/properties, state-reset, state-continuing chunks, native PPMd empty/repeated-symbol/root-symbol/periodic-prefix, stock-7z multi-block streams with LZMA encoded headers, stock-7z no-stream empty-file entries, stock-7z BCJ+PPMd filter chains, and BCJ2 graphs with Copy, PPMd, or supported main pre-coders, `Seven_Zip_PPMd`, `Seven_Zip_PPMd_File`, and `Seven_Zip_PPMd_Files` emit native PPMd 7z archives for this crate's extractor without calling local `7z`, while `Seven_Zip_External_File` and `Extract_Seven_Zip_External_File` are compatibility placeholders that fail closed without invoking local `7z`, ZIP BZip2, ZIP-LZMA streams, and Zstandard creation and unencrypted extraction for classic and ZIP64 metadata are in-process, `ZIP`/`ZIP_File`/`ZIP_Files` emit ZIP archives, `Inflate` is zlib-wrapper-only, `Inflate_With_Header` performs explicit wrapper selection, and `Inflate_Auto` is the convenience wrapper-discriminating inflate API. `Auto` remains deterministic and block-local; the library still has no zlib-compatible compression-ratio promise.

## Gzip metadata API

`GZip_Metadata` is an optional gzip-header metadata object. Use
`No_GZip_Metadata` for deterministic minimal gzip output, or set individual
fields with `Set_Name`, `Set_Comment`, `Set_MTime`, `Set_XFL`, `Set_OS`,
`Set_Extra`, and `Set_Header_CRC`.

`Set_Extra` enables FEXTRA and stores binary extra data exactly. Lengths above
65,535 bytes mark the metadata invalid. `Set_XFL` writes the gzip XFL byte; the
default remains zero. The default OS byte remains 255. FHCRC covers every header
byte emitted before the FHCRC field, including FEXTRA, FNAME, and FCOMMENT.

The existing `GZip` and `GZip_File` overloads are unchanged. New overloads accept
metadata explicitly:

```ada
function GZip
  (Input    : Byte_Array;
   Mode     : Compression_Mode;
   Metadata : GZip_Metadata;
   Status   : out Status_Code)
   return Byte_Array;

procedure GZip_File
  (Input_Path  : String;
   Output_Path : String;
   Mode        : Compression_Mode;
   Metadata    : GZip_Metadata;
   Status      : out Status_Code);

procedure Deflate_Init
  (Filter   : in out Compression_Filter_Type;
   Header   : Header_Type := Zlib_Header;
   Mode     : Compression_Mode := Auto;
   Metadata : GZip_Metadata);
```

Metadata is valid only with `Header => GZip`. For zlib and raw Deflate output,
non-default metadata raises `Status_Error` in the streaming API and maps to a
deterministic non-`Ok` one-shot status.

## Explicit gzip multi-member inflate

The default gzip inflate APIs are strict single-member APIs. The existing
`Inflate_With_Header (Input, GZip, Status)` overload rejects bytes that follow
the first validated gzip member.

Use the explicit overload when concatenated gzip members are intended:

```ada
Decoded := Zlib.Inflate_With_Header
  (Input     => Concatenated_GZip,
   Header    => Zlib.GZip,
   GZip_Mode => Zlib.Multi_Member,
   Status    => Status);
```

Streaming callers use the three-argument `Inflate_Init` overload:

```ada
Zlib.Inflate_Init
  (Filter    => Filter,
   Header    => Zlib.GZip,
   GZip_Mode => Zlib.Multi_Member);
```

Each gzip member is independently validated. `Stream_End` is true only after
`Finish` establishes that the complete logical gzip stream is complete.


## Streaming compression flush modes

`Sync_Flush` forces currently buffered compression input into the Deflate stream without ending it. It finishes the current block as non-final and emits an empty non-final stored block on a byte boundary. `Full_Flush` currently has the same byte-level behavior because the compressor has no cross-block match history; the distinction is preserved in the API and tests. Neither mode emits zlib/gzip trailers, and `Compress_Stream_End` remains `False` until `Finish`. Flush output may require repeated drain calls with small output buffers. `Finish` after a partially drained flush completes the pending flush work and then finalizes the stream. After stream end, `Sync_Flush` and `Full_Flush` are lifecycle misuse and raise `Status_Error`. Streaming inflate treats `Sync_Flush` and `Full_Flush` as `No_Flush`; Deflate flush markers are ordinary stored blocks.

## Compression levels

The public compression-level API is now available alongside the exact mode API:

```ada
type Compression_Level is range 0 .. 9;
Default_Level : constant Compression_Level := 6;
```

`Compression_Level` is a convenience policy, not an exact zlib-compatible tuning contract. Use `Compression_Mode` when a test or consumer requires exact `Stored`, `Fixed`, `Dynamic`, or `Auto` behavior. Use `Compression_Level` when a caller wants a stable broad effort setting.

The level mapping is deterministic and intentionally conservative:

- `Level => 0` maps to `Mode => Stored`.
- `Level => 1` maps to `Mode => Fixed` with low bounded matcher effort.
- `Level => 2 .. 3` maps to `Mode => Auto` with greedy matching.
- `Level => 4 .. 7` maps to `Mode => Auto` with conservative lazy matching.
- `Level => 8 .. 9` maps to `Mode => Auto` with bounded optimal parsing and the highest matcher effort.

Because the compressor has conservative lazy matching and bounded block-local optimal parsing but no whole-stream block scoring, adjacent levels may still produce identical output. No public level may emit invalid output, and no level promises zlib-compatible compression ratios.

Level overloads exist for one-shot zlib, gzip, and raw Deflate compression, file helpers, and streaming `Deflate_Init`. Level selection does not change wrapper semantics: `Deflate` still emits zlib, `GZip` still emits gzip, and `Deflate_Raw` still emits raw Deflate blocks only.

## Preset dictionary APIs

Zlib preset dictionaries are explicit and zlib-wrapper-only. Use
`Deflate_With_Dictionary` or `Deflate_Set_Dictionary` to emit a zlib stream
with the `FDICT` flag and a big-endian `DICTID` equal to
`Adler-32(Dictionary)`. Use `Inflate_With_Dictionary` or
`Inflate_Set_Dictionary` to provide the matching dictionary before Deflate
payload decoding begins.

Dictionaries are not supported for `Header => GZip` or
`Header => Raw_Deflate`; the streaming dictionary setters raise
`Status_Error` for those wrappers. Missing dictionaries report
`Unsupported_Preset_Dictionary`; wrong DICTIDs report `Invalid_Checksum`.

## Streaming file APIs

Bounded-memory file helpers are available for consumers that must process files without buffering the complete input or output in memory:

```ada
Inflate_File_Streaming
Inflate_File_With_Dictionary_Streaming
Deflate_File_Streaming
Deflate_File_With_Dictionary_Streaming
GZip_File_Streaming
Deflate_Raw_File_Streaming
```

The one-shot convenience file APIs remain available. The `*_File_Streaming` APIs open input and output files, process fixed-size internal chunks, preserve binary data including NUL and high-byte values, and close files on both success and failure. They support the same wrapper separation used elsewhere: zlib, gzip, and raw Deflate are selected explicitly where applicable.

Dictionary-aware zlib file streaming is available through `Inflate_File_With_Dictionary_Streaming` and `Deflate_File_With_Dictionary_Streaming`. These helpers are zlib-header-only because gzip and raw Deflate do not use the zlib FDICT wrapper mechanism.


## Public checksum utilities

The root `Zlib` package exposes byte-oriented checksum helpers for consumers that need the same integrity values used by the wrapper formats without depending on internal child packages:

```ada
function Adler32
  (Input : Byte_Array)
   return Interfaces.Unsigned_32;

function CRC32
  (Input : Byte_Array)
   return Interfaces.Unsigned_32;
```

`Adler32` computes the standard Adler-32 value used by zlib stream trailers and zlib preset-dictionary DICTID values. `CRC32` computes the standard gzip CRC-32 value using polynomial `0xEDB88320`, the checksum used by gzip payload trailers and FHCRC calculation. `CRC32_State`, `CRC32_Reset`, `CRC32_Update`, and `CRC32_Value` provide the same CRC-32 calculation incrementally for callers that process files or container payloads in chunks. The checksum APIs operate on bytes: NUL bytes, bytes above `0x7F`, and CR/LF bytes are included exactly, with no text conversion or encoding assumption.

These utilities only compute checksum values. They do not compress data, inflate data, parse wrapper headers, or validate an entire stream by themselves.
