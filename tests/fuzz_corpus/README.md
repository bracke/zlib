# Fuzz corpus fixtures

This directory is reserved for minimized deterministic fuzz regressions.

When a fuzz target exposes a real defect, add the minimized byte stream
or construction notes here and promote an executable regression to the normal
AUnit suite. Normal builds do not require a generated or external fuzz corpus.

Replay fixtures currently covered by `zlib_fuzz_smoke_tests`:

- `valid_zlib_empty.hex`
- `valid_gzip_empty.hex`
- `valid_raw_fixed_empty.hex`
- `truncated_zlib_header.hex`

Suggested fixture classes:

- valid zlib, gzip, and raw Deflate streams
- truncated wrapper headers and trailers
- corrupted Huffman trees and distances
- bad zlib checksums and gzip CRC/ISIZE trailers
- malformed gzip FEXTRA/FHCRC/FNAME/FCOMMENT fields
- dictionary mismatch streams
- tiny-buffer and chunk-boundary regressions
