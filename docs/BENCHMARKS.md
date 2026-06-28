# Benchmarks

The benchmark tools are intended to compare deterministic zlib/gzip/raw Deflate
output across stored, fixed, dynamic, and Auto policies. They are smoke and
regression aids, not a promise of zlib-equivalent output or ratio.

## Match-search baseline

Levels 4 through 7 use conservative lazy LZ77 matching, and levels 8 and 9 use
bounded block-local optimal parsing over the configured match candidates. Levels
2 and 3 remain greedy, level 1 remains fixed-Huffman, and level 0 remains
stored. Benchmark comparisons should therefore record the compression level and
mode alongside the input fixture.

Match search is bounded and block-local. It may improve compression ratio on
common repeated data, but it is not a whole-stream optimizer and it is not
expected to match external zlib byte output. Flush-heavy streaming benchmarks should be
interpreted separately because `Sync_Flush`, `Full_Flush`, and `Finish` finalize
the current block and stop lazy lookahead at the boundary.

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
