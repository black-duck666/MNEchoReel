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
suberror CliInputError {
  CliInputError(@replay.Diagnostic)
}

///|
fn run(args : Array[String]) -> Unit raise {
  guard args.length() >= ARG_START + 2 else {
    raise CliError(
      "usage: moon run packages/check -- <recording.har> <requests.json> [--decoded] [--report]",
    )
  }
  let mut decoded = false
  let mut report_mode = false
  for flag in args.iter().drop(ARG_START + 2) {
    match flag {
      "--decoded" if !decoded => decoded = true
      "--report" if !report_mode => report_mode = true
      _ =>
        raise CliError(
          "unknown or repeated option; expected --decoded and/or --report",
        )
    }
  }
  let profile : @replay.BodyProfile = if decoded {
    DecodedContent
  } else {
    Identity
  }
  let cassette = @replay.compile_har(
    @fs.read_file_to_string(args[ARG_START]),
    body_profile=profile,
  ) catch {
    @replay.ReplayError(d) => raise CliInputError(d)
    e => raise e
  }
  if !report_mode && !cassette.adaptations().is_empty() {
    println(cassette.adaptation_report_json())
  }
  let plan = @plan.parse_plan(@fs.read_file_to_string(args[ARG_START + 1])) catch {
    @replay.ReplayError(d) => raise CliInputError(d)
    e => raise e
  }
  let session = cassette.session()
  if report_mode {
    try plan.run(session) catch {
      @replay.ReplayError(d) => {
        print_report(
          Some(d),
          Some(@json.parse(session.report().render_json())),
          Some(@json.parse(cassette.adaptation_report_json())),
        )
        @sys.exit(1)
      }
      e => raise e
    } noraise {
      _ =>
        print_report(
          None,
          Some(@json.parse(session.report().render_json())),
          Some(@json.parse(cassette.adaptation_report_json())),
        )
    }
    return
  }
  // Print successes only after every step and completion check have committed.
  for i, response in plan.run(session) {
    println(
      "\{i}: status=\{response.status()} bytes=\{response.body().length()}",
    )
  }
  println("all \{cassette.length()} recorded exchanges consumed")
}

///|
fn print_report(
  diagnostic : @replay.Diagnostic?,
  consumption : Json?,
  adaptations : Json?,
) -> Unit {
  let d : Json = match diagnostic {
    None => Json::null()
    Some(d) => { "code": d.code, "path": d.path, "message": d.message }
  }
  let value : Json = {
    "schema": 1,
    "passed": diagnostic == None,
    "diagnostic": d,
    "consumption": consumption.unwrap_or(Json::null()),
    "adaptations": adaptations.unwrap_or(Json::null()),
  }
  println(value.stringify())
}

///|
fn main {
  let args = @env.args()
  let report_mode = args
    .iter()
    .drop(ARG_START + 2)
    .any(arg => arg == "--report")
  run(args) catch {
    @replay.ReplayError(d) => {
      if report_mode {
        print_report(Some(d), None, None)
      } else {
        println(d.format())
      }
      @sys.exit(1)
    }
    CliInputError(d) => {
      if report_mode {
        print_report(Some(d), None, None)
      } else {
        println(d.format())
      }
      @sys.exit(2)
    }
    CliError(message) => {
      if report_mode {
        print_report(
          Some({ code: "usage_error", path: "$args", message, }),
          None,
          None,
        )
      } else {
        println(message)
      }
      @sys.exit(2)
    }
    _ => {
      let d : @replay.Diagnostic = {
        code: "input_error",
        path: "$input",
        message: "cannot read the input file; check its path, permissions and UTF-8 encoding",
      }
      if report_mode {
        print_report(Some(d), None, None)
      } else {
        println(d.format())
      }
      @sys.exit(2)
    }
  }
}
