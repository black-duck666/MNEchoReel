///|
#cfg(target="js")
const ARG_START : Int32 = 2

///|
#cfg(not(target="js"))
const ARG_START : Int32 = 1

///|
suberror SuiteError {
  SuiteError(@replay.Diagnostic)
}

///|
fn[T] invalid(
  code : String,
  path : String,
  message : String,
) -> T raise SuiteError {
  raise SuiteError({ code, path, message, })
}

///|
fn run(args : Array[String]) -> Unit raise {
  guard args.length() >= ARG_START + 1 else {
    invalid(
      "usage_error", "$args", "usage: moon run packages/suite -- <suite.json> [--explain] [--junit NEW_FILE.xml]",
    )
  }
  let mut explain = false
  let mut junit_path = None
  let flags = args.iter().drop(ARG_START + 1)
  for flag in flags {
    match flag {
      "--explain" if !explain => explain = true
      "--junit" if junit_path == None => {
        guard flags.next() is Some(path) &&
          !path.is_empty() &&
          !path.has_prefix("--") else {
          invalid(
            "usage_error", "$args", "--junit requires a new output file path",
          )
        }
        if @fs.path_exists(path) {
          invalid(
            "output_exists", "$output", "JUnit output already exists; choose a new path",
          )
        }
        junit_path = Some(path)
      }
      _ =>
        invalid(
          "usage_error", "$args", "unknown or repeated option; expected --explain and/or --junit",
        )
    }
  }
  let manifest = @plan.parse_suite_manifest(
    @fs.read_file_to_string(args[ARG_START]),
  )
  let cases = manifest.load(path => @fs.read_file_to_string(path))
  let report = @plan.verify_suite(cases, explain_mismatches=explain)
  if junit_path is Some(path) {
    @fs.write_string_to_file(path, report.render_junit()) catch {
      _ =>
        invalid(
          "output_error", "$output", "cannot write JUnit artifact; check parent directory and permissions",
        )
    }
  }
  println(report.render_json())
  if !report.passed() {
    @sys.exit(1)
  }
}

///|
fn main {
  run(@env.args()) catch {
    @replay.ReplayError(d) | SuiteError(d) => {
      let error : Json = {
        "schema": 1,
        "passed": false,
        "diagnostic": { "code": d.code, "path": d.path, "message": d.message },
        "cases": [],
      }
      println(error.stringify())
      @sys.exit(2)
    }
    _ => {
      let error : Json = {
        "schema": 1,
        "passed": false,
        "diagnostic": {
          "code": "input_error",
          "path": "$input",
          "message": "cannot read complete UTF-8 inputs; check paths and permissions",
        },
        "cases": [],
      }
      println(error.stringify())
      @sys.exit(2)
    }
  }
}
