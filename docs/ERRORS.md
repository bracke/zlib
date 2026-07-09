# Errors and status codes

`Zlib` has two public error models:

- one-shot APIs return `Status_Code`;
- streaming APIs raise `Status_Error` or `Zlib_Error`.

## One-shot `Status_Code`

| Status | Meaning |
| --- | --- |
| `Ok` | Operation completed successfully. |
| `Invalid_Header` | zlib header is malformed or fails wrapper validation. |
| `Unsupported_Method` | zlib/gzip compression method is not Deflate. |
| `Unsupported_Preset_Dictionary` | zlib header requests a preset dictionary but no matching dictionary was supplied. |
| `Invalid_Checksum` | Adler-32 validation failed for zlib input, or CRC32/ISIZE validation failed for gzip input. |
| `Invalid_Block_Type` | Deflate block type is invalid or unsupported. |
| `Invalid_Stored_Block` | Stored-block `LEN`/`NLEN` validation failed. |
| `Invalid_Huffman_Code` | Huffman table or symbol decoding failed. |
| `Invalid_Distance` | LZ77 distance is invalid for the current history window. |
| `Unexpected_End_Of_Input` | Input ended before the complete wrapper, Deflate payload, or trailer was available. |
| `Input_File_Error` | File input failed in a file helper. |
| `Output_File_Error` | File output failed in a file helper. |

`Status_Image` returns release-contract diagnostic text for each status.

## Streaming exceptions

### `Status_Error`

`Status_Error` means caller lifecycle misuse:

- `Translate` before `Inflate_Init`;
- `Translate` after `Close`;
- `Flush` before `Inflate_Init`;
- `Flush` after `Close`;
- `Close` on an unopened/closed filter when `Ignore_Error = False`.

### `Zlib_Error`

`Zlib_Error` means compressed-data failure or completion failure:

- malformed zlib/gzip header;
- malformed Deflate payload;
- unsupported wrapper feature or mode;
- invalid zlib Adler-32 footer;
- invalid gzip CRC32 or ISIZE trailer;
- truncated input when `Finish` requires completion;
- `Translate` or `Flush` after the filter has entered Failed state;
- `Close` on a failed or incomplete filter when `Ignore_Error = False`.

## Failed-state behavior

After streaming `Zlib_Error`, the filter enters Failed state and remains
explicitly closeable.

- `Is_Open` returns `True`.
- Further `Translate` calls raise `Zlib_Error`.
- Further `Flush` calls raise `Zlib_Error`.
- `Close (Ignore_Error => True)` closes silently.
- `Close (Ignore_Error => False)` clears state and raises `Zlib_Error`.

## Close behavior

| Call | Result |
| --- | --- |
| `Close` before init, `Ignore_Error = False` | raises `Status_Error` |
| `Close` before init, `Ignore_Error = True` | no-op |
| `Close` after incomplete open stream, `Ignore_Error = False` | clears state and raises `Zlib_Error` |
| `Close` after incomplete open stream, `Ignore_Error = True` | closes silently |
| `Close` after Failed state, `Ignore_Error = False` | clears state and raises `Zlib_Error` |
| `Close` after Failed state, `Ignore_Error = True` | closes silently |
| `Close` after `Stream_End` | closes normally |

## Consumer mappings

### `version`

`version` should use `Inflate`, `Inflate_File`, `Deflate_Stored`, or
`Deflate_Stored_File` and map any status other than `Ok` to an object
read/write failure. Include `Status_Image (Status)` in diagnostics.

### `HttpClient`

`HttpClient` should use the streaming API. Map both `Zlib_Error` and
`Status_Error` to `Decompression_Failed`. A `Status_Error` usually indicates an
adapter lifecycle bug, but the HTTP response should still be treated as failed
decompression.

## Deterministic failure matrix

Malformed and truncated conformance tests cover zlib bad CMF/FLG, preset
dictionary flag, bad Adler-32, truncated or missing Adler-32, gzip bad ID,
unsupported method, reserved FLG bits, truncated fixed and optional header
fields, bad CRC32, bad ISIZE, missing trailer, and raw Deflate truncation or
invalid coding cases.

One-shot APIs report these through documented `Status_Code` values. Streaming APIs
raise `Zlib_Error` for malformed/truncated data and `Status_Error` only for
lifecycle misuse. Cleanup after a data failure should call
`Close (Ignore_Error => True)`.


## Streaming compression error behavior

The compression-side API uses the same exception split as streaming inflate:
`Status_Error` is lifecycle misuse, while `Zlib_Error` is an unsupported
compression configuration, failed compression state, or incomplete/failed close.

Compression `Status_Error` cases include:

- `Compress` before `Deflate_Init`;
- `Compress` after `Compress_Close`;
- `Compress` with non-empty input after `Compress_Stream_End = True`;
- `Compress_Flush` before `Deflate_Init`;
- `Compress_Flush` after `Compress_Close`;
- `Compress_Close` on an unopened or already closed compression filter when
  `Ignore_Error = False`.

Compression `Zlib_Error` cases include:

- `Compress` or `Compress_Flush` after the compression filter has entered
  Failed state;
- `Compress_Close` on an incomplete or failed compression filter when
  `Ignore_Error = False`.

After compression `Zlib_Error`, `Is_Open` remains `True` until
`Compress_Close`. `Deflate_Init` on an incomplete or failed compression filter resets it and
starts a fresh session. Cleanup code should call
`Compress_Close (Ignore_Error => True)`.


## Streaming compression flush modes

`Sync_Flush` forces currently buffered compression input into the Deflate stream without ending it. It finishes the current block as non-final and emits an empty non-final stored block on a byte boundary. `Full_Flush` currently has the same byte-level behavior because the compressor has no cross-block match history; the distinction is preserved in the API and tests. Neither mode emits zlib/gzip trailers, and `Compress_Stream_End` remains `False` until `Finish`. Flush output may require repeated drain calls with small output buffers. `Finish` after a partially drained flush completes the pending flush work and then finalizes the stream. After stream end, `Sync_Flush` and `Full_Flush` are lifecycle misuse and raise `Status_Error`. Streaming inflate treats `Sync_Flush` and `Full_Flush` as `No_Flush`; Deflate flush markers are ordinary stored blocks.

## Preset dictionary failures

For zlib streams with `FDICT` set, missing caller dictionaries fail with
`Unsupported_Preset_Dictionary`. Caller dictionaries whose Adler-32 value does
not match the stream `DICTID` fail with `Invalid_Checksum`. Streaming APIs use
`Zlib_Error` for those data failures and `Status_Error` for lifecycle or wrapper
misuse.
