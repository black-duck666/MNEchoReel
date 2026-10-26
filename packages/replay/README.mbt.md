# Replay API

Compile once, create a fresh session per test, and call `finish` after the workflow.
The project-level examples use a real GitHub API capture. This minimal example
also checks that an empty cassette has no outstanding interactions:

```mbt check
///|
test {
  let source = "{\"log\":{\"version\":\"1.2\",\"creator\":{\"name\":\"example\",\"version\":\"1\"},\"entries\":[]}}"
  let cassette = @replay.compile_har(source)
  let session = cassette.session()
  assert_eq(session.remaining(), 0)
  session.finish()
  assert_eq(cassette.source(), source)
  assert_true(cassette.compare(cassette).is_empty())
  assert_eq(cassette.request_plan(assert_headers=["Content-Type"]), "[]\n")
  assert_eq(cassette.request_plan(assert_json=["/id"]), "[]\n")
  let branch = session.fork()
  let value = branch.transaction(s => {
    s.finish()
    42
  })
  assert_eq(value, 42)
}
```

Response checks are optional and exact. This constructor requires no I/O:

```mbt check
///|
test {
  ignore(
    @replay.Expectation::new(status=200, body=b"ok", headers=[
      ("X-Optional", []),
    ]),
  )
}
```
