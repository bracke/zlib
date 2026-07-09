# Architecture

`Zlib` is a standalone Ada/Alire crate. It exposes a root one-shot API and a
public streaming inflate API.

## Public surface

The root package `Zlib` owns the public API:

- one-shot `Inflate`, `Inflate_With_Header`, and `Inflate_File`;
- stored-block `Deflate_Stored` and `Deflate_Stored_File`;
- fixed-Huffman `Deflate_Fixed` and `Deflate_Fixed_File`;
- dynamic-Huffman `Deflate_Dynamic` and `Deflate_Dynamic_File`;
- policy-based `Deflate` and `Deflate_File`;
- `Status_Code`, `Status_Image`, `Compression_Mode`, and `Header_Type`;
- streaming `Filter_Type` lifecycle and data movement operations.

## One-shot path

The one-shot path is now a compatibility wrapper over the streaming inflate
engine. `Inflate` accepts a complete zlib-wrapped Deflate stream, initializes a
streaming filter with `Header => Zlib_Header`, feeds the input through
`Translate`, drains pending bytes through `Flush (Finish)`, and returns the
accumulated output with a deterministic `Status_Code`.

The public one-shot API remains status-based. Streaming failures are kept
exception-based internally, but the streaming decoder records an exact internal
status before raising `Zlib_Error`; `Inflate` maps that stored status back to
`Invalid_Header`, `Unsupported_Preset_Dictionary`, `Invalid_Checksum`,
`Invalid_Stored_Block`, `Invalid_Huffman_Code`, `Invalid_Distance`,
`Invalid_Block_Type`, or `Unexpected_End_Of_Input` as appropriate. No `String`
conversion is used for payload bytes. NUL bytes, bytes above `0x7F`, and CR/LF
are preserved exactly.

## Streaming path

The streaming path is built from internal child packages:

```text
Zlib.Stream_Bits      incremental compressed input and Deflate bit reads
Zlib.Bits             legacy complete-buffer Deflate bit reader
Zlib.Huffman          canonical Huffman table build/decode
Zlib.Huffman_Builder  dynamic-Huffman code length analysis for compression
Zlib.Deflate_Tables   shared fixed-Huffman and length/distance metadata
Zlib.Sliding_Window   bounded output queue and 32 KiB LZ77 history
Zlib.Stream_Inflate   zlib/gzip wrappers + Deflate state machine
Zlib.Wrapper          legacy complete-buffer zlib wrapper parser
Zlib.Bit_Writer       LSB-first Deflate bit emission for compression output
Zlib.Fixed_Compress   fixed-Huffman zlib compressor
Zlib.Dynamic_Compress legacy internal dynamic-Huffman block compressor
Zlib.Raw_Inflate      legacy internal raw Deflate decoder, not used by consumers
CryptoLib.Checksums            Adler-32 trailer, DICTID, gzip/ZIP/7z CRC-32
```

The streaming engine handles zlib-wrapped, gzip-wrapped, and raw stored,
fixed-Huffman, and dynamic-Huffman Deflate blocks. Explicit streaming wrapper
modes are wrapper-strict. `Header => Default` uses lightweight wrapper
discrimination before entering the same inflate engine, matching one-shot
`Inflate` and `Inflate_With_Header` default behavior.

## Streaming wrapper state

The zlib and gzip streaming wrappers are resumable across all byte boundaries. The zlib path is:

```text
Need_CMF -> Need_FLG -> Deflate_Data -> Need_Adler_1 -> ... -> Done
```

Header validation checks compression method, window size, header modulus, and
preset-dictionary flag. The Adler footer is read incrementally and compared
against the checksum accumulated from decoded output.

## Streaming Deflate state

The Deflate state machine is resumable across stored-block fields,
fixed-Huffman symbols, dynamic-Huffman table construction, extra bits, distance
symbols, and LZ77 copies:

```text
Need_Block_Header
 -> Stored_Align / Stored_Len_* / Stored_NLen_* / Stored_Data
 -> Fixed_Init
 -> Dynamic_Header_* / Dynamic_Code_Length_* / Dynamic_All_Code_Lengths
 -> Dynamic_Build_Tables
 -> Compressed_Symbol / Compressed_Literal / Length_Extra
 -> Distance_Symbol / Distance_Extra / Copying_Match
 -> Finished
```

`BTYPE = 00`, `BTYPE = 01`, and `BTYPE = 10` are implemented in the streaming
path. `BTYPE = 11` is malformed.

## Output ownership

Decoded bytes are emitted into `Zlib.Sliding_Window`. The window records LZ77
history and holds a bounded pending-output queue. Public `Translate` and `Flush`
drain this pending queue into caller-owned output buffers. Literal bytes and
match-copy bytes both update the sliding window. Wrapped zlib streams update
Adler-32, gzip streams update CRC32/ISIZE, and raw Deflate streams perform
no checksum update.

## Gzip wrapper

The streaming inflater has explicit wrapper paths over the same Deflate state
machine. `Default`/`Zlib_Header` parse the zlib header and validate Adler-32.
`GZip` parses the gzip member header, runs raw Deflate through the same internal
decoder, tracks CRC32 and decoded size as bytes enter the sliding-window output
path, then validates the little-endian CRC32 and ISIZE trailer. `Raw_Deflate`
skips wrapper parsing and trailer validation entirely. Adler-32, gzip CRC32, and
raw no-checksum mode are mutually exclusive per stream.


## Unified decompression engine

The streaming engine is authoritative for decompression semantics. One-shot
`Inflate`, streaming zlib inflate, streaming gzip inflate, and streaming raw
Deflate inflate share the same Deflate state machine, Huffman decoder, and
sliding window. Wrapper validation remains mode-specific. Public one-shot
`Inflate_With_Header` also uses this streaming engine for explicit zlib, gzip,
and raw Deflate wrapper modes. Legacy raw-inflate internals
are not part of the consumer contract.

## Compression output

`Deflate_Stored` remains the conservative compatibility writer and is not
redirected to compression internally. `Deflate_Fixed` uses `Zlib.Bit_Writer` and
`Zlib.Fixed_Compress` to emit one final fixed-Huffman Deflate block inside a
zlib wrapper. `Deflate_Dynamic` uses the root package's maintained block-local
compression engine, matching streaming Dynamic for large-input block splitting
and default lazy LZ77 policy. `Zlib.Dynamic_Compress` remains an internal legacy
single-block helper and is not the public root Dynamic path. The fixed and
dynamic writers use the internal bounded `Zlib.LZ77_Matcher` and emit literals
or length/distance pairs followed by the end-of-block symbol. They do not
expose optimal parsing, gzip metadata, or ZIP containers. Raw Deflate output reuses the same
stored/fixed/dynamic payload emitters with wrapper/trailer emission suppressed
by the public raw compression entry points. Generated output is
validated by the existing one-shot and streaming inflate paths.

## Archive and 7z internals

Archive consumers still use only `with Zlib;`. Internal child packages split the
7z implementation by concern:

```text
Zlib.Seven_Zip_Methods            method IDs, descriptors, arity, classification
Zlib.Seven_Zip_Coders             writer coder descriptor bytes and properties
Zlib.Seven_Zip_Container          7z header/envelope construction
Zlib.Seven_Zip_Graphs             graph stream arithmetic and validation
Zlib.Seven_Zip_Numbers            7z UInt64 and little-endian scalar helpers
Zlib.Seven_Zip_Paths              safe entry and filesystem path validation
Zlib.Seven_Zip_Properties         FilesInfo parsing, target lookup, metadata images
Zlib.Seven_Zip_Filters            branch filters, Delta, and BCJ2 transforms
Zlib.Seven_Zip_AES                AES-256/SHA-256/KDF/CBC support
Zlib.PPMd7                        PPMd7 codec
Zlib.Seven_Zip_Codec_Writing      single-entry codec and method-graph writers
Zlib.Seven_Zip_File_Writing       file and file-list writer orchestration
Zlib.Seven_Zip_BCJ2_Writing       BCJ2 writer orchestration
Zlib.Seven_Zip_Encrypted_Writing  encrypted payload writer orchestration
Zlib.Seven_Zip_Filtered_Writing   filter+codec writer orchestration
Zlib.Seven_Zip_Header_Encryption  encrypted-header writer orchestration
Zlib.Seven_Zip_Header_Reading     encoded-header read recovery and normalization
Zlib.Seven_Zip_Folder_Decoding    read-side folder graph, decode policy, and slicing helpers
Zlib.Seven_Zip_File_Extraction    filesystem extraction staging and metadata
Zlib.Seven_Zip_Volumes            split-volume read/write/extract orchestration
Zlib.Archive_Listing              ZIP/7z listing dispatch
Zlib.Archive_Directory_Extraction ZIP/7z directory extraction dispatch
```

`src/zlib.adb` remains the public wrapper body and still owns root-only codec
callbacks and the largest native 7z read-side folder decode loops. Passwords
are now threaded through internal read/list/extract callbacks as explicit decode context instead of root-global state.
Encoded-header recovery is shared by native extraction and listing through
`Zlib.Seven_Zip_Header_Reading`; root-body callbacks supply codecs that still
depend on root Deflate/LZMA entry points.
Native folder graph analysis, bind-pair mapping, linear coder-chain execution,
BCJ2 graph decode, PPMd fallback policy, folder payload validation, and solid
substream slicing now flow through `Zlib.Seven_Zip_Folder_Decoding`; root-body
callbacks supply Deflate, BZip2, LZMA, and LZMA2 codecs that still depend on
root entry points. FilesInfo target-entry walking now flows through
`Zlib.Seven_Zip_Properties`; the remaining read-side orchestration in the root
body is section ordering, StreamsInfo parsing, and codec callback dispatch.

## Performance-sensitive internals

Performance work must keep the public API and decompression semantics unchanged. The main
architecture rule is that performance work remains behind the root `Zlib`
interface.

`Zlib.Deflate_Tables` is the single source of truth for Deflate length bases,
length extra-bit counts, distance bases, distance extra-bit counts, and dynamic
code-length-code order. Raw and streaming inflaters must not keep private stale
copies of these tables.

`Zlib.Stream_Bits` owns incremental input storage. It uses bounded fixed storage
with deferred compaction so normal byte consumption does not allocate or copy the
remaining suffix on every byte. The existing maximum buffered input rule still
prevents accidental whole-body buffering.

`Zlib.Huffman` stores table length bounds in the decode table. Decoders can stop
at the maximum known code length and avoid probing before the minimum known code
length while preserving canonical Huffman validation.

`CryptoLib.Checksums` supplies the Adler-32 and CRC-32 implementations used by zlib wrapper
validation and archive metadata. Zlib keeps only local byte-array adapters where child
packages need to pass zlib's public `Byte_Array` representation to cryptolib.


## Raw Deflate release hardening

Raw Deflate compression is release-hardened by `zlib_raw_release_tests`, `zlib_raw_cross_wrapper_conformance_tests`, the raw examples, and the raw tools. The contract remains unchanged: `Deflate_*` APIs emit zlib-wrapped streams, `GZip*` APIs emit gzip-wrapped streams, `Deflate_Raw*` APIs emit raw Deflate blocks only, `Seven_Zip_Stored*` APIs emit Copy-coder `.7z` archives including header-only directory entries and solid stored file-list archives with no-stream directory entries, `Seven_Zip_Deflate*` APIs emit Deflate `.7z` archives, `Seven_Zip_BZip2*` APIs emit BZip2 `.7z` archives, `Seven_Zip_LZMA*` APIs emit LZMA `.7z` archives, `Seven_Zip_LZMA2*` APIs emit LZMA2 `.7z` archives, `Seven_Zip_Filtered` emits single-entry compressed filtered `.7z` archives, `Seven_Zip_Method_Graph` emits low-level single-entry non-encrypted method-graph `.7z` containers from caller-supplied packed stream bytes, `Extract_Seven_Zip*` APIs extract those supported native 7z layouts plus native PPMd empty/repeated-symbol/root-symbol/periodic-prefix, stock-7z multi-block streams with LZMA encoded headers, stock-7z no-stream empty-file entries, stock-7z BCJ+PPMd filter chains, and BCJ2 graphs with Copy, PPMd, or supported main pre-coders, `Seven_Zip_PPMd`, `Seven_Zip_PPMd_File`, and `Seven_Zip_PPMd_Files` emit native PPMd 7z archives for this crate's extractor without calling local `7z`, `ZIP`/`ZIP_File`/`ZIP_Files` emit ZIP archives, `Inflate`, `Inflate_Auto`, `Inflate_With_Header` with `Header => Default`, and streaming `Inflate_Init` with `Header => Default` auto-detect zlib/gzip/raw input, gzip input accepts concatenated members unless `GZip_Mode => Single_Member` is requested, and concrete inflate modes remain wrapper-strict. `Auto` remains deterministic and block-local.

## Block chooser

`Zlib.Block_Chooser` owns the internal Auto scoring policy. It estimates Stored, Fixed-Huffman, and Dynamic-Huffman Deflate payload sizes and chooses the smallest valid candidate using the deterministic tie-breaker Stored, Fixed, Dynamic. Dynamic scoring includes the generated dynamic header and code-length representation, so Auto does not undercount Dynamic blocks.

The chooser is deliberately wrapper-independent. zlib, gzip, and raw Deflate wrappers add different headers and trailers, but those bytes do not influence the Deflate block kind. Explicit modes bypass the chooser.

## Lazy LZ77 matcher architecture

`Zlib.LZ77_Matcher` owns greedy, conservative lazy, and bounded optimal token
selection. The public root API does not expose matcher internals. Callers choose
public compression modes or levels; internal compression code maps those levels
to a bounded chain limit and a `Match_Strategy`.

The lazy strategy is deliberately simple: find the best match at the current
position, insert the current byte into legal history, and probe the next
position. If the next match is strictly longer, or equal length and cheaper
after paying for the literal, emit the current byte as a literal; otherwise emit
the current match. Equal-length candidates prefer lower Deflate
distance-extra-bit cost, then shorter absolute distance, preserving a stable
deterministic tie-break while improving high-level ratio on repeated payloads.
Levels 8 and 9 use bounded optimal parsing over the same block-local match
candidates found by the configured hash-chain search. All matching remains
block-local, bounded, deterministic, and constrained to Deflate-valid length and
distance ranges.
