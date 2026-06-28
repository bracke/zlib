# SPARK Coverage

`zlib` runs GNATprove as part of release validation:

```sh
alr exec -- gnatprove -P zlib.gpr --level=4
```

The current SPARK-enabled public surface is intentionally narrow and deterministic:

- `Zlib.Status_Image`, the release-contract mapping from status codes to stable text.
- `Zlib.Looks_Like_Zlib_Header`, the lightweight zlib CMF/FLG discriminator.
- `Zlib.Looks_Like_GZip_Header`, the lightweight gzip magic/method/flag discriminator.

The compression, decompression, file, stream, gzip metadata, checksum, and fuzzing internals remain ordinary Ada for now. They use dynamic buffers, stream I/O, access-backed state, container-backed assembly, and dense bit-level algorithms. Those paths are covered by the release test suite, examples, smoke tests, deterministic fuzz drivers, and `tools/bin/check_all`.
