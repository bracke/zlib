# Constraints

`Zlib` is a standalone Ada crate with a small root-package public contract.

## Must preserve

- root package `Zlib`
- public `Byte`, `Byte_Array`, and `Status_Code` declarations in `Zlib`
- one-shot `Inflate`
- one-shot `Inflate_With_Header`
- one-shot `Deflate_Stored`
- one-shot `Deflate_Fixed`
- one-shot `Deflate_Dynamic`
- one-shot native stored 7z output/extraction through `Seven_Zip_Stored` and
  `Extract_Seven_Zip_Stored`
- file helpers
- deterministic `Status_Code` failures for one-shot APIs
- public streaming API shape: `Filter_Type`, `Header_Type`, `Flush_Mode`,
  `Inflate_Init`, `Is_Open`, `Translate`, `Flush`, `Stream_End`, and `Close`
- deterministic streaming lifecycle behavior
- zlib Adler-32 validation
- gzip CRC32 and ISIZE validation

## Must not introduce

- `Zlib.Types`
- root-spec dependencies on child packages
- dependency on `version`
- dependency on `HttpClient`
- dependency on a system zlib library
- Python runtime fixture generation in normal tests
- unbounded bitstream history in `Zlib.Stream_Bits`
- use of the full decoded output as LZ77 history

## Current feature boundary

Implemented:

- zlib-wrapped one-shot inflate
- stored-block zlib output
- fixed-Huffman zlib output
- dynamic-Huffman zlib output
- streaming zlib inflate
- streaming single-member gzip inflate by default
- explicit multi-member gzip inflate through `GZip_Member_Mode => Multi_Member`
- streaming raw Deflate inflate through `Header => Raw_Deflate`
- one-shot raw Deflate output through `Deflate_Raw` and `Deflate_Raw_File`
  for `Stored`, `Fixed`, `Dynamic`, and `Auto`
- streaming raw Deflate output through `Header => Raw_Deflate` for `Stored`,
  `Fixed`, `Dynamic`, and `Auto`
- explicit one-shot gzip and raw Deflate inflate through `Inflate_With_Header`
- compression levels 0 through 9 as broad strategy/effort policy
- gzip metadata output through explicit `GZip_Metadata` APIs
- native stored, Deflate, BZip2, LZMA, and LZMA2 `.7z` output/extraction,
  plus native PPMd `.7z` extraction for empty streams with or without range
  headers, repeated-symbol, simple root-symbol, periodic-prefix, stock-7z non-solid multi-block streams with
  LZMA encoded headers, stock-7z no-stream empty-file entries, stock-7z
  BCJ+PPMd filter chains, BCJ2 graphs with Copy, PPMd, or supported main
  pre-coders, and unsupported-method failure for broader PPMd entries,
  plus covered solid substream, BCJ2 graph layouts with supported main
  pre-coders, and bounded linear filter-chain extraction layouts made from
  supported single-input coders and x86 BCJ/Delta filters, including standard
  zero-based, reverse-linear, and
  reordered zero-based and legacy one-based linear bind pairs,
  through `Seven_Zip_Stored`, `Seven_Zip_Deflate`, `Seven_Zip_BZip2`,
  `Seven_Zip_LZMA`, `Seven_Zip_LZMA2`, their file helpers, and their
  file-list helpers
- neutral native extraction aliases through `Extract_Seven_Zip`,
  `Extract_Seven_Zip_File`, and `Extract_Seven_Zip_Files`
- compatibility placeholders for former external 7z creation/extraction via
  `Seven_Zip_External_File` and `Extract_Seven_Zip_External_File`; these fail
  closed without invoking a local `7z` executable
- zlib preset dictionary compression, inflate, and streaming file APIs
- public Adler-32 and CRC32 checksum helpers
- deterministic fuzzing tools and smoke tests
- stored, fixed-Huffman, and dynamic-Huffman Deflate decoding
- bounded 32 KiB LZ77 sliding-window history
- deterministic lifecycle/error behavior

Not yet implemented (planned — see `docs/SEVEN_ZIP_PLAN.md`):

The project goal is **full, complete in-process 7z encode and decode**:
read any standard `.7z` archive `7z`/p7zip can produce, and produce archives
they can read, all in pure Ada with no external codec libraries. The list below
is current work-in-progress toward that goal, **not** a set of permanent
non-goals. The currently shipped layouts are progress, not the boundary.

Remaining work toward full 7z support:

- a general PPMd (variant H / PPMd7) encoder and decoder for arbitrary input,
  replacing the current generate-and-verify writer and the narrow decode subset
- AES-256 payload encryption, encrypted headers, and password-protected archives
- solid compression: a single shared compressed stream across multiple entries
  (not just independently packed per-entry substreams)
- the full branch-filter family for both encode and decode — ARM, ARM64, ARMT,
  PPC, SPARC, IA-64, and RISC-V — alongside the existing x86 BCJ and Delta
- a competitive LZMA/LZMA2 encoder (optimal parsing, tunable lc/lp/pb and
  dictionary) so output size matches stock `7z`, not just decodes correctly
- multi-volume (split) archives

Separately, the zlib Deflate compressor's whole-stream optimal parsing
(default-zlib-equivalent ratios) remains out of scope for the zlib path; it is
independent of the 7z LZMA encoder above.

The native 7z APIs are currently narrow in-process container APIs and are being
widened toward the full goal above. `Seven_Zip_Stored`
handles stored files with the 7z Copy coder, `Seven_Zip_Deflate` handles raw
Deflate payloads, `Seven_Zip_BZip2` handles BZip2 payloads, `Seven_Zip_LZMA`
handles LZMA payloads with the library default properties, and
`Seven_Zip_LZMA2` handles valid LZMA2 chunks. Native PPMd extraction covers
empty, repeated-symbol, simple root-symbol, periodic-prefix, stock-7z
non-solid multi-block streams with LZMA encoded headers, stock-7z
no-stream empty-file entries, stock-7z BCJ+PPMd filter chains, and
BCJ2 graphs with Copy, PPMd, or supported main pre-coders. The PPMd model table is allocated from the archive's
declared PPMd memory and requested output size rather than a fixed
stream-independent context cap; broader PPMd entries fail closed with a non-Ok
status.
The corresponding `*_Files`
helpers write multi-entry file-list archives with independently packed file
entries, no-stream directory entries, and distinct entry names.
`Seven_Zip_PPMd`, `Seven_Zip_PPMd_File`, and
`Seven_Zip_PPMd_Files` emit native PPMd archives
accepted by this crate's native extractor without calling local `7z`; empty
output uses a range-initialized empty stream, modeled stock-compatible
candidates use generated bytes, repeated/periodic payloads use specialized forms
when verified, and other supported payloads use a verified native root-context
fallback.
These native APIs do not imply
encryption or a native general-purpose 7z codec stack.
The native extractor skips SFX prefixes
and common archive/file metadata fields while extracting supported payload
layouts. Covered solid-substream, BCJ2 graph, and bounded linear filter-chain
layouts, including standard zero-based, reverse-linear, and reordered
zero-based linear bind pairs, are native extraction features. File and
file-list helpers restore supported per-entry directories, modification times,
and read-only attributes after writing output paths. Neutral
`Extract_Seven_Zip*` names fail
closed for unsupported 7z methods after native extraction reports
`Unsupported_Method`.
`Extract_Seven_Zip_Files`/`Extract_Seven_Zip_Stored_Files` extracts selected
entries below an output directory after requiring a non-empty destination and
prevalidating distinct requested names, and rejects unsafe absolute or
traversing output paths.
Duplicate matching entry names are rejected during extraction. Requested
payloads are verified before any output file is written.

For broader 7z use cases, the former external bridge APIs are retained as
compatibility placeholders. `Seven_Zip_External_File` and
`Extract_Seven_Zip_External_File` do not invoke local `7z`; unsupported broader
creation, extraction, unsupported solid layouts, and
password-protected archives fail closed with deterministic status codes. These
external APIs are separate from the deterministic native Copy/Deflate
writer/parser.
