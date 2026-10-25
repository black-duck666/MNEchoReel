///|
test "presence distinguishes null from missing and accepts escaped keys and root" {
  let session = json_session(
    "{\"value\":null,\"a/b\":{\"~\":false},\"list\":[null]}",
  )
  let required = ["", "/value", "/a~1b/~0", "/list/0"]
  let forbidden = [
    "/missing", "/list/1", "/missing/child", "/list/999999999999999999999999",
  ]
  let expected = @replay.Expectation::new(
    json_present=required,
    json_absent=forbidden,
  )
  required.clear()
  forbidden.clear()
  ignore(
    session.take_checked(
      @replay.Request::new("GET", "https://example.invalid/a"),
      expected,
    ),
  )
  session.finish()
}

///|
test "failed or malformed presence checks do not consume and never disclose pointer values" {
  let session = json_session("{\"token-secret\":null,\"list\":[1]}")
  let request = @replay.Request::new("GET", "https://example.invalid/a")
  for
    (expected, code) in [
      (
        @replay.Expectation::new(json_present=["/missing-secret"]),
        "response_json_missing",
      ),
      (
        @replay.Expectation::new(json_absent=["/token-secret"]),
        "response_json_present",
      ),
      (
        @replay.Expectation::new(json_absent=["/list/00"]),
        "response_json_selector",
      ),
      (
        @replay.Expectation::new(json_absent=["/list/-"]),
        "response_json_selector",
      ),
      (
        @replay.Expectation::new(json_absent=["/list/999999999999x"]),
        "response_json_selector",
      ),
    ] {
    try session.take_checked(request, expected) catch {
      @replay.ReplayError(d) => {
        assert_eq(d.code, code)
        assert_false(d.format().contains("secret"))
      }
    } noraise {
      _ => fail("presence guard accepted invalid input")
    }
    assert_eq(session.remaining(), 1)
  }
  ignore(
    session.take_checked(
      request,
      @replay.Expectation::new(json_present=["/token-secret"]),
    ),
  )
  session.finish()
  let malformed = json_session("not JSON")
  try
    malformed.take_checked(
      request,
      @replay.Expectation::new(json_absent=["/anything"]),
    )
  catch {
    @replay.ReplayError(d) => assert_eq(d.code, "response_json_invalid")
  } noraise {
    _ => fail("invalid body bypassed absence check")
  }
  assert_eq(malformed.remaining(), 1)
}

///|
test "presence configuration rejects conflicts and shares the JSON assertion budget" {
  for expected in [0, 1] {
    try
      @replay.Expectation::new(
        json=if expected == 0 { [("/x", "null")] } else { [] },
        json_present=if expected == 1 { ["/x"] } else { [] },
        json_absent=["/x"],
      )
    catch {
      @replay.ReplayError(d) => assert_eq(d.code, "invalid_expectation")
    } noraise {
      _ => fail("contradictory guard accepted")
    }
  }
  ignore(
    @replay.Expectation::new(json=Array::make(255, ("/x", "null")), json_present=[
      "/x",
    ]),
  )
  try
    @replay.Expectation::new(
      json=Array::make(255, ("/x", "null")),
      json_present=["/x"],
      json_absent=["/other"],
    )
  catch {
    @replay.ReplayError(d) => assert_eq(d.code, "invalid_expectation")
  } noraise {
    _ => fail("combined limit ignored")
  }
  try @replay.Expectation::new(json_absent=["/~bad"]) catch {
    @replay.ReplayError(d) => assert_eq(d.code, "invalid_expectation")
  } noraise {
    _ => fail("malformed pointer accepted")
  }
}
