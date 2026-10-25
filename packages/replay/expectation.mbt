///|
/// Exact response assertions. An empty header-value list asserts absence.
pub struct Expectation {
  priv status : Int32?
  priv body : Bytes?
  priv headers : Array[(String, Array[String])]
  priv json_checks : Array[(Array[String], Json)]
}

///|
/// Headers select names to check; unrelated response headers remain unconstrained.
pub fn Expectation::new(
  status? : Int32,
  body? : Bytes,
  headers~ : Array[(String, Array[String])] = [],
  json~ : Array[(String, String)] = [],
) -> Expectation raise ReplayError {
  if status is Some(value) && (value < 200 || value > 599) {
    fail(
      "invalid_expectation", "$expect.status", "expected a final status from 200 through 599",
    )
  }
  let names : Array[String] = []
  for (name, _) in headers {
    if !token(name) || names.iter().any(n => n.equal_ignore_ascii_case(name)) {
      fail(
        "invalid_expectation", "$expect.headers", "header names must be tokens and may appear only once, ignoring ASCII case",
      )
    }
    names.push(name)
  }
  if json.length() > 256 {
    fail(
      "invalid_expectation", "$expect.json", "at most 256 JSON field assertions are supported",
    )
  }
  let json_checks = json.map(pair => {
    let tokens = pointer_tokens(pair.0)
    if pair.1.length() > 1048576 {
      fail(
        "invalid_expectation", "$expect.json", "expected JSON value exceeds 1048576 UTF-16 units",
      )
    }
    let value = @json.parse(
      pair.1,
      reject_duplicate_keys=true,
      preserve_number_repr=true,
      max_nesting_depth=64,
    ) catch {
      _ =>
        fail(
          "invalid_expectation", "$expect.json", "expected value must be valid JSON without duplicate keys and within depth 64",
        )
    }
    (tokens, value)
  })
  {
    status,
    body,
    headers: headers.map(pair => (pair.0, pair.1.copy())),
    json_checks,
  }
}

///|
/// Reports only the differing field; expected/recorded secrets are not printed.
pub fn Expectation::check(
  self : Expectation,
  response : Response,
) -> Unit raise ReplayError {
  if self.status is Some(status) && status != response.status {
    fail(
      "status_mismatch", "$response.status", "recorded status differs from expectation",
    )
  }
  if self.body is Some(body) && body != response.body {
    fail(
      "response_body_mismatch", "$response.body", "recorded body bytes differ from expectation",
    )
  }
  for (name, values) in self.headers {
    if selected(response.headers, name) != values {
      fail(
        "response_header_mismatch", "$response.headers", "selected header values differ from expectation; duplicate order is significant",
      )
    }
  }
  if !self.json_checks.is_empty() {
    self.check_json(response.body)
  }
}
