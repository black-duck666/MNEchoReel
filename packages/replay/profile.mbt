///|
/// Reject unknown replay semantics rather than letting a typed parser drop them.
fn known_fields(
  value : Json,
  allowed : Array[String],
  path : String,
) -> Unit raise ReplayError {
  guard value is Object(fields) else {
    fail("invalid_har", path, "expected an object")
  }
  for key, _ in fields {
    if !allowed.contains(key) {
      fail(
        "unsupported_field", path, "object contains an unsupported field; inspect the source HAR and remove it only after checking its meaning",
      )
    }
  }
}

///|
fn field(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn check_profile(root : Json, max_entries : Int32) -> Unit raise ReplayError {
  let entries = field(field(root, "log"), "entries")
  guard entries is Array(items) else {
    fail("invalid_har", "$.log.entries", "expected an array")
  }
  if items.length() > max_entries {
    fail("entry_limit", "$.log.entries", "HAR exceeds max_entries")
  }
  for i, entry in items {
    let p = "$.log.entries[\{i}]"
    known_fields(
      entry,
      [
        "pageref", "startedDateTime", "time", "request", "response", "cache", "timings",
        "serverIPAddress", "connection", "comment", "_initiator", "_priority", "_resourceType",
      ],
      p,
    )
    let request = field(entry, "request")
    known_fields(
      request,
      [
        "method", "url", "httpVersion", "cookies", "headers", "queryString", "postData",
        "headersSize", "bodySize", "comment",
      ],
      p + ".request",
    )
    let post = field(request, "postData")
    if !(post is Null) {
      known_fields(
        post,
        ["mimeType", "text", "comment"],
        p + ".request.postData",
      )
    }
    let response = field(entry, "response")
    known_fields(
      response,
      [
        "status", "statusText", "httpVersion", "cookies", "headers", "content", "redirectURL",
        "headersSize", "bodySize", "comment",
      ],
      p + ".response",
    )
    known_fields(
      field(response, "content"),
      ["size", "compression", "mimeType", "text", "encoding", "comment"],
      p + ".response.content",
    )
    for part in [request, response] {
      if field(part, "headers") is Array(headers) {
        for header in headers {
          known_fields(header, ["name", "value", "comment"], p + ".headers")
        }
      }
    }
  }
}

///|
fn token(value : String) -> Bool {
  !value.is_empty() &&
  value
  .iter()
  .all(c => {
    c.is_ascii_alphabetic() ||
    c.is_ascii_digit() ||
    "!#$%&'*+-.^_`|~".contains(c.to_string())
  })
}

///|
fn check_headers(
  headers : Array[(String, String)],
  path : String,
) -> Unit raise ReplayError {
  for (name, value) in headers {
    if !token(name) ||
      value.iter().any(c => c == '\r' || c == '\n' || c == '\u0000') {
      fail(
        "invalid_header", path, "header name must be an HTTP token and value must not contain CR, LF or NUL",
      )
    }
    if name.equal_ignore_ascii_case("transfer-encoding") ||
      (
        name.equal_ignore_ascii_case("content-encoding") &&
        !value.equal_ignore_ascii_case("identity")
      ) {
      fail(
        "unsupported_encoding", path, "compressed or transfer-coded recordings require an explicit decoded-body adaptation; capture identity encoding for this profile",
      )
    }
    if name.equal_ignore_ascii_case("upgrade") {
      fail(
        "unsupported_upgrade", path, "protocol upgrades cannot be replayed as finite responses",
      )
    }
    if name.equal_ignore_ascii_case("content-type") {
      check_mime(value, path)
    }
  }
}

///|
fn check_url(url : String, path : String) -> Unit raise ReplayError {
  if (!url.has_prefix("https://") && !url.has_prefix("http://")) ||
    url.iter().any(c => c.is_ascii_control() || c == ' ') {
    fail(
      "unsupported_url", path, "expected an absolute HTTP(S) URL without whitespace or control characters",
    )
  }
  let parsed = @http.Url::parse(url) catch {
    _ => fail("unsupported_url", path, "URL authority is invalid")
  }
  if parsed.host == None || parsed.host == Some("") || parsed.fragment != None {
    fail(
      "unsupported_url", path, "expected a nonempty host and no URL fragment",
    )
  }
}

///|
fn check_mime(mime : String, path : String) -> Unit raise ReplayError {
  let parts = mime.split(";").map(p => p.trim().to_owned()).collect()
  if parts[0].equal_ignore_ascii_case("text/event-stream") ||
    parts[0].to_lower().has_prefix("multipart/") {
    fail(
      "unsupported_body", path, "streaming events and multipart bodies are outside the finite-body profile",
    )
  }
  for i in 1..<parts.length() {
    let lower = parts[i].to_lower()
    let non_utf8 = match lower.split_once("=") {
      Some((key, value)) =>
        key.trim() == "charset" &&
        value.trim() != "utf-8" &&
        value.trim() != "\"utf-8\""
      None => lower.trim() == "charset"
    }
    if non_utf8 {
      fail(
        "unsupported_charset", path, "only UTF-8 textual bodies can be reconstructed safely",
      )
    }
  }
}

///|
fn check_length(
  headers : Array[(String, String)],
  length : Int32,
  path : String,
) -> Unit raise ReplayError {
  for value in selected(headers, "content-length") {
    if value != length.to_string() {
      fail(
        "body_length", path, "Content-Length does not match the reconstructed body; re-export complete identity content",
      )
    }
  }
}
