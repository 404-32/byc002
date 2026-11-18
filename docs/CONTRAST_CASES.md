# Contrast cases: phase loss versus stuck sensor

These three examples start from a similar visible symptom: phase C voltage is
reported as zero. They differ in independent evidence and produce different
diagnoses.

## 1. Real phase loss

Input: [`real_phase_loss.json`](../examples/contrasts/real_phase_loss.json)

Evidence:

- two independent readings report phase C missing;
- phase C current is approximately zero at both nodes;
- phases A and B carry normal current.

Output: `supply_fault`.

The current/voltage consistency and multi-sensor agreement are independent of
the zero voltage label itself.

## 2. Stuck sensor with live phase current

Input: [`stuck_sensor.json`](../examples/contrasts/stuck_sensor.json)

Evidence:

- one reading reports phase C voltage at zero;
- phase C current remains at a normal live value;
- the associated telemetry series is frozen.

Output: `measurement_issue`.

The live phase current contradicts the missing-voltage interpretation. The
frozen series is supporting evidence, not the only basis for the decision.

## 3. Observationally ambiguous input

Input:
[`ambiguous_phase_vs_sensor.json`](../examples/contrasts/ambiguous_phase_vs_sensor.json)

Evidence:

- one reading reports phase C voltage at zero;
- no phase currents or second voltage sensor are supplied;
- the same meter has frozen telemetry.

Output: `undetermined`.

With only one voltage source, a real phase loss and a sensor reporting zero are
observationally equivalent. The engine reports that a second voltage source,
phase current, or field measurement is required. It does not use a softmax
score to claim physical certainty.

## Reproduce

```bash
moon build cmd/griddiagnose --target js --release
moon run cmd/griddiagnose --target js -- diagnose examples/contrasts/real_phase_loss.json
moon run cmd/griddiagnose --target js -- diagnose examples/contrasts/stuck_sensor.json
moon run cmd/griddiagnose --target js -- diagnose examples/contrasts/ambiguous_phase_vs_sensor.json
```

The corresponding JSON outputs are committed next to the inputs.

## 4. Sustained undervoltage with independent corroboration

Input:
[`persistent_undervoltage.json`](../examples/contrasts/persistent_undervoltage.json)

Two independent voltage series remain below 90% nominal for a sustained period
and vary slightly over time. Output: `supply_fault`.

The independent spatial source and the non-identical voltage trajectory prevent
the event from being treated as a frozen sensor value.

## 5. Sustained undervoltage coincident with a frozen series

Input:
[`stuck_undervoltage_sensor.json`](../examples/contrasts/stuck_undervoltage_sensor.json)

One voltage series is exactly unchanged while telemetry health reports a frozen
series. Output: `measurement_issue`.

## 6. Sustained undervoltage without sufficient independent evidence

Input:
[`ambiguous_undervoltage.json`](../examples/contrasts/ambiguous_undervoltage.json)

One constant low-voltage series is present without a second sensor, variation,
outage state, or telemetry-health observation. Output: `undetermined`.

## 7. Topology registration error

Input:
[`topology_registration_error.json`](../examples/contrasts/topology_registration_error.json)

The network itself is radial, but the observed parent differs from the declared
parent. Output: `topology_issue`.

## 8. Model not applicable

Input:
[`model_inapplicable.json`](../examples/contrasts/model_inapplicable.json)

The network is weakly meshed, while the outage-section model requires a rooted
tree. There is no observed parent mismatch. Output: `model_inapplicable`, not
`topology_issue`.

This separates a limitation of the selected diagnostic model from an error in
the topology registration.
