///|
priv struct SuiteSpec {
  index : Int32
  name : String
  har : String
  requests : String
  decoded : Bool
  mode : @replay.MatchMode
  headers : Array[String]
}

///|
/// Validated descriptors, before any file is loaded. Exact source and paths are retained.
pub struct SuiteManifest {
  priv source : String
  priv specs : Array[SuiteSpec]
  priv all_names : Array[String]
  priv shard : (Int32, Int32)?
}

///|
fn[T] suite_fail(
  code : String,
  path : String,
  message : String,
) -> T raise @replay.ReplayError {
  raise @replay.ReplayError({ code, path, message, })
}

///|
fn suite_string(
  value : Json,
  key : String,
  path : String,
) -> String raise @replay.ReplayError {
  guard get(value, key) is Some(String(text)) && !text.is_empty() else {
    suite_fail(
      "suite_manifest_error",
      path + "." + key,
      "expected a nonempty string",
    )
  }
  text
}

///|
fn suite_header(name : String) -> Bool {
  !name.is_empty() &&
  name
  .iter()
  .all(c => {
    c.is_ascii_alphabetic() ||
    c.is_ascii_digit() ||
    "!#$%&'*+-.^_`|~".contains(c.to_string())
  })
}

///|
pub fn parse_suite_manifest(
  source : String,
  max_input_units~ : Int32 = 4194304,
  max_cases~ : Int32 = 1000,
) -> SuiteManifest raise @replay.ReplayError {
  if max_input_units < 1 || max_cases < 1 {
    suite_fail("suite_limit", "$suite", "manifest limits must be positive")
  }
  if source.length() > max_input_units {
    suite_fail(
      "suite_manifest_error", "$suite", "suite manifest exceeds max_input_units",
    )
  }
  let value = @json.parse(
    source,
    reject_duplicate_keys=true,
    max_nesting_depth=16,
  ) catch {
    _ =>
      suite_fail(
        "suite_manifest_error", "$suite", "invalid JSON, duplicate key or excessive nesting",
      )
  }
  guard value is Array(items) &&
    !items.is_empty() &&
    items.length() <= max_cases else {
    suite_fail(
      "suite_manifest_error", "$suite", "expected a nonempty case array within max_cases",
    )
  }
  let names : Map[String, Bool] = Map([])
  let specs = items.mapi((i, item) => {
    let path = "$suite[\{i}]"
    guard item is Object(fields) else {
      suite_fail("suite_manifest_error", path, "expected a case object")
    }
    for key, _ in fields {
      if !["name", "har", "requests", "decoded", "mode", "match_headers"].contains(
          key,
        ) {
        suite_fail("suite_manifest_error", path, "unknown case field")
      }
    }
    let name = suite_string(item, "name", path)
    validate_case_name(name, path + ".name")
    if names.get(name) is Some(_) {
      suite_fail(
        "duplicate_case", path, "case names must be unique; no inputs were loaded",
      )
    }
    names.set(name, true)
    let har = suite_string(item, "har", path)
    let requests = suite_string(item, "requests", path)
    let decoded = match get(item, "decoded") {
      None | Some(False) => false
      Some(True) => true
      _ =>
        suite_fail(
          "suite_manifest_error",
          path + ".decoded",
          "expected a boolean",
        )
    }
    let mode : @replay.MatchMode = match get(item, "mode") {
      None | Some(String("ordered")) => Ordered
      Some(String("by-request")) => ByRequest
      Some(String("per-request")) => PerRequest
      _ =>
        suite_fail(
          "suite_manifest_error",
          path + ".mode",
          "expected ordered, by-request or per-request",
        )
    }
    let headers : Array[String] = match get(item, "match_headers") {
      None => []
      Some(Array(values)) =>
        values.map(value => {
          guard value is String(name) else {
            suite_fail(
              "suite_manifest_error",
              path + ".match_headers",
              "expected header-name strings",
            )
          }
          if !suite_header(name) {
            suite_fail(
              "invalid_match_header",
              path + ".match_headers",
              "selected header names must be HTTP tokens",
            )
          }
          name
        })
      _ =>
        suite_fail(
          "suite_manifest_error",
          path + ".match_headers",
          "expected an array",
        )
    }
    SuiteSpec::{ index: i, name, har, requests, decoded, mode, headers, }
  })
  { source, all_names: specs.map(spec => spec.name), specs, shard: None, }
}

///|
pub fn SuiteManifest::source(self : SuiteManifest) -> String {
  self.source
}

///|
pub fn SuiteManifest::names(self : SuiteManifest) -> Array[String] {
  self.specs.map(spec => spec.name)
}
