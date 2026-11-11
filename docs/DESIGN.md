# GridLatch design note

## 1. Operational problem

A smart-meter outage map answers “which customer meters are not reporting
power?” It does not directly answer “which cable or service section should the
field crew inspect?” Communication failures make the first answer noisy, and a
single transformer fault can look like many independent downstream outages.

GridLatch treats fault localization as evidence reconciliation over a known
radial network:

```text
topology + meter/status events + optional branch telemetry
                    |
                    v
expected outage footprint for every candidate section
                    |
                    v
ranked candidate section + confidence + affected customers
                    |
                    v
restoration verification
```

## 2. Actors and workflow

- A concentrator or edge gateway receives smart-meter last-gasp and online
  events.
- The gateway calls GridLatch locally when the evidence window closes or a new
  event arrives.
- A dispatch operator sees the top candidate section, confidence, supporting
  evidence, contradictions, and communication blind spots.
- After repair, a second evidence snapshot is checked against the expected
  affected set.

## 3. Data model

`Network` is a tree plus a source root. `NodeKind` distinguishes source,
junction, and meter nodes. `Edge` identifies the physical section to test.
`Observation` carries state, confidence, and timestamp. The newest observation
for each node replaces older observations for that node.

The candidate `SOURCE` represents complete transformer/feeder loss. Every
non-root edge also becomes a candidate; its fault node is the child endpoint
and its expected outage set is the downstream subtree.

## 4. Scoring

For candidate edge `e` and observation `o`:

```text
w(o) = confidence(o) * 0.5 ^ ((t_analysis - t_observe) / half_life)
```

If the expected subtree state agrees with the observed state, `w(o)` is added.
If it contradicts the observation, a class-specific penalty is subtracted.
`unknown` observations are recorded as blind evidence and do not change the
score.

The structural term is:

```text
-structural_prior * ln(1 + affected_meter_count)
```

This is deliberately weak. It resolves ambiguous near-identical hypotheses but
does not replace meter evidence. A transformer-source hypothesis receives a
small additional penalty unless the root itself supplies outage evidence.

Normalization uses:

```text
confidence(e) = exp(score(e) - max_score) / sum_k exp(score(k) - max_score)
```

The subtract-max form avoids overflow. Candidate ordering is stable: raw score
descending, then edge ID ascending.

## 5. Complexity

Let `N` be nodes, `E = N - 1` edges for a valid tree, and `K` be supplied
observations. For each of `N` candidate hypotheses, the implementation writes
or evaluates one expected subtree mask and scans `K` observations. The current
implementation is `O(N * (N + K))` plus sorting `O(N log N)`. This is intended
for a low-voltage area with tens to hundreds of nodes, not a city-scale
distribution management system.

## 6. Restoration verification

The confirmed fault edge defines an expected affected-meter set. After repair:

- energized affected meters become `restored`;
- outage affected meters remain `still_out`;
- unknown affected meters remain `unknown`;
- outage observations outside the expected set raise
  `unexpected_outage`.

The report avoids the false claim that missing telemetry means a successful
repair.

## 7. Failure handling

The parser returns structured errors for malformed JSON or missing fields.
Tree validation rejects duplicate node/edge IDs, unknown endpoints, non-radial
edge counts, and disconnected networks. Unknown observation nodes are listed as
warnings rather than silently ignored. Extreme confidence values are clamped and
reported; future timestamps are clamped to analysis time.

## 8. Safety boundary

This is decision support, not protection logic. It assumes one simultaneous
fault and an unchanged radial topology. It does not consume phase voltage,
protection relay flags, transformer loading, or field lockout state. Production
deployment would require utility topology integration, telemetry calibration,
operator override, audit logging, and fail-safe behavior on stale or missing
data.
