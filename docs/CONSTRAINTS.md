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
- reentrant independent operations without hidden synchronization of shared
  caller-owned mutable state
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
- multi-member gzip inflate by default
- explicit strict single-member gzip inflate through
  `GZip_Member_Mode => Single_Member`
- streaming raw Deflate inflate through `Header => Raw_Deflate`
- one-shot raw Deflate output through `Deflate_Raw` and `Deflate_Raw_File`
  for `Stored`, `Fixed`, `Dynamic`, and `Auto`
- streaming raw Deflate output through `Header => Raw_Deflate` for `Stored`,
  `Fixed`, `Dynamic`, and `Auto`
- explicit one-shot gzip and raw Deflate inflate through `Inflate_With_Header`
- compression levels 0 through 9 as broad strategy/effort policy
- gzip metadata output through explicit `GZip_Metadata` APIs
- native stored, Deflate, BZip2, LZMA, LZMA2, and PPMd `.7z`
  output/extraction, including general PPMd7 encode/decode, stock-7z
  non-solid multi-block streams with LZMA encoded headers, stock-7z no-stream
  empty-file entries, stock-7z BCJ+PPMd filter chains, BCJ2 graphs with Copy,
  PPMd, or supported main pre-coders, covered solid substream layouts, and
  bounded linear filter-chain extraction layouts made from supported
  single-input coders and branch/Delta filters, including standard zero-based,
  reverse-linear, and reordered zero-based and legacy one-based linear bind
  pairs,
  through `Seven_Zip_Stored`, `Seven_Zip_Deflate`, `Seven_Zip_BZip2`,
  `Seven_Zip_LZMA`, `Seven_Zip_LZMA2`, `Seven_Zip_Filtered`,
  `Seven_Zip_Method_Graph`, their file helpers, and their file-list helpers
- native AES-256 7z payload encryption/decryption, encrypted headers, and
  password handling via the sibling Ada `cryptolib` crate
- solid LZMA, LZMA2, and PPMd multi-entry 7z writers, including encrypted
  solid archives
- multi-volume 7z read/write helpers
- branch-filter encode/decode for x86, ARM, ARM64, ARMT, PPC, SPARC, IA-64,
  RISC-V JAL, and Delta; RISC-V stock-7z validation is wired into the optional
  interop lane and runs when stock 7-Zip 24.x+ is available
- neutral native extraction aliases through `Extract_Seven_Zip`,
  `Extract_Seven_Zip_File`, and `Extract_Seven_Zip_Files`
- zlib preset dictionary compression, inflate, and streaming file APIs
- internal Adler-32 and CRC32 wrapper/archive validation through CryptoLib.Checksums
- deterministic fuzzing tools and smoke tests
- stored, fixed-Huffman, and dynamic-Huffman Deflate decoding
- bounded 32 KiB LZ77 sliding-window history
- deterministic lifecycle/error behavior

The project goal is **full, complete in-process 7z encode and decode**:
read any standard `.7z` archive `7z`/p7zip can produce, and produce archives
they can read, all in pure Ada with no external codec libraries.

Remaining work toward full 7z support:

- RISC-V stock-7z branch-filter validation execution on a stock 7-Zip 24.x+
  binary; the validation lane is implemented and skipped on older binaries

The native 7z APIs are in-process container APIs. `Seven_Zip_Stored`
handles stored files with the 7z Copy coder, `Seven_Zip_Deflate` handles raw
Deflate payloads, `Seven_Zip_BZip2` handles BZip2 payloads, `Seven_Zip_LZMA`
handles LZMA payloads with the library default properties, `Seven_Zip_LZMA2`
handles valid LZMA2 chunks, and `Seven_Zip_PPMd` handles PPMd7 payloads.
The corresponding `*_Files`
helpers write multi-entry file-list archives with independently packed file
entries, no-stream directory entries, and distinct entry names.
`Seven_Zip_PPMd`, `Seven_Zip_PPMd_File`, and
`Seven_Zip_PPMd_Files` emit native PPMd archives
accepted by this crate's native extractor and stock `7z` without calling a
local `7z`.
`Seven_Zip_Filtered` emits a single-entry two-coder compressed filtered folder
with one supported pre-filter and one supported terminal codec; stock `7z`
accepts the generated BCJ+LZMA and Delta+LZMA archives covered by the optional
interop tool.
`Seven_Zip_Method_Graph` emits arbitrary supported non-encrypted single-entry
method-graph containers from caller-supplied packed stream bytes and zero-based
7z bind-pair and packed-stream indices. The graph writer does not automatically
execute arbitrary codec graphs from plain input.
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

Unsupported broader 7z creation and extraction requests fail closed with
deterministic status codes.
