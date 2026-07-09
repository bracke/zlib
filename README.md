# Zlib

Development version 0.1.0-dev.

`Zlib` is a standalone Ada/Alire crate for zlib-wrapped Deflate,
implicit multi-member gzip inflate, gzip output, explicit raw Deflate inflate/output,
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

## Reentrancy and parallel callers

Independent operations are reentrant. Tools may call zlib functions from
multiple Ada tasks when each task uses its own buffers, streaming filter
objects, and output paths. The library does not synchronize shared
caller-owned state, so shared `Filter_Type`/`Compression_Filter_Type` objects,
mutable buffers, and overlapping filesystem destinations must be protected by
the caller.

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
- native stored, Deflate, BZip2, LZMA, LZMA2, and PPMd `.7z`
  output/extraction, including general PPMd7 encode/decode, stock-7z
  non-solid multi-block streams with LZMA encoded headers, stock-7z no-stream
  empty-file entries, and stock-7z BCJ+PPMd filter chains,
  with common archive/file metadata and SFX prefixes
  skipped during supported native extraction, covered
  solid-substream, BCJ2 graph layouts with Copy or supported main pre-coders,
  and bounded linear filter-chain extraction layouts made from supported
  single-input coders and supported branch/Delta filters, including standard
  zero-based, reverse-linear, and reordered
  zero-based linear bind pairs,
  through `Seven_Zip_Stored`, `Seven_Zip_Deflate`, `Seven_Zip_BZip2`,
  `Seven_Zip_LZMA`, `Seven_Zip_LZMA2`, `Seven_Zip_Filtered`,
  `Seven_Zip_Method_Graph`, the matching file helpers,
  `Seven_Zip_Stored_Files`, `Seven_Zip_Deflate_Files`,
  `Seven_Zip_BZip2_Files`, `Seven_Zip_LZMA_Files`,
  `Seven_Zip_LZMA2_Files`, `Seven_Zip_PPMd_Files`, and `Extract_Seven_Zip`;
  broader unsupported 7z methods fail closed
- file helpers for one-shot inflate and all one-shot compression modes
- streaming zlib inflate through `Inflate_Init`, `Translate`, `Flush`,
  `Stream_End`, and `Close`
- streaming gzip inflate through `Header => GZip`, accepting concatenated
  members by default
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
`Seven_Zip_Filtered` writes a native single-entry non-encrypted compressed
filtered `.7z` archive such as BCJ+LZMA, BCJ+LZMA2, or Delta+Deflate. It
applies one supported 7z branch/Delta filter, compresses the filtered bytes
with Deflate, BZip2, LZMA, LZMA2, or PPMd, and emits the two-coder folder and
bind pair in process. RISC-V uses the compact 7z 24.x method ID and handles
32-bit JAL branches; stock RISC-V interop validation is part of
`tools/bin/seven_zip_interop_check` when the available `7z` supports it.
`Seven_Zip_Method_Graph` writes a native single-entry non-encrypted `.7z`
method-graph container from already packed stream bytes and caller-supplied
coders, bind pairs, packed stream indices, sizes, and final unpacked CRC. It is
the low-level escape hatch for graph layouts; callers remain responsible for
producing packed bytes that match the graph.
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
supported branch/Delta filters, including standard zero-based, reverse-linear,
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
Unsupported broader 7z creation, extraction, and layouts outside the native
supported set fail closed with deterministic status codes. Use the native
password overloads for supported AES-encrypted 7z payloads and encrypted
headers.

## Public one-shot API

The one-shot API is status-code based and binary-safe: input and output are
byte arrays, not strings. `Inflate` uses lightweight wrapper auto-detection for
complete zlib, gzip, and raw Deflate streams. `Inflate_With_Header` with
`Header => Default` has the same implicit behavior; concrete header values
(`Zlib_Header`, `GZip`, `Raw_Deflate`) keep strict wrapper boundaries.
`Inflate_Auto` remains an explicit alias for the same one-shot discrimination.

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

For one-shot and streaming inflate, `Default` auto-detects zlib, gzip, or raw
Deflate input. Gzip input accepts concatenated members by default in both
one-shot and streaming gzip modes. For streaming compression, `Default` remains
the zlib wrapper default. `Zlib_Header` selects a zlib wrapper plus Adler-32
trailer. `GZip` selects gzip member syntax and validates CRC32/ISIZE.
`Raw_Deflate` accepts a Deflate payload without wrapper bytes or trailer
checksum. `Deflate_Stored`,
`Deflate_Fixed`, `Deflate_Dynamic`, `Deflate`, and their
file helpers emit zlib-wrapped output. `GZip` and `GZip_File` emit gzip-wrapped
output. `Deflate_Raw`, `Deflate_Raw_File`, and streaming `Header =>
Raw_Deflate` emit raw Deflate payload bytes only.

## Build and release checklist

```sh
alr build
alr exec -- gnatls --version
alr exec -- gprbuild -P zlib.gpr
alr exec -- gnatprove -P zlib.gpr --level=4
alr test
cd tests && alr exec -- gprbuild -P tests.gpr
cd tests && ./bin/tests
alr exec -- gprbuild -P examples/examples.gpr
alr exec -- gprbuild -P tools/tools.gpr
cd check_zlib && alr build && ./bin/check_zlib && cd ..
./tools/bin/smoke_test
./tools/bin/seven_zip_interop_check
tools/bin/check_all
```

Validation is tied to Alire GNAT 15. The crate manifests require
`gnat_native = "^15"`, and the release guards check that
`alr exec -- gnatls --version` reports GNATLS 15.x. Do not run plain system
`gnat*`, `gnatprove`, or `gprbuild` for validation; those may resolve to an
older compiler outside Alire.

`tools/bin/check_all` runs the same checklist where the required tools are
available, including the `check_zlib` release documentation guard.
`tools/bin/seven_zip_interop_check` is an optional stock-7z lane for method,
filter, corpus, file-list directory, BCJ2, solid, encrypted, and multi-volume
coverage, including encrypted listing and wrong-password checks. It probes the
stock `RISCV` filter and runs RISC-V cases when available; it skips
successfully when `7z` is not on `PATH`.

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
- `zlib_bench_matrix.adb` optional compact compression benchmark matrix
- `seven_zip_interop_check.adb` optional stock-7z interoperability check
- `tools/fuzz/fuzz_inflate.adb`
- `tools/fuzz/fuzz_streaming_inflate.adb`
- `tools/fuzz/fuzz_compress_roundtrip.adb`
- `tools/fuzz/fuzz_compress_levels.adb`
- `tools/fuzz/fuzz_wrapper_mix.adb`
- `tools/fuzz/fuzz_dictionary.adb`
- `tools/fuzz/fuzz_gzip_metadata.adb`
- `tools/fuzz/fuzz_mutation.adb`
- `tools/fuzz/fuzz_flush.adb`
- `tools/fuzz/fuzz_lifecycle.adb`
- `tools/fuzz/fuzz_tiny_buffers.adb`
- `smoke_test.adb`
- `check_all.adb`
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

## Scope

This release is a maintenance-ready zlib/Deflate crate with conservative,
deterministic zlib, gzip, and raw Deflate output support. `Deflate_Stored`
remains the compatibility/no-compression zlib writer. `Deflate_Fixed` emits
fixed-Huffman zlib streams. `Deflate_Dynamic` emits deterministic
dynamic-Huffman zlib streams through the same block-local streaming compression
engine used by explicit streaming Dynamic. `Deflate` adds a zlib-wrapper policy layer, and
`Deflate_Raw` adds the corresponding raw Deflate payload policy. Explicit modes
select the requested block policy; `Auto` is deterministic and block-local for
streaming/raw output. Compression levels provide a broad effort policy while
preserving deterministic output.

The crate does not implement a performance rewrite, new `HttpClient` APIs, a new
`version` object model, or broad wrapper guessing on strict APIs. The
root-package zlib/gzip/raw Deflate surface is maintenance-ready, and the
general-purpose, pure-Ada 7z codec stack is substantially implemented — see
`docs/SEVEN_ZIP_PLAN.md` for the remaining validation and tuning boundary.
Verified native PPMd
`.7z` output is available through `Seven_Zip_PPMd`,
`Seven_Zip_PPMd_File`, and `Seven_Zip_PPMd_Files` without calling a local
`7z` executable. ZIP output is available through `ZIP`,
`ZIP_File`, and `ZIP_Files`; `ZIP_Files` can emit multi-entry ZIP archives and
explicit ZIP64 metadata. Convenience wrapper-discriminating inflate is available
through `Inflate_Auto`, and multi-member gzip output is available through
`GZip_Members` and `GZip_File_Members`. Gzip input accepts concatenated members
by default; strict single-member input is available through APIs that take
`GZip_Member_Mode`. Raw Deflate output is available through `Deflate_Raw`,
`Deflate_Raw_File`, and streaming `Header => Raw_Deflate, Mode =>
Stored|Fixed|Dynamic|Auto`; it is still only a payload for external containers
or protocols that supply framing and integrity checks.

## Release contract

Wrapper behavior is explicit for concrete modes, with inflate auto-detection on
the default path:

- one-shot `Inflate`, `Inflate_With_Header (..., Header => Default, ...)`, and
  streaming `Inflate_Init (..., Header => Default)` auto-detect zlib, gzip, or
  raw Deflate input, with concatenated gzip members accepted by default;
- `Inflate_Auto` is an explicit alias for that one-shot behavior;
- concrete headers `Zlib_Header`, `GZip`, and `Raw_Deflate` remain
  wrapper-strict; pass `GZip_Mode => Single_Member` to reject concatenated gzip
  members in one-shot or streaming gzip input;
- streaming inflate `Default` auto-detects zlib, gzip, or raw Deflate input;
- streaming compression keeps `Default` as `Zlib_Header`;
- all `Deflate_*` and `Deflate` outputs are zlib-wrapped;
- `GZip` and `GZip_File` outputs are gzip-wrapped; defaults use a deterministic minimal header;
- optional gzip metadata is emitted only through explicit metadata overloads;
- `Raw_Deflate` input/output is Deflate payload only and has no checksum trailer;
- `GZip` validates CRC32 and ISIZE for each gzip member during inflate;
- `Zlib_Header` validates Adler-32.
- `CryptoLib.Checksums` supplies internal Adler-32 and CRC32 calculation, and
  `Deflate_Bound`, `GZip_Bound`, and `Deflate_Raw_Bound` expose conservative
  one-shot output-size bounds.

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

For streaming compression, `Default` is exactly `Zlib_Header`. Raw compression
emits Deflate blocks only: no zlib header, no Adler-32 footer, no gzip header,
no CRC32 trailer, and no ISIZE trailer. `Auto` is deterministic and block-local.
Compression levels are available as broad effort policy. One-shot `Inflate`,
`Inflate_With_Header (..., Default, ...)`, and `Inflate_Auto` provide
lightweight wrapper-discriminating convenience; gzip input concatenates members
by default, while concrete header values remain wrapper-strict.
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
The contract remains unchanged for output: `Deflate_*` APIs emit zlib-wrapped streams, `GZip*` APIs emit
gzip-wrapped streams, and `Deflate_Raw*` APIs emit raw Deflate blocks only.
One-shot `Inflate`, `Inflate_With_Header (..., Default, ...)`, and
`Inflate_Auto` auto-detect zlib/gzip/raw input; gzip input accepts
concatenated members unless `GZip_Mode => Single_Member` is requested. Concrete
`Inflate_With_Header` headers remain wrapper-strict. `Auto` remains deterministic and block-local. Native `.7z`
creation and extraction cover the supported pure-Ada method set without calling
a local `7z` executable.


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
