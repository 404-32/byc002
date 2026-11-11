///|
fn sample_network() -> @gridlatch.Network {
  @gridlatch.Network::new(
    "T",
    [
      @gridlatch.Node::new("T", @gridlatch.Source),
      @gridlatch.Node::new("J1", @gridlatch.Junction),
      @gridlatch.Node::new("M1", @gridlatch.Meter),
      @gridlatch.Node::new("J2", @gridlatch.Junction),
      @gridlatch.Node::new("M2", @gridlatch.Meter),
      @gridlatch.Node::new("M3", @gridlatch.Meter),
      @gridlatch.Node::new("J3", @gridlatch.Junction),
      @gridlatch.Node::new("M4", @gridlatch.Meter),
      @gridlatch.Node::new("M5", @gridlatch.Meter),
      @gridlatch.Node::new("M6", @gridlatch.Meter),
    ],
    [
      @gridlatch.Edge::new("E0", "T", "J1", section="feeder"),
      @gridlatch.Edge::new("E1", "J1", "M1", section="leaf-1"),
      @gridlatch.Edge::new("E2", "J1", "J2", section="trunk-2"),
      @gridlatch.Edge::new("E3", "J2", "M2", section="leaf-2"),
      @gridlatch.Edge::new("E4", "J2", "M3", section="leaf-3"),
      @gridlatch.Edge::new("E5", "J2", "J3", section="branch-3"),
      @gridlatch.Edge::new("E6", "J3", "M4", section="leaf-4"),
      @gridlatch.Edge::new("E7", "J3", "M5", section="leaf-5"),
      @gridlatch.Edge::new("E8", "J3", "M6", section="leaf-6"),
    ],
  )
}

///|
fn obs(
  node : String,
  state : @gridlatch.PowerState,
  at : Double,
) -> @gridlatch.Observation {
  @gridlatch.Observation::new(node, state, 1.0, at)
}

///|
test "public version is exposed" {
  assert_eq(@gridlatch.version(), "0.1.0")
}

///|
test "localizes a branch fault from meter evidence" {
  let result = @gridlatch.infer_faults(
    sample_network(),
    [
      obs("M1", @gridlatch.Energized, 100.0),
      obs("M2", @gridlatch.Energized, 100.0),
      obs("M3", @gridlatch.Energized, 100.0),
      obs("M4", @gridlatch.Outage, 100.0),
      obs("M5", @gridlatch.Outage, 100.0),
      obs("M6", @gridlatch.Outage, 100.0),
    ],
    100.0,
  )
  let top = match result.top() {
    Some(value) => value
    None => fail("expected a candidate")
  }
  assert_eq(top.edge_id, "E5")
  assert_eq(top.affected_meter_ids, ["M4", "M5", "M6"])
  assert_true(top.confidence > 0.8)
}

///|
test "communication dropouts are represented as unknown evidence" {
  let result = @gridlatch.infer_faults(
    sample_network(),
    [
      obs("M1", @gridlatch.Energized, 100.0),
      obs("M2", @gridlatch.Energized, 100.0),
      obs("M3", @gridlatch.Energized, 100.0),
      obs("M4", @gridlatch.Outage, 100.0),
      obs("M5", @gridlatch.Unknown, 100.0),
      obs("M6", @gridlatch.Outage, 100.0),
    ],
    100.0,
  )
  let top = match result.top() {
    Some(value) => value
    None => fail("expected a candidate")
  }
  assert_eq(top.edge_id, "E5")
  assert_eq(top.blind_node_ids, ["M5"])
}

///|
test "the latest observation for a node wins" {
  let result = @gridlatch.infer_faults(
    sample_network(),
    [
      obs("M1", @gridlatch.Energized, 100.0),
      obs("M2", @gridlatch.Energized, 100.0),
      obs("M3", @gridlatch.Energized, 100.0),
      obs("M4", @gridlatch.Outage, 100.0),
      obs("M5", @gridlatch.Outage, 100.0),
      obs("M6", @gridlatch.Outage, 100.0),
      obs("M5", @gridlatch.Energized, 111.0),
    ],
    120.0,
  )
  assert_eq(result.used_observation_count, 6)
  let branch_candidate = match
    result.candidates.filter(fn(candidate) { candidate.edge_id == "E5" }).get(0) {
    Some(value) => value
    None => fail("expected E5 candidate")
  }
  assert_eq(branch_candidate.contradicting_node_ids, ["M5"])
}

///|
test "source outage explains a complete feeder loss" {
  let result = @gridlatch.infer_faults(
    sample_network(),
    [
      obs("T", @gridlatch.Outage, 100.0),
      obs("M1", @gridlatch.Outage, 100.0),
      obs("M2", @gridlatch.Outage, 100.0),
      obs("M3", @gridlatch.Outage, 100.0),
      obs("M4", @gridlatch.Outage, 100.0),
      obs("M5", @gridlatch.Outage, 100.0),
      obs("M6", @gridlatch.Outage, 100.0),
    ],
    100.0,
  )
  let top = match result.top() {
    Some(value) => value
    None => fail("expected a candidate")
  }
  assert_eq(top.edge_id, "SOURCE")
}

///|
test "candidate probabilities form a normalized distribution" {
  let result = @gridlatch.infer_faults(
    sample_network(),
    [
      obs("M1", @gridlatch.Energized, 100.0),
      obs("M2", @gridlatch.Energized, 100.0),
      obs("M3", @gridlatch.Energized, 100.0),
      obs("M4", @gridlatch.Outage, 100.0),
      obs("M5", @gridlatch.Outage, 100.0),
      obs("M6", @gridlatch.Outage, 100.0),
    ],
    100.0,
  )
  let mut sum = 0.0
  for candidate in result.candidates {
    sum += candidate.confidence
  }
  assert_true(sum > 0.999 && sum < 1.001)
}

///|
test "restoration verification distinguishes partial and unexpected outages" {
  let network = sample_network()
  let partial = @gridlatch.verify_restoration(
    network,
    "E5",
    [
      obs("M4", @gridlatch.Energized, 200.0),
      obs("M5", @gridlatch.Energized, 200.0),
      obs("M6", @gridlatch.Unknown, 200.0),
    ],
    200.0,
  )
  assert_eq(partial.status.to_string(), "partial")
  assert_eq(partial.restored_meter_ids, ["M4", "M5"])
  assert_eq(partial.unknown_meter_ids, ["M6"])

  let unexpected = @gridlatch.verify_restoration(
    network,
    "E5",
    [
      obs("M1", @gridlatch.Outage, 200.0),
      obs("M4", @gridlatch.Energized, 200.0),
      obs("M5", @gridlatch.Energized, 200.0),
      obs("M6", @gridlatch.Energized, 200.0),
    ],
    200.0,
  )
  assert_eq(unexpected.status.to_string(), "unexpected_outage")
  assert_eq(unexpected.unexpected_outage_node_ids, ["M1"])
}

///|
test "JSON input is parsed into the public data model" {
  let source =
    #|{
    #|  "analysis_time": 100,
    #|  "network": {
    #|    "root": "T",
    #|    "nodes": [
    #|      {"id":"T","kind":"source"},
    #|      {"id":"M1","kind":"meter"}
    #|    ],
    #|    "edges": [
    #|      {"id":"E1","from":"T","to":"M1","section":"only-load"}
    #|    ]
    #|  },
    #|  "observations": [
    #|    {"node_id":"M1","state":"outage","confidence":0.9}
    #|  ]
    #|}
  let document = @gridlatch.parse_input(source)
  assert_eq(document.network.root_id, "T")
  assert_eq(document.observations.length(), 1)
  let result = @gridlatch.infer_faults(
    document.network,
    document.observations,
    document.analysis_time,
  )
  assert_eq(result.top().unwrap().edge_id, "E1")
}

///|
test "invalid non-radial topology is rejected" {
  let network = @gridlatch.Network::new(
    "T",
    [
      @gridlatch.Node::new("T", @gridlatch.Source),
      @gridlatch.Node::new("A", @gridlatch.Meter),
      @gridlatch.Node::new("B", @gridlatch.Meter),
    ],
    [
      @gridlatch.Edge::new("E1", "T", "A"),
      @gridlatch.Edge::new("E2", "T", "B"),
      @gridlatch.Edge::new("E3", "A", "B"),
    ],
  )
  let outcome = Ok(@gridlatch.infer_faults(network, [], 100.0)) catch {
    error => Err(error)
  }
  assert_true(outcome is Err(@gridlatch.AnalysisError::Topology(_)))
}

///|
test "malformed JSON returns a structured parse error" {
  let outcome = Ok(@gridlatch.parse_input("{")) catch { error => Err(error) }
  assert_true(outcome is Err(@gridlatch.AnalysisError::Parse(_)))
}

///|
test "invalid confidence, future timestamps, and unknown nodes are reported" {
  let network = @gridlatch.Network::new(
    "T",
    [
      @gridlatch.Node::new("T", @gridlatch.Source),
      @gridlatch.Node::new("M1", @gridlatch.Meter),
    ],
    [@gridlatch.Edge::new("E1", "T", "M1")],
  )
  let result = @gridlatch.infer_faults(
    network,
    [
      @gridlatch.Observation::new("M1", @gridlatch.Outage, 2.0, 120.0),
      @gridlatch.Observation::new("UNKNOWN", @gridlatch.Unknown, 1.0, 90.0),
    ],
    100.0,
  )
  assert_eq(result.used_observation_count, 1)
  assert_eq(result.warnings.length(), 3)
}

///|
test "restoration verification reports complete and still-out states" {
  let network = sample_network()
  let complete = @gridlatch.verify_restoration(
    network,
    "E5",
    [
      obs("M4", @gridlatch.Energized, 210.0),
      obs("M5", @gridlatch.Energized, 210.0),
      obs("M6", @gridlatch.Energized, 210.0),
    ],
    210.0,
  )
  assert_eq(complete.status.to_string(), "complete")

  let still_out = @gridlatch.verify_restoration(
    network,
    "E5",
    [
      obs("M4", @gridlatch.Energized, 210.0),
      obs("M5", @gridlatch.Outage, 210.0),
      obs("M6", @gridlatch.Energized, 210.0),
    ],
    210.0,
  )
  assert_eq(still_out.status.to_string(), "partial")
  assert_eq(still_out.still_out_meter_ids, ["M5"])
}
