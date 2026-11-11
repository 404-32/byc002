# Deployment and integration guide

## Reference architecture

```text
smart meters / concentrator
          |
          | JSON events, status snapshots
          v
  local ingestion adapter
          |
          | normalized GridLatch input
          v
  GridLatch core (Native or JS/WASM)
          |
          +--> ranked fault section and affected meters
          +--> support/contradiction/blind evidence
          +--> restoration verification
          |
          v
 dispatch or work-order system
```

GridLatch deliberately does not own SCADA switching, protection decisions, or
field lockout. It is a diagnostic layer between telemetry and a human operator.

## Input ingestion

An adapter should produce the JSON contract in
`schema/gridlatch-input.schema.json`. Required normalization:

- use one time unit consistently;
- map device health failures to `unknown`;
- map meter last-gasp events to `outage`;
- map a fresh normal online report to `energized`;
- assign confidence from device health, event quality, and source reliability;
- keep the topology root and edge IDs stable across calls.

The engine selects the newest observation for each node. Do not pre-aggregate
opposite states before calling it, because the newest test is useful for
diagnosing communication recovery.

## Edge deployment

For a concentrator or gateway:

1. Keep a versioned topology snapshot on the device.
2. Buffer events locally with bounded memory.
3. Run `gridlatch analyze` when the evidence window closes.
4. Send the top candidate, confidence, affected IDs, and evidence lists to the
   dispatch service.
5. Require an operator to confirm field work.

For web or mobile integration:

1. Build the package for JavaScript or WebAssembly.
2. Feed the same JSON contract to avoid a second implementation.
3. Cache the topology and parameters locally.
4. Display uncertainty and blind nodes alongside the top result.

## Recommended operating parameters

The defaults are a starting point, not universal constants:

| Parameter | Default | Meaning |
|---|---:|---|
| `half_life_sec` | 120 | older observations lose weight |
| `structural_prior` | 0.18 | weak preference for smaller sections |
| outage contradiction | 2.2 | penalty for missing predicted outage |
| powered contradiction | 2.8 | penalty for power where outage predicted |

Calibrate these values against a utility-specific labeled replay set. Do not
tune them on a single incident.

## Observability

Log:

- topology version and hash;
- analysis time;
- number of usable, unknown, stale, and rejected observations;
- top candidate and confidence;
- warning codes;
- engine version;
- whether an operator accepted or rejected the recommendation.

Do not log customer names or addresses in the core engine. Meter IDs are
sufficient for computation.

## Failure policy

- Invalid topology: return an error, do not guess.
- No usable evidence: rank structurally and warn.
- High confidence ties: show multiple candidates.
- Stale evidence: lower its weight and expose the age.
- Unknown nodes: ignore them for scoring and warn.
- Unexpected restoration evidence: classify as an out-of-scope outage or
  possible topology mismatch.

## Safety checklist

- Confirm that the deployed topology matches the current switch state.
- Do not automatically open or close field equipment from GridLatch output.
- Keep a human-approval step for dispatch and protection actions.
- Re-run restoration verification after a topology change.
- Treat low-confidence or high-blind-node results as inspection guidance, not
  a confirmed fault.
