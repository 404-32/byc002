///|
enum Command {
  Diagnose
  Analyze
  Verify
}

///|
struct CliOptions {
  command : Command
  path : String
  json_output : Bool
  edge_id : String?
  policy : @core.InferencePolicy
}

///|
enum CliParseError {
  MissingCommand
  UnknownCommand(String)
  MissingPath
  MissingValue(String)
  UnknownOption(String)
  InvalidValue(String)
}

///|
fn cli_error_text(error : CliParseError) -> String {
  match error {
    MissingCommand => "missing command"
    UnknownCommand(command) => "unknown command '" + command + "'"
    MissingPath => "missing input JSON path"
    MissingValue(option) => "missing value after " + option
    UnknownOption(option) => "unknown option " + option
    InvalidValue(option) => "invalid value for " + option
  }
}

///|
fn parse_positive_double(value : String) -> Double? {
  let number = @string.parse_double(value) catch { _ => return None }
  if number > 0.0 && number - number == 0.0 {
    Some(number)
  } else {
    None
  }
}

///|
fn parse_cli(args : Array[String]) -> Result[CliOptions, CliParseError] {
  let offset = if args.length() > 1 && args[1].has_suffix(".js") {
    2
  } else {
    1
  }
  if args.length() <= offset {
    return Err(MissingCommand)
  }
  let command = match args[offset] {
    "diagnose" => Diagnose
    "analyze" => Analyze
    "verify" => Verify
    other => return Err(UnknownCommand(other))
  }
  let path_index = offset + 1
  if args.length() <= path_index || args[path_index].has_prefix("-") {
    return Err(MissingPath)
  }
  let mut json_output = false
  let mut edge_id : String? = None
  let mut half_life = 120.0
  let mut prior = 0.18
  let mut index = path_index + 1
  while index < args.length() {
    match args[index] {
      "--json" => {
        json_output = true
        index += 1
      }
      "--edge" => {
        if index + 1 >= args.length() {
          return Err(MissingValue("--edge"))
        }
        edge_id = Some(args[index + 1])
        index += 2
      }
      "--half-life" => {
        if index + 1 >= args.length() {
          return Err(MissingValue("--half-life"))
        }
        half_life = match parse_positive_double(args[index + 1]) {
          Some(value) => value
          None => return Err(InvalidValue("--half-life"))
        }
        index += 2
      }
      "--prior" => {
        if index + 1 >= args.length() {
          return Err(MissingValue("--prior"))
        }
        prior = match parse_positive_double(args[index + 1]) {
          Some(value) => value
          None => return Err(InvalidValue("--prior"))
        }
        index += 2
      }
      option => return Err(UnknownOption(option))
    }
  }
  Ok({
    command,
    path: args[path_index],
    json_output,
    edge_id,
    policy: @core.InferencePolicy::balanced(half_life, prior),
  })
}

///|
fn usage() -> String {
  (
    #|GridDiagnose - multi-model low-voltage distribution diagnostics
    #|
    #|Usage:
    #|  griddiagnose diagnose INPUT.json [--json]
    #|  griddiagnose analyze INPUT.json [--json] [--half-life SECONDS] [--prior WEIGHT]
    #|  griddiagnose verify  INPUT.json [--edge EDGE_ID] [--json]
    #|
    #|Examples:
    #|  griddiagnose diagnose examples/griddiagnose_multimodel.json
    #|  griddiagnose analyze examples/branch_fault.json
    #|  griddiagnose verify examples/restore_case.json --edge E17 --json
  )
}

///|
fn join_ids(values : Array[String]) -> String {
  if values.length() == 0 {
    "(none)"
  } else {
    values.join(", ")
  }
}

///|
fn percent(value : Double) -> String {
  (value * 100.0).to_string() + "%"
}

///|
fn analyze_text(
  document : @core.InputDocument,
  result : @core.InferenceResult,
) -> String {
  let top = match result.top() {
    Some(value) => value
    None => return "No fault candidates were generated."
  }
  let mut output = "GridDiagnose outage fault localization\n"
  output += "Analysis time: " + result.analysis_time.to_string() + " s\n"
  output += "Observations used: " +
    result.used_observation_count.to_string() +
    "\n\n"
  output += "Top candidate: " + top.edge_id + " [" + top.section + "]\n"
  output += "Fault node: " + top.fault_node_id + "\n"
  output += "Confidence: " + percent(top.confidence) + "\n"
  output += "Affected meters (" +
    top.affected_meter_ids.length().to_string() +
    "): "
  output += join_ids(top.affected_meter_ids) + "\n"
  output += "Supporting nodes: " + join_ids(top.supporting_node_ids) + "\n"
  output += "Contradicting nodes: " +
    join_ids(top.contradicting_node_ids) +
    "\n"
  output += "Blind nodes: " + join_ids(top.blind_node_ids) + "\n\n"
  output += "Candidate ranking:\n"
  let limit = if result.candidates.length() < 5 {
    result.candidates.length()
  } else {
    5
  }
  for index in 0..<limit {
    let candidate = result.candidates[index]
    output += "  " + (index + 1).to_string() + ". "
    output += candidate.edge_id + " [" + candidate.section + "]  "
    output += percent(candidate.confidence) + "\n"
  }
  if result.warnings.length() > 0 {
    output += "\nWarnings:\n"
    for warning in result.warnings {
      output += "  - " + warning + "\n"
    }
  }
  let _ = document
  output
}

///|
fn restore_text(report : @core.RestoreReport) -> String {
  let mut output = "GridDiagnose restoration verification\n"
  output += "Fault edge: " + report.fault_edge_id + "\n"
  output += "Status: " + report.status.to_string() + "\n"
  output += "Expected affected: " +
    report.expected_affected_meter_ids.length().to_string() +
    "\n"
  output += "Restored: " + report.restored_meter_ids.length().to_string() + "\n"
  output += "Still out: " +
    report.still_out_meter_ids.length().to_string() +
    "\n"
  output += "Unknown: " + report.unknown_meter_ids.length().to_string() + "\n"
  if report.unexpected_outage_node_ids.length() > 0 {
    output += "Unexpected outage outside the repaired section: "
    output += join_ids(report.unexpected_outage_node_ids) + "\n"
  }
  output
}

///|
fn diagnostic_text(report : @core.DiagnosticReport) -> String {
  let mut output = "GridDiagnose combined diagnostic report\n"
  output += "Analysis time: " + report.analysis_time.to_string() + " s\n"
  output += "Critical findings: " + report.critical_count.to_string() + "\n"
  output += "Warnings: " + report.warning_count.to_string() + "\n\n"
  output += "Primary diagnosis: " + report.arbitration.primary_class
  output += " (" + percent(report.arbitration.overall_confidence) + ")\n"
  output += "Decision margin: " +
    percent(report.arbitration.decision_margin) +
    "\n"
  for cause in report.arbitration.causes {
    output += "  [" + cause.class + "] "
    output += percent(cause.confidence) + " -> "
    output += join_ids(cause.subject_ids) + "\n"
  }
  if report.arbitration.independent_evidence_sources.length() > 0 {
    output += "  independent evidence: "
    output += join_ids(report.arbitration.independent_evidence_sources) + "\n"
  }
  if report.arbitration.undetermined_reasons.length() > 0 {
    output += "  undetermined:\n"
    for reason in report.arbitration.undetermined_reasons {
      output += "    - " + reason + "\n"
    }
  }
  for conflict in report.arbitration.conflicts {
    output += "  conflict: " + conflict + "\n"
  }
  output += "Evidence scoring:\n"
  for contribution in report.arbitration.contributions {
    output += "  " + contribution.cause_class + "/" + contribution.feature
    output += " = " + contribution.weight.to_string() + "\n"
  }
  output += "\n"
  match report.topology {
    Some(topology) => {
      output += "Topology: " + topology.status + "\n"
      output += "  nodes=" + topology.node_count.to_string()
      output += " edges=" + topology.edge_count.to_string()
      output += " components=" + topology.connected_components.to_string()
      output += " cycles=" + topology.cycle_rank.to_string() + "\n"
    }
    None => output += "Topology: not supplied\n"
  }
  match report.outage {
    Some(outage) => {
      output += "\nOutage hypotheses: " +
        outage.faults.length().to_string() +
        "\n"
      for hypothesis in outage.faults {
        let candidate = hypothesis.candidate
        output += "  " + hypothesis.rank.to_string() + ". "
        output += candidate.edge_id + " [" + candidate.section + "] "
        output += "stage confidence " + percent(candidate.confidence) + "\n"
        output += "     affected: "
        output += join_ids(candidate.affected_meter_ids) + "\n"
      }
      if outage.residual_outage_meter_ids.length() > 0 {
        output += "  unexplained: "
        output += join_ids(outage.residual_outage_meter_ids) + "\n"
      }
    }
    None => output += "\nOutage hypotheses: not run\n"
  }
  output += "\nPhase findings: " +
    report.phase.findings.length().to_string() +
    "\n"
  for finding in report.phase.findings {
    output += "  [" + finding.severity + "] " + finding.node_id + " "
    output += finding.kind + ": " + finding.summary + "\n"
  }
  output += "\nPower-quality events: " +
    report.power_quality.events.length().to_string() +
    "\n"
  for event in report.power_quality.events {
    output += "  [" + event.severity + "] " + event.node_id + " "
    output += event.kind + " for " + event.duration_sec.to_string() + " s"
    output += ", deviation " + event.deviation_percent.to_string() + "%\n"
  }
  output += "\nTelemetry findings: " +
    report.telemetry.findings.length().to_string() +
    "\n"
  for finding in report.telemetry.findings {
    output += "  [" + finding.severity + "] " + finding.node_id + " "
    output += finding.kind + ": " + finding.summary + "\n"
  }
  if report.warnings.length() > 0 {
    output += "\nWarnings:\n"
    for warning in report.warnings {
      output += "  - " + warning + "\n"
    }
  }
  output
}

///|
fn analysis_json(
  document : @core.InputDocument,
  result : @core.InferenceResult,
) -> String {
  let object : Map[String, Json] = Map([
    ("network", @core.network_to_json(document.network)),
    ("analysed_observations", @core.observations_to_json(document.observations)),
    ("analysis", @core.result_to_json(result)),
  ])
  let restoration = match document.confirmed_fault_edge_id {
    Some(edge_id) => {
      let report = @core.verify_restoration(
        document.network,
        edge_id,
        document.observations,
        document.analysis_time,
      ) catch {
        _ => return Json::object(object).stringify(indent=2)
      }
      Some(@core.restore_to_json(report))
    }
    None => None
  }
  match restoration {
    Some(value) => object.set("restoration", value)
    None => ()
  }
  Json::object(object).stringify(indent=2)
}

///|
fn execute(options : CliOptions) -> Result[String, String] {
  let source = @fs.read_file_to_string(options.path) catch {
    @fs.IOError::IOError(message) =>
      return Err("cannot read '" + options.path + "': " + message)
  }
  match options.command {
    Diagnose => {
      let input = @core.parse_diagnostic_input(source) catch {
        error => return Err(error.describe())
      }
      let report = @core.run_diagnostic(input)
      if options.json_output {
        Ok(@core.diagnostic_json_string(report))
      } else {
        Ok(diagnostic_text(report))
      }
    }
    Analyze => {
      let document = @core.parse_input(source) catch {
        error => return Err(error.describe())
      }
      let result = @core.infer_faults(
        document.network,
        document.observations,
        document.analysis_time,
        policy=options.policy,
      ) catch {
        error => return Err(error.describe())
      }
      if options.json_output {
        Ok(analysis_json(document, result))
      } else {
        Ok(analyze_text(document, result))
      }
    }
    Verify => {
      let document = @core.parse_input(source) catch {
        error => return Err(error.describe())
      }
      let edge_id = match options.edge_id {
        Some(value) => value
        None =>
          match document.confirmed_fault_edge_id {
            Some(value) => value
            None =>
              return Err(
                "missing --edge and no confirmed_fault_edge_id in input",
              )
          }
      }
      let report = @core.verify_restoration(
        document.network,
        edge_id,
        document.observations,
        document.analysis_time,
      ) catch {
        error => return Err(error.describe())
      }
      if options.json_output {
        Ok(@core.restore_json_string(report))
      } else {
        Ok(restore_text(report))
      }
    }
  }
}

///|
fn main {
  let args = @env.args()
  if args.contains("--version") {
    println(@core.version())
    return
  }
  if args.contains("--help") {
    println(usage())
    return
  }
  let options = match parse_cli(args) {
    Ok(value) => value
    Err(error) => {
      eprintln("griddiagnose: " + cli_error_text(error))
      eprintln(usage())
      @env.exit(2)
      return
    }
  }
  match execute(options) {
    Ok(output) => println(output)
    Err(message) => {
      eprintln("griddiagnose: " + message)
      @env.exit(2)
    }
  }
}
