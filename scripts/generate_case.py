#!/usr/bin/env python3
"""Deterministic synthetic low-voltage outage scenario generator."""

from __future__ import annotations

import argparse
import json
import random
from pathlib import Path


def build_fixture_network() -> dict:
    nodes = [
        {"id": "T1", "label": "Transformer T1", "kind": "source"},
    ]
    edges = []

    def junction(node_id: str, parent: str, label: str) -> None:
        nodes.append({"id": node_id, "label": label, "kind": "junction"})
        edges.append(
            {
                "id": f"E-{parent}-{node_id}",
                "from": parent,
                "to": node_id,
                "section": f"{parent}-{node_id}",
            }
        )

    junction("J1", "T1", "Main trunk")
    junction("J2", "J1", "North trunk")
    junction("J3", "J1", "South trunk")
    junction("J4", "J2", "North-west trunk")
    junction("J5", "J2", "North-east trunk")
    junction("J6", "J3", "South-west trunk")
    junction("J7", "J3", "South-east trunk")
    junction("J8", "J4", "Branch 8")
    junction("J9", "J4", "Branch 9")
    junction("J10", "J5", "Branch 10")
    junction("J11", "J5", "Branch 11")
    junction("J12", "J6", "Branch 12")
    junction("J13", "J6", "Branch 13")
    junction("J14", "J7", "Branch 14")
    junction("J15", "J7", "Branch 15")

    leaf_groups = {
        "J1": 2,
        "J2": 1,
        "J3": 1,
        "J4": 2,
        "J5": 2,
        "J6": 2,
        "J7": 2,
        "J8": 3,
        "J9": 3,
        "J10": 3,
        "J11": 3,
        "J12": 3,
        "J13": 3,
        "J14": 3,
        "J15": 3,
    }
    meter_no = 100
    for parent, count in leaf_groups.items():
        for _ in range(count):
            meter = f"M{meter_no}"
            nodes.append(
                {"id": meter, "label": f"Meter {meter[1:]}", "kind": "meter"}
            )
            edges.append(
                {
                    "id": f"E-{parent}-{meter}",
                    "from": parent,
                    "to": meter,
                    "section": f"service {meter}",
                }
            )
            meter_no += 1
    return {
        "root": "T1",
        "nodes": nodes,
        "edges": edges,
    }


def orient_network(network: dict) -> tuple[dict[str, str], dict[str, list[str]]]:
    adjacency: dict[str, list[tuple[str, str]]] = {
        node["id"]: [] for node in network["nodes"]
    }
    for edge in network["edges"]:
        adjacency[edge["from"]].append((edge["to"], edge["id"]))
        adjacency[edge["to"]].append((edge["from"], edge["id"]))

    parent: dict[str, str] = {}
    parent_edge: dict[str, str] = {}
    children: dict[str, list[str]] = {
        node["id"]: [] for node in network["nodes"]
    }
    queue = [network["root"]]
    seen = {network["root"]}
    while queue:
        current = queue.pop(0)
        for neighbor, edge_id in adjacency[current]:
            if neighbor not in seen:
                seen.add(neighbor)
                parent[neighbor] = current
                parent_edge[neighbor] = edge_id
                children[current].append(neighbor)
                queue.append(neighbor)
    return parent_edge, children


def downstream(node: str, children: dict[str, list[str]]) -> set[str]:
    out: set[str] = set()
    stack = [node]
    while stack:
        current = stack.pop()
        out.add(current)
        stack.extend(children[current])
    return out


def generate(seed: int, difficulty: str = "mixed") -> dict:
    rng = random.Random(seed)
    network = build_fixture_network()
    node_by_id = {node["id"]: node for node in network["nodes"]}
    parent_edge, children = orient_network(network)

    candidate_nodes = []
    for node_id, edge_id in parent_edge.items():
        descendants = downstream(node_id, children)
        meter_count = sum(
            node_by_id[item]["kind"] == "meter" for item in descendants
        )
        if meter_count >= 2:
            candidate_nodes.append((edge_id, node_id, meter_count))

    # Branch faults are the interesting cases; feeder faults are included less
    # frequently because they are much easier to localize.
    branch_faults = [
        item for item in candidate_nodes if item[1].startswith("J")
    ]
    if seed % 5 == 0:
        fault_edge, fault_node, _ = candidate_nodes[0]
    else:
        fault_edge, fault_node, _ = rng.choice(branch_faults)

    impacted_nodes = downstream(fault_node, children)
    impacted_meters = sorted(
        item for item in impacted_nodes if node_by_id[item]["kind"] == "meter"
    )
    all_meters = sorted(
        node["id"] for node in network["nodes"] if node["kind"] == "meter"
    )

    unknown_rate = {
        "clean": 0.02,
        "mixed": 0.12,
        "severe": 0.28,
    }[difficulty]
    false_alarm_rate = {
        "clean": 0.01,
        "mixed": 0.04,
        "severe": 0.08,
    }[difficulty]

    observations = []
    for meter in all_meters:
        if rng.random() < unknown_rate:
            state = "unknown"
            confidence = round(rng.uniform(0.55, 0.9), 2)
        else:
            out = meter in impacted_meters
            if rng.random() < false_alarm_rate:
                out = not out
            state = "outage" if out else "energized"
            confidence = round(rng.uniform(0.82, 0.995), 3)
        observations.append(
            {
                "node_id": meter,
                "state": state,
                "confidence": confidence,
                "observed_at": 300 - rng.randint(0, 18),
            }
        )

    # Add a small amount of branch-point telemetry. It is usually energized,
    # and explicitly models the boundary evidence field crews rely on.
    for junction in ("J1", "J2", "J3", "J4", "J5", "J6", "J7"):
        if rng.random() < 0.45:
            out = junction in impacted_nodes
            observations.append(
                {
                    "node_id": junction,
                    "state": "outage" if out else "energized",
                    "confidence": 0.93,
                    "observed_at": 299,
                }
            )

    case = {
        "analysis_time": 300,
        "network": network,
        "observations": observations,
    }
    truth = {
        "edge_id": fault_edge,
        "fault_node_id": fault_node,
        "affected_meter_ids": impacted_meters,
        "difficulty": difficulty,
        "seed": seed,
    }
    return {"case": case, "truth": truth, "children": children, "node_by_id": node_by_id}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=int, default=11)
    parser.add_argument(
        "--difficulty", choices=("clean", "mixed", "severe"), default="mixed"
    )
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    generated = generate(args.seed, args.difficulty)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(
        json.dumps(generated["case"], ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        f"wrote {args.out} (truth={generated['truth']['edge_id']}, "
        f"meters={len(generated['truth']['affected_meter_ids'])})"
    )


if __name__ == "__main__":
    main()
