///|
test "response assertions are exact and atomic across all fields" {
  let e = entry()
  put(at(e, "response"), "headers", [
    { "name": "Set-Cookie", "value": "a=1" },
    { "name": "Set-Cookie", "value": "b=2" },
  ])
  let session = @replay.compile_har(fixture([e])).session()
  let request = @replay.Request::new("GET", "https://example.invalid/a")
  for
    (expectation, code) in [
      (@replay.Expectation::new(status=404), "status_mismatch"),
      (@replay.Expectation::new(body=b"secret"), "response_body_mismatch"),
      (
        @replay.Expectation::new(headers=[("set-cookie", ["b=2", "a=1"])]),
        "response_header_mismatch",
      ),
      (
        @replay.Expectation::new(headers=[("set-cookie", [])]),
        "response_header_mismatch",
      ),
    ] {
    try session.take_checked(request, expectation) catch {
      @replay.ReplayError(d) => {
        assert_eq(d.code, code)
        assert_false(d.format().contains("secret"))
        assert_false(d.format().contains("a=1"))
      }
    } noraise {
      _ => fail("expected assertion failure")
    }
    assert_eq(session.remaining(), 1)
  }
  let values = ["a=1", "b=2"]
  let checks = [("SET-COOKIE", values), ("missing", [])]
  let expected = @replay.Expectation::new(
    status=200,
    body=b"ok",
    headers=checks,
  )
  values.clear()
  checks.clear()
  ignore(session.take_checked(request, expected))
  session.finish()
}

///|
test "invalid expectations reject contradictory headers and invalid statuses" {
  for headers in [[("X", []), ("x", ["value"])], [("Bad Header", [])]] {
    try @replay.Expectation::new(headers~) catch {
      @replay.ReplayError(d) => assert_eq(d.code, "invalid_expectation")
    } noraise {
      _ => fail("invalid expectation accepted")
    }
  }
  try @replay.Expectation::new(status=199) catch {
    @replay.ReplayError(d) => assert_eq(d.code, "invalid_expectation")
  } noraise {
    _ => fail("invalid status accepted")
  }
  let response = @replay.compile_har(fixture([entry()]))
    .session()
    .take(@replay.Request::new("GET", "https://example.invalid/a"))
  @replay.Expectation::new().check(response)
}
