///|
fn retry_entry(path : String, status : Int32, header : String) -> Json {
  let e = entry()
  put(at(e, "request"), "url", Json("https://example.invalid/" + path))
  put(at(e, "request"), "headers", [{ "name": "X-Key", "value": header }])
  put(at(e, "response"), "status", Json(status))
  e
}

///|
test "independent retry sequences allow all interleavings and keep per-key order" {
  let cassette = @replay.compile_har(
    fixture([
      retry_entry("a", 429, "one"),
      retry_entry("b", 503, "one"),
      retry_entry("a", 200, "one"),
      retry_entry("b", 201, "one"),
    ]),
  )
  for
    order in [
      ["a", "a", "b", "b"],
      ["a", "b", "a", "b"],
      ["a", "b", "b", "a"],
      ["b", "b", "a", "a"],
      ["b", "a", "b", "a"],
      ["b", "a", "a", "b"],
    ] {
    let session = cassette.session(mode=PerRequest)
    let mut a = 0
    let mut b = 0
    for path in order {
      let expected = if path == "a" {
        if a == 0 {
          429
        } else {
          200
        }
      } else if b == 0 {
        503
      } else {
        201
      }
      assert_eq(
        session
        .take(@replay.Request::new("GET", "https://example.invalid/" + path))
        .status(),
        expected,
      )
      if path == "a" {
        a += 1
      } else {
        b += 1
      }
    }
    session.finish()
  }
  let by_request = cassette.session(mode=ByRequest)
  try
    by_request.take(@replay.Request::new("GET", "https://example.invalid/a"))
  catch {
    @replay.ReplayError(d) => assert_eq(d.code, "ambiguous_request")
  } noraise {
    _ => fail("ByRequest ambiguity behavior changed")
  }
  assert_eq(by_request.remaining(), 4)
}

///|
test "per-request assertions do not skip earlier responses and selected headers define streams" {
  let cassette = @replay.compile_har(
    fixture([
      retry_entry("a", 429, "one"),
      retry_entry("a", 503, "two"),
      retry_entry("a", 200, "one"),
      retry_entry("a", 201, "two"),
    ]),
    match_headers=["x-key"],
  )
  let session = cassette.session(mode=PerRequest)
  let one = @replay.Request::new("GET", "https://example.invalid/a", headers=[
    ("X-Key", "one"),
  ])
  let two = @replay.Request::new("GET", "https://example.invalid/a", headers=[
    ("X-Key", "two"),
  ])
  try session.take_checked(one, @replay.Expectation::new(status=200)) catch {
    @replay.ReplayError(d) => assert_eq(d.code, "status_mismatch")
  } noraise {
    _ => fail("expectation skipped first reply")
  }
  assert_eq(session.remaining(), 4)
  assert_eq(session.take(two).status(), 503)
  let fork = session.fork()
  assert_eq(fork.take(two).status(), 201)
  assert_eq(session.report().consumed_indices(), [1])
  try
    session.transaction(s => {
      ignore(s.take(one))
      ignore(s.take(one))
      ignore(s.take(one))
    })
  catch {
    @replay.ReplayError(d) => assert_eq(d.code, "no_match")
    e => raise e
  } noraise {
    _ => fail("expected stream exhaustion")
  }
  assert_eq(session.report().consumed_indices(), [1])
  assert_eq(session.take(one).status(), 429)
  assert_eq(session.take(one).status(), 200)
  assert_eq(session.take(two).status(), 201)
  session.finish()
  session.reset()
  assert_eq(session.take(one).status(), 429)
  assert_true(session.report().render_json().contains("per_request"))
}
