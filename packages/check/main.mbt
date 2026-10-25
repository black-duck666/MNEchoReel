///|
#cfg(target="js")
const ARG_START : Int32 = 2

///|
#cfg(not(target="js"))
const ARG_START : Int32 = 1

///|
suberror CliError {
  CliError(String)
}

///|
fn run(args : Array[String]) -> Unit raise {
  guard args.length() == ARG_START + 2 || args.length() == ARG_START + 3 else {
    raise CliError(
      "usage: moon run packages/check -- <recording.har> <requests.json> [--decoded]",
    )
  }
  let profile : @replay.BodyProfile = if args.length() == ARG_START + 3 {
    if args[ARG_START + 2] != "--decoded" {
      raise CliError("unknown option; expected --decoded")
    }
    DecodedContent
  } else {
    Identity
  }
  let cassette = @replay.compile_har(
    @fs.read_file_to_string(args[ARG_START]),
    body_profile=profile,
  )
  if !cassette.adaptations().is_empty() {
    println(cassette.adaptation_report_json())
  }
  let plan = @plan.parse_plan(@fs.read_file_to_string(args[ARG_START + 1]))
  let session = cassette.session()
  // Print successes only after every step and completion check have committed.
  for i, response in plan.run(session) {
    println(
      "\{i}: status=\{response.status()} bytes=\{response.body().length()}",
    )
  }
  println("all \{cassette.length()} recorded exchanges consumed")
}

///|
fn main {
  run(@env.args()) catch {
    @replay.ReplayError(d) => {
      println(d.format())
      @sys.exit(if d.code == "manifest_error" { 2 } else { 1 })
    }
    CliError(message) => {
      println(message)
      @sys.exit(2)
    }
    _ => {
      println(
        "input_error: cannot read the input file; check its path, permissions and UTF-8 encoding",
      )
      @sys.exit(2)
    }
  }
}
