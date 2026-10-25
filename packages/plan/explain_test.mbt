///|
test "reported mismatch explanations capture failure-point consumption before atomic rollback" {
  let session = @replay.compile_har(recording()).session()
  let plan = @plan.Plan::new([
    (req("a"), @replay.Expectation::new()),
    (req("wrong-secret"), @replay.Expectation::new()),
  ])
  let report = plan.verify(session, explain_mismatches=true)
  assert_false(report.passed())
  let explanation = report.explanation().unwrap()
  assert_eq(explanation.outcome(), "request_mismatch")
  assert_eq(explanation.candidates().map(c => c.consumed), [false, true])
  assert_eq(session.remaining(), 2)
  assert_true(report.render_json().contains("\"explanation\""))
  assert_false(report.render_json().contains("wrong-secret"))
  assert_true(plan.verify(session).explanation() is None)
  let assertion = @plan.Plan::new([
    (req("a"), @replay.Expectation::new(status=404)),
  ]).verify(session, explain_mismatches=true)
  assert_true(assertion.explanation() is None)
}
