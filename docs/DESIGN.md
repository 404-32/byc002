# GridDiagnose architecture

## Product boundary

GridDiagnose is a distribution-network diagnostic engine. It consumes
caller-supplied topology, event, phase, time-series, and telemetry data. It
returns typed findings and evidence. It does not execute switching, protection,
or field-control actions.

The project has four diagnostic models:

```text
                       shared input and timestamp policy
                                      |
                    +-----------------+-----------------+
                    |                 |                 |
              graph topology      telemetry       phase / voltage
                    |                 |                 |
              outage + multi-fault  data integrity   supply + power quality
                    +-----------------+-----------------+
                                      |
                            unified diagnostic report
```

GridLatch is the outage-localization module retained for compatibility.

## Core data flow

1. An adapter reads topology and measurements from JSON.
2. Timestamps and confidence values are normalized.
3. The topology assessor counts components and independent cycles.
4. Optional diagnostic modules run independently.
5. Findings retain source objects and evidence rather than returning one
   unexplained score.
6. A combined report counts critical and warning findings.

This design allows a site to deploy only outage diagnosis, only power quality,
or the complete suite without changing the wire format.

## Shared graph model

`Network` stores source, junction, and meter nodes plus physical edges. The
legacy outage model requires a rooted tree. The broader topology assessor uses
union-find and can classify radial, weakly meshed, partial, disconnected, and
empty networks.

For unsupported physical models, the engine reports what it knows and skips the
model that requires stronger assumptions. It never fabricates unknown edges.

## Outage model

Every non-root tree edge is a field-testable candidate. Its expected impact is
the downstream meter set. Evidence compatibility uses outage, energized, and
unknown states. Observations decay over time and confidence.

The multi-fault extension is greedy:

1. Rank single-fault hypotheses.
2. Accept the top hypothesis only if it explains unexplained outage evidence.
3. Mask the explained subtree as unknown.
4. Repeat up to a configured limit.
5. Preserve every residual unexplained outage in the report.

Stage confidence is intentionally shown per iteration. Probability mass is
normalized inside a stage, not across the complete multi-fault chain.

## Phase model

A phase is treated as present when its voltage is at least 15% of nominal.
One or two present phases indicate phase loss. For three present phases,
`(max-min)/mean` identifies unbalance. Sustained voltage below 90% or above
110% nominal identifies undervoltage or overvoltage.

The output distinguishes the fault type, affected phases, metric, and severity.

## Power-quality model

Voltage samples are sorted by timestamp. Adjacent observations outside a 90%
to 110% nominal band are grouped into intervals. The event duration is based on
the observed midpoint sample period. A sustained event records start, end,
duration, extreme voltage, and percentage deviation.

This model does not infer protection operation or a physical fault by itself.
It supplies evidence that can later be correlated with an outage or equipment
event.

## Telemetry integrity model

The integrity model reports:

- no samples;
- latest sample older than the stale threshold;
- duplicate or decreasing timestamps;
- a value frozen for longer than the stuck window;
- a declared parent that differs from an observed upstream relation.

The report does not delete suspect evidence. Other diagnostic models still
receive it, allowing the combined output to explain disagreement.

## Combined report

`run_diagnostic` runs every supplied model and assembles:

- topology assessment;
- multi-fault outage hypotheses;
- phase findings;
- voltage-quality events;
- telemetry-integrity findings;
- warnings and severity counts.

Optional sections are omitted if not supplied. If fault localization is not
structurally valid, its error becomes a report warning while the other models
continue.

## Causal arbitration

Independent detections are not treated as a final diagnosis. `arbitrate_causes`
reconciles them using object identity, branch context, and cross-model support.

It builds three subject sets:

- outage, phase, and power-quality subjects support a supply hypothesis;
- frozen, stale, clock, and missing-series subjects support a measurement
  hypothesis;
- topology mismatch, unregistered objects, isolated nodes, and non-radial
  topology support a topology hypothesis.

The arbitration emits each supported cause with its own confidence and
evidence. A positive overlap between a supply reading and a suspect
measurement series is recorded as a conflict. If no independent outage supports
a single phase/quality reading on a suspect series, the measurement hypothesis
becomes primary.

When multiple distinct cause classes remain supported, the primary class is
`mixed`. This preserves independent project depth: a supply fault and a
topology-registration error are not collapsed into one threshold alarm.

Each cause includes a recommended action, allowing a consumer to request field
inspection, sensor repair, or topology reconciliation separately.

## Extensibility

New diagnostic models should consume the existing graph/time-series contracts
and return findings with object IDs, severity, confidence, and evidence. They
should not duplicate the JSON adapter or aggregate unrelated fault types into a
single unexplained score.

Potential next models include transformer-load stress, phase-current
consistency, protection-event correlation, and utility-specific outage
messages.

## Safety boundary

The engine is deterministic decision support. Production deployment requires
topology validation, sensor calibration, operator override, audit logging, and
organization-specific safety procedures.
