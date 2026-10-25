///|
fn shared_manifest() -> String {
  "[{\"name\":\"one\",\"har\":\"capture\",\"requests\":\"requests\"},{\"name\":\"two\",\"har\":\"capture\",\"requests\":\"requests\",\"mode\":\"per-request\"}]"
}

///|
test "suite manifests retain source and share one read snapshot per exact path" {
  let source = " \n" + shared_manifest() + "\n"
  let manifest = @plan.parse_suite_manifest(source)
  assert_eq(manifest.source(), source)
  assert_eq(manifest.names(), ["one", "two"])
  let names = manifest.names()
  names.clear()
  assert_eq(manifest.names().length(), 2)
  let har = recording()
  let plan = @replay.compile_har(har).request_plan()
  let mut reads = 0
  let cases = manifest.load(path => {
    reads += 1
    match path {
      "capture" => har
      "requests" => plan
      _ => fail("unexpected source")
    }
  })
  assert_eq(reads, 2)
  assert_true(@plan.verify_suite(cases).passed())
  ignore(
    manifest.load(path => {
      reads += 1
      if path == "capture" {
        har
      } else {
        plan
      }
    }),
  )
  assert_eq(reads, 4)
  try manifest.load(_ => "not JSON") catch {
    @replay.ReplayError(d) => {
      assert_eq(d.code, "invalid_json")
      assert_true(d.path.has_prefix("$suite[0].har"))
    }
    e => raise e
  } noraise {
    _ => fail("a later load reused stale compiled input")
  }
}

///|
test "manifest compiled-input budgets charge shared sources once and distinct HAR variants separately" {
  let source = shared_manifest()
  let manifest = @plan.parse_suite_manifest(source)
  let har = recording()
  let plan = @replay.compile_har(har).request_plan()
  let limit = source.length() + har.length() + plan.length()
  let load : (String) -> String raise = path => {
    if path == "capture" {
      har
    } else {
      plan
    }
  }
  assert_eq(manifest.load(load, max_total_input_units=limit).length(), 2)
  try manifest.load(load, max_total_input_units=limit - 1) catch {
    @replay.ReplayError(d) => assert_eq(d.code, "suite_limit")
    e => raise e
  } noraise {
    _ => fail("input budget ignored")
  }
  let variant_source = "[{\"name\":\"one\",\"har\":\"capture\",\"requests\":\"requests\"},{\"name\":\"two\",\"har\":\"capture\",\"requests\":\"requests\",\"decoded\":true}]"
  let variant = @plan.parse_suite_manifest(variant_source)
  let mut reads = 0
  let loaded = variant.load(
    path => {
      reads += 1
      load(path)
    },
    max_total_input_units=variant_source.length() +
      har.length() * 2 +
      plan.length(),
  )
  assert_eq(reads, 2)
  assert_true(@plan.verify_suite(loaded).passed())
  try
    variant.load(
      load,
      max_total_input_units=variant_source.length() +
        har.length() +
        plan.length(),
    )
  catch {
    @replay.ReplayError(d) => assert_eq(d.code, "suite_limit")
    e => raise e
  } noraise {
    _ => fail("distinct compilation variant was not budgeted")
  }
}

///|
test "shared HAR snapshots do not merge distinct selected-header matchers" {
  let source = "[{\"name\":\"plain\",\"har\":\"capture\",\"requests\":\"requests\"},{\"name\":\"selected\",\"har\":\"capture\",\"requests\":\"requests\",\"match_headers\":[\"X-Mode\"]}]"
  let plan = "[{\"method\":\"GET\",\"url\":\"https://example.invalid/a\",\"headers\":[{\"name\":\"X-Mode\",\"value\":\"changed\"}]},{\"method\":\"GET\",\"url\":\"https://example.invalid/b\"}]"
  let har = recording()
  let manifest = @plan.parse_suite_manifest(source)
  let mut reads = 0
  let report = @plan.verify_suite(
    manifest.load(path => {
      reads += 1
      if path == "capture" {
        har
      } else {
        plan
      }
    }),
  )
  assert_eq(reads, 2)
  assert_true(report.cases()[0].1.passed())
  assert_false(report.cases()[1].1.passed())
}

///|
suberror SuiteReadFailure {
  SuiteReadFailure
}

///|
test "suite loaders preserve original errors and recover on a fresh invocation" {
  let manifest = @plan.parse_suite_manifest(shared_manifest())
  try manifest.load(_ => raise SuiteReadFailure) catch {
    SuiteReadFailure => ()
    e => raise e
  } noraise {
    _ => fail("loader failure swallowed")
  }
  let har = recording()
  let plan = @replay.compile_har(har).request_plan()
  assert_true(
    @plan.verify_suite(
      manifest.load(path => if path == "capture" { har } else { plan }),
    ).passed(),
  )
}

///|
test "all suite metadata validates before a loader can be called" {
  for
    source in [
      "[]", "[{}]", "[{\"name\":\"x\",\"name\":\"y\"}]", "[{\"name\":\"x\",\"har\":\"h\",\"requests\":\"p\",\"unknown\":true}]",
      "[{\"name\":\"x\",\"har\":\"h\",\"requests\":\"p\",\"match_headers\":[\"bad header\"]}]",
    ] {
    let mut reads = 0
    try
      @plan.parse_suite_manifest(source).load(_ => {
        reads += 1
        ""
      })
    catch {
      @replay.ReplayError(_) => ()
      e => raise e
    } noraise {
      _ => fail("invalid metadata accepted")
    }
    assert_eq(reads, 0)
  }
  let source = shared_manifest()
  assert_eq(
    @plan.parse_suite_manifest(
      source,
      max_input_units=source.length(),
      max_cases=2,
    )
    .names()
    .length(),
    2,
  )
  for (units, cases) in [(source.length() - 1, 2), (source.length(), 1), (0, 2)] {
    try
      @plan.parse_suite_manifest(source, max_input_units=units, max_cases=cases)
    catch {
      @replay.ReplayError(_) => ()
    } noraise {
      _ => fail("manifest limit ignored")
    }
  }
}
