///|
test "source preservation, deterministic sessions and independent consumption" {
  let source = " \n" + fixture([entry(), entry()]) + "\n"
  let cassette = @replay.compile_har(source)
  assert_eq(cassette.source(), source)
  assert_eq(cassette.length(), 2)
  let a = cassette.session()
  let b = cassette.session()
  let request = @replay.Request::new("GET", "https://example.invalid/a")
  assert_eq(a.take(request), b.take(request))
  ignore(a.take(request))
  assert_eq(b.remaining(), 1)
  a.finish()
  a.reset()
  assert_eq(a.remaining(), 2)
  assert_eq(a.take(request), b.take(request))
}

///|
test "mismatch is recoverable, secret-free and does not consume" {
  let cassette = @replay.compile_har(fixture([entry()]), match_headers=[
    "Authorization",
  ])
  let session = cassette.session()
  try
    session.take(
      @replay.Request::new("GET", "https://example.invalid/a", headers=[
        ("Authorization", "secret-token"),
      ]),
    )
  catch {
    @replay.ReplayError(d) => {
      assert_eq(d.code, "request_mismatch")
      assert_true(d.path.has_suffix("selected_headers"))
      assert_false(d.format().contains("secret-token"))
    }
  } noraise {
    _ => fail("expected mismatch")
  }
  assert_eq(session.remaining(), 1)
  try session.finish() catch {
    @replay.ReplayError(d) => assert_eq(d.code, "unconsumed")
  } noraise {
    _ => fail("expected unconsumed")
  }
  assert_eq(
    session
    .take(@replay.Request::new("GET", "https://example.invalid/a"))
    .body(),
    b"ok",
  )
  session.finish()
  try
    session.take(@replay.Request::new("GET", "https://example.invalid/a"))
  catch {
    @replay.ReplayError(d) => assert_eq(d.code, "no_match")
  } noraise {
    _ => fail("expected exhaustion")
  }
}

///|
test "strict ordering supports 429 then 200; unordered mode refuses ambiguity atomically" {
  let first = entry()
  put(at(first, "response"), "status", 429)
  let cassette = @replay.compile_har(fixture([first, entry()]))
  let request = @replay.Request::new("GET", "https://example.invalid/a")
  let ordered = cassette.session()
  assert_eq(ordered.take(request).status(), 429)
  assert_eq(ordered.take(request).status(), 200)
  ordered.finish()
  let unordered = cassette.session(mode=ByRequest)
  try unordered.take(request) catch {
    @replay.ReplayError(d) => assert_eq(d.code, "ambiguous_request")
  } noraise {
    _ => fail("expected ambiguity")
  }
  assert_eq(unordered.remaining(), 2)
}

///|
test "unordered distinct paths, equivalent duplicates and exact query ordering" {
  let second = entry()
  put(at(second, "request"), "url", "https://example.invalid/b?x=1&y=2")
  let session = @replay.compile_har(fixture([entry(), second, entry()])).session(
    mode=ByRequest,
  )
  try
    session.take(
      @replay.Request::new("GET", "https://example.invalid/b?y=2&x=1"),
    )
  catch {
    @replay.ReplayError(d) => assert_eq(d.code, "no_match")
  } noraise {
    _ => fail("query ordering was normalized")
  }
  ignore(
    session.take(
      @replay.Request::new("GET", "https://example.invalid/b?x=1&y=2"),
    ),
  )
  ignore(session.take(@replay.Request::new("GET", "https://example.invalid/a")))
  ignore(session.take(@replay.Request::new("GET", "https://example.invalid/a")))
  session.finish()
}

///|
test "repeated header order preserved and returned arrays cannot alter later sessions" {
  let e = entry()
  put(at(e, "response"), "headers", [
    { "name": "Set-Cookie", "value": "a=1" },
    { "name": "Set-Cookie", "value": "b=2" },
  ])
  put(at(e, "request"), "headers", [
    { "name": "X-Variant", "value": "a" },
    { "name": "x-variant", "value": "b" },
  ])
  let names = ["x-variant"]
  let cassette = @replay.compile_har(fixture([e]), match_headers=names)
  names[0] = "ignored"
  let pairs = [("X-VARIANT", "a"), ("x-variant", "b")]
  let request = @replay.Request::new(
    "GET",
    "https://example.invalid/a",
    headers=pairs,
  )
  pairs.clear()
  let original = cassette.session().take(request)
  let headers = original.headers()
  assert_eq(headers, [("Set-Cookie", "a=1"), ("Set-Cookie", "b=2")])
  headers.clear()
  assert_eq(cassette.session().take(request), original)
}

///|
test "UTF-8 request bytes participate in identity and errors preserve cursor" {
  let e = entry()
  let req = at(e, "request")
  put(req, "method", "POST")
  put(req, "postData", {
    "mimeType": "text/plain; charset=utf-8",
    "text": "拾响🙂",
  })
  put(req, "bodySize", 10)
  let session = @replay.compile_har(fixture([e])).session()
  try
    session.take(
      @replay.Request::new("POST", "https://example.invalid/a", body=b"wrong"),
    )
  catch {
    @replay.ReplayError(d) => assert_true(d.path.has_suffix("body"))
  } noraise {
    _ => fail("expected body mismatch")
  }
  ignore(
    session.take(
      @replay.Request::new(
        "POST",
        "https://example.invalid/a",
        body=@utf8.encode("拾响🙂"),
      ),
    ),
  )
  session.finish()
}
