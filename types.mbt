///|
pub enum DeclarationKind {
  Function
  Struct
  Enum
  Type
  Error
  Trait
  Impl
  Value
  Other
}

///|
pub fn DeclarationKind::label(self : DeclarationKind) -> String {
  match self {
    Function => "function"
    Struct => "struct"
    Enum => "enum"
    Type => "type"
    Error => "error"
    Trait => "trait"
    Impl => "impl"
    Value => "value"
    Other => "other"
  }
}

///|
pub struct Declaration {
  kind : DeclarationKind
  name : String
  canonical : String
  line : Int32
}

///|
pub fn Declaration::key(self : Declaration) -> String {
  "\{self.kind.label()}:\{self.name}"
}

///|
pub struct ApiSnapshot {
  package_id : String
  declarations : Array[Declaration]
  source : String
}

///|
pub enum ChangeSeverity {
  Breaking
  Compatible
}

///|
pub fn ChangeSeverity::label(self : ChangeSeverity) -> String {
  match self {
    Breaking => "breaking"
    Compatible => "compatible"
  }
}

///|
pub enum ChangeKind {
  PackageRenamed
  Removed
  Added
  DeclarationChanged
}

///|
pub fn ChangeKind::label(self : ChangeKind) -> String {
  match self {
    PackageRenamed => "package_renamed"
    Removed => "removed"
    Added => "added"
    DeclarationChanged => "declaration_changed"
  }
}

///|
pub struct Change {
  package_id : String
  name : String
  declaration_kind : String
  kind : ChangeKind
  severity : ChangeSeverity
  before : String
  after : String
  message : String
}

///|
pub enum VersionBump {
  Major
  Minor
  Patch
}

///|
pub fn VersionBump::label(self : VersionBump) -> String {
  match self {
    Major => "major"
    Minor => "minor"
    Patch => "patch"
  }
}

///|
pub struct CompatibilityReport {
  base_package : String
  head_package : String
  changes : Array[Change]
  breaking_count : Int32
  compatible_count : Int32
  unchanged_count : Int32
}

///|
pub fn CompatibilityReport::has_breaking_changes(
  self : CompatibilityReport,
) -> Bool {
  self.breaking_count > 0
}

///|
pub fn CompatibilityReport::recommended_bump(
  self : CompatibilityReport,
) -> VersionBump {
  if self.breaking_count > 0 {
    Major
  } else if self.compatible_count > 0 {
    Minor
  } else {
    Patch
  }
}

///|
pub fn CompatibilityReport::result(self : CompatibilityReport) -> String {
  if self.has_breaking_changes() {
    "breaking"
  } else if self.compatible_count > 0 {
    "compatible"
  } else {
    "unchanged"
  }
}
