///|
/// Compile a pre-sanitized, self-contained HAR 1.2 into repeatable offline tests.
/// Input limits count UTF-16 code units before parsing, entries, and decoded bytes.
pub fn compile_har(
  source : String,
  match_headers~ : Array[String] = [],
  max_input_units~ : Int32 = 16777216,
  max_entries~ : Int32 = 10000,
  max_body_bytes~ : Int32 = 4194304,
  body_profile~ : BodyProfile = Identity,
) -> Cassette raise ReplayError {
  if max_input_units < 1 || max_entries < 0 || max_body_bytes < 0 {
    fail(
      "invalid_limit", "$", "input limit must be positive; entry and body limits must be nonnegative",
    )
  }
  if source.length() > max_input_units {
    fail("input_limit", "$", "HAR exceeds max_input_units")
  }
  for name in match_headers {
    if !token(name) {
      fail(
        "invalid_match_header", "$", "selected header names must be HTTP tokens",
      )
    }
  }
  let raw = @json.parse(
    source,
    reject_duplicate_keys=true,
    max_nesting_depth=64,
  ) catch {
    _ =>
      fail(
        "invalid_json", "$", "invalid JSON, duplicate key or nesting deeper than 64; check the source file",
      )
  }
  check_profile(raw, max_entries)
  let document = match @har.parse_har(source) {
    Ok(value) => value
    Err(error) =>
      fail(
        "invalid_har",
        error.path(),
        "HAR structure is invalid; validate the recording with har-toolkit",
      )
  }
  if document.version() != "1.2" {
    fail("har_version", "$.log.version", "only HAR 1.2 is supported")
  }
  if document.entry_count() > max_entries {
    fail("entry_limit", "$.log.entries", "HAR exceeds max_entries")
  }
  let validation = @har.validate_har(document)
  for issue in validation.issues() {
    if issue.severity() == "error" {
      fail(
        "invalid_har",
        issue.path(),
        "HAR validation failed; check the source with har-toolkit",
      )
    }
  }
  let exchanges = []
  let adaptations = []
  for i, entry in document.entries() {
    let p = "$.log.entries[\{i}]"
    let request = entry.request()
    let http_method = request.request_method()
    if !token(http_method) || http_method == "CONNECT" || http_method == "TRACE" {
      fail(
        "unsupported_method",
        p + ".request.method",
        "expected an ordinary HTTP method; CONNECT and TRACE are outside this profile",
      )
    }
    let url = request.url()
    check_url(url, p + ".request.url")
    let request_headers = request.headers().map(h => (h.name(), h.value()))
    check_headers(request_headers, p + ".request.headers")
    if !request.cookies().is_empty() &&
      selected(request_headers, "cookie").is_empty() {
      fail(
        "missing_cookie_header",
        p + ".request.headers",
        "cookie metadata has no Cookie header; this profile does not synthesize headers",
      )
    }
    let request_body = match request.post_data() {
      None => {
        if request.body_size() != 0 {
          fail(
            "missing_body",
            p + ".request.postData",
            "request body is absent but bodySize is not zero; export complete request content",
          )
        }
        b""
      }
      Some(post) => {
        check_mime(post.mime_type(), p + ".request.postData.mimeType")
        guard post.text() is Some(text) else {
          fail(
            "missing_body",
            p + ".request.postData.text",
            "request text is required; params and external files cannot reconstruct original bytes",
          )
        }
        @utf8.encode(text)
      }
    }
    if request_body.length() > max_body_bytes {
      fail(
        "body_limit",
        p + ".request.postData",
        "request exceeds max_body_bytes",
      )
    }
    if request.body_size() >= 0 &&
      request.body_size() != request_body.length().to_double() {
      fail(
        "body_length",
        p + ".request.bodySize",
        "recorded request size differs from UTF-8 bytes",
      )
    }
    check_length(request_headers, request_body.length(), p + ".request.headers")
    let response = entry.response()
    let status = response.status()
    if status < 200 || status > 599 || status != status.to_int().to_double() {
      fail(
        "unsupported_status",
        p + ".response.status",
        "expected a final HTTP status from 200 through 599",
      )
    }
    let headers = response.headers().map(h => (h.name(), h.value()))
    check_headers(
      headers,
      p + ".response.headers",
      allow_content_coding=body_profile == DecodedContent,
    )
    if !response.cookies().is_empty() &&
      selected(headers, "set-cookie").is_empty() {
      fail(
        "missing_cookie_header",
        p + ".response.headers",
        "cookie metadata has no Set-Cookie header; export complete response headers",
      )
    }
    if response.redirect_url() != "" &&
      selected(headers, "location") != [response.redirect_url()] {
      fail(
        "redirect_header",
        p + ".response.redirectURL",
        "redirectURL requires one identical Location header",
      )
    }
    let content = response.content()
    check_mime(content.mime_type(), p + ".response.content.mimeType")
    if content.encoding() != None && content.encoding() != Some("base64") {
      fail(
        "unsupported_encoding",
        p + ".response.content.encoding",
        "only absent encoding or base64 is supported",
      )
    }
    let no_body = http_method == "HEAD" || status == 204 || status == 304
    let body = match content.text() {
      None =>
        if no_body || content.size() == 0 {
          b""
        } else {
          fail(
            "missing_body",
            p + ".response.content.text",
            "response content was omitted; export HAR with content",
          )
        }
      Some(text) =>
        match content.encoding() {
          None => @utf8.encode(text)
          Some("base64") => {
            let bytes = @base64.decode(text) catch {
              _ =>
                fail(
                  "invalid_base64",
                  p + ".response.content.text",
                  "expected canonical padded base64",
                )
            }
            if @base64.encode(bytes) != text {
              fail(
                "invalid_base64",
                p + ".response.content.text",
                "expected canonical padded base64 without whitespace",
              )
            }
            bytes
          }
          Some(_) =>
            fail(
              "unsupported_encoding",
              p + ".response.content.encoding",
              "only absent encoding or base64 is supported",
            )
        }
    }
    if body.length() > max_body_bytes {
      fail(
        "body_limit",
        p + ".response.content",
        "response exceeds max_body_bytes",
      )
    }
    let (headers, changes, adapted) = decoded_headers(
      headers,
      body_profile,
      response.body_size(),
      body.length(),
      no_body,
      i,
    )
    for change in changes {
      adaptations.push(change)
    }
    if adapted &&
      content.compression() is Some(saved) &&
      saved != body.length().to_double() - response.body_size() {
      fail(
        "body_length",
        p + ".response.content.compression",
        "compression metadata differs from decoded size minus encoded bodySize",
      )
    }
    if !adapted &&
      response.body_size() >= 0 &&
      response.body_size() != body.length().to_double() {
      fail(
        "body_length",
        p + ".response.bodySize",
        "identity response bodySize differs from reconstructed bytes",
      )
    }
    if no_body && !body.is_empty() {
      fail(
        "body_forbidden",
        p + ".response.content",
        "HEAD, 204 and 304 must have an empty body",
      )
    }
    if (!no_body || status == 204) &&
      content.size() != body.length().to_double() {
      fail(
        "body_length",
        p + ".response.content.size",
        "decoded content.size differs from reconstructed bytes",
      )
    }
    if http_method != "HEAD" && status != 304 {
      check_length(headers, body.length(), p + ".response.headers")
    }
    exchanges.push({
      request: Request::new(
        http_method,
        url,
        headers=request_headers,
        body=request_body,
      ),
      response: { status: status.to_int(), headers, body, },
    })
  }
  { source, exchanges, header_names: match_headers.copy(), adaptations, }
}
