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
      "usage: moon run packages/check -- <recording.har> <requests.json> [--decoded] [--report] [--explain] [--mode ordered|by-request|per-request] [--match-header NAME] [--junit NEW_FILE.xml]",
    )
  }
  let mut decoded = false
  let mut report_mode = false
  let mut explain_mode = false
  let mut chosen_mode : @replay.MatchMode? = None
  let mut junit_path : String? = None
  let match_headers : Array[String] = []
  let options = args.iter().drop(ARG_START + 2)
  for flag in options {
    match flag {
      "--decoded" if !decoded => decoded = true
      "--report" if !report_mode => report_mode = true
      "--explain" if !explain_mode => explain_mode = true
      "--junit" if junit_path == None => {
        guard options.next() is Some(path) &&
          !path.is_empty() &&
          !path.has_prefix("--") else {
          raise CliError("--junit requires a new output file path")
        }
        if @fs.path_exists(path) {
          raise CliInputError({
            code: "output_exists",
            path: "$output",
            message: "JUnit output already exists; choose a new path or deliberately remove the old artifact",
          })
        }
        junit_path = Some(path)
      }
      "--mode" if chosen_mode == None =>
        chosen_mode = Some(
          match options.next() {
            Some("ordered") => @replay.Ordered
            Some("by-request") => @replay.ByRequest
            Some("per-request") => @replay.PerRequest
            _ =>
              raise CliError(
                "--mode requires ordered, by-request or per-request",
              )
          },
        )
      "--match-header" => {
        guard options.next() is Some(name) && !name.has_prefix("--") else {
          raise CliError("--match-header requires a header name")
        }
        if match_headers.iter().any(n => n.equal_ignore_ascii_case(name)) {
          raise CliError("repeated match-header name; names ignore ASCII case")
        }
        match_headers.push(name)
      }
      _ =>
        raise CliError(
          "unknown or repeated option; consult --mode, --match-header, --decoded, --report, --explain and --junit usage",
        )
    }
  }
  let report_mode = report_mode || explain_mode
  let profile : @replay.BodyProfile = if decoded {
    DecodedContent
  } else {
    Identity
  }
  let cassette = @replay.compile_har(
    @fs.read_file_to_string(args[ARG_START]),
    body_profile=profile,
    match_headers~,
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
  let session = cassette.session(mode=chosen_mode.unwrap_or(Ordered))
  if report_mode || junit_path != None {
    let verification = plan.verify(session, explain_mismatches=explain_mode)
    if junit_path is Some(path) {
      @fs.write_string_to_file(path, verification.render_junit()) catch {
        _ =>
          raise CliInputError({
            code: "output_error",
            path: "$output",
            message: "cannot write JUnit artifact; check the parent directory and write permissions",
          })
      }
    }
    if report_mode {
      print_report(
        verification.diagnostic(),
        Some(@json.parse(session.report().render_json())),
        Some(@json.parse(cassette.adaptation_report_json())),
        explanation?=if explain_mode {
          Some(
            verification
            .explanation()
            .map(r => r.to_json())
            .unwrap_or(Json::null()),
          )
        } else {
          None
        },
      )
    } else if verification.diagnostic() is Some(d) {
      println(d.format())
    } else {
      println(
        "all \{cassette.length()} recorded exchanges consumed; JUnit artifact written",
      )
    }
    if !verification.passed() {
      @sys.exit(1)
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
  explanation? : Json,
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
  if explanation is Some(report) && value is Object(fields) {
    fields.set("explanation", report)
  }
  println(value.stringify())
}

///|
fn main {
  let args = @env.args()
  let report_mode = args
    .iter()
    .drop(ARG_START + 2)
    .any(arg => arg == "--report" || arg == "--explain")
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
