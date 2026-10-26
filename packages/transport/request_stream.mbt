///|
/// Enable bounded request-stream materialization before exact HAR matching.
/// Returns a new configuration sharing this session; the original keeps its existing policy.
pub fn ReplayTransport::with_request_streams(
  self : ReplayTransport,
  max_bytes~ : Int32 = 4194304,
  max_chunks~ : Int32 = 65536,
) -> ReplayTransport raise @replay.ReplayError {
  if max_bytes < 0 || max_chunks < 1 {
    raise @replay.ReplayError({
      code: "invalid_transport_option",
      path: "$transport.request_stream_limits",
      message: "max_bytes must be nonnegative and max_chunks must be positive",
    })
  }
  { ..self, request_stream_limits: Some((max_bytes, max_chunks)), }
}

///|
async fn ReplayTransport::buffer_request(
  self : ReplayTransport,
  request : @http.Request,
) -> @http.Request raise @http.HttpError {
  guard self.request_stream_limits is Some((max_bytes, max_chunks)) &&
    request.body is @http.Body::Stream(body) else {
    return request
  }
  if body.length() is Some(length) && length > max_bytes.to_int64() {
    raise @http.HttpError::Protocol(
      "request_stream_limit: declared body exceeds max_bytes; stream not taken; no exchange consumed",
    )
  }
  let reader = body.take()
  defer reader.close()
  let output = Buffer()
  let mut chunks = 0
  while reader.read_some() is Some(chunk) {
    if chunks == max_chunks || chunk.length() > max_bytes - output.length() {
      raise @http.HttpError::Protocol(
        "request_stream_limit: body exceeds max_bytes or max_chunks; no exchange consumed",
      )
    }
    chunks += 1
    output.write_bytes(chunk)
  }
  request.body_bytes(output.to_bytes())
}
