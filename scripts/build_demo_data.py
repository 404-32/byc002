#!/usr/bin/env python3
"""Generate the static demo bundle from real GridLatch CLI output."""

from __future__ import annotations

import json
import subprocess
import argparse
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def run_cli(node: str, cli: Path, *args: str) -> dict:
    completed = subprocess.run(
        [node, str(cli), *args, "--json"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=True,
    )
    return json.loads(completed.stdout)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--node", default="node")
    parser.add_argument(
        "--bin",
        type=Path,
        default=ROOT / "_build/js/release/build/cmd/gridlatch/gridlatch.js",
    )
    args = parser.parse_args()
    branch_path = ROOT / "examples/branch_fault.json"
    feeder_path = ROOT / "examples/feeder_loss.json"
    restore_path = ROOT / "examples/restore_case.json"

    branch_input = json.loads(branch_path.read_text(encoding="utf-8"))
    feeder_input = json.loads(feeder_path.read_text(encoding="utf-8"))
    restore_input = json.loads(restore_path.read_text(encoding="utf-8"))

    branch_output = run_cli(args.node, args.bin, "analyze", str(branch_path))
    feeder_output = run_cli(args.node, args.bin, "analyze", str(feeder_path))
    restore_output = run_cli(args.node, args.bin, "verify", str(restore_path))

    scenarios = [
        {
            "id": "branch",
            "eyebrow": "缺失告警场景",
            "name": "东侧电缆故障",
            "description": "M52 在停电后掉线，算法仍利用边界与相邻电表定位到 E17。",
            "kind": "analysis",
            "network": branch_output["network"],
            "observations": branch_output["analysed_observations"],
            "analysis": branch_output["analysis"],
        },
        {
            "id": "feeder",
            "eyebrow": "台区级故障",
            "name": "配电变压器失电",
            "description": "根节点和全部电表失电，系统将 SOURCE 与第一条馈线正确拆分。",
            "kind": "analysis",
            "network": feeder_output["network"],
            "observations": feeder_output["analysed_observations"],
            "analysis": feeder_output["analysis"],
        },
        {
            "id": "restore",
            "eyebrow": "抢修闭环",
            "name": "复电范围核验",
            "description": "E17 修复后两户恢复，M53 尚未回传，系统判定为部分完成而非全部成功。",
            "kind": "restore",
            "network": restore_input["network"],
            "observations": restore_input["observations"],
            "restoration": restore_output,
        },
    ]

    out = ROOT / "demo/scenarios.generated.js"
    out.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(scenarios, ensure_ascii=False, indent=2)
    out.write_text(f"window.GRIDLATCH_SCENARIOS = {payload};\n", encoding="utf-8")
    print(f"wrote {out} with {len(scenarios)} scenarios")


if __name__ == "__main__":
    main()
