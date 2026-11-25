///|
pub struct CauseHypothesis {
  class : String
  raw_score : Double
  mut confidence : Double
  subject_ids : Array[String]
  supporting_models : Array[String]
  evidence : Array[String]
  recommended_action : String
}

///|
pub struct EvidenceContribution {
  cause_class : String
  feature : String
  weight : Double
  detail : String
}

///|
type PhaseReadingList = Array[PhaseReading]

///|
type VoltageSeriesList = Array[VoltageSeries]

///|
pub struct CausalArbitration {
  primary_class : String
  overall_confidence : Double
  decision_margin : Double
  causes : Array[CauseHypothesis]
  contributions : Array[EvidenceContribution]
  conflicts : Array[String]
  independent_evidence_sources : Array[String]
  undetermined_reasons : Array[String]
}

///|
fn add_unique(values : Array[String], value : String) -> Unit {
  if !values.contains(value) {
    values.push(value)
  }
  ()
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
fn capped_weight(value : Double, maximum : Double) -> Double {
  if value < 0.0 {
    0.0
  } else if value > maximum {
    maximum
  } else {
    value
  }
}

///|
fn add_contribution(
  contributions : Array[EvidenceContribution],
  cause_class : String,
  feature : String,
  weight : Double,
  detail : String,
) -> Unit {
  contributions.push({ cause_class, feature, weight, detail, })
}

///|
fn sum_contributions(
  contributions : Array[EvidenceContribution],
  cause_class : String,
) -> Double {
  let mut value = 0.0
  for contribution in contributions {
    if contribution.cause_class == cause_class {
      value += contribution.weight
    }
  }
  value
}

///|
fn latest_phase_reading(
  readings : Array[PhaseReading],
  node_id : String,
) -> PhaseReading? {
  let mut found : PhaseReading? = None
  for reading in readings {
    if reading.node_id == node_id {
      found = match found {
        Some(previous) if previous.timestamp > reading.timestamp =>
          Some(previous)
        _ => Some(reading)
      }
    }
  }
  found
}

///|
fn current_for_phase(reading : PhaseReading, phase : String) -> Double {
  match phase {
    "A" => reading.a_current
    "B" => reading.b_current
    "C" => reading.c_current
    _ => -1.0
  }
}

///|
fn phase_current_verdict(
  reading : PhaseReading,
  affected_phases : Array[String],
) -> Int32 {
  let mut active_sum = 0.0
  let mut active_count = 0
  for phase in ["A", "B", "C"] {
    if !affected_phases.contains(phase) {
      let current = current_for_phase(reading, phase)
      if current >= 0.0 {
        active_sum += current
        active_count += 1
      }
    }
  }
  if active_count == 0 {
    return 0
  }
  let active_mean = active_sum / active_count.to_double()
  let mut has_missing_current = false
  let mut supports = true
  for phase in affected_phases {
    let current = current_for_phase(reading, phase)
    if current >= 0.0 {
      has_missing_current = true
      if current > 0.15 * active_mean {
        supports = false
      }
    }
  }
  if !has_missing_current {
    0
  } else if supports {
    1
  } else {
    -1
  }
}

///|
fn latest_voltage(series : VoltageSeries) -> Double? {
  let mut latest_timestamp = -1.0
  let mut latest_value : Double? = None
  for point in series.samples {
    if point.timestamp > latest_timestamp {
      latest_timestamp = point.timestamp
      latest_value = Some(point.voltage)
    }
  }
  latest_value
}

///|
/// Reconcile diagnostic findings by scoring three competing physical
/// hypotheses. Evidence compatibility and object overlap determine the score;
/// no single detector can assign the final primary cause by itself.
pub fn arbitrate_causes(
  topology : TopologyAssessment?,
  outage : MultiFaultReport?,
  phase : PhaseReport,
  power_quality : PowerQualityReport,
  telemetry : TelemetryReport,
  phase_readings : PhaseReadingList,
  voltage_series? : VoltageSeriesList,
) -> CausalArbitration {
  let supply_subjects : Array[String] = []
  let measurement_subjects : Array[String] = []
  let topology_subjects : Array[String] = []
  let model_subjects : Array[String] = []
  let supply_evidence : Array[String] = []
  let measurement_evidence : Array[String] = []
  let topology_evidence : Array[String] = []
  let model_evidence : Array[String] = []
  let contributions : Array[EvidenceContribution] = []
  let conflicts : Array[String] = []
  let independent_evidence_sources : Array[String] = []
  let undetermined_reasons : Array[String] = []
  let readings = phase_readings
  let voltage_inputs = match voltage_series {
    Some(value) => value
    None => []
  }
  let mut outage_count = 0
  let mut outage_confidence_sum = 0.0
  match outage {
    Some(report) => {
      outage_count = report.faults.length()
      for hypothesis in report.faults {
        outage_confidence_sum += hypothesis.candidate.confidence
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
        add_contribution(
          contributions, "supply_fault", "residual_outage", -0.7, "some outage evidence is not explained by accepted hypotheses",
        )
        add_contribution(
          contributions, "topology_issue", "residual_outage", 0.6, "unexplained outage can indicate a model or topology mismatch",
        )
      }
    }
    None => ()
  }
  let mut phase_loss_count = 0
  let phase_loss_subjects : Array[String] = []
  for finding in phase.findings {
    add_unique(supply_subjects, finding.node_id)
    supply_evidence.push(
      "phase model reports " + finding.kind + " at " + finding.node_id,
    )
    if finding.kind == "phase_loss" {
      phase_loss_count += 1
      add_unique(phase_loss_subjects, finding.node_id)
    }
  }
  for event in power_quality.events {
    add_unique(supply_subjects, event.node_id)
    supply_evidence.push(
      "voltage model reports " + event.kind + " at " + event.node_id,
    )
  }
  let mut topology_mismatch_count = 0
  let mut telemetry_quality_count = 0
  let mut telemetry_severe_count = 0
  let mut constant_series_count = 0
  for finding in telemetry.findings {
    if finding.kind == "topology_mismatch" {
      topology_mismatch_count += 1
      add_unique(topology_subjects, finding.node_id)
      topology_evidence.push("declared parent differs at " + finding.node_id)
    } else {
      telemetry_quality_count += 1
      if finding.kind == "constant_series" {
        constant_series_count += 1
      }
      if finding.severity == "critical" {
        telemetry_severe_count += 1
      }
      add_unique(measurement_subjects, finding.node_id)
      measurement_evidence.push(finding.kind + " at " + finding.node_id)
    }
  }
  let mut topology_uncertain = false
  let mut isolated_or_unknown_count = 0
  match topology {
    Some(value) => {
      if value.status != "radial" {
        topology_uncertain = true
        if value.status == "weakly_meshed" ||
          value.status == "disconnected" ||
          value.status == "empty" {
          add_unique(model_subjects, "network")
          model_evidence.push(
            "outage diagnostic requires a rooted tree; topology=" + value.status,
          )
          add_contribution(
            contributions,
            "model_inapplicable",
            "topology_model",
            if value.status == "disconnected" {
              1.3
            } else {
              0.9
            },
            "outage boundary model is not applicable to this topology",
          )
        }
      }
      for edge_id in value.unknown_edge_ids {
        isolated_or_unknown_count += 1
        add_unique(topology_subjects, edge_id)
        topology_evidence.push("unregistered topology object " + edge_id)
      }
      for node_id in value.isolated_node_ids {
        isolated_or_unknown_count += 1
        add_unique(topology_subjects, node_id)
        topology_evidence.push("isolated meter node " + node_id)
      }
    }
    None => ()
  }

  let mut current_support_count = 0
  let mut current_conflict_count = 0
  for finding in phase.findings {
    if finding.kind == "phase_loss" {
      match latest_phase_reading(readings, finding.node_id) {
        Some(reading) => {
          let verdict = phase_current_verdict(reading, finding.affected_phases)
          if verdict > 0 {
            current_support_count += 1
            add_unique(
              independent_evidence_sources, "phase_current_consistency",
            )
            add_contribution(
              contributions, "supply_fault", "phase_current_consistency", 1.1, "missing-phase voltage agrees with near-zero phase current",
            )
          } else if verdict < 0 {
            current_conflict_count += 1
            add_unique(
              independent_evidence_sources, "phase_current_contradiction",
            )
            add_contribution(
              contributions, "measurement_issue", "phase_current_contradiction",
              1.2, "zero reported voltage conflicts with live phase current",
            )
            add_contribution(
              contributions, "supply_fault", "phase_current_contradiction", -0.6,
              "supply hypothesis is contradicted by live phase current",
            )
            conflicts.push(
              "phase voltage and phase current disagree at " + finding.node_id,
            )
          }
        }
        None => ()
      }
    }
  }
  let phase_corroborated = phase_loss_subjects.length() >= 2
  if phase_corroborated {
    add_unique(independent_evidence_sources, "multi_sensor_phase_loss")
    add_contribution(
      contributions, "supply_fault", "multi_sensor_phase_loss", 1.0, "independent sensors report phase loss",
    )
  }
  if outage_count > 0 {
    add_unique(independent_evidence_sources, "independent_outage_state")
  }
  if telemetry_quality_count > 0 {
    add_unique(independent_evidence_sources, "telemetry_temporal_health")
  }
  if topology_mismatch_count > 0 {
    add_unique(independent_evidence_sources, "observed_parent_relation")
  }
  let ambiguous_phase = phase_loss_count > 0 &&
    current_support_count == 0 &&
    current_conflict_count == 0 &&
    phase_loss_subjects.length() < 2 &&
    outage_count == 0
  if ambiguous_phase {
    undetermined_reasons.push(
      "single missing-phase reading has no independent voltage, current, or outage corroboration",
    )
  }

  let sustained_voltage_nodes : Array[String] = []
  let low_voltage_sources : Array[String] = []
  let mut variable_voltage_count = 0
  for event in power_quality.events {
    if event.duration_sec >= 1.0 {
      add_unique(sustained_voltage_nodes, event.node_id)
      add_unique(low_voltage_sources, event.node_id + "@" + event.source_id)
      if event.variation_percent >= 0.05 {
        variable_voltage_count += 1
      }
    }
  }
  let mut corroborated_voltage = false
  let mut contradicted_voltage = false
  if low_voltage_sources.length() >= 2 {
    corroborated_voltage = true
  }
  for node_id in sustained_voltage_nodes {
    let mut low_sources = 0
    let mut normal_references = 0
    for source_key in low_voltage_sources {
      let prefix = node_id + "@"
      if source_key.has_prefix(prefix) {
        low_sources += 1
      }
    }
    for item in voltage_inputs {
      if item.node_id == node_id {
        let key = item.node_id + "@" + item.source_id
        if !low_voltage_sources.contains(key) {
          match latest_voltage(item) {
            Some(value) if value >= 0.9 * item.nominal_voltage =>
              normal_references += 1
            _ => ()
          }
        }
      }
    }
    if low_sources >= 2 {
      corroborated_voltage = true
    }
    if low_sources >= 1 && normal_references >= 1 {
      contradicted_voltage = true
    }
  }
  let ambiguous_voltage = sustained_voltage_nodes.length() > 0 &&
    !corroborated_voltage &&
    !contradicted_voltage &&
    outage_count == 0
  if corroborated_voltage {
    add_unique(independent_evidence_sources, "redundant_voltage_consensus")
    add_contribution(
      contributions, "supply_fault", "redundant_voltage_consensus", 1.2, "independent voltage sources agree on a sustained excursion",
    )
  }
  let supply_has_independent_evidence = outage_count > 0 ||
    current_support_count > 0 ||
    phase_corroborated ||
    corroborated_voltage
  if supply_subjects.length() > 0 && !supply_has_independent_evidence {
    undetermined_reasons.push(
      "supply indication has no independent voltage, phase-current, or outage confirmation",
    )
  }
  if contradicted_voltage {
    add_unique(independent_evidence_sources, "redundant_voltage_conflict")
    add_contribution(
      contributions, "measurement_issue", "redundant_voltage_conflict", 1.4, "one source reports low voltage while an independent source is normal",
    )
    add_contribution(
      contributions, "supply_fault", "redundant_voltage_conflict", -0.8, "independent healthy source contradicts the supply excursion",
    )
    conflicts.push("independent voltage sources disagree on sustained voltage")
  }
  if variable_voltage_count > 0 {
    add_unique(independent_evidence_sources, "voltage_trajectory_variation")
    add_contribution(
      contributions, "supply_fault", "voltage_trajectory_variation", 0.5, "sustained voltage changes over time instead of being bit-identical",
    )
  }
  if ambiguous_voltage {
    undetermined_reasons.push(
      "single flat sustained voltage has no spatial, temporal-variation, outage, or telemetry-health corroboration",
    )
  }

  if outage_count > 0 {
    add_contribution(
      contributions,
      "supply_fault",
      "outage_hypotheses",
      1.8 + capped_weight(outage_count.to_double() * 0.2, 0.6),
      outage_count.to_string() +
      " outage hypothesis(es) explain observed clients",
    )
    add_contribution(
      contributions,
      "supply_fault",
      "outage_stage_confidence",
      capped_weight(outage_confidence_sum, 0.8),
      "accepted stages have aggregate stage confidence",
    )
  }
  if phase.findings.length() > 0 {
    add_contribution(
      contributions,
      "supply_fault",
      "phase_findings",
      0.9 + capped_weight(phase.findings.length().to_double() * 0.12, 0.4),
      phase.findings.length().to_string() + " phase finding(s)",
    )
  }
  if phase_loss_count > 0 {
    add_contribution(
      contributions,
      "supply_fault",
      "phase_loss",
      0.5 * phase_loss_count.to_double(),
      "missing phase voltage is direct supply-side evidence",
    )
  }
  if power_quality.events.length() > 0 {
    add_contribution(
      contributions,
      "supply_fault",
      "voltage_events",
      0.5 + capped_weight(power_quality.events.length().to_double() * 0.12, 0.4),
      power_quality.events.length().to_string() + " voltage event(s)",
    )
  }
  if supply_subjects.length() >= 3 {
    add_contribution(
      contributions, "supply_fault", "spatial_support", 0.4, "supply evidence spans multiple affected objects",
    )
  }
  if telemetry_quality_count > 0 {
    add_contribution(
      contributions,
      "measurement_issue",
      "integrity_findings",
      1.5 + capped_weight(telemetry_quality_count.to_double() * 0.2, 0.6),
      telemetry_quality_count.to_string() + " telemetry-quality finding(s)",
    )
  }
  if telemetry_severe_count > 0 {
    add_contribution(
      contributions,
      "measurement_issue",
      "severe_integrity",
      0.4 * telemetry_severe_count.to_double(),
      "critical telemetry-integrity findings require validation",
    )
  }
  let measurement_overlap = count_overlap(measurement_subjects, supply_subjects)
  if measurement_overlap > 0 {
    add_contribution(
      contributions,
      "measurement_issue",
      "supply_overlap",
      0.6 * measurement_overlap.to_double(),
      "supply readings share a subject with suspect telemetry",
    )
    add_contribution(
      contributions,
      "supply_fault",
      "measurement_overlap",
      -0.5 * measurement_overlap.to_double(),
      "supply evidence depends on suspect telemetry",
    )
    conflicts.push(
      measurement_overlap.to_string() +
      " supply finding(s) overlap suspected measurement faults",
    )
  }
  if topology_mismatch_count > 0 {
    add_contribution(
      contributions,
      "topology_issue",
      "parent_mismatch",
      1.4 + capped_weight(topology_mismatch_count.to_double() * 0.2, 0.6),
      topology_mismatch_count.to_string() +
      " declared/observed parent mismatch(es)",
    )
  }
  if isolated_or_unknown_count > 0 {
    add_contribution(
      contributions,
      "topology_issue",
      "unknown_relationships",
      0.4 * isolated_or_unknown_count.to_double(),
      "unregistered or isolated topology objects are present",
    )
  }
  if outage_count > 0 && topology_uncertain {
    add_contribution(
      contributions, "topology_issue", "outage_under_uncertainty", 0.6, "outage candidates depend on an uncertain topology",
    )
    conflicts.push(
      "outage candidates rely on a topology with registration uncertainty",
    )
  }

  let causes : Array[CauseHypothesis] = []
  if supply_subjects.length() > 0 && supply_has_independent_evidence {
    causes.push({
      class: "supply_fault",
      raw_score: sum_contributions(contributions, "supply_fault"),
      confidence: 0.0,
      subject_ids: supply_subjects,
      supporting_models: ["outage", "phase", "power_quality"],
      evidence: supply_evidence,
      recommended_action: "Dispatch electrical inspection and verify isolation and supply restoration on the affected branches.",
    })
  }
  let measurement_has_independent_evidence = current_conflict_count > 0 ||
    contradicted_voltage ||
    telemetry_quality_count > constant_series_count
  if measurement_subjects.length() > 0 && measurement_has_independent_evidence {
    causes.push({
      class: "measurement_issue",
      raw_score: sum_contributions(contributions, "measurement_issue"),
      confidence: 0.0,
      subject_ids: measurement_subjects,
      supporting_models: ["telemetry"],
      evidence: measurement_evidence,
      recommended_action: "Validate the meter clock, frozen register, sensor source, and communication channel before using its measurements for repair decisions.",
    })
  }
  if topology_subjects.length() > 0 {
    causes.push({
      class: "topology_issue",
      raw_score: sum_contributions(contributions, "topology_issue"),
      confidence: 0.0,
      subject_ids: topology_subjects,
      supporting_models: ["topology", "telemetry"],
      evidence: topology_evidence,
      recommended_action: "Reconcile the registered topology with field switching records before relying on boundary localization.",
    })
  }
  if model_subjects.length() > 0 {
    causes.push({
      class: "model_inapplicable",
      raw_score: sum_contributions(contributions, "model_inapplicable"),
      confidence: 0.0,
      subject_ids: model_subjects,
      supporting_models: ["topology"],
      evidence: model_evidence,
      recommended_action: "Do not force the radial outage model; select a meshed/partial-topology model or correct the topological representation.",
    })
  }
  causes.sort_by(fn(left, right) {
    if left.raw_score > right.raw_score {
      -1
    } else if left.raw_score < right.raw_score {
      1
    } else {
      left.class.compare(right.class)
    }
  })
  let mut max_score = 0.0
  if causes.length() > 0 {
    max_score = causes[0].raw_score
  }
  let mut normalizer = 0.0
  for cause in causes {
    normalizer += @math.exp(cause.raw_score - max_score)
  }
  for cause in causes {
    cause.confidence = if normalizer > 0.0 {
      @math.exp(cause.raw_score - max_score) / normalizer
    } else {
      0.0
    }
  }
  let mut primary_class = "no_incident"
  let mut overall_confidence = 1.0
  let mut decision_margin = 1.0
  if causes.length() > 0 {
    primary_class = causes[0].class
    overall_confidence = causes[0].confidence
    if causes.length() > 1 {
      decision_margin = causes[0].confidence - causes[1].confidence
    } else {
      decision_margin = causes[0].confidence
    }
    let high_support = causes
      .filter(fn(cause) { cause.confidence >= 0.15 })
      .length()
    if high_support >= 2 && causes[0].confidence < 0.68 {
      primary_class = "mixed"
    }
    if primary_class == "mixed" {
      overall_confidence = 1.0 - decision_margin
    }
  }
  if ambiguous_phase || ambiguous_voltage {
    primary_class = "undetermined"
    overall_confidence = 0.5
    decision_margin = 0.0
  }
  {
    primary_class,
    overall_confidence,
    decision_margin,
    causes,
    contributions,
    conflicts,
    independent_evidence_sources,
    undetermined_reasons,
  }
}
