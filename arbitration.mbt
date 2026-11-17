///|
pub struct CauseHypothesis {
  class : String
  confidence : Double
  subject_ids : Array[String]
  supporting_models : Array[String]
  evidence : Array[String]
  recommended_action : String
}

///|
pub struct CausalArbitration {
  primary_class : String
  overall_confidence : Double
  causes : Array[CauseHypothesis]
  conflicts : Array[String]
}

///|
fn add_unique(values : Array[String], value : String) -> Unit {
  if !values.contains(value) {
    values.push(value)
  }
  ()
}

///|
fn capped_confidence(value : Double) -> Double {
  if value < 0.0 {
    0.0
  } else if value > 1.0 {
    1.0
  } else {
    value
  }
}

///|
fn count_overlap(left : Array[String], right : Array[String]) -> Int32 {
  let mut count = 0
  for value in left {
    if right.contains(value) {
      count += 1
    }
  }
  count
}

///|
/// Reconcile diagnostic findings into supply, measurement, and topology causes.
/// The arbitration uses object overlap rather than severity alone.
pub fn arbitrate_causes(
  topology : TopologyAssessment?,
  outage : MultiFaultReport?,
  phase : PhaseReport,
  power_quality : PowerQualityReport,
  telemetry : TelemetryReport,
) -> CausalArbitration {
  let supply_subjects : Array[String] = []
  let measurement_subjects : Array[String] = []
  let topology_subjects : Array[String] = []
  let supply_evidence : Array[String] = []
  let measurement_evidence : Array[String] = []
  let topology_evidence : Array[String] = []
  let conflicts : Array[String] = []
  let mut outage_count = 0
  match outage {
    Some(report) => {
      outage_count = report.faults.length()
      for hypothesis in report.faults {
        add_unique(supply_subjects, hypothesis.candidate.fault_node_id)
        for meter_id in hypothesis.candidate.affected_meter_ids {
          add_unique(supply_subjects, meter_id)
        }
        supply_evidence.push(
          "outage hypothesis " +
          hypothesis.candidate.edge_id +
          " explains " +
          hypothesis.newly_explained_meter_ids.length().to_string() +
          " meter(s)",
        )
      }
      if report.residual_outage_meter_ids.length() > 0 {
        supply_evidence.push(
          report.residual_outage_meter_ids.length().to_string() +
          " outage meter(s) remain unexplained",
        )
      }
    }
    None => ()
  }
  for finding in phase.findings {
    add_unique(supply_subjects, finding.node_id)
    supply_evidence.push(
      "phase model reports " + finding.kind + " at " + finding.node_id,
    )
  }
  for event in power_quality.events {
    add_unique(supply_subjects, event.node_id)
    supply_evidence.push(
      "voltage model reports " + event.kind + " at " + event.node_id,
    )
  }
  let mut topology_mismatch_count = 0
  let mut telemetry_quality_count = 0
  for finding in telemetry.findings {
    if finding.kind == "topology_mismatch" {
      topology_mismatch_count += 1
      add_unique(topology_subjects, finding.node_id)
      topology_evidence.push("declared parent differs at " + finding.node_id)
    } else {
      telemetry_quality_count += 1
      add_unique(measurement_subjects, finding.node_id)
      measurement_evidence.push(finding.kind + " at " + finding.node_id)
    }
  }
  match topology {
    Some(value) => {
      if value.status != "radial" {
        add_unique(topology_subjects, "network")
        topology_evidence.push("topology classified as " + value.status)
      }
      for edge_id in value.unknown_edge_ids {
        add_unique(topology_subjects, edge_id)
        topology_evidence.push("unregistered topology object " + edge_id)
      }
      for node_id in value.isolated_node_ids {
        add_unique(topology_subjects, node_id)
        topology_evidence.push("isolated meter node " + node_id)
      }
    }
    None => ()
  }
  let causes : Array[CauseHypothesis] = []
  if supply_subjects.length() > 0 {
    let confidence = capped_confidence(
      0.35 +
      outage_count.to_double() * 0.10 +
      phase.findings.length().to_double() * 0.06 +
      power_quality.events.length().to_double() * 0.04,
    )
    causes.push({
      class: "supply_fault",
      confidence,
      subject_ids: supply_subjects,
      supporting_models: ["outage", "phase", "power_quality"],
      evidence: supply_evidence,
      recommended_action: "Dispatch electrical inspection and verify isolation and supply restoration on the affected branches.",
    })
  }
  if measurement_subjects.length() > 0 {
    let overlap = count_overlap(measurement_subjects, supply_subjects)
    let confidence = capped_confidence(
      0.32 +
      telemetry_quality_count.to_double() * 0.06 +
      overlap.to_double() * 0.10,
    )
    causes.push({
      class: "measurement_issue",
      confidence,
      subject_ids: measurement_subjects,
      supporting_models: ["telemetry"],
      evidence: measurement_evidence,
      recommended_action: "Validate the meter clock, frozen register, sensor source, and communication channel before using its measurements for repair decisions.",
    })
    if overlap > 0 {
      conflicts.push(
        overlap.to_string() +
        " supply finding(s) overlap suspected measurement faults",
      )
    }
  }
  if topology_subjects.length() > 0 {
    let no_outage_bonus = if outage_count == 0 { 0.10 } else { 0.0 }
    let confidence = capped_confidence(
      0.38 + topology_mismatch_count.to_double() * 0.10 + no_outage_bonus,
    )
    causes.push({
      class: "topology_issue",
      confidence,
      subject_ids: topology_subjects,
      supporting_models: ["topology", "telemetry"],
      evidence: topology_evidence,
      recommended_action: "Reconcile the registered topology with field switching records before relying on boundary localization.",
    })
    if outage_count > 0 {
      conflicts.push(
        "outage candidates rely on a topology with registration uncertainty",
      )
    }
  }
  let has_supply = causes.any(fn(cause) { cause.class == "supply_fault" })
  let has_measurement = causes.any(fn(cause) {
    cause.class == "measurement_issue"
  })
  let has_topology = causes.any(fn(cause) { cause.class == "topology_issue" })
  let supply_overlap = count_overlap(measurement_subjects, supply_subjects)
  let supply_model_count = outage_count +
    phase.findings.length() +
    power_quality.events.length()
  let primary_class = if has_supply && has_measurement && has_topology {
    "mixed"
  } else if has_supply && has_measurement {
    if supply_overlap > 0 && supply_model_count == 1 && outage_count == 0 {
      "measurement_issue"
    } else {
      "mixed"
    }
  } else if has_supply {
    "supply_fault"
  } else if has_topology {
    "topology_issue"
  } else if has_measurement {
    "measurement_issue"
  } else {
    "no_incident"
  }
  let mut overall_confidence = 0.0
  for cause in causes {
    if cause.confidence > overall_confidence {
      overall_confidence = cause.confidence
    }
  }
  { primary_class, overall_confidence, causes, conflicts, }
}
