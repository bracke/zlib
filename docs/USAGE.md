# Usage

For a first-use build and roundtrip walkthrough, start with `docs/QUICKSTART.md`.
For API selection by task, use `docs/API_CHEATSHEET.md`. For AI-generated
consumer code or repository changes, use `docs/AI_GUIDE.md`.

`Zlib` exposes one-shot and streaming inflate APIs from the root package only.

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

Use `Header => Default` or `Header => Zlib_Header` for zlib-wrapped streaming
input. `Default` is exactly `Zlib_Header`; it is not auto-detection. Use
`Header => GZip` for single-member gzip streaming input with CRC32 and ISIZE
trailer validation. Use `Header => Raw_Deflate` only for raw Deflate payloads that have no
zlib/gzip wrapper and no trailer checksum. One-shot `Inflate_With_Header`
supports the same explicit wrapper modes for complete in-memory buffers.
Plain one-shot `Inflate` remains zlib-wrapper-only. `Deflate_*` APIs continue
to produce zlib-wrapped output, while `GZip`/`GZip_File` produce gzip-wrapped
output.

Use `docs/STREAMING.md` for the exact lifecycle, `In_Last`/`Out_Last`, finish,
failed-state, and close rules.

## Non-dependencies

`Zlib` is a standalone Ada crate. It has no dependency on `version`, no
dependency on `HttpClient`, and no dependency on a system zlib library.

## Release baseline

See `docs/API.md`, `docs/API_CHEATSHEET.md`, and `docs/CONSTRAINTS.md` for the public API, task mapping, and explicit non-goals.
