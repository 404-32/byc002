///|
fn optional_array(
  object : Map[String, Json],
  key : String,
) -> Array[Json] raise AnalysisError {
  match object.get(key) {
    None | Some(Null) => []
    Some(value) => array_of(value)
  }
}

///|
fn parse_voltage_point(value : Json) -> VoltagePoint raise AnalysisError {
  let object = object_of(value)
  VoltagePoint::new(
    required_number(object, "timestamp"),
    required_number(object, "voltage"),
  )
}

///|
fn parse_voltage_series(value : Json) -> VoltageSeries raise AnalysisError {
  let object = object_of(value)
  let samples : Array[VoltagePoint] = []
  for sample in optional_array(object, "samples") {
    samples.push(parse_voltage_point(sample))
  }
  VoltageSeries::new(
    required_string(object, "node_id"),
    optional_number(object, "nominal_voltage", 230.0),
    samples,
  )
}

///|
fn parse_telemetry_point(value : Json) -> TelemetryPoint raise AnalysisError {
  let object = object_of(value)
  TelemetryPoint::new(
    required_number(object, "timestamp"),
    required_number(object, "value"),
  )
}

///|
fn parse_telemetry_series(value : Json) -> TelemetrySeries raise AnalysisError {
  let object = object_of(value)
  let samples : Array[TelemetryPoint] = []
  for sample in optional_array(object, "samples") {
    samples.push(parse_telemetry_point(sample))
  }
  TelemetrySeries::new(required_string(object, "node_id"), samples)
}

///|
fn parse_phase_reading(value : Json) -> PhaseReading raise AnalysisError {
  let object = object_of(value)
  PhaseReading::new(
    required_string(object, "node_id"),
    required_number(object, "timestamp"),
    required_number(object, "a_voltage"),
    required_number(object, "b_voltage"),
    required_number(object, "c_voltage"),
  )
}

///|
fn parse_topology_link(
  value : Json,
) -> TopologyLinkObservation raise AnalysisError {
  let object = object_of(value)
  TopologyLinkObservation::new(
    required_string(object, "node_id"),
    required_string(object, "declared_parent"),
    required_string(object, "observed_parent"),
  )
}

///|
fn parse_diagnostic_document(
  source : String,
) -> DiagnosticInput raise AnalysisError {
  let json = @json.parse(source) catch {
    error => raise AnalysisError::Parse(error.to_string())
  }
  let object = object_of(json)
  let analysis_time = required_number(object, "analysis_time")
  let network = match object.get("network") {
    None | Some(Null) => None
    Some(value) => Some(parse_network(value))
  }
  let observations : Array[Observation] = []
  for value in optional_array(object, "observations") {
    observations.push(parse_observation(value, analysis_time))
  }
  let phase_readings : Array[PhaseReading] = []
  for value in optional_array(object, "phase_readings") {
    phase_readings.push(parse_phase_reading(value))
  }
  let voltage_series : Array[VoltageSeries] = []
  for value in optional_array(object, "voltage_series") {
    voltage_series.push(parse_voltage_series(value))
  }
  let telemetry_series : Array[TelemetrySeries] = []
  for value in optional_array(object, "telemetry_series") {
    telemetry_series.push(parse_telemetry_series(value))
  }
  let topology_links : Array[TopologyLinkObservation] = []
  for value in optional_array(object, "topology_links") {
    topology_links.push(parse_topology_link(value))
  }
  let unknown_edges : Array[String] = []
  for value in optional_array(object, "unknown_topology_edge_ids") {
    unknown_edges.push(string_of(value))
  }
  {
    analysis_time,
    network,
    outage_observations: observations,
    phase_readings,
    voltage_series,
    telemetry_series,
    topology_links,
    unknown_topology_edge_ids: unknown_edges,
  }
}

///|
pub fn parse_diagnostic_input(
  source : String,
) -> DiagnosticInput raise AnalysisError {
  parse_diagnostic_document(source)
}

///|
fn phase_finding_json(finding : PhaseFinding) -> Json {
  Json::object(
    Map([
      ("node_id", Json::string(finding.node_id)),
      ("kind", Json::string(finding.kind)),
      ("severity", Json::string(finding.severity)),
      ("metric", Json::number(finding.metric)),
      ("affected_phases", strings_json(finding.affected_phases)),
      ("summary", Json::string(finding.summary)),
    ]),
  )
}

///|
fn power_quality_event_json(event : PowerQualityEvent) -> Json {
  Json::object(
    Map([
      ("node_id", Json::string(event.node_id)),
      ("kind", Json::string(event.kind)),
      ("severity", Json::string(event.severity)),
      ("start_time", Json::number(event.start_time)),
      ("end_time", Json::number(event.end_time)),
      ("duration_sec", Json::number(event.duration_sec)),
      ("extreme_voltage", Json::number(event.extreme_voltage)),
      ("deviation_percent", Json::number(event.deviation_percent)),
    ]),
  )
}

///|
fn telemetry_finding_json(finding : TelemetryFinding) -> Json {
  Json::object(
    Map([
      ("node_id", Json::string(finding.node_id)),
      ("kind", Json::string(finding.kind)),
      ("severity", Json::string(finding.severity)),
      ("summary", Json::string(finding.summary)),
      ("metric", Json::number(finding.metric)),
    ]),
  )
}

///|
fn cause_hypothesis_json(cause : CauseHypothesis) -> Json {
  Json::object(
    Map([
      ("class", Json::string(cause.class)),
      ("raw_score", Json::number(cause.raw_score)),
      ("confidence", Json::number(cause.confidence)),
      ("subject_ids", strings_json(cause.subject_ids)),
      ("supporting_models", strings_json(cause.supporting_models)),
      ("evidence", strings_json(cause.evidence)),
      ("recommended_action", Json::string(cause.recommended_action)),
    ]),
  )
}

///|
fn evidence_contribution_json(contribution : EvidenceContribution) -> Json {
  Json::object(
    Map([
      ("cause_class", Json::string(contribution.cause_class)),
      ("feature", Json::string(contribution.feature)),
      ("weight", Json::number(contribution.weight)),
      ("detail", Json::string(contribution.detail)),
    ]),
  )
}

///|
fn arbitration_json(arbitration : CausalArbitration) -> Json {
  Json::object(
    Map([
      ("primary_class", Json::string(arbitration.primary_class)),
      ("overall_confidence", Json::number(arbitration.overall_confidence)),
      ("decision_margin", Json::number(arbitration.decision_margin)),
      ("causes", Json::array(arbitration.causes.map(cause_hypothesis_json))),
      (
        "contributions",
        Json::array(arbitration.contributions.map(evidence_contribution_json)),
      ),
      ("conflicts", strings_json(arbitration.conflicts)),
    ]),
  )
}

///|
fn topology_json(topology : TopologyAssessment) -> Json {
  Json::object(
    Map([
      ("status", Json::string(topology.status)),
      ("node_count", Json::number(topology.node_count.to_double())),
      ("edge_count", Json::number(topology.edge_count.to_double())),
      (
        "connected_components",
        Json::number(topology.connected_components.to_double()),
      ),
      ("cycle_rank", Json::number(topology.cycle_rank.to_double())),
      ("unknown_edge_ids", strings_json(topology.unknown_edge_ids)),
      ("isolated_node_ids", strings_json(topology.isolated_node_ids)),
      ("warnings", strings_json(topology.warnings)),
    ]),
  )
}

///|
fn fault_hypothesis_json(hypothesis : FaultHypothesis) -> Json {
  Json::object(
    Map([
      ("rank", Json::number(hypothesis.rank.to_double())),
      ("candidate", candidate_json(hypothesis.candidate)),
      (
        "newly_explained_meter_ids",
        strings_json(hypothesis.newly_explained_meter_ids),
      ),
    ]),
  )
}

///|
fn multi_fault_json(report : MultiFaultReport) -> Json {
  Json::object(
    Map([
      ("faults", Json::array(report.faults.map(fault_hypothesis_json))),
      (
        "residual_outage_meter_ids",
        strings_json(report.residual_outage_meter_ids),
      ),
      ("iterations", Json::number(report.iterations.to_double())),
      ("warnings", strings_json(report.warnings)),
    ]),
  )
}

///|
pub fn diagnostic_to_json(report : DiagnosticReport) -> Json {
  let object : Map[String, Json] = Map([
    ("version", Json::string(report.version)),
    ("analysis_time", Json::number(report.analysis_time)),
    ("critical_count", Json::number(report.critical_count.to_double())),
    ("warning_count", Json::number(report.warning_count.to_double())),
    ("warnings", strings_json(report.warnings)),
    (
      "phase",
      Json::object(
        Map([
          (
            "findings",
            Json::array(report.phase.findings.map(phase_finding_json)),
          ),
          ("warnings", strings_json(report.phase.warnings)),
        ]),
      ),
    ),
    (
      "power_quality",
      Json::object(
        Map([
          (
            "events",
            Json::array(
              report.power_quality.events.map(power_quality_event_json),
            ),
          ),
          ("warnings", strings_json(report.power_quality.warnings)),
        ]),
      ),
    ),
    (
      "telemetry",
      Json::object(
        Map([
          (
            "findings",
            Json::array(report.telemetry.findings.map(telemetry_finding_json)),
          ),
          ("warnings", strings_json(report.telemetry.warnings)),
        ]),
      ),
    ),
    ("arbitration", arbitration_json(report.arbitration)),
  ])
  match report.topology {
    Some(value) => object.set("topology", topology_json(value))
    None => ()
  }
  match report.outage {
    Some(value) => object.set("outage", multi_fault_json(value))
    None => ()
  }
  Json::object(object)
}

///|
pub fn diagnostic_json_string(report : DiagnosticReport) -> String {
  diagnostic_to_json(report).stringify(indent=2)
}
