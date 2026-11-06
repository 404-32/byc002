///|
test "parser recognizes functions, types, fields, impls, and traits" {
  let source =
    #|// Generated using `moon info`, DON'T EDIT IT
    #|package "example/core"
    #|
    #|// Values
    #|pub fn parse(String, limit? : Int32) -> Config raise
    #|
    #|// Errors
    #|pub suberror ParseError derive(Show)
    #|
    #|// Types and methods
    #|pub(all) struct Config {
    #|  name : String
    #|  retries : Int32
    #|}
    #|pub impl Eq for Config
    #|
    #|// Traits
    #|pub(open) trait Encoder {
    #|  encode(Self) -> String
    #|}
  let snapshot = @mooncompat.parse_api(source, source_name="example.mbti")
  assert_eq(snapshot.package_id, "example/core")
  assert_eq(snapshot.declarations.length(), 6)
  assert_eq(snapshot.declarations[4].kind.label(), "struct")
  assert_eq(snapshot.declarations[4].name, "Config")
  assert_true(snapshot.declarations[4].canonical.contains("retries : Int32"))
  assert_eq(snapshot.source, "example.mbti")
}

///|
test "field and variant ordering does not change the canonical interface" {
  let first =
    #|package "example/core"
    #|pub(all) struct Config {
    #|  alpha : String
    #|  beta : Int32
    #|}
  let second =
    #|package "example/core"
    #|pub(all) struct Config {
    #|  beta : Int32
    #|  alpha : String
    #|}
  assert_eq(
    @mooncompat.parse_api(first).declarations[0].canonical,
    @mooncompat.parse_api(second).declarations[0].canonical,
  )
}

///|
test "private implementation fields are ignored" {
  let base =
    #|package "example/core"
    #|pub struct Secret {
    #|  value : String
    #|  // private fields
    #|}
  let head =
    #|package "example/core"
    #|pub struct Secret {
    #|  value : String
    #|  // private fields
    #|}
  let report = @mooncompat.compare_snapshots(
    @mooncompat.parse_api(base),
    @mooncompat.parse_api(head),
  )
  assert_false(report.has_breaking_changes())
  assert_eq(report.result(), "unchanged")
}

///|
test "missing package is rejected" {
  let message = try {
    ignore(@mooncompat.parse_api("pub fn parse(String) -> Unit"))
    "no error"
  } catch {
    Failure(message) => message
    _ => "unexpected error"
  }
  assert_true(message.contains("missing package"))
}

///|
test "unterminated block is rejected with a location" {
  let source =
    #|package "example/core"
    #|pub struct Broken {
    #|  value : String
  let message = try {
    ignore(@mooncompat.parse_api(source))
    "no error"
  } catch {
    Failure(message) => message
    _ => "unexpected error"
  }
  assert_true(message.contains("unterminated declaration block"))
}

///|
test "unknown public syntax fails closed instead of being ignored" {
  let source =
    #|package "example/core"
    #|pub quantum fn surprise() -> Unit
  let message = try {
    ignore(@mooncompat.parse_api(source))
    "no error"
  } catch {
    Failure(message) => message
    _ => "unexpected error"
  }
  assert_true(message.contains("unsupported .mbti public syntax"))
}
