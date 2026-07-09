# Compression

This crate exposes explicit one-shot zlib compression modes, deterministic
gzip output helpers, and a small public selection layer. `Deflate_*` APIs write
zlib-wrapped Deflate streams. `GZip` and `GZip_File` write gzip-wrapped Deflate
streams. The compressor exposes a broad Compression_Level API, but the exact Compression_Mode API remains the precise block-strategy control surface.

## Explicit modes

### Stored mode

`Deflate_Stored` and `Deflate_Stored_File` write zlib streams containing stored
Deflate blocks. This is the compatibility/no-compression output path. It is the
right choice when predictable output and minimal compressor complexity matter
more than size reduction.

`Deflate (Input, Stored, Status)` is an exact alias for `Deflate_Stored`.

### Fixed mode

`Deflate_Fixed` and `Deflate_Fixed_File` write zlib streams containing a final
fixed-Huffman Deflate block. The implementation uses a low-effort bounded LZ77 matcher and emits
fixed-Huffman length/distance pairs when matches are found.

`Deflate (Input, Fixed, Status)` is an exact alias for `Deflate_Fixed`.

### Dynamic mode

`Deflate_Dynamic` and `Deflate_Dynamic_File` write zlib streams containing a
dynamic-Huffman Deflate block sequence. The implementation uses the maintained
streaming compression engine, so large inputs are split at the same bounded
block size as streaming Dynamic. Each block is tokenized with the level-aware
bounded LZ77 matcher; default level policy uses conservative lazy matching. It
builds deterministic literal/length, distance, and code-length Huffman
descriptions, and emits literals plus length/distance pairs followed by
end-of-block.

`Deflate (Input, Dynamic, Status)` is an exact alias for `Deflate_Dynamic`.

## Auto mode

`Deflate (Input, Status => Status)` and `Deflate (Input, Auto, Status)` are the
convenience one-shot policy APIs for callers that want a valid zlib stream
without committing to a Deflate block type.

The Auto compression policy is deliberately bounded and block-local. For each
pending compression block, Auto scores the Stored, Fixed-Huffman, and, for
levels 2 through 9, Dynamic-Huffman candidates before any current-block bytes
are emitted. Stored scoring includes the stored-block header, byte-alignment
padding, LEN/NLEN, and payload bytes. Fixed scoring includes the block header,
token code lengths, extra bits, EOB, and final byte padding. Dynamic scoring
includes the dynamic header, code-length-code lengths, encoded literal/length
and distance code lengths, token payload, extra bits, EOB, and final byte
padding.

Auto emits the smallest valid candidate. Equal scores use the deterministic
tie-breaker Stored, then Fixed, then Dynamic. If a candidate cannot be emitted
at the current bit position, it is removed from the candidate set before the
choice is made; the implementation does not silently use a fixed-first fallback
order. Once a block has begun emitting, Auto does not switch modes mid-block.
Any post-emission failure is treated as an internal compression error and
reported as `Zlib_Error`.

This makes `Auto` deterministic and safe: it must not return corrupt or partial
compressed output. Auto is block-local, does not imply best possible whole-file
compression, and does not buffer the entire stream.

## Raw Deflate compression contract

Raw Deflate compression is explicit and separate from the existing zlib and gzip
APIs. `Deflate_Raw` and `Deflate_Raw_File` now support `Mode => Stored`, `Mode => Fixed`, `Mode => Dynamic`, and `Mode => Auto`. The output contains only Deflate blocks; it does not emit a zlib CMF/FLG header, Adler-32 footer, gzip header, gzip CRC32 trailer, or gzip ISIZE trailer.
Raw output has no wrapper checksum, so consumers should use it only when a
container or protocol explicitly supplies its own wrapper, length, and checksum.

`Mode => Dynamic` emits raw dynamic-Huffman Deflate blocks. `Mode => Auto` uses the same deterministic block-local Stored/Fixed/Dynamic size-scoring policy as zlib/gzip Auto. The existing
`Deflate_Stored`, `Deflate_Fixed`, `Deflate_Dynamic`, `Deflate`, and
`Deflate_File` APIs remain zlib-wrapped. `GZip` and `GZip_File` remain
gzip-wrapped.

## File API

`Deflate_File` is a thin wrapper over `Deflate`:

```text
Read_File -> Deflate(Input, Mode, Status) -> Write_File
```

The file status policy is unchanged from the explicit file helpers:

- missing or unreadable input -> `Input_File_Error`;
- output creation/write failure -> `Output_File_Error`;
- compression failure -> the compression `Status_Code`.

## Gzip output

`GZip` and `GZip_File` produce deterministic minimal gzip members by default.
The default gzip header is exactly `1F 8B 08 00 00 00 00 00 00 FF`. Optional
metadata is emitted only when callers use `GZip_Metadata` and the metadata
overloads. The Deflate payload is raw Deflate and the trailer contains
little-endian CRC32 and ISIZE values for the uncompressed input.

`GZip` supports `Stored`, `Fixed`, `Dynamic`, and `Auto`. The `Deflate_*` APIs
remain zlib-wrapped and are intentionally not changed to gzip output.

## Consumer guidance

Use explicit mode APIs for fixtures and tests that need deterministic block type
expectations. Use `Deflate (Auto)` for archive/backup-style consumers that want
the deterministic block-local scorer to choose among the currently implemented
Stored, Fixed, and Dynamic block writers.

For Git loose-object style output, `Deflate_Stored` remains the simplest and
most conservative option. `Deflate_Fixed` or `Deflate (Auto)` may be used only
when the consumer explicitly chooses smaller objects over stored-block
simplicity.


## Streaming compression

Streaming compression supports zlib-wrapped and gzip-wrapped stored,
fixed-Huffman, and dynamic-Huffman Deflate blocks. Use `Deflate_Init` with
`Header => Default`, `Header => Zlib_Header`, or `Header => GZip`, and
`Mode => Stored`, `Mode => Fixed`, `Mode => Dynamic`, or `Mode => Auto`.
`Header => Raw_Deflate` supports streaming compression with `Mode => Stored`, `Mode => Fixed`, `Mode => Dynamic`, and `Mode => Auto`. It emits raw Deflate blocks only and suppresses zlib/gzip headers and trailers. `Mode => Auto` uses the same deterministic block-local policy as zlib/gzip Auto.
For streaming compression, `Auto` is block-local and deterministic: each
buffered block chooses the smallest valid Stored, Fixed, or Dynamic candidate by deterministic size scoring.
It does not run a whole-stream smallest-output search and does not buffer the
entire stream.

Stored mode preserves the documented zlib/gzip stored-output behavior: `Compress` accepts
incremental input and bounded output buffers, full 65,535-byte stored blocks are
emitted as non-final blocks, and `Finish` emits the final stored block plus the
active wrapper trailer. For `Header => Raw_Deflate`, the same stored-block writer
is used but no wrapper trailer is emitted.

Fixed mode emits fixed-Huffman Deflate blocks. It buffers one
bounded block, writes BFINAL/BTYPE bits only when the block is ready, tokenizes
the block with the low-effort bounded LZ77 matcher, emits literals or
length/distance pairs followed by EOB, flushes the final partial Deflate byte at
stream end, and then emits the active wrapper trailer. Output buffers of length
1 are valid.

Dynamic mode emits dynamic-Huffman Deflate blocks. It buffers a
bounded block, tokenizes it with the default level-aware bounded LZ77 matcher,
including conservative lazy matching at the default level, builds
deterministic literal/length, distance, and code-length Huffman tables for that
block, emits the dynamic header and literal or length/distance payload followed
by EOB, and preserves bit continuity across multiple blocks. It does not
perform optimal parsing.

`Header => GZip` emits the deterministic gzip header before the raw Deflate
payload and a CRC32/ISIZE trailer after the final block. `Header => Raw_Deflate`
emits only raw Deflate payload bytes for `Mode => Stored`, `Fixed`, `Dynamic`,
or `Auto`.


## Cross-API equivalence contract

One-shot and streaming compression are required to be semantically equivalent,
not byte-for-byte identical. For the same wrapper and mode, both APIs must emit
valid deterministic streams that inflate to the same uncompressed payload and
carry valid wrapper trailers. `Deflate_Dynamic` uses the same block-local
Dynamic emission engine as streaming Dynamic. Other one-shot exact-mode helpers
may still choose their own whole-input block boundaries, while streaming
compression always uses bounded, block-local emission.

Determinism is still strict within each API: the same header, mode, input, input
chunking, and output buffer size must produce identical streaming bytes across
repeated runs.

## Non-goals

The compressor does not provide:

- whole-stream optimal parsing;
- advanced block splitting.

## Output conformance

The `Deflate_*` and `Deflate` entry points emit zlib-wrapped streams:

- `Deflate_Stored`
- `Deflate_Fixed`
- `Deflate_Dynamic`
- `Deflate (Input, Stored, Status)`
- `Deflate (Input, Fixed, Status)`
- `Deflate (Input, Dynamic, Status)`
- `Deflate (Input, Auto, Status)`

The conformance suite verifies that each one-shot and streaming zlib output
inflates through both one-shot and streaming `Zlib_Header`, rejects wrong
wrapper modes, carries a valid Adler-32 footer, and is deterministic across
repeated calls. Gzip output is covered separately for deterministic header,
CRC32/ISIZE trailer, wrapper rejection, and one-shot/streaming inflate
roundtrips. Raw Deflate output is covered separately by the raw compression
and cross-wrapper conformance suites. Streaming dynamic-Huffman compression uses
the same default lazy LZ77 policy as one-shot dynamic compression for a single
buffered block, while still preserving streaming block-local emission.


### Frozen streaming lifecycle

The compression-side lifecycle semantics are part of the documented public contract. `Deflate_Init` always
resets the filter, including open, failed, completed, and closed filters.
`Compress` and `Compress_Flush` always initialize their out parameters before
raising lifecycle or compression exceptions. Failed compression filters remain
open until `Compress_Close` so exception cleanup can be uniform.

`Compress_Stream_End` is stronger than "finish was requested": it is `True`
only after the final Deflate block, the zlib Adler-32 footer or gzip
CRC32/ISIZE trailer, and all pending output bytes have been drained to the
caller. Double `Finish` after end returns no output. Additional non-empty input
after end raises `Status_Error`.

The no-consumption/no-output markers match streaming inflate: non-null arrays
use `First - 1`, while null arrays use `First` as the safe marker.

## Streaming compression conformance

The streaming compressor is covered by a wrapper/mode conformance matrix. The supported matrix is:

| Header | Modes |
| --- | --- |
| `Default` | `Stored`, `Fixed`, `Dynamic`, `Auto` |
| `Zlib_Header` | `Stored`, `Fixed`, `Dynamic`, `Auto` |
| `GZip` | `Stored`, `Fixed`, `Dynamic`, `Auto` |

`Default` is tested as `Zlib_Header`. For all supported entries, fixed Ada fixtures roundtrip through the matching streaming inflate wrapper and the applicable one-shot inflate API. `Auto` is tested for deterministic byte-for-byte output when input chunking and output buffer sizes are identical.

The conformance tests also assert strict wrapper boundaries: raw stored/fixed/dynamic/auto output must inflate only through `Raw_Deflate` or the default auto-detect path; zlib output must fail through gzip or raw-Deflate inflate paths; and gzip output must fail through zlib-header or raw-Deflate inflate paths while the default auto-detect path accepts it. `Header => Raw_Deflate` compression is supported for `Stored`, `Fixed`, `Dynamic`, and `Auto`.

## Streaming compression completion

The streaming compression API supports the same public compression policies as
the one-shot API for zlib and gzip wrappers: `Stored`, `Fixed`, `Dynamic`, and
`Auto`.

`Stored` emits stored Deflate blocks. `Fixed` emits fixed-Huffman
blocks. `Dynamic` emits bounded dynamic-Huffman blocks. `Auto` is
deterministic and block-local: each pending block is selected as Dynamic when
valid, otherwise Fixed, otherwise Stored before any bytes for that block are
emitted.

One-shot `Deflate_*`, `Deflate`, and `Deflate_File` produce zlib-wrapped output.
One-shot `GZip` and `GZip_File` produce deterministic minimal gzip output.
Streaming `Header => Zlib_Header` produces zlib-wrapped output. Streaming
`Header => GZip` produces gzip-wrapped output.

There is no whole-stream optimal parser, advanced block splitter, in-process full
LZMA/LZMA2/in-process stock-compatible PPMd codec stack, or new compression algorithms.
ZIP output is available through `ZIP`, `ZIP_File`, and `ZIP_Files`; `ZIP_Files`
can emit multi-entry archives and explicit ZIP64 metadata.
Broader 7z creation and extraction is available only through native in-process
APIs; unsupported requests fail closed without invoking a local `7z`
executable. Streaming compression
supports sync flush and full flush; full flush is currently byte-equivalent to
sync flush because there is no cross-block match history to reset. Optional gzip
metadata is available only through explicit metadata overloads and includes
MTIME, OS, XFL, FEXTRA, FNAME, FCOMMENT, and FHCRC.


## Raw dynamic compression note

Raw_Deflate compression now supports `Stored`, `Fixed`, `Dynamic`, and `Auto`. Raw output is Deflate block data only: it has no zlib header, no Adler-32 footer, no gzip header, no CRC32 trailer, and no ISIZE trailer. Raw `Auto` uses the same deterministic block-local policy as zlib/gzip Auto. `Deflate_*` APIs remain zlib-wrapped, and `GZip*` APIs remain gzip-wrapped.


## Raw dynamic compression

`Header => Raw_Deflate, Mode => Dynamic` now emits dynamic-Huffman Deflate blocks only. It suppresses the zlib header, Adler-32 footer, gzip header, CRC32 trailer, and ISIZE trailer. `Raw_Deflate` with `Mode => Auto` is supported.

## One-shot raw Deflate bridge

The one-shot raw bridge is now frozen: `Deflate_Raw`, `Deflate_Raw_File`, `Deflate_Raw_File_Size`, and `Deflate_Raw_File_To_Stream` support Stored, Fixed, Dynamic, and Auto raw Deflate output. The implementation uses the streaming raw compression path so one-shot raw output has the same wrapper contract as `Deflate_Init (Header => Raw_Deflate, Mode => ...)`: Deflate blocks only, no zlib wrapper, no Adler-32 footer, no gzip wrapper, and no gzip trailer.

Raw Deflate output must be selected explicitly. The zlib one-shot APIs continue to emit zlib-wrapped streams, and the gzip APIs continue to emit deterministic gzip members. Use raw output only when an external container or protocol supplies its own wrapper, size metadata, and checksum.

## Wrapper-strict conformance baseline

Compression output is wrapper-strict across all public compression surfaces:

- `Deflate_Stored`, `Deflate_Fixed`, `Deflate_Dynamic`, `Deflate`, and `Deflate_File` produce zlib-wrapped Deflate streams only.
- `GZip` and `GZip_File` produce gzip-wrapped Deflate members only.
- `Deflate_Raw` and `Deflate_Raw_File` produce raw Deflate streams only.

Raw Deflate output contains Deflate blocks only. It has no zlib CMF/FLG header,
no Adler-32 footer, no gzip header, no CRC32 trailer, and no ISIZE trailer.
Wrong-wrapper inputs fail deterministically: zlib output is accepted only by
`Inflate`/`Inflate_With_Header (..., Zlib_Header)`, gzip output is accepted only
by `Inflate_With_Header (..., GZip)`, and raw output is accepted only by
`Inflate_With_Header (..., Raw_Deflate)`.


## Raw Deflate compression output

Raw Deflate output is available through `Deflate_Raw`, `Deflate_Raw_File`, and
streaming `Deflate_Init (Header => Raw_Deflate, Mode => ...)`. The supported raw
matrix is `Stored`, `Fixed`, `Dynamic`, and `Auto`. Raw output is Deflate block
data only and intentionally omits all zlib and gzip wrapper bytes.

Use raw output only for protocols or containers that already provide their own
framing and integrity checks. Use `Deflate`/`Deflate_File` for zlib streams and
`GZip`/`GZip_File` for gzip members.


## Raw Deflate release hardening

Raw Deflate compression is release-hardened by `zlib_raw_release_tests`, `zlib_raw_cross_wrapper_conformance_tests`, the raw examples, and the raw tools. The contract remains unchanged: `Deflate_*` APIs emit zlib-wrapped streams, `GZip*` APIs emit gzip-wrapped streams, `Deflate_Raw*` APIs emit raw Deflate blocks only, `Seven_Zip_Stored*` APIs emit Copy-coder `.7z` archives including header-only directory entries and solid stored file-list archives with no-stream directory entries, `Seven_Zip_Deflate*` APIs emit Deflate `.7z` archives, `Seven_Zip_BZip2*` APIs emit BZip2 `.7z` archives, `Seven_Zip_LZMA*` APIs emit LZMA `.7z` archives, `Seven_Zip_LZMA2*` APIs emit LZMA2 `.7z` archives, `Seven_Zip_Filtered` emits single-entry compressed filtered `.7z` archives, `Seven_Zip_Method_Graph` emits low-level single-entry non-encrypted method-graph `.7z` containers from caller-supplied packed stream bytes, `Extract_Seven_Zip*` APIs extract those supported native 7z layouts plus native PPMd empty/repeated-symbol/root-symbol/periodic-prefix, stock-7z multi-block streams with LZMA encoded headers, stock-7z no-stream empty-file entries, stock-7z BCJ+PPMd filter chains, and BCJ2 graphs with Copy, PPMd, or supported main pre-coders, `Seven_Zip_PPMd`, `Seven_Zip_PPMd_File`, and `Seven_Zip_PPMd_Files` emit native PPMd 7z archives for this crate's extractor without calling local `7z`, `ZIP`/`ZIP_File`/`ZIP_Files` emit ZIP archives, `Inflate`, `Inflate_Auto`, `Inflate_With_Header` with `Header => Default`, and streaming `Inflate_Init` with `Header => Default` auto-detect zlib/gzip/raw input, gzip input accepts concatenated members unless `GZip_Mode => Single_Member` is requested, and concrete inflate modes remain wrapper-strict. `Auto` remains deterministic and block-local.

## Optional gzip metadata

The gzip compression APIs preserve their old default behavior. Use the metadata
overloads only when a caller explicitly needs gzip header fields such as name,
comment, MTIME, OS, or FHCRC. Metadata never changes the Deflate payload policy
and never changes the trailer CRC32/ISIZE semantics.


## Streaming compression flush modes

`Sync_Flush` forces currently buffered compression input into the Deflate stream without ending it. It finishes the current block as non-final and emits an empty non-final stored block on a byte boundary. `Full_Flush` currently has the same byte-level behavior because the compressor has no cross-block match history; the distinction is preserved in the API and tests. Neither mode emits zlib/gzip trailers, and `Compress_Stream_End` remains `False` until `Finish`. Flush output may require repeated drain calls with small output buffers. `Finish` after a partially drained flush completes the pending flush work and then finalizes the stream. After stream end, `Sync_Flush` and `Full_Flush` are lifecycle misuse and raise `Status_Error`. Streaming inflate treats `Sync_Flush` and `Full_Flush` as `No_Flush`; Deflate flush markers are ordinary stored blocks.

## Compression level policy

The library now exposes `Compression_Level` as a broad effort policy on top of the existing exact compression modes. The stable public range is `0 .. 9`, with `Default_Level = 6`.

The current deterministic mapping is:

| Level | Internal policy |
| --- | --- |
| `0` | `Stored` |
| `1` | `Fixed` |
| `2 .. 3` | `Auto` with greedy matching |
| `4 .. 7` | `Auto` with conservative lazy matching |
| `8 .. 9` | `Auto` with bounded block-local optimal parsing |

`Compression_Mode` remains the exact low-level control surface.
`Compression_Level` is for callers that want a conventional effort-style API
without selecting an exact Deflate block strategy. Levels now control bounded
hash-chain matcher effort and the greedy/lazy/optimal strategy. Internally,
level 0 is the only level that reports matching disabled; levels 1 through 9
enable bounded LZ77 matching. The implementation still does not perform
whole-stream block scoring, so outputs remain deterministic and conservative.

## Bounded LZ77 matcher

Fixed, Dynamic, and Auto compression use the internal `Zlib.LZ77_Matcher`
package. The matcher is a conservative hash-chain implementation with greedy,
lazy, and bounded optimal strategies, Deflate's required 32 KiB window, minimum match length 3, maximum match length
258, and distance range 1 .. 32768. It is bounded by compression level:

- level 0: no matcher; stored output
- level 1: fixed-Huffman with a 4-probe chain limit
- level 2: 8 probes
- level 3: 16 probes
- level 4: 32 probes
- level 5: 64 probes
- level 6: 256 probes
- level 7: 1024 probes
- level 8: 2048 probes
- level 9: 8192 probes

The matcher is deterministic. Levels 2 and 3 use greedy matching; levels 4
through 7 use conservative lazy matching that accepts the next-position match
when it is strictly longer or when an equal-length next match is cheaper after
paying for the literal. Levels 8 and 9 use bounded optimal parsing over the
block-local match candidates found by the configured hash-chain search.
Equal-length match candidates prefer the one with cheaper Deflate distance
coding, then the shorter absolute distance, so high-effort searches can improve
ratio without changing the bounded parser model. The matcher does not perform
whole-stream buffering beyond the existing block buffer or wrapper policy
changes. Stored mode and level 0 never use it.

## Auto block selection

`Mode => Auto` now uses deterministic per-block size scoring. For each pending compression block the compressor evaluates Stored, Fixed-Huffman, and, for levels 2 through 9, Dynamic-Huffman candidates. The Stored score includes the Deflate block header, byte-alignment padding, LEN/NLEN, and payload bytes. The Fixed score includes the block header, token code lengths, length/distance extra bits, EOB, and final padding. The Dynamic score includes the dynamic header fields, code-length-code lengths, encoded literal/length and distance code lengths, token payload, extra bits, EOB, and final padding.

The tie-breaker is stable and documented: Stored wins equal scores before Fixed, and Fixed wins equal scores before Dynamic. Explicit `Stored`, `Fixed`, and `Dynamic` modes remain explicit and are not silently size-optimized. Level 0 maps to Stored, level 1 maps to Fixed, levels 2 and 3 map to greedy Auto, levels 4 through 7 map to lazy Auto, and levels 8 and 9 map to bounded-optimal Auto with the matcher effort for that level. Wrapper bytes and checksums are not part of the score, so zlib, gzip, and raw Deflate use the same block choice for the same block and policy.

## Zlib preset dictionaries

Preset dictionary compression is opt-in. For zlib-wrapped output the compressor
sets `FDICT`, writes `DICTID = Adler-32(Dictionary)` in big-endian order, then
emits the Deflate payload and the normal Adler-32 trailer for the uncompressed
input. Existing non-dictionary zlib/gzip/raw outputs remain unchanged.

The dictionary implementation emits correct dictionary metadata and deterministic streams. The
compressed payload remains valid even when the current block encoder does not
choose dictionary-backed matches.

## Streaming file APIs

Bounded-memory file helpers are available for consumers that must process files without buffering the complete input or output in memory:

```ada
Inflate_File_Streaming
Inflate_File_With_Dictionary_Streaming
Deflate_File_Streaming
Deflate_File_With_Dictionary_Streaming
GZip_File_Streaming
Deflate_Raw_File_Streaming
```

The one-shot convenience file APIs remain available. The `*_File_Streaming` APIs open input and output files, process fixed-size internal chunks, preserve binary data including NUL and high-byte values, and close files on both success and failure. They support the same wrapper separation used elsewhere: zlib, gzip, and raw Deflate are selected explicitly where applicable.

Dictionary-aware zlib file streaming is available through `Inflate_File_With_Dictionary_Streaming` and `Deflate_File_With_Dictionary_Streaming`. These helpers are zlib-header-only because gzip and raw Deflate do not use the zlib FDICT wrapper mechanism.

## Public bound helpers

Adler-32 trailer, preset-dictionary DICTID, gzip CRC-32, ZIP CRC-32, and 7z CRC-32 calculation are internal zlib behavior backed by `CryptoLib.Checksums`. Consumers that need standalone checksum routines should use cryptolib directly.

`Deflate_Bound`, `GZip_Bound`, and `Deflate_Raw_Bound` provide conservative output-size bounds for the package's zlib, minimal-gzip, and raw-Deflate outputs. Use them for allocation and preflight decisions; do not treat them as predictions of the exact compressed size.

## Lazy LZ77 matching policy

Compression levels now select the internal LZ77 token strategy as well as the
bounded hash-chain effort:

- level 0 remains stored output and does not use the matcher;
- level 1 remains low-effort fixed-Huffman output;
- levels 2 and 3 use greedy matching;
- levels 4 through 7 use conservative lazy matching;
- levels 8 and 9 use bounded optimal parsing.

The default level is 6, so default dynamic-Huffman and level-based Auto paths use
lazy matching with a 256-probe bound. Lazy matching is block-local and deterministic: at position `P`,
the compressor keeps the current match unless the best valid match at `P + 1` is
strictly longer or is equal length and cheaper after accounting for the literal.
Equal-length match candidates prefer cheaper distance coding before shorter
absolute distance. The matcher remains bounded by the configured chain limit and
still emits only valid Deflate matches with lengths in 3 .. 258 and distances in
1 .. 32768.

Stored mode and level 0 are unaffected. Fixed mode remains greedy. Lazy lookahead
never crosses block, `Sync_Flush`, `Full_Flush`, or `Finish` boundaries because
those boundaries finalize the pending block before tokenization. The resulting
compression ratio may improve for repeated data, but the output is not intended
to be byte-for-byte equivalent to zlib.
