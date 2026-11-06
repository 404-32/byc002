#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOON="${MOON:-moon}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cd "$ROOT"
"$MOON" info
set +e
"$MOON" run cmd/main -- check \
  api-baseline/v0.1.0 \
  pkg.generated.mbti \
  --format json \
  --output "$TMP_DIR/self-api.json"
STATUS=$?
set -e
cat "$TMP_DIR/self-api.json"
test "$STATUS" -eq 0
