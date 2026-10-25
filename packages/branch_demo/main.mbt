///|
#cfg(target="js")
const ARG_START : Int32 = 2

///|
#cfg(not(target="js"))
const ARG_START : Int32 = 1

///|
fn main raise {
  let args = @env.args()
  guard args.length() == ARG_START + 1 else {
    abort("usage: moon run packages/branch_demo -- examples/repository.har")
  }
  let cassette = @replay.compile_har(@fs.read_file_to_string(args[ARG_START]))
  let parent = cassette.session()
  let request = @replay.Request::new(
    "GET", "https://api.github.com/repos/moonbitlang/core",
  )
  let alternative = parent.fork()
  ignore(alternative.take(request))
  alternative.finish()
  assert_eq(parent.remaining(), 1)
  try
    parent.transaction(s => {
      ignore(s.take(request))
      ignore(s.take(request))
    })
  catch {
    @replay.ReplayError(d) => assert_eq(d.code, "no_match")
    error => raise error
  } noraise {
    _ => abort("expected failed trial")
  }
  assert_eq(parent.remaining(), 1)
  let name = parent.transaction(s => {
    let response = s.take_checked(request, @replay.Expectation::new(status=200))
    let payload = @json.parse(@utf8.decode(response.body()))
    guard payload is { "full_name": String(name), .. } else {
      abort("repository field missing")
    }
    assert_eq(name, "moonbitlang/core")
    s.finish()
    name
  })
  println(
    "isolated branch and failed trial preserved parent; committed result: \{name}",
  )
}
