# Recorded SDK transport

Configure response chunk boundaries without changing the recorded HTTP body or
the buffered `send` result. The returned adapter shares the same consumption
session. Chunk sizes are bytes: a UTF-8 character may span multiple reads.

```mbt check
///|
test {
  let source = "{\"log\":{\"version\":\"1.2\",\"creator\":{\"name\":\"example\",\"version\":\"1\"},\"entries\":[]}}"
  let session = @replay.compile_har(source).session()
  let original = @transport.ReplayTransport::new(session)
  ignore(original.with_response_chunks(7))
  session.finish()
}
```

Run `moon run packages/stream_demo -- examples/repository.har` from the repository
root for a complete example using the real capture. Close each returned stream.
Finite body chunks model client reads; they do not model wire framing, timing,
backpressure, SSE, or WebSockets.
