# Gzip output

Zlib can emit deterministic gzip-wrapped Deflate output through the one-shot
`GZip` / `GZip_File` APIs and the streaming compression API with
`Header => Zlib.GZip`.

## Gzip member shape

The library emits exactly one gzip member.

The fixed 10-byte header is:

| Byte | Value | Meaning |
| --- | --- | --- |
| 0 | `16#1F#` | ID1 |
| 1 | `16#8B#` | ID2 |
| 2 | `16#08#` | CM = Deflate |
| 3 | `16#00#` | FLG = no optional fields |
| 4..7 | `16#00# 16#00# 16#00# 16#00#` | MTIME = 0 |
| 8 | `16#00#` | XFL = 0 |
| 9 | `16#FF#` | OS = unknown |

No optional header fields are emitted:

- no FEXTRA
- no FNAME
- no FCOMMENT
- no FHCRC

These bytes remain unchanged unless the caller explicitly supplies
`GZip_Metadata`.

The trailer is eight bytes:

1. CRC32 of the uncompressed input, little-endian.
2. ISIZE, the uncompressed size modulo 2^32, little-endian.

## Public API behavior

`GZip` and `GZip_File` produce gzip-wrapped output.

`Deflate_Stored`, `Deflate_Fixed`, `Deflate_Dynamic`, `Deflate`, and
`Deflate_File` produce zlib-wrapped output, not gzip output.

Streaming compression with `Header => Zlib.GZip` produces gzip-wrapped output.
Streaming compression with `Header => Zlib.Default` or `Header => Zlib.Zlib_Header`
produces zlib-wrapped output.

Gzip output inflates with:

```ada
Zlib.Inflate_With_Header (Input, Zlib.GZip, Status)
```

or with streaming inflate initialized as:

```ada
Zlib.Inflate_Init (Filter, Header => Zlib.GZip);
```

Gzip output is rejected by `Zlib_Header` mode. There is no wrapper
auto-detection.

## Determinism

For the same input and compression mode, the default gzip output is deterministic.
The default header contains no timestamps, names, comments, extra fields, or
host-specific metadata. Without explicit `GZip_Metadata`, `MTIME` is zero,
`XFL` is zero, and `OS` is 255.

## Non-goals

The gzip writer does not emit multiple members or ZIP containers. Compression
levels are wrapper-neutral and do not change gzip header semantics. Extra data,
file names, comments, MTIME, XFL, OS, and header CRCs are emitted only when
requested through `GZip_Metadata`.

## Optional gzip metadata output

The default gzip output remains byte-for-byte deterministic and minimal:

```text
1F 8B 08 00 00 00 00 00 00 FF
```

Callers that need metadata use `GZip_Metadata` and the metadata overloads of
`GZip`, `GZip_File`, or streaming `Deflate_Init`. Empty metadata is exactly the
same as the legacy gzip API. Metadata is accepted only for `Header => GZip`; a
non-default metadata value with zlib or raw Deflate compression is rejected as
API misuse.

Supported optional fields are:

- `MTIME`, emitted little-endian when set; otherwise zero.
- `XFL`, emitted when set; otherwise zero.
- `OS`, emitted when set; otherwise 255.
- `FEXTRA`, emitted as little-endian XLEN followed by the exact caller-supplied
  bytes. Length must be at most 65,535 bytes.
- `FNAME`, emitted as caller-supplied bytes followed by NUL.
- `FCOMMENT`, emitted as caller-supplied bytes followed by NUL.
- `FHCRC`, emitted as the low sixteen bits of the CRC32 over the gzip header up
  to, but not including, the FHCRC bytes.

`FEXTRA` is binary-safe and may contain NUL/high-byte values. `FNAME` and
`FCOMMENT` must not contain embedded NUL bytes. Invalid metadata is reported
deterministically and does not produce partial one-shot output. The gzip trailer
remains unchanged: CRC32 and ISIZE are computed over the uncompressed payload
only, not over metadata.

## Metadata release coverage

The metadata contract is covered by tests for default-output preservation,
MTIME/OS byte layout, XFL preservation, FEXTRA output and inflate, FNAME-only
output, FCOMMENT-only output, empty explicit strings, FEXTRA+FNAME+FCOMMENT+FHCRC
roundtrip, `Auto` mode with metadata, invalid NUL rejection, oversized FEXTRA
rejection, `GZip_File` metadata output, trailer CRC32/ISIZE independence, and
streaming emission through one-byte output buffers. The command-line smoke test
also exercises `gzip_metadata_file` for every compression mode.
