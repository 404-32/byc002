///|
priv struct CandidatePlan {
  edge_id : String
  fault_node_id : String
  section : String
  mask : Array[Bool]
  affected_meters : Array[String]
}

///|
fn latest_observations(
  network : Network,
  observations : Array[Observation],
  analysis_time : Double,
) -> (Array[Observation], Array[String]) {
  let latest : Map[String, Observation] = Map([])
  let warnings : Array[String] = []
  for observation in observations {
    match network.find_node(observation.node_id) {
      Some(_) => {
        let normalized = observation
        if normalized.confidence < 0.0 || normalized.confidence > 1.0 {
          warnings.push(
            "confidence for '" + normalized.node_id + "' was clamped to [0, 1]",
          )
          normalized.confidence = if normalized.confidence < 0.0 {
            0.0
          } else if normalized.confidence > 1.0 {
            1.0
          } else {
            normalized.confidence
          }
        }
        if normalized.observed_at > analysis_time {
          warnings.push(
            "future timestamp for '" +
            normalized.node_id +
            "' was clamped to analysis time",
          )
          normalized.observed_at = analysis_time
        }
        match latest.get(normalized.node_id) {
          Some(previous) if previous.observed_at > normalized.observed_at => ()
          _ => latest.set(normalized.node_id, normalized)
        }
      }
      None =>
        warnings.push(
          "observation for unknown node '" +
          observation.node_id +
          "' was ignored",
        )
    }
  }
  (latest.values().to_array(), warnings)
}

///|
fn observation_weight(
  observation : Observation,
  analysis_time : Double,
  half_life_sec : Double,
) -> Double {
  let age = analysis_time - observation.observed_at
  if age <= 0.0 || half_life_sec <= 0.0 {
    observation.confidence
  } else {
    observation.confidence * @math.pow(0.5, age / half_life_sec)
  }
}

///|
fn make_plans(network : Network, tree : Tree) -> Array[CandidatePlan] {
  let plans : Array[CandidatePlan] = []
  // A source-level outage explains loss of the complete feeder.
  let source_mask : Array[Bool] = Array::make(network.nodes.length(), true)
  plans.push({
    edge_id: "SOURCE",
    fault_node_id: network.root_id,
    section: "Transformer / feeder",
    mask: source_mask,
    affected_meters: all_meter_ids(network),
  })
  for node in tree.order {
    if node == tree.root {
      continue
    }
    let edge_index = tree.parent_edge[node]
    if edge_index < 0 {
      continue
    }
    let edge = network.edges[edge_index]
    plans.push({
      edge_id: edge.id,
      fault_node_id: network.nodes[node].id,
      section: edge.section,
      mask: downstream_mask(tree, node),
      affected_meters: downstream_meter_ids(network, tree, node),
    })
  }
  plans
}

///|
fn score_plan(
  plan : CandidatePlan,
  network : Network,
  observations : Array[Observation],
  analysis_time : Double,
  policy : InferencePolicy,
) -> Candidate {
  let supporting : Array[String] = []
  let contradicting : Array[String] = []
  let blind : Array[String] = []
  let mut raw_score = 0.0
  for observation in observations {
    let node_index = match network.find_node(observation.node_id) {
      Some(index) => index
      None => continue
    }
    let predicted_outage = plan.mask[node_index]
    let weight = observation_weight(
      observation,
      analysis_time,
      policy.half_life_sec,
    )
    match observation.state {
      Unknown => blind.push(observation.node_id)
      Outage if predicted_outage => {
        raw_score += weight
        supporting.push(observation.node_id)
      }
      Outage => {
        raw_score -= policy.outage_penalty * weight
        contradicting.push(observation.node_id)
      }
      Energized if predicted_outage => {
        raw_score -= policy.powered_penalty * weight
        contradicting.push(observation.node_id)
      }
      Energized => {
        raw_score += weight
        supporting.push(observation.node_id)
      }
    }
  }
  // The weak structural prior breaks ties toward the smallest faulted section
  // without overwhelming direct meter evidence.
  let prior = policy.structural_prior *
    @math.ln(1.0 + plan.affected_meters.length().to_double())
  raw_score -= prior
  if plan.edge_id == "SOURCE" {
    // A transformer/feeder-source outage requires explicit root evidence.
    // Without it, prefer the first downstream cable, which has the same meter
    // footprint and is the locally testable fault boundary.
    raw_score -= 0.35
  }
  {
    edge_id: plan.edge_id,
    fault_node_id: plan.fault_node_id,
    section: plan.section,
    raw_score,
    confidence: 0.0,
    affected_meter_ids: plan.affected_meters,
    supporting_node_ids: supporting,
    contradicting_node_ids: contradicting,
    blind_node_ids: blind,
  }
}

///|
/// Rank fault candidates from noisy outage evidence using topology-aware
/// likelihood scoring. The function is deterministic and does not mutate its
/// inputs.
pub fn infer_faults(
  network : Network,
  observations : Array[Observation],
  analysis_time : Double,
  policy? : InferencePolicy,
) -> InferenceResult raise AnalysisError {
  let tree = match build_tree(network) {
    Ok(tree) => tree
    Err(error) => raise AnalysisError::Topology(error.describe())
  }
  let (effective, warning_values) = latest_observations(
    network, observations, analysis_time,
  )
  let warnings = warning_values
  if effective.length() == 0 {
    warnings.push(
      "no usable observations: candidate ranking is structural only",
    )
  }
  let policy = match policy {
    Some(value) => value
    None => InferencePolicy::default()
  }
  let plans = make_plans(network, tree)
  let candidates : Array[Candidate] = []
  for plan in plans {
    candidates.push(score_plan(plan, network, effective, analysis_time, policy))
  }
  candidates.sort_by(fn(left, right) {
    let score_order = if left.raw_score > right.raw_score {
      -1
    } else if left.raw_score < right.raw_score {
      1
    } else {
      0
    }
    if score_order != 0 {
      score_order
    } else {
      left.edge_id.compare(right.edge_id)
    }
  })
  let mut max_score = candidates[0].raw_score
  for candidate in candidates {
    if candidate.raw_score > max_score {
      max_score = candidate.raw_score
    }
  }
  let mut normalizer = 0.0
  for candidate in candidates {
    normalizer += @math.exp(candidate.raw_score - max_score)
  }
  for candidate in candidates {
    candidate.confidence = if normalizer > 0.0 {
      @math.exp(candidate.raw_score - max_score) / normalizer
    } else {
      0.0
    }
  }
  {
    analysis_time,
    candidates,
    used_observation_count: effective.length(),
    warnings,
  }
}

///|
pub fn verify_restoration(
  network : Network,
  fault_edge_id : String,
  observations : Array[Observation],
  analysis_time : Double,
) -> RestoreReport raise AnalysisError {
  let tree = match build_tree(network) {
    Ok(tree) => tree
    Err(error) => raise AnalysisError::Topology(error.describe())
  }
  let (fault_node, expected) = if fault_edge_id == "SOURCE" {
    (tree.root, all_meter_ids(network))
  } else {
    let node = match fault_node_for_edge(network, tree, fault_edge_id) {
      Some(index) => index
      None =>
        raise AnalysisError::InvalidInput(
          "unknown fault edge '" + fault_edge_id + "'",
        )
    }
    (node, downstream_meter_ids(network, tree, node))
  }
  let expected_mask = if fault_edge_id == "SOURCE" {
    Array::make(network.nodes.length(), true)
  } else {
    downstream_mask(tree, fault_node)
  }
  let (effective, _warnings) = latest_observations(
    network, observations, analysis_time,
  )
  let state_by_node : Map[String, PowerState] = Map([])
  for observation in effective {
    state_by_node.set(observation.node_id, observation.state)
  }
  let restored : Array[String] = []
  let still_out : Array[String] = []
  let unknown : Array[String] = []
  let unexpected : Array[String] = []
  for meter_id in expected {
    match state_by_node.get(meter_id) {
      Some(Energized) => restored.push(meter_id)
      Some(Outage) => still_out.push(meter_id)
      _ => unknown.push(meter_id)
    }
  }
  for node in network.nodes {
    let index = match network.find_node(node.id) {
      Some(value) => value
      None => continue
    }
    if expected_mask[index] {
      continue
    }
    match state_by_node.get(node.id) {
      Some(Outage) => unexpected.push(node.id)
      _ => ()
    }
  }
  let status = if unexpected.length() > 0 {
    UnexpectedOutage
  } else if still_out.length() > 0 {
    Partial
  } else if unknown.length() == 0 {
    Complete
  } else if unknown.length() > 0 && restored.length() == 0 {
    Indeterminate
  } else {
    Partial
  }
  {
    fault_edge_id,
    status,
    expected_affected_meter_ids: expected,
    restored_meter_ids: restored,
    still_out_meter_ids: still_out,
    unknown_meter_ids: unknown,
    unexpected_outage_node_ids: unexpected,
  }
}
