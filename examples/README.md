# Zlib examples

Build all examples:

```sh
alr exec -- gprbuild -P examples/examples.gpr
```

All examples print a short success/status message and set a non-zero process
exit status on detected API or data failure. They are examples, not the release
test suite; the release path remains `tools/bin/check_all`.

Examples use only the public root package:

```ada
with Zlib;
```

`quickstart.adb` is the compiled source of truth for the top-level README quickstart.

`example_raw_support.adb` / `example_raw_support.ads` are shared helper units
for the raw and streaming examples and are intentionally not standalone mains.

## One-shot inflate examples

- `inflate_file.adb` — one-shot zlib file inflate.
- `inflate_raw_file.adb` — one-shot raw Deflate file inflate.
- `inflate_with_header.adb` — explicit one-shot zlib/gzip/raw wrapper selection.
- `inflate_raw.adb` — `Inflate_Raw` convenience wrapper for complete raw Deflate payloads.
- `gzip_multimember_inflate.adb` — explicit multi-member gzip input decoding.

## One-shot compression examples

- `deflate_stored_file.adb` — one-shot stored-block zlib file output.
- `deflate_fixed_file.adb` — one-shot fixed-Huffman zlib file output.
- `deflate_dynamic_file.adb` — one-shot dynamic-Huffman zlib file output.
- `deflate_raw_file.adb` — one-shot raw Deflate file output.
- `gzip_file.adb` — one-shot gzip file output.
- `compress_with_level.adb` — broad `Compression_Level` policy for zlib, gzip, and raw output.
- `gzip_with_metadata.adb` — one-shot gzip output with explicit `GZip_Metadata` and roundtrip verification.
- `dictionary_roundtrip.adb` — preset-dictionary zlib compression and matching dictionary inflate.
- `checksums.adb` — public compression-bound helpers.

## In-memory roundtrip examples

- `roundtrip_stored.adb` — in-memory stored-output/inflate roundtrip.
- `roundtrip_fixed.adb` — in-memory fixed-Huffman output/inflate roundtrip.
- `roundtrip_dynamic.adb` — in-memory dynamic-Huffman output/inflate roundtrip.
- `raw_roundtrip.adb` — raw Deflate output plus one-shot and streaming raw inflate.
- `raw_vs_zlib_vs_gzip.adb` — compares raw, zlib-wrapped, and gzip-wrapped output.

## Streaming examples

- `streaming_inflate_zlib.adb` — streaming zlib inflate with exception handling.
- `streaming_inflate_gzip.adb` — streaming gzip inflate with exception handling.
- `streaming_deflate_zlib.adb` — streaming zlib compression with small buffers.
- `streaming_deflate_gzip.adb` — streaming gzip compression with small buffers.
- `streaming_deflate_raw.adb` — streaming raw Deflate compression with small buffers.
- `streaming_roundtrip_zlib.adb` — streaming zlib compression followed by inflate verification.
- `streaming_roundtrip_gzip.adb` — streaming gzip compression followed by inflate verification.

## Streaming file examples

- `deflate_file_streaming.adb` — bounded-buffer zlib file compression.
- `inflate_file_streaming.adb` — bounded-buffer zlib file inflate.
- `gzip_file_streaming.adb` — bounded-buffer gzip file compression.
- `deflate_raw_file_streaming.adb` — bounded-buffer raw Deflate file compression.
- `inflate_raw_file_streaming.adb` — bounded-buffer raw Deflate file inflate.

## Raw Deflate support code

- `example_raw_support.adb` and `example_raw_support.ads` contain reusable cleanup helpers for raw examples.
  Exception paths close open filters with `Ignore_Error => True`, while top-level examples report `Zlib_Error`
  and `Status_Error` as process failures.
