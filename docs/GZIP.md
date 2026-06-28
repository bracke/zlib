# GZip inflate and output

The public API supports explicit single-member gzip inflate through both
streaming and one-shot wrapper selection:

```ada
Zlib.Inflate_Init (Filter, Header => Zlib.GZip);
Decoded := Zlib.Inflate_With_Header (Input, Zlib.GZip, Status);
```

`Header => GZip` parses a single gzip member, reuses the same Deflate engine as
zlib-wrapped streams, and validates the gzip trailer before reporting success.

## Header prefix helper

`Looks_Like_GZip_Header` checks only the gzip magic bytes, `CM = 8`, and reserved `FLG` bits. It is intended as a lightweight discriminator for callers that still choose an explicit wrapper mode themselves. It does not validate optional metadata fields, Deflate payload bytes, CRC32, ISIZE, trailing data, or member completeness.

## Supported gzip structure

The implementation accepts the standard gzip wrapper around a Deflate payload:

```text
gzip header
raw Deflate payload
gzip trailer
```

The parser validates:

* `ID1 = 0x1F`
* `ID2 = 0x8B`
* `CM = 8`
* reserved `FLG` bits are clear
* trailer CRC32 equals the CRC32 of the decoded payload
* trailer ISIZE equals the decoded payload size modulo 2^32

The following gzip flags are accepted:

* `FTEXT` — accepted; no special behavior
* `FHCRC` — header CRC16 is validated against the low 16 bits of the running
  gzip header CRC32
* `FEXTRA` — extra field is skipped incrementally
* `FNAME` — original file name is skipped incrementally through the terminating
  NUL byte
* `FCOMMENT` — comment is skipped incrementally through the terminating NUL byte

Malformed headers, unsupported compression methods, reserved flags, bad header
CRC, bad payload CRC32, bad ISIZE, and truncated streams raise `Zlib_Error` from
`Translate`/`Flush` when detected. `Finish` requires the complete header,
Deflate payload, CRC32 trailer, and ISIZE trailer to be present.

## Stream end policy

For gzip streams, `Stream_End (Filter)` becomes `True` only after all of the
following have happened:

1. the Deflate final block has ended;
2. the four-byte gzip CRC32 trailer has been read and validated;
3. the four-byte gzip ISIZE trailer has been read and validated.

It does not become true immediately at Deflate end-of-block.

## Member policy

Gzip inflate is strict single-member by default. Concatenated gzip members are
accepted only through the explicit multi-member APIs; each member header,
optional metadata area, Deflate payload, CRC32 trailer, and ISIZE trailer is
validated independently.

## Streaming contract

Streaming gzip inflate supports exactly one gzip member by default. Optional gzip header
fields are parsed according to the gzip wrapper policy. In default single-member mode,
`Stream_End` becomes `True` only after the gzip trailer is fully read and both CRC32 and
ISIZE validate. Extra bytes after the first member are left unconsumed for the caller.
In explicit multi-member mode, every member is validated before the logical stream ends.

Bad gzip header fields, reserved flags, bad FHCRC, bad data CRC, bad ISIZE,
and truncation under `Finish` raise `Zlib_Error` and place the filter in Failed
state until `Close`. This is sufficient for an HttpClient decompression adapter
to support `Content-Encoding: gzip`.

## Gzip output

The crate also emits deterministic minimal gzip streams through `GZip`,
`GZip_File`, and streaming compression with `Deflate_Init (Header => GZip, ...)`.
Generated gzip members use the fixed ten-byte header
`1F 8B 08 00 00 00 00 00 00 FF`, emit a raw Deflate payload, and finish with
little-endian CRC32 and ISIZE trailer fields. Stored, fixed-Huffman,
dynamic-Huffman, and `Auto` modes are supported. The existing `Deflate_*` APIs
remain zlib-wrapper-only.

Default gzip output does not include FEXTRA, FNAME, FCOMMENT, FHCRC, or any
other metadata fields. Optional FEXTRA, FNAME, FCOMMENT, MTIME, XFL, OS, and
FHCRC output is available only through the explicit metadata APIs. Concatenated
multi-member gzip output is available through `GZip_Members` and
`GZip_File_Members`.

## One-shot gzip inflate

Use `Inflate_With_Header (Input, Header => GZip, Status => Status)` for a
complete gzip member. The one-shot path uses the same wrapper validation as the
streaming path: gzip header parsing is explicit, CRC32 and ISIZE are validated,
and checksum or size failures map to `Invalid_Checksum`. Plain `Inflate` remains
zlib-wrapper-only and intentionally rejects gzip input.

Optional gzip metadata output is explicit. Multi-member gzip input is accepted only through the explicit
`GZip_Member_Mode => Multi_Member` APIs. Multi-member gzip output is explicit
through `GZip_Members` and `GZip_File_Members`; strict inflate APIs still do not
auto-detect wrappers, while `Inflate_Auto` provides lightweight one-shot
wrapper discrimination.
Gzip compression output is available only through the explicit gzip output APIs or streaming `Header => GZip`.

## Interoperability contract

The wrapper mode is strict: gzip input is accepted only by `Header => GZip`,
and zlib/raw inputs are rejected in gzip mode. The conformance tests include
fixed-Huffman and dynamic-Huffman gzip fixtures,
binary body fixtures, bad ID bytes, unsupported compression method, reserved
flag bits, truncated fixed and optional headers, bad CRC32, bad ISIZE, and
missing trailer cases.

## Metadata output

Gzip output defaults to the existing deterministic minimal header. Optional
metadata is available through `GZip_Metadata`; fields are emitted only when the
caller sets them. `FEXTRA` is emitted with a little-endian 16-bit XLEN followed
by the caller supplied bytes exactly; arbitrary byte values, including NUL, are
valid in FEXTRA and lengths above 65,535 are rejected deterministically. `FNAME`
and `FCOMMENT` are NUL-terminated and reject embedded NUL bytes. `XFL` and `OS`
can be set explicitly; defaults remain XFL = 0 and OS = 255. `FHCRC`, when
enabled, is the low 16 bits of the CRC32 over the gzip header bytes before the
FHCRC field, including FEXTRA/FNAME/FCOMMENT when present.

## Multi-member inflate policy

Gzip inflate is single-member strict by default. The existing
`Inflate_With_Header (Input, GZip, Status)` overload accepts exactly one gzip
member and rejects any trailing bytes after that member, including a second
valid gzip member. This avoids silently concatenating unrelated compressed
bodies.

Concatenated gzip files are supported only when explicitly requested with
`GZip_Mode => Multi_Member`. In multi-member mode, every member is parsed and
validated independently: base header, optional metadata fields, optional FHCRC,
Deflate payload, CRC32 trailer, and ISIZE trailer. The returned payload is the
byte concatenation of all decoded members.

Malformed second or later members fail with the same deterministic status codes
as malformed first members. Non-gzip trailing bytes after a valid member are
reported as `Invalid_Header`.

## CRC32 utility

Consumers that need the same checksum used by gzip trailers can call `Zlib.CRC32` directly from the root package. It computes the standard gzip CRC-32 with polynomial `0xEDB88320` over the supplied bytes. The same byte-oriented rule applies to FHCRC-related data: bytes are included exactly, with no string conversion or character encoding assumption. `Zlib.CRC32` is only a checksum helper and does not validate a gzip member by itself.
