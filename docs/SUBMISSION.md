# GridLatch submission brief

## One-line pitch

GridLatch is a MoonBit-native evidence engine that turns noisy smart-meter
outage alerts into a ranked, explainable fault section and a restoration
checklist for low-voltage distribution networks.

## Real problem

During a low-voltage outage, a smart-meter dashboard can show dozens of dark
users without telling the crew which cable section failed. Communication
dropouts make the status set incomplete, and false or stale reports can point
at the wrong branch.

GridLatch combines the known radial topology with last-gasp events, online
status, confidence, timestamps, and optional branch-point telemetry. It answers
three operational questions:

1. Which field-testable section is most likely faulty?
2. Which meters should be affected if that hypothesis is true?
3. After repair, is the affected area actually restored?

## Users and deployment

Primary users are distribution-network dispatch teams and field crews. The
engine is intended for a concentrator, edge gateway, or browser/WebAssembly
environment where connectivity to a cloud service may be intermittent.

## What is implemented

- Typed MoonBit network and event model.
- Radial-tree validation with structured error paths.
- Confidence- and age-weighted evidence scoring.
- Source, trunk, branch, and service section candidates.
- Stable normalized confidence and top-k ranking.
- Supporting, contradicting, and communication-blind evidence.
- Restoration verification for complete, partial, unknown, and out-of-scope
  states.
- JSON API and CLI.
- Interactive three-scenario dashboard.
- Reproducible fault injection and a 36-case benchmark.
- Unit tests and cross-target CI configuration.

## Why it is not an existing-project resubmission

The rejected project addressed API compatibility and permission guarding. This
project has a different domain, different input/output, and different technical
core.

Within the MoonBit ecosystem, the closest existing projects are calculation
libraries:

- `MoonElec`: circuit and electrical formulas.
- `moon-power-flow`: unbalanced distribution power-flow solving.
- `gridflow`: balanced positive-sequence power-flow solving.

GridLatch does not solve voltages or currents. It performs fault-section
inference from outage evidence. A separate cold-chain monitoring project was
also found and is unrelated to this power-system use case.

## Validation

The deterministic benchmark covers 36 synthetic cases at three evidence-quality
levels:

| Metric | Value |
|---|---:|
| Top-1 fault-section accuracy | 91.7% |
| Top-3 recall | 94.4% |
| Mean affected-meter Jaccard | 92.6% |
| Clean-scenario Top-1 | 100% |
| Mixed-scenario Top-1 | 91.7% |
| Severe-scenario Top-1 | 83.3% |

The included real examples exercise:

- branch fault with a communication dropout;
- feeder-wide outage with explicit root evidence;
- partial repair where one meter has not yet returned.

## Three-minute demo

1. Open `demo/index.html`.
2. Show the east-cable fault. Point out M52 as unknown rather than outage.
3. Explain why E17 beats the two individual service edges.
4. Switch to the transformer outage and show the `SOURCE` hypothesis.
5. Switch to repair verification and show two restored meters plus one pending.
6. Run the CLI on `examples/branch_fault.json` with `--json`.

## Boundaries

The current release supports one simultaneous fault and an unchanged radial
tree. It is decision support, not protection or dispatch automation. Production
deployment requires utility topology integration, phase/voltage evidence,
telemetry calibration, operator override, and audit logging.

## Next milestones

- Multiple-fault decomposition using connected outage components.
- Impedance and phase-voltage evidence for sections with identical meter sets.
- Topology-change reconciliation from field switching records.
- Import adapters for common distribution automation event formats.
- Operator-labeled replay set from anonymized utility data.
