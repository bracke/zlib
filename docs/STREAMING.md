# Streaming API contract

This document is the consumer-facing contract for `Filter_Type`,
`Inflate_Init`, `Translate`, `Flush`, `Stream_End`, and `Close`.

## Supported wrappers and payloads

Supported:

- `Header => Default`: exactly the same as `Zlib_Header`
- `Header => Zlib_Header`: zlib wrapper, Deflate payload, Adler-32 trailer
- `Header => GZip`: gzip member input containing a Deflate payload, CRC32 trailer, and ISIZE trailer;
  strict single-member mode is the default, and explicit multi-member mode is available through the overload
  that takes `GZip_Member_Mode`
- `Header => Raw_Deflate`: Deflate payload only, with no wrapper and no trailer checksum

Supported Deflate payloads:

- stored blocks (`BTYPE = 00`)
- fixed-Huffman blocks (`BTYPE = 01`)
- dynamic-Huffman blocks (`BTYPE = 10`)

Unsupported:

- auto-detecting gzip or raw data through `Default`
- implicit multi-member gzip concatenation in the default `GZip` mode
- wrapper auto-detection for strict one-shot or streaming inflate APIs

Unsupported wrappers or malformed block types fail deterministically with
`Zlib_Error`.


## Relationship to one-shot inflate

`Inflate` is zlib-wrapper-only and is equivalent to `Inflate_With_Header` with
`Header => Zlib_Header`. Complete gzip or raw Deflate buffers should use
`Inflate_With_Header` with `Header => GZip` or `Header => Raw_Deflate`.
Streaming callers should continue to use `Inflate_Init` with the matching
`Header_Type`; no wrapper auto-detection is performed by strict APIs.
`Inflate_Auto` is the explicit one-shot convenience API for lightweight wrapper
discrimination.

## State model

`Filter_Type` is limited private. Externally observable states are:

| State | Observable behavior |
| --- | --- |
| Closed | Default state and state after `Close`; `Is_Open` is `False`. |
| Open | State after `Inflate_Init`; `Is_Open` is `True`. |
| Failed | State after fatal `Zlib_Error`; `Is_Open` remains `True` until `Close`. |
| Ended | State after full wrapper-validated stream end; `Is_Open` remains `True` until `Close`. |

`Inflate_Init` may be called on a closed, open, failed, or ended filter. It
resets all previous state and starts a fresh session.

## `Inflate_Init`

```ada
Zlib.Inflate_Init (Filter, Header => Zlib.Zlib_Header);
```

Effects:

- opens the filter;
- records the selected wrapper mode;
- resets bitstream, output-window, Deflate, wrapper, and checksum state;
- clears previous failure status.

## `Translate`

`Translate` feeds input and writes decoded output into a caller-supplied output
buffer.

It always initializes `In_Last` and `Out_Last` before raising any exception.
It consumes as much input as useful, writes at most `Out_Data'Length` bytes, and
may return with no progress when it needs more input or more output capacity.

With `Flush => No_Flush`, missing additional input is not an error. With
`Flush => Finish`, the call must reach wrapper-validated stream completion or
raise `Zlib_Error`.

`Translate` raises:

- `Status_Error` for lifecycle misuse, such as use before `Inflate_Init` or
  after `Close`;
- `Zlib_Error` for malformed headers, invalid stored-block lengths, invalid
  Huffman trees/codes, invalid LZ77 distances, invalid checksums, invalid
  block types, invalid raw Deflate payloads, or truncation under `Finish`.

## `Flush`

`Flush` drains pending decoded output without adding new input.

- `Flush => No_Flush`: returns normally when no output is pending.
- `Flush => Finish`: requires `Stream_End = True`; otherwise it marks the
  filter failed and raises `Zlib_Error`.

`Flush` also initializes `Out_Last` before any exception.

## `Stream_End`

`Stream_End` returns `True` only after all required stream-end conditions have
been satisfied.

For zlib streams:

- the Deflate final block has ended;
- the Adler-32 footer has been fully read;
- the computed Adler-32 matches the footer.

For gzip streams:

- the Deflate final block for the active member has ended;
- the CRC32 trailer has been fully read and validated;
- the ISIZE trailer has been fully read and validated;
- in explicit multi-member mode, every concatenated member has completed the same validation.

For raw Deflate streams:

- the Deflate final block has ended;
- all pending decoded output has been drained.

Seeing the Deflate end-of-block symbol alone is not enough for wrapped streams,
and `Stream_End` is not true for any mode while decoded output remains pending.

## `Close`

`Close` releases/reset owned internal state.

| Call | Result |
| --- | --- |
| `Close` before init, `Ignore_Error = False` | raises `Status_Error` |
| `Close` before init, `Ignore_Error = True` | no-op |
| `Close` after incomplete open stream, `Ignore_Error = False` | clears state and raises `Zlib_Error` |
| `Close` after incomplete open stream, `Ignore_Error = True` | closes silently |
| `Close` after Failed state, `Ignore_Error = False` | clears state and raises `Zlib_Error` |
| `Close` after Failed state, `Ignore_Error = True` | closes silently |
| `Close` after `Stream_End` | closes normally |

`Close (Ignore_Error => True)` is appropriate in exception cleanup paths.

## Failed-state behavior

After `Zlib_Error`, the filter enters Failed state.

- `Is_Open` returns `True`.
- Further `Translate` calls raise `Zlib_Error`.
- Further `Flush` calls raise `Zlib_Error`.
- `Close (Ignore_Error => True)` closes silently.
- `Close (Ignore_Error => False)` clears state and raises `Zlib_Error`.

## `In_Last` and `Out_Last`

Ada stream arrays may have arbitrary bounds. The API uses this convention:

- for non-null input, `In_Last` is the last consumed index;
- if no input was consumed, `In_Last = In_Data'First - 1`;
- for null input arrays, `In_Last = In_Data'First`;
- for non-null output, `Out_Last` is the last written index;
- if no output was written, `Out_Last = Out_Data'First - 1`;
- for null output arrays, `Out_Last = Out_Data'First`.

With a null output buffer and `No_Flush`, `Translate` and `Flush` return after
lifecycle validation without consuming input or decoding additional bytes. With
a null output buffer and `Finish`, the completion check still applies.

## zlib vs gzip header behavior

`Default` and `Zlib_Header` parse a zlib wrapper: CMF/FLG header, Deflate
payload, and Adler-32 trailer.

`GZip` parses a gzip wrapper: gzip header, optional FEXTRA/FNAME/FCOMMENT/FHCRC
fields, Deflate payload, and CRC32/ISIZE trailer.

The gzip implementation accepts exactly one member. Extra bytes after the first
completed member are not decoded as a second member.

## One-shot bridge

The public one-shot `Inflate` function uses the same streaming engine
internally. It maps streaming `Zlib_Error` failures to deterministic
`Status_Code` values and preserves the status-code based one-shot contract.

## Conformance notes

The streaming API is covered by a chunk matrix using input chunk sizes `1`, `2`,
`3`, `5`, and full input, and output buffer sizes `1`, `2`, `7`, and full
expected output. `In_Last` and `Out_Last` must always remain inside their
respective buffers or use the documented no-consumption/no-output marker.

`Stream_End` becomes true only after the active wrapper has been fully validated:
Adler-32 for zlib, CRC32/ISIZE for gzip, and Deflate final-block completion for
raw Deflate. `Close` succeeds after valid `Stream_End`. Malformed or truncated
input raises `Zlib_Error`; lifecycle misuse raises `Status_Error`. After a
failure, `Close (Ignore_Error => True)` is valid cleanup.

## Streaming gzip member boundaries

`Inflate_Init` defaults to `GZip_Mode => Single_Member`. In this mode a gzip
stream is complete after exactly one validated member; extra input supplied with
`Flush => Finish` is rejected.

`GZip_Mode => Multi_Member` enables concatenated gzip input. A validated member
boundary is not necessarily `Stream_End`: the decoder resets its per-member gzip
and Deflate state and continues when buffered input or caller input contains the
next member. `Stream_End` becomes true only after `Finish` confirms that the
logical concatenated gzip stream is complete and all pending output has been
drained.

In `Multi_Member` mode, completing one member under `No_Flush` returns control
to the caller and does not imply `Stream_End`. A later `Translate` call may
provide the next member. A later `Flush (Finish)` finalizes the logical gzip
stream when no next-member bytes are pending.

## Streaming inflate dictionaries

A preset dictionary must be supplied after `Inflate_Init` and before Deflate
payload decoding starts:

```ada
Inflate_Init (Filter, Header => Zlib_Header);
Inflate_Set_Dictionary (Filter, Dictionary);
Translate (...);
```

Only the last 32 KiB of the dictionary seeds LZ77 history. Dictionary bytes are
history only and are never emitted as output. If the zlib header does not set
`FDICT`, any proactively supplied dictionary is ignored for that stream.

## Streaming file APIs

Bounded-memory file helpers are available for consumers that must process files without buffering the complete input or output in memory:

```ada
Inflate_File_Streaming
Inflate_File_With_Dictionary_Streaming
Deflate_File_Streaming
Deflate_File_With_Dictionary_Streaming
GZip_File_Streaming
Deflate_Raw_File_Streaming
```

The one-shot convenience file APIs remain available. The `*_File_Streaming` APIs open input and output files, process fixed-size internal chunks, preserve binary data including NUL and high-byte values, and close files on both success and failure. They support the same wrapper separation used elsewhere: zlib, gzip, and raw Deflate are selected explicitly where applicable.

Dictionary-aware zlib file streaming is available through `Inflate_File_With_Dictionary_Streaming` and `Deflate_File_With_Dictionary_Streaming`. These helpers are zlib-header-only because gzip and raw Deflate do not use the zlib FDICT wrapper mechanism.
