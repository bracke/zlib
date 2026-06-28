# Zlib tools

These command-line tools use only the public `Zlib` root package.

Build:

```sh
alr exec -- gprbuild -P tools/tools.gpr
```

Run:

```sh
./tools/bin/zlib_deflate_stored_file INPUT OUTPUT.z
./tools/bin/zlib_deflate_fixed_file INPUT OUTPUT.z
./tools/bin/zlib_deflate_dynamic_file INPUT OUTPUT.z
./tools/bin/zlib_inflate_file [--header=zlib|gzip|raw] INPUT OUTPUT
./tools/bin/zlib_compress_file --level=6 INPUT OUTPUT.z
./tools/bin/gzip_file --level=6 INPUT OUTPUT.gz
./tools/bin/raw_deflate_file --level=6 INPUT OUTPUT.deflate
./tools/bin/raw_inflate_file INPUT.deflate OUTPUT
./tools/bin/gzip_metadata_file --mode=auto --name=payload.bin --comment=demo --mtime=0 --os=255 INPUT OUTPUT.gz
./tools/bin/smoke_test
```

`tools/bin/check_all` runs the release checklist and fails fast.

## Optional benchmarks

Ada-only benchmark/profiling tools are included. They are intentionally not part
of the correctness test runner and should not be used for wall-clock assertions.
The compression benchmarks verify roundtrips by default and fail with a non-zero
process exit status on compression, inflate, parsing, or verification errors.

Build all tools with:

```sh
alr exec -- gprbuild -P tools/tools.gpr
```

Compression benchmarks:

```sh
./tools/bin/zlib_bench_deflate --pattern=text-like --size=1048576 --wrapper=zlib --mode=auto --repeat=5
./tools/bin/zlib_bench_gzip --input payload.bin --mode=dynamic --input-chunk=4096 --output-chunk=1024
./tools/bin/zlib_bench_raw --pattern=repeated --size=1048576 --level=6 --no-verify
```

Compression benchmark options:

```text
--input FILE
--pattern=random-ish|repeated|text-like
--size BYTES
--wrapper=zlib|gzip|raw
--mode=stored|fixed|dynamic|auto
--level=0..9
--input-chunk BYTES
--output-chunk BYTES
--repeat N
--no-verify
```

`--mode` and `--level` are mutually exclusive. When `--input` is not supplied,
the tools use deterministic Ada-generated synthetic input.

Inflate benchmark:

```sh
./tools/bin/zlib_bench_inflate --input payload.z --wrapper=zlib --expect-size=1048576 --repeat=5
```

Inflate benchmark options:

```text
--input FILE
--wrapper=zlib|gzip|raw
--input-chunk BYTES
--output-chunk BYTES
--repeat N
--expect-size BYTES
```


## Raw Deflate tools

Public-API raw Deflate tools:

- `raw_deflate_file (--mode=stored|fixed|dynamic|auto | --level=0..9) INPUT OUTPUT`
- `raw_inflate_file INPUT OUTPUT`
- `raw_roundtrip INPUT`
- `raw_vs_zlib_vs_gzip INPUT`

`raw_deflate_file` writes raw Deflate payload bytes only. The output has no zlib
header, no Adler-32 trailer, no gzip header, no CRC32 trailer, and no ISIZE
trailer. Use `raw_inflate_file` for the raw-inflate convenience API,
or use `zlib_inflate_file --header=raw` for the general explicit-wrapper path.

Build and smoke-test with:

```sh
alr exec -- gprbuild -P tools/tools.gpr
./tools/bin/smoke_test
```

## Gzip metadata tool

`gzip_metadata_file` writes a gzip member with explicit `GZip_Metadata`. It sets
`FNAME`, `FCOMMENT`, `MTIME`, `OS`, and `FHCRC`, then writes the gzip payload
with the selected compression mode. Metadata is accepted only for gzip output;
zlib and raw Deflate tools continue to emit wrapper-specific output without
gzip metadata.


## Compression level option

`zlib_compress_file`, `gzip_file`, and `raw_deflate_file` accept either an exact
`--mode=stored|fixed|dynamic|auto` option or a broad `--level=0..9` option.
Level `0` maps to stored output, level `1` maps to fixed-Huffman output, and
levels `2..9` map to Auto in this release.

## Deterministic fuzzing tools

The release includes deterministic Ada-native fuzz drivers under `tools/fuzz/`. They
are built by `tools/tools.gpr` and accept optional positional arguments:

```text
<iterations> <seed>
```

Available drivers:

- `fuzz_inflate`
- `fuzz_streaming_inflate`
- `fuzz_compress_roundtrip`
- `fuzz_compress_levels`
- `fuzz_wrapper_mix`
- `fuzz_dictionary`
- `fuzz_gzip_metadata`
- `fuzz_mutation`
- `fuzz_lifecycle`
- `fuzz_tiny_buffers`

Each summary includes target, seed, iteration count, deterministic result counts,
crash count, digest, last input length, and a hex snippet for reproduction.
The drivers use target-aware exit policy: arbitrary/corrupted-input targets allow
deterministic decode failures, while roundtrip-style targets fail on any
deterministic failure or crash. `tools/bin/check_all` runs short deterministic
fuzz smoke passes; longer fuzzing is manual.

Fuzz driver coverage:

| Driver | Purpose |
| --- | --- |
| `fuzz_inflate` | arbitrary complete zlib/gzip/raw inflate inputs |
| `fuzz_streaming_inflate` | arbitrary streaming inflate inputs, chunking, and small outputs |
| `fuzz_compress_roundtrip` | generated payload roundtrips across wrappers and modes |
| `fuzz_compress_levels` | level 0..9 policy roundtrips across wrappers |
| `fuzz_wrapper_mix` | wrapper mismatch rejection and gzip multi-member input policy |
| `fuzz_dictionary` | preset-dictionary success and mismatch behavior |
| `fuzz_gzip_metadata` | gzip FEXTRA/FNAME/FCOMMENT/MTIME/OS/XFL/FHCRC output paths |
| `fuzz_mutation` | corrupted stream rejection for zlib, gzip, and raw Deflate |
| `fuzz_lifecycle` | invalid inflate/compress lifecycle and flush sequencing |
| `fuzz_tiny_buffers` | one-byte/tiny-buffer decode paths for raw, zlib, gzip, and dictionary streams |

Detailed seed/reproducibility rules are in `docs/FUZZING.md`.
