///|
/// Changes to replay behavior, rather than HAR timings or browser metadata.
pub(all) enum ChangeKind {
  Added
  Removed
  Status
  Headers
  Body
} derive(Eq, Debug)

///|
pub extend ChangeKind with Eq::{equal, not_equal}

///|
pub extend ChangeKind with @debug.Debug::{to_repr}

///|
/// Indices refer to the original before/after HAR entry arrays. No payload values.
pub(all) struct Change {
  kind : ChangeKind
  before_index : Int32?
  after_index : Int32?
} derive(Eq, Debug)

///|
pub extend Change with Eq::{equal, not_equal}

///|
pub extend Change with @debug.Debug::{to_repr}

///|
pub struct ChangeReport {
  priv changes : Array[Change]
  priv ignored : Array[String]
  priv json_pointers : Array[String]?
  priv json_changes : Array[JsonFieldChange]
}

///|
pub fn ChangeReport::changes(self : ChangeReport) -> Array[Change] {
  self.changes.copy()
}

///|
pub fn ChangeReport::is_empty(self : ChangeReport) -> Bool {
  self.changes.is_empty()
}

///|
pub fn ChangeReport::render_json(self : ChangeReport) -> String {
  let json : Json = {
    "schema": 1,
    "ignored_response_headers": self.ignored,
    "changes": self.changes.map(c => {
      let kind = match c.kind {
        Added => "added"
        Removed => "removed"
        Status => "status"
        Headers => "headers"
        Body => "body"
      }
      let row : Json = {
        "kind": kind,
        "before_index": match c.before_index {
          Some(i) => Json(i)
          None => Json::null()
        },
        "after_index": match c.after_index {
          Some(i) => Json(i)
          None => Json::null()
        },
      }
      row
    }),
  }
  if self.json_pointers is Some(pointers) && json is Object(fields) {
    fields.set("body_mode", Json("json_pointers"))
    fields.set("json_pointers", Json(pointers))
    fields.set(
      "json_changes",
      Json(
        self.json_changes.map(change => {
          let value : Json = {
            "before_index": change.before_index,
            "after_index": change.after_index,
            "pointer_index": change.pointer_index,
            "kind": change.kind,
          }
          value
        }),
      ),
    )
  }
  json.stringify()
}

///|
fn kept_headers(
  headers : Array[(String, String)],
  ignored : Array[String],
) -> Array[(String, String)] {
  headers.filter(pair => {
    !ignored.iter().any(name => name.equal_ignore_ascii_case(pair.0))
  })
}

///|
/// Align exact request identities with bounded LCS, then compare aligned responses.
/// Ties remove the earlier old entry first. Reordering is represented as remove/add.
/// Timings and other non-replay metadata are intentionally outside this report.
pub fn Cassette::compare(
  self : Cassette,
  after : Cassette,
  ignore_response_headers~ : Array[String] = [],
  max_cells~ : Int32 = 1000000,
  json_pointers? : Array[String],
) -> ChangeReport raise ReplayError {
  for name in ignore_response_headers {
    if !token(name) {
      fail(
        "invalid_review_option", "$review", "ignored header names must be HTTP tokens",
      )
    }
  }
  let same_names = self.header_names
    .iter()
    .all(n => after.header_names.iter().any(m => n.equal_ignore_ascii_case(m))) &&
    after.header_names
    .iter()
    .all(n => self.header_names.iter().any(m => n.equal_ignore_ascii_case(m)))
  if !same_names {
    fail(
      "incomparable_matchers", "$review", "compile both cassettes with the same selected request header names",
    )
  }
  let n = self.length()
  let m = after.length()
  if max_cells < 1 || n + 1 > max_cells / (m + 1) {
    fail(
      "review_limit", "$review", "alignment exceeds max_cells; reduce the fixture or explicitly raise the review budget",
    )
  }
  let pointers = json_pointers.map(review_pointers)
  let before_json = if pointers == None {
    []
  } else {
    review_json_bodies(self, "$review.before", pointers.unwrap())
  }
  let after_json = if pointers == None {
    []
  } else {
    review_json_bodies(after, "$review.after", pointers.unwrap())
  }
  let width = m + 1
  let lengths = Array::make((n + 1) * width, 0)
  for ri in 0..<n {
    let i = n - 1 - ri
    for rj in 0..<m {
      let j = m - 1 - rj
      lengths[i * width + j] = if mismatch(
          self.exchanges[i].request,
          after.exchanges[j].request,
          self.header_names,
        ) ==
        None {
        1 + lengths[(i + 1) * width + j + 1]
      } else {
        let remove = lengths[(i + 1) * width + j]
        let add = lengths[i * width + j + 1]
        if remove >= add {
          remove
        } else {
          add
        }
      }
    }
  }
  let changes : Array[Change] = []
  let json_changes : Array[JsonFieldChange] = []
  for i = 0, j = 0; i < n || j < m; {
    if i < n &&
      j < m &&
      mismatch(
        self.exchanges[i].request,
        after.exchanges[j].request,
        self.header_names,
      ) ==
      None {
      let before = self.exchanges[i].response
      let next = after.exchanges[j].response
      if before.status != next.status {
        changes.push({
          kind: Status,
          before_index: Some(i),
          after_index: Some(j),
        })
      }
      if kept_headers(before.headers, ignore_response_headers) !=
        kept_headers(next.headers, ignore_response_headers) {
        changes.push({
          kind: Headers,
          before_index: Some(i),
          after_index: Some(j),
        })
      }
      let body_changed = match pointers {
        None => before.body != next.body
        Some(tokens) =>
          compare_json_fields(
            before_json[i],
            after_json[j],
            tokens,
            i,
            j,
            json_changes,
          )
      }
      if body_changed {
        changes.push({
          kind: Body,
          before_index: Some(i),
          after_index: Some(j),
        })
      }
      continue i + 1, j + 1
    }
    if i < n &&
      (j == m || lengths[(i + 1) * width + j] >= lengths[i * width + j + 1]) {
      changes.push({ kind: Removed, before_index: Some(i), after_index: None, })
      continue i + 1, j
    }
    changes.push({ kind: Added, before_index: None, after_index: Some(j), })
    continue i, j + 1
  }
  {
    changes,
    ignored: ignore_response_headers.copy(),
    json_pointers: json_pointers.map(names => names.copy()),
    json_changes,
  }
}
