# Quickstart

This quickstart shows the shortest supported path for adding `Zlib` to an Ada
project and using the public root package. Public consumers should use only:

```ada
with Zlib;
```

Child packages are implementation details.

## 1. Add the crate

For an Alire project, add the dependency in the normal Alire way:

```sh
alr with zlib
```

Then build your project:

```sh
alr build
```

When working directly from this repository, build the library, examples, and
release checks with:

```sh
alr build
alr exec -- gprbuild -P zlib.gpr
alr exec -- gprbuild -P examples/examples.gpr
alr exec -- gprbuild -P tools/tools.gpr
tools/bin/check_all
```

## 2. Compress and inflate a zlib stream

`Deflate` produces zlib-wrapped output. `Inflate` accepts zlib-wrapped input
only. Both APIs are binary-safe and report deterministic status codes.

```ada
with Ada.Text_IO;
with Zlib;

procedure Quickstart_Zlib is
   Status : Zlib.Status_Code;

   Plain : constant Zlib.Byte_Array :=
     [16#68#, 16#65#, 16#6C#, 16#6C#, 16#6F#];

   Compressed : constant Zlib.Byte_Array :=
     Zlib.Deflate (Plain, Status => Status);

   Back : constant Zlib.Byte_Array :=
     Zlib.Inflate (Compressed, Status);
begin
   if Status /= Zlib.Ok or else Back /= Plain then
      Ada.Text_IO.Put_Line ("zlib roundtrip failed: " & Zlib.Status_Image (Status));
   else
      Ada.Text_IO.Put_Line ("zlib roundtrip ok");
   end if;
end Quickstart_Zlib;
```

Use `Compression_Mode` when you need explicit output policy:

```ada
Dynamic_Compressed : constant Zlib.Byte_Array :=
  Zlib.Deflate (Plain, Mode => Zlib.Dynamic, Status => Status);
```

Use `Compression_Level` when you want broad effort policy instead of exact block
strategy:

```ada
Level_Compressed : constant Zlib.Byte_Array :=
  Zlib.Deflate (Plain, Level => Zlib.Default_Level, Status => Status);
```

## 3. Work with gzip

`GZip` produces gzip-wrapped output. Decode gzip input through
`Inflate_With_Header` with `Header => Zlib.GZip`.

```ada
with Ada.Text_IO;
with Zlib;

procedure Quickstart_Gzip is
   Status : Zlib.Status_Code;

   Plain : constant Zlib.Byte_Array :=
     [16#67#, 16#7A#, 16#69#, 16#70#];

   Compressed : constant Zlib.Byte_Array :=
     Zlib.GZip (Plain, Mode => Zlib.Auto, Status => Status);

   Back : constant Zlib.Byte_Array :=
     Zlib.Inflate_With_Header
       (Compressed,
        Header => Zlib.GZip,
        Status => Status);
begin
   if Status /= Zlib.Ok or else Back /= Plain then
      Ada.Text_IO.Put_Line ("gzip roundtrip failed: " & Zlib.Status_Image (Status));
   else
      Ada.Text_IO.Put_Line ("gzip roundtrip ok");
   end if;
end Quickstart_Gzip;
```

Optional gzip metadata is explicit. Default gzip output remains deterministic
and minimal.

```ada
Metadata : Zlib.GZip_Metadata := Zlib.No_GZip_Metadata;

Zlib.Set_Name (Metadata, "payload.bin");
Zlib.Set_Comment (Metadata, "created by quickstart");

declare
   Gzip_With_Name : constant Zlib.Byte_Array :=
     Zlib.GZip
       (Plain,
        Mode     => Zlib.Auto,
        Metadata => Metadata,
        Status   => Status);
begin
   null;
end;
```

## 4. Work with raw Deflate

Raw Deflate output contains Deflate blocks only: no zlib header, no Adler-32
footer, no gzip header, no CRC32 trailer, and no ISIZE trailer. Use it only when
another protocol or container supplies framing and integrity checks.

```ada
with Ada.Text_IO;
with Zlib;

procedure Quickstart_Raw is
   Status : Zlib.Status_Code;

   Plain : constant Zlib.Byte_Array :=
     [16#72#, 16#61#, 16#77#];

   Compressed : constant Zlib.Byte_Array :=
     Zlib.Deflate_Raw (Plain, Mode => Zlib.Fixed, Status => Status);

   Back : constant Zlib.Byte_Array :=
     Zlib.Inflate_Raw (Compressed, Status);
begin
   if Status /= Zlib.Ok or else Back /= Plain then
      Ada.Text_IO.Put_Line ("raw Deflate roundtrip failed: " & Zlib.Status_Image (Status));
   else
      Ada.Text_IO.Put_Line ("raw Deflate roundtrip ok");
   end if;
end Quickstart_Raw;
```

## 5. Use file helpers

The file helpers are convenience wrappers around the same public behavior.
Status is `Input_File_Error` or `Output_File_Error` for file-level failures.

```ada
with Ada.Command_Line;
with Ada.Text_IO;
with Zlib;

procedure Quickstart_Files is
   Status : Zlib.Status_Code;
begin
   Zlib.Deflate_File
     (Input_Path  => "input.bin",
      Output_Path => "input.bin.z",
      Mode        => Zlib.Auto,
      Status      => Status);

   if Status /= Zlib.Ok then
      Ada.Text_IO.Put_Line ("compress failed: " & Zlib.Status_Image (Status));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   Zlib.Inflate_File
     (Input_Path  => "input.bin.z",
      Output_Path => "input.roundtrip.bin",
      Status      => Status);

   if Status /= Zlib.Ok then
      Ada.Text_IO.Put_Line ("inflate failed: " & Zlib.Status_Image (Status));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Quickstart_Files;
```

## 6. Use streaming when buffers are bounded

The streaming APIs are intended for bounded-memory callers and small input or
output buffers. Streaming operations use exceptions:

- `Zlib_Error` for malformed, truncated, unsupported, or checksum-invalid data;
- `Status_Error` for lifecycle misuse.

Use:

- `docs/STREAMING.md` for streaming inflate;
- `docs/STREAMING_COMPRESSION.md` for streaming compression;
- `examples/streaming_roundtrip_zlib.adb` for a complete zlib streaming example;
- `examples/streaming_roundtrip_gzip.adb` for a complete gzip streaming example;
- `examples/streaming_deflate_raw.adb` for raw streaming output.

## 7. Validate a checkout

For repository development, the normal validation path is:

```sh
tools/bin/check_all
```

That script builds the library, tests, examples, and tools where GNAT/GPRBuild
are available, runs the AUnit suite, runs command-line smoke checks, and runs
short deterministic fuzz smoke passes.

For fuzzing details, seeds, target policy, and corpus rules, see
`docs/FUZZING.md`.

## For AI coding assistants

Automated agents should read `llms.txt`, `AGENTS.md`, `docs/AI_GUIDE.md`, and
`docs/API_CHEATSHEET.md` and `docs/CONSTRAINTS.md` before changing code or generating downstream examples.
Consumer-facing code should import only `with Zlib;`; child packages are
implementation details.

## Wrapper rules to remember

- `Inflate` is zlib-wrapper-only.
- `Inflate_With_Header` is the explicit wrapper-selection API.
- `Inflate_Auto` is the explicit lightweight wrapper-discriminating convenience API.
- `Default` means exactly `Zlib_Header`; strict inflate APIs do not auto-detect.
- `Deflate`, `Deflate_Stored`, `Deflate_Fixed`, and `Deflate_Dynamic` emit zlib streams.
- `GZip` emits gzip streams.
- `Deflate_Raw` emits raw Deflate payload bytes only.
- Multi-member gzip input is explicit through `GZip_Member_Mode`; multi-member
  gzip output is explicit through `GZip_Members` and `GZip_File_Members`.
- ZIP output is explicit through `ZIP`, `ZIP_File`, and `ZIP_Files`; `ZIP_Files`
  supports multi-entry archives and explicit ZIP64 metadata.
