///|
/// Inject into SDKs that accept gaato/http's Transport. No network is accessed.
pub struct ReplayTransport {
  priv session : @replay.Session
}

///|
pub fn ReplayTransport::new(session : @replay.Session) -> ReplayTransport {
  { session, }
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
    remaining: Some(response.body),
  }
  ({ status: response.status, headers: response.headers, }, stream)
}

///|
priv struct MemoryBody {
  mut remaining : Bytes?
}

///|
impl @http.BodyStream for MemoryBody with fn read_some(self) {
  let bytes = self.remaining
  self.remaining = None
  match bytes {
    Some(value) => if value.is_empty() { None } else { Some(value) }
    None => None
  }
}

///|
impl @http.BodyStream for MemoryBody with fn close(self) {
  self.remaining = None
}

///|
pub extend ReplayTransport with @http.Transport::{send, send_stream}
