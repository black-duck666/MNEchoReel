///|
/// RFC 6901 string form only. URI fragments and append tokens are not selectors.
fn pointer_tokens(pointer : String) -> Array[String] raise ReplayError {
  if pointer.length() > 4096 ||
    (!pointer.is_empty() && !pointer.has_prefix("/")) {
    fail(
      "invalid_expectation", "$expect.json", "JSON pointer must be empty or start with / and fit 4096 UTF-16 units",
    )
  }
  if pointer.is_empty() {
    return []
  }
  let parts = pointer.split("/").drop(1).map(p => p.to_owned()).collect()
  if parts.length() > 64 {
    fail(
      "invalid_expectation", "$expect.json", "JSON pointer exceeds 64 tokens",
    )
  }
  parts.map(part => {
    let mut escaped = false
    for c in part.iter() {
      if escaped {
        if c != '0' && c != '1' {
          fail(
            "invalid_expectation", "$expect.json", "JSON pointer escapes must be ~0 or ~1",
          )
        }
        escaped = false
      } else if c == '~' {
        escaped = true
      }
    }
    if escaped {
      fail(
        "invalid_expectation", "$expect.json", "JSON pointer has a trailing escape",
      )
    }
    part.replace(old="~1", new="/").replace(old="~0", new="~")
  })
}

///|
fn pointer_value(root : Json, tokens : Array[String]) -> Json? {
  let mut value = root
  for token in tokens {
    let next = match value {
      Object(fields) => fields.get(token)
      Array(items) => {
        if token.is_empty() || (token.length() > 1 && token.has_prefix("0")) {
          return None
        }
        let mut index = 0
        for c in token.iter() {
          if !c.is_ascii_digit() {
            return None
          }
          let digit = c.to_int() - '0'.to_int()
          if index > (2147483647 - digit) / 10 {
            return None
          }
          index = index * 10 + digit
        }
        items.get(index)
      }
      _ => None
    }
    guard next is Some(found) else { return None }
    value = found
  }
  Some(value)
}

///|
// Preserve numeric token spelling: Double equality would silently round large IDs.
fn json_exact(a : Json, b : Json) -> Bool {
  match (a, b) {
    (Number(_, repr=Some(x)), Number(_, repr=Some(y))) => x == y
    (Array(x), Array(y)) =>
      x.length() == y.length() &&
      x.iter().zip(y.iter()).all(pair => json_exact(pair.0, pair.1))
    (Object(x), Object(y)) =>
      x.length() == y.length() &&
      x
      .iter()
      .all(pair => {
        match y.get(pair.0) {
          Some(v) => json_exact(pair.1, v)
          None => false
        }
      })
    _ => a == b
  }
}

///|
fn Expectation::check_json(
  self : Expectation,
  bytes : Bytes,
) -> Unit raise ReplayError {
  let text = @utf8.decode(bytes, ignore_bom=false) catch {
    _ =>
      fail(
        "response_json_invalid", "$response.body", "JSON assertion requires a valid UTF-8 response body",
      )
  }
  let root = @json.parse(
    text,
    reject_duplicate_keys=true,
    preserve_number_repr=true,
    max_nesting_depth=64,
  ) catch {
    _ =>
      fail(
        "response_json_invalid", "$response.body", "JSON body is malformed, has duplicate keys or exceeds depth 64",
      )
  }
  for i, (tokens, expected) in self.json_checks {
    guard pointer_value(root, tokens) is Some(actual) else {
      fail(
        "response_json_missing",
        "$expect.json[\{i}]",
        "JSON pointer does not resolve to an existing value; no exchange consumed",
      )
    }
    if !json_exact(actual, expected) {
      fail(
        "response_json_mismatch",
        "$expect.json[\{i}]",
        "selected JSON value differs; numeric token spelling is exact; no exchange consumed",
      )
    }
  }
}
