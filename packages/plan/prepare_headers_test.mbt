///|
fn header_recording(headers : Array[(String, String)]) -> String raise {
  let root = @json.parse(recording())
  guard root is { "log": { "entries": Array(entries), .. }, .. } else {
    fail("fixture entries missing")
  }
  for entry in entries {
    guard entry is { "response": Object(response), .. } else {
      fail("fixture response missing")
    }
    response.set(
      "headers",
      Json(
        headers.map(pair => {
          let value : Json = { "name": pair.0, "value": pair.1 }
          value
        }),
      ),
    )
  }
  root.stringify()
}

///|
test "generated header contracts replay and fail atomically after duplicate order or absence changes" {
  let headers = [("X-Contract", "a"), ("x-contract", "b")]
  let cassette = @replay.compile_har(header_recording(headers))
  let text = cassette.request_plan(assert_headers=["x-contract", "X-Absent"])
  let plan = @plan.parse_plan(text)
  assert_true(plan.verify(cassette.session()).passed())
  for
    changed in [
      [("X-Contract", "b"), ("x-contract", "a")],
      headers + [("X-Absent", "unexpected")],
      [("X-Contract", "a")],
    ] {
    let session = @replay.compile_har(header_recording(changed)).session()
    let report = plan.verify(session)
    assert_false(report.passed())
    assert_eq(report.diagnostic().unwrap().code, "response_header_mismatch")
    assert_eq(session.remaining(), 2)
    assert_false(report.render_json().contains("unexpected"))
  }
  let unrelated = @replay.compile_har(
    header_recording(headers + [("Date", "later")]),
  )
  assert_true(plan.verify(unrelated.session()).passed())
}
