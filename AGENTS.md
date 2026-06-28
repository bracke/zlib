# Agent instructions

Development version 0.1.0-dev.

This repository is a pure Ada zlib/gzip/raw Deflate crate. These instructions
are intended for AI coding agents and other automated maintainers.

## Public contract

- Consumer code must use only `with Zlib;`.
- `src/zlib.ads` is the public API source of truth.
- Child packages under `src/zlib-*.ads` are internal implementation details.
- `Zlib.Fuzzing` is for repository fuzz tools/tests, not general consumers.

## Build and validation

Preferred full validation:

```sh
alr build
alr exec -- gprbuild -P zlib.gpr
cd tests && alr exec -- gprbuild -P tests.gpr
cd tests && ./bin/tests
alr exec -- gprbuild -P examples/examples.gpr
alr exec -- gprbuild -P tools/tools.gpr
./tools/bin/smoke_test
tools/bin/check_all
```

When GNAT/GPRBuild are unavailable, state that clearly and run static checks
that the environment supports.

## Coding rules

- Ada 2022 style; keep lines at or below 120 characters.
- Do not use Ada reserved words as identifiers, regardless of case.
- Do not add `goto`.
- Preserve deterministic status codes for one-shot APIs.
- Preserve exception-based lifecycle/data errors for streaming APIs.
- Do not add wrapper auto-detection unless a future explicit public feature requires it.
- Do not add ZIP container support to this crate.
- Do not introduce dependencies on system zlib, Python-generated fixtures, Git,
  `version`, or `HttpClient`.

## Documentation rules

Any public behavior change must update:

- `src/zlib.ads` GNATdoc comments;
- `docs/API.md`;
- `docs/API_CHEATSHEET.md`;
- relevant wrapper docs in `docs/`;
- `docs/QUICKSTART.md` when first-use behavior changes;
- `examples/README.md` and any affected examples;
- `README.md` lists;
- `llms.txt` when high-level entry points or validation commands change.

## Example rules

Examples must:

- compile against the public root package only;
- check `Status_Code` results;
- set a non-zero exit status on failure;
- avoid importing internal child packages;
- be listed in `examples/examples.gpr`, `examples/README.md`, and `README.md`.
