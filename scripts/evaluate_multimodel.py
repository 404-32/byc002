#!/usr/bin/env python3
"""Evaluate all GridDiagnose diagnostic models with deterministic scenarios."""

from __future__ import annotations

import argparse
import json
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def base_network() -> dict:
    return {
        "root": "T1",
        "nodes": [
            {"id": "T1", "kind": "source"},
            {"id": "J1", "kind": "junction"},
            {"id": "J2", "kind": "junction"},
            {"id": "J3", "kind": "junction"},
            {"id": "M21", "kind": "meter"},
            {"id": "M22", "kind": "meter"},
            {"id": "M31", "kind": "meter"},
            {"id": "M32", "kind": "meter"},
            {"id": "M33", "kind": "meter"},
        ],
        "edges": [
            {"id": "E0", "from": "T1", "to": "J1", "section": "feeder"},
            {"id": "E1", "from": "J1", "to": "J2", "section": "branch-2"},
            {"id": "E2", "from": "J1", "to": "J3", "section": "branch-3"},
            {"id": "E3", "from": "J2", "to": "M21", "section": "M21 service"},
            {"id": "E4", "from": "J2", "to": "M22", "section": "M22 service"},
            {"id": "E5", "from": "J3", "to": "M31", "section": "M31 service"},
            {"id": "E6", "from": "J3", "to": "M32", "section": "M32 service"},
            {"id": "E7", "from": "J3", "to": "M33", "section": "M33 service"},
        ],
    }


def outage_case(index: int) -> tuple[dict, callable]:
    network = base_network()
    confidence = 0.84 + (index % 4) * 0.04
    case = {
        "analysis_time": 500,
        "network": network,
        "observations": [
            {"node_id": "M21", "state": "outage", "confidence": confidence},
            {"node_id": "M22", "state": "energized", "confidence": confidence},
            {"node_id": "M31", "state": "outage", "confidence": confidence},
            {"node_id": "M32", "state": "outage", "confidence": confidence},
            {"node_id": "M33", "state": "outage", "confidence": confidence},
        ],
    }

    def check(output: dict) -> bool:
        faults = output.get("outage", {}).get("faults", [])
        edges = {item["candidate"]["edge_id"] for item in faults}
        return len(faults) == 2 and edges == {"E3", "E2"}

    return case, check


def phase_case(index: int) -> tuple[dict, callable]:
    kind = ("normal", "phase_loss", "unbalance", "undervoltage", "overvoltage")[
        index % 5
    ]
    a, b, c = 230.0, 230.0, 230.0
    expected = None
    if kind == "phase_loss":
        c = 0.0
        expected = "phase_loss"
    elif kind == "unbalance":
        a, b, c = 245.0, 205.0, 230.0
        expected = "voltage_unbalance"
    elif kind == "undervoltage":
        a, b, c = 185.0, 188.0, 182.0
        expected = "undervoltage"
    elif kind == "overvoltage":
        a, b, c = 263.0, 260.0, 262.0
        expected = "overvoltage"
    case = {
        "analysis_time": 500,
        "phase_readings": [
            {
                "node_id": "M1",
                "timestamp": 500,
                "a_voltage": a,
                "b_voltage": b,
                "c_voltage": c,
            }
        ],
    }

    def check(output: dict) -> bool:
        findings = output.get("phase", {}).get("findings", [])
        if expected is None:
            return len(findings) == 0
        return any(item["kind"] == expected for item in findings)

    return case, check


def power_quality_case(index: int) -> tuple[dict, callable]:
    kind = ("normal", "sag", "swell", "both")[index % 4]
    samples = [{"timestamp": i * 0.01, "voltage": 230} for i in range(8)]
    expected = set()
    if kind in ("sag", "both"):
        samples[2]["voltage"] = 178
        samples[3]["voltage"] = 171
        expected.add("voltage_sag")
    if kind in ("swell", "both"):
        samples[5]["voltage"] = 261
        samples[6]["voltage"] = 266
        expected.add("voltage_swell")
    case = {
        "analysis_time": 500,
        "voltage_series": [
            {
                "node_id": "M1",
                "nominal_voltage": 230,
                "samples": samples,
            }
        ],
    }

    def check(output: dict) -> bool:
        found = {
            item["kind"]
            for item in output.get("power_quality", {}).get("events", [])
        }
        return found == expected

    return case, check


def telemetry_case(index: int) -> tuple[dict, callable]:
    kind = ("normal", "stale", "stuck", "clock", "topology", "all")[index % 6]
    timestamps = [400, 450, 500]
    if kind in ("clock", "all"):
        timestamps = [500, 450, 400]
    values = [1.0, 1.1, 1.2]
    if kind in ("stuck", "all"):
        values = [1.0, 1.0, 1.0]
    analysis_time = 1000 if kind in ("stale", "all") else 510
    case = {
        "analysis_time": analysis_time,
        "telemetry_series": [
            {
                "node_id": "M1",
                "samples": [
                    {"timestamp": timestamps[i], "value": values[i]}
                    for i in range(3)
                ],
            }
        ],
    }
    expected = set()
    if kind in ("stale", "all"):
        expected.add("stale_series")
    if kind in ("stuck", "all"):
        expected.add("stuck_series")
    if kind in ("clock", "all"):
        expected.add("clock_anomaly")
    if kind in ("topology", "all"):
        case["topology_links"] = [
            {"node_id": "M1", "declared_parent": "J1", "observed_parent": "J2"}
        ]
        expected.add("topology_mismatch")

    def check(output: dict) -> bool:
        found = {
            item["kind"]
            for item in output.get("telemetry", {}).get("findings", [])
        }
        return expected.issubset(found)

    return case, check


def arbitration_case(index: int) -> tuple[dict, callable]:
    kind = (
        "supply_fault",
        "measurement_issue",
        "topology_issue",
        "mixed",
        "real_phase_loss",
        "stuck_sensor",
        "ambiguous",
    )[index % 7]
    case = {"analysis_time": 500}
    if kind in ("supply_fault", "mixed", "stuck_sensor", "ambiguous"):
        case["phase_readings"] = [
            {
                "node_id": "M1",
                "timestamp": 499,
                "a_voltage": 230,
                "b_voltage": 230,
                "c_voltage": 0,
            }
        ]
    if kind == "real_phase_loss":
        case["phase_readings"] = [
            {
                "node_id": "M1",
                "timestamp": 499,
                "a_voltage": 230,
                "b_voltage": 229,
                "c_voltage": 0,
                "a_current": 4.8,
                "b_current": 4.7,
                "c_current": 0,
            },
            {
                "node_id": "M2",
                "timestamp": 499,
                "a_voltage": 229,
                "b_voltage": 230,
                "c_voltage": 0,
                "a_current": 4.9,
                "b_current": 4.8,
                "c_current": 0,
            },
        ]
    if kind == "stuck_sensor":
        case["phase_readings"][0].update(
            {"a_current": 4.8, "b_current": 4.7, "c_current": 4.8}
        )
    if kind in ("measurement_issue", "mixed", "stuck_sensor", "ambiguous"):
        case["telemetry_series"] = [
            {
                "node_id": "M2" if kind == "mixed" else "M1",
                "samples": [
                    {"timestamp": 100, "value": 1.0},
                    {"timestamp": 200, "value": 1.0},
                ],
            }
        ]
    if kind in ("topology_issue", "mixed"):
        case["network"] = base_network()
        case["unknown_topology_edge_ids"] = ["X-NEW"]
        case["topology_links"] = [
            {"node_id": "M22", "declared_parent": "J2", "observed_parent": "J3"}
        ]

    def check(output: dict) -> bool:
        expected = {
            "real_phase_loss": "supply_fault",
            "stuck_sensor": "measurement_issue",
            "ambiguous": "undetermined",
        }.get(kind, kind)
        return output.get("arbitration", {}).get("primary_class") == expected

    return case, check


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bin", type=Path, required=True)
    parser.add_argument("--node", default="node")
    parser.add_argument("--cases-per-model", type=int, default=12)
    parser.add_argument(
        "--out", type=Path, default=ROOT / "benchmark/multimodel-results.json"
    )
    args = parser.parse_args()

    generators = [
        ("outage_multi", outage_case),
        ("phase", phase_case),
        ("power_quality", power_quality_case),
        ("telemetry_integrity", telemetry_case),
        ("causal_arbitration", arbitration_case),
    ]
    results = {}
    failures = []
    with tempfile.TemporaryDirectory(prefix="griddiagnose-bench-") as temp:
        temp_path = Path(temp)
        for category, generator in generators:
            passed = 0
            for index in range(args.cases_per_model):
                case, verify = generator(index)
                input_path = temp_path / f"{category}-{index}.json"
                input_path.write_text(
                    json.dumps(case, ensure_ascii=False), encoding="utf-8"
                )
                completed = subprocess.run(
                    [
                        args.node,
                        str(args.bin.resolve()),
                        "diagnose",
                        str(input_path),
                        "--json",
                    ],
                    cwd=ROOT,
                    capture_output=True,
                    text=True,
                    encoding="utf-8",
                    check=False,
                )
                if completed.returncode != 0:
                    failures.append(
                        {"category": category, "case": index, "error": completed.stderr}
                    )
                    continue
                output = json.loads(completed.stdout)
                if verify(output):
                    passed += 1
                else:
                    failures.append(
                        {"category": category, "case": index, "output": output}
                    )
            results[category] = {
                "cases": args.cases_per_model,
                "passed": passed,
                "accuracy": passed / args.cases_per_model,
            }
    summary = {
        "cases": args.cases_per_model * len(generators),
        "results": results,
        "failures": failures,
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
