///|
/// A small SDK function with an injectable transport; usable against any transport.
async fn repository_name(transport : &@http.Transport) -> String {
  let response = transport.send(
    @http.Request::get("https://api.github.com/repos/moonbitlang/core"),
  )
  guard response.status == 200 else { abort("unexpected API status") }
  let payload = response.json()
  guard payload is { "full_name": String(name), .. } else {
    abort("missing repository full_name")
  }
  name
}

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
    abort("usage: moon run demo -- examples/repository.har")
  }
  let cassette = @replay.compile_har(@fs.read_file_to_string(args[ARG_START]))
  let session = cassette.session()
  let name = repository_name(@transport.ReplayTransport::new(session))
  guard name == "moonbitlang/core" else { abort("unexpected repository") }
  session.finish()
  println("offline SDK result: \{name}; all interactions verified")
}
