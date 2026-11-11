#!/usr/bin/env python3
"""Run GridLatch against deterministic fault scenarios and summarize metrics."""

from __future__ import annotations

import argparse
import json
import statistics
import subprocess
import tempfile
import time
from pathlib import Path

from generate_case import generate


def jaccard(left: list[str], right: list[str]) -> float:
    left_set = set(left)
    right_set = set(right)
    if not left_set and not right_set:
        return 1.0
    return len(left_set & right_set) / len(left_set | right_set)


def naive_prediction(generated: dict) -> tuple[str, list[str]]:
    node_by_id = generated["node_by_id"]
    case = generated["case"]
    children = generated["children"]
    parent_edge: dict[str, str] = {}
    for edge in case["network"]["edges"]:
        if edge["to"] in children.get(edge["from"], []):
            parent_edge[edge["to"]] = edge["id"]
        elif edge["from"] in children.get(edge["to"], []):
            parent_edge[edge["from"]] = edge["id"]
    first_outage = next(
        obs["node_id"]
        for obs in case["observations"]
        if obs["state"] == "outage"
    )
    edge_id = parent_edge[first_outage]
    impacted_nodes = set()
    stack = [first_outage]
    while stack:
        node = stack.pop()
        impacted_nodes.add(node)
        stack.extend(children[node])
    meters = sorted(
        node for node in impacted_nodes if node_by_id[node]["kind"] == "meter"
    )
    return edge_id, meters


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bin", type=Path, required=True)
    parser.add_argument("--node", default="node")
    parser.add_argument("--cases", type=int, default=36)
    parser.add_argument("--out", type=Path, default=Path("benchmark/results.json"))
    args = parser.parse_args()

    difficulties = ("clean", "mixed", "severe")
    exact = 0
    top3 = 0
    affected_scores = []
    baseline_exact = 0
    latencies = []
    failures = []
    predictions = []

    with tempfile.TemporaryDirectory(prefix="gridlatch-bench-") as temp_dir:
        temp_root = Path(temp_dir)
        for index in range(args.cases):
            difficulty = difficulties[index % len(difficulties)]
            generated = generate(seed=1000 + index, difficulty=difficulty)
            case_path = temp_root / f"case-{index}.json"
            case_path.write_text(
                json.dumps(generated["case"], ensure_ascii=False),
                encoding="utf-8",
            )
            started = time.perf_counter()
            completed = subprocess.run(
                [
                    args.node,
                    str(args.bin.resolve()),
                    "analyze",
                    str(case_path),
                    "--json",
                ],
                cwd=Path(__file__).resolve().parents[1],
                capture_output=True,
                text=True,
                encoding="utf-8",
                check=False,
            )
            latencies.append((time.perf_counter() - started) * 1000)
            if completed.returncode != 0:
                failures.append(
                    {
                        "index": index,
                        "stderr": completed.stderr.strip(),
                    }
                )
                continue

            output = json.loads(completed.stdout)
            candidates = output["analysis"]["candidates"]
            truth = generated["truth"]
            truth_edge = truth["edge_id"]
            truth_meters = truth["affected_meter_ids"]
            predicted_edge = candidates[0]["edge_id"]
            predicted_meters = candidates[0]["affected_meter_ids"]
            baseline_edge, baseline_meters = naive_prediction(generated)

            exact += predicted_edge == truth_edge
            top3 += any(item["edge_id"] == truth_edge for item in candidates[:3])
            affected_scores.append(jaccard(predicted_meters, truth_meters))
            baseline_exact += baseline_edge == truth_edge
            predictions.append(
                {
                    "case": index,
                    "seed": truth["seed"],
                    "difficulty": difficulty,
                    "truth_edge": truth_edge,
                    "predicted_edge": predicted_edge,
                    "top3_edges": [item["edge_id"] for item in candidates[:3]],
                    "confidence": candidates[0]["confidence"],
                    "affected_jaccard": affected_scores[-1],
                }
            )

    count = args.cases
    summary = {
        "cases": count,
        "difficulty_distribution": {
            name: sum(1 for i in range(count) if difficulties[i % 3] == name)
            for name in difficulties
        },
        "gridlatch_top1_accuracy": exact / count if count else 0.0,
        "gridlatch_top3_recall": top3 / count if count else 0.0,
        "gridlatch_mean_affected_meter_jaccard": (
            statistics.fmean(affected_scores) if affected_scores else 0.0
        ),
        "nearest_outage_edge_baseline_top1_accuracy": (
            baseline_exact / count if count else 0.0
        ),
        "accuracy_by_difficulty": {
            name: (
                sum(
                    1
                    for item in predictions
                    if item["difficulty"] == name
                    and item["truth_edge"] == item["predicted_edge"]
                )
                / max(
                    1,
                    sum(
                        1
                        for item in predictions
                        if item["difficulty"] == name
                    ),
                )
            )
            for name in difficulties
        },
        "cli_latency_ms_median": (
            statistics.median(latencies) if latencies else 0.0
        ),
        "cli_latency_ms_p95": (
            statistics.quantiles(latencies, n=20)[-1]
            if len(latencies) >= 20
            else max(latencies, default=0.0)
        ),
        "failures": failures,
        "predictions": predictions,
        "seed_policy": "seed=1000+index; difficulty cycles clean,mixed,severe",
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
