///|
#cfg(target="js")
const ARG_START : Int32 = 2

///|
#cfg(not(target="js"))
const ARG_START : Int32 = 1

///|
priv struct Upload {
  bytes : Bytes
  mut offset : Int32
  mut closes : Int32
}

///|
impl @http.BodyStream for Upload with fn read_some(self) {
  if self.offset == self.bytes.length() {
    return None
  }
  let end = self.offset + (self.bytes.length() - self.offset).min(5)
  let chunk = self.bytes[self.offset:end].to_owned()
  self.offset = end
  Some(chunk)
}

///|
impl @http.BodyStream for Upload with fn close(self) {
  self.closes += 1
}

///|
async fn main {
  let args = @env.args()
  guard args.length() == ARG_START + 1 else {
    abort("usage: moon run packages/upload_demo -- <one-exchange.har>")
  }
  let cassette = @replay.compile_har(@fs.read_file_to_string(args[ARG_START]))
  guard cassette.length() == 1 else {
    abort("upload_demo requires exactly one complete exchange")
  }
  guard @json.parse(cassette.request_plan(assert_bodies=true)) is Array(steps) else {
    abort("plan invariant")
  }
  guard steps[0]
    is {
      "method": String(http_method),
      "url": String(url),
      "headers": Array(headers),
      "body": String(text),
      "expect_status": Number(status, ..),
      "expect_body_base64": String(expected),
      ..
    } else {
    abort("generated step invariant")
  }
  let pairs = headers.map(header => {
    guard header is { "name": String(name), "value": String(value), .. } else {
      abort("generated header invariant")
    }
    (name, value)
  })
  let bytes = @utf8.encode(text)
  let source = Upload::{ bytes, offset: 0, closes: 0, }
  let request = @http.Request::new(http_method, url).body_stream(
    source,
    length=bytes.length().to_int64(),
  )
  let request = { ..request, headers: @http.Headers::from_array(pairs), }
  let session = cassette.session()
  let transport = @transport.ReplayTransport::new(session).with_request_streams(
    max_bytes=bytes.length(),
    max_chunks=1 + bytes.length() / 5,
  )
  let response = transport.send(request)
  assert_eq(response.status.to_double(), status)
  assert_eq(@base64.encode(response.body), expected)
  assert_eq(source.closes, 1)
  assert_eq(source.offset, bytes.length())
  assert_false(request.body.is_replayable())
  session.finish()
  println(
    "streamed recorded request: \{bytes.length()} request bytes; \{response.body.length()} response bytes; all interactions verified",
  )
}
