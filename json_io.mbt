///|
pub struct InputDocument {
  network : Network
  observations : Array[Observation]
  analysis_time : Double
  confirmed_fault_edge_id : String?
}

///|
fn object_of(value : Json) -> Map[String, Json] raise AnalysisError {
  match value {
    Object(object) => object
    _ => raise AnalysisError::InvalidInput("expected a JSON object")
  }
}

///|
fn array_of(value : Json) -> Array[Json] raise AnalysisError {
  match value {
    Array(array) => array
    _ => raise AnalysisError::InvalidInput("expected a JSON array")
  }
}

///|
fn string_of(value : Json) -> String raise AnalysisError {
  match value {
    String(value) => value
    _ => raise AnalysisError::InvalidInput("expected a JSON string")
  }
}

///|
fn number_of(value : Json) -> Double raise AnalysisError {
  match value {
    Number(value, ..) => value
    _ => raise AnalysisError::InvalidInput("expected a JSON number")
  }
}

///|
fn required(
  object : Map[String, Json],
  key : String,
) -> Json raise AnalysisError {
  match object.get(key) {
    Some(value) => value
    None => raise AnalysisError::InvalidInput("missing field '" + key + "'")
  }
}

///|
fn required_string(
  object : Map[String, Json],
  key : String,
) -> String raise AnalysisError {
  string_of(required(object, key))
}

///|
fn optional_string(
  object : Map[String, Json],
  key : String,
) -> String? raise AnalysisError {
  match object.get(key) {
    None => None
    Some(Null) => None
    Some(value) => Some(string_of(value))
  }
}

///|
fn required_number(
  object : Map[String, Json],
  key : String,
) -> Double raise AnalysisError {
  number_of(required(object, key))
}

///|
fn optional_number(
  object : Map[String, Json],
  key : String,
  default : Double,
) -> Double raise AnalysisError {
  match object.get(key) {
    None => default
    Some(Null) => default
    Some(value) => number_of(value)
  }
}

///|
fn parse_node_kind(value : String) -> NodeKind raise AnalysisError {
  match value {
    "source" => Source
    "junction" => Junction
    "meter" => Meter
    _ => raise AnalysisError::InvalidInput("unknown node kind '" + value + "'")
  }
}

///|
fn parse_node(value : Json) -> Node raise AnalysisError {
  let object = object_of(value)
  let id = required_string(object, "id")
  let kind = parse_node_kind(required_string(object, "kind"))
  let label = optional_string(object, "label")
  match label {
    Some(value) => Node::new(id, kind, label=value)
    None => Node::new(id, kind)
  }
}

///|
fn parse_edge(value : Json) -> Edge raise AnalysisError {
  let object = object_of(value)
  let id = required_string(object, "id")
  let from_id = required_string(object, "from")
  let to_id = required_string(object, "to")
  let section = optional_string(object, "section")
  match section {
    Some(value) => Edge::new(id, from_id, to_id, section=value)
    None => Edge::new(id, from_id, to_id)
  }
}

///|
fn parse_power_state(value : String) -> PowerState raise AnalysisError {
  match value {
    "energized" | "powered" | "on" => Energized
    "outage" | "off" | "lost" => Outage
    "unknown" | "blind" => Unknown
    _ =>
      raise AnalysisError::InvalidInput(
        "unknown observation state '" + value + "'",
      )
  }
}

///|
fn parse_observation(
  value : Json,
  analysis_time : Double,
) -> Observation raise AnalysisError {
  let object = object_of(value)
  let node_id = required_string(object, "node_id")
  let state = parse_power_state(required_string(object, "state"))
  let confidence = optional_number(object, "confidence", 1.0)
  let observed_at = optional_number(object, "observed_at", analysis_time)
  Observation::new(node_id, state, confidence, observed_at)
}

///|
fn parse_network(value : Json) -> Network raise AnalysisError {
  let object = object_of(value)
  let root_id = required_string(object, "root")
  let node_values = array_of(required(object, "nodes"))
  let edge_values = array_of(required(object, "edges"))
  let nodes : Array[Node] = []
  for node_value in node_values {
    nodes.push(parse_node(node_value))
  }
  let edges : Array[Edge] = []
  for edge_value in edge_values {
    edges.push(parse_edge(edge_value))
  }
  Network::new(root_id, nodes, edges)
}

///|
fn parse_document(source : String) -> InputDocument raise AnalysisError {
  let json = @json.parse(source) catch {
    error => raise AnalysisError::Parse(error.to_string())
  }
  let object = object_of(json)
  let analysis_time = required_number(object, "analysis_time")
  let network = parse_network(required(object, "network"))
  let observation_values = array_of(required(object, "observations"))
  let observations : Array[Observation] = []
  for observation_value in observation_values {
    observations.push(parse_observation(observation_value, analysis_time))
  }
  let confirmed = optional_string(object, "confirmed_fault_edge_id")
  { network, observations, analysis_time, confirmed_fault_edge_id: confirmed, }
}

///|
/// Parse the public JSON input contract used by the CLI and demo.
pub fn parse_input(source : String) -> InputDocument raise AnalysisError {
  parse_document(source)
}

///|
fn strings_json(values : Array[String]) -> Json {
  Json::array(values.map(fn(value) { Json::string(value) }))
}

///|
fn node_json(node : Node) -> Json {
  Json::object(
    Map([
      ("id", Json::string(node.id)),
      ("label", Json::string(node.label)),
      ("kind", Json::string(node.kind.to_string())),
    ]),
  )
}

///|
fn edge_json(edge : Edge) -> Json {
  Json::object(
    Map([
      ("id", Json::string(edge.id)),
      ("from", Json::string(edge.from_id)),
      ("to", Json::string(edge.to_id)),
      ("section", Json::string(edge.section)),
    ]),
  )
}

///|
fn observation_json(observation : Observation) -> Json {
  Json::object(
    Map([
      ("node_id", Json::string(observation.node_id)),
      ("state", Json::string(observation.state.to_string())),
      ("confidence", Json::number(observation.confidence)),
      ("observed_at", Json::number(observation.observed_at)),
    ]),
  )
}

///|
pub fn network_to_json(network : Network) -> Json {
  Json::object(
    Map([
      ("root", Json::string(network.root_id)),
      ("nodes", Json::array(network.nodes.map(node_json))),
      ("edges", Json::array(network.edges.map(edge_json))),
    ]),
  )
}

///|
pub fn observations_to_json(observations : Array[Observation]) -> Json {
  Json::array(observations.map(observation_json))
}

///|
fn candidate_json(candidate : Candidate) -> Json {
  Json::object(
    Map([
      ("edge_id", Json::string(candidate.edge_id)),
      ("fault_node_id", Json::string(candidate.fault_node_id)),
      ("section", Json::string(candidate.section)),
      ("raw_score", Json::number(candidate.raw_score)),
      ("confidence", Json::number(candidate.confidence)),
      ("affected_meter_ids", strings_json(candidate.affected_meter_ids)),
      ("supporting_node_ids", strings_json(candidate.supporting_node_ids)),
      ("contradicting_node_ids", strings_json(candidate.contradicting_node_ids)),
      ("blind_node_ids", strings_json(candidate.blind_node_ids)),
    ]),
  )
}

///|
pub fn result_to_json(result : InferenceResult) -> Json {
  Json::object(
    Map([
      ("analysis_time", Json::number(result.analysis_time)),
      (
        "used_observation_count",
        Json::number(result.used_observation_count.to_double()),
      ),
      ("warnings", strings_json(result.warnings)),
      ("candidates", Json::array(result.candidates.map(candidate_json))),
    ]),
  )
}

///|
pub fn restore_to_json(report : RestoreReport) -> Json {
  Json::object(
    Map([
      ("fault_edge_id", Json::string(report.fault_edge_id)),
      ("status", Json::string(report.status.to_string())),
      (
        "expected_affected_meter_ids",
        strings_json(report.expected_affected_meter_ids),
      ),
      ("restored_meter_ids", strings_json(report.restored_meter_ids)),
      ("still_out_meter_ids", strings_json(report.still_out_meter_ids)),
      ("unknown_meter_ids", strings_json(report.unknown_meter_ids)),
      (
        "unexpected_outage_node_ids",
        strings_json(report.unexpected_outage_node_ids),
      ),
    ]),
  )
}

///|
pub fn result_json_string(result : InferenceResult) -> String {
  result_to_json(result).stringify()
}

///|
pub fn restore_json_string(report : RestoreReport) -> String {
  restore_to_json(report).stringify()
}
