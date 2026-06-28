# Streaming compression

The streaming compression API is the public, resumable counterpart to the
one-shot `Deflate`, `GZip`, and explicit `Deflate_*` operations. It is useful
when a consumer cannot or should not hold the whole uncompressed payload or the
whole compressed stream in memory.

Only the root package is required:

```ada
with Ada.Streams;
with Zlib;
```

Do not depend on internal child packages.

## Lifecycle

A compression stream has this lifecycle:

1. Declare a `Zlib.Compression_Filter_Type`.
2. Open it with `Zlib.Deflate_Init`.
3. Feed input with `Zlib.Compress`.
4. Drain pending output with `Zlib.Compress_Flush`.
5. Finish with `Flush => Zlib.Finish` until `Zlib.Compress_Stream_End` is true.
6. Close it with `Zlib.Compress_Close`.

`Zlib.Is_Open (Filter)` is true after `Deflate_Init` and remains true until
`Compress_Close`, including failed filters that still need cleanup.

`Compress_Close` raises `Zlib.Zlib_Error` for an open incomplete or failed
stream unless `Ignore_Error => True` is used. Use `Ignore_Error => True` in
exception cleanup paths.

## `In_Last` and `Out_Last`

`Compress` always initializes `In_Last` and `Out_Last`, including before raising
an exception.

`In_Last` is the last consumed input index. If no input was consumed, it is the
index immediately before `In_Data'First` when that marker is representable.

`Out_Last` is the last produced output index. If no output was produced, it is
the index immediately before `Out_Data'First` when that marker is representable.

Callers must treat both values as buffer-relative progress markers, not byte
counts. With small output buffers, a call may produce output without consuming
all input. Continue calling with the unconsumed suffix until the chunk is fully
consumed.

## Minimal zlib streaming compression

```ada
with Ada.Streams;
with Zlib;

procedure Example is
   use type Ada.Streams.Stream_Element_Offset;

   Filter  : Zlib.Compression_Filter_Type;
   Input   : constant Ada.Streams.Stream_Element_Array (1 .. 5) :=
     [1 => 104, 2 => 101, 3 => 108, 4 => 108, 5 => 111];
   Output  : Ada.Streams.Stream_Element_Array (1 .. 64);
   In_Last : Ada.Streams.Stream_Element_Offset;
   Out_Last : Ada.Streams.Stream_Element_Offset;
begin
   Zlib.Deflate_Init
     (Filter, Header => Zlib.Zlib_Header, Mode => Zlib.Auto);

   Zlib.Compress
     (Filter, Input, In_Last, Output, Out_Last, Zlib.No_Flush);

   while not Zlib.Compress_Stream_End (Filter) loop
      Zlib.Compress_Flush (Filter, Output, Out_Last, Zlib.Finish);
      --  Write Output (Output'First .. Out_Last) when Out_Last indicates data.
   end loop;

   Zlib.Compress_Close (Filter);
exception
   when others =>
      if Zlib.Is_Open (Filter) then
         Zlib.Compress_Close (Filter, Ignore_Error => True);
      end if;
      raise;
end Example;
```

## Minimal gzip streaming compression

Use the same lifecycle with `Header => Zlib.GZip`:

```ada
Zlib.Deflate_Init (Filter, Header => Zlib.GZip, Mode => Zlib.Auto);
```

The output is a deterministic gzip member with a minimal header and CRC32/ISIZE
trailer.

## Chunked input loop

A robust caller should pass chunks and retry the unconsumed suffix when the
output buffer fills:

```ada
First := Chunk'First;
while First <= Chunk'Last loop
   Zlib.Compress
     (Filter, Chunk (First .. Chunk'Last), In_Last, Out_Buffer, Out_Last,
      Zlib.No_Flush);

   Write_Produced_Output (Out_Buffer, Out_Last);

   if In_Last >= First then
      First := In_Last + 1;
   elsif Produced_Output (Out_Buffer, Out_Last) then
      null; --  Retry with the same First; output space was the bottleneck.
   else
      raise Program_Error with "compression made no progress";
   end if;
end loop;
```

## Small output buffer loop

The compressor is required to work with small output buffers, including
one-byte buffers. Small buffers are slower, but they are valid. This is useful
for adapters that write directly into fixed network or file buffers.

## Finish loop

`Flush => Zlib.Finish` finalizes the Deflate stream and emits the active wrapper
trailer. Keep draining until `Compress_Stream_End` is true:

```ada
while not Zlib.Compress_Stream_End (Filter) loop
   Zlib.Compress_Flush (Filter, Out_Buffer, Out_Last, Zlib.Finish);
   Write_Produced_Output (Out_Buffer, Out_Last);
end loop;
```

After stream end, `Compress_Flush` with `No_Flush` or `Finish` is idempotent
and produces no more bytes. `Compress_Flush` with `Sync_Flush` or
`Full_Flush` raises `Status_Error` because the stream can no longer be flushed.
After stream end, `Compress` with empty input and `No_Flush` or `Finish` is
idempotent; non-empty input or a new `Sync_Flush`/`Full_Flush` request is
lifecycle misuse and raises `Zlib.Status_Error`.

## Error handling

`Zlib.Zlib_Error` means the selected compression operation failed, the selected
wrapper/mode combination is unsupported, or close detected an incomplete or
failed stream.

`Zlib.Status_Error` means lifecycle misuse: using a closed filter, passing
non-empty input after stream end, or closing a closed filter without
`Ignore_Error => True`.

Use this cleanup pattern:

```ada
exception
   when others =>
      if Zlib.Is_Open (Filter) then
         Zlib.Compress_Close (Filter, Ignore_Error => True);
      end if;
      raise;
```

## Supported combinations

| Header | Stored | Fixed | Dynamic | Auto |
| --- | --- | --- | --- | --- |
| `Default` | supported | supported | supported | supported |
| `Zlib_Header` | supported | supported | supported | supported |
| `GZip` | supported | supported | supported | supported |
| `Raw_Deflate` | supported | supported | supported | supported |

`Default` means exactly `Zlib_Header`.

`Raw_Deflate` compression supports `Mode => Stored`, `Mode => Fixed`, `Mode => Dynamic`, and `Mode => Auto` and emits Deflate blocks only. It has no zlib header, Adler-32 footer, gzip header, CRC32 trailer, or ISIZE trailer. Raw `Auto` uses the same deterministic block-local policy as zlib/gzip Auto.

## Compression mode policy

`Stored` emits stored Deflate blocks.

`Fixed` emits fixed-Huffman Deflate blocks.

`Dynamic` emits bounded dynamic-Huffman Deflate blocks.

`Auto` is deterministic and block-local. Each pending block is selected as
the smallest valid Stored, Fixed, or Dynamic candidate by deterministic size scoring before bytes for that block
are emitted. Auto does not imply zlib-compatible compression-ratio levels, optimal parsing, lazy
matching beyond the configured level policy, global whole-stream buffering, or non-determinism. Level-based APIs may
map to Auto while preserving the same block-local behavior.

## Non-goals and omitted features

Compression-ratio tuning is bounded by the public level-to-policy mapping and
expanded high-level match-search effort. Levels 8 and 9 use bounded
block-local optimal parsing, but there is still no whole-stream optimal parser
or zlib-compatible ratio promise.

Sync flush and full flush are supported for streaming compression. Full flush is
currently byte-equivalent to sync flush because the compressor has no cross-block
match history to reset.

Streaming compression emits zlib, gzip, and raw Deflate streams. ZIP output
exists only through the one-shot/file-list `ZIP`, `ZIP_File`, and `ZIP_Files`
helpers.

Default gzip output remains the deterministic minimal header. Optional metadata
output is available only through explicit metadata overloads.


## Raw Deflate compression

`Header => Raw_Deflate` is an explicit compression contract, not an alias for
zlib or gzip output. With `Mode => Stored`, streaming compression emits stored
Deflate blocks only. It does not emit a zlib header, Adler-32 footer, gzip
header, CRC32 trailer, or ISIZE trailer. Empty input finalized with `Finish`
emits the valid final empty stored block `01 00 00 FF FF`.

`Header => Raw_Deflate` with `Mode => Auto` is supported. It uses the same block-local Stored/Fixed/Dynamic size-scoring policy as zlib/gzip Auto. The stream contains Deflate blocks only. It does not contain a zlib header, Adler-32 footer, gzip
header, gzip CRC32 trailer, or gzip ISIZE trailer. Raw output has no checksum;
use it only for containers or protocols that explicitly provide their own
framing and validation.


## Raw dynamic compression note

Raw_Deflate compression now supports `Stored`, `Fixed`, `Dynamic`, and `Auto`. Raw output is Deflate block data only: it has no zlib header, no Adler-32 footer, no gzip header, no CRC32 trailer, and no ISIZE trailer. Raw `Auto` uses the same deterministic block-local policy as zlib/gzip Auto. `Deflate_*` APIs remain zlib-wrapped, and `GZip*` APIs remain gzip-wrapped.


## Raw dynamic compression

`Header => Raw_Deflate, Mode => Dynamic` now emits dynamic-Huffman Deflate blocks only. It suppresses the zlib header, Adler-32 footer, gzip header, CRC32 trailer, and ISIZE trailer. `Raw_Deflate` with `Mode => Auto` is supported.

## One-shot bridge relationship

`Deflate_Raw` is the one-shot bridge over the raw streaming compressor. For the same payload and compression mode, it is expected to be semantically equivalent to a streaming session initialized with `Deflate_Init (Header => Raw_Deflate, Mode => Mode)`, drained with `Finish`, and closed. Raw bridge output has the same strict boundary as streaming raw compression: it inflates with `Header => Raw_Deflate` and must be rejected by zlib and gzip inflate paths.

## Wrapper strictness

Streaming compression has the same wrapper boundary as the one-shot APIs.
`Deflate_Init (Header => Zlib_Header | Default, Mode => ...)` emits zlib output,
`Header => GZip` emits gzip output, and `Header => Raw_Deflate` emits raw
Deflate output. All three wrappers support `Stored`, `Fixed`, `Dynamic`, and
`Auto`.

The streaming inflate side does not auto-detect wrappers. A stream produced with
`Header => Raw_Deflate` must be decoded with `Inflate_Init (Header =>
Raw_Deflate)`. Zlib-wrapped output must be decoded with `Header => Zlib_Header`
or `Default`, and gzip output must be decoded with `Header => GZip`. Supplying a
non-matching wrapper raises `Zlib_Error`; the failed filter remains closable with
`Close (Ignore_Error => True)`.

For raw output, `Compress_Stream_End` becomes true only after the final raw
Deflate block has been emitted and all pending output has been drained.
`Stream_End` becomes true only after the raw final block has been decoded and all
pending inflated output has been drained.


## Streaming raw Deflate compression

`Deflate_Init (Header => Raw_Deflate, Mode => Stored|Fixed|Dynamic|Auto)` opens
a streaming compressor that emits raw Deflate payload bytes only. The lifecycle
is unchanged: feed input with `Compress`, finish with `Compress_Flush (...,
Finish)` until `Compress_Stream_End`, then call `Compress_Close`.

For raw Deflate, `Compress_Stream_End` means the final Deflate block has been
fully emitted and drained. There is no zlib Adler-32 or gzip CRC32/ISIZE trailer
to emit. Small output buffers are supported; callers must collect every byte
reported through `Out_Last` before retrying.


## Raw Deflate release hardening

Raw Deflate compression is release-hardened by `zlib_raw_release_tests`, `zlib_raw_cross_wrapper_conformance_tests`, the raw examples, and the raw tools. The contract remains unchanged: `Deflate_*` APIs emit zlib-wrapped streams, `GZip*` APIs emit gzip-wrapped streams, `Deflate_Raw*` APIs emit raw Deflate blocks only, `Seven_Zip_Stored*` APIs emit Copy-coder `.7z` archives including header-only directory entries and solid stored file-list archives with no-stream directory entries, `Seven_Zip_Deflate*` APIs emit Deflate `.7z` archives, `Seven_Zip_BZip2*` APIs emit BZip2 `.7z` archives, `Seven_Zip_LZMA*` APIs emit LZMA `.7z` archives, `Seven_Zip_LZMA2*` APIs emit LZMA2 `.7z` archives, `Extract_Seven_Zip*` APIs extract those supported native 7z layouts plus native PPMd empty/repeated-symbol/root-symbol/periodic-prefix, stock-7z multi-block streams with LZMA encoded headers, stock-7z no-stream empty-file entries, stock-7z BCJ+PPMd filter chains, and BCJ2 graphs with Copy, PPMd, or supported main pre-coders, `Seven_Zip_PPMd`, `Seven_Zip_PPMd_File`, and `Seven_Zip_PPMd_Files` emit native PPMd 7z archives for this crate's extractor without calling local `7z`, while `Seven_Zip_External_File` and `Extract_Seven_Zip_External_File` are compatibility placeholders that fail closed without invoking local `7z`, `ZIP`/`ZIP_File`/`ZIP_Files` emit ZIP archives, `Inflate` is zlib-wrapper-only, `Inflate_With_Header` performs explicit wrapper selection, and `Inflate_Auto` is the convenience wrapper-discriminating inflate API. `Auto` remains deterministic and block-local; the library still has no general-purpose 7z codec stack or zlib-compatible compression-ratio promise.

## Streaming gzip metadata

The metadata overload of `Deflate_Init` must be called before any compression
output is requested. For `Header => GZip`, the compressor emits the base gzip
header, optional `FNAME`, optional `FCOMMENT`, and optional `FHCRC` before any
Deflate payload bytes. Header metadata emission is resumable and works with
small output buffers, including one-byte buffers.

For `Header => Zlib_Header`, `Header => Default`, and `Header => Raw_Deflate`,
non-default metadata is rejected with `Status_Error` rather than silently
ignored.


## Streaming compression flush modes

`Sync_Flush` forces currently buffered compression input into the Deflate stream without ending it. It finishes the current block as non-final and emits an empty non-final stored block on a byte boundary. `Full_Flush` currently has the same byte-level behavior because the compressor has no cross-block match history; the distinction is preserved in the API and tests. Neither mode emits zlib/gzip trailers, and `Compress_Stream_End` remains `False` until `Finish`. Flush output may require repeated drain calls with small output buffers. `Finish` after a partially drained flush completes the pending flush work and then finalizes the stream. After stream end, `Sync_Flush` and `Full_Flush` are lifecycle misuse and raise `Status_Error`. Streaming inflate treats `Sync_Flush` and `Full_Flush` as `No_Flush`; Deflate flush markers are ordinary stored blocks.

## Level-based streaming initialization

Streaming compression can now be initialized with a broad compression level:

```ada
Deflate_Init (Filter, Header => Zlib_Header, Level => Default_Level);
Deflate_Init (Filter, Header => GZip,        Level => 6);
Deflate_Init (Filter, Header => Raw_Deflate, Level => 0);
```

The mapping is the same as one-shot compression: level `0` uses stored blocks,
level `1` uses fixed-Huffman blocks, levels `2 .. 3` use greedy `Auto`, levels
`4 .. 7` use conservative lazy `Auto`, and levels `8 .. 9` use bounded-optimal
`Auto`. This level choice affects only compression policy. It does not change
zlib, gzip, or raw Deflate wrapper boundaries, flush semantics, lifecycle
behavior, or trailer emission.

## Auto block scoring and flushes

Streaming `Auto` is block-local and deterministic. When a block is finalized, the compressor scores Stored, Fixed-Huffman, and, for levels 2 through 9, Dynamic-Huffman candidates before emitting any bytes for that block. Dynamic header cost is included in the score; it is not assumed to be free. Equal scores use the tie-breaker Stored, then Fixed, then Dynamic.

`Sync_Flush` and `Full_Flush` first finalize the current buffered block with the chooser as a non-final block, then emit the required empty stored flush marker. `Finish` finalizes the current block with `BFINAL = 1` and then emits the active wrapper trailer, if any. Wrapper headers and trailers are never included in block-choice scoring.

## Streaming compression dictionaries

A preset dictionary must be supplied after `Deflate_Init` and before any input
is compressed or header byte is emitted:

```ada
Deflate_Init (Filter, Header => Zlib_Header, Mode => Auto);
Deflate_Set_Dictionary (Filter, Dictionary);
Compress (...);
```

The API is rejected with `Status_Error` for gzip and raw Deflate wrappers.

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

## Lazy matching and flush boundaries

Level-based streaming compression uses the same internal matching policy as the
one-shot APIs. Levels 2 and 3 use greedy matching. Levels 4 through 7, including
the default level 6, use conservative lazy matching for dynamic-Huffman and Auto
candidates. Levels 8 and 9 use bounded block-local
optimal parsing. Level 0 remains stored and level 1 remains fixed-Huffman.

Lazy matching is bounded to the current pending compression block. It does not
look past `Sync_Flush`, `Full_Flush`, or `Finish`; those requests finalize the
current block using only bytes already accepted into that block. This preserves
chunking determinism and avoids whole-stream buffering. Stored mode is not
affected by the matcher.
