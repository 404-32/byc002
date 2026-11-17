///|
pub struct DiagnosticInput {
  analysis_time : Double
  network : Network?
  outage_observations : Array[Observation]
  phase_readings : Array[PhaseReading]
  voltage_series : Array[VoltageSeries]
  telemetry_series : Array[TelemetrySeries]
  topology_links : Array[TopologyLinkObservation]
  unknown_topology_edge_ids : Array[String]
}

///|
pub struct DiagnosticReport {
  version : String
  analysis_time : Double
  topology : TopologyAssessment?
  outage : MultiFaultReport?
  phase : PhaseReport
  power_quality : PowerQualityReport
  telemetry : TelemetryReport
  arbitration : CausalArbitration
  warnings : Array[String]
  critical_count : Int32
  warning_count : Int32
}

///|
fn severity_count_findings(
  findings : Array[PhaseFinding],
  target : String,
) -> Int32 {
  let mut count = 0
  for finding in findings {
    if finding.severity == target {
      count += 1
    }
  }
  count
}

///|
fn severity_count_telemetry(
  findings : Array[TelemetryFinding],
  target : String,
) -> Int32 {
  let mut count = 0
  for finding in findings {
    if finding.severity == target {
      count += 1
    }
  }
  count
}

///|
fn severity_count_power_quality(
  events : Array[PowerQualityEvent],
  target : String,
) -> Int32 {
  let mut count = 0
  for event in events {
    if event.severity == target {
      count += 1
    }
  }
  count
}

///|
/// Run every supplied diagnostic model through one report.
pub fn run_diagnostic(input : DiagnosticInput) -> DiagnosticReport {
  let warnings : Array[String] = []
  let topology = match input.network {
    Some(network) =>
      Some(
        assess_topology(
          network,
          unknown_edge_ids=input.unknown_topology_edge_ids,
        ),
      )
    None => None
  }
  let outage = match input.network {
    Some(network) if input.outage_observations.length() > 0 => {
      let outcome = Ok(
        infer_multiple_faults(
          network,
          input.outage_observations,
          input.analysis_time,
        ),
      ) catch {
        error => Err(error)
      }
      match outcome {
        Ok(value) => Some(value)
        Err(error) => {
          warnings.push("outage diagnosis skipped: " + error.describe())
          None
        }
      }
    }
    _ => None
  }
  let phase = diagnose_phase(input.phase_readings)
  let power_quality = diagnose_power_quality(input.voltage_series)
  let telemetry = diagnose_telemetry(
    input.telemetry_series,
    input.topology_links,
    input.analysis_time,
  )
  let arbitration = arbitrate_causes(
    topology, outage, phase, power_quality, telemetry,
  )
  for warning in phase.warnings {
    warnings.push(warning)
  }
  for warning in power_quality.warnings {
    warnings.push(warning)
  }
  for warning in telemetry.warnings {
    warnings.push(warning)
  }
  let critical_count = severity_count_findings(phase.findings, "critical") +
    severity_count_telemetry(telemetry.findings, "critical") +
    severity_count_power_quality(power_quality.events, "critical")
  let warning_count = severity_count_findings(phase.findings, "warning") +
    severity_count_telemetry(telemetry.findings, "warning") +
    severity_count_power_quality(power_quality.events, "warning")
  let critical_count = match outage {
    Some(value) => critical_count + value.faults.length()
    None => critical_count
  }
  let critical_count = match topology {
    Some(value) if value.status == "disconnected" || value.status == "empty" =>
      critical_count + 1
    _ => critical_count
  }
  let warning_count = match topology {
    Some(value) if value.status == "partial" || value.status == "weakly_meshed" =>
      warning_count + 1
    _ => warning_count
  }
  {
    version: version(),
    analysis_time: input.analysis_time,
    topology,
    outage,
    phase,
    power_quality,
    telemetry,
    arbitration,
    warnings,
    critical_count,
    warning_count,
  }
}
