///|
test "read-only explanations follow every actual matching mode without authorizing nearest candidates" {
  let b = entry()
  put(at(b, "request"), "url", "https://example.invalid/b")
  let retry = entry()
  put(at(retry, "response"), "status", 429)
  let cassette = @replay.compile_har(fixture([entry(), b, retry]))
  let request = @replay.Request::new("GET", "https://example.invalid/b")
  let ordered = cassette.session()
  let explanation = ordered.explain(request)
  assert_eq(explanation.outcome(), "request_mismatch")
  assert_eq(explanation.matched_index(), None)
  assert_eq(explanation.candidates()[0].entry_index, 1)
  assert_eq(explanation.candidates()[0].differences, [])
  assert_eq(ordered.remaining(), 3)
  assert_eq(at(explanation.to_json(), "next_ordered_index"), Json(0))
  for mode in [@replay.ByRequest, PerRequest] {
    let session = cassette.session(mode~)
    let report = session.explain(request)
    assert_eq(report.outcome(), "matched")
    assert_eq(report.matched_index(), Some(1))
    assert_eq(at(report.to_json(), "matched_index"), Json(1))
    assert_eq(session.remaining(), 3)
    assert_eq(session.take(request).status(), 200)
    assert_eq(session.explain(request).outcome(), "no_match")
    assert_true(session.explain(request).candidates()[0].consumed)
  }
  let ambiguous = cassette
    .session(mode=ByRequest)
    .explain(@replay.Request::new("GET", "https://example.invalid/a"))
  assert_eq(ambiguous.outcome(), "ambiguous_request")
  assert_eq(ambiguous.matched_index(), None)
}

///|
test "nearest-field reports redact all HTTP values and isolate nested arrays and JSON" {
  let e = entry()
  put(at(e, "request"), "headers", [
    { "name": "Authorization", "value": "recorded-secret" },
  ])
  let session = @replay.compile_har(fixture([e]), match_headers=[
    "Authorization",
  ]).session()
  let request = @replay.Request::new(
    "POST",
    "https://caller-secret.invalid/",
    body=b"body-secret",
    headers=[("Authorization", "caller-token-secret")],
  )
  let report = session.explain(request)
  let before = report.render_json()
  assert_eq(report.candidates()[0].differences, [
    "method", "url", "body", "selected_headers",
  ])
  for
    value in [
      "recorded-secret", "caller-secret", "body-secret", "caller-token", "example.invalid",
      "Authorization",
    ] {
    assert_false(before.contains(value))
  }
  let values = report.candidates()
  values[0].differences.clear()
  values.clear()
  let json = report.to_json()
  guard at(json, "candidates") is Array(candidates) else {
    fail("candidates missing")
  }
  guard at(candidates[0], "differences") is Array(differences) else {
    fail("differences missing")
  }
  differences.clear()
  candidates.clear()
  assert_eq(report.render_json(), before)
  assert_eq(session.remaining(), 1)
}

///|
test "explanation ranking is bounded stable and prefers unused records for equal distances" {
  let entries = []
  for i in 0..<6 {
    let e = entry()
    put(
      at(e, "request"),
      "url",
      Json("https://example.invalid/" + i.to_string()),
    )
    entries.push(e)
  }
  let session = @replay.compile_har(fixture(entries)).session(mode=ByRequest)
  ignore(session.take(@replay.Request::new("GET", "https://example.invalid/2")))
  let request = @replay.Request::new("GET", "https://no-match.invalid/")
  let report = session.explain(request, max_candidates=3)
  assert_eq(report.candidates().map(c => c.entry_index), [0, 1, 3])
  assert_eq(at(report.to_json(), "truncated"), Json(true))
  assert_eq(
    report.render_json(),
    session.explain(request, max_candidates=3).render_json(),
  )
  assert_eq(
    session
    .explain(request, max_candidates=100)
    .candidates()
    .map(c => c.entry_index),
    [0, 1, 3, 4, 5, 2],
  )
  assert_eq(session.explain(request, max_candidates=0).candidates().length(), 0)
  for limit in [-1, 101] {
    try session.explain(request, max_candidates=limit) catch {
      @replay.ReplayError(d) => assert_eq(d.code, "invalid_limit")
    } noraise {
      _ => fail("invalid candidate limit accepted")
    }
  }
  assert_eq(session.remaining(), 5)
}

///|
test "empty explanations use scalar nulls and snapshots survive later consumption" {
  let request = @replay.Request::new("GET", "https://example.invalid/a")
  let empty = @replay.compile_har(fixture([])).session().explain(request)
  assert_eq(empty.outcome(), "no_match")
  assert_eq(empty.candidates().length(), 0)
  assert_eq(at(empty.to_json(), "matched_index"), Json::null())
  assert_eq(at(empty.to_json(), "next_ordered_index"), Json::null())
  assert_eq(at(empty.to_json(), "truncated"), Json(false))
  let session = @replay.compile_har(fixture([entry()])).session()
  let report = session.explain(request, max_candidates=0)
  let before = report.render_json()
  ignore(session.take(request))
  session.reset()
  assert_eq(report.render_json(), before)
  assert_eq(report.matched_index(), Some(0))
}
