///|
test "derived plans execute deterministically with strict request headers and binary response assertions" {
  let source = recording()
  let cassette = @replay.compile_har(source)
  for assert_bodies in [false, true] {
    let text = cassette.request_plan(assert_bodies~)
    assert_eq(text, cassette.request_plan(assert_bodies~))
    let plan = @plan.parse_plan(text)
    assert_eq(plan.length(), 2)
    let responses = plan.run(cassette.session())
    assert_eq(responses[0].body(), b"ok")
    assert_eq(cassette.source(), source)
    assert_eq(text.contains("expect_body_base64"), assert_bodies)
  }
}
