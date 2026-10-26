///|
#cfg(target="js")
const ARG_START : Int32 = 2

///|
#cfg(not(target="js"))
const ARG_START : Int32 = 1

///|
async fn main {
  let args = @env.args()
  guard args.length() == ARG_START + 1 else {
    abort("usage: moon run packages/stream_demo -- examples/repository.har")
  }
  let cassette = @replay.compile_har(@fs.read_file_to_string(args[ARG_START]))
  let session = cassette.session()
  let transport = @transport.ReplayTransport::new(session).with_response_chunks(
    7,
  )
  let (head, stream) = transport.send_stream(
    @http.Request::get("https://api.github.com/repos/moonbitlang/core"),
  )
  defer stream.close()
  assert_eq(head.status, 200)
  let body = Buffer()
  let mut chunks = 0
  while stream.read_some() is Some(chunk) {
    assert_true(chunk.length() > 0 && chunk.length() <= 7)
    body.write_bytes(chunk)
    chunks += 1
  }
  let text = @utf8.decode(body.to_bytes())
  guard @json.parse(text) is { "full_name": String(name), .. } else {
    abort("missing repository full_name")
  }
  assert_eq(name, "moonbitlang/core")
  assert_true(chunks > 1)
  session.finish()
  println(
    "streamed SDK result: \{name}; \{chunks} chunks; all interactions verified",
  )
}
