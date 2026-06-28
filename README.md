# Zlib

Development version 0.1.0-dev.

`Zlib` is a standalone Ada/Alire crate for zlib-wrapped Deflate,
single-member and explicit multi-member gzip inflate, gzip output, explicit raw Deflate inflate/output,
native stored-file 7z archive output/extraction, and wrapper-strict deterministic compression. It is not Git-specific, not
HttpClient-specific, and has no dependency on `version`, `HttpClient`, system
`zlib`, generated Python fixtures, or C runtime compression libraries.

The crate provides a small root package:

```ada
with Zlib;
```

Public child packages are not part of the consumer contract. Consumers should
use only the declarations in `src/zlib.ads` unless they are deliberately
working on the crate internals.

## Quickstart

Add the crate to an Alire project with:

```sh
alr with zlib
alr build
```

When working from this repository, the fast validation path is:

```sh
alr build
tools/bin/check_all
```

Compress and inflate a zlib-wrapped stream:

```ada
with Ada.Text_IO;
with Zlib;

procedure Example is
   Status : Zlib.Status_Code;
   Plain  : constant Zlib.Byte_Array :=
     [16#68#, 16#65#, 16#6C#, 16#6C#, 16#6F#];
   Packed : constant Zlib.Byte_Array :=
     Zlib.Deflate (Plain, Status => Status);
   Back   : constant Zlib.Byte_Array :=
     Zlib.Inflate (Packed, Status);
begin
   if Status /= Zlib.Ok or else Back /= Plain then
      Ada.Text_IO.Put_Line ("zlib roundtrip failed: " & Zlib.Status_Image (Status));
   end if;
end Example;
```

Use explicit wrapper APIs when the input or output is not a zlib stream:

```ada
Gz : constant Zlib.Byte_Array := Zlib.GZip (Plain, Status => Status);
Gz_Back : constant Zlib.Byte_Array :=
  Zlib.Inflate_With_Header (Gz, Zlib.GZip, Status);

Raw : constant Zlib.Byte_Array := Zlib.Deflate_Raw (Plain, Status => Status);
Raw_Back : constant Zlib.Byte_Array := Zlib.Inflate_Raw (Raw, Status);
```

Use file helpers for whole-file operations:

```ada
Zlib.Deflate_File ("input.bin", "input.bin.z", Status => Status);
Zlib.Inflate_File ("input.bin.z", "input.bin.out", Status => Status);
Zlib.GZip_File ("input.bin", "input.bin.gz", Status => Status);
Zlib.Deflate_Raw_File ("input.bin", "input.bin.deflate", Status => Status);
Zlib.Seven_Zip_Stored_File ("input.bin", "input.7z", "input.bin", Status);
Zlib.Extract_Seven_Zip_Stored_File ("input.7z", "input.out", "input.bin", Status);
```

The compiled version of this quickstart is `examples/quickstart.adb`; the full first-use walkthrough is in `docs/QUICKSTART.md`.

Generate consumer-facing GNATdoc output for the root public API with:

```sh
alr exec -- gnatdoc -P docs/public_docs.gpr --style gnat --generate public --backend html --warnings -O docs/html
```

## Current capabilities

- one-shot zlib inflate for stored, fixed-Huffman, and dynamic-Huffman Deflate
  blocks
- explicit one-shot wrapper selection through `Inflate_With_Header` for
  `Zlib_Header`, `GZip`, and `Raw_Deflate`
- convenience wrapper-discriminating inflate through `Inflate_Auto`
- one-shot zlib stored-block output through `Deflate_Stored`
- one-shot zlib fixed-Huffman output through `Deflate_Fixed`
- one-shot zlib dynamic-Huffman output through `Deflate_Dynamic`
- policy-based zlib output through `Deflate` with `Compression_Mode`
- deterministic one-shot gzip output through `GZip` with `Compression_Mode`
- deterministic multi-member gzip output through `GZip_Members` and
  `GZip_File_Members`
- one-shot raw Deflate output through `Deflate_Raw` with `Compression_Mode`
- ZIP output through `ZIP`, `ZIP_File`, and `ZIP_Files` for Stored and Deflate
  entries, including explicit ZIP64 metadata from `ZIP_Files`
- in-process BZip2, ZIP-LZMA, and Zstandard member-payload
  creation and unencrypted extraction for ZIP methods 12, 14, 20, and 93
  through the ZIP compatibility bridge
- native stored, Deflate, BZip2, LZMA, and LZMA2 `.7z` output/extraction,
  plus native PPMd `.7z` extraction for empty streams with or without range
  headers, repeated-symbol, simple root-symbol, periodic-prefix, stock-7z non-solid multi-block streams
  with LZMA encoded headers, stock-7z no-stream empty-file entries, and
  stock-7z BCJ+PPMd filter chains,
  with common archive/file metadata and SFX prefixes
  skipped during supported native extraction, covered
  solid-substream, BCJ2 graph layouts with Copy or supported main pre-coders,
  and bounded linear filter-chain extraction layouts made from supported
  single-input coders and x86 BCJ/Delta filters, including standard
  zero-based, reverse-linear, and reordered
  zero-based linear bind pairs,
  through `Seven_Zip_Stored`, `Seven_Zip_Deflate`, `Seven_Zip_BZip2`,
  `Seven_Zip_LZMA`, `Seven_Zip_LZMA2`, the matching file helpers,
  `Seven_Zip_Stored_Files`, `Seven_Zip_Deflate_Files`,
  `Seven_Zip_BZip2_Files`, `Seven_Zip_LZMA_Files`,
  `Seven_Zip_LZMA2_Files`, `Seven_Zip_PPMd_Files`, and `Extract_Seven_Zip`;
  broader unsupported 7z methods fail closed
- opt-in external `.7z` creation/extraction compatibility placeholders
  through `Seven_Zip_External_File` and `Extract_Seven_Zip_External_File`;
  these do not invoke a local `7z` executable and return deterministic
  failure codes for unsupported broader 7z work
- file helpers for one-shot inflate and all one-shot compression modes
- streaming zlib inflate through `Inflate_Init`, `Translate`, `Flush`,
  `Stream_End`, and `Close`
- streaming single-member gzip inflate through `Header => GZip`
- streaming raw Deflate inflate through `Header => Raw_Deflate`
- streaming zlib, gzip, and raw Deflate compression through `Deflate_Init`,
  `Compress`, `Compress_Flush`, `Compress_Stream_End`, and `Compress_Close`
  for stored-block, fixed-Huffman, dynamic-Huffman, and Auto output
- zlib Adler-32 validation
- gzip CRC32 and ISIZE validation
- deterministic lifecycle/error behavior for streaming callers
- internal streaming engine shared by the one-shot and streaming APIs
- Ada-only AUnit tests with frozen byte-vector fixtures

`Seven_Zip_Stored`/`Seven_Zip_Stored_File` write a native `.7z` container with
the Copy coder for one file or a header-only directory entry. Single-entry 7z
metadata overloads emit supported modification FILETIME and raw Windows
attributes for file entries; the stored metadata overload and compressed
metadata overloads can also emit header-only directory entries. File and
file-list 7z helpers preserve source modification time and read-only state
where the platform exposes them. Single-entry file helpers accept ordinary-file
inputs or directory inputs; directories become header-only directory entries.
`Seven_Zip_Deflate`/`Seven_Zip_Deflate_File` write a single-entry `.7z`
container with a raw-Deflate packed payload or a header-only directory entry
using either a compression mode or compression level.
`Seven_Zip_LZMA`/`Seven_Zip_LZMA_File`
write native single-entry `.7z` archives with the LZMA coder.
`Seven_Zip_BZip2`/`Seven_Zip_BZip2_File` write native single-entry `.7z`
archives with the BZip2 coder. `Seven_Zip_LZMA2` and `Seven_Zip_LZMA2_File`
write native single-entry `.7z` archives using valid LZMA2 chunks, including
compressed chunks for payloads that benefit from them.
`Seven_Zip_PPMd`/`Seven_Zip_PPMd_File` write native single-entry `.7z`
archives using deterministic verified PPMd streams accepted by this crate's
native extractor. The writer selects among modeled stock-compatible candidates,
repeated/periodic PPMd forms, and a verified native root-context fallback. The
file helper
accepts either the input basename or an explicit entry name, and directory
inputs become header-only directory entries.
They self-verify generated archives and do not call a local `7z` executable.
Empty PPMd output uses a range-initialized empty stream.
`Seven_Zip_Stored_Files` writes a multi-entry solid Copy-coder archive from
parallel input-path and distinct entry-name lists. Ordinary files become packed
substreams and directory input paths become no-stream directory entries.
`Seven_Zip_Deflate_Files` writes the same file-list shape with independently
Deflate-packed entries using either a compression mode or compression level.
`Seven_Zip_BZip2_Files` writes the same file-list shape with independently
BZip2-packed entries.
`Seven_Zip_LZMA_Files` writes the same file-list shape with independently
LZMA-coded entries using the library default properties.
`Seven_Zip_LZMA2_Files` writes the same file-list shape with independently
LZMA2-coded entries using valid LZMA2 chunks. `Seven_Zip_PPMd_Files` writes
the same file-list shape with independently packed deterministic PPMd entries
using the same verified candidate selection. File-list writers preserve supported
per-entry source metadata for files and directories.
`Extract_Seven_Zip_Stored` and its file helpers verify and extract one named
entry from those Copy-coder, Deflate, BZip2, LZMA, or LZMA2 layouts, plus the
native PPMd extraction subset for empty streams with or without range headers,
repeated-symbol, simple root-symbol, periodic-prefix, stock-7z non-solid multi-block streams with LZMA encoded
headers, stock-7z no-stream empty-file entries, stock-7z BCJ+PPMd filter
chains, and BCJ2 graphs with Copy, PPMd, or supported main pre-coders. The PPMd model table is allocated from
the archive's declared PPMd memory and requested output size rather than a
fixed stream-independent context cap. The supported PPMd decode mode ladder is
used for payloads, encoded headers, BCJ+x86 chains, and BCJ2 graphs. Broader
PPMd entries fail closed with a non-Ok status. `Extract_Seven_Zip` is the neutral extractor name with the same
native-only supported method set. Duplicate matching names are rejected.
`Extract_Seven_Zip_Metadata` exposes supported entry kind, modification
FILETIME, and Windows attribute metadata for a selected verified entry.
Native LZMA extraction accepts stored
lc/lp/pb and dictionary metadata for supported property combinations. Native
LZMA2 extraction accepts compressed, uncompressed, reset/properties,
state-reset, and state-continuing chunks for supported lc/lp/pb properties in
the single-folder layout. Supported extraction also accepts covered solid
substreams, BCJ2 graph layouts with Copy or supported main pre-coders, and
bounded linear filter-chain layouts made from supported single-input coders and
x86 BCJ/Delta filters, including standard zero-based, reverse-linear,
reordered zero-based, and legacy one-based linear bind pairs. File and
file-list extraction helpers create needed parent
directories and restore supported per-entry directories, modification times,
and read-only attributes after writing output paths.
`Extract_Seven_Zip_Stored_Files` extracts selected entries into an output
directory after requiring a non-empty destination and prevalidating distinct
requested names, and rejects unsafe absolute or traversing entry paths before
writing. It verifies all requested payloads before writing any output file.
`Extract_Seven_Zip_Files` has the same staging and path-safety behavior, and
unsupported 7z methods fail closed after native extraction returns
`Unsupported_Method`. ZIP BZip2
and Zstandard creation and unencrypted extraction for
classic and ZIP64 metadata use in-process payload handling backed by libbz2 and
libzstd. ZIP method 14 LZMA uses an in-tree range coder, literal coder, and
normal-match distance coding including pos-special, direct-bit, and align-bit
distances plus rep matches emitted by this library.
For general 7z methods and general archives, `Seven_Zip_External_File` and
`Extract_Seven_Zip_External_File` are compatibility placeholders for the former
external bridge. They do not call local `7z`; unsupported broader creation,
extraction, unsupported broader solid layouts, and
password-protected archives fail closed with deterministic status codes.

## Public one-shot API

The one-shot API is status-code based and binary-safe: input and output are
byte arrays, not strings. `Inflate` accepts complete zlib streams only.
`Inflate_With_Header` adds explicit wrapper selection for complete zlib, gzip,
and raw Deflate buffers. No one-shot API auto-detects wrappers.

```ada
with Zlib;

procedure Example is
   Status : Zlib.Status_Code;
   Plain  : constant Zlib.Byte_Array :=
     [1 => 16#68#, 2 => 16#65#, 3 => 16#6C#, 4 => 16#6C#, 5 => 16#6F#];
   ZData  : constant Zlib.Byte_Array := Zlib.Deflate (Plain, Status => Status);
   Back   : constant Zlib.Byte_Array := Zlib.Inflate (ZData, Status);
begin
   null;
end Example;
```

## Public streaming API

The streaming API is exception-based. `Status_Error` indicates caller lifecycle
misuse. `Zlib_Error` indicates malformed, truncated, unsupported, or
validation-failed compressed data.

```ada
type Filter_Type is limited private;
type Header_Type is (Default, Zlib_Header, GZip, Raw_Deflate);
type Flush_Mode is (No_Flush, Sync_Flush, Full_Flush, Finish);

Zlib_Error   : exception;
Status_Error : exception;

procedure Inflate_Init (Filter : in out Filter_Type; Header : Header_Type := Default);
function Is_Open (Filter : Filter_Type) return Boolean;
procedure Translate (...);
procedure Flush (...);
function Stream_End (Filter : Filter_Type) return Boolean;
procedure Close (Filter : in out Filter_Type; Ignore_Error : Boolean := False);
```

`Default` is exactly `Zlib_Header`; it does not auto-detect gzip or raw streams.
`Zlib_Header` selects a zlib wrapper plus Adler-32 trailer. `GZip` selects one
gzip member and validates CRC32/ISIZE. `Raw_Deflate` accepts a Deflate payload
without wrapper bytes or trailer checksum. One-shot `Inflate` remains
zlib-wrapper-only; use `Inflate_With_Header` for explicit one-shot gzip or raw
Deflate input. `Deflate_Stored`, `Deflate_Fixed`, `Deflate_Dynamic`, `Deflate`, and their
file helpers emit zlib-wrapped output. `GZip` and `GZip_File` emit gzip-wrapped
output. `Deflate_Raw`, `Deflate_Raw_File`, and streaming `Header =>
Raw_Deflate` emit raw Deflate payload bytes only.

## Build and release checklist

```sh
alr build
alr exec -- gprbuild -P zlib.gpr
alr exec -- gnatprove -P zlib.gpr --level=4
alr test
cd tests && alr exec -- gprbuild -P tests.gpr
cd tests && ./bin/tests
alr exec -- gprbuild -P examples/examples.gpr
alr exec -- gprbuild -P tools/tools.gpr
cd check_zlib && alr build && ./bin/check_zlib && cd ..
./tools/bin/smoke_test
tools/bin/check_all
```

`tools/bin/check_all` runs the same checklist where the required tools are
available, including the `check_zlib` release documentation guard.

## Release readiness

The crate metadata currently declares `licenses = "MIT OR Apache-2.0 WITH LLVM-exception"`.
The repository `LICENSE` file contains the MIT license text, the full Apache
License 2.0 text, and the LLVM exception text matching that expression. Before
publishing a package, run `tools/bin/check_all` from the repository root and
ensure `check_zlib` passes and the run ends with `zlib release checklist passed`.

## Documentation

- `docs/AI_GUIDE.md` — AI-agent discoverability, safe entry points, and maintenance rules
- `docs/API_CHEATSHEET.md` — compact task-to-public-API mapping
- `docs/QUICKSTART.md` — first build, one-shot, gzip, raw, file, and validation examples
- `docs/API.md` — public root-package API summary
- `docs/USAGE.md` — short usage examples for one-shot and streaming callers
- `docs/STREAMING.md` — streaming inflate lifecycle and wrapper contract
- `docs/STREAMING_COMPRESSION.md` — streaming compression lifecycle, flushes, wrappers, levels, dictionaries
- `docs/ERRORS.md` — status/exception mapping and lifecycle failures
- `docs/GZIP.md` — gzip inflate/output wrapper policy, metadata, multi-member input, CRC32
- `docs/GZIP_OUTPUT.md` — gzip output shape, metadata emission, determinism
- `docs/COMPRESSION.md` — compression modes, levels, output contract, dictionaries, checksums
- `docs/RAW_DEFLATE.md` — raw Deflate usage and wrapper comparison
- `docs/RAW_COMPRESSION.md` — raw compression matrix and lifecycle notes
- `docs/CONSUMERS.md` — integration notes for `version`, `HttpClient`, and other Ada tools
- `docs/TESTING.md` — test organization, release checklist, fuzz smoke policy
- `docs/FUZZING.md` — deterministic fuzzing tools, seeds, pass/fail policy
- `docs/BENCHMARKS.md` — optional benchmark/profiling guidance
- `docs/ARCHITECTURE.md` — internal package overview
- `docs/MAINTENANCE.md` — long-term maintenance rules
- `docs/CONSTRAINTS.md` — explicit scope constraints
- `docs/ROADMAP.md` — controlled maintenance path and future work
- `docs/SEVEN_ZIP_PLAN.md` — ordered implementation plan toward full 7z encode/decode
- `docs/SPARK.md` — SPARK-enabled units and GNATprove release command

## Examples and tools

Examples under `examples/` compile against the public root package only. Checked examples include `examples/quickstart.adb`, `examples/streaming_deflate_zlib.adb`, `examples/streaming_deflate_raw.adb`, `examples/gzip_with_metadata.adb`, and `examples/dictionary_roundtrip.adb`. The standalone mains are:

- `checksums.adb`
- `compress_with_level.adb`
- `deflate_file_streaming.adb`
- `deflate_raw_file.adb`
- `deflate_raw_file_to_stream.adb`
- `deflate_raw_file_streaming.adb`
- `deflate_stored_file.adb`
- `deflate_fixed_file.adb`
- `deflate_dynamic_file.adb`
- `dictionary_roundtrip.adb`
- `gzip_file.adb`
- `gzip_file_streaming.adb`
- `gzip_multimember_inflate.adb`
- `gzip_with_metadata.adb`
- `inflate_file.adb`
- `inflate_file_streaming.adb`
- `inflate_raw.adb`
- `inflate_raw_file.adb`
- `inflate_raw_file_streaming.adb`
- `inflate_with_header.adb`
- `raw_roundtrip.adb`
- `raw_vs_zlib_vs_gzip.adb`
- `roundtrip_stored.adb`
- `roundtrip_fixed.adb`
- `roundtrip_dynamic.adb`
- `streaming_deflate_zlib.adb`
- `streaming_deflate_gzip.adb`
- `streaming_deflate_raw.adb`
- `streaming_inflate_zlib.adb`
- `streaming_inflate_gzip.adb`
- `streaming_roundtrip_zlib.adb`
- `streaming_roundtrip_gzip.adb`
- `example_raw_support.adb` / `example_raw_support.ads` support raw-example cleanup code

Tools under `tools/` are small command-line utilities using only public `Zlib`, except the
deterministic fuzz drivers which use the internal deterministic `Zlib.Fuzzing` helper package:

- `zlib_inflate_file.adb`
- `zlib_deflate_stored_file.adb`
- `zlib_deflate_fixed_file.adb`
- `zlib_deflate_dynamic_file.adb`
- `zlib_compress_file.adb`
- `zlib_streaming_roundtrip.adb`
- `gzip_file.adb`
- `gzip_metadata_file.adb`
- `gzip_streaming_roundtrip.adb`
- `raw_deflate_file.adb`
- `raw_inflate_file.adb`
- `raw_roundtrip.adb`
- `raw_vs_zlib_vs_gzip.adb`
- `zlib_bench_inflate.adb` optional inflate benchmark
- `zlib_bench_deflate.adb` optional zlib/gzip/raw compression benchmark
- `zlib_bench_gzip.adb` optional gzip-default compression benchmark
- `zlib_bench_raw.adb` optional raw-default compression benchmark
- `tools/fuzz/fuzz_*.adb` deterministic fuzz drivers documented in `docs/FUZZING.md`
- `smoke_test`
- `check_all`
- `check_zlib`

## AI and automated-agent discoverability

This repository includes explicit AI-facing entry points so automated coding
assistants can find the public API and avoid internal packages:

- `llms.txt` — compact repository summary for language-model consumers
- `AGENTS.md` — repository maintenance rules for coding agents
- `docs/AI_GUIDE.md` — detailed AI integration and safe-change guide
- `docs/API_CHEATSHEET.md` — task-to-API lookup table

The rule for generated examples, downstream integrations, and AI-authored code
is simple: import only `with Zlib;` unless the task is explicitly internal crate
maintenance. `src/zlib.ads` remains the source of truth for the public API.

## Scope and non-goals

This release is a maintenance-ready zlib/Deflate crate with conservative,
deterministic zlib, gzip, and raw Deflate output support. `Deflate_Stored`
remains the compatibility/no-compression zlib writer. `Deflate_Fixed` emits
fixed-Huffman zlib streams. `Deflate_Dynamic` emits deterministic
dynamic-Huffman zlib streams through the same block-local streaming compression
engine used by explicit streaming Dynamic. `Deflate` adds a zlib-wrapper policy layer, and
`Deflate_Raw` adds the corresponding raw Deflate payload policy. Explicit modes
select the requested block policy; `Auto` is deterministic and block-local for
streaming/raw output. It does not imply best possible
compression, lazy matching, optimal parsing, or whole-stream buffering. These simple writers should not be
compared with default `zlib` compression ratios.

The crate does not implement a performance rewrite, new `HttpClient` APIs, a new
`version` object model, or broad wrapper guessing on strict APIs. A
general-purpose, pure-Ada 7z codec stack **is** an explicit goal of the project
and is under active development — see `docs/SEVEN_ZIP_PLAN.md` for the ordered
plan and `docs/CONSTRAINTS.md` for what is shipped versus not-yet-built. The
currently supported native 7z layouts are progress toward full encode/decode
support, not the intended final boundary. Verified native PPMd
`.7z` output is available through `Seven_Zip_PPMd`,
`Seven_Zip_PPMd_File`, and `Seven_Zip_PPMd_Files` without calling a local
`7z` executable. ZIP output is available through `ZIP`,
`ZIP_File`, and `ZIP_Files`; `ZIP_Files` can emit multi-entry ZIP archives and
explicit ZIP64 metadata. Convenience wrapper-discriminating inflate is available
through `Inflate_Auto`, and multi-member gzip output is available through
`GZip_Members` and `GZip_File_Members`. Explicit multi-member gzip input is
available through the APIs that take `GZip_Member_Mode`. Raw Deflate output is available through `Deflate_Raw`,
`Deflate_Raw_File`, and streaming `Header => Raw_Deflate, Mode =>
Stored|Fixed|Dynamic|Auto`; it is still only a payload for external containers
or protocols that supply framing and integrity checks.

## Release contract

Wrapper behavior is explicit and intentionally strict:

- strict inflate APIs do not perform wrapper auto-detection; use `Inflate_Auto`
  when lightweight wrapper-discriminating convenience is wanted;
- `Default` means exactly `Zlib_Header`;
- `Inflate` is zlib-wrapper-only;
- `Inflate_With_Header` is the explicit one-shot wrapper-selection API;
- all `Deflate_*` and `Deflate` outputs are zlib-wrapped;
- `GZip` and `GZip_File` outputs are gzip-wrapped; defaults use a deterministic minimal header;
- optional gzip metadata is emitted only through explicit metadata overloads;
- `Raw_Deflate` input/output is Deflate payload only and has no checksum trailer;
- `GZip` validates CRC32 and ISIZE for one gzip member during inflate;
- `Zlib_Header` validates Adler-32.

The release checklist builds the crate, tests, examples, and tools, then runs the
AUnit suite and command-line smoke test. No runtime fixture generation or system
zlib dependency is part of the normal release path.

## Streaming compression examples and tools

The public root package now supports completed one-shot and streaming
compression for zlib, gzip, and raw Deflate output.

Supported streaming compression combinations are:

- `Header => Default / Zlib_Header`, `Mode => Stored`
- `Header => Default / Zlib_Header`, `Mode => Fixed`
- `Header => Default / Zlib_Header`, `Mode => Dynamic`
- `Header => Default / Zlib_Header`, `Mode => Auto`
- `Header => GZip`, `Mode => Stored`
- `Header => GZip`, `Mode => Fixed`
- `Header => GZip`, `Mode => Dynamic`
- `Header => GZip`, `Mode => Auto`
- `Header => Raw_Deflate`, `Mode => Stored`
- `Header => Raw_Deflate`, `Mode => Fixed`
- `Header => Raw_Deflate`, `Mode => Dynamic`
- `Header => Raw_Deflate`, `Mode => Auto`

`Default` is exactly `Zlib_Header`. Raw compression emits Deflate blocks only:
no zlib header, no Adler-32 footer, no gzip header, no CRC32 trailer, and no
ISIZE trailer. `Auto` is deterministic and block-local. Compression levels are
available as broad effort policy. Strict wrapper APIs remain explicit;
`Inflate_Auto` provides lightweight wrapper-discriminating convenience.
Multi-member gzip output and ZIP output are available through their explicit
APIs. Broader unsupported 7z extraction fails closed. Optional gzip metadata
output is available through explicit
metadata overloads only; default gzip output remains minimal.

See:

- `docs/STREAMING_COMPRESSION.md`
- `docs/GZIP_OUTPUT.md`
- `examples/streaming_deflate_zlib.adb`
- `examples/streaming_deflate_gzip.adb`
- `examples/streaming_roundtrip_zlib.adb`
- `examples/streaming_roundtrip_gzip.adb`
- `examples/streaming_deflate_raw.adb`
- `examples/raw_roundtrip.adb`
- `examples/raw_vs_zlib_vs_gzip.adb`

Useful validation commands:

```sh
alr exec -- gprbuild -P examples/examples.gpr
alr exec -- gprbuild -P tools/tools.gpr
cd check_zlib && alr build && ./bin/check_zlib && cd ..
./tools/bin/smoke_test
tools/bin/check_all
```


## Raw Deflate compression

Raw Deflate compression is now part of the public API through `Deflate_Raw`,
`Deflate_Raw_File`, `Deflate_Raw_File_Size`,
`Deflate_Raw_File_To_Stream`, and streaming `Deflate_Init (Header =>
Raw_Deflate, ...)`. Raw output is Deflate block data only: it has no zlib
header/Adler-32 trailer and no gzip header/CRC32/ISIZE trailer.
`Deflate_Raw_File_Size` and `Deflate_Raw_File_To_Stream` support container
writers that need exact raw payload sizes or need to write into an already-open
output stream. Use raw
Deflate only when an outer protocol or container supplies framing and integrity
checks. See `docs/RAW_DEFLATE.md` and `docs/RAW_COMPRESSION.md`.

Examples and tools for raw output are included in `examples/streaming_deflate_raw.adb`,
`examples/deflate_raw_file.adb`, `examples/deflate_raw_file_to_stream.adb`, `examples/inflate_raw_file.adb`,
`examples/deflate_raw_file_streaming.adb`, `examples/inflate_raw_file_streaming.adb`,
`examples/raw_roundtrip.adb`, `examples/raw_vs_zlib_vs_gzip.adb`,
`tools/raw_deflate_file.adb`, `tools/raw_roundtrip.adb`, and
`tools/raw_vs_zlib_vs_gzip.adb`.


## Raw Deflate release hardening

Raw Deflate compression is release-hardened by `zlib_raw_release_tests`,
`zlib_raw_cross_wrapper_conformance_tests`, the raw examples, and the raw tools.
The contract remains unchanged: `Deflate_*` APIs emit zlib-wrapped streams, `GZip*` APIs emit
gzip-wrapped streams, `Deflate_Raw*` APIs emit raw Deflate blocks only, `Inflate` is
zlib-wrapper-only, and `Inflate_With_Header` performs explicit wrapper selection without
auto-detection. `Auto` remains deterministic and block-local; the library still
has no general-purpose 7z codec stack and no broad wrapper guessing on strict
APIs. Native PPMd `.7z` single-file and file-list creation is available in
process without calling a local `7z` executable, using verified
modeled stock-compatible candidates, repeated/periodic PPMd forms, and a
verified native root-context fallback.


## Streaming compression flush modes

`Sync_Flush` forces currently buffered compression input into the Deflate stream without ending it.
It finishes the current block as non-final and emits an empty non-final stored block on a byte
boundary. `Full_Flush` currently has the same byte-level behavior because the compressor has no
cross-block match history; the distinction is preserved in the API and tests. Neither mode emits
zlib/gzip trailers, and `Compress_Stream_End` remains `False` until `Finish`. Flush output may
require repeated drain calls with small output buffers. `Finish` after a partially drained flush
completes the pending flush work and then finalizes the stream. After stream end, `Sync_Flush` and
`Full_Flush` are lifecycle misuse and raise `Status_Error`. Streaming inflate treats `Sync_Flush`
and `Full_Flush` as `No_Flush`; Deflate flush markers are ordinary stored blocks.
