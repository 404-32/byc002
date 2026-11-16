///|
pub struct TelemetryPoint {
  timestamp : Double
  value : Double
}

///|
pub fn TelemetryPoint::new(
  timestamp : Double,
  value : Double,
) -> TelemetryPoint {
  { timestamp, value, }
}

///|
pub struct TelemetrySeries {
  node_id : String
  samples : Array[TelemetryPoint]
}

///|
pub fn TelemetrySeries::new(
  node_id : String,
  samples : Array[TelemetryPoint],
) -> TelemetrySeries {
  { node_id, samples, }
}

///|
pub struct TopologyLinkObservation {
  node_id : String
  declared_parent_id : String
  observed_parent_id : String
}

///|
pub fn TopologyLinkObservation::new(
  node_id : String,
  declared_parent_id : String,
  observed_parent_id : String,
) -> TopologyLinkObservation {
  { node_id, declared_parent_id, observed_parent_id, }
}

///|
pub struct TelemetryFinding {
  node_id : String
  kind : String
  severity : String
  summary : String
  metric : Double
}

///|
pub struct TelemetryReport {
  findings : Array[TelemetryFinding]
  warnings : Array[String]
}

///|
fn sorted_telemetry_points(
  samples : Array[TelemetryPoint],
) -> Array[TelemetryPoint] {
  let points = samples.copy()
  points.sort_by(fn(left, right) {
    if left.timestamp < right.timestamp {
      -1
    } else if left.timestamp > right.timestamp {
      1
    } else {
      0
    }
  })
  points
}

///|
/// Diagnose stale series, delayed timestamps, duplicate samples, frozen values,
/// and declared-vs-observed topology mismatches.
pub fn diagnose_telemetry(
  series : Array[TelemetrySeries],
  links : Array[TopologyLinkObservation],
  analysis_time : Double,
  stale_after_sec? : Double,
  stuck_window_sec? : Double,
  constant_tolerance? : Double,
) -> TelemetryReport {
  let stale_after = match stale_after_sec {
    Some(value) if value > 0.0 => value
    _ => 300.0
  }
  let stuck_window = match stuck_window_sec {
    Some(value) if value > 0.0 => value
    _ => 60.0
  }
  let tolerance = match constant_tolerance {
    Some(value) if value >= 0.0 => value
    _ => 1.0e-9
  }
  let findings : Array[TelemetryFinding] = []
  let warnings : Array[String] = []
  for item in series {
    if item.samples.length() == 0 {
      findings.push({
        node_id: item.node_id,
        kind: "missing_series",
        severity: "warning",
        summary: "no telemetry samples are available",
        metric: 0.0,
      })
      continue
    }
    let mut clock_issues = 0
    for index in 1..<item.samples.length() {
      if item.samples[index].timestamp <= item.samples[index - 1].timestamp {
        clock_issues += 1
      }
    }
    if clock_issues > 0 {
      findings.push({
        node_id: item.node_id,
        kind: "clock_anomaly",
        severity: "warning",
        summary: "timestamps are duplicated or not strictly increasing",
        metric: clock_issues.to_double(),
      })
    }
    let points = sorted_telemetry_points(item.samples)
    let latest = points[points.length() - 1]
    let age = analysis_time - latest.timestamp
    if age > stale_after {
      findings.push({
        node_id: item.node_id,
        kind: "stale_series",
        severity: if age > 2.0 * stale_after {
          "critical"
        } else {
          "warning"
        },
        summary: "latest telemetry sample is older than the stale threshold",
        metric: age,
      })
    }
    let mut run_start = points[0].timestamp
    let mut run_end = points[0].timestamp
    let mut run_value = points[0].value
    let mut stuck_found = false
    for index in 1..<points.length() {
      let point = points[index]
      if (point.value - run_value).abs() <= tolerance {
        run_end = point.timestamp
        if run_end - run_start >= stuck_window {
          stuck_found = true
        }
      } else {
        run_start = point.timestamp
        run_end = point.timestamp
        run_value = point.value
      }
    }
    if stuck_found {
      findings.push({
        node_id: item.node_id,
        kind: "stuck_series",
        severity: "warning",
        summary: "telemetry value remains constant beyond the stuck threshold",
        metric: run_end - run_start,
      })
    }
  }
  for link in links {
    if link.declared_parent_id != link.observed_parent_id {
      findings.push({
        node_id: link.node_id,
        kind: "topology_mismatch",
        severity: "critical",
        summary: "observed upstream relation differs from the registered topology",
        metric: 1.0,
      })
    }
  }
  if series.length() == 0 && links.length() == 0 {
    warnings.push("no telemetry or topology-relation evidence was supplied")
  }
  { findings, warnings, }
}
