///|
test "canonical base64 roundtrips every byte and boundary lengths" {
  for length in 0..<=256 {
    let bytes = Bytes::makei(length, i => i.to_byte())
    let e = entry()
    let content = at(at(e, "response"), "content")
    put(content, "encoding", "base64")
    put(content, "text", Json(@base64.encode(bytes)))
    put(content, "size", Json(length))
    put(at(e, "response"), "bodySize", Json(length))
    let cassette = @replay.compile_har(fixture([e]), max_body_bytes=length)
    let replayed = cassette
      .session()
      .take(@replay.Request::new("GET", "https://example.invalid/a"))
    assert_eq(replayed.body(), bytes)
    assert_eq(@base64.encode(replayed.body()), @base64.encode(bytes))
  }
}

///|
test "malformed base64, size mismatches and missing body never become empty success" {
  for text in ["a", "%%%", "Zg", "Zh==", "Zg==\n", "Zg==="] {
    let e = entry()
    put(at(at(e, "response"), "content"), "encoding", "base64")
    put(at(at(e, "response"), "content"), "text", Json(text))
    rejected(fixture([e]), "invalid_base64")
  }
  let missing = entry()
  guard at(at(missing, "response"), "content") is Object(fields) else {
    abort("fixture")
  }
  fields.remove("text")
  rejected(fixture([missing]), "missing_body")
  let size = entry()
  put(at(at(size, "response"), "content"), "size", 3)
  rejected(fixture([size]), "body_length")
  let length = entry()
  put(at(length, "response"), "headers", [
    { "name": "Content-Length", "value": "3" },
  ])
  rejected(fixture([length]), "body_length")
}

///|
test "explicit input, entry and body limits including zero" {
  let source = fixture([entry()])
  assert_eq(
    @replay.compile_har(
      source,
      max_input_units=source.length(),
      max_entries=1,
      max_body_bytes=2,
    ).length(),
    1,
  )
  for
    (input_limit, entries, body, expected) in [
      (source.length() - 1, 1, 2, "input_limit"),
      (source.length(), 0, 2, "entry_limit"),
      (source.length(), 1, 1, "body_limit"),
      (0, 1, 2, "invalid_limit"),
      (source.length(), -1, 2, "invalid_limit"),
    ] {
    try
      @replay.compile_har(
        source,
        max_input_units=input_limit,
        max_entries=entries,
        max_body_bytes=body,
      )
    catch {
      @replay.ReplayError(d) => assert_eq(d.code, expected)
    } noraise {
      _ => fail("expected a limit error")
    }
  }
  let empty = @replay.compile_har(fixture([]), max_entries=0, max_body_bytes=0).session()
  empty.finish()
}

///|
test "malformed JSON, duplicate keys, unpaired Unicode and truncated inputs are rejected" {
  rejected("{\"log\":{},\"log\":{}}", "invalid_json")
  rejected("{\"a\":\"\\ud800\"}", "invalid_json")
  rejected("[".repeat(65) + "0" + "]".repeat(65), "invalid_json")
  let source = fixture([entry()])
  for length in 0..<source.length() {
    // Every prefix is incomplete JSON because the complete fixture ends in two braces.
    rejected(source[:length].to_owned(), "invalid_json")
  }
}

///|
test "unsupported body transformations and vendor replay fields produce diagnostics" {
  for
    (name, value, expected) in [
      ("Content-Encoding", "gzip", "unsupported_encoding"),
      ("Transfer-Encoding", "chunked", "unsupported_encoding"),
      ("Content-Type", "text/plain; charset=latin1", "unsupported_charset"),
      ("Upgrade", "websocket", "unsupported_upgrade"),
      ("Bad Header", "x", "invalid_header"),
      ("X-Test", "a\r\nb", "invalid_header"),
    ] {
    let e = entry()
    put(at(e, "response"), "headers", [{ "name": name, "value": value }])
    rejected(fixture([e]), expected)
  }
  for mime in ["text/event-stream", "multipart/form-data; boundary=x"] {
    let e = entry()
    put(at(at(e, "response"), "content"), "mimeType", Json(mime))
    rejected(fixture([e]), "unsupported_body")
  }
  let file = entry()
  put(at(at(file, "response"), "content"), "_file", "body.bin")
  rejected(fixture([file]), "unsupported_field")
  let post = entry()
  put(at(post, "request"), "postData", {
    "mimeType": "application/x-www-form-urlencoded",
    "params": [],
  })
  rejected(fixture([post]), "unsupported_field")
}

///|
test "semantic empty responses, invalid final statuses and URL authorities" {
  for status in [204, 304] {
    let e = entry()
    put(at(e, "response"), "status", Json(status))
    rejected(fixture([e]), "body_forbidden")
    put(at(at(e, "response"), "content"), "text", "")
    put(at(at(e, "response"), "content"), "size", 0)
    put(at(e, "response"), "bodySize", 0)
    assert_eq(@replay.compile_har(fixture([e])).length(), 1)
  }
  for status in [101, 600] {
    let e = entry()
    put(at(e, "response"), "status", Json(status))
    rejected(fixture([e]), "unsupported_status")
  }
  for
    url in [
      "/relative", "https://", "https://example.invalid:99999/a", "https://example.invalid/a#fragment",
      "https://example.invalid/ a",
    ] {
    let e = entry()
    put(at(e, "request"), "url", Json(url))
    try @replay.compile_har(fixture([e])) catch {
      @replay.ReplayError(d) =>
        assert_true(d.code == "unsupported_url" || d.code == "invalid_har")
    } noraise {
      _ => fail("expected invalid URL")
    }
  }
}

///|
test "HEAD keeps representation length while rejecting received content" {
  let e = entry()
  put(at(e, "request"), "method", "HEAD")
  put(at(e, "response"), "bodySize", 0)
  put(at(e, "response"), "headers", [
    { "name": "Content-Length", "value": "4096" },
  ])
  put(at(at(e, "response"), "content"), "text", "")
  put(at(at(e, "response"), "content"), "size", 4096)
  let response = @replay.compile_har(fixture([e]))
    .session()
    .take(@replay.Request::new("HEAD", "https://example.invalid/a"))
  assert_eq(response.body(), b"")
  assert_eq(response.headers(), [("Content-Length", "4096")])
  put(at(at(e, "response"), "content"), "text", "x")
  put(at(e, "response"), "bodySize", 1)
  rejected(fixture([e]), "body_forbidden")
}

///|
test "bodySize, charset spelling variants and missing semantic headers" {
  let length = entry()
  put(at(length, "response"), "bodySize", 1)
  rejected(fixture([length]), "body_length")
  for
    mime in [
      "text/plain; Charset = ISO-8859-1", "text/plain; charset", "Multipart/form-data; boundary=x",
    ] {
    let e = entry()
    put(at(at(e, "response"), "content"), "mimeType", Json(mime))
    rejected(
      fixture([e]),
      if mime.has_prefix("Multipart") {
        "unsupported_body"
      } else {
        "unsupported_charset"
      },
    )
  }
  let redirect = entry()
  put(at(redirect, "response"), "redirectURL", "https://example.invalid/b")
  rejected(fixture([redirect]), "redirect_header")
  let cookie = entry()
  put(at(cookie, "response"), "cookies", [{ "name": "a", "value": "1" }])
  rejected(fixture([cookie]), "missing_cookie_header")
  let request = entry()
  put(at(request, "request"), "bodySize", -1)
  rejected(fixture([request]), "missing_body")
}
