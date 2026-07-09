# SPARK Coverage

`zlib` runs GNATprove as part of release validation:

```sh
alr exec -- gnatprove -P zlib.gpr --level=4
```

The current SPARK-enabled public surface is intentionally narrow and deterministic:

- `Zlib.Status_Image`, the release-contract mapping from status codes to stable text.
- `Zlib.Deflate_Bound`, `Zlib.GZip_Bound`, and `Zlib.Deflate_Raw_Bound`,
  the public conservative compression-bound helpers.
- `Zlib.Looks_Like_Zlib_Header`, the lightweight zlib CMF/FLG discriminator.
- `Zlib.Looks_Like_GZip_Header`, the lightweight gzip magic/method/flag discriminator.
- `Zlib.Is_ZIP_External_Method` and `Zlib.ZIP_External_Method_Name`, the public ZIP external-codec bridge
  method discriminator and canonical-name mapper.
- Root-body scalar compression helpers for trailer byte extraction, checksum finalization, compression-level to
  mode selection, effective compression-mode selection, block-collection state selection, trailer start-state
  selection, canonical-code bit reversal, and Deflate length/distance symbol lookup.
- Public streaming inflate and compression lifecycle `Is_Open` predicates, plus compression stream-end detection.
- Root-body scalar compression-mode support validation, compression output-buffer fullness detection, and
  streaming inflate/compression failure-state marking.
- Root-body scalar stream-array no-element marker selection and produced-count calculation shared by streaming and
  one-shot bridge code.
- Root-body scalar validation helper for detecting embedded NUL characters in metadata and archive entry names.
- Root-body scalar wrapper for native 7z entry-name validation.
- Root-body scalar wrapper for native 7z byte-availability checks.
- Root-body scalar native 7z PPMd property-bounds gate.
- Root-body scalar text-to-byte conversion helper used by gzip multi-member construction.
- Public scalar gzip metadata setters for MTIME, OS, XFL, and header-CRC state.
- Root-body scalar gzip metadata helpers for optional-header detection, FLG byte construction, and gzip header
  CRC16 finalization.
- Root-body scalar ZIP method-name mapping used by external-codec extraction.

Additional internal packages in the proof boundary:

- `CryptoLib.Checksums`, used by zlib for Adler-32 trailer, preset-dictionary DICTID calculation, gzip CRC-32,
  ZIP CRC-32, and 7z CRC-32 values.
- `Zlib.Deflate_Tables`, covering the shared Deflate length, distance, and code-length-order tables.
- `Zlib.LZ77_Matcher`, covering the deterministic compression-level policy helpers for chain limits and
  stored-only matching enablement, parsing strategy selection, plus the Deflate length/distance extra-bit helpers,
  token-cost helper, and match tie-breaker used by bounded matching.
- `Zlib.Block_Chooser`, covering Deflate length/distance symbol lookup, stored-block bit sizing, byte-padding
  arithmetic, candidate tie-breaking, score selection, and block-kind to compression-mode mapping.
- `Zlib.Fixed_Compress`, covering fixed-Huffman code mapping, bit reversal for fixed-code widths, local
  length/distance symbol lookup, and Adler-32 trailer byte extraction.
- `Zlib.Dynamic_Compress`, covering dynamic-wrapper CRC trailer byte extraction, dynamic-header literal/length,
  distance, and code-length-order last-symbol scans, plus local length/distance symbol lookup.
- `Zlib.Wrapper`, covering the legacy complete-buffer zlib wrapper parser retained for maintenance tests.
- `Zlib.Seven_Zip_Methods`, including descriptor tables, descriptor flags, SPARK-friendly method-ID
  classification, public-filter/codec/graph mappings, coder predicates, and branch-architecture mapping.
  `Method_For_ID` remains ordinary Ada as a thin legacy Boolean wrapper because its API has an `out` parameter,
  which SPARK does not allow.
- `Zlib.Seven_Zip_Paths`, covering deterministic relative output-name validation for native archive extraction.
- `Zlib.Seven_Zip_Numbers`, covering 7z variable-length UInt64 encoded-size calculation and little-endian
  scalar reads. Cursor-advancing variable-length parsing remains ordinary Ada.
- `Zlib.LZMA_Properties`, covering LZMA property-byte validation, `lc`/`lp`/`pb` property-byte construction,
  and default dictionary property bytes.
- `Zlib.LZMA_Core`, covering shared LZMA probability-model constants, property-byte decoding, bit-price
  calculation, literal contexts, state transitions, distance-slot classification, and length-model initialization.
- `Zlib.LZMA_Repetitions`, covering repeated-distance choice-price arithmetic for the LZMA parser.
- `Zlib.LZMA2_Framing`, covering LZMA2 control-byte classification, packed/unpacked size arithmetic, and
  bounded LZMA2 chunk header construction.
- `Zlib.LZMA2_Decoder`, covering lightweight decoder lifecycle helpers for property-presence checks and
  dictionary-base reset. The mutating property setter remains ordinary Ada because its function API has an
  `in out` parameter, which SPARK does not allow.
- `Zlib.Seven_Zip_Graphs`, covering low-level method-graph stream counting, packed-size overflow checks, and
  shape validation for the arbitrary method-graph writer.
- `Zlib.Seven_Zip_Container`, covering the scalar byte-availability predicate shared by native 7z header
  readers, the 7z archive-signature discriminator, and fixed-width little-endian start-header writers.
- `Zlib.Seven_Zip_Header_Reading`, covering the encoded-header byte-availability wrapper, PPMd property
  bounds gate, and local CRC adapter.
- `Zlib.Seven_Zip_Properties`, covering scalar FilesInfo bitmap and little-endian UInt32/UInt64 readers used by
  native archive extraction, plus the leap-year helper used by FILETIME metadata conversion.
- `Zlib.Seven_Zip_Volumes`, covering deterministic multi-volume suffix formatting.
- `Zlib.Huffman`, covering decode-table reset, canonical-code bit reversal, and bounded decode-table insertion.
- `Zlib.Huffman_Builder`, covering bounded code-length width calculation.
- `Zlib.Raw_Inflate`, covering the dynamic-Huffman nonzero code-length predicate used by complete-buffer
  raw Deflate decoding.
- `Zlib.Sliding_Window`, covering the stream-output boundary helper, bounded modular index arithmetic,
  back-reference index calculation, and read-only output/copy-state accessors.
- `Zlib.Stream_Bits`, covering bit-count representability checks used before little-endian field reads.
- `Zlib.Stream_Inflate`, covering scalar streaming-wrapper header and gzip/zlib flag predicates, dynamic-Huffman
  nonzero code-length validation, plus read-only lifecycle/status accessors.
- `Zlib.Fuzzing`, covering deterministic fuzz-result acceptance/equality predicates and the bounded internal
  hexadecimal nibble formatter used by fuzz summaries.

The compression, decompression, file, stream, gzip metadata parsing, fixed-Huffman emission, full token scoring,
full Huffman table construction, full 7z FilesInfo property parsing, branch/Delta filter transforms, and fuzz input
generation/execution internals remain ordinary Ada for now.
They use dynamic buffers, stream I/O, access-backed state, container-backed assembly, `out`-parameter parsing helpers,
and dense bit-level algorithms. Those paths are covered by the release test suite, examples, smoke tests,
deterministic fuzz drivers, and `tools/bin/check_all`.
