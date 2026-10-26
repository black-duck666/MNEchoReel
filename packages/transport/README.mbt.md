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
  ignore(original.with_request_streams(max_bytes=0, max_chunks=1))
  session.finish()
}
```

Run `moon run packages/stream_demo -- examples/repository.har` from the repository
root for a complete example using the real capture. Close each returned stream.
Finite body chunks model client reads; they do not model wire framing, timing,
backpressure, SSE, or WebSockets.

`with_request_streams(max_bytes=4194304, max_chunks=65536)` explicitly enables
finite request bodies. It reads and closes a taken source before exact matching;
failed reads, budget errors and cancellation leave the HAR session unconsumed.
Empty chunks count, and the exact chunk boundary permits one further EOF probe.
Known oversized lengths are refused before taking ownership. A taken source
stays single-use even on failure; create a fresh source for a retry.

Run `moon run packages/upload_demo -- examples/repository.har` to stream the
recorded request without network access. This real GET has an empty request body;
the same demo accepts a one-exchange POST HAR with UTF-8 text. CI also derives an
explicitly synthetic POST with the real API JSON as its body. Budgets bound bytes
and read calls, not the duration of an individual asynchronous read.
