///|
const TOOL_VERSION : String = "0.1.0"

///|
struct CliConfig {
  command : String
  base : String
  head : String
  format : String
  output : String?
  fail_on : String
  verbose : Bool
}

///|
fn require_next(
  args : Array[String],
  index : Int32,
  option : String,
) -> String raise {
  guard index + 1 < args.length() else {
    raise Failure("option `\{option}` requires a value")
  }
  args[index + 1]
}

///|
fn parse_args(args : Array[String]) -> CliConfig raise {
  guard args.length() > 1 else {
    return {
      command: "help",
      base: "",
      head: "",
      format: "text",
      output: None,
      fail_on: "breaking",
      verbose: true,
    }
  }
  let command = args[1]
  if command == "--help" || command == "-h" || command == "help" {
    return {
      command: "help",
      base: "",
      head: "",
      format: "text",
      output: None,
      fail_on: "breaking",
      verbose: true,
    }
  }
  if command == "--version" || command == "version" {
    return {
      command: "version",
      base: "",
      head: "",
      format: "text",
      output: None,
      fail_on: "breaking",
      verbose: true,
    }
  }
  if command == "rules" {
    return {
      command: "rules",
      base: "",
      head: "",
      format: "text",
      output: None,
      fail_on: "breaking",
      verbose: true,
    }
  }
  guard command == "check" || command == "snapshot" else {
    raise Failure("unknown command `\{command}`; run `mooncompat help`")
  }
  let positionals : Array[String] = []
  let mut format = "text"
  let mut output : String? = None
  let mut fail_on = "breaking"
  let mut verbose = true
  let mut index = 2
  while index < args.length() {
    let argument = args[index]
    if argument == "--format" {
      format = require_next(args, index, "--format")
      index = index + 2
    } else if argument.has_prefix("--format=") {
      format = argument[9:].to_owned()
      index = index + 1
    } else if argument == "--output" || argument == "-o" {
      output = Some(require_next(args, index, argument))
      index = index + 2
    } else if argument.has_prefix("--output=") {
      output = Some(argument[9:].to_owned())
      index = index + 1
    } else if argument == "--fail-on" {
      fail_on = require_next(args, index, "--fail-on")
      index = index + 2
    } else if argument.has_prefix("--fail-on=") {
      fail_on = argument[10:].to_owned()
      index = index + 1
    } else if argument == "--quiet" || argument == "-q" {
      verbose = false
      index = index + 1
    } else if argument == "--help" || argument == "-h" {
      return {
        command: "help",
        base: "",
        head: "",
        format: "text",
        output: None,
        fail_on: "breaking",
        verbose: true,
      }
    } else if argument.has_prefix("-") {
      raise Failure("unknown option `\{argument}`")
    } else {
      positionals.push(argument)
      index = index + 1
    }
  }
  guard format == "text" || format == "json" else {
    raise Failure("unsupported format `\{format}`; expected text or json")
  }
  guard fail_on == "breaking" || fail_on == "never" else {
    raise Failure("unsupported --fail-on value `\{fail_on}`")
  }
  if command == "snapshot" {
    guard positionals.length() == 1 else {
      raise Failure("snapshot expects exactly one path")
    }
    {
      command,
      base: positionals[0],
      head: "",
      format: "json",
      output,
      fail_on,
      verbose,
    }
  } else {
    guard positionals.length() == 2 else {
      raise Failure("check expects a base path and a head path")
    }
    {
      command,
      base: positionals[0],
      head: positionals[1],
      format,
      output,
      fail_on,
      verbose,
    }
  }
}

///|
fn help_text() -> String {
  let text =
    #|MoonCompat 0.1.0 - MoonBit public API compatibility guard
    #|
    #|Usage:
    #|  mooncompat check <base-path> <head-path> [options]
    #|  mooncompat snapshot <path> [--output report.json]
    #|  mooncompat rules
    #|  mooncompat version
    #|
    #|Paths may point to a .mbti file or a directory containing .mbti files.
    #|Directories are scanned recursively; .git, .mooncakes, _build and target
    #|directories are ignored.
    #|
    #|Check options:
    #|  --format text|json       Report format (default: text)
    #|  -o, --output FILE        Write the report to FILE
    #|  --fail-on breaking|never Exit 1 on breaking changes (default: breaking)
    #|  -q, --quiet              Hide before/after signatures in text output
    #|
    #|Exit codes:
    #|  0  no breaking changes, or --fail-on=never
    #|  1  breaking changes detected
    #|  2  invalid input, parse failure, or I/O error
  text
}

///|
fn rules_text() -> String {
  let text =
    #|MoonCompat v0.1 compatibility policy
    #|
    #|Breaking changes:
    #|  - removing or renaming a public declaration
    #|  - changing a public function or method signature
    #|  - changing public struct fields, enum variants, traits, errors, or type aliases
    #|  - removing a public trait implementation
    #|  - changing the package identifier
    #|
    #|Compatible additions:
    #|  - adding a new public declaration
    #|
    #|No public declaration changes:
    #|  - internal implementation-only changes, including changes omitted by `moon info`
    #|
    #|Field, variant, and trait member order is ignored. Private fields omitted from
    #|the generated .mbti are outside this check's API surface.
  text
}

///|
fn is_ignored_path(path : StringView) -> Bool {
  path.contains("/.git/") ||
  path.contains("\\.git\\") ||
  path.contains("/.mooncakes/") ||
  path.contains("\\.mooncakes\\") ||
  path.contains("/_build/") ||
  path.contains("\\_build\\") ||
  path.contains("/target/") ||
  path.contains("\\target\\")
}

///|
fn join_path(directory : StringView, name : StringView) -> String {
  if directory.is_empty() {
    name.to_owned()
  } else if directory.has_suffix("/") || directory.has_suffix("\\") {
    "\{directory}\{name}"
  } else {
    "\{directory}/\{name}"
  }
}

///|
async fn mbti_files(path : StringView) -> Array[String] {
  let files : Array[String] = []
  match @fs.kind(path) {
    Regular => {
      guard path.has_suffix(".mbti") else {
        raise Failure("expected a .mbti file, got `\{path}`")
      }
      files.push(path.to_owned())
    }
    Directory =>
      @fs.walk(
        path,
        fn(directory, names) {
          for name in names {
            if name.has_suffix(".mbti") {
              files.push(join_path(directory, name))
            }
          }
        },
        exclude=fn(candidate) { is_ignored_path(candidate) },
        max_concurrency=4,
      )
    _ => raise Failure("unsupported filesystem entry `\{path}`")
  }
  files.sort()
  files
}

///|
async fn load_snapshots(path : StringView) -> Array[@mooncompat.ApiSnapshot] {
  let snapshots : Array[@mooncompat.ApiSnapshot] = []
  for file in mbti_files(path) {
    let source = @fs.read_file(file).text()
    snapshots.push(@mooncompat.parse_api(source, source_name=file))
  }
  guard !snapshots.is_empty() else {
    raise Failure("no .mbti files found under `\{path}`")
  }
  snapshots
}

///|
async fn emit(text : String, output : String?) -> Unit {
  match output {
    Some(path) => @fs.write_file(path, text)
    None => @stdio.stdout.write(text)
  }
}

///|
async fn run(config : CliConfig) -> Int32 {
  match config.command {
    "help" => {
      @stdio.stdout.write(help_text())
      0
    }
    "version" => {
      @stdio.stdout.write("MoonCompat \{TOOL_VERSION}\n")
      0
    }
    "rules" => {
      @stdio.stdout.write(rules_text())
      0
    }
    "snapshot" => {
      let snapshots = load_snapshots(config.base)
      guard snapshots.length() == 1 else {
        raise Failure(
          "snapshot expects one package, found \{snapshots.length()} packages; pass a single .mbti file",
        )
      }
      let rendered = @mooncompat.render_snapshot_json(snapshots[0]) + "\n"
      emit(rendered, config.output)
      0
    }
    "check" => {
      let base = load_snapshots(config.base)
      let head = load_snapshots(config.head)
      let report = @mooncompat.compare_api_sets(
        base,
        head,
        base_label=config.base,
        head_label=config.head,
      )
      let rendered = if config.format == "json" {
        @mooncompat.render_report_json(report) + "\n"
      } else {
        @mooncompat.render_report_text(report, verbose=config.verbose)
      }
      emit(rendered, config.output)
      if report.has_breaking_changes() && config.fail_on == "breaking" {
        1
      } else {
        0
      }
    }
    _ => raise Failure("unreachable command")
  }
}

///|
#cfg(target="wasm")
fn runtime_wasm_exit(code : Int32) -> Unit = "wasi_snapshot_preview1" "proc_exit"

///|
#cfg(target="wasm-gc")
fn runtime_wasm_exit(code : Int32) -> Unit = "__moonbit_sys_unstable" "exit"

///|
#cfg(any(target="wasm", target="wasm-gc"))
fn runtime_exit(code : Int32) -> Unit {
  runtime_wasm_exit(code)
}

///|
#cfg(any(target="native", target="llvm"))
extern "c" fn runtime_native_exit(code : Int32) = "exit"

///|
#cfg(any(target="native", target="llvm"))
fn runtime_exit(code : Int32) -> Unit {
  runtime_native_exit(code)
}

///|
#cfg(target="js")
extern "js" fn runtime_js_exit(code : Int32) -> Unit =
  #| function(code) {
  #|   if (typeof process !== "undefined" && typeof process.exit === "function") {
  #|     process.exit(code);
  #|   }
  #| }

///|
#cfg(target="js")
fn runtime_exit(code : Int32) -> Unit {
  runtime_js_exit(code)
}

///|
async fn main {
  let exit_code = run(parse_args(@env.args())) catch {
    Failure(message) => {
      @stdio.stderr.write("error: \{message}\n")
      2
    }
    error => {
      @stdio.stderr.write("error: \{error}\n")
      2
    }
  }
  runtime_exit(exit_code)
}
