///|
const PARSER_VERSION : String = "mbti-v1"

///|
fn collapse_whitespace(text : StringView) -> String {
  let out = StringBuilder(size_hint=text.length())
  let mut pending_space = false
  for ch in text {
    if ch.is_whitespace() {
      pending_space = !out.is_empty()
    } else {
      if pending_space {
        out.write_char(' ')
        pending_space = false
      }
      out.write_char(ch)
    }
  }
  out
  .to_string()
  .replace_all(old="@json.Json", new="Json")
  .replace_all(old="@builtin.Json", new="Json")
  .replace_all(old="@json.ToJson", new="ToJson")
  .replace_all(old="@builtin.ToJson", new="ToJson")
  .replace_all(old="@json.FromJson", new="FromJson")
  .replace_all(old="@builtin.FromJson", new="FromJson")
}

///|
fn between_quotes(line : StringView, context : String) -> String raise {
  let first = match line.find("\"") {
    Some(index) => index
    None =>
      raise Failure("invalid .mbti: \{context} is missing an opening quote")
  }
  let rest = line[first + 1:]
  let second = match rest.find("\"") {
    Some(index) => index
    None =>
      raise Failure("invalid .mbti: \{context} is missing a closing quote")
  }
  rest[:second].to_owned()
}

///|
fn brace_delta(line : StringView) -> Int32 {
  let mut depth = 0
  for ch in line {
    match ch {
      '{' => depth = depth + 1
      '}' => depth = depth - 1
      _ => ()
    }
  }
  depth
}

///|
fn is_ascii_space_code(code : UInt16) -> Bool {
  code == 32 || (code >= 9 && code <= 13)
}

///|
fn is_declaration_start(line : StringView) -> Bool {
  line.has_prefix("pub fn") ||
  line.has_prefix("pub async fn") ||
  line.has_prefix("pub let") ||
  line.has_prefix("pub const") ||
  line.has_prefix("pub using") ||
  line.has_prefix("pub impl") ||
  line.has_prefix("pub struct") ||
  line.has_prefix("pub enum") ||
  line.has_prefix("pub type") ||
  line.has_prefix("pub suberror") ||
  line.has_prefix("pub trait") ||
  line.has_prefix("pub(all)") ||
  line.has_prefix("pub(open)") ||
  line.has_prefix("type ")
}

///|
fn declaration_kind(line : StringView) -> DeclarationKind {
  if line.has_prefix("pub fn") || line.has_prefix("pub async fn") {
    Function
  } else if line.contains("struct") {
    Struct
  } else if line.contains("enum") {
    Enum
  } else if line.contains("suberror") || line.contains(" error ") {
    Error
  } else if line.contains("trait") {
    Trait
  } else if line.has_prefix("pub impl") || line.contains(" impl") {
    Impl
  } else if line.contains(" let ") ||
    line.has_prefix("pub let") ||
    line.has_prefix("pub const") {
    Value
  } else if line.has_prefix("pub using") {
    Other
  } else if line.contains(" type ") || line.has_prefix("type ") {
    Type
  } else {
    Other
  }
}

///|
fn next_token_after_marker(
  line : StringView,
  marker : StringView,
) -> String raise {
  let marker_at = match line.find(marker) {
    Some(index) => index
    None => raise Failure("invalid .mbti declaration: missing `\{marker}`")
  }
  let mut index = marker_at + marker.length()
  while index < line.length() && is_ascii_space_code(line[index]) {
    index = index + 1
  }
  if index < line.length() && line[index] == '[' {
    let mut bracket_depth = 0
    while index < line.length() {
      match line[index] {
        '[' => bracket_depth = bracket_depth + 1
        ']' => {
          bracket_depth = bracket_depth - 1
          if bracket_depth == 0 {
            index = index + 1
            break
          }
        }
        _ => ()
      }
      index = index + 1
    }
    while index < line.length() && is_ascii_space_code(line[index]) {
      index = index + 1
    }
  }
  let start = index
  while index < line.length() &&
        !is_ascii_space_code(line[index]) &&
        line[index] != '(' &&
        line[index] != '{' &&
        line[index] != '[' {
    index = index + 1
  }
  guard index > start else {
    raise Failure("invalid .mbti declaration: cannot read name from `\{line}`")
  }
  line[start:index].to_owned()
}

///|
fn impl_name(line : StringView) -> String raise {
  let marker_at = match line.find("impl") {
    Some(index) => index
    None => raise Failure("invalid .mbti declaration: missing `impl`")
  }
  let mut index = marker_at + 4
  while index < line.length() && is_ascii_space_code(line[index]) {
    index = index + 1
  }
  if index < line.length() && line[index] == '[' {
    let mut depth = 0
    while index < line.length() {
      match line[index] {
        '[' => depth = depth + 1
        ']' => {
          depth = depth - 1
          if depth == 0 {
            index = index + 1
            break
          }
        }
        _ => ()
      }
      index = index + 1
    }
    while index < line.length() && is_ascii_space_code(line[index]) {
      index = index + 1
    }
  }
  line[index:].trim().to_owned()
}

///|
fn declaration_name(line : StringView, kind : DeclarationKind) -> String raise {
  match kind {
    Function => next_token_after_marker(line, "fn")
    Struct => next_token_after_marker(line, "struct")
    Enum => next_token_after_marker(line, "enum")
    Error =>
      if line.contains("suberror") {
        next_token_after_marker(line, "suberror")
      } else {
        line.to_owned()
      }
    Trait => next_token_after_marker(line, "trait")
    Type => next_token_after_marker(line, "type")
    Value =>
      if line.has_prefix("pub const") {
        next_token_after_marker(line, "const")
      } else {
        next_token_after_marker(line, "let")
      }
    Impl => impl_name(line)
    Other => line.to_owned()
  }
}

///|
fn normalize_type_aliases(text : String) -> String {
  let out = StringBuilder(size_hint=text.length())
  let token = StringBuilder()
  for ch in text {
    if ch.is_ascii_alphabetic() || ch.is_ascii_digit() || ch == '_' {
      token.write_char(ch)
    } else {
      if token.to_string() == "Int" {
        out.write_string("Int32")
      } else if token.to_string() == "UInt" {
        out.write_string("UInt32")
      } else {
        out.write_string(token.to_string())
      }
      token.reset()
      out.write_char(ch)
    }
  }
  if token.to_string() == "Int" {
    out.write_string("Int32")
  } else if token.to_string() == "UInt" {
    out.write_string("UInt32")
  } else {
    out.write_string(token.to_string())
  }
  out.to_string()
}

///|
fn sort_strings(values : Array[String]) -> Unit {
  let mut index = 1
  while index < values.length() {
    let current = values[index]
    let mut insert_at = index
    while insert_at > 0 && values[insert_at - 1].lexical_compare(current) > 0 {
      values[insert_at] = values[insert_at - 1]
      insert_at = insert_at - 1
    }
    values[insert_at] = current
    index = index + 1
  }
}

///|
fn split_derive_traits(content : StringView) -> Array[String] {
  let traits : Array[String] = []
  let current = StringBuilder()
  let mut in_arguments = false
  for ch in content {
    match ch {
      '(' => in_arguments = true
      ')' => in_arguments = false
      ',' if !in_arguments => {
        let trait_name = current.to_string().trim().to_owned()
        if !trait_name.is_empty() {
          traits.push(trait_name)
        }
        current.reset()
      }
      _ => if !in_arguments { current.write_char(ch) }
    }
  }
  let trait_name = current.to_string().trim().to_owned()
  if !trait_name.is_empty() {
    traits.push(trait_name)
  }
  traits
}

///|
fn strip_derive(
  canonical : String,
  type_name : String,
) -> (String, Array[Declaration]) {
  let marker_at = match canonical.find(" derive(") {
    Some(index) => index
    None => return (canonical, [])
  }
  let content_start = marker_at + " derive(".length()
  let mut index = content_start
  let mut depth = 1
  while index < canonical.length() && depth > 0 {
    match canonical[index] {
      '(' => depth = depth + 1
      ')' => depth = depth - 1
      _ => ()
    }
    index = index + 1
  }
  let derived = split_derive_traits(canonical[content_start:index - 1])
  let stripped = canonical[:marker_at].trim().to_owned()
  let implementation_names : Array[Declaration] = derived.map(fn(trait_name) {
    {
      kind: Impl,
      name: "\{trait_name} for \{type_name}",
      canonical: "pub impl \{trait_name} for \{type_name}",
      line: 0,
    }
  })
  (stripped, implementation_names)
}

///|
fn canonical_declaration(block : ArrayView[String]) -> String raise {
  guard block.length() > 0 else {
    raise Failure("invalid .mbti: empty declaration")
  }
  if block.length() == 1 {
    return normalize_type_aliases(collapse_whitespace(block[0]))
  }
  let first = collapse_whitespace(block[0])
  guard first.contains("{") &&
    collapse_whitespace(block[block.length() - 1]) == "}" else {
    return normalize_type_aliases(
      block.map(fn(line) { collapse_whitespace(line) }).join(" "),
    )
  }
  let body : Array[String] = []
  for index in 1..<(block.length() - 1) {
    let line = collapse_whitespace(block[index])
    if !line.is_empty() && !line.has_prefix("//") {
      body.push(line)
    }
  }
  sort_strings(body)
  normalize_type_aliases("\{first} \{body.join("; ")} }")
}

///|
fn make_declarations(
  block : Array[String],
  line_number : Int32,
) -> Array[Declaration] raise {
  let first = block[0]
  let kind = declaration_kind(first)
  let name = declaration_name(first, kind)
  let (canonical, derived_implementations) = strip_derive(
    canonical_declaration(block),
    name,
  )
  let declarations = [{ kind, name, canonical, line: line_number, }]
  for implementation in derived_implementations {
    declarations.push({ ..implementation, line: line_number, })
  }
  declarations
}

///|
fn append_declarations(
  target : Array[Declaration],
  declarations : Array[Declaration],
) -> Unit {
  for declaration in declarations {
    target.push(declaration)
  }
}

///|
fn deduplicate_declarations(
  declarations : Array[Declaration],
) -> Array[Declaration] {
  let unique : Array[Declaration] = []
  for declaration in declarations {
    let mut duplicate = false
    for existing in unique {
      if existing.key() == declaration.key() {
        duplicate = true
        break
      }
    }
    if !duplicate {
      unique.push(declaration)
    }
  }
  unique
}

///|
fn sort_declarations(declarations : Array[Declaration]) -> Unit {
  let mut index = 1
  while index < declarations.length() {
    let current = declarations[index]
    let mut insert_at = index
    while insert_at > 0 &&
          declarations[insert_at - 1].key().lexical_compare(current.key()) > 0 {
      declarations[insert_at] = declarations[insert_at - 1]
      insert_at = insert_at - 1
    }
    declarations[insert_at] = current
    index = index + 1
  }
}

///|
pub fn parse_api(
  source : String,
  source_name~ : String = "<memory>",
) -> ApiSnapshot raise {
  let mut package_id = ""
  let declarations : Array[Declaration] = []
  let block : Array[String] = []
  let mut block_line = 0
  let mut depth = 0
  let mut line_number = 0
  for raw_line in source.split("\n") {
    line_number = line_number + 1
    let line = raw_line.trim()
    if block.is_empty() {
      if line.has_prefix("package ") {
        if package_id.is_empty() {
          package_id = between_quotes(line, "package declaration")
        }
        continue
      }
      if is_declaration_start(line) {
        block.push(collapse_whitespace(line))
        block_line = line_number
        depth = brace_delta(line)
        if depth == 0 {
          append_declarations(
            declarations,
            make_declarations(block, block_line),
          )
          block.clear()
        }
      } else if line.has_prefix("pub") {
        raise Failure(
          "unsupported .mbti public syntax at \{source_name}:\{line_number}: \{line}",
        )
      }
    } else {
      block.push(collapse_whitespace(line))
      depth = depth + brace_delta(line)
      if depth == 0 {
        append_declarations(declarations, make_declarations(block, block_line))
        block.clear()
      } else if depth < 0 {
        raise Failure(
          "invalid .mbti at \{source_name}:\{line_number}: unbalanced '}'",
        )
      }
    }
  }
  if !block.is_empty() {
    raise Failure(
      "invalid .mbti at \{source_name}:\{block_line}: unterminated declaration block",
    )
  }
  if package_id.is_empty() {
    raise Failure("invalid .mbti: missing package declaration")
  }
  let unique = deduplicate_declarations(declarations)
  sort_declarations(unique)
  { package_id, declarations: unique, source: source_name, }
}

///|
pub fn parser_version() -> String {
  PARSER_VERSION
}
