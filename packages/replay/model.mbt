///|
/// A stable diagnostic. Messages never include request or response values.
pub(all) struct Diagnostic {
  code : String
  path : String
  message : String
} derive(Eq, Debug)

///|
pub fn Diagnostic::format(self : Diagnostic) -> String {
  "\{self.code} at \{self.path}: \{self.message}"
}

///|
pub(all) suberror ReplayError {
  ReplayError(Diagnostic)
} derive(Debug)

///|
fn[T] fail(
  code : String,
  path : String,
  message : String,
) -> T raise ReplayError {
  raise ReplayError({ code, path, message, })
}

///|
/// Ordered preserves all ordering; PerRequest preserves each exact identity's sequence.
pub(all) enum MatchMode {
  Ordered
  ByRequest
  PerRequest
} derive(Eq, Debug)

///|
/// Construct a request without exposing the session's internal mutable arrays.
pub struct Request {
  priv http_method : String
  priv url : String
  priv headers : Array[(String, String)]
  priv body : Bytes
} derive(Eq, Debug)

///|
pub fn Request::new(
  http_method : String,
  url : String,
  headers~ : Array[(String, String)] = [],
  body~ : Bytes = b"",
) -> Request {
  { http_method, url, headers: headers.copy(), body, }
}

///|
/// A finite, buffered application response. Duplicate headers retain their order.
pub struct Response {
  priv status : Int32
  priv headers : Array[(String, String)]
  priv body : Bytes
} derive(Eq, Debug)

///|
pub fn Response::status(self : Response) -> Int32 {
  self.status
}

///|
pub fn Response::headers(self : Response) -> Array[(String, String)] {
  self.headers.copy()
}

///|
pub fn Response::body(self : Response) -> Bytes {
  self.body
}

///|
priv struct Exchange {
  request : Request
  response : Response
}

///|
/// Compiled exchanges plus the exact original input; this type has no mutable API.
pub struct Cassette {
  priv source : String
  priv exchanges : Array[Exchange]
  priv header_names : Array[String]
  priv adaptations : Array[HeaderChange]
}

///|
pub fn Cassette::source(self : Cassette) -> String {
  self.source
}

///|
pub fn Cassette::length(self : Cassette) -> Int32 {
  self.exchanges.length()
}

///|
/// An independent consumption cursor. Do not share one session between tests.
pub struct Session {
  priv cassette : Cassette
  priv used : Array[Bool]
  priv mode : MatchMode
}

///|
pub fn Cassette::session(
  self : Cassette,
  mode~ : MatchMode = Ordered,
) -> Session {
  { cassette: self, used: Array::make(self.length(), false), mode, }
}

///|
pub extend Diagnostic with Eq::{equal, not_equal}

///|
pub extend Diagnostic with @debug.Debug::{to_repr}

///|
pub extend ReplayError with @debug.Debug::{to_repr}

///|
pub extend MatchMode with Eq::{equal, not_equal}

///|
pub extend MatchMode with @debug.Debug::{to_repr}

///|
pub extend Request with Eq::{equal, not_equal}

///|
pub extend Request with @debug.Debug::{to_repr}

///|
pub extend Response with Eq::{equal, not_equal}

///|
pub extend Response with @debug.Debug::{to_repr}
