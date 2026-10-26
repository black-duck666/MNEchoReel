///|
fn json_contract_recording(text : String) -> String raise {
  let root = @json.parse(recording())
  guard root is { "log": { "entries": Array(entries), .. }, .. } else {
    fail("fixture entries missing")
  }
  for entry in entries {
    guard entry is { "response": Object(response), .. } else {
      fail("fixture response missing")
    }
    let length = @utf8.encode(text).length()
    response.set("bodySize", Json(length))
    response.set("content", {
      "size": length,
      "mimeType": "application/json",
      "text": text,
    })
  }
  root.stringify()
}

///|
test "generated JSON contracts replay exact numbers and selected fields with atomic failure recovery" {
  let body = "{\"id\":9007199254740993,\"amount\":1.00,\"optional\":null,\"volatile\":1}"
  let cassette = @replay.compile_har(json_contract_recording(body))
  let plan = @plan.parse_plan(
    cassette.request_plan(assert_json=["/id", "/amount", "/optional"], assert_headers=[
      "X-Absent",
    ]),
  )
  assert_true(plan.verify(cassette.session()).passed())
  let untracked = @replay.compile_har(
    json_contract_recording(
      "{\"volatile\":2,\"optional\":null,\"amount\":1.00,\"id\":9007199254740993}",
    ),
  )
  assert_true(plan.verify(untracked.session()).passed())
  for
    changed in [
      body.replace_all(old="9007199254740993", new="9007199254740992"),
      body.replace_all(old="1.00", new="1.0"),
      body.replace_all(old="null", new="true"),
    ] {
    let revised = @replay.compile_har(json_contract_recording(changed))
    let session = revised.session()
    let report = plan.verify(session)
    assert_false(report.passed())
    assert_eq(report.diagnostic().unwrap().code, "response_json_mismatch")
    assert_eq(session.remaining(), 2)
    let corrected = @plan.parse_plan(
      revised.request_plan(assert_json=["/id", "/amount", "/optional"]),
    )
    assert_true(corrected.verify(session).passed())
    session.finish()
  }
}

///|
test "root JSON contract export roundtrips through the public plan parser at the value limit" {
  let body = Json("x".repeat(1048574)).stringify()
  let cassette = @replay.compile_har(json_contract_recording(body))
  let text = cassette.request_plan(assert_json=[""])
  let plan = @plan.parse_plan(text)
  assert_true(plan.verify(cassette.session()).passed())
  assert_eq(text, cassette.request_plan(assert_json=[""]))
}

///|
test "JSON export reserves envelope depth so every generated plan remains parseable" {
  let body = "[".repeat(60) + "0" + "]".repeat(60)
  let cassette = @replay.compile_har(json_contract_recording(body))
  let plan = @plan.parse_plan(cassette.request_plan(assert_json=[""]))
  assert_true(plan.verify(cassette.session()).passed())
  let deeper = "[".repeat(61) + "0" + "]".repeat(61)
  let too_deep = @replay.compile_har(json_contract_recording(deeper))
  try too_deep.request_plan(assert_json=[""]) catch {
    @replay.ReplayError(d) => assert_eq(d.code, "plan_json_limit")
  } noraise {
    _ => fail("unparseable generated plan accepted")
  }
  let deepest = "[".repeat(64) + "0" + "]".repeat(64)
  let leaf = @replay.compile_har(json_contract_recording(deepest))
  let selected = @plan.parse_plan(
    leaf.request_plan(assert_json=["/0".repeat(64)]),
  )
  assert_true(selected.verify(leaf.session()).passed())
}
