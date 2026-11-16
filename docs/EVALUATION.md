# Evaluation

GridDiagnose has two benchmark suites: a 36-case outage ranking benchmark and a
48-case multi-model regression suite.

## Legacy outage benchmark

`scripts/generate_case.py` creates a known 20-node/19-edge low-voltage tree with
15 meters, multiple trunk branches, and leaf service sections. Each synthetic
case selects a fault edge, computes the true downstream meter set, and injects:

- a fixed, reproducible dropout rate;
- false state reports;
- confidence values between 0.55 and 0.995;
- observation timestamps up to 18 seconds behind the analysis time.

`scripts/evaluate.py` invokes the actual MoonBit-built JavaScript CLI for each
case and reads the returned JSON. It records exact edge accuracy, Top-3 recall,
affected-meter Jaccard, and process-level CLI latency.

The baseline is a conventional nearest-outage heuristic: follow the first
outaged meter to its parent edge. It is intentionally simple and is not a
utility-grade competitor.

## Reproduce

```bash
moon build cmd/griddiagnose --target js --release
python scripts/evaluate.py \
  --bin _build/js/release/build/cmd/griddiagnose/griddiagnose.js \
  --cases 36
```

The output is written to `benchmark/results.json`. The seed policy is
`seed = 1000 + case_index`; the three difficulty classes cycle in
`clean, mixed, severe`.

## Results

| Difficulty | Dropout | False reports | Cases | Top-1 |
|---|---:|---:|---:|---:|
| clean | 2% | 1% | 12 | 100% |
| mixed | 12% | 4% | 12 | 91.7% |
| severe | 28% | 8% | 12 | 83.3% |

Overall:

- Top-1: **91.7%**
- Top-3: **94.4%**
- Mean affected-meter Jaccard: **92.6%**
- Nearest-outage-edge baseline: **0%**
- CLI median latency: **89.0 ms** on the current benchmark run

## Interpretation

The severe scenario contains only one true outage leaf in some cases while
random false outage reports land elsewhere. The correct section can therefore
remain in the candidate list without being the first item. This is why Top-3
recall is reported separately.

The latency is process-level CLI latency, not an in-process benchmark. It
includes Node.js startup and JSON parsing. The core computation is small enough
for an edge gateway, but the current latency claim should not be interpreted as
microbenchmark performance.

## Multi-model regression suite

`scripts/evaluate_multimodel.py` creates 48 deterministic cases:

- 12 two-fault outage scenarios;
- 12 phase scenarios covering normal, phase loss, unbalance, undervoltage, and
  overvoltage;
- 12 power-quality scenarios covering normal, sag, swell, and mixed events;
- 12 telemetry scenarios covering normal, stale, frozen, clock, topology
  mismatch, and combined anomalies.

Each case is passed through the real `griddiagnose diagnose --json` CLI. A case
passes only when the expected finding class is present and unrelated event
classes are absent where the scenario specifies a normal input.

| Model | Passed | Accuracy |
|---|---:|---:|
| Multi-fault outage | 12/12 | 100% |
| Phase | 12/12 | 100% |
| Power quality | 12/12 | 100% |
| Telemetry integrity | 12/12 | 100% |

Reproduce:

```bash
python scripts/evaluate_multimodel.py \
  --bin _build/js/release/build/cmd/griddiagnose/griddiagnose.js \
  --cases-per-model 12
```

These are controlled synthetic tests. They verify the intended diagnostic
boundaries and prevent regressions; they do not establish accuracy on a
particular utility network.
