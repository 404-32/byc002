# Roadmap

Only tested, source-compatible-tooling improvements are listed here.

## v0.2

- GitHub Action package that generates both worktrees and publishes SARIF;
- `--base-ref` and `--head-ref` wrappers around `git worktree`;
- machine-readable reasons for every compatibility rule;
- fixture generation from real MoonBit packages.

## Later

- optional automatic `moon.mod` version recommendation;
- cross-package rename hints;
- IDE annotation adapter;
- protocol and serialized-format compatibility as a separate engine.

ABI and behavioral compatibility are intentionally not promised by the v0.1 engine.
