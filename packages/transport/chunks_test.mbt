///|
test "response chunk configuration validates before consumption and preserves default adapter" {
  let session = cassette().session()
  let transport = @transport.ReplayTransport::new(session)
  for size in [0, -1] {
    try transport.with_response_chunks(size) catch {
      @replay.ReplayError(d) => assert_eq(d.code, "invalid_transport_option")
    } noraise {
      _ => fail("invalid chunk size accepted")
    }
    assert_eq(session.remaining(), 1)
  }
  ignore(transport.with_response_chunks(2147483647))
}

///|
async test "configured SDK chunks preserve response headers bytes consumption and independent streams" {
  let session = cassette().session()
  let original = @transport.ReplayTransport::new(session)
  let chunked = original.with_response_chunks(1)
  let (head, stream) = chunked.send_stream(
    @http.Request::get("https://example.invalid/a"),
  )
  assert_eq(head.headers.get_all("set-cookie"), ["a=1", "b=2"])
  session.finish()
  session.reset()
  let (_, whole) = original.send_stream(
    @http.Request::get("https://example.invalid/a"),
  )
  assert_eq(whole.read_some(), Some(b"ok"))
  assert_eq(whole.read_some(), None)
  assert_eq(stream.read_some(), Some(b"o"))
  assert_eq(stream.read_some(), Some(b"k"))
  assert_eq(stream.read_some(), None)
  stream.close()
  session.reset()
  assert_eq(
    chunked.send(@http.Request::get("https://example.invalid/a")).body,
    b"ok",
  )
  session.finish()
}
