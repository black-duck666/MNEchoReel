///|
fn coded() -> Json {
  let e = entry()
  put(at(e, "response"), "bodySize", 1)
  put(at(e, "response"), "headers", [
    { "name": "Content-Encoding", "value": "gzip" },
    { "name": "Content-Length", "value": "1" },
    { "name": "X-Keep", "value": "a" },
    { "name": "X-Keep", "value": "b" },
  ])
  e
}

///|
test "decoded profile reports every edit and preserves source, body and unrelated headers" {
  let source = fixture([coded()])
  rejected(source, "unsupported_encoding")
  let cassette = @replay.compile_har(source, body_profile=DecodedContent)
  assert_eq(cassette.source(), source)
  let edits = cassette.adaptations()
  assert_eq(edits.length(), 2)
  assert_eq(edits[0].header_index, 0)
  assert_eq(edits[0].before, "gzip")
  assert_eq(edits[0].after, None)
  assert_eq(edits[1].after, Some("2"))
  edits.clear()
  assert_eq(cassette.adaptations().length(), 2)
  assert_true(cassette.adaptation_report_json().contains("\"after\":\"2\""))
  assert_eq(
    cassette.adaptation_report_json(),
    @replay.compile_har(source, body_profile=DecodedContent).adaptation_report_json(),
  )
  let reply = cassette
    .session()
    .take(@replay.Request::new("GET", "https://example.invalid/a"))
  assert_eq(reply.body(), b"ok")
  assert_eq(reply.headers(), [
    ("Content-Length", "2"),
    ("X-Keep", "a"),
    ("X-Keep", "b"),
  ])
  let identity = @replay.compile_har(fixture([entry()]))
  assert_true(identity.adaptations().is_empty())
  assert_true(
    identity
    .compare(
      @replay.compile_har(identity.source(), body_profile=DecodedContent),
    )
    .is_empty(),
  )
}

///|
test "decoded profile refuses incomplete, unknown, framed and integrity-sensitive bodies" {
  for
    (header, value, code) in [
      ("Content-Encoding", "unknown", "unsupported_encoding"),
      ("Transfer-Encoding", "chunked", "unsupported_encoding"),
      ("Digest", "opaque", "unsupported_integrity_adaptation"),
      ("Content-Range", "bytes 0-1/2", "unsupported_integrity_adaptation"),
    ] {
    let e = coded()
    put(at(e, "response"), "headers", [
      { "name": "Content-Encoding", "value": "gzip" },
      { "name": header, "value": value },
    ])
    try @replay.compile_har(fixture([e]), body_profile=DecodedContent) catch {
      @replay.ReplayError(d) => assert_eq(d.code, code)
    } noraise {
      _ => fail("unsupported adaptation accepted")
    }
  }
  let e = coded()
  put(at(e, "response"), "bodySize", -1)
  try @replay.compile_har(fixture([e]), body_profile=DecodedContent) catch {
    @replay.ReplayError(d) => assert_eq(d.code, "wire_length_unknown")
  } noraise {
    _ => fail("unknown wire size accepted")
  }
  put(at(e, "response"), "bodySize", 1)
  put(at(e, "request"), "method", "HEAD")
  try @replay.compile_har(fixture([e]), body_profile=DecodedContent) catch {
    @replay.ReplayError(d) => assert_eq(d.code, "unsupported_empty_adaptation")
  } noraise {
    _ => fail("representation headers were silently adapted")
  }
}

///|
test "binary decoded content and multiple content codings keep exact bytes" {
  let e = coded()
  put(at(e, "response"), "headers", [
    { "name": "Content-Encoding", "value": "gzip, br" },
  ])
  let content = at(at(e, "response"), "content")
  put(content, "text", "AP8=")
  put(content, "encoding", "base64")
  put(content, "compression", 1)
  let cassette = @replay.compile_har(fixture([e]), body_profile=DecodedContent)
  assert_eq(
    cassette
    .session()
    .take(@replay.Request::new("GET", "https://example.invalid/a"))
    .body(),
    b"\x00\xff",
  )
  put(content, "compression", 2)
  try @replay.compile_har(fixture([e]), body_profile=DecodedContent) catch {
    @replay.ReplayError(d) => assert_eq(d.code, "body_length")
  } noraise {
    _ => fail("inconsistent compression metadata accepted")
  }
}

///|
test "decoded profile still rejects missing bytes and inconsistent encoded length" {
  let e = coded()
  put(at(e, "response"), "headers", [
    { "name": "Content-Encoding", "value": "gzip" },
    { "name": "Content-Length", "value": "9" },
  ])
  try @replay.compile_har(fixture([e]), body_profile=DecodedContent) catch {
    @replay.ReplayError(d) => assert_eq(d.code, "body_length")
  } noraise {
    _ => fail("encoded length mismatch accepted")
  }
  let missing = coded()
  guard at(at(missing, "response"), "content") is Object(content) else {
    abort("fixture")
  }
  content.remove("text")
  try
    @replay.compile_har(fixture([missing]), body_profile=DecodedContent)
  catch {
    @replay.ReplayError(d) => assert_eq(d.code, "missing_body")
  } noraise {
    _ => fail("missing decoded content accepted")
  }
}
