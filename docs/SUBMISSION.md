# GridDiagnose submission brief

## One-line pitch

GridDiagnose is a MoonBit-native multi-model diagnostic engine that connects
distribution-network topology, outage evidence, phase measurements, voltage
traces, and telemetry quality to produce explainable operational findings.

## Problem

A low-voltage distribution operator may simultaneously see missing meter
messages, a phase voltage at zero, a short voltage sag, and a topology record
that disagrees with observed upstream relationships. A dashboard presents each
as a separate alert. A single-purpose outage locator treats the latter events
as missing or contradictory data.

GridDiagnose makes those signals part of one diagnostic workflow while keeping
their physical meaning separate. The common layer supplies graph context,
timestamp normalization, severity, confidence, affected objects, and evidence.

## Implemented diagnostic coverage

1. **Outage and fault section**: topology-aware ranking, source outage,
   communication dropouts, restoration checks, and greedy multi-fault
   decomposition.
2. **Phase supply**: phase loss, three-phase unbalance, sustained undervoltage,
   and overvoltage.
3. **Power quality**: grouped voltage-sag and voltage-swell events with
   duration and deviation.
4. **Telemetry integrity**: stale series, frozen values, clock anomalies,
   missing series, and declared-vs-observed parent mismatch.
5. **Topology assessment**: radial, weakly meshed, partial, disconnected, and
   empty network classification.

GridLatch remains available as a compatible outage-specific module.

## Broad deployment scenarios

- utility low-voltage station-area diagnosis;
- campus, park, and commercial-building power operations;
- industrial auxiliary power systems;
- microgrids and distributed-energy low-voltage networks;
- commissioning teams checking topology and sensor integrity;
- operators correlating outages with phase and voltage-quality events.

## What is reusable

The repository does not duplicate generic time-series statistics. Its reusable
capability is domain-specific evidence orchestration:

- typed physical graph and topology classification;
- one JSON contract for multiple diagnostic models;
- deterministic multi-fault reasoning;
- typed finding severity and evidence;
- one CLI and report for legacy outage and new multi-model workflows;
- reproducible generators and cross-model benchmark suites.

## Validation

- 19 MoonBit tests pass on `wasm-gc` and `js`.
- CI also performs a Native smoke test.
- The legacy outage benchmark contains 36 cases: 91.7% Top-1 accuracy, 94.4%
  Top-3 recall, and 92.6% mean affected-meter Jaccard.
- The multi-model suite contains 48 deterministic cases, 12 per model, and all
  expected classes pass.
- GitHub Actions runs formatting, checks, tests, release metadata validation,
  and both benchmark suites.

## Distinction from adjacent MoonBit projects

- `MoonElec` provides electrical calculations.
- `moon-power-flow` and `GridFlow` solve power flow.
- `MoonSignalKit` provides generic streaming telemetry statistics.
- `moon-stream-quality` provides generic data-quality rules.
- GridDiagnose applies physical distribution-network context to combine
  topology, outages, phases, power quality, and telemetry into diagnostic
  findings.

It is not a rebrand of the rejected MoonCompat API guard, and it is not a
repackaging of an existing power-flow library.

## Three-minute demo

1. Open `demo/index.html` on the combined scenario.
2. Point out two independent outage hypotheses.
3. Show M21 phase loss and M31 voltage unbalance.
4. Show M33 sag and swell events from the same voltage trace.
5. Show M22 frozen, duplicated-timestamp telemetry and topology mismatch.
6. Switch to the legacy outage scenario to show compatibility.

## Boundaries

Outage localization requires a rooted radial network. Weakly meshed and partial
topologies are assessed and surfaced, but unknown edges are not invented.
Multi-fault search is greedy. Phase and power-quality thresholds require
site-specific calibration. The project is decision support, not protection or
automatic switching.
