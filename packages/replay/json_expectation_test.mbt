///|
fn json_session(text : String) -> @replay.Session raise {
  let e = entry()
  let bytes = @utf8.encode(text).length()
  put(at(at(e, "response"), "content"), "text", Json(text))
  put(at(at(e, "response"), "content"), "size", Json(bytes))
  put(at(e, "response"), "bodySize", Json(bytes))
  @replay.compile_har(fixture([e])).session()
}

///|
test "JSON assertions bound expected text and handle non-UTF8 bodies without changing raw replay" {
  let request = @replay.Request::new("GET", "https://example.invalid/a")
  let e = entry()
  let content = at(at(e, "response"), "content")
  put(content, "text", "/w==")
  put(content, "encoding", "base64")
  put(content, "size", 1)
  put(at(e, "response"), "bodySize", 1)
  let session = @replay.compile_har(fixture([e])).session()
  try
    session.take_checked(request, @replay.Expectation::new(json=[("", "null")]))
  catch {
    @replay.ReplayError(d) => assert_eq(d.code, "response_json_invalid")
  } noraise {
    _ => fail("invalid UTF-8 accepted")
  }
  assert_eq(session.remaining(), 1)
  assert_eq(session.take(request).body(), b"\xff")
  let limit = "\"" + "x".repeat(1048574) + "\""
  ignore(@replay.Expectation::new(json=[("", limit)]))
  try @replay.Expectation::new(json=[("", limit + " ")]) catch {
    @replay.ReplayError(d) => assert_eq(d.code, "invalid_expectation")
  } noraise {
    _ => fail("oversized expected text accepted")
  }
  ignore(@replay.Expectation::new(json=Array::make(256, ("", "0"))))
}

///|
test "JSON selectors preserve exact structure escapes empty keys and numeric IDs" {
  let text = "{\"\":{\"a/b\":{\"~1\":[null,{\"id\":9007199254740993,\"ok\":true}]}},\"volatile\":123}"
  let checks = [
    ("//a~1b/~01/0", "null"),
    ("//a~1b/~01/1", "{\"ok\":true,\"id\":9007199254740993}"),
  ]
  let expectation = @replay.Expectation::new(json=checks)
  checks.clear()
  let session = json_session(text)
  ignore(
    session.take_checked(
      @replay.Request::new("GET", "https://example.invalid/a"),
      expectation,
    ),
  )
  session.finish()
  let root = json_session("[1,2,3]")
  ignore(
    root.take_checked(
      @replay.Request::new("GET", "https://example.invalid/a"),
      @replay.Expectation::new(json=[("", "[1,2,3]")]),
    ),
  )
}

///|
test "JSON failures preserve state do not expose selectors or values and allow recovery" {
  let session = json_session(
    "{\"token-secret\":9007199254740993,\"list\":[1],\"null\":null}",
  )
  let request = @replay.Request::new("GET", "https://example.invalid/a")
  for
    (pointer, value, code) in [
      ("/token-secret", "9007199254740992", "response_json_mismatch"),
      ("/list/0", "1.0", "response_json_mismatch"),
      ("/absent", "null", "response_json_missing"),
      ("/null/child", "null", "response_json_missing"),
      ("/list/01", "1", "response_json_missing"),
      ("/list/-", "1", "response_json_missing"),
      (
        "/list/9999999999999999999999999999999999999", "1", "response_json_missing",
      ),
      ("/list/+0", "1", "response_json_missing"),
    ] {
    try
      session.take_checked(
        request,
        @replay.Expectation::new(json=[(pointer, value)]),
      )
    catch {
      @replay.ReplayError(d) => {
        assert_eq(d.code, code)
        assert_false(d.format().contains("token-secret"))
        assert_false(d.format().contains("900719925474099"))
      }
    } noraise {
      _ => fail("expected JSON failure")
    }
    assert_eq(session.remaining(), 1)
  }
  ignore(
    session.take_checked(
      request,
      @replay.Expectation::new(json=[("/null", "null")]),
    ),
  )
  session.finish()
}

///|
test "JSON assertions reject malformed pointers values duplicates and depth" {
  for
    (pointer, value) in [
      ("bad", "1"),
      ("#fragment", "1"),
      ("/~2", "1"),
      ("/~", "1"),
      ("", "["),
      ("", "{\"x\":1,\"x\":2}"),
      ("", "[".repeat(65) + "0" + "]".repeat(65)),
      ("/x".repeat(65), "0"),
      ("/" + "a".repeat(4096), "0"),
    ] {
    try @replay.Expectation::new(json=[(pointer, value)]) catch {
      @replay.ReplayError(d) => assert_eq(d.code, "invalid_expectation")
    } noraise {
      _ => fail("invalid JSON expectation accepted")
    }
  }
  try @replay.Expectation::new(json=Array::make(257, ("", "0"))) catch {
    @replay.ReplayError(d) => assert_eq(d.code, "invalid_expectation")
  } noraise {
    _ => fail("assertion count accepted")
  }
  for
    text in [
      "not JSON",
      "{\"x\":1,\"x\":2}",
      "[".repeat(65) + "0" + "]".repeat(65),
    ] {
    let session = json_session(text)
    try
      session.take_checked(
        @replay.Request::new("GET", "https://example.invalid/a"),
        @replay.Expectation::new(json=[("", "null")]),
      )
    catch {
      @replay.ReplayError(d) => assert_eq(d.code, "response_json_invalid")
    } noraise {
      _ => fail("malformed body accepted")
    }
    assert_eq(session.remaining(), 1)
    ignore(
      session.take(@replay.Request::new("GET", "https://example.invalid/a")),
    )
  }
}
