#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOON="${MOON:-moon}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

git clone --quiet --depth 1 --branch v0.5.6 \
  https://github.com/moonbitlang/x.git "$TMP_DIR/x-old"
git clone --quiet --depth 1 --branch v0.5.7 \
  https://github.com/moonbitlang/x.git "$TMP_DIR/x-new"
git clone --quiet --depth 1 --branch v0.21.3 \
  https://github.com/moonbitlang/async.git "$TMP_DIR/async-old"
git clone --quiet --depth 1 --branch v0.22.7 \
  https://github.com/moonbitlang/async.git "$TMP_DIR/async-new"

cd "$ROOT"
"$MOON" run cmd/main -- check "$TMP_DIR/x-old" "$TMP_DIR/x-new" \
  --format json --fail-on never --output "$TMP_DIR/x.json"
"$MOON" run cmd/main -- check "$TMP_DIR/async-old/src/fs" "$TMP_DIR/async-new/src/fs" \
  --format json --fail-on never --output "$TMP_DIR/async-fs.json"

python3 - "$TMP_DIR/x.json" "$TMP_DIR/async-fs.json" <<'PY'
import json
import sys

x = json.load(open(sys.argv[1], encoding="utf-8"))
async_fs = json.load(open(sys.argv[2], encoding="utf-8"))

assert x["schema_version"] == 1
assert x["summary"]["breaking"] == 0, x["summary"]
assert x["summary"]["compatible"] == 0, x["summary"]
assert x["summary"]["unchanged"] >= 800, x["summary"]

assert async_fs["schema_version"] == 1
assert async_fs["summary"]["breaking"] == 3, async_fs["summary"]
assert async_fs["summary"]["compatible"] == 11, async_fs["summary"]
assert async_fs["summary"]["unchanged"] >= 50, async_fs["summary"]

breaking_names = {
    change["name"]
    for change in async_fs["changes"]
    if change["severity"] == "breaking"
}
assert breaking_names == {"mkdir", "remove", "rmdir"}, breaking_names

print("moonbitlang/x:", x["summary"])
print("moonbitlang/async/fs:", async_fs["summary"])
PY

echo "Real-package regression passed."
