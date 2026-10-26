///|
fn upload_cassette(
  text : String,
  headers~ : Array[(String, String)] = [],
) -> @replay.Cassette raise {
  let root = @json.parse(cassette().source())
  guard root is { "log": { "entries": Array(entries), .. }, .. } else {
    fail("fixture entries missing")
  }
  guard entries[0] is { "request": Object(request), .. } else {
    fail("fixture request missing")
  }
  request.set("method", "POST")
  request.set("postData", {
    "mimeType": "text/plain; charset=utf-8",
    "text": text,
  })
  request.set("bodySize", Json(@utf8.encode(text).length()))
  request.set(
    "headers",
    Json(
      headers.map(pair => {
        let value : Json = { "name": pair.0, "value": pair.1 }
        value
      }),
    ),
  )
  @replay.compile_har(root.stringify(), match_headers=["X-Contract"])
}

///|
priv struct UploadSource {
  chunks : Array[Bytes]
  fail_at : Int32?
  repeat : Bool
  mut cursor : Int32
  mut reads : Int32
  mut closes : Int32
}

///|
fn upload_source(
  chunks : Array[Bytes],
  fail_at? : Int32,
  repeat~ : Bool = false,
) -> UploadSource {
  { chunks: chunks.copy(), fail_at, repeat, cursor: 0, reads: 0, closes: 0, }
}

///|
impl @http.BodyStream for UploadSource with fn read_some(self) {
  let index = self.reads
  self.reads += 1
  if self.fail_at == Some(index) {
    raise @http.HttpError::Network(phase=Body, message="original-source-error")
  }
  if self.repeat {
    return Some(self.chunks[0])
  }
  let chunk = self.chunks.get(self.cursor)
  if chunk is Some(_) {
    self.cursor += 1
  }
  chunk
}

///|
impl @http.BodyStream for UploadSource with fn close(self) {
  self.closes += 1
}

///|
test "request stream configuration rejects invalid budgets without consuming or changing defaults" {
  let session = cassette().session()
  let original = @transport.ReplayTransport::new(session)
  for (bytes, chunks) in [(-1, 1), (0, 0), (1, -1)] {
    try
      original.with_request_streams(max_bytes=bytes, max_chunks=chunks)
    catch {
      @replay.ReplayError(d) => assert_eq(d.code, "invalid_transport_option")
    } noraise {
      _ => fail("invalid upload budget accepted")
    }
    assert_eq(session.remaining(), 1)
  }
  ignore(original.with_request_streams(max_bytes=0, max_chunks=1))
}

///|
async test "streamed requests roundtrip Unicode bytes across boundaries both response kinds and length modes" {
  let text = "拾响🙂upload"
  let bytes = @utf8.encode(text)
  let headers = [("X-Contract", "first"), ("x-contract", "second")]
  let recording = upload_cassette(text, headers~)
  for size in [1, 2, 3, 7, 100] {
    for known in [false, true] {
      for streaming in [false, true] {
        let chunks : Array[Bytes] = []
        for offset = 0; offset < bytes.length(); {
          let end = (offset + size).min(bytes.length())
          chunks.push(bytes[offset:end].to_owned())
          continue end
        }
        let source = upload_source(chunks)
        let request = @http.Request::post("https://example.invalid/a").body_stream(
          source,
          length?=if known { Some(bytes.length().to_int64()) } else { None },
        )
        let request = {
          ..request,
          headers: @http.Headers::from_array(headers),
        }
        let session = recording.session()
        let transport = @transport.ReplayTransport::new(session)
          .with_response_chunks(1)
          .with_request_streams(
            max_bytes=bytes.length(),
            max_chunks=chunks.length(),
          )
        if streaming {
          let (head, body) = transport.send_stream(request)
          assert_eq(head.headers.get_all("set-cookie"), ["a=1", "b=2"])
          assert_eq(body.read_some(), Some(b"o"))
          assert_eq(body.read_some(), Some(b"k"))
          assert_eq(body.read_some(), None)
          body.close()
        } else {
          assert_eq(transport.send(request).body, b"ok")
        }
        assert_eq(source.closes, 1)
        assert_eq(source.reads, chunks.length() + 1)
        assert_false(request.body.is_replayable())
        session.finish()
      }
    }
  }
  let session = upload_cassette("").session()
  let source = upload_source([b""])
  ignore(
    @transport.ReplayTransport::new(session)
    .with_request_streams(max_bytes=0, max_chunks=1)
    .send(
      @http.Request::post("https://example.invalid/a").body_stream(
        source,
        length=0L,
      ),
    ),
  )
  assert_eq(source.reads, 2)
  assert_eq(source.closes, 1)
  session.finish()
}

///|
async test "upload budgets count empty chunks reject before append and leave HAR consumption recoverable" {
  for
    (chunks, max_bytes, max_chunks, repeat) in [
      ([b"a", b"b"], 1, 4, false),
      ([b""], 0, 2, true),
    ] {
    let session = upload_cassette("ab").session()
    let source = upload_source(chunks, repeat~)
    let transport = @transport.ReplayTransport::new(session).with_request_streams(
      max_bytes~,
      max_chunks~,
    )
    try
      transport.send(
        @http.Request::post("https://example.invalid/a").body_stream(source),
      )
    catch {
      @http.HttpError::Protocol(message) =>
        assert_true(message.contains("request_stream_limit"))
      _ => fail("expected a budget error")
    } noraise {
      _ => fail("unbounded upload accepted")
    }
    assert_true(source.reads <= max_chunks + 1)
    assert_eq(source.closes, 1)
    assert_eq(session.remaining(), 1)
    assert_eq(
      transport.send(
        @http.Request::post("https://example.invalid/a").body_bytes(b"ab"),
      ).body,
      b"ok",
    )
    session.finish()
  }
  let session = upload_cassette("ab").session()
  let source = upload_source([b"a", b"b"])
  let request = @http.Request::post("https://example.invalid/a").body_stream(
    source,
    length=2L,
  )
  let original = @transport.ReplayTransport::new(session)
  let limited = original.with_request_streams(max_bytes=1)
  try limited.send(request) catch {
    @http.HttpError::Protocol(message) =>
      assert_true(message.contains("stream not taken"))
    _ => fail("expected preflight rejection")
  } noraise {
    _ => fail("declared oversize accepted")
  }
  assert_eq(source.reads, 0)
  assert_eq(source.closes, 0)
  assert_true(request.body.is_replayable())
  try original.send(request) catch {
    @http.HttpError::Protocol(message) =>
      assert_true(message.contains("unsupported_request_stream"))
    _ => fail("expected unchanged default rejection")
  } noraise {
    _ => fail("original adapter changed")
  }
  assert_eq(source.reads, 0)
  assert_eq(source.closes, 0)
  ignore(original.with_request_streams(max_bytes=2, max_chunks=2).send(request))
  assert_eq(source.closes, 1)
  session.finish()
}

///|
async test "source errors declared length violations and reuse close once without consuming HAR" {
  for length in [Some(-1L), Some(1L), Some(3L), None] {
    let session = upload_cassette("ab").session()
    let source = upload_source(
      [b"a", b"b"],
      fail_at?=if length == None { Some(1) } else { None },
    )
    let request = @http.Request::post("https://example.invalid/a").body_stream(
      source,
      length?,
    )
    let transport = @transport.ReplayTransport::new(session).with_request_streams(
      max_bytes=4,
    )
    try transport.send(request) catch {
      @http.HttpError::Network(phase=Body, message~) =>
        assert_eq(message, "original-source-error")
      @http.HttpError::Protocol(_) => assert_true(length != None)
      _ => fail("unexpected stream error")
    } noraise {
      _ => fail("bad stream accepted")
    }
    assert_eq(source.closes, 1)
    assert_eq(session.remaining(), 1)
    let reads = source.reads
    try transport.send(request) catch {
      @http.HttpError::Protocol(_) => ()
      _ => fail("expected already-taken error")
    } noraise {
      _ => fail("one-shot source reused")
    }
    assert_eq(source.reads, reads)
    assert_eq(source.closes, 1)
    ignore(
      transport.send(
        @http.Request::post("https://example.invalid/a").body_bytes(b"ab"),
      ),
    )
    session.finish()
  }
}

///|
async test "a fully read mismatching upload closes its source but preserves exact matching and recovery" {
  let session = upload_cassette("ab").session()
  let transport = @transport.ReplayTransport::new(session)
    .with_request_streams()
    .with_response_chunks(1)
  let source = upload_source([b"private-value"])
  try
    transport.send(
      @http.Request::post("https://example.invalid/a").body_stream(source),
    )
  catch {
    @http.HttpError::Protocol(message) => {
      assert_true(message.contains("request_mismatch"))
      assert_false(message.contains("private-value"))
    }
    _ => fail("expected exact body mismatch")
  } noraise {
    _ => fail("wrong upload body accepted")
  }
  assert_eq(source.closes, 1)
  assert_eq(session.remaining(), 1)
  ignore(
    transport.send(
      @http.Request::post("https://example.invalid/a").body_stream(
        upload_source([b"ab"]),
      ),
    ),
  )
  session.finish()
}

///|
priv struct BlockingUpload {
  ready : @async.Queue[Unit]
  blocked : @async.Queue[Unit]
  mut reads : Int32
  mut closes : Int32
}

///|
impl @http.BodyStream for BlockingUpload with fn read_some(self) {
  self.reads += 1
  if self.reads == 1 {
    return Some(b"a")
  }
  self.ready.put(()) catch {
    _ => raise @http.HttpError::Protocol("test signal closed")
  }
  self.blocked.get() catch {
    _ => raise @http.HttpError::Protocol("test blocker closed")
  }
  None
}

///|
impl @http.BodyStream for BlockingUpload with fn close(self) {
  self.closes += 1
}

///|
async test "cancelled partial upload closes during structured cleanup before HAR consumption" {
  let session = upload_cassette("ab").session()
  let source = BlockingUpload::{
    ready: @async.Queue(kind=Unbounded),
    blocked: @async.Queue(kind=Unbounded),
    reads: 0,
    closes: 0,
  }
  let request = @http.Request::post("https://example.invalid/a").body_stream(
    source,
  )
  let transport = @transport.ReplayTransport::new(session).with_request_streams()
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { ignore(transport.send(request)) })
    source.ready.get()
    assert_eq(source.closes, 0)
    assert_eq(session.remaining(), 1)
    group.return_immediately(())
  })
  assert_eq(source.closes, 1)
  assert_false(request.body.is_replayable())
  assert_eq(session.remaining(), 1)
  source.ready.close()
  source.blocked.close()
  ignore(
    transport.send(
      @http.Request::post("https://example.invalid/a").body_bytes(b"ab"),
    ),
  )
  session.finish()
}
