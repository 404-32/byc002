///|
fn find_declaration(
  declarations : ArrayView[Declaration],
  key : String,
) -> Declaration? {
  for declaration in declarations {
    if declaration.key() == key {
      return Some(declaration)
    }
  }
  None
}

///|
fn sort_changes(changes : Array[Change]) -> Unit {
  let mut index = 1
  while index < changes.length() {
    let current = changes[index]
    let current_key = "\{current.severity.label()}:\{current.package_id}:\{current.name}"
    let mut insert_at = index
    while insert_at > 0 {
      let previous = changes[insert_at - 1]
      let previous_key = "\{previous.severity.label()}:\{previous.package_id}:\{previous.name}"
      if previous_key.lexical_compare(current_key) <= 0 {
        break
      }
      changes[insert_at] = previous
      insert_at = insert_at - 1
    }
    changes[insert_at] = current
    index = index + 1
  }
}

///|
pub fn compare_snapshots(
  base : ApiSnapshot,
  head : ApiSnapshot,
) -> CompatibilityReport {
  let changes : Array[Change] = []
  if base.package_id != head.package_id {
    changes.push({
      package_id: base.package_id,
      name: base.package_id,
      declaration_kind: "package",
      kind: PackageRenamed,
      severity: Breaking,
      before: base.package_id,
      after: head.package_id,
      message: "package name changed from \{base.package_id} to \{head.package_id}",
    })
  }
  let mut unchanged_count = 0
  for previous in base.declarations {
    match find_declaration(head.declarations, previous.key()) {
      None =>
        changes.push({
          package_id: base.package_id,
          name: previous.name,
          declaration_kind: previous.kind.label(),
          kind: Removed,
          severity: Breaking,
          before: previous.canonical,
          after: "",
          message: "removed public \{previous.kind.label()} `\{previous.name}`",
        })
      Some(current) =>
        if previous.canonical == current.canonical {
          unchanged_count = unchanged_count + 1
        } else {
          changes.push({
            package_id: base.package_id,
            name: previous.name,
            declaration_kind: previous.kind.label(),
            kind: DeclarationChanged,
            severity: Breaking,
            before: previous.canonical,
            after: current.canonical,
            message: "changed public \{previous.kind.label()} `\{previous.name}`",
          })
        }
    }
  }
  for current in head.declarations {
    if find_declaration(base.declarations, current.key()) is None {
      changes.push({
        package_id: head.package_id,
        name: current.name,
        declaration_kind: current.kind.label(),
        kind: Added,
        severity: Compatible,
        before: "",
        after: current.canonical,
        message: "added public \{current.kind.label()} `\{current.name}`",
      })
    }
  }
  sort_changes(changes)
  let mut breaking_count = 0
  let mut compatible_count = 0
  for change in changes {
    match change.severity {
      Breaking => breaking_count = breaking_count + 1
      Compatible => compatible_count = compatible_count + 1
    }
  }
  {
    base_package: base.package_id,
    head_package: head.package_id,
    changes,
    breaking_count,
    compatible_count,
    unchanged_count,
  }
}

///|
fn find_snapshot(
  snapshots : ArrayView[ApiSnapshot],
  package_id : String,
) -> ApiSnapshot? {
  for snapshot in snapshots {
    if snapshot.package_id == package_id {
      return Some(snapshot)
    }
  }
  None
}

///|
fn append_report(target : Array[Change], report : CompatibilityReport) -> Int32 {
  for change in report.changes {
    target.push(change)
  }
  report.unchanged_count
}

///|
pub fn compare_api_sets(
  base : Array[ApiSnapshot],
  head : Array[ApiSnapshot],
  base_label~ : String,
  head_label~ : String,
) -> CompatibilityReport {
  let changes : Array[Change] = []
  let mut unchanged_count = 0
  let single_package_rename = base.length() == 1 &&
    head.length() == 1 &&
    base[0].package_id != head[0].package_id
  if single_package_rename {
    let report = compare_snapshots(base[0], head[0])
    unchanged_count = unchanged_count + append_report(changes, report)
  } else {
    for previous in base {
      let report = match find_snapshot(head, previous.package_id) {
        Some(current) => compare_snapshots(previous, current)
        None =>
          compare_snapshots(previous, {
            package_id: previous.package_id,
            declarations: [],
            source: "<missing>",
          })
      }
      unchanged_count = unchanged_count + append_report(changes, report)
    }
    for current in head {
      if find_snapshot(base, current.package_id) is None {
        let report = compare_snapshots(
          {
            package_id: current.package_id,
            declarations: [],
            source: "<missing>",
          },
          current,
        )
        ignore(append_report(changes, report))
      }
    }
  }
  sort_changes(changes)
  let mut breaking_count = 0
  let mut compatible_count = 0
  for change in changes {
    match change.severity {
      Breaking => breaking_count = breaking_count + 1
      Compatible => compatible_count = compatible_count + 1
    }
  }
  {
    base_package: base_label,
    head_package: head_label,
    changes,
    breaking_count,
    compatible_count,
    unchanged_count,
  }
}
