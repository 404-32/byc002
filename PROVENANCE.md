# Provenance and originality

GridDiagnose was created for the MoonBit Open Source Hackathon submission from
an empty repository on 2026-11-11. Version 0.2.0 broadened the original
GridLatch outage locator with shared topology, phase, power-quality, telemetry,
multi-fault, and unified-report capabilities on 2026-11-16.

## Implemented here

- Network and observation data model.
- Radial-tree validation and orientation.
- Topology-aware weighted fault candidate scoring.
- Stable confidence normalization and evidence explanations.
- Restore verification logic.
- Multi-fault decomposition and general topology classification.
- Phase, power-quality, and telemetry-integrity diagnosis.
- JSON input/output contract.
- CLI, examples, demo, synthetic benchmark generator, and evaluator.

## References

- The implementation uses the official MoonBit standard library and
  `moonbitlang/x` file-system package.
- Design references are general power-distribution concepts: radial topology,
  downstream affected sets, smart-meter last-gasp evidence, confidence decay,
  and post-repair verification. No source code was copied from another
  distribution automation repository.
- Existing MoonBit projects were checked to distinguish the scope:
  - `SupremeHuaji/MoonElec`: electrical formulas and calculations.
  - `Duckweed-yhb/moon-power-flow`: unbalanced distribution power flow.
  - `Zcxssxx/gridflow`: balanced positive-sequence power flow.
  - `sujy123456/sujy_project`: cold-chain excursion analysis.
  - `cn-wn/MoonSignalKit`: generic streaming telemetry statistics.
  - `zmjknn/moon-stream-quality`: generic stream-quality rules.

## Data

All included topology and event data are synthetic and committed for
reproducibility. No utility customer data is used.

## AI assistance

AI-assisted development was used for implementation scaffolding, tests, and
documentation. The project behavior is checked by the committed MoonBit test
suite and the reproducible benchmark.
