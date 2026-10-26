///|
fn json_export_entry(text : String) -> Json {
  let e = entry()
  let response = at(e, "response")
  let content = at(response, "content")
  put(content, "text", Json(text))
  put(content, "size", Json(@utf8.encode(text).length()))
  put(response, "bodySize", Json(@utf8.encode(text).length()))
  e
}

///|
fn json_export_rejected(
  source : String,
  pointers : Array[String],
  code : String,
) -> Unit raise {
  let cassette = @replay.compile_har(source)
  try cassette.request_plan(assert_json=pointers) catch {
    @replay.ReplayError(d) => {
      assert_eq(d.code, code)
      assert_false(d.format().contains("private-value"))
    }
  } noraise {
    _ => fail("invalid JSON contract exported")
  }
  assert_eq(cassette.source(), source)
  assert_eq(cassette.session().remaining(), cassette.length())
}

///|
test "JSON contract export preserves numeric tokens escaped pointers null and selector order" {
  let body = "{\"id\":9007199254740993,\"amount\":1.00,\"a/b~\":{\"\":null},\"items\":[{\"name\":\"拾响🙂\"}],\"ignored\":\"private-value\"}"
  let source = fixture([json_export_entry(body)])
  let cassette = @replay.compile_har(source)
  let pointers = ["/id", "/amount", "/a~1b~0/", "/items/0/name"]
  let text = cassette.request_plan(assert_json=pointers, assert_headers=[
    "X-Absent",
  ])
  assert_eq(
    text,
    cassette.request_plan(assert_json=pointers, assert_headers=["X-Absent"]),
  )
  pointers.clear()
  guard @json.parse(text, preserve_number_repr=true) is Array(steps) else {
    fail("plan missing")
  }
  let expected = @json.parse(
    "[{\"pointer\":\"/id\",\"value\":9007199254740993},{\"pointer\":\"/amount\",\"value\":1.00},{\"pointer\":\"/a~1b~0/\",\"value\":null},{\"pointer\":\"/items/0/name\",\"value\":\"拾响🙂\"}]",
    preserve_number_repr=true,
  )
  assert_eq(at(steps[0], "expect_json").stringify(), expected.stringify())
  assert_false(text.contains("private-value"))
  assert_eq(cassette.request_plan(assert_json=[]), cassette.request_plan())
  assert_eq(cassette.source(), source)
}

///|
test "JSON contract configuration is checked on empty captures and bounded inclusively" {
  let source = fixture([])
  for
    pointers in [
      ["private-value"],
      ["/bad~2"],
      ["/bad~"],
      ["x".repeat(4097)],
      ["/a".repeat(65)],
      ["/a", "/a"],
      Array::makei(257, i => "/" + i.to_string()),
    ] {
    json_export_rejected(source, pointers, "invalid_plan_option")
  }
  let cassette = @replay.compile_har(source)
  assert_eq(
    cassette.request_plan(
      assert_json=Array::makei(256, i => "/" + i.to_string()),
    ),
    "[]\n",
  )
  assert_eq(cassette.request_plan(assert_json=["/" + "x".repeat(4095)]), "[]\n")
  assert_eq(cassette.request_plan(assert_json=["/a".repeat(64)]), "[]\n")
}

///|
test "JSON contract generation rejects malformed bodies missing fields and noncanonical array selectors" {
  for
    body in [
      "",
      "private-value",
      "{\"a\":1,\"a\":2}",
      "[".repeat(65) + "0" + "]".repeat(65),
    ] {
    let source = fixture([json_export_entry(body)])
    json_export_rejected(source, [""], "plan_json_invalid")
    // No JSON selection retains the original ability to export arbitrary finite response bytes.
    ignore(@replay.compile_har(source).request_plan())
  }
  let binary = entry()
  let content = at(at(binary, "response"), "content")
  put(content, "encoding", "base64")
  put(content, "text", "/wA=")
  json_export_rejected(fixture([binary]), [""], "plan_json_invalid")
  for pointer in ["/missing", "/items/1", "/items/999999999999999999999999999"] {
    json_export_rejected(
      fixture([json_export_entry("{\"items\":[null]}")]),
      [pointer],
      "plan_json_missing",
    )
  }
  for pointer in ["/00", "/-", "/01", "/+0", "/0x"] {
    json_export_rejected(
      fixture([json_export_entry("[null]")]),
      [pointer],
      "plan_json_selector",
    )
  }
  let source = fixture([
    json_export_entry("{\"id\":1}"),
    json_export_entry("{}"),
  ])
  try @replay.compile_har(source).request_plan(assert_json=["/id"]) catch {
    @replay.ReplayError(d) =>
      assert_eq(d.path, "$.log.entries[1].response.content.pointers[0]")
  } noraise {
    _ => fail("later missing field silently dropped")
  }
}

///|
test "JSON root selection handles scalars objects arrays and composes with byte assertions" {
  for
    body in [
      "null", "true", "9007199254740993", "\"拾响\"", "[1,null]", "{\"01\":3}",
    ] {
    let cassette = @replay.compile_har(fixture([json_export_entry(body)]))
    let text = cassette.request_plan(assert_json=[""], assert_bodies=true)
    guard @json.parse(text, preserve_number_repr=true) is Array(steps) else {
      fail("plan missing")
    }
    guard at(steps[0], "expect_json") is Array(assertions) else {
      fail("assertions missing")
    }
    assert_eq(at(assertions[0], "value").stringify(), body)
    assert_eq(
      at(steps[0], "expect_body_base64"),
      Json(@base64.encode(@utf8.encode(body))),
    )
    assert_eq(
      cassette.request_plan(
        assert_json=[""],
        assert_bodies=true,
        max_input_units=text.length(),
      ),
      text,
    )
    try
      cassette.request_plan(
        assert_json=[""],
        assert_bodies=true,
        max_input_units=text.length() - 1,
      )
    catch {
      @replay.ReplayError(d) => assert_eq(d.code, "plan_limit")
    } noraise {
      _ => fail("JSON export exceeded limit")
    }
  }
}

///|
test "generated JSON values respect the downstream expectation size limit" {
  let body = Json("x".repeat(1048574)).stringify()
  let cassette = @replay.compile_har(fixture([json_export_entry(body)]))
  assert_true(cassette.request_plan(assert_json=[""]).contains("expect_json"))
  let too_large = Json("x".repeat(1048575)).stringify()
  json_export_rejected(
    fixture([json_export_entry(too_large)]),
    [""],
    "plan_json_limit",
  )
}
