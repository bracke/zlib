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
| `Insufficient_Memory` | Not enough memory to hold an intermediate or final result. |

`Status_Image` returns release-contract diagnostic text for each status.

`Insufficient_Memory` does not implicate the input. A well-formed stream or
archive reports it when the decoded payload does not fit in available memory,
so it must not be read as `Unexpected_End_Of_Input`, which means the input
really was truncated.

## Memory needed to decode

One-shot APIs that return a decoded `Byte_Array` build that result on the
stack, so the practical limit for `Inflate` and friends is the calling task's
stack size rather than the heap. Callers decoding large payloads should run the
call in a task with a sufficient `Storage_Size`.

`Extract_Archive_File_To_Directory` is the exception. For a ZIP whose members
all use Stored or Deflate, it reads only the central directory and then streams
each member from the archive file straight to its output file, so its working
memory is a small fixed amount independent of both the archive size and the
size of any member. Such an archive extracts in well under a megabyte of stack
however large it is.

Members whose method is neither Stored nor Deflate are not streamed, but they
no longer spoil the archive: such a member is rebuilt as a single-entry image
holding only its own compressed bytes and decoded from that, so the cost is
that one member rather than the whole archive. A mostly-Deflate archive with
one BZip2 member therefore still extracts in memory proportional to its largest
member.

An encrypted member is rebuilt the same way, keeping its encryption flag so it
can be decrypted with the caller's password, so it too costs one member rather
than the archive.

`Extract_Archive_To_Directory` takes an image the caller already holds in
memory and is unaffected.

A `.7z` is read from its signature header, its header, and the packed streams
of the folders a request actually touches, so the archive itself is never read
whole. That holds for extracting one member and for extracting the whole
archive to a directory, which goes member by member off the catalogue. A compressed header, which `7z a` writes by default, is decoded and then used
in place, so it costs no more than a plain one.

What remains is the folder, and that is the format's own bound rather than an
implementation limit: 7z groups files into folders that share one coder chain,
and any file in a folder requires decoding that whole folder. For a non-solid
archive a folder is one member, and extracting one 800 KB member from a 9.6 MB
archive needs about a megabyte. For a solid archive -- also a `7z a` default --
one folder holds everything, so the cost is the archive's whole decompressed
content and no amount of streaming can reduce it. Callers who care should write
archives with `-ms=off`.

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
