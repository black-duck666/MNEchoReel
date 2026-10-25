///|
test "request-plan export preserves UTF-8 BOM Unicode escapes duplicate headers and binary responses" {
  let e = entry()
  let request = at(e, "request")
  put(request, "method", "POST")
  let text = "\uFEFF拾响🙂\"\\\n"
  put(request, "postData", {
    "mimeType": "text/plain; charset=utf-8",
    "text": text,
  })
  put(request, "bodySize", Json(@utf8.encode(text).length()))
  put(request, "headers", [
    { "name": "X-Key", "value": "a" },
    { "name": "x-key", "value": "b" },
  ])
  let content = at(at(e, "response"), "content")
  put(content, "text", "/wA=")
  put(content, "encoding", "base64")
  let cassette = @replay.compile_har(fixture([e]), match_headers=["X-Key"])
  let exported = @json.parse(cassette.request_plan(assert_bodies=true))
  guard exported is Array(steps) else { fail("manifest array missing") }
  assert_eq(at(steps[0], "body"), Json(text))
  assert_eq(at(steps[0], "expect_body_base64"), Json("/wA="))
  assert_eq(at(steps[0], "headers"), at(request, "headers"))
  assert_eq(cassette.length(), 1)
  assert_eq(cassette.session().remaining(), 1)
}

///|
test "request-plan export handles empty recordings and every response byte" {
  assert_eq(
    @json.parse(@replay.compile_har(fixture([])).request_plan()),
    Json::array([]),
  )
  for byte in 0..<256 {
    let e = entry()
    let body = Bytes::from_array([byte.to_byte()])
    let content = at(at(e, "response"), "content")
    put(content, "text", Json(@base64.encode(body)))
    put(content, "encoding", "base64")
    put(content, "size", 1)
    put(at(e, "response"), "bodySize", 1)
    let cassette = @replay.compile_har(fixture([e]))
    guard @json.parse(cassette.request_plan(assert_bodies=true)) is Array(steps) else {
      fail("manifest missing")
    }
    assert_eq(at(steps[0], "expect_body_base64"), Json(@base64.encode(body)))
  }
}

///|
test "request-plan export enforces an inclusive output limit without altering the cassette" {
  let cassette = @replay.compile_har(fixture([entry()]))
  let text = cassette.request_plan()
  assert_eq(cassette.request_plan(max_input_units=text.length()), text)
  for
    (limit, code) in [
      (0, "invalid_limit"),
      (-1, "invalid_limit"),
      (text.length() - 1, "plan_limit"),
    ] {
    try cassette.request_plan(max_input_units=limit) catch {
      @replay.ReplayError(d) => assert_eq(d.code, code)
    } noraise {
      _ => fail("export limit ignored")
    }
  }
  assert_eq(cassette.request_plan(), text)
  assert_eq(cassette.session().remaining(), 1)
}
