#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOON="${MOON:-moon}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cd "$ROOT"
"$MOON" build cmd/main --deny-warn
"$MOON" run cmd/main -- --help > "$TMP_DIR/help.txt"
grep -q "MoonCompat 0.1.0" "$TMP_DIR/help.txt"

set +e
"$MOON" run cmd/main -- check fixtures/demo/base fixtures/demo/head \
  > "$TMP_DIR/breaking.txt"
BREAKING_EXIT=$?
set -e
test "$BREAKING_EXIT" -eq 1
grep -q "3 breaking, 1 compatible, 2 unchanged" "$TMP_DIR/breaking.txt"
grep -q "Recommended bump: major" "$TMP_DIR/breaking.txt"

"$MOON" run cmd/main -- check fixtures/compatible/base fixtures/compatible/head \
  > "$TMP_DIR/compatible.txt"
grep -q "0 breaking, 1 compatible, 1 unchanged" "$TMP_DIR/compatible.txt"
grep -q "Recommended bump: minor" "$TMP_DIR/compatible.txt"

"$MOON" run cmd/main -- check fixtures/unchanged/base fixtures/unchanged/head \
  > "$TMP_DIR/unchanged.txt"
grep -q "No public API changes detected" "$TMP_DIR/unchanged.txt"
grep -q "Recommended bump: patch" "$TMP_DIR/unchanged.txt"

"$MOON" run cmd/main -- check fixtures/demo/base fixtures/demo/head \
  --format json --output "$TMP_DIR/report.json" --fail-on never
grep -q '"result": "breaking"' "$TMP_DIR/report.json"
grep -q '"recommended_bump": "major"' "$TMP_DIR/report.json"
grep -q '"kind": "declaration_changed"' "$TMP_DIR/report.json"

"$MOON" run cmd/main -- snapshot fixtures/demo/base/pkg.generated.mbti \
  --output "$TMP_DIR/snapshot.json"
grep -q '"package": "github\\/404-32\\/weather-client"' "$TMP_DIR/snapshot.json"
grep -q '"canonical": "pub fn parse(String) -> Forecast"' "$TMP_DIR/snapshot.json"

set +e
"$MOON" run cmd/main -- check fixtures/malformed fixtures/compatible/head \
  > "$TMP_DIR/malformed.out" 2> "$TMP_DIR/malformed.err"
MALFORMED_EXIT=$?
set -e
test "$MALFORMED_EXIT" -eq 2
grep -q "unsupported .mbti public syntax" "$TMP_DIR/malformed.err"

echo "CLI integration tests passed."
