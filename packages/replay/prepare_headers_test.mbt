///|
test "selected response header export preserves duplicate order casing absence and default output" {
  let e = entry()
  put(at(e, "response"), "headers", [
    { "name": "X-Contract", "value": "first" },
    { "name": "x-contract", "value": "second" },
    { "name": "X-Unselected", "value": "secret" },
  ])
  let source = fixture([e])
  let cassette = @replay.compile_har(source)
  let original = cassette.request_plan()
  let names = ["X-Contract", "X-Absent"]
  let output = cassette.request_plan(assert_headers=names)
  assert_eq(output, cassette.request_plan(assert_headers=names))
  names.clear()
  guard @json.parse(output) is Array(steps) else { fail("plan missing") }
  let expected : Json = [
    { "name": "X-Contract", "values": ["first", "second"] },
    { "name": "X-Absent", "values": [] },
  ]
  assert_eq(at(steps[0], "expect_headers"), expected)
  assert_false(output.contains("X-Unselected"))
  assert_false(output.contains("secret"))
  assert_eq(cassette.request_plan(assert_headers=[]), original)
  assert_eq(cassette.source(), source)
  assert_eq(cassette.session().remaining(), 1)
}

///|
test "header export rejects invalid duplicate and excessive selectors even with no exchanges" {
  let cassette = @replay.compile_har(fixture([]))
  let excessive = Array::makei(257, i => "X-" + i.to_string())
  for names in [[""], ["Bad Header"], ["X-Secret\r\n"], ["x", "X"], excessive] {
    try cassette.request_plan(assert_headers=names) catch {
      @replay.ReplayError(d) => {
        assert_eq(d.code, "invalid_plan_option")
        assert_true(d.path.has_prefix("$plan.assert_headers"))
        assert_false(d.format().contains("X-Secret"))
      }
    } noraise {
      _ => fail("invalid header selection accepted")
    }
  }
  assert_eq(
    @json.parse(
      cassette.request_plan(assert_headers=excessive[:256].to_owned()),
    ),
    Json::array([]),
  )
}

///|
test "header assertions compose with binary body assertions and inclusive export limits" {
  let cassette = @replay.compile_har(fixture([entry()]))
  let text = cassette.request_plan(
    assert_headers=["X-Absent"],
    assert_bodies=true,
  )
  assert_eq(
    cassette.request_plan(
      assert_headers=["X-Absent"],
      assert_bodies=true,
      max_input_units=text.length(),
    ),
    text,
  )
  try
    cassette.request_plan(
      assert_headers=["X-Absent"],
      assert_bodies=true,
      max_input_units=text.length() - 1,
    )
  catch {
    @replay.ReplayError(d) => assert_eq(d.code, "plan_limit")
  } noraise {
    _ => fail("export limit ignored")
  }
  guard @json.parse(text) is Array(steps) else { fail("plan missing") }
  assert_eq(at(steps[0], "expect_body_base64"), Json("b2s="))
  let expected : Json = [{ "name": "X-Absent", "values": [] }]
  assert_eq(at(steps[0], "expect_headers"), expected)
}
