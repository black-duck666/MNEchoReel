///|
fn json_entry(text : String) -> Json {
  let e = entry()
  put(at(at(e, "response"), "content"), "text", Json(text))
  put(
    at(at(e, "response"), "content"),
    "size",
    Json(@utf8.encode(text).length()),
  )
  put(at(e, "response"), "bodySize", Json(@utf8.encode(text).length()))
  e
}

///|
test "JSON review scopes volatile fields and retains exact numeric IDs and object semantics" {
  let before = @replay.compile_har(
    fixture([
      json_entry(
        "{\"id\":9007199254740992,\"volatile\":1,\"obj\":{\"a\":1,\"b\":2}}",
      ),
    ]),
  )
  let after = @replay.compile_har(
    fixture([
      json_entry(
        "{\"obj\":{\"b\":2,\"a\":1},\"volatile\":2,\"id\":9007199254740993}",
      ),
    ]),
  )
  assert_false(before.compare(after).is_empty())
  assert_true(before.compare(after, json_pointers=["/obj"]).is_empty())
  let names = ["/id"]
  let report = before.compare(after, json_pointers=names)
  names.clear()
  assert_eq(report.json_changes().length(), 1)
  assert_eq(report.json_changes()[0].kind, "changed")
  assert_eq(report.json_changes()[0].pointer_index, 0)
  assert_true(report.render_json().contains("\"json_pointers\":[\"/id\"]"))
  assert_false(report.render_json().contains("900719925"))
  let changes = report.json_changes()
  changes.clear()
  assert_eq(report.json_changes().length(), 1)
}

///|
test "JSON field review distinguishes absent null and arrays after request alignment" {
  let before = @replay.compile_har(
    fixture([json_entry("{\"remove\":null,\"list\":[1,2]}")]),
  )
  let inserted = json_entry("{}")
  put(at(inserted, "request"), "url", "https://example.invalid/inserted")
  let after = @replay.compile_har(
    fixture([inserted, json_entry("{\"add\":null,\"list\":[2,1]}")]),
  )
  let report = before.compare(after, json_pointers=["/add", "/remove", "/list"])
  assert_eq(report.json_changes().map(c => c.kind), [
    "added", "removed", "changed",
  ])
  assert_eq(report.json_changes().map(c => c.after_index), [1, 1, 1])
  assert_eq(report.changes()[0].kind, @replay.Added)
  assert_eq(report.changes()[1].kind, @replay.Body)
}

///|
test "JSON review validates all bodies including unaligned entries and malformed selectors" {
  let empty = @replay.compile_har(fixture([]))
  for text in ["not-secret-json", "{\"x\":1,\"x\":2}"] {
    let bad = @replay.compile_har(fixture([json_entry(text)]))
    try empty.compare(bad, json_pointers=["/x"]) catch {
      @replay.ReplayError(d) => {
        assert_eq(d.code, "review_json_invalid")
        assert_false(d.format().contains("secret"))
      }
    } noraise {
      _ => fail("unaligned invalid JSON was ignored")
    }
  }
  let arrays = @replay.compile_har(fixture([json_entry("[1]")]))
  try arrays.compare(arrays, json_pointers=["/01"]) catch {
    @replay.ReplayError(d) => assert_eq(d.code, "review_json_selector")
  } noraise {
    _ => fail("invalid selector bypassed by equal bytes")
  }
  assert_true(arrays.compare(arrays).is_empty())
  let binary = entry()
  let content = at(at(binary, "response"), "content")
  put(content, "text", "/w==")
  put(content, "encoding", "base64")
  put(content, "size", 1)
  put(at(binary, "response"), "bodySize", 1)
  let binary_recording = @replay.compile_har(fixture([binary]))
  try binary_recording.compare(binary_recording, json_pointers=[""]) catch {
    @replay.ReplayError(d) => assert_eq(d.code, "review_json_invalid")
  } noraise {
    _ => fail("non-UTF8 body accepted for JSON comparison")
  }
}

///|
test "JSON review options are explicit bounded and deterministic" {
  let cassette = @replay.compile_har(fixture([json_entry("{}")]))
  for pointers in [[], ["bad"], ["/~bad"], ["/x", "/x"], Array::make(257, "")] {
    try cassette.compare(cassette, json_pointers=pointers) catch {
      @replay.ReplayError(d) => assert_eq(d.code, "invalid_review_option")
    } noraise {
      _ => fail("invalid JSON review profile accepted")
    }
  }
  let pointers = []
  for i in 0..<256 {
    pointers.push("/field" + i.to_string())
  }
  let report = cassette.compare(cassette, json_pointers=pointers)
  assert_true(report.is_empty())
  assert_eq(
    report.render_json(),
    cassette.compare(cassette, json_pointers=pointers).render_json(),
  )
  assert_false(
    cassette.compare(cassette).render_json().contains("json_pointers"),
  )
}
