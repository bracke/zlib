# Roadmap

`Zlib` is at version `0.1.0`. The intended initial stable surface is the
public root-package API in `src/zlib.ads`, plus the documented examples, tools,
tests, and deterministic fuzzing infrastructure shipped in this repository.

## Intended stable baseline

The stable consumer surface includes:

- root package `Zlib` as the public API boundary;
- one-shot zlib inflate through `Inflate`;
- explicit one-shot zlib, gzip, and raw Deflate inflate through
  `Inflate_With_Header`;
- raw Deflate convenience inflate through `Inflate_Raw`;
- streaming zlib, gzip, and raw Deflate inflate through `Header_Type`;
- stored, fixed-Huffman, and dynamic-Huffman Deflate decode;
- zlib Adler-32 validation and gzip CRC32/ISIZE validation;
- zlib, gzip, and raw Deflate compression through stored, fixed-Huffman,
  dynamic-Huffman, Auto, and level-selected output paths;
- compression levels 0 through 9 as deterministic broad effort policies;
- explicit gzip metadata output through `GZip_Metadata`, including FEXTRA,
  FNAME, FCOMMENT, MTIME, OS, XFL, and FHCRC;
- implicit multi-member gzip input and explicit strict single-member gzip input
  through `GZip_Member_Mode => Single_Member`;
- zlib preset dictionary compression and inflate APIs;
- one-shot and streaming file helpers, including zlib preset-dictionary file helpers;
- internal Adler-32 and CRC32 wrapper/archive validation through CryptoLib.Checksums;
- examples, command-line tools, bounded deterministic fuzz drivers, and
  AI-facing discoverability documents.

Wrapper behavior is explicit for concrete modes, with inflate auto-detection on
the default path. `Inflate`, `Inflate_Auto`, `Inflate_With_Header` with
`Header => Default`, and streaming `Inflate_Init` with `Header => Default`
discriminate zlib, gzip, and raw Deflate. Gzip input accepts concatenated
members unless `GZip_Mode => Single_Member` is requested. `Inflate_Raw` is
raw-only, concrete `Inflate_With_Header` and `Inflate_Init` modes remain
wrapper-strict, and streaming compression `Default` means `Zlib_Header`.
`Deflate_*` APIs emit zlib-wrapped streams, `GZip*` APIs emit gzip-wrapped
streams, and `Deflate_Raw*` APIs emit raw Deflate bytes only.

## Maintenance policy

Maintenance should be conservative. Public profiles, enum values,
exception names, status names, and wrapper semantics should remain stable unless
a later major version deliberately changes the contract.

Internal implementation changes should prefer behavioral tests over byte-exact
fixture rewrites. Byte identity should only be asserted where the public API or a
fixture explicitly promises it. The ordinary validation gate is:

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

## Primary goal: full 7z encode and decode

The headline goal of the crate is **complete, pure-Ada 7z support**: decode any
standard `.7z` archive that `7z`/p7zip can produce, and produce archives they
can read back, with no external codec libraries (AES uses the sibling
`../cryptolib` Ada crate). This goal is **substantially met** — per-milestone
status lives in `docs/SEVEN_ZIP_PLAN.md`.

Delivered and validated against stock 7-Zip in both directions:

- general PPMd7 (variant H) encoder and decoder, bit-exact, including the
  memory-pressure glue path;
- AES-256 payload encryption, encrypted headers (`mhe=on`) read **and** write,
  and password handling (SHA-256 key derivation) via `../cryptolib`;
- solid compression (one shared compressed stream across entries), including
  encrypted solid archives for LZMA / LZMA2 / PPMd;
- the branch-filter family on decode and encode — x86 masked BCJ, ARM, ARM64,
  ARMT, PPC, SPARC, IA-64, RISC-V JAL, plus Delta;
- a competitive LZMA/LZMA2 encoder with optimal (price-based) parsing;
- multi-volume (split) archives, read and write.

The BCJ2 encoder (`Seven_Zip_BCJ2`) is also done — the last decode-only codec —
producing stored `-m0=BCJ2` archives stock 7z reads.
`Seven_Zip_Filtered` writes public non-encrypted compressed filtered archives
with one branch/Delta pre-filter plus Deflate, BZip2, LZMA, LZMA2, or PPMd
as the terminal codec.
`Seven_Zip_Method_Graph` writes low-level single-entry non-encrypted method
graph containers from caller-supplied packed stream bytes, coders, bind pairs,
packed stream indexes, sizes, and the final unpacked CRC.

Remaining 7z work:

- **RISC-V stock validation execution** — the in-process JAL converter, method
  `0B` plumbing, and stock-interop lane are implemented. This workstation has
  7-Zip 23.01, so `tools/bin/seven_zip_interop_check` skips the RISC-V cases
  until it runs with a 24.x+ binary.

## Other future work

Possible future work must preserve the explicit-wrapper design unless a new
major version intentionally changes it. The current polish pass added optional
interop summary accounting, broader benchmark matrix reporting, replayed
deterministic fuzz corpus fixtures, and additional bounded compression-quality
tuning behind the existing level/mode APIs.

The following require explicit replanning as new public features:

- additional gzip member-policy changes;
- cryptographic hashes as a public general-purpose API (note: SHA-256 and AES
  are still implemented internally as required for 7z encryption — see
  `docs/SEVEN_ZIP_PLAN.md`);
- external runtime dependencies on system zlib, Python fixture generation, or C
  compression libraries (the full 7z goal is met in pure Ada, without them).
