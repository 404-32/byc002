# Changelog

## 0.5.0 - 2026-11-18

- Added phase-current consistency as independent evidence for real phase loss.
- Added multi-sensor phase-loss corroboration.
- Added an explicit `undetermined` result when a zero-voltage reading and
  frozen telemetry are observationally equivalent.
- Added real-phase-loss, stuck-sensor, and ambiguous contrast fixtures with
  committed input/output pairs.
- Added arbitration evidence-source and undetermined-boundary fields to JSON.

## 0.4.0 - 2026-11-17

- Replaced direct class confidence assignment with a signed cross-model
  evidence matrix and stable softmax normalization.
- Added decision margin, per-feature contribution traces, and explicit
  contradiction weights.
- Added spatial-support and suspect-telemetry penalties to improve separation of
  supply, measurement, and topology causes.

## 0.3.0 - 2026-11-17

- Added cross-model causal arbitration for supply, measurement, topology, and
  mixed incidents.
- Added object-overlap conflict detection between supply findings and suspect
  telemetry series.
- Added primary-cause confidence, supporting models, evidence, conflicts, and
  recommended actions to the combined report.
- Added 12 arbitration regression cases.

## 0.2.0 - 2026-11-16

- Broadened the project into GridDiagnose, a multi-model distribution-grid
  diagnostic engine.
- Added topology classification for radial, weakly meshed, partial, and
  disconnected networks.
- Added greedy multi-fault decomposition.
- Added phase-loss, unbalance, undervoltage, and overvoltage diagnosis.
- Added voltage-sag and voltage-swell event detection.
- Added telemetry staleness, clock anomaly, frozen-signal, and topology-mismatch
  diagnostics.
- Added a unified diagnostic JSON contract and combined report.

## 0.1.0 - 2026-11-11

- Added radial low-voltage topology validation.
- Added confidence-aware and time-decayed outage evidence scoring.
- Added source, branch, and service-section fault candidates.
- Added JSON input/output and an explainable CLI report.
- Added restoration verification with unknown, partial, and out-of-scope states.
- Added hand-checkable examples and an interactive topology dashboard.
- Added deterministic 36-case benchmark and reproducible metrics.
