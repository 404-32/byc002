///|
fn change_to_json(change : Change) -> Json {
  {
    "package": change.package_id,
    "name": change.name,
    "declaration_kind": change.declaration_kind,
    "kind": change.kind.label(),
    "severity": change.severity.label(),
    "before": change.before,
    "after": change.after,
    "message": change.message,
  }
}

///|
pub fn report_to_json(report : CompatibilityReport) -> Json {
  let changes = Json::array(report.changes.map(change_to_json))
  {
    "schema_version": 1,
    "tool": "mooncompat",
    "parser_version": PARSER_VERSION,
    "base_package": report.base_package,
    "head_package": report.head_package,
    "result": report.result(),
    "recommended_bump": report.recommended_bump().label(),
    "summary": {
      "breaking": report.breaking_count,
      "compatible": report.compatible_count,
      "unchanged": report.unchanged_count,
    },
    "changes": changes,
  }
}

///|
pub fn render_report_json(report : CompatibilityReport) -> String {
  report_to_json(report).stringify(escape_slash=true, indent=2)
}

///|
pub fn render_report_text(
  report : CompatibilityReport,
  verbose~ : Bool = true,
) -> String {
  let out = StringBuilder()
  out.write_string(
    "MoonCompat: \{report.base_package} -> \{report.head_package}\n",
  )
  if report.changes.is_empty() {
    out.write_string("No public API changes detected.\n")
  } else {
    for change in report.changes {
      out.write_string(
        "\{change.severity.label().to_upper()}: \{change.message}\n",
      )
      if verbose {
        if !change.before.is_empty() {
          out.write_string("  before: \{change.before}\n")
        }
        if !change.after.is_empty() {
          out.write_string("  after:  \{change.after}\n")
        }
      }
    }
  }
  out.write_string(
    "\nSummary: \{report.breaking_count} breaking, \{report.compatible_count} compatible, \{report.unchanged_count} unchanged\n",
  )
  out.write_string("Recommended bump: \{report.recommended_bump().label()}\n")
  out.to_string()
}

///|
pub fn snapshot_to_json(snapshot : ApiSnapshot) -> Json {
  let declarations = Json::array(
    snapshot.declarations.map(fn(declaration) {
      {
        "kind": declaration.kind.label(),
        "name": declaration.name,
        "canonical": declaration.canonical,
        "line": Json::number(declaration.line.to_double()),
      }
    }),
  )
  {
    "schema_version": 1,
    "tool": "mooncompat",
    "parser_version": PARSER_VERSION,
    "package": snapshot.package_id,
    "declarations": declarations,
  }
}

///|
pub fn render_snapshot_json(snapshot : ApiSnapshot) -> String {
  snapshot_to_json(snapshot).stringify(escape_slash=true, indent=2)
}
