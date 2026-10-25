///|
test "suites continue after a failed case and isolate every fresh session" {
  let cassette = @replay.compile_har(recording())
  let good = @plan.parse_plan(cassette.request_plan())
  let bad = @plan.Plan::new([(req("a"), @replay.Expectation::new(status=404))])
  let cases = [
    @plan.SuiteCase::new("broken", cassette, bad),
    @plan.SuiteCase::new("identity", cassette, good),
  ]
  let report = @plan.verify_suite(cases)
  cases.clear()
  assert_false(report.passed())
  let results = report.cases()
  assert_eq(results.length(), 2)
  assert_false(results[0].1.passed())
  assert_true(results[1].1.passed())
  results.clear()
  assert_eq(report.cases().length(), 2)
  assert_eq(cassette.session().remaining(), 2)
  let xml = report.render_junit()
  assert_true(
    xml.contains(
      "testsuites tests=\"5\" failures=\"1\" errors=\"0\" skipped=\"1\"",
    ),
  )
  assert_true(
    xml.contains("classname=\"echoreel.broken\" name=\"broken.step.0\""),
  )
  assert_true(
    xml.contains("classname=\"echoreel.identity\" name=\"identity.step.0\""),
  )
  assert_eq(xml, report.render_junit())
  assert_false(xml.contains("example.invalid"))
  let repeated = @plan.verify_suite([
    @plan.SuiteCase::new("broken", cassette, bad),
    @plan.SuiteCase::new("identity", cassette, good),
  ])
  assert_eq(repeated.render_json(), report.render_json())
}

///|
test "suite check budgets are inclusive and reject invalid totals before execution" {
  let cassette = @replay.compile_har(recording())
  let plan = @plan.parse_plan(cassette.request_plan())
  let case = @plan.SuiteCase::new("x".repeat(128), cassette, plan)
  assert_true(@plan.verify_suite([case], max_checks=3).passed())
  for limit in [-1, 0, 2] {
    try @plan.verify_suite([case], max_checks=limit) catch {
      @replay.ReplayError(d) => assert_eq(d.code, "suite_limit")
      e => raise e
    } noraise {
      _ => fail("check budget ignored")
    }
  }
  assert_true(@plan.verify_suite([], max_checks=0).passed())
  assert_eq(cassette.session().remaining(), 2)
}

///|
test "suite identities limits empty output and matching modes are explicit" {
  let cassette = @replay.compile_har(recording())
  let plan = @plan.Plan::new([
    (req("b"), @replay.Expectation::new()),
    (req("a"), @replay.Expectation::new()),
  ])
  for name in ["", "a/b", "secret\n", "拾响", "x".repeat(129)] {
    try @plan.SuiteCase::new(name, cassette, plan) catch {
      @replay.ReplayError(d) => {
        assert_eq(d.code, "invalid_case_name")
        assert_false(d.format().contains("secret"))
      }
    } noraise {
      _ => fail("invalid name accepted")
    }
  }
  let case = @plan.SuiteCase::new("reordered", cassette, plan, mode=PerRequest)
  assert_true(@plan.verify_suite([case], max_cases=1).passed())
  for
    (cases, limit, code) in [
      ([case, case], 2, "duplicate_case"),
      ([case], 0, "suite_limit"),
      ([], -1, "suite_limit"),
    ] {
    try @plan.verify_suite(cases, max_cases=limit) catch {
      @replay.ReplayError(d) => assert_eq(d.code, code)
      e => raise e
    } noraise {
      _ => fail("suite preflight accepted invalid cases")
    }
  }
  let empty = @plan.verify_suite([], max_cases=0)
  assert_true(empty.passed())
  assert_true(empty.render_json().contains("\"cases\":[]"))
  assert_true(empty.render_junit().contains("tests=\"0\" failures=\"0\""))
}
