# Consumer integration guide

This document defines how downstream crates should consume `Zlib` without
coupling to internal child packages.

## Dependency boundary

Consumer code should depend on the root package only:

```ada
with Zlib;
```

Do not use these implementation packages from consumer crates:

```ada
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

Those packages may change as the implementation evolves. The public
surface is `src/zlib.ads`.

## `version`

`version` should use the one-shot status-code API for Git loose-object style
zlib streams:

```ada
Decoded := Zlib.Inflate (Input, Status);
```

Recommended mapping:

- `Ok` -> continue object parsing
- any other `Status_Code` -> object read/write failure with
  `Status_Image (Status)` in diagnostics

`Deflate_Stored` may be used to emit valid zlib streams containing stored
Deflate blocks. This is suitable for correctness-first compatibility output,
not size optimization.

`Deflate_Fixed` may be used when a consumer explicitly wants fixed-Huffman zlib
output without changing existing stored-output behavior. `Deflate (Auto)` may be
used if smaller loose objects are desired and the caller accepts policy-based
mode selection. Tests and fixtures should prefer explicit modes when they need a
known Deflate block type. The simple compressors are intentionally not
comparable to a default `zlib` compressor. `version` should continue using
`Deflate_Stored` unless it deliberately opts into another mode later. Git loose
objects are zlib-wrapped, so `version` should not use `Raw_Deflate`.

`Zlib` does not construct Git object headers, parse Git object types, compute
Git object hashes, update refs, write packfiles, or manage repository state.
Those concerns remain in `version`.

## `HttpClient`

`HttpClient` should use the streaming API for response bodies. Do not call
one-shot `Inflate` for streaming HTTP payloads.

Recommended wrapper mapping:

```text
Content-Encoding: gzip    -> Header => GZip
Content-Encoding: deflate -> Header => Zlib_Header or Default
```

Recommended error mapping:

- `Zlib_Error` -> `Decompression_Failed`
- `Status_Error` -> `Decompression_Failed` or an internal adapter invariant
  failure, depending on the adapter's diagnostic model

The adapter should call `Inflate_Init` once per compressed body, feed body
chunks through `Translate`, use caller-owned output buffers, finish with
`Flush => Finish` at end of body, check `Stream_End`, and always call `Close`
for cleanup. `Close (Ignore_Error => True)` is appropriate during exception
cleanup.

The streaming API validates zlib Adler-32 trailers and gzip CRC32/ISIZE
trailers before `Stream_End` becomes `True`. `Raw_Deflate` is available for
low-level container/protocol adapters that already know the payload is raw
Deflate. Do not use it as an implicit fallback for HTTP `deflate`; introduce a
separate compatibility policy if such fallback is ever desired.

## Future Ada tools

Future tools should choose the API according to data shape:

- complete in-memory zlib stream: use `Inflate` or `Inflate_With_Header` with
  `Header => Zlib_Header`
- complete in-memory gzip member: use `Inflate_With_Header` with
  `Header => GZip`
- complete in-memory raw Deflate payload: use `Inflate_Raw`, or use
  `Inflate_With_Header` with `Header => Raw_Deflate` when the caller is already
  using the general explicit wrapper API
- file-to-file zlib stream: use `Inflate_File`
- incremental network/file inflate pipeline: use the streaming inflate API
- valid but uncompressed zlib output: use `Deflate_Stored` or
  `Deflate_Stored_File`
- valid fixed-Huffman zlib output: use `Deflate_Fixed` or
  `Deflate_Fixed_File`
- valid dynamic-Huffman zlib output: use `Deflate_Dynamic` or
  `Deflate_Dynamic_File`
- policy-based valid zlib output: use `Deflate`, `Deflate (Auto)`, or
  `Deflate_File` with default/explicit `Auto` mode
- raw Deflate stored-block, fixed-Huffman, dynamic-Huffman, or Auto compression output: use `Deflate_Raw` or
  `Deflate_Raw_File` with `Mode => Stored`, `Mode => Fixed`, `Mode => Dynamic`, or `Mode => Auto` only when a container/protocol
  explicitly supplies its own wrapper and checksum
- file-to-file raw Deflate payload: use `Inflate_Raw_File`, or
  `Inflate_Raw_File_Streaming` when bounded-memory streaming is required
- incremental known raw Deflate payload: use streaming
  `Inflate_Init (Header => Raw_Deflate)`

The crate intentionally does not provide general solid-archive or
general-purpose 7z support or default-zlib-equivalent ratio promises. File-list
creation emits ordinary-file payloads plus no-stream directory entries, stored
file payloads use solid Copy, and native PPMd output is available for
single-entry and file-list archives consumed by this crate's native extractor
without calling local `7z`, using verified modeled stock-compatible candidates,
repeated/periodic forms, and a native root-context fallback.
Unsupported PPMd 7z streams fail closed with a non-Ok status. Streaming zlib
and gzip compression are supported for stored-block,
fixed-Huffman,
dynamic-Huffman, and deterministic block-local `Auto` through `Deflate_Init`,
`Compress`, `Compress_Flush`, `Compress_Stream_End`, and `Compress_Close`.


## Dynamic compression consumers

Consumers that explicitly want dynamic-Huffman zlib output may call
`Deflate_Dynamic` or `Deflate_Dynamic_File`. Existing consumers should not be
switched from `Deflate_Stored` or `Deflate_Fixed` implicitly; each compression
mode remains an explicit caller choice. `Auto` is also explicit: callers opt into
it by using `Deflate`, `Deflate (Auto)`, or `Deflate_File` in Auto mode.

## Wrapper selection rule

No consumer-facing API auto-detects wrappers. `Default` means `Zlib_Header`.
`Inflate` is zlib-wrapper-only. `Inflate_Raw` is a convenience wrapper for
complete raw Deflate payloads and does not auto-detect zlib or gzip wrappers.
`Inflate_With_Header` is the public general one-shot entry point for explicit
zlib, gzip, or raw Deflate buffers. `Raw_Deflate` has no checksum validation;
`GZip` validates CRC32 and ISIZE; `Zlib_Header` validates Adler-32.

## Consumer fixtures

The release suite includes consumer-shaped regression tests without importing
consumer crates.

For `version`, fixtures include `blob 0<NUL>`, `blob 12<NUL>hello world<LF>`, a
tree-like binary payload with NUL separators, and commit-like text. Zlib treats
all of these as opaque bytes and does not parse Git object headers.

For `HttpClient`, fixtures include gzip binary bodies, deflate/zlib binary
bodies, chunked-like split simulations, truncated responses, and checksum
failures. Truncated or checksum-invalid compressed responses map to
`Zlib_Error` in the streaming API.

## Streaming compression consumer guidance

### version

For Git loose objects, use `Deflate` or an explicit `Deflate_Stored`,
`Deflate_Fixed`, or `Deflate_Dynamic` operation. The output is zlib-wrapped and
is the correct wrapper family for Git loose objects.

Do not use `GZip` for Git objects. Do not use `Raw_Deflate` for Git loose
objects.

### HttpClient

For response decompression:

- HTTP `gzip` content coding: use streaming `Inflate_Init (Header => GZip)`.
- HTTP `deflate` content coding: use streaming `Inflate_Init (Header => Zlib_Header)`.

For request compression, if needed later:

- gzip request body: use streaming `Deflate_Init (Header => GZip)`.
- deflate request body: use streaming `Deflate_Init (Header => Zlib_Header)`.

Prefer selecting the wrapper from protocol metadata. Use `Inflate_Auto` only
when a one-shot convenience decoder should discriminate zlib, gzip, and raw
Deflate payloads from lightweight prefixes.


## Raw Deflate compression guidance

Raw Deflate compression is explicit. It is not produced by `Deflate_Stored`,
`Deflate_Fixed`, `Deflate_Dynamic`, `Deflate`, or `Deflate_File`; those remain
zlib-wrapped. It is not produced by `GZip` or `GZip_File`; those remain
gzip-wrapped. Raw compression supports `Deflate_Raw` and `Deflate_Raw_File` for
`Mode => Stored`, `Mode => Fixed`, `Mode => Dynamic`, and `Mode => Auto`; raw Auto uses
the same deterministic block-local policy as zlib/gzip Auto. Do not use raw Deflate compression unless the target
format explicitly provides its own wrapper/checksum, such as a container format
that stores raw Deflate payloads internally.


## Raw dynamic compression note

Raw_Deflate compression now supports `Stored`, `Fixed`, `Dynamic`, and `Auto`. Raw output is Deflate block data only: it has no zlib header, no Adler-32 footer, no gzip header, no CRC32 trailer, and no ISIZE trailer. Raw `Auto` uses the same deterministic block-local policy as zlib/gzip Auto. `Deflate_*` APIs remain zlib-wrapped, and `GZip*` APIs remain gzip-wrapped.

## Raw Deflate producer guidance

Use `Deflate_Raw` or `Deflate_Raw_File` only when the receiving format already defines its own framing and integrity metadata. Raw Deflate carries no zlib CMF/FLG header, no Adler-32 checksum, no gzip header, no CRC32, and no ISIZE. Consumers that need standalone compressed files should prefer `Deflate`/`Deflate_File` for zlib streams or `GZip`/`GZip_File` for gzip members.

## Wrapper selection guidance

Do not infer wrapper type from payload bytes or from compression mode. Select the
API that matches the protocol or container boundary:

- use `Deflate_*` or `Deflate` for zlib-wrapped output with Adler-32 validation;
- use `GZip` for gzip output with CRC32/ISIZE validation;
- use `Deflate_Raw` only when an outer format supplies its own framing and
  integrity checks.

Inflate paths are equally explicit. `Inflate` is zlib-only. `Inflate_Raw` is
raw-only. `Inflate_With_Header (..., GZip)` is gzip-only.
`Inflate_With_Header (..., Raw_Deflate)` is raw-only.
Wrong-wrapper inputs are expected to fail deterministically rather than being
silently auto-detected.


## Consumer notes

### Git / version

Git loose objects use zlib-wrapped Deflate. They do **not** use raw Deflate. For
Git loose-object output, use `Deflate`, `Deflate_Stored`, `Deflate_Fixed`, or
`Deflate_Dynamic`; do not use `Deflate_Raw`.

### HTTP / HttpClient

HTTP `deflate` content encoding in this crate expects zlib-wrapped Deflate. Use
`Inflate_Init (Header => Zlib_Header)`, not `Inflate_Init (Header =>
Raw_Deflate)`, unless an external protocol explicitly specifies a raw Deflate
payload. HTTP `gzip` remains `Header => GZip`.

### ZIP-like containers

ZIP-like containers often embed raw Deflate internally. `Zlib` supplies raw
Deflate payload support and ZIP creation helpers through `ZIP`, `ZIP_File`, and
`ZIP_Files`; broader archive policy, per-entry metadata beyond deterministic
timestamps, and extraction remain the responsibility of a ZIP-focused layer.


## Raw Deflate release hardening

Raw Deflate compression is release-hardened by `zlib_raw_release_tests`, `zlib_raw_cross_wrapper_conformance_tests`, the raw examples, and the raw tools. Raw Deflate inflate convenience APIs are covered by `zlib_inflate_raw_api_tests`. The contract remains unchanged: `Deflate_*` APIs emit zlib-wrapped streams, `GZip*` APIs emit gzip-wrapped streams, `Deflate_Raw*` APIs emit raw Deflate blocks only, `Inflate_Raw*` APIs consume raw Deflate payloads only, `Seven_Zip_Stored*` APIs emit Copy-coder `.7z` archives including header-only directory entries and solid stored file-list archives with no-stream directory entries, `Seven_Zip_Deflate*` APIs emit Deflate `.7z` archives, `Seven_Zip_BZip2*` APIs emit BZip2 `.7z` archives, `Seven_Zip_LZMA*` APIs emit LZMA `.7z` archives, `Seven_Zip_LZMA2*` APIs emit LZMA2 `.7z` archives, `Extract_Seven_Zip*` APIs extract those supported native 7z layouts plus native PPMd empty/repeated-symbol/root-symbol/periodic-prefix, stock-7z multi-block streams with LZMA encoded headers, stock-7z no-stream empty-file entries, stock-7z BCJ+PPMd filter chains, and BCJ2 graphs with Copy, PPMd, or supported main pre-coders, `Seven_Zip_PPMd`, `Seven_Zip_PPMd_File`, and `Seven_Zip_PPMd_Files` emit native PPMd 7z archives for this crate's extractor without calling local `7z`, while `Seven_Zip_External_File` and `Extract_Seven_Zip_External_File` are compatibility placeholders that fail closed without invoking local `7z`, `ZIP`/`ZIP_File`/`ZIP_Files` emit ZIP archives, `Inflate` is zlib-wrapper-only, `Inflate_With_Header` performs explicit wrapper selection, and `Inflate_Auto` is the convenience wrapper-discriminating inflate API. `Auto` remains deterministic and block-local; the library still has no general-purpose 7z codec stack or zlib-compatible compression-ratio promise.

## Gzip member policy for consumers

HTTP and protocol consumers should normally use the default single-member gzip
inflate behavior. Multi-member gzip is intended for gzip file semantics,
`gzip -cat` style tools, archives, and inputs that are explicitly documented as
concatenated gzip members.

## Choosing mode or level

Consumers now have two compression control surfaces:

- `Compression_Mode` for exact behavior: `Stored`, `Fixed`, `Dynamic`, or `Auto`.
- `Compression_Level` for broad effort policy: `0 .. 9`, with `Default_Level = 6`.

Use `Compression_Mode` in tests, fixtures, archive formats, and protocols that require a specific Deflate block strategy. Use `Compression_Level` in CLI tools or user-facing settings where callers expect a conventional level value. In the current implementation, level `0` maps to stored output, level `1` maps to low-effort fixed-Huffman output, levels `2 .. 3` map to greedy `Auto`, and levels `4 .. 7` map to conservative lazy `Auto`, and levels `8 .. 9` map to bounded-optimal `Auto`. Adjacent levels may still be byte-identical because the compressor remains conservative and block-local.

## Consumers using zlib preset dictionaries

Preset dictionaries are an interoperability feature for protocols that already
specify a shared dictionary. Consumers must pass the dictionary explicitly on
both compression and inflate. Do not enable dictionary APIs for gzip, raw
Deflate, ZIP, or wrapper autodetection flows.

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

## Direct checksum use

Use `Zlib.Adler32` when a consumer needs the zlib Adler-32 value directly, such as for comparing a zlib trailer or computing a preset-dictionary DICTID. Use `Zlib.CRC32` when a consumer needs the gzip CRC32 value directly, such as for external gzip metadata checks or container-level compatibility tests. Both functions are available through `with Zlib;` only; consumers should not depend on internal checksum child packages.

The checksum helpers operate on bytes, not text. They include NUL bytes, bytes greater than `0x7F`, and CR/LF exactly. They do not compress, inflate, parse, or validate whole streams.

## Wrapper prefix helpers

Use `Looks_Like_Zlib_Header` and `Looks_Like_GZip_Header` only as lightweight prefix checks before selecting an explicit wrapper mode. They are not complete validators; `Inflate_Auto` uses this kind of lightweight discrimination for one-shot convenience, while `Inflate` and streaming decode APIs remain strict.
