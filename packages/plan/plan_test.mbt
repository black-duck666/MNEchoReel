///|
fn recording() -> String {
  let entries : Array[Json] = ["a", "b"].map(path => {
    "startedDateTime": "2026-10-25T00:00:00Z",
    "time": 0,
    "request": {
      "method": "GET",
      "url": "https://example.invalid/" + path,
      "httpVersion": "HTTP/1.1",
      "headers": [],
      "cookies": [],
      "queryString": [],
      "headersSize": -1,
      "bodySize": 0,
    },
    "response": {
      "status": 200,
      "statusText": "OK",
      "httpVersion": "HTTP/1.1",
      "headers": [],
      "cookies": [],
      "content": { "size": 2, "mimeType": "text/plain", "text": "ok" },
      "redirectURL": "",
      "headersSize": -1,
      "bodySize": 2,
    },
    "cache": {},
    "timings": { "send": 0, "wait": 0, "receive": 0 },
  })
  let root : Json = {
    "log": {
      "version": "1.2",
      "creator": { "name": "test", "version": "1" },
      "entries": entries,
    },
  }
  root.stringify()
}

///|
fn req(path : String) -> @replay.Request {
  @replay.Request::new("GET", "https://example.invalid/" + path)
}

///|
test "plan failure and final completion checks roll back the entire run" {
  let cassette = @replay.compile_har(recording())
  let session = cassette.session()
  let steps = [
    (req("a"), @replay.Expectation::new()),
    (req("b"), @replay.Expectation::new(status=404)),
  ]
  let broken = @plan.Plan::new(steps)
  steps.clear()
  assert_eq(broken.length(), 2)
  try broken.run(session) catch {
    @replay.ReplayError(d) => {
      assert_eq(d.code, "status_mismatch")
      assert_true(d.path.has_prefix("$plan[1]"))
    }
    e => raise e
  } noraise {
    _ => fail("partial plan accepted")
  }
  assert_eq(session.remaining(), 2)
  let partial = @plan.Plan::new([(req("a"), @replay.Expectation::new())])
  try partial.run(session) catch {
    @replay.ReplayError(d) => assert_eq(d.code, "unconsumed")
    e => raise e
  } noraise {
    _ => fail("unfinished plan accepted")
  }
  assert_eq(session.remaining(), 2)
  assert_eq(partial.run(session, require_complete=false).length(), 1)
  assert_eq(session.remaining(), 1)
  let tail = @plan.Plan::new([(req("b"), @replay.Expectation::new(body=b"ok"))])
  assert_eq(tail.run(session)[0].status(), 200)
  session.finish()
}

///|
test "parsed plans are reusable and respect a supplied out-of-order session" {
  let plan = @plan.parse_plan(
    "[{\"method\":\"GET\",\"url\":\"https://example.invalid/b\",\"expect_body_base64\":\"b2s=\"},{\"method\":\"GET\",\"url\":\"https://example.invalid/a\",\"expect_headers\":[{\"name\":\"absent\",\"values\":[]}]}]",
  )
  let cassette = @replay.compile_har(recording())
  for _ in 0..<2 {
    let session = cassette.session(mode=ByRequest)
    let responses = plan.run(session)
    assert_eq(responses.length(), 2)
    responses.clear()
    session.finish()
  }
  let ordered = cassette.session()
  try plan.run(ordered) catch {
    @replay.ReplayError(d) => assert_eq(d.code, "request_mismatch")
    e => raise e
  } noraise {
    _ => fail("matching mode ignored")
  }
  assert_eq(ordered.remaining(), 2)
  assert_eq(
    @plan.Plan::new([])
    .run(
      @replay.compile_har(
        "{\"log\":{\"version\":\"1.2\",\"creator\":{\"name\":\"test\",\"version\":\"1\"},\"entries\":[]}}",
      ).session(),
    )
    .length(),
    0,
  )
}

///|
test "manifest validation is complete bounded deterministic and secret free" {
  for
    source in [
      "{}", "[", "[{\"method\":\"GET\",\"method\":\"POST\"}]", "[{\"method\":\"GET\",\"url\":\"secret\",\"extra\":true}]",
      "[{\"method\":\"GET\",\"url\":\"x\",\"headers\":[{\"name\":\"x\",\"value\":\"y\",\"extra\":0}]}]",
      "[{\"method\":\"GET\",\"url\":\"x\",\"expect_json\":[{\"pointer\":\"\"}]}]",
      "[{\"method\":\"GET\",\"url\":\"x\",\"body\":7}]", "[{\"method\":\"GET\",\"url\":\"x\",\"expect_body\":\"ok\",\"expect_body_base64\":\"b2s=\"}]",
      "[{\"method\":\"GET\",\"url\":\"x\",\"expect_body_base64\":\"Zh==\"}]",
    ] {
    for _ in 0..<2 {
      try @plan.parse_plan(source) catch {
        @replay.ReplayError(d) => {
          assert_eq(d.code, "manifest_error")
          assert_false(d.format().contains("secret"))
        }
      } noraise {
        _ => fail("invalid plan accepted")
      }
    }
  }
  assert_eq(@plan.parse_plan("[]", max_input_units=2, max_steps=0).length(), 0)
  for (limit, steps) in [(1, 0), (0, 0), (2, -1)] {
    try @plan.parse_plan("[]", max_input_units=limit, max_steps=steps) catch {
      @replay.ReplayError(d) => assert_eq(d.code, "manifest_error")
    } noraise {
      _ => fail("invalid limits accepted")
    }
  }
  try
    @plan.parse_plan("[{\"method\":\"GET\",\"url\":\"x\"}]", max_steps=0)
  catch {
    @replay.ReplayError(d) => assert_eq(d.code, "manifest_error")
  } noraise {
    _ => fail("step limit ignored")
  }
}

///|
test "a malformed final step is rejected before a workflow exists" {
  let prefix = "[{\"method\":\"GET\",\"url\":\"https://example.invalid/a\"},"
  try
    @plan.parse_plan(
      prefix +
      "{\"method\":\"GET\",\"url\":\"https://example.invalid/b\",\"expect_json\":[{\"pointer\":\"/~x-secret\",\"value\":null}]}]",
    )
  catch {
    @replay.ReplayError(d) => {
      assert_eq(d.code, "invalid_expectation")
      assert_eq(d.path, "$plan[1].expect.json")
      assert_false(d.format().contains("secret"))
    }
  } noraise {
    _ => fail("malformed last step accepted")
  }
  let valid = "[{\"method\":\"GET\",\"url\":\"https://example.invalid/a\"}]"
  for n in 0..<valid.length() {
    try @plan.parse_plan(valid[:n].to_owned()) catch {
      @replay.ReplayError(d) => assert_eq(d.code, "manifest_error")
    } noraise {
      _ => fail("truncated plan accepted")
    }
  }
  assert_eq(
    @plan.parse_plan(valid, max_input_units=valid.length(), max_steps=1).length(),
    1,
  )
}
