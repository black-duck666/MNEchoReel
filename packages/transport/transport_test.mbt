///|
fn cassette() -> @replay.Cassette raise @replay.ReplayError {
  let source =
    #|{"log":{"version":"1.2","creator":{"name":"test","version":"1"},"entries":[{"startedDateTime":"2026-10-25T00:00:00Z","time":0,"request":{"method":"GET","url":"https://example.invalid/a","httpVersion":"HTTP/1.1","headers":[],"cookies":[],"queryString":[],"headersSize":-1,"bodySize":0},"response":{"status":200,"statusText":"OK","httpVersion":"HTTP/1.1","headers":[{"name":"Set-Cookie","value":"a=1"},{"name":"Set-Cookie","value":"b=2"}],"cookies":[],"content":{"size":2,"mimeType":"text/plain","text":"ok"},"redirectURL":"","headersSize":-1,"bodySize":2},"cache":{},"timings":{"send":0,"wait":0,"receive":0}}]}}
  @replay.compile_har(source)
}

///|
async test "SDK transport executes buffered and finite stream calls, preserving headers" {
  let session = cassette().session()
  let transport = @transport.ReplayTransport::new(session)
  let reply = transport.send(@http.Request::get("https://example.invalid/a"))
  assert_eq(reply.text(), "ok")
  assert_eq(reply.headers.get_all("set-cookie"), ["a=1", "b=2"])
  reply.headers.set("set-cookie", "changed")
  session.finish()
  session.reset()
  let (head, body) = transport.send_stream(
    @http.Request::get("https://example.invalid/a"),
  )
  assert_eq(head.status, 200)
  assert_eq(head.headers.get_all("set-cookie"), ["a=1", "b=2"])
  assert_eq(body.read_some(), Some(b"ok"))
  assert_eq(body.read_some(), None)
  body.close()
  body.close()
  assert_eq(body.read_some(), None)
  session.finish()
}

///|
async test "transport mismatch can recover; closing unread memory stream is terminal" {
  let session = cassette().session()
  let transport = @transport.ReplayTransport::new(session)
  try
    transport.send(@http.Request::get("https://example.invalid/wrong"))
  catch {
    @http.HttpError::Protocol(message) =>
      assert_true(message.contains("request_mismatch"))
    _ => fail("expected a protocol diagnostic")
  } noraise {
    _ => fail("expected rejection")
  }
  assert_eq(session.remaining(), 1)
  let (_, body) = transport.send_stream(
    @http.Request::get("https://example.invalid/a"),
  )
  body.close()
  assert_eq(body.read_some(), None)
  session.finish()
}

///|
priv struct Probe {
  mut reads : Int32
}

///|
impl @http.BodyStream for Probe with fn read_some(self) {
  self.reads += 1
  Some(b"not consumed")
}

///|
impl @http.BodyStream for Probe with fn close(_self) {
  ()
}

///|
async test "streaming request is refused before reading or consuming" {
  let session = cassette().session()
  let transport = @transport.ReplayTransport::new(session)
  let probe = Probe::{ reads: 0, }
  try
    transport.send(
      @http.Request::get("https://example.invalid/a").body_stream(probe),
    )
  catch {
    @http.HttpError::Protocol(message) =>
      assert_true(message.contains("unsupported_request_stream"))
    _ => fail("expected stream diagnostic")
  } noraise {
    _ => fail("expected rejection")
  }
  assert_eq(probe.reads, 0)
  assert_eq(session.remaining(), 1)
  ignore(transport.send(@http.Request::get("https://example.invalid/a")))
  session.finish()
}
