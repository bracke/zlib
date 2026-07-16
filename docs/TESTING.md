# Testing and release checklist

The test suite is organized by public contract, internal subsystem, malformed
input behavior, streaming behavior, interoperability fixtures, and release
boundary checks.

## Main commands

Validation must use the Alire GNAT 15 toolchain. The crate manifests require
`gnat_native = "^15"`, and `tools/bin/check_all` plus `check_zlib` fail if
`alr exec -- gnatls --version` does not report GNATLS 15.x. Do not run plain
system `gnat*`, `gnatprove`, or `gprbuild` for validation; they may resolve to
an older compiler outside Alire.

```sh
alr build
alr exec -- gnatls --version
alr exec -- gnatprove -P zlib.gpr --level=4
alr test
alr exec -- gprbuild -P zlib.gpr
cd tests && alr exec -- gprbuild -P tests.gpr
cd tests && ./bin/tests
alr exec -- gprbuild -P examples/examples.gpr
alr exec -- gprbuild -P tools/tools.gpr
cd check_zlib && alr build && ./bin/check_zlib && cd ..
./tools/bin/smoke_test
tools/bin/check_all
```

The Ada smoke test must exercise `Deflate_Stored_File`, `Deflate_Fixed_File`,
and `Deflate_Dynamic_File` through `Inflate_File` so the command-line wrappers remain
wired into the release path.

`tools/bin/check_all` runs this checklist and fails fast, including `check_zlib`.

## Test categories

The expected suite categories are:

- `zlib_auto_block_selection_tests`
- `zlib_bit_writer_tests`
- `zlib_bits_tests`
- `zlib_block_chooser_tests`
- `zlib_public_tests`
- `zlib_compression_conformance_tests`
- `zlib_compression_level_tests`
- `zlib_consumer_fixture_tests`
- `zlib_crc32_tests`
- `zlib_cross_api_equivalence_tests`
- `zlib_deflate_auto_tests`
- `zlib_deflate_dynamic_tests`
- `zlib_deflate_fixed_tests`
- `zlib_deflate_raw_auto_tests`
- `zlib_deflate_raw_bridge_tests`
- `zlib_deflate_raw_dynamic_tests`
- `zlib_deflate_raw_fixed_tests`
- `zlib_deflate_raw_stored_tests`
- `zlib_deflate_stored_tests`
- `zlib_dictionary_tests`
- `zlib_file_tests`
- `zlib_fuzz_smoke_tests`
- `zlib_git_fixture_tests`
- `zlib_gzip_broader_compat_tests`
- `zlib_gzip_metadata_tests`
- `zlib_gzip_multimember_tests`
- `zlib_gzip_output_tests`
- `zlib_huffman_builder_tests`
- `zlib_huffman_tests`
- `zlib_inflate_dynamic_tests`
- `zlib_inflate_fixed_tests`
- `zlib_inflate_raw_api_tests`
- `zlib_inflate_with_header_tests`
- `zlib_interop_fixture_tests`
- `zlib_lazy_compression_tests`
- `zlib_lazy_matcher_tests`
- `zlib_lz77_matcher_tests`
- `zlib_malformed_conformance_tests`
- `zlib_malformed_tests`
- `zlib_one_shot_streaming_bridge_tests`
- `zlib_performance_regression_tests`
- `zlib_public_checksum_tests`
- `zlib_raw_compression_api_tests`
- `zlib_raw_cross_wrapper_conformance_tests`
- `zlib_raw_release_tests`
- `zlib_release_contract_tests`
- `zlib_seven_zip_filter_tests`
- `zlib_seven_zip_lzma_interop_tests`
- `zlib_seven_zip_tests`
- `zlib_sliding_window_tests`
- `zlib_stream_bits_tests`
- `zlib_streaming_api_tests`
- `zlib_streaming_compress_auto_tests`
- `zlib_streaming_compress_bounds_tests`
- `zlib_streaming_compress_conformance_tests`
- `zlib_streaming_compress_dynamic_tests`
- `zlib_streaming_compress_finish_tests`
- `zlib_streaming_compress_fixed_tests`
- `zlib_streaming_compress_flush_tests`
- `zlib_streaming_compress_gzip_tests`
- `zlib_streaming_compress_level_tests`
- `zlib_streaming_compress_lifecycle_tests`
- `zlib_streaming_compress_raw_auto_tests`
- `zlib_streaming_compress_raw_dynamic_tests`
- `zlib_streaming_compress_raw_fixed_tests`
- `zlib_streaming_compress_raw_stored_tests`
- `zlib_streaming_compress_stored_tests`
- `zlib_streaming_compression_api_tests`
- `zlib_streaming_compression_release_tests`
- `zlib_streaming_dictionary_tests`
- `zlib_streaming_equivalence_tests`
- `zlib_streaming_file_tests`
- `zlib_streaming_finish_tests`
- `zlib_streaming_gzip_metadata_tests`
- `zlib_streaming_gzip_tests`
- `zlib_streaming_inflate_dynamic_tests`
- `zlib_streaming_inflate_fixed_tests`
- `zlib_streaming_inflate_stored_tests`
- `zlib_streaming_lifecycle_tests`
- `zlib_streaming_raw_deflate_tests`
- `zlib_wrapper_tests`
- `zlib_wrapper_mode_conformance_tests`
- `zlib_zip_external_codec_tests`

`tests/src/tests.adb` loads `All_Suites`, which loads `Zlib_Suite`.
`tests/src/zlib_suite.adb` must register every test package, including `zlib_raw_cross_wrapper_conformance_tests` and `zlib_raw_release_tests`.
`tools/bin/check_all` enforces that every `tests/src/zlib_*_tests.ads` package
has a matching body, registers at least one AUnit routine, is both withed and
added to `Zlib_Suite`, and is listed in this inventory. It also rejects orphan
`zlib_*_tests.adb` bodies without specs and stale inventory bullets for removed
or renamed test packages, so test coverage cannot silently disappear from the
release path or remain overstated in the docs.

`zlib_streaming_compression_api_tests` verifies compression filter lifecycle,
reset, open/closed state, out-parameter initialization, and unsupported
configuration errors. `zlib_streaming_compress_stored_tests`, `zlib_streaming_compress_fixed_tests`,
and `zlib_streaming_compress_dynamic_tests` verify the zlib streaming
compressors, including small buffers, byte-sized chunks, finalization, direct
Adler-32 footer validation, inflate roundtrips, large-block splitting,
No_Flush finalization rules, and unsupported header combinations.

## Release contract checks

The release contract tests simulate an external consumer using only:

```ada
with Zlib;
```

They exercise the one-shot API, streaming inflate API, streaming compression
API, public enums, public exceptions, and `Status_Image`. They must not depend on internal packages such as `Zlib.Bits`,
`Zlib.Bit_Writer`, `Zlib.Deflate_Tables`,
`Zlib.Dynamic_Compress`, `Zlib.Fixed_Compress`, `Zlib.Huffman`,
`Zlib.Huffman_Builder`, `Zlib.Raw_Inflate`, `Zlib.Sliding_Window`,
`Zlib.Stream_Bits`, `Zlib.Stream_Inflate`, or `Zlib.Wrapper`. The streaming compression release-hardening suite keeps an external-style compression contract so that public root visibility remains covered when streaming compression changes.

## Fixture policy

Regression and interoperability fixtures are fixed byte vectors stored in Ada
tests. The test suite must not generate fixtures with Python or require system
`zlib` at runtime. External tool comparisons may be added as optional manual
checks, but normal release tests must remain Ada-only and deterministic.

## Performance-regression tests

`Zlib_Performance_Regression_Tests` is intentionally correctness-oriented. It
uses large compressed fixtures, tiny streaming input/output buffers, and a stored
stream larger than the 32 KiB Deflate history window to catch behavior changes
from internal optimization work. These tests must not assert wall-clock timing.

Optional benchmark executables live under `tools/` and are built with
`alr exec -- gprbuild -P tools/tools.gpr`; they are for local smoke measurements only.

## Conformance suites

The release-hardening suites include:

- `zlib_fixture_data`: frozen hardcoded fixtures; no runtime generation and no
  dependency on system zlib;
- `zlib_wrapper_mode_conformance_tests`: one-shot default auto-detection and
  strict concrete wrapper-mode behavior;
- `zlib_cross_api_equivalence_tests`: one-shot, streaming, chunk matrix, and
  zlib file API equivalence;
- `zlib_malformed_conformance_tests`: malformed/truncated zlib, gzip, and raw
  Deflate matrix;
- `zlib_compression_conformance_tests`: deterministic zlib-wrapped compression
  output and Adler validation;
- `zlib_consumer_fixture_tests`: `version`- and `HttpClient`-shaped regression
  fixtures without importing those crates;
- `zlib_streaming_compression_release_tests`: final streaming compression
  release-hardening matrix for large payloads, one-byte buffers, repeated-run
  determinism, cross-API semantic equivalence, trailer endian/checksum checks,
  wrong-wrapper rejection, cleanup behavior, and public-root API use.


## Streaming compression conformance matrix

`zlib_streaming_compress_conformance_tests` is the cross-wrapper streaming compression matrix. It covers:

- `Zlib_Header`, `Default`, and `GZip`;
- `Stored`, `Fixed`, `Dynamic`, and `Auto`;
- empty, small text, Git-shaped, binary, repeated, and block-sized-or-larger payload fixtures;
- deterministic output for repeated runs with identical chunking;
- one-byte input/output buffers and full-buffer chunking;
- strict zlib-vs-gzip-vs-raw wrapper failure behavior;
- `Raw_Deflate` compression behavior for Stored, Fixed, Dynamic, and Auto.

The suite is Ada-only. Fixtures are constants in the test package or in `zlib_fixture_data`; there is no runtime Python generation and no dependency on a system zlib library.

## Final streaming compression suites

The completed streaming compression implementation is covered by these suites:

- `zlib_streaming_compression_api_tests`
- `zlib_streaming_compress_stored_tests`
- `zlib_streaming_compress_fixed_tests`
- `zlib_streaming_compress_dynamic_tests`
- `zlib_streaming_compress_gzip_tests`
- `zlib_streaming_compress_auto_tests`
- `zlib_streaming_compress_lifecycle_tests`
- `zlib_streaming_compress_finish_tests`
- `zlib_streaming_compress_bounds_tests`
- `zlib_streaming_compress_conformance_tests`
- `zlib_streaming_compression_release_tests`

Run the full test executable with:

```sh
cd tests && alr exec -- gprbuild -P tests.gpr
cd tests && ./bin/tests
```

The public examples and tools must compile, and the smoke test must exercise both zlib and gzip streaming compression output:

```sh
alr exec -- gprbuild -P examples/examples.gpr
alr exec -- gprbuild -P tools/tools.gpr
cd check_zlib && alr build && ./bin/check_zlib && cd ..
./tools/bin/smoke_test
tools/bin/check_all
```

## Raw cross-wrapper conformance tests

`zlib_raw_cross_wrapper_conformance_tests` is registered in the test suite. The suite covers the complete zlib/gzip/raw wrapper matrix across
`Stored`, `Fixed`, `Dynamic`, and `Auto`, using empty, short text, Git-shaped,
binary, repeated, and large multi-block payloads.

The suite asserts that:

- zlib output roundtrips only through `Inflate`/`Zlib_Header`;
- gzip output roundtrips only through `GZip`;
- raw Deflate output roundtrips only through `Raw_Deflate`;
- wrong-wrapper one-shot calls return a stable non-`Ok` status;
- wrong-wrapper streaming calls raise `Zlib_Error` and remain cleanup-safe;
- one-shot and streaming raw compression are byte-equivalent for matching input,
  mode, and chunking;
- raw `Stored`, `Fixed`, `Dynamic`, and `Auto` output remains deterministic under
  tiny input and output buffers.

## Raw release hardening tests

`zlib_raw_release_tests` proves that raw Deflate compression is release-ready without changing APIs, wrappers, algorithms, or lifecycle behavior. The suite covers large binary/repeated/Git-shaped payloads, payloads spanning many Deflate blocks, one-byte input and output buffers, alternating empty/non-empty input, many `Compress` and `Compress_Flush` calls before `Finish`, final-output draining, repeated-run determinism, one-shot versus streaming semantic equivalence, wrapper strictness, raw-output structure sanity, cleanup/failure lifecycle behavior, and external-style root-package use.

Raw release tests intentionally use deterministic Ada-generated payloads only. They do not shell out to Python or external compressors. The accepted equivalence contract for one-shot raw compression versus streaming raw compression is semantic equivalence: both outputs must inflate to the same payload, remain deterministic for fixed inputs/chunking, and remain wrapper-strict. Byte-identical output is not required unless a specific implementation path separately guarantees it.

## Raw Deflate compression test suites

Raw compression and wrapper separation are covered by these suites:

- `zlib_streaming_compress_raw_stored_tests`
- `zlib_streaming_compress_raw_fixed_tests`
- `zlib_streaming_compress_raw_dynamic_tests`
- `zlib_streaming_compress_raw_auto_tests`
- `zlib_deflate_raw_stored_tests`
- `zlib_deflate_raw_fixed_tests`
- `zlib_deflate_raw_dynamic_tests`
- `zlib_deflate_raw_auto_tests`
- `zlib_raw_cross_wrapper_conformance_tests`
- `zlib_raw_release_tests`
- `zlib_deflate_raw_bridge_tests`
- `zlib_zstd_tests`
- `zlib_bzip2_tests`

Standard test command:

```sh
cd tests && alr exec -- gprbuild -P tests.gpr
cd tests && ./bin/tests
```

Release verification also builds examples and tools and runs the smoke tests:

```sh
alr exec -- gprbuild -P examples/examples.gpr
alr exec -- gprbuild -P tools/tools.gpr
cd check_zlib && alr build && ./bin/check_zlib && cd ..
./tools/bin/smoke_test
tools/bin/check_all
```

## Gzip metadata coverage

Gzip metadata output is covered by `zlib_gzip_metadata_tests`,
`zlib_streaming_gzip_metadata_tests`, `examples/gzip_with_metadata.adb`, and the
`gzip_metadata_file` path in `tools/bin/smoke_test`. These checks prove that the
legacy minimal gzip header remains unchanged, metadata fields are emitted only
when requested, invalid NUL-containing metadata is rejected, trailer CRC32/ISIZE
remain payload-only, and streaming metadata output makes progress with one-byte
output buffers.

## Streaming file APIs

Bounded-memory file helpers are available for consumers that must process files without buffering the complete input or output in memory:

```ada
Inflate_File_Streaming
Deflate_File_Streaming
GZip_File_Streaming
Deflate_Raw_File_Streaming
```

The one-shot convenience file APIs remain available. The `*_File_Streaming` APIs open input and output files, process fixed-size internal chunks, preserve binary data including NUL and high-byte values, and close files on both success and failure. They support the same wrapper separation used elsewhere: zlib, gzip, and raw Deflate are selected explicitly where applicable.

Dictionary-aware zlib file streaming is covered by tests for `Inflate_File_With_Dictionary_Streaming` and `Deflate_File_With_Dictionary_Streaming`, including wrong-dictionary failure behavior. These helpers are zlib-header-only because gzip and raw Deflate do not use the zlib FDICT wrapper mechanism.

## Benchmark tools

Ada-only benchmark/profiling tools live under `tools/`:

- `zlib_bench_inflate.adb`
- `zlib_bench_deflate.adb`
- `zlib_bench_gzip.adb`
- `zlib_bench_raw.adb`
- `zlib_bench_matrix.adb`

They are optional command-line tools, not AUnit correctness tests. The release
checklist builds them through `tools/tools.gpr`, but `tools/bin/check_all`
does not make timing assertions. Compression benchmarks verify roundtrips by
default unless `--no-verify` is supplied.

Compression benchmarks support file input, deterministic synthetic input,
wrapper selection, exact mode or broad level selection, input/output chunk sizes,
and repeat counts. Supplying both `--mode` and `--level` is a usage error.
Inflate benchmarks require `--input FILE`, support explicit wrapper selection,
input/output chunk sizes, repeat counts, and optional `--expect-size` validation.

## Optional stock-7z interop check

`tools/bin/seven_zip_interop_check` is an optional interoperability lane. When
`7z` is on `PATH`, it creates a deterministic payload corpus, verifies native
Copy, Deflate, BZip2, LZMA, LZMA2, PPMd, BCJ+LZMA, Delta+LZMA, and, when stock
support is present, RISCV+LZMA archives with stock `7z`. It verifies matching
stock-created archives with the native extractor, and also covers file-list
archives with directory entries, BCJ2, solid LZMA/LZMA2/PPMd archives,
AES-encrypted payloads, encrypted headers, and multi-volume archives both
directions. The encrypted cases also verify listing and wrong-password
rejection. It fails on any byte mismatch. When `7z` is missing, it prints a
skip message and exits successfully. When `7z` predates the RISC-V method, it
skips only the RISC-V stock cases. The final line reports executed check count
and skip count so optional coverage is visible in logs. It is built by
`tools/tools.gpr` but is not part of the mandatory pure-Ada release checklist.

## Deterministic fuzz smoke tests

The release includes `zlib_fuzz_smoke_tests` as bounded, deterministic
smoke/integration tests. They verify that deterministic fuzz helpers reproduce
identical summaries for identical target/seed/iteration inputs, that corrupted
streams fail predictably, and that small roundtrip, wrapper, metadata, dictionary,
compression-level, mutation, flush, tiny-buffer, and lifecycle fuzz passes do
not raise unexpected exceptions. They also verify the target-aware acceptance
policy used by the CLI fuzz drivers so semantic failures in roundtrip-style
targets fail CI. The suite also replays the small ASCII-hex fixtures under
`tests/fuzz_corpus/` through the public wrapper APIs.

Heavy fuzzing remains manual and tool-driven. `tools/bin/check_all` only runs
short deterministic smoke passes after the ordinary build, test, example, and
Ada smoke-test checklist has already passed. Use `alr exec -- gprbuild -P tools/tools.gpr`
to build the `tools/fuzz/` drivers for manual hardening passes, including
`fuzz_compress_levels`, `fuzz_mutation`, `fuzz_flush`, `fuzz_lifecycle`, and
`fuzz_tiny_buffers`.

## Documentation completeness checks

Documentation is part of the release surface. `check_zlib` verifies the required docs/API support-level contract, and a completeness pass should verify:

- every Markdown link points to an existing file or heading;
- `README.md` lists every document in `docs/` that is part of the maintained user-facing set;
- `examples/README.md` lists every example built by `examples/examples.gpr`;
- `tools/README.md` and `docs/FUZZING.md` list every executable built by `tools/tools.gpr`;
- fuzz driver names are consistent across `tools/tools.gpr`, `tools/bin/check_all`, `tools/README.md`,
  and `docs/FUZZING.md`;
- public API changes in `src/zlib.ads` are reflected in `docs/API.md` and the topic-specific document;
- public functions and procedures in `src/zlib.ads` have GNATdoc `@param` tags for every formal parameter
  and `@return` tags for function results;
- new test suites or release gates are reflected in this file and, when relevant, in `docs/MAINTENANCE.md`.

`tools/bin/check_all` enforces root public-spec GNATdoc tag completeness. GNATdoc covers declaration-level
reference text; the Markdown files explain release policy, wrapper behavior, workflows, and maintenance rules.


## AI discoverability checks

A release/completeness pass should verify that:

- `README.md` lists all maintained documents under `docs/`;
- `llms.txt` names the current public API families and validation commands;
- `AGENTS.md` matches the current repository maintenance rules;
- `docs/AI_GUIDE.md` and `docs/API_CHEATSHEET.md` do not recommend child
  packages for consumer use;
- examples referenced by AI-facing docs exist and are listed in
  `examples/examples.gpr`;
- wrapper rules in AI-facing docs match `src/zlib.ads` and wrapper-specific
  documentation.
