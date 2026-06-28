# Full 7z Support — Implementation Plan

Status: living document. Goal: **complete, pure-Ada 7z encode and decode** —
decode any standard `.7z` archive that `7z`/p7zip can produce, and produce
archives they can read back, with no external codec libraries and no shelling
out to a local `7z`.

This plan is grounded in the current implementation, which lives almost entirely
in the monolithic `src/zlib.adb` (~23k lines). Line anchors below are accurate as
of this writing; treat them as starting points, not guarantees.

## Where the 7z code lives today

| Concern | Location (`src/zlib.adb`) |
|---|---|
| Coder method enum (`Seven_Zip_Coder_Method`) | grep `Seven_Zip_Coder_Method` |
| Writer coder-metadata emission (`Append_Seven_Zip_Coder`) | ~6719–6789 |
| Single-file archive assembly (`Seven_Zip_Single_File`) | ~12566–12677 |
| Method-ID parsing on decode | ~19351–19512 |
| Folder / bind-pair analysis | ~19524–19809 |
| Single-coder decode dispatch (`Run_Post_Coders`) | ~20463–20615 |
| BCJ2 multi-coder dispatch (`Decode_BCJ2_Main_Chain`) | ~21298–21442 |
| Delta decode (`Seven_Zip_Delta_Decode`) | ~6791–6822 |
| x86 BCJ decode (`Seven_Zip_BCJ_X86_Decode`) | ~11365–11415 |
| BCJ2 decode (`Seven_Zip_BCJ2_Decode`) | ~11417–11457 |
| PPMd decoder (`Seven_Zip_PPMd_Decode`) | ~6824–11074 |
| PPMd generate-and-verify writer (`Seven_Zip_PPMd_Encode`) | ~16807–17285 |

### Architectural debt to address alongside the features

The 7z subsystem is one 23k-line file with `if/elsif` method-ID matching and
nested dispatch functions. Before or during the larger workstreams, extract the
7z code into internal child packages so each codec is independently testable:

- `Zlib.Seven_Zip.Filters` — branch/delta converters (this is milestone 1).
- `Zlib.Seven_Zip.PPMd` — model + range coder, both directions.
- `Zlib.Seven_Zip.LZMA` — encoder/decoder and properties.
- `Zlib.Seven_Zip.Crypto` — AES-256, SHA-256, key derivation.
- `Zlib.Seven_Zip.Container` — header parse/build, folders, bind pairs, streams.

Replace the hard-coded method-ID `if/elsif` chains (parse side ~19351 and
dispatch side ~20463) with a single table mapping method-ID → codec descriptor
(decode fn, encode fn, property shape). New codecs then become table entries plus
a package, not surgery on a 23k-line procedure.

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

### M1 — Full branch-filter family (encode + decode) — DONE (except RISC-V)

Each branch filter is a deterministic byte transform with a known algorithm
(LZMA SDK `Bra*.c` / xz). No entropy coding, no allocation.

- Internal package `Zlib.Seven_Zip_Filters` provides `Branch_Convert`
  (encode/decode) for x86 (full masked BCJ), ARM, ARMT, ARM64, PPC, SPARC,
  IA-64, plus Delta. Each pair is exact inverses; functions return 1-based
  arrays (codebase convention).
- Method-IDs are wired into the decode parser (classic 4-byte **and** compact
  1-byte forms), every decode dispatch site, the BCJ2 pre-coder case, and
  writer coder emission. The buggy simplified inline x86 decoder was replaced
  by the masked converter.
- Tested by round-trips, interop known-answer vectors, and frozen stock-7z
  fixtures; **validated against stock 7-Zip 23.01** (all filters × multiple
  binaries/sizes decode byte-identically).
- **RISC-V is deferred** (Task #8): 7-Zip 23.01 predates the RISC-V filter, so
  it cannot be cross-validated; shipping the intricate converter unvalidated is
  avoided. Add it once a 7-Zip 24.x+ is available.

### M2 — Writer multi-coder folders (filter + codec with bind pairs)

The writer currently emits only single-coder folders. To *produce* filtered
archives (and later, solid ones), the header builder must emit folders with
multiple coders, bind pairs, and ordered pack streams.

- Generalize `Seven_Zip_Single_File` / `Append_Seven_Zip_Coder` to take a coder
  chain rather than one coder.
- Emit `NumCoders`, per-coder in/out stream counts, `BindPairs`, and
  `PackedStreams` correctly.
- Tests: build filter→LZMA archives and read them back with our own extractor
  (which already supports bounded linear filter chains) and with stock `7z`.

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

Remaining polish: `Glue_Free_Blocks` is stubbed (only diverges under heavy
memory pressure — high order + large input + tight `mem`; default 16 MB
auto-covers realistic inputs). The ~25 fake `Stock_*_Context_Encode` generators
and the canned decoder are now dead code and can be deleted.

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
forward shortest-path DP over 2 KB segments that carries `State` + the four
repeat distances per offset and prices every literal/match/rep against an
integer LZMA-SDK bit-price table. Long matches (≥ nice-len) are taken whole for
speed. Emission reuses the proven range-coder routines, so a misprice only costs
ratio, never correctness. Output stays standard — stock `7z` reads it and our
decoder reads it; LZMA2 shares the encoder.

Result vs stock `7z` LZMA: **within +1.9% everywhere** (most under +1%), and it
**beats** stock on text (−1%) and highly-repetitive data (−16%). Throughput
≈0.6 s per 300 KB. (The pre-optimal greedy+lazy+rep encoder was +3.4..11%.)

Still future work: 7z-style flush-at-long-match segmentation (removes the small
residual match split at segment boundaries on pathological inputs) and per-input
`lc`/`lp`/`pb` tuning (defaults 3/0/2).

### M5 — Solid compression

Real ratio wins for many-file archives come from a single shared stream.

- `*_Files` writers currently pack entries independently. Add a solid mode that
  concatenates entry payloads into one folder with substream sizes/CRCs.
- Decoder already handles covered solid substreams; verify and broaden.
- Tests: multi-file solid archives, both directions, vs stock `7z`.

### M6 — Encryption (AES-256 + SHA-256 key derivation, encrypted headers)

Table-stakes for 7z interop. Pure-Ada crypto.

- `Zlib.Seven_Zip.Crypto`: AES-256 (CBC as 7z uses), SHA-256, and the 7z key
  derivation (password + salt, `NumCyclesPower` iterations).
- AES coder (`06 F1 07 01`) on decode and encode; encrypted-header support.
- Password parameters already exist in the API surface
  (`Seven_Zip_External_File`, etc.) but are currently inert — wire them in.
- Tests: decrypt archives 7z produced from a known password; encrypt and have
  7z decrypt; constant-time compare where it matters.

### M7 — Multi-volume (split) archives

- Read/write `.7z.001`, `.7z.002`, … splitting the stream at volume boundaries.
- Tests: round-trip across volume boundaries; read stock multi-volume sets.

## Cross-cutting: interop test harness

Add an optional CI lane that, when a real `7z`/`p7zip` binary is present:

- for every codec/filter, encodes with us → decodes with `7z`, and encodes with
  `7z` → decodes with us;
- runs on a fixed corpus (text, machine code per architecture, random,
  incompressible, empty, large).

Keep it optional so the default pure-Ada build/test path stays dependency-free,
matching the existing release-checklist philosophy.

## Definition of done

Full 7z support is reached when, for the standard method set (Copy, Deflate,
BZip2, LZMA, LZMA2, PPMd, all branch filters, Delta, BCJ2, AES-256), with solid
and multi-volume layouts:

- we decode every archive stock `7z` produces, and
- stock `7z` decodes every archive we produce,

across the interop corpus, in pure Ada, with the existing deterministic
status-code / exception contracts preserved.
