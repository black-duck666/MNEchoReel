///|
#cfg(target="js")
const ARG_START : Int32 = 2

///|
#cfg(not(target="js"))
const ARG_START : Int32 = 1

///|
priv struct EmptyRequest {
  mut closed : Bool
}

///|
impl @http.BodyStream for EmptyRequest with fn read_some(_self) {
  None
}

///|
impl @http.BodyStream for EmptyRequest with fn close(self) {
  self.closed = true
}

///|
async fn main {
  let args = @env.args()
  guard args.length() == ARG_START + 1 else {
    abort("usage: sdk <repository.har>")
  }
  let cassette = @replay.compile_har(@fs.read_file_to_string(args[ARG_START]))
  let session = cassette.session()
  let adapter = @transport.ReplayTransport::new(session)
    .with_response_chunks(5)
    .with_request_streams(max_bytes=0, max_chunks=1)
  let input = EmptyRequest::{ closed: false, }
  let client : &@http.Transport = adapter
  let (head, stream) = client.send_stream(
    @http.Request::get("https://api.github.com/repos/moonbitlang/core").body_stream(
      input,
      length=0L,
    ),
  )
  defer stream.close()
  assert_true(input.closed)
  assert_eq(head.status, 200)
  let output = Buffer()
  let mut chunks = 0
  while stream.read_some() is Some(bytes) {
    assert_true(bytes.length() <= 5)
    output.write_bytes(bytes)
    chunks += 1
  }
  assert_true(chunks > 1)
  guard @json.parse(@utf8.decode(output.to_bytes()))
    is { "full_name": String(name), .. } else {
    abort("repository name missing")
  }
  assert_eq(name, "moonbitlang/core")
  session.finish()
  println(
    "external SDK consumer: public Transport, bounded request and response chunks passed",
  )
}
