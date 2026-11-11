# Fault localization algorithm

## Input interpretation

GridLatch assumes a connected radial tree. The source node is the transformer
or feeder root. Every edge can be represented by two hypotheses:

1. the edge is healthy; or
2. the edge is open and its child-side downstream subtree loses power.

The virtual `SOURCE` hypothesis represents loss of the complete feeder. It is
selected only when root evidence and downstream evidence agree.

The implementation first validates:

- unique node identifiers;
- unique edge identifiers;
- known edge endpoints;
- exactly `N - 1` edges;
- full reachability from the configured root.

The tree is then oriented with breadth-first search. `parent_edge[node]` and
`children[node]` turn each candidate edge into a downstream set.

## Evidence normalization

Only the newest observation for a node participates in a decision. If the same
meter reports outage and then restoration, the restoration replaces the earlier
status instead of being averaged with it.

Confidence is clamped to `[0, 1]`. A future timestamp is clamped to
`analysis_time`. Observations for nodes outside the supplied topology are
reported as warnings rather than being silently counted.

The evidence weight is:

```text
w = confidence * 0.5 ^ ((analysis_time - observed_at) / half_life)
```

This allows a high-confidence recent report to dominate a stale report while
retaining a smooth contribution from older evidence.

## Candidate scoring

For each candidate edge, GridLatch computes an expected outage mask. A
downstream meter is expected to be out; every node outside the subtree is
expected to have power.

```text
supported:
    outage   + weight
    energized + weight

contradicting:
    outage    - outage_penalty * weight
    energized - powered_penalty * weight

unknown:
    no score change; recorded as blind evidence
```

The powered contradiction is slightly stronger than an outage contradiction
because a live meter is direct evidence that the implied upstream outage did
not occur.

The structural term:

```text
-structural_prior * ln(1 + affected_meter_count)
```

breaks ties toward a smaller field-testable section. It is intentionally weak;
the ranking changes when direct telemetry contradicts the prior.

The `SOURCE` candidate receives a small penalty unless the root provides
outage evidence. This prevents an unobserved source and the first feeder edge
from being treated as indistinguishable when they have the same downstream
meters.

## Probability normalization

Raw scores can be negative and can be separated by several units. GridLatch
converts them to a stable distribution:

```text
p_i = exp(score_i - max_score) / sum_j exp(score_j - max_score)
```

The maximum subtraction avoids overflow. The candidate list is sorted by score
and then by edge ID for deterministic replay.

## Worked example

`examples/branch_fault.json` contains:

- an energized trunk at `J2`;
- energized meters on the west and north branches;
- outage reports from M51 and M53 on the east branch;
- an unknown report from M52;
- stale or lower-confidence reports on several other meters.

The E17 hypothesis predicts M51, M52, and M53 to be out. M51 and M53 support it,
M52 is blind, and every observed upstream meter agrees. Individual service
edges E18 and E20 each contradict another outage on the same branch. The result
is E17 at about 89.6% confidence.

## Restoration verification

After a crew repairs a confirmed edge, observations are checked against the
edge's expected downstream meters:

- energized affected meter: restored;
- outage affected meter: still out;
- unknown affected meter: awaiting verification;
- outage outside the expected set: possible secondary fault or topology
  mismatch.

The function does not equate missing telemetry with restoration.

## Complexity and limits

For `N` nodes, `N - 1` edges, and `K` observations, the current implementation
costs `O(N * (N + K))` plus `O(N log N)` sorting. It targets tens to hundreds of
low-voltage nodes.

The current boundary is one simultaneous fault, a fixed radial topology,
optional junction telemetry, and no phase-voltage evidence. Those constraints
are surfaced in the CLI and documentation rather than hidden behind optimistic
output.
