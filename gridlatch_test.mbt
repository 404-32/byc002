///|
fn sample_network() -> @griddiagnose.Network {
  @griddiagnose.Network::new(
    "T",
    [
      @griddiagnose.Node::new("T", @griddiagnose.Source),
      @griddiagnose.Node::new("J1", @griddiagnose.Junction),
      @griddiagnose.Node::new("M1", @griddiagnose.Meter),
      @griddiagnose.Node::new("J2", @griddiagnose.Junction),
      @griddiagnose.Node::new("M2", @griddiagnose.Meter),
      @griddiagnose.Node::new("M3", @griddiagnose.Meter),
      @griddiagnose.Node::new("J3", @griddiagnose.Junction),
      @griddiagnose.Node::new("M4", @griddiagnose.Meter),
      @griddiagnose.Node::new("M5", @griddiagnose.Meter),
      @griddiagnose.Node::new("M6", @griddiagnose.Meter),
    ],
    [
      @griddiagnose.Edge::new("E0", "T", "J1", section="feeder"),
      @griddiagnose.Edge::new("E1", "J1", "M1", section="leaf-1"),
      @griddiagnose.Edge::new("E2", "J1", "J2", section="trunk-2"),
      @griddiagnose.Edge::new("E3", "J2", "M2", section="leaf-2"),
      @griddiagnose.Edge::new("E4", "J2", "M3", section="leaf-3"),
      @griddiagnose.Edge::new("E5", "J2", "J3", section="branch-3"),
      @griddiagnose.Edge::new("E6", "J3", "M4", section="leaf-4"),
      @griddiagnose.Edge::new("E7", "J3", "M5", section="leaf-5"),
      @griddiagnose.Edge::new("E8", "J3", "M6", section="leaf-6"),
    ],
  )
}

///|
fn obs(
  node : String,
  state : @griddiagnose.PowerState,
  at : Double,
) -> @griddiagnose.Observation {
  @griddiagnose.Observation::new(node, state, 1.0, at)
}

///|
test "public version is exposed" {
  assert_eq(@griddiagnose.version(), "0.3.0")
}

///|
test "localizes a branch fault from meter evidence" {
  let result = @griddiagnose.infer_faults(
    sample_network(),
    [
      obs("M1", @griddiagnose.Energized, 100.0),
      obs("M2", @griddiagnose.Energized, 100.0),
      obs("M3", @griddiagnose.Energized, 100.0),
      obs("M4", @griddiagnose.Outage, 100.0),
      obs("M5", @griddiagnose.Outage, 100.0),
      obs("M6", @griddiagnose.Outage, 100.0),
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
  let result = @griddiagnose.infer_faults(
    sample_network(),
    [
      obs("M1", @griddiagnose.Energized, 100.0),
      obs("M2", @griddiagnose.Energized, 100.0),
      obs("M3", @griddiagnose.Energized, 100.0),
      obs("M4", @griddiagnose.Outage, 100.0),
      obs("M5", @griddiagnose.Unknown, 100.0),
      obs("M6", @griddiagnose.Outage, 100.0),
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
  let result = @griddiagnose.infer_faults(
    sample_network(),
    [
      obs("M1", @griddiagnose.Energized, 100.0),
      obs("M2", @griddiagnose.Energized, 100.0),
      obs("M3", @griddiagnose.Energized, 100.0),
      obs("M4", @griddiagnose.Outage, 100.0),
      obs("M5", @griddiagnose.Outage, 100.0),
      obs("M6", @griddiagnose.Outage, 100.0),
      obs("M5", @griddiagnose.Energized, 111.0),
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
  let result = @griddiagnose.infer_faults(
    sample_network(),
    [
      obs("T", @griddiagnose.Outage, 100.0),
      obs("M1", @griddiagnose.Outage, 100.0),
      obs("M2", @griddiagnose.Outage, 100.0),
      obs("M3", @griddiagnose.Outage, 100.0),
      obs("M4", @griddiagnose.Outage, 100.0),
      obs("M5", @griddiagnose.Outage, 100.0),
      obs("M6", @griddiagnose.Outage, 100.0),
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
  let result = @griddiagnose.infer_faults(
    sample_network(),
    [
      obs("M1", @griddiagnose.Energized, 100.0),
      obs("M2", @griddiagnose.Energized, 100.0),
      obs("M3", @griddiagnose.Energized, 100.0),
      obs("M4", @griddiagnose.Outage, 100.0),
      obs("M5", @griddiagnose.Outage, 100.0),
      obs("M6", @griddiagnose.Outage, 100.0),
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
  let partial = @griddiagnose.verify_restoration(
    network,
    "E5",
    [
      obs("M4", @griddiagnose.Energized, 200.0),
      obs("M5", @griddiagnose.Energized, 200.0),
      obs("M6", @griddiagnose.Unknown, 200.0),
    ],
    200.0,
  )
  assert_eq(partial.status.to_string(), "partial")
  assert_eq(partial.restored_meter_ids, ["M4", "M5"])
  assert_eq(partial.unknown_meter_ids, ["M6"])

  let unexpected = @griddiagnose.verify_restoration(
    network,
    "E5",
    [
      obs("M1", @griddiagnose.Outage, 200.0),
      obs("M4", @griddiagnose.Energized, 200.0),
      obs("M5", @griddiagnose.Energized, 200.0),
      obs("M6", @griddiagnose.Energized, 200.0),
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
  let document = @griddiagnose.parse_input(source)
  assert_eq(document.network.root_id, "T")
  assert_eq(document.observations.length(), 1)
  let result = @griddiagnose.infer_faults(
    document.network,
    document.observations,
    document.analysis_time,
  )
  assert_eq(result.top().unwrap().edge_id, "E1")
}

///|
test "invalid non-radial topology is rejected" {
  let network = @griddiagnose.Network::new(
    "T",
    [
      @griddiagnose.Node::new("T", @griddiagnose.Source),
      @griddiagnose.Node::new("A", @griddiagnose.Meter),
      @griddiagnose.Node::new("B", @griddiagnose.Meter),
    ],
    [
      @griddiagnose.Edge::new("E1", "T", "A"),
      @griddiagnose.Edge::new("E2", "T", "B"),
      @griddiagnose.Edge::new("E3", "A", "B"),
    ],
  )
  let outcome = Ok(@griddiagnose.infer_faults(network, [], 100.0)) catch {
    error => Err(error)
  }
  assert_true(outcome is Err(@griddiagnose.AnalysisError::Topology(_)))
}

///|
test "malformed JSON returns a structured parse error" {
  let outcome = Ok(@griddiagnose.parse_input("{")) catch { error => Err(error) }
  assert_true(outcome is Err(@griddiagnose.AnalysisError::Parse(_)))
}

///|
test "invalid confidence, future timestamps, and unknown nodes are reported" {
  let network = @griddiagnose.Network::new(
    "T",
    [
      @griddiagnose.Node::new("T", @griddiagnose.Source),
      @griddiagnose.Node::new("M1", @griddiagnose.Meter),
    ],
    [@griddiagnose.Edge::new("E1", "T", "M1")],
  )
  let result = @griddiagnose.infer_faults(
    network,
    [
      @griddiagnose.Observation::new("M1", @griddiagnose.Outage, 2.0, 120.0),
      @griddiagnose.Observation::new(
        "UNKNOWN",
        @griddiagnose.Unknown,
        1.0,
        90.0,
      ),
    ],
    100.0,
  )
  assert_eq(result.used_observation_count, 1)
  assert_eq(result.warnings.length(), 3)
}

///|
test "restoration verification reports complete and still-out states" {
  let network = sample_network()
  let complete = @griddiagnose.verify_restoration(
    network,
    "E5",
    [
      obs("M4", @griddiagnose.Energized, 210.0),
      obs("M5", @griddiagnose.Energized, 210.0),
      obs("M6", @griddiagnose.Energized, 210.0),
    ],
    210.0,
  )
  assert_eq(complete.status.to_string(), "complete")

  let still_out = @griddiagnose.verify_restoration(
    network,
    "E5",
    [
      obs("M4", @griddiagnose.Energized, 210.0),
      obs("M5", @griddiagnose.Outage, 210.0),
      obs("M6", @griddiagnose.Energized, 210.0),
    ],
    210.0,
  )
  assert_eq(still_out.status.to_string(), "partial")
  assert_eq(still_out.still_out_meter_ids, ["M5"])
}

///|
test "topology assessment distinguishes radial and weakly meshed graphs" {
  let radial = sample_network()
  let radial_report = @griddiagnose.assess_topology(radial)
  assert_eq(radial_report.status, "radial")

  let meshed = @griddiagnose.Network::new(
    "T",
    [
      @griddiagnose.Node::new("T", @griddiagnose.Source),
      @griddiagnose.Node::new("A", @griddiagnose.Junction),
      @griddiagnose.Node::new("B", @griddiagnose.Junction),
    ],
    [
      @griddiagnose.Edge::new("E1", "T", "A"),
      @griddiagnose.Edge::new("E2", "T", "B"),
      @griddiagnose.Edge::new("E3", "A", "B"),
    ],
  )
  let meshed_report = @griddiagnose.assess_topology(meshed)
  assert_eq(meshed_report.status, "weakly_meshed")
  assert_eq(meshed_report.cycle_rank, 1)
}

///|
test "partial topology is reported separately" {
  let report = @griddiagnose.assess_topology(sample_network(), unknown_edge_ids=[
    "E-UNREGISTERED",
  ])
  assert_eq(report.status, "partial")
  assert_eq(report.unknown_edge_ids, ["E-UNREGISTERED"])
}

///|
test "phase diagnosis detects phase loss and imbalance" {
  let report = @griddiagnose.diagnose_phase([
    @griddiagnose.PhaseReading::new("M1", 100.0, 230.0, 230.0, 0.0),
    @griddiagnose.PhaseReading::new("M2", 100.0, 240.0, 215.0, 230.0),
  ])
  assert_eq(report.findings.length(), 2)
  assert_eq(report.findings[0].kind, "phase_loss")
  assert_eq(report.findings[0].affected_phases, ["C"])
  assert_eq(report.findings[1].kind, "voltage_unbalance")
}

///|
test "power quality diagnosis groups sag and swell intervals" {
  let samples = [
    @griddiagnose.VoltagePoint::new(0.00, 230.0),
    @griddiagnose.VoltagePoint::new(0.01, 230.0),
    @griddiagnose.VoltagePoint::new(0.02, 180.0),
    @griddiagnose.VoltagePoint::new(0.03, 175.0),
    @griddiagnose.VoltagePoint::new(0.04, 230.0),
    @griddiagnose.VoltagePoint::new(0.05, 260.0),
    @griddiagnose.VoltagePoint::new(0.06, 265.0),
    @griddiagnose.VoltagePoint::new(0.07, 230.0),
  ]
  let report = @griddiagnose.diagnose_power_quality(
    [@griddiagnose.VoltageSeries::new("M1", 230.0, samples)],
    minimum_duration_sec=0.02,
  )
  assert_eq(report.events.length(), 2)
  assert_eq(report.events[0].kind, "voltage_sag")
  assert_eq(report.events[1].kind, "voltage_swell")
  assert_true(report.events[0].duration_sec >= 0.019999)
}

///|
test "telemetry diagnosis detects stale, frozen, clock, and topology issues" {
  let samples = [
    @griddiagnose.TelemetryPoint::new(100.0, 12.0),
    @griddiagnose.TelemetryPoint::new(50.0, 12.0),
    @griddiagnose.TelemetryPoint::new(10.0, 12.0),
  ]
  let report = @griddiagnose.diagnose_telemetry(
    [@griddiagnose.TelemetrySeries::new("M1", samples)],
    [@griddiagnose.TopologyLinkObservation::new("M1", "J1", "J2")],
    500.0,
    stuck_window_sec=50.0,
  )
  let mut stale = false
  let mut stuck = false
  let mut clock = false
  let mut mismatch = false
  for finding in report.findings {
    if finding.kind == "stale_series" {
      stale = true
    }
    if finding.kind == "stuck_series" {
      stuck = true
    }
    if finding.kind == "clock_anomaly" {
      clock = true
    }
    if finding.kind == "topology_mismatch" {
      mismatch = true
    }
  }
  assert_true(stale && stuck && clock && mismatch)
}

///|
test "multiple independent faults are decomposed into hypotheses" {
  let report = @griddiagnose.infer_multiple_faults(
    sample_network(),
    [
      obs("M1", @griddiagnose.Outage, 100.0),
      obs("M2", @griddiagnose.Energized, 100.0),
      obs("M3", @griddiagnose.Energized, 100.0),
      obs("M4", @griddiagnose.Outage, 100.0),
      obs("M5", @griddiagnose.Outage, 100.0),
      obs("M6", @griddiagnose.Outage, 100.0),
    ],
    100.0,
  )
  assert_eq(report.faults.length(), 2)
  assert_true(
    report.faults[0].candidate.edge_id != report.faults[1].candidate.edge_id,
  )
  assert_eq(report.residual_outage_meter_ids.length(), 0)
}

///|
test "unified diagnostic input produces one combined report" {
  let source =
    #|{
    #|  "analysis_time": 100,
    #|  "phase_readings": [
    #|    {"node_id":"M1","timestamp":99,"a_voltage":230,"b_voltage":230,"c_voltage":0}
    #|  ],
    #|  "voltage_series": [
    #|    {
    #|      "node_id":"M1",
    #|      "nominal_voltage":230,
    #|      "samples":[
    #|        {"timestamp":0,"voltage":230},
    #|        {"timestamp":0.01,"voltage":180},
    #|        {"timestamp":0.02,"voltage":175},
    #|        {"timestamp":0.03,"voltage":230}
    #|      ]
    #|    }
    #|  ]
    #|}
  let input = @griddiagnose.parse_diagnostic_input(source)
  let report = @griddiagnose.run_diagnostic(input)
  assert_eq(report.version, "0.3.0")
  assert_true(report.critical_count >= 1)
  assert_eq(report.phase.findings[0].kind, "phase_loss")
  assert_eq(report.power_quality.events[0].kind, "voltage_sag")
  assert_eq(report.arbitration.primary_class, "supply_fault")
}

///|
test "arbitration separates supply faults from measurement faults" {
  let supply = @griddiagnose.arbitrate_causes(
    None,
    None,
    @griddiagnose.diagnose_phase([
      @griddiagnose.PhaseReading::new("M1", 100.0, 230.0, 230.0, 0.0),
    ]),
    @griddiagnose.diagnose_power_quality([]),
    @griddiagnose.diagnose_telemetry([], [], 100.0),
  )
  assert_eq(supply.primary_class, "supply_fault")

  let measurement = @griddiagnose.arbitrate_causes(
    None,
    None,
    @griddiagnose.diagnose_phase([]),
    @griddiagnose.diagnose_power_quality([]),
    @griddiagnose.diagnose_telemetry(
      [
        @griddiagnose.TelemetrySeries::new("M1", [
          @griddiagnose.TelemetryPoint::new(0.0, 1.0),
          @griddiagnose.TelemetryPoint::new(100.0, 1.0),
        ]),
      ],
      [],
      1000.0,
      stuck_window_sec=50.0,
    ),
  )
  assert_eq(measurement.primary_class, "measurement_issue")
}

///|
test "co-located supply and telemetry anomalies reduce to measurement issue" {
  let phase = @griddiagnose.diagnose_phase([
    @griddiagnose.PhaseReading::new("M1", 100.0, 230.0, 0.0, 0.0),
  ])
  let telemetry = @griddiagnose.diagnose_telemetry(
    [
      @griddiagnose.TelemetrySeries::new("M1", [
        @griddiagnose.TelemetryPoint::new(0.0, 1.0),
        @griddiagnose.TelemetryPoint::new(100.0, 1.0),
      ]),
    ],
    [],
    1000.0,
    stuck_window_sec=50.0,
  )
  let result = @griddiagnose.arbitrate_causes(
    None,
    None,
    phase,
    @griddiagnose.diagnose_power_quality([]),
    telemetry,
  )
  assert_eq(result.primary_class, "measurement_issue")
  assert_true(result.conflicts.length() > 0)
}

///|
test "combined report exposes all three root-cause classes" {
  let source =
    #|{
    #|  "analysis_time": 500,
    #|  "network": {
    #|    "root":"T1",
    #|    "nodes":[
    #|      {"id":"T1","kind":"source"},
    #|      {"id":"J1","kind":"junction"},
    #|      {"id":"M1","kind":"meter"},
    #|      {"id":"M2","kind":"meter"}
    #|    ],
    #|    "edges":[
    #|      {"id":"E0","from":"T1","to":"J1","section":"feeder"},
    #|      {"id":"E1","from":"J1","to":"M1","section":"service M1"},
    #|      {"id":"E2","from":"J1","to":"M2","section":"service M2"}
    #|    ]
    #|  },
    #|  "unknown_topology_edge_ids":["X-NEW"],
    #|  "observations":[
    #|    {"node_id":"M1","state":"outage","confidence":0.99},
    #|    {"node_id":"M2","state":"energized","confidence":0.99}
    #|  ],
    #|  "phase_readings":[
    #|    {"node_id":"M1","timestamp":499,"a_voltage":230,"b_voltage":230,"c_voltage":0}
    #|  ],
    #|  "telemetry_series":[
    #|    {"node_id":"M2","samples":[
    #|      {"timestamp":0,"value":1.0},
    #|      {"timestamp":100,"value":1.0}
    #|    ]}
    #|  ],
    #|  "topology_links":[
    #|    {"node_id":"M2","declared_parent":"J1","observed_parent":"T1"}
    #|  ]
    #|}
  let report = @griddiagnose.run_diagnostic(
    @griddiagnose.parse_diagnostic_input(source),
  )
  assert_eq(report.arbitration.primary_class, "mixed")
  assert_eq(report.arbitration.causes.length(), 3)
}
