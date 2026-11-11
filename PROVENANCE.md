# Provenance and originality

GridLatch was created for the MoonBit Open Source Hackathon submission from an
empty repository on 2026-11-11.

## Implemented here

- Network and observation data model.
- Radial-tree validation and orientation.
- Topology-aware weighted fault candidate scoring.
- Stable confidence normalization and evidence explanations.
- Restore verification logic.
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

## Data

All included topology and event data are synthetic and committed for
reproducibility. No utility customer data is used.

## AI assistance

AI-assisted development was used for implementation scaffolding, tests, and
documentation. The project behavior is checked by the committed MoonBit test
suite and the reproducible benchmark.
