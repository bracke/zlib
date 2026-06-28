# AI integration guide

Development version 0.1.0-dev.

This document is for AI coding assistants and other automated consumers that need
to understand this crate quickly and make safe changes without importing internal
implementation details.

## Stable public entry point

The consumer contract is the root package only:

```ada
with Zlib;
```

Use `src/zlib.ads` as the source of truth for public declarations. Do not import
child packages from application code unless the task is explicitly to maintain
this crate internally.

Internal packages include, but are not limited to:

```text
Zlib.Bit_Writer
Zlib.Bits
Zlib.Block_Chooser
Zlib.Checksums
Zlib.CRC32_Internal
Zlib.Deflate_Tables
Zlib.Dynamic_Compress
Zlib.Fixed_Compress
Zlib.Fuzzing
Zlib.Huffman
Zlib.Huffman_Builder
Zlib.LZ77_Matcher
Zlib.Raw_Inflate
Zlib.Sliding_Window
Zlib.Stream_Bits
Zlib.Stream_Inflate
Zlib.Wrapper
```

`Zlib.Fuzzing` is intentionally available to repository fuzz tools and tests,
not to normal consumers.

## First files to read

Read these files in this order for most tasks:

1. `README.md` — current capability summary and release contract.
2. `docs/QUICKSTART.md` — shortest build and usage path.
3. `docs/API_CHEATSHEET.md` — task-to-API mapping for one-shot, file, and streaming use.
4. `src/zlib.ads` — exact public declarations and GNATdoc comments.
5. `examples/README.md` — complete executable example list.
6. `docs/TESTING.md` — validation checklist.

For wrapper-specific tasks, also read:

- `docs/GZIP.md` and `docs/GZIP_OUTPUT.md` for gzip behavior.
- `docs/RAW_DEFLATE.md` and `docs/RAW_COMPRESSION.md` for raw Deflate.
- `docs/STREAMING.md` for streaming inflate.
- `docs/STREAMING_COMPRESSION.md` for streaming compression.
- `docs/FUZZING.md` for deterministic fuzz drivers and seeds.

## Do not infer wrappers

Wrapper choice is explicit and strict:

| Data shape | Correct public API |
| --- | --- |
| zlib stream in memory | `Zlib.Inflate` |
| gzip member in memory | `Zlib.Inflate_With_Header (..., Header => Zlib.GZip, ...)` |
| raw Deflate payload in memory | `Zlib.Inflate_Raw` |
| zlib output in memory | `Zlib.Deflate` or explicit `Deflate_Stored`/`Deflate_Fixed`/`Deflate_Dynamic` |
| gzip output in memory | `Zlib.GZip` |
| raw Deflate output in memory | `Zlib.Deflate_Raw` |
| bounded-memory zlib/gzip/raw input | `Inflate_Init` + `Translate` + `Flush` + `Close` |
| bounded-memory zlib/gzip/raw output | `Deflate_Init` + `Compress` + `Compress_Flush` + `Compress_Close` |

`Default` means exactly `Zlib_Header`; it is not auto-detection. Do not add
fallbacks that try zlib, then gzip, then raw unless a future public feature
explicitly changes the contract.

## Status and exception model

One-shot and file helpers use `Status_Code`:

```ada
Status : Zlib.Status_Code;
Output : constant Zlib.Byte_Array := Zlib.Deflate (Input, Status => Status);

if Status /= Zlib.Ok then
   --  Treat Output as invalid partial data or empty data.
end if;
```

Streaming APIs use exceptions:

- `Zlib.Zlib_Error` for malformed, truncated, unsupported, checksum-invalid, or
  incomplete compressed data.
- `Zlib.Status_Error` for lifecycle misuse.

Always close streaming filters. During exception cleanup, use
`Ignore_Error => True` only to suppress cleanup-time errors after the primary
failure has already been recorded.

## Common AI mistakes to avoid

- Do not use `Zlib.Wrapper`, `Zlib.Raw_Inflate`, or other child packages in
  examples or consumer-facing code.
- Do not call `Inflate` for gzip or raw Deflate input.
- Do not call `Deflate_Raw` for standalone `.z` files or Git loose objects.
- Do not assume raw Deflate has checksum validation.
- Do not expand ZIP support beyond the explicit `ZIP`, `ZIP_File`, and
  `ZIP_Files` writer contract without updating the public contract and release
  tests.
- Do not compare compression ratios with system zlib as a correctness criterion.
- Do not silently ignore non-`Ok` statuses in examples, tools, or tests.
- Do not introduce Ada reserved words as identifiers, even with different case.
- Do not add public API without updating `src/zlib.ads`, docs, examples where
  appropriate, tests, and this guide.

## Choosing examples to copy

Use these examples as canonical starting points:

| Task | Example |
| --- | --- |
| zlib one-shot roundtrip | `examples/roundtrip_dynamic.adb` |
| compression level use | `examples/compress_with_level.adb` |
| gzip metadata | `examples/gzip_with_metadata.adb` |
| gzip multi-member input | `examples/gzip_multimember_inflate.adb` |
| raw Deflate one-shot | `examples/raw_roundtrip.adb` |
| dictionary compression/inflate | `examples/dictionary_roundtrip.adb` |
| checksums | `examples/checksums.adb` |
| file compression | `examples/deflate_dynamic_file.adb` |
| streaming zlib roundtrip | `examples/streaming_roundtrip_zlib.adb` |
| streaming gzip roundtrip | `examples/streaming_roundtrip_gzip.adb` |
| streaming raw output | `examples/streaming_deflate_raw.adb` |

Every example should set a non-zero process exit status on failure.

## Validation before returning changes

Run the full validation path when the Ada toolchain is available:

```sh
alr build
alr exec -- gprbuild -P zlib.gpr
cd tests && alr exec -- gprbuild -P tests.gpr
cd tests && ./bin/tests
alr exec -- gprbuild -P examples/examples.gpr
alr exec -- gprbuild -P tools/tools.gpr
./tools/bin/smoke_test
tools/bin/check_all
```

If the environment lacks GNAT/GPRBuild, report that explicitly and at minimum
run the available static checks: line-length checks, shell syntax checks,
example/tool/documentation wiring checks, and zip integrity checks.

## Documentation update rules

When changing public behavior, update all affected discoverability surfaces:

- `src/zlib.ads` GNATdoc comments;
- `docs/API.md` and `docs/API_CHEATSHEET.md`;
- wrapper-specific docs under `docs/`;
- `docs/QUICKSTART.md` if first-use behavior changes;
- `examples/README.md` and relevant examples;
- `README.md` documentation/tool/example lists;
- `llms.txt` if entry points, public contract, or validation commands change;
- `AGENTS.md` if repository maintenance workflow changes.
