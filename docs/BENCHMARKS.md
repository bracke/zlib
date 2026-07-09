# Benchmarks

The benchmark tools are intended to compare deterministic zlib/gzip/raw Deflate
output across stored, fixed, dynamic, and Auto policies. They are smoke and
regression aids, not a promise of zlib-equivalent output or ratio.
Compression and inflate tools report the last run, aggregate throughput, and
repeat-aware minimum, maximum, and average byte counts so local before/after
comparisons can separate deterministic output size from timing variance.

## Match-search baseline

Levels 4 through 7 use conservative lazy LZ77 matching, and levels 8 and 9 use
bounded block-local optimal parsing over the configured match candidates. Levels
2 and 3 remain greedy, level 1 remains fixed-Huffman, and level 0 remains
stored. Benchmark comparisons should therefore record the compression level and
mode alongside the input fixture.

Match search is bounded and block-local. It may improve compression ratio on
common repeated data, but it is not a whole-stream optimizer and it is not
expected to match external zlib byte output. Equal-length matches prefer lower
Deflate distance-extra-bit cost, then shorter absolute distance, so distance
distribution can affect high-level ratio. Lazy levels may also defer one byte
for an equal-length next match when the lower distance cost pays for the extra
literal. Flush-heavy streaming benchmarks should be interpreted separately
because `Sync_Flush`, `Full_Flush`, and `Finish` finalize the current block and
stop lazy lookahead at the boundary.

The `ratio` field describes the last measured run. The `avg ratio` field is
computed from aggregate bytes across all repeats; for deterministic compression
runs these should normally match, while inflate runs use the compressed input
bytes over decoded output bytes.

`tools/bin/zlib_bench_matrix` provides a compact CSV benchmark sweep over the
three deterministic synthetic payload families, zlib/gzip/raw wrappers, and
levels 0, 1, 6, and 9. Use it for quick local before/after comparisons before
choosing more focused single-case benchmark commands. Matrix rows include
last-run ratio, aggregate ratio, minimum/maximum/average compressed bytes, and
percentage saved relative to the input size.

## Release benchmark smoke

Before publishing benchmark numbers, run the normal release commands first:

```sh
alr build
alr exec -- gprbuild -P zlib.gpr
cd tests && alr exec -- gprbuild -P tests.gpr
cd tests && ./bin/tests
alr exec -- gprbuild -P tools/tools.gpr
./tools/bin/smoke_test
tools/bin/check_all
```
