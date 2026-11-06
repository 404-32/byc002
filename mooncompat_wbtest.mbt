///|
test "whitespace is canonicalized" {
  assert_eq(collapse_whitespace("  pub   fn  parse  "), "pub fn parse")
}

///|
test "string ordering is lexical" {
  assert_true("function:a".lexical_compare("type:a") < 0)
}

///|
test "generic function names skip type parameters" {
  let source =
    #|package "example/core"
    #|pub fn[R : Reader] decode(R, mode? : Int32) -> String
  let snapshot = parse_api(source)
  assert_eq(snapshot.declarations[0].name, "decode")
}

///|
test "breaking changes take precedence over additive changes" {
  let base =
    #|package "example/core"
    #|pub fn parse(String) -> String
  let head =
    #|package "example/core"
    #|pub fn parse(String, Bool) -> String
    #|pub fn format(String) -> String
  let report = compare_snapshots(parse_api(base), parse_api(head))
  assert_eq(report.breaking_count, 1)
  assert_eq(report.compatible_count, 1)
  assert_eq(report.recommended_bump().label(), "major")
}

///|
test "method names include the receiver type" {
  let source =
    #|package "example/core"
    #|type File
    #|pub fn File::size(Self) -> Int64
    #|pub async fn File::read(Self) -> Bytes
  let snapshot = parse_api(source)
  assert_eq(snapshot.declarations[0].name, "File::read")
  assert_eq(snapshot.declarations[1].name, "File::size")
}

///|
test "Int aliases are normalized to Int32" {
  let source =
    #|package "example/core"
    #|pub fn size(Int) -> Int
    #|pub fn wide(Int64) -> UInt
  let snapshot = parse_api(source)
  assert_eq(snapshot.declarations[0].canonical, "pub fn size(Int32) -> Int32")
  assert_eq(snapshot.declarations[1].canonical, "pub fn wide(Int64) -> UInt32")
}

///|
test "prelude Json aliases are platform-independent" {
  let plain =
    #|package "example/core"
    #|pub fn report() -> Json
  let qualified =
    #|package "example/core"
    #|pub fn report() -> @json.Json
  assert_eq(
    parse_api(plain).declarations[0].canonical,
    parse_api(qualified).declarations[0].canonical,
  )
}

///|
test "public constants and re-exports are part of the API surface" {
  let source =
    #|package "example/core"
    #|pub const LIMIT : Int32 = 10
    #|pub using @builtin {type Array as Vec}
  let snapshot = parse_api(source)
  assert_eq(snapshot.declarations.length(), 2)
  assert_eq(snapshot.declarations[1].name, "LIMIT")
  assert_true(snapshot.declarations[0].canonical.contains("pub using"))
}

///|
test "moving a derived trait to an explicit impl is not a breaking change" {
  let base =
    #|package "example/core"
    #|type Zone derive(Eq, @debug.Debug)
  let head =
    #|package "example/core"
    #|type Zone derive(@debug.Debug)
    #|pub impl Eq for Zone
  let report = compare_snapshots(parse_api(base), parse_api(head))
  assert_eq(report.breaking_count, 0)
  assert_eq(report.compatible_count, 0)
  assert_eq(report.unchanged_count, 3)
}

///|
test "adding a trait implementation is compatible" {
  let base =
    #|package "example/core"
    #|pub struct Message {
    #|  value : String
    #|}
  let head =
    #|package "example/core"
    #|pub struct Message {
    #|  value : String
    #|}
    #|pub impl Show for Message
  let report = compare_snapshots(parse_api(base), parse_api(head))
  assert_eq(report.compatible_count, 1)
  assert_eq(report.recommended_bump().label(), "minor")
}

///|
test "removing a trait implementation is breaking" {
  let base =
    #|package "example/core"
    #|pub struct Message {
    #|  value : String
    #|}
    #|pub impl Show for Message
  let head =
    #|package "example/core"
    #|pub struct Message {
    #|  value : String
    #|}
  let report = compare_snapshots(parse_api(base), parse_api(head))
  assert_eq(report.breaking_count, 1)
  assert_eq(report.changes[0].name, "Show for Message")
}

///|
test "removing a public struct field is breaking" {
  let base =
    #|package "example/core"
    #|pub(all) struct Point {
    #|  x : Int32
    #|  y : Int32
    #|}
  let head =
    #|package "example/core"
    #|pub(all) struct Point {
    #|  x : Int32
    #|}
  let report = compare_snapshots(parse_api(base), parse_api(head))
  assert_eq(report.breaking_count, 1)
  assert_eq(report.changes[0].declaration_kind, "struct")
}

///|
test "trait method changes are breaking" {
  let base =
    #|package "example/core"
    #|pub(open) trait Encoder {
    #|  encode(Self) -> String
    #|}
  let head =
    #|package "example/core"
    #|pub(open) trait Encoder {
    #|  encode(Self, Int32) -> String
    #|}
  let report = compare_snapshots(parse_api(base), parse_api(head))
  assert_eq(report.breaking_count, 1)
  assert_eq(report.changes[0].declaration_kind, "trait")
}

///|
test "comments and declaration order do not affect compatibility" {
  let base =
    #|package "example/core"
    #|pub fn first() -> Unit
    #|pub fn second() -> Unit
  let head =
    #|package "example/core"
    #|// Documentation changed only.
    #|pub fn second() -> Unit
    #|pub fn first() -> Unit
  let report = compare_snapshots(parse_api(base), parse_api(head))
  assert_eq(report.breaking_count, 0)
  assert_eq(report.compatible_count, 0)
  assert_eq(report.unchanged_count, 2)
}

///|
test "empty APIs are valid and unchanged" {
  let source =
    #|package "example/empty"
  let base = parse_api(source)
  let head = parse_api(source)
  let report = compare_snapshots(base, head)
  assert_eq(report.result(), "unchanged")
  assert_eq(report.recommended_bump().label(), "patch")
}

///|
test "snapshot JSON records normalized declarations" {
  let source =
    #|package "example/core"
    #|pub fn size(Int) -> Int
  let snapshot = parse_api(source)
  let json = render_snapshot_json(snapshot)
  assert_true(json.contains("\"package\": \"example\\/core\""))
  assert_true(json.contains("\"canonical\": \"pub fn size(Int32) -> Int32\""))
}

///|
test "adding an enum variant is breaking because exhaustive matches may fail" {
  let base =
    #|package "example/core"
    #|pub(all) enum Status {
    #|  Ready
    #|  Failed
    #|}
  let head =
    #|package "example/core"
    #|pub(all) enum Status {
    #|  Ready
    #|  Failed
    #|  Cancelled
    #|}
  let report = compare_snapshots(parse_api(base), parse_api(head))
  assert_eq(report.breaking_count, 1)
}

///|
test "changing a return type is breaking" {
  let base =
    #|package "example/core"
    #|pub fn count() -> Int32
  let head =
    #|package "example/core"
    #|pub fn count() -> Int64
  let report = compare_snapshots(parse_api(base), parse_api(head))
  assert_eq(report.breaking_count, 1)
  assert_true(report.changes[0].before.contains("Int32"))
  assert_true(report.changes[0].after.contains("Int64"))
}

///|
test "removing an abstract type is breaking" {
  let base =
    #|package "example/core"
    #|type Handle
  let head =
    #|package "example/core"
  let report = compare_snapshots(parse_api(base), parse_api(head))
  assert_eq(report.breaking_count, 1)
  assert_eq(report.changes[0].declaration_kind, "type")
}

///|
test "changing sync to async is breaking" {
  let base =
    #|package "example/core"
    #|pub fn load(String) -> String
  let head =
    #|package "example/core"
    #|pub async fn load(String) -> String
  let report = compare_snapshots(parse_api(base), parse_api(head))
  assert_eq(report.breaking_count, 1)
}

///|
test "changing a public error constructor is breaking" {
  let base =
    #|package "example/core"
    #|pub(all) suberror ParseError {
    #|  EmptyInput
    #|}
  let head =
    #|package "example/core"
    #|pub(all) suberror ParseError {
    #|  EmptyInput
    #|  InvalidUtf8
    #|}
  let report = compare_snapshots(parse_api(base), parse_api(head))
  assert_eq(report.breaking_count, 1)
  assert_eq(report.changes[0].declaration_kind, "error")
}

///|
test "removed declarations are breaking" {
  let base =
    #|package "example/core"
    #|pub fn old_api() -> Unit
    #|pub fn stable() -> Unit
  let head =
    #|package "example/core"
    #|pub fn stable() -> Unit
  let report = compare_snapshots(parse_api(base), parse_api(head))
  assert_eq(report.breaking_count, 1)
  assert_eq(report.unchanged_count, 1)
  assert_eq(report.changes[0].kind.label(), "removed")
  assert_eq(report.changes[0].name, "old_api")
}

///|
test "added declarations recommend a minor bump" {
  let base =
    #|package "example/core"
    #|pub fn parse(String) -> String
  let head =
    #|package "example/core"
    #|pub fn parse(String) -> String
    #|pub fn format(String) -> String
  let report = compare_snapshots(parse_api(base), parse_api(head))
  assert_eq(report.result(), "compatible")
  assert_eq(report.recommended_bump().label(), "minor")
}

///|
test "package rename is breaking" {
  let base =
    #|package "example/old"
    #|pub fn parse(String) -> String
  let head =
    #|package "example/new"
    #|pub fn parse(String) -> String
  let report = compare_snapshots(parse_api(base), parse_api(head))
  assert_eq(report.breaking_count, 1)
  assert_eq(report.changes[0].kind.label(), "package_renamed")
}

///|
test "JSON report has stable machine-readable fields" {
  let base =
    #|package "example/core"
    #|pub fn parse(String) -> String
  let head =
    #|package "example/core"
    #|pub fn parse(String, Bool) -> String
  let json = render_report_json(
    compare_snapshots(parse_api(base), parse_api(head)),
  )
  assert_true(json.contains("\"schema_version\": 1"))
  assert_true(json.contains("\"result\": \"breaking\""))
  assert_true(json.contains("\"recommended_bump\": \"major\""))
  assert_true(json.contains("\"kind\": \"declaration_changed\""))
}

///|
test "text report explains before and after signatures" {
  let base =
    #|package "example/core"
    #|pub fn parse(String) -> String
  let head =
    #|package "example/core"
    #|pub fn parse(String, Bool) -> String
  let text = render_report_text(
    compare_snapshots(parse_api(base), parse_api(head)),
  )
  assert_true(text.contains("BREAKING: changed public function `parse`"))
  assert_true(text.contains("before: pub fn parse(String) -> String"))
  assert_true(text.contains("after:  pub fn parse(String, Bool) -> String"))
}

///|
test "multi-package comparison handles missing and added packages" {
  let kept =
    #|package "example/kept"
    #|pub fn stable() -> Unit
  let removed =
    #|package "example/removed"
    #|pub fn gone() -> Unit
  let added =
    #|package "example/added"
    #|pub fn fresh() -> Unit
  let base = [parse_api(kept), parse_api(removed)]
  let head = [parse_api(kept), parse_api(added)]
  let report = compare_api_sets(
    base,
    head,
    base_label="base",
    head_label="head",
  )
  assert_eq(report.breaking_count, 1)
  assert_eq(report.compatible_count, 1)
  assert_eq(report.unchanged_count, 1)
  assert_eq(report.changes[0].name, "gone")
  assert_eq(report.changes[1].name, "fresh")
}
