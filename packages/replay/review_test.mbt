///|
fn named(url : String) -> Json {
  let e = entry()
  put(at(e, "request"), "url", Json("https://example.invalid/" + url))
  e
}

///|
test "LCS review isolates inserted calls and all aligned response changes" {
  let a = @replay.compile_har(fixture([named("a"), named("b")]))
  let changed = named("b")
  put(at(changed, "response"), "status", 404)
  put(at(changed, "response"), "headers", [
    { "name": "X-Test", "value": "secret" },
  ])
  put(at(at(changed, "response"), "content"), "text", "no")
  let b = @replay.compile_har(fixture([named("a"), named("inserted"), changed]))
  let report = a.compare(b)
  assert_eq(report.changes().map(c => c.kind), [Added, Status, Headers, Body])
  assert_eq(report.changes()[0].after_index, Some(1))
  assert_eq(report.changes()[1].before_index, Some(1))
  assert_eq(report.changes()[1].after_index, Some(2))
  assert_false(report.render_json().contains("secret"))
  assert_true(report.render_json().contains("\"before_index\":1"))
  assert_true(report.render_json().contains("\"after_index\":2"))
  assert_eq(report.render_json(), a.compare(b).render_json())
  report.changes().clear()
  assert_eq(report.changes().length(), 4)
  assert_eq(a.source(), fixture([named("a"), named("b")]))
}

///|
test "review handles duplicates, ties, empty records and explicit header exclusions" {
  let a = @replay.compile_har(fixture([named("a"), named("b"), named("a")]))
  let b = @replay.compile_har(fixture([named("b"), named("a")]))
  assert_eq(a.compare(b).changes().map(c => c.kind), [Removed])
  let empty = @replay.compile_har(fixture([]))
  assert_eq(empty.compare(a).changes().length(), 3)
  assert_eq(a.compare(empty).changes().length(), 3)
  assert_true(empty.compare(empty, max_cells=1).is_empty())
  let dated = named("a")
  put(at(dated, "response"), "headers", [
    { "name": "Date", "value": "different" },
  ])
  let old = @replay.compile_har(fixture([named("a")]))
  let next = @replay.compile_har(fixture([dated]))
  assert_false(old.compare(next).is_empty())
  let ignored = ["date"]
  let report = old.compare(next, ignore_response_headers=ignored)
  ignored.clear()
  assert_true(report.is_empty())
  assert_true(report.render_json().contains("date"))
}

///|
test "review budgets and matcher settings are checked before allocation" {
  let a = @replay.compile_har(fixture([entry()]))
  assert_true(a.compare(a, max_cells=4).is_empty())
  for cells in [0, 3] {
    try a.compare(a, max_cells=cells) catch {
      @replay.ReplayError(d) => assert_eq(d.code, "review_limit")
    } noraise {
      _ => fail("expected budget refusal")
    }
  }
  let b = @replay.compile_har(a.source(), match_headers=["Accept"])
  try a.compare(b) catch {
    @replay.ReplayError(d) => assert_eq(d.code, "incomparable_matchers")
  } noraise {
    _ => fail("expected incompatible request identities")
  }
}
