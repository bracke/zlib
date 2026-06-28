# Raw Deflate

Raw Deflate is the Deflate bitstream by itself. It contains Deflate blocks and
nothing else. In this crate, raw Deflate is selected explicitly with
`Header => Raw_Deflate` for inflate, `Inflate_Raw`/`Inflate_Raw_File`/
`Inflate_Raw_File_Streaming` as convenience raw-inflate entry points, and
`Deflate_Raw`, `Deflate_Raw_File`, or `Deflate_Init (Header => Raw_Deflate, ...)`
for compression.

Use raw Deflate only when an external protocol or container already supplies
framing and checksums. Raw Deflate has no zlib header, no Adler-32 trailer, no
gzip header, no CRC32 trailer, and no ISIZE trailer.

## Wrapper comparison

| Format | Public compression API | Public inflate header | Framing/checksum |
| --- | --- | --- | --- |
| zlib-wrapped Deflate | `Deflate`, `Deflate_Stored`, `Deflate_Fixed`, `Deflate_Dynamic` | `Zlib_Header` or `Default` | zlib header plus Adler-32 |
| gzip-wrapped Deflate | `GZip` | `GZip` | gzip member header plus CRC32/ISIZE |
| raw Deflate | `Deflate_Raw` | `Raw_Deflate` | none |

Raw Deflate differs from the zlib wrapper by omitting the CMF/FLG header and the
Adler-32 trailer. It differs from the gzip wrapper by omitting the gzip member
header, optional metadata, CRC32 trailer, and ISIZE trailer.

Wrapper handling is strict. Raw Deflate output is accepted only by raw Deflate
inflate APIs. It is not a zlib stream and it is not a gzip member.

## One-shot raw compression

```ada
with Zlib;

procedure Example is
   Status : Zlib.Status_Code;
   Plain  : constant Zlib.Byte_Array := [1 => 16#68#, 2 => 16#69#];
   Raw    : constant Zlib.Byte_Array :=
     Zlib.Deflate_Raw (Plain, Zlib.Auto, Status);
begin
   if Status /= Zlib.Ok then
      raise Program_Error with Zlib.Status_Image (Status);
   end if;
end Example;
```

`Deflate_Raw` supports `Stored`, `Fixed`, `Dynamic`, and `Auto`.

## Streaming raw compression

```ada
Zlib.Deflate_Init (Filter, Header => Zlib.Raw_Deflate, Mode => Zlib.Auto);
Zlib.Compress (Filter, In_Data, In_Last, Out_Data, Out_Last, Zlib.No_Flush);
while not Zlib.Compress_Stream_End (Filter) loop
   Zlib.Compress_Flush (Filter, Out_Data, Out_Last, Zlib.Finish);
end loop;
Zlib.Compress_Close (Filter);
```

The streaming compressor is safe with small caller-owned output buffers. The
caller must collect every byte reported through `Out_Last` before calling again.

For container writers that need exact raw payload metadata,
`Deflate_Raw_File_Size` runs the selected raw compression mode without writing
output, and `Deflate_Raw_File_To_Stream` writes `Stored`, `Fixed`, `Dynamic`,
or `Auto` raw Deflate into an open `Ada.Streams.Stream_IO.File_Type`.
`Stored_Raw_Deflate_Size` and `Deflate_Raw_Stored_File_To_Stream` remain
compatibility helpers for stored-block-only container writers. This keeps
container headers, such as ZIP local file headers, outside zlib while sharing
the raw Deflate emission logic.

## One-shot raw inflate

```ada
Decoded := Zlib.Inflate_Raw (Raw, Status);
--  Equivalent general explicit-wrapper form:
Decoded := Zlib.Inflate_With_Header (Raw, Zlib.Raw_Deflate, Status);
```

`Inflate_Raw` is a convenience wrapper for complete raw Deflate payloads. It
does not auto-detect wrappers: zlib-wrapped and gzip-wrapped inputs fail with a
non-`Ok` status. `Inflate` remains zlib-wrapper-only, and
`Inflate_With_Header` remains the general explicit wrapper API. The raw inflate
path validates Deflate structure only. It cannot validate an outer checksum
because raw Deflate has none.

For files, `Inflate_Raw_File` is the whole-file convenience helper and
`Inflate_Raw_File_Streaming` uses bounded-memory streaming file inflate with
`Header => Raw_Deflate`.

## Streaming raw inflate

```ada
Zlib.Inflate_Init (Filter, Header => Zlib.Raw_Deflate);
Zlib.Translate (Filter, In_Data, In_Last, Out_Data, Out_Last, Zlib.No_Flush);
Zlib.Flush (Filter, Out_Data, Out_Last, Zlib.Finish);
Zlib.Close (Filter);
```

Use `Finish` when the external framing layer says the raw Deflate payload is
complete. `Stream_End` becomes true only after the final Deflate block has been
processed and pending output has been drained.

## Raw roundtrip

```ada
Raw     := Zlib.Deflate_Raw (Plain, Zlib.Dynamic, Status);
Decoded := Zlib.Inflate_Raw (Raw, Status);
```

For complete runnable versions, see:

- `examples/raw_roundtrip.adb`
- `examples/streaming_deflate_raw.adb`
- `examples/deflate_raw_file.adb`
- `examples/deflate_raw_file_to_stream.adb`
- `examples/inflate_raw_file.adb`
- `examples/deflate_raw_file_streaming.adb`
- `examples/inflate_raw_file_streaming.adb`
- `examples/raw_vs_zlib_vs_gzip.adb`
- `tools/raw_roundtrip.adb`
- `tools/raw_deflate_file.adb`
- `tools/raw_vs_zlib_vs_gzip.adb`


## Raw Deflate release hardening

Raw Deflate compression is release-hardened by `zlib_raw_release_tests`,
`zlib_raw_cross_wrapper_conformance_tests`, the raw examples, and the raw tools.
Raw Deflate inflate convenience APIs are covered by `zlib_inflate_raw_api_tests`.
The contract remains unchanged: `Deflate_*` APIs emit zlib-wrapped streams, `GZip*`
APIs emit gzip-wrapped streams, `Deflate_Raw*` APIs emit raw Deflate blocks only,
`Inflate_Raw*` APIs consume raw Deflate payloads only, native `Seven_Zip_*` APIs
emit/extract supported Copy and Deflate 7z layouts, `Seven_Zip_External_File`
and `Extract_Seven_Zip_External_File` are compatibility placeholders that fail
closed without invoking local `7z`, `ZIP`/`ZIP_File`/`ZIP_Files` emit ZIP
archives, `Inflate` is
zlib-wrapper-only, `Inflate_With_Header` performs explicit wrapper selection,
and `Inflate_Auto` is the convenience wrapper-discriminating inflate API. `Auto`
remains deterministic and block-local; the library still has no in-process full
LZMA/LZMA2/stock-compatible PPMd codec stack, whole-stream optimal parser, or
zlib-compatible compression-ratio promise.
