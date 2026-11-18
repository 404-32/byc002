///|
pub struct PhaseReading {
  node_id : String
  timestamp : Double
  a_voltage : Double
  b_voltage : Double
  c_voltage : Double
  a_current : Double
  b_current : Double
  c_current : Double
}

///|
pub fn PhaseReading::new(
  node_id : String,
  timestamp : Double,
  a_voltage : Double,
  b_voltage : Double,
  c_voltage : Double,
  a_current? : Double,
  b_current? : Double,
  c_current? : Double,
) -> PhaseReading {
  let a_current = match a_current {
    Some(value) => value
    None => -1.0
  }
  let b_current = match b_current {
    Some(value) => value
    None => -1.0
  }
  let c_current = match c_current {
    Some(value) => value
    None => -1.0
  }
  {
    node_id,
    timestamp,
    a_voltage,
    b_voltage,
    c_voltage,
    a_current,
    b_current,
    c_current,
  }
}

///|
pub struct PhaseFinding {
  node_id : String
  kind : String
  severity : String
  metric : Double
  affected_phases : Array[String]
  summary : String
}

///|
pub struct PhaseReport {
  findings : Array[PhaseFinding]
  warnings : Array[String]
}

///|
fn phase_voltage(value : Double, nominal : Double) -> Bool {
  value >= 0.15 * nominal
}

///|
fn phase_unbalance(values : Array[Double]) -> Double {
  if values.length() == 0 {
    return 0.0
  }
  let mut minimum = values[0]
  let mut maximum = values[0]
  let mut sum = 0.0
  for value in values {
    if value < minimum {
      minimum = value
    }
    if value > maximum {
      maximum = value
    }
    sum += value
  }
  let mean = sum / values.length().to_double()
  if mean <= 0.0 {
    0.0
  } else {
    100.0 * (maximum - minimum) / mean
  }
}

///|
/// Diagnose phase loss, unbalance, sustained undervoltage, and overvoltage.
pub fn diagnose_phase(
  readings : Array[PhaseReading],
  nominal_voltage? : Double,
) -> PhaseReport {
  let nominal = match nominal_voltage {
    Some(value) if value > 0.0 => value
    _ => 230.0
  }
  let findings : Array[PhaseFinding] = []
  let warnings : Array[String] = []
  for reading in readings {
    let active : Array[String] = []
    let values : Array[Double] = []
    if phase_voltage(reading.a_voltage, nominal) {
      active.push("A")
      values.push(reading.a_voltage)
    }
    if phase_voltage(reading.b_voltage, nominal) {
      active.push("B")
      values.push(reading.b_voltage)
    }
    if phase_voltage(reading.c_voltage, nominal) {
      active.push("C")
      values.push(reading.c_voltage)
    }
    if active.length() < 3 {
      let missing : Array[String] = []
      if !phase_voltage(reading.a_voltage, nominal) {
        missing.push("A")
      }
      if !phase_voltage(reading.b_voltage, nominal) {
        missing.push("B")
      }
      if !phase_voltage(reading.c_voltage, nominal) {
        missing.push("C")
      }
      findings.push({
        node_id: reading.node_id,
        kind: "phase_loss",
        severity: "critical",
        metric: active.length().to_double(),
        affected_phases: missing,
        summary: "one or more phase voltages are missing",
      })
    } else {
      let unbalance = phase_unbalance(values)
      if unbalance > 10.0 {
        findings.push({
          node_id: reading.node_id,
          kind: "voltage_unbalance",
          severity: "critical",
          metric: unbalance,
          affected_phases: ["A", "B", "C"],
          summary: "three-phase voltage unbalance exceeds 10%",
        })
      } else if unbalance > 5.0 {
        findings.push({
          node_id: reading.node_id,
          kind: "voltage_unbalance",
          severity: "warning",
          metric: unbalance,
          affected_phases: ["A", "B", "C"],
          summary: "three-phase voltage unbalance exceeds 5%",
        })
      }
      let minimum = match values.get(0) {
        Some(value) => value
        None => nominal
      }
      let maximum = match values.get(0) {
        Some(value) => value
        None => nominal
      }
      let mut min_value = minimum
      let mut max_value = maximum
      for value in values {
        if value < min_value {
          min_value = value
        }
        if value > max_value {
          max_value = value
        }
      }
      if min_value < 0.9 * nominal {
        findings.push({
          node_id: reading.node_id,
          kind: "undervoltage",
          severity: "warning",
          metric: 100.0 * (1.0 - min_value / nominal),
          affected_phases: ["A", "B", "C"],
          summary: "at least one phase is below 90% nominal voltage",
        })
      }
      if max_value > 1.1 * nominal {
        findings.push({
          node_id: reading.node_id,
          kind: "overvoltage",
          severity: "warning",
          metric: 100.0 * (max_value / nominal - 1.0),
          affected_phases: ["A", "B", "C"],
          summary: "at least one phase is above 110% nominal voltage",
        })
      }
    }
  }
  if readings.length() == 0 {
    warnings.push("no phase readings were supplied")
  }
  { findings, warnings, }
}
