///|
/// Inject into SDKs that accept gaato/http's Transport. No network is accessed.
pub struct ReplayTransport {
  priv session : @replay.Session
  priv response_chunk_bytes : Int32?
}

///|
pub fn ReplayTransport::new(session : @replay.Session) -> ReplayTransport {
  { session, response_chunk_bytes: None, }
}

///|
/// Return a configured adapter sharing this session. Only send_stream chunk boundaries change.
/// No HTTP transfer coding or timing is simulated; send still returns all recorded bytes.
pub fn ReplayTransport::with_response_chunks(
  self : ReplayTransport,
  chunk_bytes : Int32,
) -> ReplayTransport raise @replay.ReplayError {
  if chunk_bytes < 1 {
    raise @replay.ReplayError({
      code: "invalid_transport_option",
      path: "$transport.response_chunk_bytes",
      message: "response chunk size must be positive",
    })
  }
  { ..self, response_chunk_bytes: Some(chunk_bytes), }
}

///|
fn ReplayTransport::respond(
  self : ReplayTransport,
  request : @http.Request,
) -> @http.Response raise @http.HttpError {
  guard request.body.as_bytes() is Some(body) else {
    raise @http.HttpError::Protocol(
      "unsupported_request_stream: supply a buffered request; no exchange consumed",
    )
  }
  let response = self.session.take(
    @replay.Request::new(
      request.http_method,
      request.url,
      headers=request.headers.iter().collect(),
      body~,
    ),
  ) catch {
    @replay.ReplayError(diagnostic) =>
      raise @http.HttpError::Protocol(diagnostic.format())
  }
  {
    status: response.status(),
    headers: @http.Headers::from_array(response.headers()),
    body: response.body(),
  }
}

///|
pub impl @http.Transport for ReplayTransport with fn send(self, request) {
  self.respond(request)
}

///|
pub impl @http.Transport for ReplayTransport with fn send_stream(self, request) {
  let response = self.respond(request)
  let stream : &@http.BodyStream = MemoryBody::{
    body: response.body,
    offset: 0,
    chunk_bytes: self.response_chunk_bytes.unwrap_or(
      response.body.length().max(1),
    ),
  }
  ({ status: response.status, headers: response.headers, }, stream)
}

///|
priv struct MemoryBody {
  mut body : Bytes
  mut offset : Int32
  chunk_bytes : Int32
}

///|
fn MemoryBody::next_chunk(self : MemoryBody) -> Bytes? {
  if self.body.is_empty() {
    return None
  }
  let end = self.offset + self.chunk_bytes.min(self.body.length() - self.offset)
  let chunk = self.body[self.offset:end].to_owned()
  if end == self.body.length() {
    self.body = b""
    self.offset = 0
  } else {
    self.offset = end
  }
  Some(chunk)
}

///|
impl @http.BodyStream for MemoryBody with fn read_some(self) {
  self.next_chunk()
}

///|
impl @http.BodyStream for MemoryBody with fn close(self) {
  self.body = b""
  self.offset = 0
}

///|
pub extend ReplayTransport with @http.Transport::{send, send_stream}
