# Validation

Validation was last run on 2026-11-06 with MoonBit:

```text
moon 0.1.20261028
moonc v0.10.18+6c83a7f62
```

## Library tests

```bash
moon test --deny-warn
moon test --target wasm-gc --deny-warn
moon test --target js --deny-warn
```

Observed result: 32 tests passed. The test suite covers parser failures, all declaration kinds used by the project, signature removal/change/addition, field and enum changes, trait implementations, derive normalization, `Int` aliases, package renames, multi-package comparisons, deterministic reports, and JSON fields.

Native compilation is exercised in GitHub Actions on Ubuntu. The local Windows environment used for development did not have MSVC Build Tools installed, so local native compilation was not claimed as verified.

## CLI fixtures

```bash
moon run cmd/main -- check fixtures/demo/base fixtures/demo/head
moon run cmd/main -- check fixtures/compatible/base fixtures/compatible/head
moon run cmd/main -- check fixtures/unchanged/base fixtures/unchanged/head
```

Observed:

| Fixture | Breaking | Compatible | Unchanged | Exit |
|---|---:|---:|---:|---:|
| `demo` | 3 | 1 | 2 | 1 |
| `compatible` | 0 | 1 | 1 | 0 |
| `unchanged` | 0 | 0 | 1 | 0 |

## Real package smoke tests

The regression script shallow-clones released MoonBit packages and compares their checked-in `.mbti` files.

### `moonbitlang/x`

Comparison: `v0.5.6` → `v0.5.7` across the full repository.

Observed: `0 breaking`, `0 compatible`, `854 unchanged`.

This also validated that moving `Eq` from a `derive(...)` clause to an explicit `pub impl` is normalized as unchanged. An earlier parser revision reported that representation change as breaking; the regression is now covered by a unit test.

### `moonbitlang/async`

Comparison: `v0.21.3` → `v0.22.7`, package `moonbitlang/async/fs`.

Observed: `3 breaking`, `11 compatible`, `60 unchanged`.

The breaking changes were inspected in the generated report:

- `mkdir` gained the `allow_exist?` parameter;
- `remove` gained `nocancel`;
- `rmdir` gained `nocancel`.

The added methods were `Directory::open`, `Directory::remove`, and the async `File` read/write methods.

## Reproduce

```bash
bash scripts/test-cli.sh
bash scripts/check-real-packages.sh
```

The scripts fail if expected exit statuses, report fields, or summaries are absent.
