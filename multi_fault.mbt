///|
pub struct FaultHypothesis {
  rank : Int32
  candidate : Candidate
  newly_explained_meter_ids : Array[String]
}

///|
pub struct MultiFaultReport {
  faults : Array[FaultHypothesis]
  residual_outage_meter_ids : Array[String]
  iterations : Int32
  warnings : Array[String]
}

///|
fn contains_string(values : Array[String], target : String) -> Bool {
  for value in values {
    if value == target {
      return true
    }
  }
  false
}

///|
/// Greedy multi-fault decomposition. Each accepted hypothesis must explain at
/// least one currently unexplained outage and exceed the confidence threshold.
/// Explained observations are masked as unknown before the next iteration.
pub fn infer_multiple_faults(
  network : Network,
  observations : Array[Observation],
  analysis_time : Double,
  max_faults? : Int32,
  minimum_confidence? : Double,
) -> MultiFaultReport raise AnalysisError {
  let limit = match max_faults {
    Some(value) if value > 0 => value
    _ => 3
  }
  let threshold = match minimum_confidence {
    Some(value) if value >= 0.0 && value <= 1.0 => value
    // In a multi-fault incident, probability mass is split between independent
    // fault components. A per-component confidence around 0.35 is therefore
    // still actionable when the hypothesis explains otherwise unexplained
    // telemetry.
    _ => 0.30
  }
  let working : Array[Observation] = []
  for observation in observations {
    working.push(
      Observation::new(
        observation.node_id,
        observation.state,
        observation.confidence,
        observation.observed_at,
      ),
    )
  }
  let faults : Array[FaultHypothesis] = []
  let warnings : Array[String] = []
  let mut iterations = 0
  while iterations < limit {
    iterations += 1
    let result = infer_faults(network, working, analysis_time)
    for warning in result.warnings {
      if !warnings.contains(warning) {
        warnings.push(warning)
      }
    }
    let top = match result.top() {
      Some(value) => value
      None => break
    }
    if top.confidence < threshold {
      warnings.push(
        "stopped multi-fault search at confidence " +
        top.confidence.to_string() +
        " below threshold " +
        threshold.to_string(),
      )
      break
    }
    let explained : Array[String] = []
    for meter_id in top.affected_meter_ids {
      let mut has_unexplained_outage = false
      for observation in working {
        if observation.node_id == meter_id && observation.state is Outage {
          has_unexplained_outage = true
          break
        }
      }
      if has_unexplained_outage {
        explained.push(meter_id)
      }
    }
    if explained.length() == 0 {
      break
    }
    faults.push({
      rank: faults.length() + 1,
      candidate: top,
      newly_explained_meter_ids: explained,
    })
    // Mask every observation in the explained subtree. This prevents the same
    // fault from being selected again while leaving independent components
    // available for the next iteration.
    for index in 0..<working.length() {
      let observation = working[index]
      if contains_string(top.affected_meter_ids, observation.node_id) {
        working[index] = Observation::new(
          observation.node_id,
          Unknown,
          observation.confidence,
          observation.observed_at,
        )
      }
    }
    let mut remaining_outages = 0
    for observation in working {
      if observation.state is Outage {
        remaining_outages += 1
      }
    }
    if remaining_outages == 0 {
      break
    }
  }
  let residual : Array[String] = []
  for observation in working {
    if observation.state is Outage &&
      !contains_string(residual, observation.node_id) {
      residual.push(observation.node_id)
    }
  }
  if residual.length() > 0 && faults.length() >= limit {
    warnings.push(
      "fault limit reached with unexplained outage evidence remaining",
    )
  }
  { faults, residual_outage_meter_ids: residual, iterations, warnings, }
}
