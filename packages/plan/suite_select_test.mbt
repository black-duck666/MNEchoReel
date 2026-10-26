///|
fn selection_source(names : Array[String]) -> String {
  let cases = names.map(name => {
    let item : Json = { "name": name, "har": "capture", "requests": "requests" }
    item
  })
  Json(cases).stringify()
}

///|
test "named selection preserves source order and reports complete membership without aliases" {
  let source = selection_source(["a", "b", "c"])
  let manifest = @plan.parse_suite_manifest(source)
  let names = ["c", "a"]
  let selected = manifest.select(names~)
  names.clear()
  assert_eq(selected.names(), ["a", "c"])
  assert_eq(manifest.names(), ["a", "b", "c"])
  assert_eq(selected.source(), source)
  let audit = selected.selection_json()
  guard audit is { "selected": Array(values), "excluded": Array(excluded), .. } else {
    fail("membership audit missing")
  }
  assert_eq(excluded, [Json("b")])
  values.clear()
  excluded.clear()
  assert_eq(selected.names(), ["a", "c"])
  assert_eq(
    selected.selection_json().stringify(),
    manifest.select(names=["a", "c"]).selection_json().stringify(),
  )
}

///|
test "name shards are disjoint exhaustive stable after additions and independent of backend hash seeds" {
  let names = ["a", "b", "aa"]
  for i in 0..<40 {
    names.push("case-" + i.to_string())
  }
  names.push("x".repeat(128))
  let manifest = @plan.parse_suite_manifest(selection_source(names))
  assert_true(
    manifest.select(shard_index=0, shard_count=4).names().contains("aa"),
  )
  assert_true(
    manifest.select(shard_index=1, shard_count=4).names().contains("a"),
  )
  for count in [1, 2, 3, 7, 1024] {
    let seen : Map[String, Bool] = Map([])
    let mut total = 0
    for index in 0..<count {
      let selected = manifest
        .select(shard_index=index, shard_count=count)
        .names()
      assert_eq(selected, names.filter(name => selected.contains(name)))
      for name in selected {
        assert_true(seen.get(name) is None)
        seen.set(name, true)
        total += 1
      }
    }
    assert_eq(total, names.length())
  }
  let larger = @plan.parse_suite_manifest(
    selection_source(["new-case"] + names),
  )
  for index in 0..<7 {
    let original = manifest.select(shard_index=index, shard_count=7).names()
    assert_eq(
      larger
      .select(shard_index=index, shard_count=7)
      .names()
      .filter(name => name != "new-case"),
      original,
    )
  }
}

///|
test "selection validates before loading and empty shards perform no input reads" {
  let manifest = @plan.parse_suite_manifest(selection_source(["a", "b"]))
  for
    (names, index, count, code) in [
      (["unknown"], None, None, "unknown_case"),
      (["a", "a"], None, None, "duplicate_selection"),
      ([], Some(0), None, "invalid_shard"),
      ([], Some(0), Some(0), "invalid_shard"),
      ([], Some(-1), Some(2), "invalid_shard"),
      ([], Some(2), Some(2), "invalid_shard"),
      ([], Some(0), Some(1025), "invalid_shard"),
    ] {
    try manifest.select(names~, shard_index?=index, shard_count?=count) catch {
      @replay.ReplayError(d) => assert_eq(d.code, code)
    } noraise {
      _ => fail("invalid selection accepted")
    }
  }
  let empty = manifest.select(names=["a"], shard_index=0, shard_count=4)
  assert_eq(empty.names(), [])
  let mut reads = 0
  let cases = empty.load(_ => {
    reads += 1
    ""
  })
  assert_eq(reads, 0)
  assert_true(@plan.verify_suite(cases).passed())
  assert_true(
    empty.selection_json().stringify().contains("\"excluded\":[\"a\",\"b\"]"),
  )
}

///|
test "excluded files are not read and selected failures retain original manifest indices" {
  let source = "[{\"name\":\"excluded\",\"har\":\"missing\",\"requests\":\"requests\"},{\"name\":\"chosen\",\"har\":\"capture\",\"requests\":\"requests\"}]"
  let selected = @plan.parse_suite_manifest(source).select(names=["chosen"])
  let har = recording()
  let plan = @replay.compile_har(har).request_plan()
  let cases = selected.load(path => {
    match path {
      "capture" => har
      "requests" => plan
      _ => fail("excluded source was loaded")
    }
  })
  assert_true(@plan.verify_suite(cases).passed())
  try selected.load(_ => "not JSON") catch {
    @replay.ReplayError(d) => assert_true(d.path.has_prefix("$suite[1].har"))
    e => raise e
  } noraise {
    _ => fail("invalid selected input accepted")
  }
}
