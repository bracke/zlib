# Streaming API contract

This document is the consumer-facing contract for `Filter_Type`,
`Inflate_Init`, `Translate`, `Flush`, `Stream_End`, and `Close`.

## Task safety

Streaming inflate is safe for parallel callers when each Ada task uses its own
`Filter_Type` object and caller-owned input/output buffers. A `Filter_Type` is
mutable session state and is not internally synchronized; protect it externally
if it is shared between tasks.

## Supported wrappers and payloads

Supported:

- `Header => Default`: lightweight wrapper auto-detection for zlib, gzip, or raw Deflate input
- `Header => Zlib_Header`: zlib wrapper, Deflate payload, Adler-32 trailer
- `Header => GZip`: gzip member input containing a Deflate payload, CRC32 trailer, and ISIZE trailer;
  multi-member mode is the default, and explicit single-member mode is available through the overload
  that takes `GZip_Member_Mode`
- `Header => Raw_Deflate`: Deflate payload only, with no wrapper and no trailer checksum

Supported Deflate payloads:

- stored blocks (`BTYPE = 00`)
- fixed-Huffman blocks (`BTYPE = 01`)
- dynamic-Huffman blocks (`BTYPE = 10`)

Unsupported:

- implicit wrapper switching after the first stream has been detected in an already-open streaming filter

Unsupported wrappers or malformed block types fail deterministically with
`Zlib_Error`.


## Relationship to one-shot inflate

`Inflate`, `Inflate_Auto`, one-shot `Inflate_With_Header` with
`Header => Default`, and streaming `Inflate_Init` with `Header => Default` use
lightweight wrapper auto-detection for zlib, gzip, or raw Deflate input. Gzip
one-shot and streaming paths accept concatenated members by default; pass
`GZip_Mode => Single_Member` when strict single-member boundaries are required.
Streaming callers can still use concrete `Header_Type` values when wrapper
strictness is required.

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

`Default` waits until two prefix bytes are available, then selects gzip for
`1F 8B`, zlib for a syntactically valid zlib CMF/FLG pair, and raw Deflate
otherwise. The selected wrapper stays fixed for the life of that filter.

`Zlib_Header` parses a zlib wrapper: CMF/FLG header, Deflate payload, and
Adler-32 trailer.

`GZip` parses a gzip wrapper: gzip header, optional FEXTRA/FNAME/FCOMMENT/FHCRC
fields, Deflate payload, and CRC32/ISIZE trailer.

The gzip implementation accepts concatenated members by default. Extra bytes
after the first completed member are rejected only when
`GZip_Mode => Single_Member` is selected.

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

`Inflate_Init (Filter, Header => GZip)` and detected gzip streams from
`Inflate_Init (Filter, Header => Default)` default to
`GZip_Mode => Multi_Member`. A validated member boundary is not necessarily
`Stream_End`: the decoder resets its per-member gzip and Deflate state and
continues when buffered input or caller input contains the next member.
`Stream_End` becomes true only after `Finish` confirms that the logical
concatenated gzip stream is complete and all pending output has been drained.

`GZip_Mode => Single_Member` is the strict override. In this mode a gzip stream
is complete after exactly one validated member; extra input supplied with
`Flush => Finish` is rejected.

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
