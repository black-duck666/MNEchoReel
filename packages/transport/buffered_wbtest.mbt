///|
/// Runs on Wasm-GC too, where Moon currently skips async tests.
test "synchronous adapter core rejects an empty recording" {
  let har : Json = {
    "log": {
      "version": "1.2",
      "creator": { "name": "test", "version": "1" },
      "entries": [],
    },
  }
  let session = @replay.compile_har(har.stringify()).session()
  let transport = ReplayTransport::new(session)
  try transport.respond(@http.Request::get("https://example.invalid/a")) catch {
    @http.HttpError::Protocol(message) =>
      assert_true(message.contains("no_match"))
    _ => fail("expected protocol error")
  } noraise {
    _ => fail("empty recording must reject")
  }
  session.finish()
}
