# API cheatsheet

This page maps common caller intent to the public `Zlib` declarations. It is a
compact complement to `src/zlib.ads`; the spec remains the exact source of
truth.

## Import

```ada
with Zlib;
```

Do not import child packages from consumer code.

## Parallel callers

Independent jobs are reentrant: use separate buffers, streaming filter objects,
and output paths per Ada task. Shared `Filter_Type`, `Compression_Filter_Type`,
mutable buffers, or overlapping filesystem destinations need caller-side
synchronization.

## Core data and result types

| Need | Declaration |
| --- | --- |
| Byte buffer | `type Byte_Array is array (Natural range <>) of Byte` |
| One-shot result | `type Status_Code` |
| Human-readable status | `Status_Image (Status)` |
| zlib/gzip prefix sniffing | `Looks_Like_Zlib_Header`, `Looks_Like_GZip_Header` |
| Explicit wrapper | `type Header_Type is (Default, Zlib_Header, GZip, Raw_Deflate)` |
| Compression strategy | `type Compression_Mode is (Stored, Fixed, Dynamic, Auto)` |
| Broad compression effort | `type Compression_Level is range 0 .. 9` |

## One-shot inflate

| Input format | API |
| --- | --- |
| zlib/gzip/raw Deflate with one-shot auto-detection | `Inflate (Input, Status)` |
| default auto-detect or explicit zlib/gzip/raw wrapper | `Inflate_With_Header (Input, Header, Status)` |
| explicit gzip single or multi-member | `Inflate_With_Header (Input, Header => GZip, GZip_Mode => ..., Status => Status)` |
| raw Deflate payload | `Inflate_Raw (Input, Status)` |
| zlib stream requiring preset dictionary | `Inflate_With_Dictionary (Input, Dictionary, Status)` |

`Inflate`, `Inflate_With_Header` with `Header => Default`, and streaming
`Inflate_Init` with `Header => Default` auto-detect zlib, gzip, or raw Deflate
input. Gzip input accepts concatenated members by default; concrete headers
remain wrapper-strict.

## One-shot compression

| Desired output | API |
| --- | --- |
| zlib stored blocks | `Deflate_Stored (Input, Status)` |
| zlib fixed-Huffman blocks | `Deflate_Fixed (Input, Status)` |
| zlib dynamic-Huffman blocks | `Deflate_Dynamic (Input, Status)` |
| zlib policy-selected output | `Deflate (Input, Mode => Auto, Status => Status)` |
| zlib broad compression level | `Deflate (Input, Level => Default_Level, Status => Status)` |
| zlib preset dictionary | `Deflate_With_Dictionary (Input, Dictionary, Mode, Status)` |
| gzip output | `GZip (Input, Mode => Auto, Status => Status)` |
| gzip output with metadata | `GZip (Input, Mode, Metadata, Status)` |
| raw Deflate payload | `Deflate_Raw (Input, Mode => Auto, Status => Status)` |

## 7z helpers

| Desired operation | API |
| --- | --- |
| native single-entry Copy-coder 7z output | `Seven_Zip_Stored (Input, Entry_Name, Status)` |
| native Copy-coder 7z output with metadata | `Seven_Zip_Stored (Input, Entry_Name, Metadata, Status)` |
| native header-only 7z directory entry | `Seven_Zip_Stored` metadata overload with `Metadata.Is_Directory = True` |
| Deflate/BZip2/LZMA/LZMA2/PPMd 7z output | `Seven_Zip_Deflate`, `Seven_Zip_BZip2`, `Seven_Zip_LZMA`, `Seven_Zip_LZMA2`, `Seven_Zip_PPMd` |
| compressed filtered 7z output | `Seven_Zip_Filtered (Input, Entry_Name, Filter, Codec, Status)` |
| explicit 7z method graph container output | `Seven_Zip_Method_Graph (Packed_Data, Entry_Name, Coders, Bind_Pairs, Packed_Streams, Pack_Sizes, Unpack_Sizes, Unpacked_CRC, Metadata, Status)` |
| compressed 7z output with metadata | `Seven_Zip_Deflate`, `Seven_Zip_BZip2`, `Seven_Zip_LZMA`, `Seven_Zip_LZMA2`, `Seven_Zip_PPMd` metadata overloads |
| extract supported native 7z layouts | `Extract_Seven_Zip_Stored`, `Extract_Seven_Zip` |
| inspect supported 7z entry metadata | `Extract_Seven_Zip_Metadata` |
| file helper 7z output/extraction | `Seven_Zip_*_File`, `Extract_Seven_Zip_*_File`; dirs are header-only |
| file-list 7z output/extraction | `Seven_Zip_*_Files`, `Extract_Seven_Zip_*_Files`; dirs are no-stream |

Native 7z extraction covers the library Copy/Deflate/BZip2/LZMA/LZMA2 layouts,
selected solid/filter-chain layouts including standard zero-based,
reverse-linear, reordered zero-based, and legacy one-based linear bind pairs
and BCJ2 graphs with Copy or supported main pre-coders, and supported PPMd
mode-ladder streams including empty streams with range headers, stock-7z
no-stream empty-file entries, BCJ+PPMd filter chains, and BCJ2 graphs with
Copy, PPMd, or supported main pre-coders.
The PPMd model table is sized from declared PPMd memory and requested output
size. `Seven_Zip_Filtered` emits non-encrypted compressed filtered archives
such as BCJ+LZMA and Delta+Deflate, including the RISC-V 7z 24.x compact
branch-filter method ID. `Seven_Zip_Method_Graph` emits arbitrary
supported non-encrypted 7z method graph containers from caller-supplied packed
streams using zero-based 7z bind-pair and packed-stream indices.
`Seven_Zip_PPMd` and `Seven_Zip_PPMd_Files` emit verified PPMd streams
without calling local `7z`; candidate selection includes stock-compatible
modeled candidates, repeated/periodic forms, and a native root-context
fallback. File and file-list helpers create needed parent directories and
restore supported directories,
modification times, and read-only attributes.
Neutral 7z extraction
fails closed for broader unsupported methods. It is not a general-purpose 7z
codec.

## Gzip metadata

Start with `No_GZip_Metadata`, then call setters before compression:

```ada
Metadata : Zlib.GZip_Metadata := Zlib.No_GZip_Metadata;

Zlib.Set_Name (Metadata, "payload.bin");
Zlib.Set_Comment (Metadata, "created by application");
Zlib.Set_MTime (Metadata, 0);
Zlib.Set_OS (Metadata, 255);
Zlib.Set_XFL (Metadata, 0);
Zlib.Set_Extra (Metadata, Extra_Bytes);
Zlib.Set_Header_CRC (Metadata, True);
```

Metadata affects gzip headers only. It does not apply to zlib or raw Deflate
output.

## File helpers

| Desired operation | API |
| --- | --- |
| inflate zlib file | `Inflate_File` |
| inflate raw file | `Inflate_Raw_File` |
| deflate zlib file by mode or level | `Deflate_File` |
| deflate gzip file by mode or level | `GZip_File` |
| deflate raw file by mode or level | `Deflate_Raw_File` |
| streaming inflate file | `Inflate_File_Streaming` |
| streaming dictionary file | `Inflate_File_With_Dictionary_Streaming`, `Deflate_File_With_Dictionary_Streaming` |
| streaming inflate raw file | `Inflate_Raw_File_Streaming` |
| streaming zlib/gzip/raw file compression | `Deflate_File_Streaming` |
| streaming gzip file compression | `GZip_File_Streaming` |
| streaming raw file compression | `Deflate_Raw_File_Streaming` |

File helpers report file failures through `Input_File_Error` and
`Output_File_Error`.

## Streaming inflate lifecycle

Use this order:

1. Declare `Filter : Zlib.Filter_Type;`.
2. Call `Inflate_Init (Filter, Header => ...)`.
3. Feed bytes with `Translate`.
4. Drain/check finish with `Flush (..., Flush => Finish)` when input ends.
5. Check `Stream_End (Filter)`.
6. Call `Close (Filter)`.

`Inflate_Init (Filter, Header => Default)` auto-detects zlib, gzip, or raw
Deflate input. Concrete headers remain wrapper-strict. Detected gzip input uses
multi-member mode unless `GZip_Mode => Single_Member` is passed.

For dictionary streams, call `Inflate_Set_Dictionary` only after the stream asks
for a preset dictionary through the documented failure/status path.

## Streaming compression lifecycle

Use this order:

1. Declare `Filter : Zlib.Compression_Filter_Type;`.
2. Call `Deflate_Init (Filter, Header => ..., Mode => ...)` or the level
   overload.
3. Optionally call `Deflate_Set_Dictionary` before compression data starts.
4. Feed bytes with `Compress`.
5. Finish with `Compress_Flush (..., Flush => Finish)`.
6. Check `Compress_Stream_End (Filter)`.
7. Call `Compress_Close (Filter)`.

`Header => Raw_Deflate` emits Deflate blocks only. `Header => GZip` emits gzip
wrapper/trailer bytes. `Header => Zlib_Header` emits zlib wrapper/trailer bytes.

## Checksums

| Need | API |
| --- | --- |
| zlib Adler-32 | internal wrapper validation via `CryptoLib.Checksums` |
| gzip/ZIP/7z CRC32 | internal wrapper/archive validation via `CryptoLib.Checksums` |
| direct Adler-32 or CRC32 | use `CryptoLib.Checksums` |
| conservative zlib output bound | `Deflate_Bound (Input_Length)` |
| conservative gzip output bound | `GZip_Bound (Input_Length)` |
| conservative raw Deflate output bound | `Deflate_Raw_Bound (Input_Length)` |

## Wrapper matrix

| API family | Emits/accepts zlib | Emits/accepts gzip | Emits/accepts raw Deflate |
| --- | --- | --- | --- |
| `Inflate` | yes | no | no |
| `Inflate_With_Header` | explicit | explicit | explicit |
| `Inflate_Raw` | no | no | yes |
| `Deflate_*`, `Deflate` | yes | no | no |
| `GZip` | no | yes | no |
| `Deflate_Raw` | no | no | yes |
| streaming inflate/compression | selected by `Header_Type` | selected by `Header_Type` | selected by `Header_Type` |
