///|
/// Indices and a configured pointer ordinal only; kind is added, removed or changed.
pub(all) struct JsonFieldChange {
  before_index : Int32
  after_index : Int32
  pointer_index : Int32
  kind : String
} derive(Eq, Debug)

///|
pub extend JsonFieldChange with Eq::{equal, not_equal}

///|
pub extend JsonFieldChange with @debug.Debug::{to_repr}

///|
pub fn ChangeReport::json_changes(
  self : ChangeReport,
) -> Array[JsonFieldChange] {
  self.json_changes.copy()
}

///|
fn review_pointers(
  names : Array[String],
) -> Array[Array[String]] raise ReplayError {
  if names.is_empty() || names.length() > 256 {
    fail(
      "invalid_review_option", "$review.json_pointers", "JSON body comparison requires 1 through 256 unique pointers",
    )
  }
  let tokens = []
  for i, name in names {
    let pointer = pointer_tokens(name) catch {
      ReplayError(_) =>
        fail(
          "invalid_review_option",
          "$review.json_pointers[\{i}]",
          "expected an RFC 6901 string pointer",
        )
    }
    if tokens.contains(pointer) {
      fail(
        "invalid_review_option",
        "$review.json_pointers[\{i}]",
        "duplicate JSON pointer",
      )
    }
    tokens.push(pointer)
  }
  tokens
}

///|
fn review_json_bodies(
  cassette : Cassette,
  path : String,
  pointers : Array[Array[String]],
) -> Array[Json] raise ReplayError {
  cassette.exchanges.mapi((i, exchange) => {
    let location = path + "[\{i}].body"
    let text = @utf8.decode(exchange.response.body, ignore_bom=false) catch {
      _ =>
        fail(
          "review_json_invalid", location, "JSON comparison requires strict UTF-8 bodies",
        )
    }
    let body = @json.parse(
      text,
      reject_duplicate_keys=true,
      preserve_number_repr=true,
      max_nesting_depth=64,
    ) catch {
      _ =>
        fail(
          "review_json_invalid", location, "JSON body is malformed, has duplicate keys or exceeds depth 64",
        )
    }
    for k, tokens in pointers {
      if pointer_lookup(body, tokens) is BadIndex {
        fail(
          "review_json_selector",
          location + ".pointers[\{k}]",
          "array selector is not a canonical nonnegative decimal index",
        )
      }
    }
    body
  })
}

///|
fn compare_json_fields(
  before : Json,
  after : Json,
  pointers : Array[Array[String]],
  before_index : Int32,
  after_index : Int32,
  changes : Array[JsonFieldChange],
) -> Bool raise ReplayError {
  let mut changed = false
  for pointer_index, tokens in pointers {
    let kind = match
      (pointer_lookup(before, tokens), pointer_lookup(after, tokens)) {
      (Located(a), Located(b)) =>
        if json_exact(a, b) {
          None
        } else {
          Some("changed")
        }
      (NotFound, Located(_)) => Some("added")
      (Located(_), NotFound) => Some("removed")
      (NotFound, NotFound) => None
      (BadIndex, _) | (_, BadIndex) =>
        fail(
          "review_json_selector",
          "$review.json_pointers[\{pointer_index}]",
          "invalid array selector cannot be compared",
        )
    }
    if kind is Some(kind) {
      changed = true
      changes.push({ before_index, after_index, pointer_index, kind, })
    }
  }
  changed
}
