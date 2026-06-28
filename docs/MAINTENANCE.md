# Zlib maintenance notes

`Zlib` is currently at development version `0.1.0-dev`. The root package is the
intended stable public maintenance contract. Maintenance work should prefer internal-only
refactors, test fixtures, and documentation over public API changes.

## Hot path packages

The performance-sensitive path is:

- `Zlib.Stream_Bits`: incremental byte/bit input buffering.
- `Zlib.Huffman`: canonical Huffman table construction and symbol decoding.
- `Zlib.Stream_Inflate`: streaming zlib/gzip wrapper state and Deflate state.
- `Zlib.Sliding_Window`: 32 KiB LZ77 history and pending-output queue.
- `Zlib.Checksums` and `Zlib.CRC32_Internal`: zlib Adler-32 and gzip CRC32/ISIZE checks.

The one-shot API now routes through the streaming engine. Changes to the
streaming engine therefore affect both public decode paths.

## Invariants that must not be broken

- Public root package profiles, enum values, exception names, and
  `Status_Image` strings should remain unchanged unless a release-contract test
  is deliberately updated.
- Deflate length/distance metadata must come from `Zlib.Deflate_Tables`.
- Huffman table construction must reject oversubscribed or empty trees
  deterministically.
- Streaming decode must not accept malformed streams that were previously
  rejected.
- Each emitted byte must enter the sliding-window history exactly once.
- LZ77 overlapping copies must read from the evolving history, not from a
  precomputed snapshot.
- Distance validation remains strict: distance 0, distance > 32 KiB, and
  distance beyond produced history are invalid.
- Output buffer size 1 is a supported correctness case.
- zlib Adler-32 and gzip CRC32/ISIZE trailer validation must remain exact.


## Internal compatibility-code policy

The public one-shot inflate path is routed through the streaming engine.
`Zlib.Raw_Inflate`, `Zlib.Bits`, and `Zlib.Wrapper` are retained as internal,
non-consumer compatibility/maintenance packages. They must not be used by new
public code or downstream crates. Remove them only when the full release
checklist proves that removal is behavior-neutral and the remaining tests still
cover the same malformed-input and wrapper-boundary behavior.

## Allocation policy

Initial filter setup may allocate owned filter state. Dynamic Huffman table
construction may use the table storage already owned by the decoder. Repeated
`Translate` calls should avoid heap allocation in normal byte translation.
`Zlib.Stream_Bits` uses fixed internal storage and compacts only when needed,
rather than allocating while each consumed byte advances.

## Optional benchmarks

The benchmark programs are simple smoke tools, not pass/fail tests:

```sh
alr exec -- gprbuild -P tools/tools.gpr
./tools/bin/zlib_bench_inflate --input payload.z --wrapper zlib
./tools/bin/zlib_bench_deflate --pattern text-like --size 1048576 --wrapper zlib --mode auto
```

They report input/output bytes, compressed bytes where applicable, ratio,
elapsed time, throughput, wrapper, compression mode or level, input chunk size,
and output buffer size. Do not gate correctness on wall-clock timing.
Use them to compare local before/after changes on the same machine and build
configuration.

## Release check

Before release, run:

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

If a platform lacks Alire, run the direct `gprbuild` commands at minimum.

Generate consumer-facing GNATdoc output for the public root package with:

```sh
alr exec -- gnatdoc -P docs/public_docs.gpr --style gnat --generate public --backend html --warnings -O docs/html
```

The full `zlib.gpr` GNATdoc run also processes internal child packages and may
warn about undocumented internal implementation entities. The `docs/public_docs.gpr`
project intentionally documents only the supported consumer API in `src/zlib.ads`.

## Streaming compression hardening gate

The final compression-side hardening gate is `zlib_streaming_compression_release_tests`.
It is intentionally broader than the earlier mode-specific streaming suites and must
remain registered in `Zlib_Suite`. It covers:

- large deterministic Ada-generated binary, repeated, and Git-shaped payloads;
- many one-byte input/output calls, alternating empty/non-empty input, repeated
  `No_Flush` drains, and `Finish` with pending input;
- byte-for-byte determinism for identical header/mode/input/chunking;
- semantic equivalence between one-shot and streaming zlib/gzip compression,
  without requiring byte-for-byte equality between APIs;
- zlib Adler-32 big-endian trailer checks and gzip CRC32/ISIZE little-endian
  trailer checks with one-byte output buffers;
- explicit `Compress_Stream_End` checks proving completion is reported only
  after the final trailer/output byte has been drained;
- strict wrapper rejection and raw-Deflate compression coverage;
- external-style use of only the public `Zlib` root package.

Do not weaken this suite to accommodate an internal refactor. If compression
policy intentionally changes, update the public documentation and add focused
replacement assertions before removing any existing release-hardening coverage.

## Raw Deflate validation checklist

Before release, run:

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

Confirm that raw examples and tools use only the public root `Zlib` API, that
`Deflate_Raw` output is not accepted by zlib/gzip inflate paths, and that
zlib/gzip behavior remains unchanged.


## Raw Deflate hardening

Raw Deflate compression is release-hardened by `zlib_raw_release_tests`, `zlib_raw_cross_wrapper_conformance_tests`, the raw examples, and the raw tools. The contract remains unchanged: `Deflate_*` APIs emit zlib-wrapped streams, `GZip*` APIs emit gzip-wrapped streams, `Deflate_Raw*` APIs emit raw Deflate blocks only, `Seven_Zip_Stored*` APIs emit Copy-coder `.7z` archives including header-only directory entries and solid stored file-list archives with no-stream directory entries, `Seven_Zip_Deflate*` APIs emit Deflate `.7z` archives, `Seven_Zip_BZip2*` APIs emit BZip2 `.7z` archives, `Seven_Zip_LZMA*` APIs emit LZMA `.7z` archives, `Seven_Zip_LZMA2*` APIs emit LZMA2 `.7z` archives, `Extract_Seven_Zip*` APIs extract those supported native 7z layouts plus native PPMd empty/repeated-symbol/root-symbol/periodic-prefix, stock-7z multi-block streams with LZMA encoded headers, stock-7z no-stream empty-file entries, stock-7z BCJ+PPMd filter chains, and BCJ2 graphs with Copy, PPMd, or supported main pre-coders, `Seven_Zip_PPMd`, `Seven_Zip_PPMd_File`, and `Seven_Zip_PPMd_Files` emit native PPMd 7z archives for this crate's extractor without calling local `7z`, while `Seven_Zip_External_File` and `Extract_Seven_Zip_External_File` are compatibility placeholders that fail closed without invoking local `7z`, `ZIP`/`ZIP_File`/`ZIP_Files` emit ZIP archives, `Inflate` is zlib-wrapper-only, `Inflate_With_Header` performs explicit wrapper selection, and `Inflate_Auto` is the convenience wrapper-discriminating inflate API. `Auto` remains deterministic and block-local; the library still has no general-purpose 7z codec stack or zlib-compatible compression-ratio promise.

## Maintaining Auto block selection

When changing compression internals, keep `Zlib.Block_Chooser` and the actual block emitters in sync. Stored scoring must include block header bits, alignment padding, LEN/NLEN, and payload bytes. Fixed scoring must include EOB and all match extra bits. Dynamic scoring must include HLIT/HDIST/HCLEN, code-length-code lengths, encoded code lengths, token payload, extra bits, EOB, and padding.

Do not include zlib, gzip, or raw wrapper overhead in candidate scores. Do not optimize explicit `Stored`, `Fixed`, or `Dynamic` modes through Auto. Tests in `zlib_block_chooser_tests` cover scorer rules and tie-breaking; tests in `zlib_auto_block_selection_tests` cover wrapper roundtrips, level policy, determinism, and flush behavior.

## Lazy matching maintenance notes

Lazy matching is an internal compression-quality improvement, not a public API
change. Maintenance work must preserve these invariants:

- level 0 and stored mode never use the matcher;
- levels 2 and 3 remain greedy unless the documentation and tests are updated;
- levels 4 through 7 use conservative lazy matching;
- levels 8 and 9 use bounded block-local optimal parsing;
- lazy lookahead must not cross block or flush boundaries;
- emitted matches must remain length 3 .. 258 and distance 1 .. 32768;
- repeated runs with the same input, level, mode, and chunking must produce the
  same token stream and compressed bytes.

Avoid byte-exact fixture updates unless byte identity has explicitly been frozen
for that fixture. Prefer roundtrip, validity, determinism, and non-regression
coverage for matcher changes.

## Fuzzing maintenance

Fuzzing failures must be treated as reproducible defects. Preserve the target,
seed, iteration count, and any printed configuration. Add a minimized regression
fixture to the normal AUnit suite when a fuzzer exposes a real parser,
state-machine, wrapper, dictionary, metadata, or flush bug.

Do not make fuzzing nondeterministic. The fuzz generator is deliberately
simple and fixed so failures can be reproduced without an external service or
coverage-guided fuzzing runtime. System zlib comparison, when added or used, must
remain optional and must not become a normal build dependency.

## Documentation maintenance

When adding or changing public behavior, update documentation in the same change set. The minimum expected
updates are:

- `src/zlib.ads` GNATdoc comments for declaration-level reference text;
- `docs/QUICKSTART.md` for first-use workflow, build commands, or primary public examples;
- `docs/API.md` for public root-package API additions or signature changes;
- the topic document for the affected area, such as `docs/GZIP.md`, `docs/COMPRESSION.md`,
  `docs/STREAMING.md`, `docs/STREAMING_COMPRESSION.md`, `docs/RAW_DEFLATE.md`, or `docs/FUZZING.md`;
- `docs/TESTING.md` for new suites, release gates, fuzz smoke checks, or fixture policy;
- `tools/README.md` for new command-line tools;
- `examples/README.md` for new examples;
- `README.md` when the top-level capability, document, example, or tool inventory changes;
- `docs/ROADMAP.md` when the maintenance baseline or future-work boundary changes.

Keep documentation deterministic and implementation-specific. Avoid vague claims such as "best compression" or
"fully compatible" unless the test suite enforces that exact contract.


## AI discoverability maintenance

Keep `llms.txt`, `AGENTS.md`, `docs/AI_GUIDE.md`, and
`docs/API_CHEATSHEET.md` synchronized with public behavior. Any change to public
entry points, wrapper policy, validation commands, example policy, or internal
package boundaries must update these files in the same change set.

AI-facing docs are not a second API contract. They must summarize and point to
`src/zlib.ads`, which remains the source of truth for declarations and GNATdoc
comments.
