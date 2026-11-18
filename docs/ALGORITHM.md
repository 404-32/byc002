# Diagnostic algorithms

## Input interpretation

The outage model assumes a connected radial tree. The source node is the
transformer or feeder root. Every edge can be represented by two hypotheses:

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

For each candidate edge, the outage model computes an expected outage mask. A
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

Raw scores can be negative and can be separated by several units. The engine
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

The current boundary is explicit: outage localization requires a rooted tree;
multi-fault decomposition is greedy; phase and quality diagnostics use
configurable thresholds; and unknown topology relationships are reported rather
than guessed. The broader combined pipeline can still run other diagnostic
models when outage localization is unavailable.

## Multi-fault decomposition

The single-fault ranking is reused as one stage of a greedy decomposition.
After selecting a hypothesis, observations in its affected subtree are masked
as unknown. The next stage must explain evidence that remains unexplained.

Stage confidence is normalized within each stage. It is not treated as a joint
probability across all faults.

## Topology assessment

Union-find computes the number of connected components. For a valid graph with
`N` nodes, `E` edges, and `C` components, the cycle rank is:

```text
cycle_rank = max(0, E - N + C)
```

Cycle rank greater than zero produces `weakly_meshed`. Multiple components
produce `disconnected`. Unregistered relationships or isolated meter nodes
produce `partial`.

## Phase diagnosis

A phase below 15% nominal is treated as absent. If one or two phases are absent,
the finding is `phase_loss`. Otherwise, phase voltage unbalance is:

```text
unbalance_percent = 100 * (max(Va, Vb, Vc) - min(Va, Vb, Vc))
                    / mean(Va, Vb, Vc)
```

Thresholds default to 5% warning and 10% critical. Sustained values below 90%
or above 110% nominal produce undervoltage or overvoltage findings.

## Power-quality events

Samples below 90% nominal are grouped into sag intervals; samples above 110%
are grouped into swell intervals. A gap larger than 2.5 sample periods splits
the interval. Each event reports its time range, duration, extreme voltage, and
relative deviation.

## Telemetry integrity

The integrity model compares the latest sample with `analysis_time`, checks
strict timestamp ordering, and finds constant-value runs longer than the stuck
window. Declared and observed parent IDs are compared without changing the
topology graph.

## Cross-model causal arbitration

The arbitration layer assigns each finding a subject class:

```text
supply:
    outage fault nodes, affected meters, phase readings, voltage events
measurement:
    stale/frozen/clock/missing-series subjects
topology:
    mismatch nodes, unknown topology objects, isolated nodes, non-radial graph
```

It constructs a cause for each non-empty class and gives every feature a signed
weight. Examples include:

```text
supply:
    + outage hypothesis count and stage confidence
    + phase loss / unbalance / voltage events
    + evidence spread across multiple affected objects
    - supply readings that depend on suspect telemetry

measurement:
    + stale / frozen / clock findings
    + overlap with supply readings

topology:
    + declared/observed parent mismatch
    + partial or non-radial topology
    + outage residual under an uncertain topology
    - direct outage hypotheses already explained by a radial tree
```

The scores are normalized with a stable softmax. The report includes each
feature weight, the normalized cause probability, and the margin between the top
two causes. The principal decision rule is:

- supply only -> `supply_fault`;
- measurement only -> `measurement_issue`;
- topology only -> `topology_issue`;
- supply plus measurement overlap with no independent outage -> prefer
  `measurement_issue`;
- distinct causes remain highly supported without a clear margin -> `mixed`.

### Independent evidence is required for phase loss

A zero voltage value alone is not evidence of a real phase loss because a stuck
sensor can generate the same value. The arbitration checks independent channels:

- another node reporting the same phase loss;
- missing-phase current near zero while other phases remain loaded;
- missing-phase voltage at zero while the corresponding phase current stays
  live, which contradicts a supply-side explanation;
- outage observations in the corresponding electrical region.

When one missing-phase reading and frozen telemetry coexist without a second
voltage source or current evidence, the primary class is `undetermined`. The
report lists the evidence source and the exact missing discriminator. It does
not force a high-confidence supply or sensor label.

### Sustained undervoltage

For voltage events lasting at least one second, the power-quality report exposes
minimum, maximum, and variation percentage. A real sustained undervoltage can be
corroborated by:

- multiple independent sensors observing the same extent;
- non-identical time evolution rather than a bit-for-bit frozen value;
- an independent outage state.

A single flat low-voltage trace plus frozen telemetry favors the measurement
cause. A single flat trace without any telemetry anomaly or independent spatial
source is `undetermined`.

### Model boundary versus topology registration

`topology_issue` is emitted when evidence says the registered topology is wrong:
an observed parent differs from the declared parent, an edge is unregistered,
or a meter is isolated.

`model_inapplicable` is emitted when the topology is structurally valid but not
supported by the selected model, for example a weakly meshed network with no
registration mismatch. The downstream model reports what part of the system
could not be evaluated.

Conflicts are retained in the report. For example, an outage hypothesis on a
partially known topology includes the topology caveat instead of presenting a
false precision.
