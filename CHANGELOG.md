# Changelog

All notable changes are documented here. The project follows Semantic Versioning.

## [0.1.0] - 2026-11-06

### Added

- MoonBit `.mbti` parser and normalized declaration IR.
- Single-package and multi-package compatibility comparison.
- Breaking/compatible classification and SemVer recommendation.
- Text and deterministic JSON reports.
- CLI directory scanning with dependency/build-directory exclusions.
- Snapshot command.
- GitHub Actions CI and release workflows.
- Unit and CLI fixture tests.
- Real-package regression scripts for `moonbitlang/x` and `moonbitlang/async`.
- Fail-closed handling for unknown public `.mbti` syntax.

### Known limitations

- Source-level interface checks only; no ABI or behavioral verification.
- Signature changes are conservatively classified as breaking.
