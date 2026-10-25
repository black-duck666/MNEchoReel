///|
/// Exact response assertions. An empty header-value list asserts absence.
pub struct Expectation {
  priv status : Int32?
  priv body : Bytes?
  priv headers : Array[(String, Array[String])]
}

///|
/// Headers select names to check; unrelated response headers remain unconstrained.
pub fn Expectation::new(
  status? : Int32,
  body? : Bytes,
  headers~ : Array[(String, Array[String])] = [],
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
  { status, body, headers: headers.map(pair => (pair.0, pair.1.copy())), }
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
}
