///|
test "reported verification distinguishes attempted checks skipped steps and atomic commit" {
  let session = @replay.compile_har(recording()).session()
  let plan = @plan.Plan::new([
    (req("a"), @replay.Expectation::new()),
    (req("b"), @replay.Expectation::new(status=404)),
    (req("a"), @replay.Expectation::new()),
  ])
  let report = plan.verify(session)
  assert_false(report.passed())
  assert_eq(report.outcomes(), [@plan.Passed, Failed, Skipped])
  assert_eq(report.completion(), Some(@plan.Skipped))
  assert_eq(session.remaining(), 2)
  assert_eq(report.diagnostic().unwrap().code, "status_mismatch")
  let outcomes = report.outcomes()
  outcomes.clear()
  assert_eq(report.outcomes().length(), 3)
  let json = report.render_json()
  assert_true(json.contains("\"committed\":false"))
  assert_eq(plan.verify(session).render_json(), json)
  let xml = report.render_junit()
  assert_true(
    xml.contains("tests=\"4\" failures=\"1\" errors=\"0\" skipped=\"2\""),
  )
  assert_true(xml.contains("name=\"step.1\"><failure"))
  assert_true(xml.contains("name=\"step.2\"><skipped>"))
  assert_false(xml.contains("https://"))
  assert_false(xml.contains("example.invalid"))
  assert_eq(xml, report.render_junit())
  let success = @plan.Plan::new([
    (req("a"), @replay.Expectation::new()),
    (req("b"), @replay.Expectation::new()),
  ]).verify(session)
  assert_true(success.passed())
  assert_eq(success.outcomes(), [@plan.Passed, Passed])
  assert_eq(success.completion(), Some(@plan.Passed))
  assert_eq(success.diagnostic(), None)
  session.finish()
}

///|
test "completion failures and partial plans have accurate test case counts" {
  let session = @replay.compile_har(recording()).session()
  let partial = @plan.Plan::new([(req("a"), @replay.Expectation::new())])
  let report = partial.verify(session)
  assert_eq(report.outcomes(), [@plan.Passed])
  assert_eq(report.completion(), Some(@plan.Failed))
  assert_eq(report.diagnostic().unwrap().code, "unconsumed")
  assert_eq(session.remaining(), 2)
  assert_true(report.render_junit().contains("name=\"completion\"><failure"))
  let accepted = partial.verify(session, require_complete=false)
  assert_eq(accepted.completion(), None)
  assert_true(accepted.passed())
  assert_eq(session.remaining(), 1)
  assert_true(
    accepted
    .render_junit()
    .contains("tests=\"1\" failures=\"0\" errors=\"0\" skipped=\"0\""),
  )
  let empty = @plan.Plan::new([]).verify(session, require_complete=false)
  assert_eq(empty.outcomes(), [])
  assert_true(empty.passed())
  assert_true(empty.render_junit().contains("tests=\"0\""))
}

///|
test "every failure position restores an existing session prefix" {
  let cassette = @replay.compile_har(recording())
  for prefix in 0..<2 {
    for failed in 0..<(2 - prefix) {
      let session = cassette.session()
      if prefix == 1 {
        ignore(session.take(req("a")))
      }
      let before = session.report().render_json()
      let paths = if prefix == 0 { ["a", "b"] } else { ["b"] }
      let steps = paths.mapi((i, path) => {
        (
          req(path),
          @replay.Expectation::new(status=if i == failed { 404 } else { 200 }),
        )
      })
      let report = @plan.Plan::new(steps).verify(session)
      for i, outcome in report.outcomes() {
        assert_eq(
          outcome,
          if i < failed {
            @plan.Passed
          } else if i == failed {
            @plan.Failed
          } else {
            @plan.Skipped
          },
        )
      }
      assert_eq(report.completion(), Some(@plan.Skipped))
      assert_eq(session.report().render_json(), before)
    }
  }
}
