# Evaluation

## Method

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
moon build cmd/gridlatch --target js --release
python scripts/evaluate.py \
  --bin _build/js/release/build/cmd/gridlatch/gridlatch.js \
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
- CLI median latency: **70.9 ms**

## Interpretation

The severe scenario contains only one true outage leaf in some cases while
random false outage reports land elsewhere. The correct section can therefore
remain in the candidate list without being the first item. This is why Top-3
recall is reported separately.

The latency is process-level CLI latency, not an in-process benchmark. It
includes Node.js startup and JSON parsing. The core computation is small enough
for an edge gateway, but the current latency claim should not be interpreted as
microbenchmark performance.
