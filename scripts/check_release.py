#!/usr/bin/env python3
"""Check that package, CLI, README, and changelog versions agree."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    module = (ROOT / "moon.mod").read_text(encoding="utf-8")
    source = (ROOT / "gridlatch.mbt").read_text(encoding="utf-8")
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    changelog = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")

    versions = {
        "moon.mod": re.search(r'^version\s*=\s*"([^"]+)"', module, re.MULTILINE),
        "gridlatch.mbt": re.search(r'pub fn version\(\) -> String \{\s*"([^"]+)"', source),
        "README.md": re.search(r"Current release:\s*`([^`]+)`", readme),
        "CHANGELOG.md": re.search(r"^##\s+([0-9]+\.[0-9]+\.[0-9]+)\s+-\s+", changelog, re.MULTILINE),
    }
    missing = [name for name, match in versions.items() if match is None]
    if missing:
        raise SystemExit(f"missing release version in: {', '.join(missing)}")
    found = {name: match.group(1) for name, match in versions.items()}
    unique = set(found.values())
    if len(unique) != 1:
        details = "\n".join(f"  {name}: {value}" for name, value in found.items())
        raise SystemExit(f"release versions disagree:\n{details}")
    print(f"release metadata consistent: {next(iter(unique))}")


if __name__ == "__main__":
    sys.exit(main())
