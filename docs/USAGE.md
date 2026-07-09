# Usage

For a first-use build and roundtrip walkthrough, start with `docs/QUICKSTART.md`.
For API selection by task, use `docs/API_CHEATSHEET.md`. For AI-generated
consumer code or repository changes, use `docs/AI_GUIDE.md`.

`Zlib` exposes one-shot and streaming inflate APIs from the root package only.

## Reentrancy and parallel callers

Independent calls are reentrant. An external tool may run separate compression,
inflate, archive, or streaming jobs in multiple Ada tasks when each task owns
its input/output buffers, streaming filter object, and output path.

The library does not synchronize shared caller-owned state. Do not use the same
`Filter_Type` or `Compression_Filter_Type` concurrently from multiple tasks
unless the caller protects it. Likewise, avoid concurrent writes to the same
file, extraction directory, or mutable buffer unless that sharing is externally
synchronized.

## One-shot zlib inflate

`Inflate` expects a complete zlib stream:

```text
zlib header | Deflate payload | Adler-32 footer
```

It validates the wrapper, decodes the complete Deflate payload, and compares
the computed Adler-32 of the output with the footer. On success, `Status` is
`Ok`. On failure, `Status` is deterministic and the returned byte array must be
treated as invalid partial output.

## Stored-block zlib output

`Deflate_Stored` writes a valid zlib stream using Deflate stored blocks. This is
intended for correctness and interoperability, not compression ratio.

## Fixed-Huffman zlib output

`Deflate_Fixed` writes a valid zlib stream using one fixed-Huffman Deflate block.
The fixed-Huffman writer uses low-effort bounded LZ77 matching and emits
fixed-Huffman length/distance pairs where profitable. Dynamic Huffman trees
are provided by `Deflate_Dynamic`, and public compression levels are available
through the level-taking `Deflate`, `GZip`, raw Deflate, and streaming
overloads. Levels 8 and 9 use bounded block-local optimal parsing. Consumers
that require the safest compatibility path may continue using `Deflate_Stored`.

## Gzip output

`GZip` writes a deterministic minimal gzip member using stored, fixed-Huffman,
dynamic-Huffman, or `Auto` mode. The default gzip header is fixed and minimal; optional metadata fields are
emitted only through explicit metadata overloads. The trailer contains CRC32 and ISIZE for the uncompressed input.
`Deflate_*` APIs remain zlib-wrapped.

## File helpers

`Inflate_File`, `Deflate_Stored_File`, `Deflate_Fixed_File`,
`Deflate_Dynamic_File`, `Deflate_File`, and `GZip_File` are convenience wrappers.
They map file read errors to `Input_File_Error` and file write errors to
`Output_File_Error`.

## Streaming inflate

Use `Header => Default` for streaming wrapper auto-detection across zlib, gzip,
and raw Deflate input. Use `Header => Zlib_Header` for strict zlib-wrapped
streaming input. Use `Header => GZip` for strict gzip streaming input with
CRC32 and ISIZE trailer validation. Use `Header => Raw_Deflate` only for raw
Deflate payloads that have no zlib/gzip wrapper and no trailer checksum.
One-shot `Inflate` and `Inflate_With_Header` with `Header => Default` use the
same wrapper discrimination for complete zlib, gzip, or raw Deflate buffers.
Gzip input accepts concatenated members by default; concrete one-shot and
streaming headers remain wrapper-strict. `Deflate_*` APIs continue
to produce zlib-wrapped output, while `GZip`/`GZip_File` produce gzip-wrapped
output.

Use `docs/STREAMING.md` for the exact lifecycle, `In_Last`/`Out_Last`, finish,
failed-state, and close rules.

## Non-dependencies

`Zlib` is a standalone Ada crate. It has no dependency on `version`, no
dependency on `HttpClient`, and no dependency on a system zlib library.

## Release baseline

See `docs/API.md`, `docs/API_CHEATSHEET.md`, and `docs/CONSTRAINTS.md` for the
public API, task mapping, and current constraints.
