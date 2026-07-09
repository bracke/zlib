# Full 7z Support — Implementation Plan

Status: living document. Goal: **complete, pure-Ada 7z encode and decode** —
decode any standard `.7z` archive that `7z`/p7zip can produce, and produce
archives they can read back, with no external codec libraries and no shelling
out to a local `7z`.

This plan is grounded in the current implementation. The public 7z API remains
in `src/zlib.ads`, while most writer/listing/filesystem orchestration and shared
container helpers now live in internal child packages. The root body still owns
public wrapper glue, codec callbacks that depend on root Deflate/LZMA entry
points, and the large native 7z folder decode paths. Encoded-header recovery is
shared by extraction and listing through `Zlib.Seven_Zip_Header_Reading`.
Passwords are threaded through read/list/extract callbacks as explicit decode
context.

## Where the 7z code lives today

| Concern | Location |
|---|---|
| Public contract and compatibility wrappers | `src/zlib.ads`, `src/zlib.adb` |
| Method IDs, descriptors, arity, and classification | `Zlib.Seven_Zip_Methods` |
| Coder descriptor emission and writer properties | `Zlib.Seven_Zip_Coders` |
| Container header/envelope construction | `Zlib.Seven_Zip_Container` |
| Method-graph stream arithmetic and validation | `Zlib.Seven_Zip_Graphs` |
| 7z UInt64 and little-endian scalar helpers | `Zlib.Seven_Zip_Numbers` |
| Safe entry and filesystem path validation | `Zlib.Seven_Zip_Paths` |
| FilesInfo parsing, target lookup, metadata images, and source metadata | `Zlib.Seven_Zip_Properties` |
| Branch filters, Delta, and BCJ2 transforms | `Zlib.Seven_Zip_Filters` |
| AES-256/SHA-256/KDF/CBC support | `Zlib.Seven_Zip_AES` |
| PPMd7 codec | `Zlib.PPMd7` |
| Single-entry codec and method-graph writers | `Zlib.Seven_Zip_Codec_Writing` |
| File and file-list writer orchestration | `Zlib.Seven_Zip_File_Writing` |
| BCJ2 writer orchestration | `Zlib.Seven_Zip_BCJ2_Writing` |
| Encrypted writer orchestration | `Zlib.Seven_Zip_Encrypted_Writing` |
| Filtered writer orchestration | `Zlib.Seven_Zip_Filtered_Writing` |
| Header-encrypted writer orchestration | `Zlib.Seven_Zip_Header_Encryption` |
| Encoded-header read recovery and normalization | `Zlib.Seven_Zip_Header_Reading` |
| Read-side folder graph analysis and linear chain decode; BCJ2 graph decode; PPMd fallback; substream slicing | `Zlib.Seven_Zip_Folder_Decoding` |
| Filesystem extraction staging and metadata application | `Zlib.Seven_Zip_File_Extraction` |
| Split-volume read/write/extract orchestration | `Zlib.Seven_Zip_Volumes` |
| Archive listing dispatch | `Zlib.Archive_Listing` |
| Archive directory extraction dispatch | `Zlib.Archive_Directory_Extraction` |
| Native 7z folder decode loops | `src/zlib.adb` |

### Remaining architecture debt

The largest remaining 7z cleanup is native read-side orchestration in
`src/zlib.adb`. Listing dispatch has moved into `Zlib.Seven_Zip_Listing`;
encoded-header recovery is shared through `Zlib.Seven_Zip_Header_Reading`; and
folder graph analysis, bind-pair mapping, linear coder-chain execution, BCJ2 graph decode, PPMd fallback
policy, and solid substream slicing are shared through `Zlib.Seven_Zip_Folder_Decoding`. password handling now uses explicit decode context
instead of root-global state. FilesInfo target-entry walking is shared through
`Zlib.Seven_Zip_Properties`. The root body still carries StreamsInfo section
ordering and codec callback dispatch.

Future cleanup should extract these pieces without changing the public root API:

- Broader reuse between `Zlib.Seven_Zip_Listing` and extraction after
  StreamsInfo and folder metadata are parsed.

Replace remaining decode dispatch chains with descriptors where practical. New
codecs should become table entries plus a package, not surgery on a root-body
procedure.

## Standard 7z method IDs (reference)

Classic 4-byte BCJ family (what this repo already uses for x86/BCJ2):

| ID | Filter |
|---|---|
| `03 03 01 03` | BCJ x86 |
| `03 03 02 05` | PPC (big-endian) |
| `03 03 04 01` | IA-64 |
| `03 03 05 01` | ARM (little-endian) |
| `03 03 07 01` | ARMT (Thumb) |
| `03 03 08 05` | SPARC |
| `03 03 01 1B` | BCJ2 |

Compact single-byte IDs (7-Zip 21.x+, also used by xz):

| ID | Filter |
|---|---|
| `04` | x86 | `05` PPC | `06` IA-64 | `07` ARM | `08` ARMT | `09` SPARC | `0A` ARM64 | `0B` RISC-V |

Core codecs: `00` Copy, `21` LZMA2, `03 01 01` LZMA, `03 04 01` PPMd,
`04 01 08` Deflate, `04 02 02` BZip2. Crypto: `06 F1 07 01` AES-256 + SHA-256.

A complete decoder must recognize **both** the classic 4-byte and the compact
1-byte forms for each filter.

## Milestones (ordered)

Ordering favors: (1) interop wins that expand the set of real archives we can
read, (2) self-contained low-risk work first, (3) the hard codec/crypto work
last. Each milestone ends with round-trip tests and, where a reference `7z` is
available in CI, cross-tool interop tests.

### M1 — Full branch-filter family (encode + decode) — DONE

Each branch filter is a deterministic byte transform with a known algorithm
(LZMA SDK `Bra*.c` / xz). No entropy coding, no allocation.

- Internal package `Zlib.Seven_Zip_Filters` provides `Branch_Convert`
  (encode/decode) for x86 (full masked BCJ), ARM, ARMT, ARM64, PPC, SPARC,
  IA-64, RISC-V JAL, plus Delta. Each pair is exact inverses; functions return
  1-based arrays (codebase convention).
- Method-IDs are wired into the decode parser (classic 4-byte **and** compact
  1-byte forms), every decode dispatch site, the BCJ2 pre-coder case, and
  writer coder emission. The buggy simplified inline x86 decoder was replaced
  by the masked converter.
- Tested by round-trips, interop known-answer vectors, and frozen stock-7z
  fixtures; **validated against stock 7-Zip 23.01** (all filters × multiple
  binaries/sizes decode byte-identically).
- RISC-V method `0B` and the 32-bit JAL converter are implemented and covered
  by local round-trip and known-answer tests. Stock RISC-V archive validation
  is wired into `tools/bin/seven_zip_interop_check` and runs when a 7-Zip 24.x+
  binary is available; this workstation has 23.01, which predates the filter.

### M2 — Writer multi-coder folders (filter + codec with bind pairs) — DONE

The writer emits public single-entry compressed filtered archives through
`Seven_Zip_Filtered`. It applies one supported branch/Delta pre-filter,
compresses the filtered bytes with Deflate, BZip2, LZMA, LZMA2, or PPMd, and
emits the two-coder folder, bind pair, ordered packed stream, sizes, and CRCs.
The lower-level `Seven_Zip_Method_Graph` writer emits arbitrary supported
non-encrypted single-entry 7z method graph containers from caller-supplied
packed stream bytes, coders, bind pairs, packed stream indexes, stream sizes,
and the final unpacked CRC. It is a container writer; callers remain
responsible for producing packed bytes that match the graph.

- Tested by building BCJ+LZMA and Delta+Deflate archives and reading them back
  with the native extractor's bounded linear filter-chain path.
- Tested by building an explicit BCJ+Delta+Deflate graph archive from
  pre-packed bytes and reading it back with the native extractor.
- BCJ2 stored archive writing remains covered by the separate `Seven_Zip_BCJ2`
  writer.

### M3 — General PPMd7 (variant H) codec — DONE (real, bit-exact)

The old PPMd was fake on **both** sides (pattern-matching encoders + canned
decode vectors). It is now a real, clean-room PPMd7 in package **`Zlib.PPMd7`**
(`src/zlib-ppmd7.{ads,adb}`): byte-pool sub-allocator, suffix-context model
(CreateSuccessors/UpdateModel/Rescale/Update1_0/1/2/Bin), SEE + binary contexts,
and the 7z range decoder **and** encoder. `Compress`/`Decompress` are the API.

- **Validated bit-exact against stock 7-Zip 23.01** (no reference source —
  black-box debugged): our encoder output is byte-identical to stock's pack, and
  our decoder reads stock streams, across 500 B–300 KB, text/binary/patterned,
  orders 2–32.
- **Wired into the container paths**: `Extract_Seven_Zip` decodes arbitrary
  stock PPMd folders and BCJ2 main-chain PPMd pre-coders; `Seven_Zip_PPMd`
  writes archives stock `7z` reads. Defaults now match stock (order 6, 16 MB).
- 845/845 suite green; end-to-end interop both ways verified.

Fully complete: `Glue_Free_Blocks` (the memory-pressure coalescing path) is
implemented and validated bit-exact vs stock on 1–2 MB inputs at 1 MB `mem`,
orders 4–32, both directions. The ~8500 lines of fake PPMd code (pattern
encoders + canned decoder) and the historic local decode shims have been
deleted; container paths call `Zlib.PPMd7.Compress` and
`Zlib.PPMd7.Decompress` directly.

### M3.5 — LZMA/LZMA2 standard-compliance (CORRECTNESS — mostly DONE)

**Status: implemented.** The codec is now standard-compliant: the encoder
emits matched literals; all decoders use `Use_Matched_Literals => True,
Initial_Rep_Distance => 1`; the LZMA2 `Ctx` decoder gained matched literals and
standard rep init. Verified bidirectional interop — we decode stock `7z` plain
LZMA and LZMA2 (to 60 KB across varied content), and stock `7z` reads and
extracts our LZMA archives. Locked in by
`tests/src/zlib_seven_zip_lzma_interop_tests.adb`. Filter+LZMA *chains* are also
fixed: a separate bind-pair packed-coder bug (the Generic bind mapping was
swapped vs the 7z `(InIndex, OutIndex)` format) made the extractor apply the
branch filter to the LZMA input; corrected so all stock filter+LZMA chains
(ARM/ARMT/PPC/SPARC/IA64, Delta/ARM + Deflate) extract correctly.

**Original finding (M1 validation).** Our LZMA codec was internally
self-consistent but **non-standard**, so stock-`7z` LZMA archives failed to
extract (`Unsupported_Method`) and our LZMA archives were not readable by stock
`7z`. Two specific deviations (now fixed):

1. **Initial rep distances.** Fresh streams init rep0..rep3 to 0. Standard LZMA's
   initial rep means distance 1; in this decoder's 1-based distance convention
   that must be **1**. Stock's early short-rep uses rep0=0 and the decoder
   rejects `Distance = 0` (`Decode_LZMA_Payload`, ~zlib.adb:4791).
2. **Matched-literal coding.** Literals after a match (state ≥ 7) must use the
   match-byte-conditioned literal model. The 7z folder path disables it
   (`Use_Matched_Literals => False`); standard requires it.

Telling inconsistency: the 7z **encoded-header** LZMA decoder already passes the
standard `(Use_Matched_Literals => True, Initial_Rep_Distance => 1)` (~11986,
~11999), while the folder-payload `LZMA_Decode_Raw` passes `(False, 0)` to pair
with our non-standard **encoder** (`LZMA_Encode_Bounded`, ~4163, which emits no
matched literals).

Fix (touches encoder + decoders; **changes emitted bytes**):
- make `LZMA_Encode_Bounded` emit matched literals after matches and use standard
  rep init/handling;
- flip `LZMA_Decode_Raw` to `(Use_Matched_Literals => True, Initial_Rep_Distance => 1)`;
- apply the same to the LZMA2 codec (the `Ctx`-based decoder ~12058 also lacks
  matched literals);
- verify: stock `7z` reads our archives and we read stock archives; roundtrip +
  full suite stay green; regenerate any frozen LZMA byte fixtures.

This is a prerequisite for any real LZMA interop and should land before M4.

### M4 — Competitive LZMA / LZMA2 encoder — DONE (matches stock)

`LZMA_Encode_Bounded` uses an **HC3 hash-chain** match finder (matches extend to
the LZMA maximum of 273) feeding a **price-based optimal parser** (M4+): a
forward shortest-path DP over 8 KB segments that carries `State` + the four
repeat distances per offset and prices every literal/match/rep against an
integer LZMA-SDK bit-price table. The parser includes one-byte `rep0` short
reps for interrupted repeats. Direct, filtered, file-list, solid, encrypted
LZMA 7z output, native ZIP LZMA payloads, and compressed LZMA2 chunks try a
bounded set of valid `lc`/`lp`/`pb` property candidates and write the winning
property byte into the coder metadata or chunk header. Long matches
(≥ nice-len) are taken whole for speed. Parser passes start at 8 KB and extend
up to 32 KB when a nice-length match would otherwise cross the pass boundary,
matching the intended flush-at-long-match behavior while keeping memory bounded.
Emission
reuses the proven range-coder routines, so a misprice only costs ratio, never
correctness. Output stays standard — stock `7z` reads it and our decoder reads
it; LZMA2 shares the encoder.

Result vs stock `7z` LZMA: **within +1.9% everywhere** (most under +1%), and it
**beats** stock on text (−1%) and highly-repetitive data (−16%). Throughput
≈0.6 s per 300 KB. (The pre-optimal greedy+lazy+rep encoder was +3.4..11%.)

Per-input `lc`/`lp`/`pb` tuning already covers direct, filtered, file-list,
solid, encrypted, ZIP LZMA, and compressed LZMA2 writer paths.

### M5 — Solid compression — DONE

`Seven_Zip_Compressed_Files_Internal` gained a solid mode: it concatenates all
ordinary-file payloads, compresses them as a single folder, and emits
`SubStreamsInfo` (per-file substream sizes + CRCs). Public entry points
`Seven_Zip_{LZMA,LZMA2,PPMd}_Solid_Files`. The decoder already handled solid
substreams.

Also fixed a pre-existing bug in the shared multi-file metadata writer (the
`WinAttributes` property omitted its `External` byte), which had made **all**
multi-file archives — solid and non-solid — unreadable by stock `7z`.

Validated both directions vs stock `7z`: our solid archives extract in stock and
round-trip in our extractor (LZMA/LZMA2/PPMd, 5–8 files); the ratio win is large
on many similar files (e.g. 1.3 KB solid vs 5.4 KB non-solid). 845/845 green.

### M6 — Encryption (AES-256 + SHA-256) — DONE

7zAES (`06 F1 07 01`) via the `../cryptolib` crate (AES-256-CBC + SHA-256).

- New `Zlib.Seven_Zip_AES`: 7z key derivation (iterated SHA-256 over salt +
  UTF-16LE password + 8-byte LE counter, `2**NumCyclesPower` rounds) and
  AES-256-CBC encrypt/decrypt. Validated bit-exact vs stock (decrypting a
  stock pack reproduces the exact inner stream).
- **Decode**: the AES coder is parsed (`06F10701` + control/salt/IV props),
  the requested password drives key derivation, and the decrypted pack (block
  padding dropped to the coder unpack size) feeds the inner coder.
  `Extract_Seven_Zip (.., Password, ..)` overload. Works for AES+LZMA /
  AES+LZMA2 data **and** encrypted headers (`mhe=on`), various sizes.
- **Encode**: `Seven_Zip_LZMA_Encrypted` builds an `[AES -> LZMA]` folder that
  stock `7z` extracts with the password; wrong passwords are rejected.
- Tested by an in-memory round-trip + wrong-password regression, and validated
  against stock `7z` in both directions.

Refinements also done: CSPRNG IV (`Random_IV`); encrypted solid multi-file
writing for LZMA/LZMA2/PPMd (`Seven_Zip_*_Encrypted_Files`); encrypted-header
**writing** (`Encrypt_Seven_Zip_Header`, mhe=on) that composes with any writer;
and encrypted-header **reading** (`Decode_AES_Encoded_Header`, both the
AES-only and AES+LZMA encoded-header layouts). All validated both ways vs
stock 7-Zip.

### M7 — Multi-volume (split) archives — DONE

- Read/write `.7z.001`, `.7z.002`, … splitting the stream at volume boundaries.
- Tests: round-trip across volume boundaries; read stock multi-volume sets.

## Cross-cutting: interop test harness

An optional stock-7z lane is implemented as `tools/bin/seven_zip_interop_check`.
When a real `7z`/`p7zip` binary is present, it:

- encodes Copy, Deflate, BZip2, LZMA, LZMA2, and PPMd with us, extracts them
  with stock `7z`, and byte-compares empty, code-shaped, text-like, and large
  deterministic payloads;
- encodes the same six methods with stock `7z`, extracts them with us, and
  byte-compares the same payload corpus;
- exercises non-solid multi-entry file-list archives with files plus no-stream
  directory entries for all six methods in both directions;
- exercises BCJ+LZMA and Delta+LZMA filtered archives in both directions across
  non-empty corpus variants;
- probes for the stock `RISCV` method and, when available, exercises
  RISCV+LZMA filtered archives in both directions across non-empty corpus
  variants;
- exercises BCJ2 archives in both directions;
- exercises solid LZMA, LZMA2, and PPMd multi-file archives in both directions;
- exercises AES-encrypted LZMA payloads and encrypted headers in both
  directions, including encrypted-header listing and wrong-password rejection;
- exercises multi-volume archives in both directions.

It skips successfully when `7z` is absent, and skips only the RISC-V stock
cases when the present `7z` predates that method, so the default pure-Ada
build/test path stays dependency-free.

## Definition of done

Full 7z support is reached when, for the standard method set (Copy, Deflate,
BZip2, LZMA, LZMA2, PPMd, all branch filters, Delta, BCJ2, AES-256), with solid
and multi-volume layouts:

- we decode every archive stock `7z` produces, and
- stock `7z` decodes every archive we produce,

across the interop corpus, in pure Ada, with the existing deterministic
status-code / exception contracts preserved.
