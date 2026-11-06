#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOON="${MOON:-moon}"

cd "$ROOT"
"$MOON" info
"$MOON" run cmd/main -- check \
  api-baseline/v0.1.0 \
  pkg.generated.mbti \
  --quiet
