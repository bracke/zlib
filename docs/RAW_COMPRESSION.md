# Raw compression

Raw compression is the public compression matrix for `Header => Raw_Deflate`.
It emits Deflate payload bytes only.

| Header | Mode | Output |
| --- | --- | --- |
| `Raw_Deflate` | `Stored` | raw stored Deflate blocks |
| `Raw_Deflate` | `Fixed` | raw fixed-Huffman Deflate blocks |
| `Raw_Deflate` | `Dynamic` | raw dynamic-Huffman Deflate blocks |
| `Raw_Deflate` | `Auto` | deterministic block-local policy |

## Public APIs

Use one-shot APIs when the complete payload is already available:

```ada
Raw := Zlib.Deflate_Raw (Input, Zlib.Auto, Status);
Zlib.Deflate_Raw_File (Input_Path, Output_Path, Zlib.Auto, Status);
```

Use streaming APIs when input or output is incremental:

```ada
Zlib.Deflate_Init (Filter, Header => Zlib.Raw_Deflate, Mode => Zlib.Auto);
```

## Auto policy

Raw `Auto` uses the same deterministic block-local policy as streaming zlib and
gzip compression: emit a dynamic-Huffman block when valid, otherwise fall back to
fixed-Huffman, then stored. It follows the public compression-level policy where level overloads are used,
but does not expose lazy matching, optimal parsing, or whole-stream tuning.

## Wrapper absence

Raw output contains no wrapper bytes:

- no zlib CMF/FLG header;
- no zlib Adler-32 footer;
- no gzip header;
- no gzip CRC32 trailer;
- no gzip ISIZE trailer.

`Deflate_Raw` output is not accepted by zlib or gzip inflate. Use
`Inflate_With_Header (..., Header => Raw_Deflate)` or streaming
`Inflate_Init (Header => Raw_Deflate)` for raw payloads.

## Determinism

For the same API, header, mode, input, chunking, and output buffer sizes, raw
compression output is byte-for-byte deterministic. One-shot and streaming output
may use different block boundaries; each path remains deterministic within its
own contract.

## Tiny-buffer safety

The streaming raw compressor is required to work with small caller-owned output
buffers. Callers must preserve all emitted bytes and retry when no input is
consumed because the output buffer filled.

## Streaming lifecycle

The raw compression lifecycle is the same as wrapped compression:

1. call `Deflate_Init`;
2. call `Compress` until all input is accepted;
3. call `Compress_Flush (..., Finish)` until `Compress_Stream_End` is true;
4. call `Compress_Close`.

`Compress_Stream_End` means the final Deflate block has been fully emitted and
drained to caller output. For raw Deflate there is no wrapper trailer to emit,
but the end condition is still stronger than merely requesting `Finish`.

## Non-goals

Raw compression itself does not add container metadata, gzip metadata, wrapper
guessing, or new algorithms. Optional gzip metadata belongs only to gzip output
APIs and is rejected for raw Deflate; ZIP output and wrapper-discriminating
inflate are provided by their explicit root-package APIs.


## Raw Deflate release hardening

Raw Deflate compression is release-hardened by `zlib_raw_release_tests`, `zlib_raw_cross_wrapper_conformance_tests`, the raw examples, and the raw tools. The contract remains unchanged: `Deflate_*` APIs emit zlib-wrapped streams, `GZip*` APIs emit gzip-wrapped streams, `Deflate_Raw*` APIs emit raw Deflate blocks only, `Seven_Zip_Stored*` APIs emit Copy-coder `.7z` archives including header-only directory entries and solid stored file-list archives with no-stream directory entries, `Seven_Zip_Deflate*` APIs emit Deflate `.7z` archives, `Seven_Zip_BZip2*` APIs emit BZip2 `.7z` archives, `Seven_Zip_LZMA*` APIs emit LZMA `.7z` archives, `Seven_Zip_LZMA2*` APIs emit LZMA2 `.7z` archives, `Extract_Seven_Zip*` APIs extract those supported native 7z layouts plus native PPMd empty/repeated-symbol/root-symbol/periodic-prefix, stock-7z multi-block streams with LZMA encoded headers, stock-7z no-stream empty-file entries, stock-7z BCJ+PPMd filter chains, and BCJ2 graphs with Copy, PPMd, or supported main pre-coders, `Seven_Zip_PPMd`, `Seven_Zip_PPMd_File`, and `Seven_Zip_PPMd_Files` emit native PPMd 7z archives for this crate's extractor without calling local `7z`, while `Seven_Zip_External_File` and `Extract_Seven_Zip_External_File` are compatibility placeholders that fail closed without invoking local `7z`, `ZIP`/`ZIP_File`/`ZIP_Files` emit ZIP archives, `Inflate` is zlib-wrapper-only, `Inflate_With_Header` performs explicit wrapper selection, and `Inflate_Auto` is the convenience wrapper-discriminating inflate API. `Auto` remains deterministic and block-local; the library still has no general-purpose 7z codec stack or zlib-compatible compression-ratio promise.
