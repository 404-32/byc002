///|
/// Role of a node in a low-voltage distribution tree.
pub(all) enum NodeKind {
  Source
  Junction
  Meter
}

///|
pub fn NodeKind::to_string(self : NodeKind) -> String {
  match self {
    Source => "source"
    Junction => "junction"
    Meter => "meter"
  }
}

///|
pub struct Node {
  id : String
  label : String
  kind : NodeKind
}

///|
pub fn Node::new(id : String, kind : NodeKind, label? : String) -> Node {
  let label = match label {
    Some(value) if value != "" => value
    _ => id
  }
  { id, label, kind, }
}

///|
pub struct Edge {
  id : String
  from_id : String
  to_id : String
  section : String
}

///|
pub fn Edge::new(
  id : String,
  from_id : String,
  to_id : String,
  section? : String,
) -> Edge {
  let section = match section {
    Some(value) if value != "" => value
    _ => id
  }
  { id, from_id, to_id, section, }
}

///|
pub struct Network {
  root_id : String
  nodes : Array[Node]
  edges : Array[Edge]
}

///|
pub fn Network::new(
  root_id : String,
  nodes : Array[Node],
  edges : Array[Edge],
) -> Network {
  { root_id, nodes, edges, }
}

///|
pub fn Network::find_node(self : Network, id : String) -> Int32? {
  let mut i = 0
  while i < self.nodes.length() {
    if self.nodes[i].id == id {
      return Some(i)
    }
    i += 1
  }
  None
}

///|
pub(all) enum PowerState {
  Energized
  Outage
  Unknown
}

///|
pub fn PowerState::to_string(self : PowerState) -> String {
  match self {
    Energized => "energized"
    Outage => "outage"
    Unknown => "unknown"
  }
}

///|
pub struct Observation {
  node_id : String
  state : PowerState
  mut confidence : Double
  mut observed_at : Double
}

///|
pub fn Observation::new(
  node_id : String,
  state : PowerState,
  confidence : Double,
  observed_at : Double,
) -> Observation {
  { node_id, state, confidence, observed_at, }
}

///|
pub struct InferencePolicy {
  half_life_sec : Double
  structural_prior : Double
  outage_penalty : Double
  powered_penalty : Double
}

///|
pub fn InferencePolicy::default() -> InferencePolicy {
  {
    half_life_sec: 120.0,
    structural_prior: 0.18,
    outage_penalty: 2.2,
    powered_penalty: 2.8,
  }
}

///|
pub fn InferencePolicy::balanced(
  half_life_sec : Double,
  structural_prior : Double,
) -> InferencePolicy {
  {
    half_life_sec,
    structural_prior,
    outage_penalty: 2.2,
    powered_penalty: 2.8,
  }
}

///|
pub struct Candidate {
  edge_id : String
  fault_node_id : String
  section : String
  raw_score : Double
  mut confidence : Double
  affected_meter_ids : Array[String]
  supporting_node_ids : Array[String]
  contradicting_node_ids : Array[String]
  blind_node_ids : Array[String]
}

///|
pub struct InferenceResult {
  analysis_time : Double
  candidates : Array[Candidate]
  used_observation_count : Int32
  warnings : Array[String]
}

///|
pub fn InferenceResult::top(self : InferenceResult) -> Candidate? {
  self.candidates.get(0)
}

///|
pub(all) enum RestoreState {
  Complete
  Partial
  UnexpectedOutage
  Indeterminate
}

///|
pub fn RestoreState::to_string(self : RestoreState) -> String {
  match self {
    Complete => "complete"
    Partial => "partial"
    UnexpectedOutage => "unexpected_outage"
    Indeterminate => "indeterminate"
  }
}

///|
pub struct RestoreReport {
  fault_edge_id : String
  status : RestoreState
  expected_affected_meter_ids : Array[String]
  restored_meter_ids : Array[String]
  still_out_meter_ids : Array[String]
  unknown_meter_ids : Array[String]
  unexpected_outage_node_ids : Array[String]
}

///|
pub suberror AnalysisError {
  Parse(String)
  InvalidInput(String)
  Topology(String)
}

///|
pub fn AnalysisError::describe(self : AnalysisError) -> String {
  match self {
    Parse(message) => "JSON parse error: " + message
    InvalidInput(message) => "invalid input: " + message
    Topology(message) => "invalid topology: " + message
  }
}
