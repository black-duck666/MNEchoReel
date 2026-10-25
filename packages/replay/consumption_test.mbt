///|
test "consumption reports partition all arbitrary states into stable sorted indices" {
  for n in 0..<=8 {
    let entries : Array[Json] = []
    for i in 0..<n {
      let e = entry()
      put(
        at(e, "request"),
        "url",
        Json("https://example.invalid/" + i.to_string()),
      )
      entries.push(e)
    }
    let cassette = @replay.compile_har(fixture(entries))
    for mask in 0..<(1 << n) {
      let session = cassette.session(mode=ByRequest)
      // Consume backwards: reports use original fixture order, not arrival order.
      for j in 0..<n {
        let i = n - j - 1
        if (mask & (1 << i)) != 0 {
          ignore(
            session.take(
              @replay.Request::new(
                "GET",
                "https://example.invalid/" + i.to_string(),
              ),
            ),
          )
        }
      }
      let report = session.report()
      let consumed = report.consumed_indices()
      let remaining = report.remaining_indices()
      assert_eq(consumed.length() + remaining.length(), n)
      assert_eq(remaining.length(), session.remaining())
      for i in 0..<n {
        assert_eq(consumed.contains(i), (mask & (1 << i)) != 0)
        assert_eq(remaining.contains(i), !consumed.contains(i))
      }
      for values in [consumed, remaining] {
        for i in 1..<values.length() {
          assert_true(values[i - 1] < values[i])
        }
      }
      assert_eq(report.render_json(), session.report().render_json())
      let count = consumed.length()
      consumed.clear()
      remaining.clear()
      session.reset()
      assert_eq(report.remaining_indices().length(), n - count)
    }
  }
}

///|
test "reports preserve snapshots across forks resets failed assertions and transaction rollback" {
  let session = @replay.compile_har(fixture([entry(), entry()])).session()
  let request = @replay.Request::new("GET", "https://example.invalid/a")
  ignore(session.take(request))
  let snapshot = session.report()
  let before = snapshot.render_json()
  let branch = session.fork()
  ignore(branch.take(request))
  assert_eq(branch.report().remaining_indices(), [])
  try
    session.take_checked(request, @replay.Expectation::new(status=404))
  catch {
    @replay.ReplayError(_) => ()
  } noraise {
    _ => fail("expected failed assertion")
  }
  assert_eq(session.report().render_json(), before)
  try
    session.transaction(s => {
      s.reset()
      ignore(s.take(request))
      ignore(s.take(request))
      ignore(s.take(request))
    })
  catch {
    @replay.ReplayError(_) => ()
    e => raise e
  } noraise {
    _ => fail("expected rollback")
  }
  assert_eq(session.report().render_json(), before)
  session.reset()
  assert_eq(snapshot.render_json(), before)
  assert_eq(snapshot.consumed_indices(), [0])
  assert_eq(snapshot.remaining_indices(), [1])
  assert_false(before.contains("example.invalid"))
  assert_false(before.contains("ok"))
}
