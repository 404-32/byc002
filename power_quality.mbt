///|
pub struct VoltagePoint {
  timestamp : Double
  voltage : Double
}

///|
pub fn VoltagePoint::new(timestamp : Double, voltage : Double) -> VoltagePoint {
  { timestamp, voltage, }
}

///|
pub struct VoltageSeries {
  node_id : String
  nominal_voltage : Double
  samples : Array[VoltagePoint]
}

///|
pub fn VoltageSeries::new(
  node_id : String,
  nominal_voltage : Double,
  samples : Array[VoltagePoint],
) -> VoltageSeries {
  { node_id, nominal_voltage, samples, }
}

///|
pub struct PowerQualityEvent {
  node_id : String
  kind : String
  severity : String
  start_time : Double
  end_time : Double
  duration_sec : Double
  extreme_voltage : Double
  deviation_percent : Double
}

///|
pub struct PowerQualityReport {
  events : Array[PowerQualityEvent]
  warnings : Array[String]
}

///|
fn sorted_voltage_points(samples : Array[VoltagePoint]) -> Array[VoltagePoint] {
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
/// Detect persistent voltage-sag and voltage-swell intervals.
pub fn diagnose_power_quality(
  series : Array[VoltageSeries],
  minimum_duration_sec? : Double,
) -> PowerQualityReport {
  let minimum_duration = match minimum_duration_sec {
    Some(value) if value > 0.0 => value
    _ => 0.02
  }
  let events : Array[PowerQualityEvent] = []
  let warnings : Array[String] = []
  for item in series {
    let points = sorted_voltage_points(item.samples)
    if points.length() < 2 {
      warnings.push(
        "node '" + item.node_id + "' has fewer than two voltage samples",
      )
      continue
    }
    let nominal = if item.nominal_voltage > 0.0 {
      item.nominal_voltage
    } else {
      230.0
    }
    let intervals : Array[Double] = []
    for index in 1..<points.length() {
      intervals.push(points[index].timestamp - points[index - 1].timestamp)
    }
    intervals.sort()
    let sample_period = intervals[intervals.length() / 2]
    let mut index = 0
    while index < points.length() {
      let point = points[index]
      let kind = if point.voltage < 0.9 * nominal {
        "voltage_sag"
      } else if point.voltage > 1.1 * nominal {
        "voltage_swell"
      } else {
        ""
      }
      if kind == "" {
        index += 1
        continue
      }
      let start = point.timestamp
      let mut end = point.timestamp
      let mut extreme = point.voltage
      let mut next = index + 1
      while next < points.length() {
        let next_point = points[next]
        let same_kind = if kind == "voltage_sag" {
          next_point.voltage < 0.9 * nominal
        } else {
          next_point.voltage > 1.1 * nominal
        }
        if !same_kind || next_point.timestamp - end > 2.5 * sample_period {
          break
        }
        end = next_point.timestamp
        if kind == "voltage_sag" && next_point.voltage < extreme {
          extreme = next_point.voltage
        }
        if kind == "voltage_swell" && next_point.voltage > extreme {
          extreme = next_point.voltage
        }
        next += 1
      }
      let duration = end - start + sample_period
      if duration + 1.0e-9 >= minimum_duration {
        let deviation = if kind == "voltage_sag" {
          100.0 * (1.0 - extreme / nominal)
        } else {
          100.0 * (extreme / nominal - 1.0)
        }
        let severity = if duration >= 1.0 || deviation >= 20.0 {
          "critical"
        } else {
          "warning"
        }
        events.push({
          node_id: item.node_id,
          kind,
          severity,
          start_time: start,
          end_time: end,
          duration_sec: duration,
          extreme_voltage: extreme,
          deviation_percent: deviation,
        })
      }
      index = next
    }
  }
  if series.length() == 0 {
    warnings.push("no voltage series were supplied")
  }
  { events, warnings, }
}
