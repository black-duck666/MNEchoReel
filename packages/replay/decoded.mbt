///|
/// DecodedContent trusts HAR's embedded decoded content, never compressed wire bytes.
pub(all) enum BodyProfile {
  Identity
  DecodedContent
} derive(Eq, Debug)

///|
pub extend BodyProfile with Eq::{equal, not_equal}

///|
pub extend BodyProfile with @debug.Debug::{to_repr}

///|
/// One explicit header edit. header_index always addresses the original HAR array.
pub(all) struct HeaderChange {
  entry_index : Int32
  header_index : Int32
  name : String
  before : String
  after : String?
} derive(Eq, Debug)

///|
pub extend HeaderChange with Eq::{equal, not_equal}

///|
pub extend HeaderChange with @debug.Debug::{to_repr}

///|
pub fn Cassette::adaptations(self : Cassette) -> Array[HeaderChange] {
  self.adaptations.copy()
}

///|
/// Includes every removed/rewritten value; unchanged headers are absent from the report.
pub fn Cassette::adaptation_report_json(self : Cassette) -> String {
  let report : Json = {
    "schema": 1,
    "header_changes": self.adaptations.map(c => {
      let value : Json = {
        "entry_index": c.entry_index,
        "header_index": c.header_index,
        "name": c.name,
        "before": c.before,
        "after": match c.after {
          Some(value) => Json(value)
          None => Json::null()
        },
      }
      value
    }),
  }
  report.stringify()
}

///|
fn decoded_headers(
  headers : Array[(String, String)],
  profile : BodyProfile,
  wire_size : Double,
  decoded_size : Int32,
  no_body : Bool,
  entry_index : Int32,
) -> (Array[(String, String)], Array[HeaderChange], Bool) raise ReplayError {
  if profile == Identity {
    return (headers, [], false)
  }
  let path = "$.log.entries[\{entry_index}].response"
  let mut coded = false
  for value in selected(headers, "content-encoding") {
    for item in value.split(",") {
      let coding = item.trim().to_owned().to_lower()
      if !["identity", "gzip", "br", "deflate"].contains(coding) {
        fail(
          "unsupported_encoding",
          path + ".headers",
          "decoded profile accepts only identity, gzip, br and deflate content codings",
        )
      }
      if coding != "identity" {
        coded = true
      }
    }
  }
  if !coded {
    return (headers, [], false)
  }
  if no_body {
    fail(
      "unsupported_empty_adaptation", path, "content coding on HEAD, 204 or 304 requires representation-aware handling; no headers adapted",
    )
  }
  if wire_size < 0 ||
    wire_size > 2147483647 ||
    wire_size != wire_size.to_int().to_double() {
    fail(
      "wire_length_unknown",
      path + ".bodySize",
      "decoded profile requires a known nonnegative 32-bit encoded bodySize",
    )
  }
  check_length(headers, wire_size.to_int(), path + ".headers")
  // Integrity metadata can describe encoded bytes; do not silently invalidate it.
  for (name, _) in headers {
    if [
        "content-md5", "digest", "content-digest", "repr-digest", "content-range",
        "signature", "signature-input",
      ].contains(name.to_lower()) {
      fail(
        "unsupported_integrity_adaptation",
        path + ".headers",
        "encoded-body integrity or range metadata needs explicit application handling",
      )
    }
  }
  let output = []
  let changes = []
  for index, (name, value) in headers {
    if name.equal_ignore_ascii_case("content-encoding") {
      changes.push({
        entry_index,
        header_index: index,
        name,
        before: value,
        after: None,
      })
    } else if name.equal_ignore_ascii_case("content-length") &&
      value != decoded_size.to_string() {
      let next = decoded_size.to_string()
      changes.push({
        entry_index,
        header_index: index,
        name,
        before: value,
        after: Some(next),
      })
      output.push((name, next))
    } else {
      output.push((name, value))
    }
  }
  (output, changes, true)
}
