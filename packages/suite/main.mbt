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
fn field(value : Json, key : String) -> Json? {
  match value {
    Object(fields) => fields.get(key)
    _ => None
  }
}

///|
fn required(
  value : Json,
  key : String,
  path : String,
) -> String raise SuiteError {
  guard field(value, key) is Some(String(text)) && !text.is_empty() else {
    invalid(
      "suite_manifest_error",
      path + "." + key,
      "expected a nonempty string",
    )
  }
  text
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
  let source = @fs.read_file_to_string(args[ARG_START])
  if source.length() > 4194304 {
    invalid(
      "suite_manifest_error", "$suite", "suite manifest exceeds 4194304 UTF-16 units",
    )
  }
  let value = @json.parse(
    source,
    reject_duplicate_keys=true,
    max_nesting_depth=16,
  ) catch {
    _ =>
      invalid(
        "suite_manifest_error", "$suite", "invalid JSON, duplicate key or excessive nesting",
      )
  }
  guard value is Array(items) && items.length() > 0 && items.length() <= 1000 else {
    invalid(
      "suite_manifest_error", "$suite", "expected an array of 1 through 1000 cases",
    )
  }
  // Resolve and compile every input before starting any case.
  let mut total_input = source.length()
  let cases = items.mapi((i, item) => {
    let path = "$suite[\{i}]"
    guard item is Object(fields) else {
      invalid("suite_manifest_error", path, "expected a case object")
    }
    for key, _ in fields {
      if !["name", "har", "requests", "decoded", "mode", "match_headers"].contains(
          key,
        ) {
        invalid("suite_manifest_error", path, "unknown case field")
      }
    }
    let name = required(item, "name", path)
    let har = required(item, "har", path)
    let requests = required(item, "requests", path)
    let decoded = match field(item, "decoded") {
      None | Some(False) => false
      Some(True) => true
      _ =>
        invalid("suite_manifest_error", path + ".decoded", "expected a boolean")
    }
    let mode : @replay.MatchMode = match field(item, "mode") {
      None | Some(String("ordered")) => Ordered
      Some(String("by-request")) => ByRequest
      Some(String("per-request")) => PerRequest
      _ =>
        invalid(
          "suite_manifest_error",
          path + ".mode",
          "expected ordered, by-request or per-request",
        )
    }
    let match_headers : Array[String] = match field(item, "match_headers") {
      None => []
      Some(Array(names)) =>
        names.map(value => {
          match value {
            String(name) => name
            _ =>
              invalid(
                "suite_manifest_error",
                path + ".match_headers",
                "expected header-name strings",
              )
          }
        })
      _ =>
        invalid(
          "suite_manifest_error",
          path + ".match_headers",
          "expected an array",
        )
    }
    let har_source = @fs.read_file_to_string(har)
    let plan_source = @fs.read_file_to_string(requests)
    for text in [har_source, plan_source] {
      if text.length() > 67108864 - total_input {
        invalid(
          "suite_limit", path, "combined input exceeds 67108864 UTF-16 units",
        )
      }
      total_input += text.length()
    }
    let cassette = @replay.compile_har(
      har_source,
      body_profile=if decoded { DecodedContent } else { Identity },
      match_headers~,
    )
    let plan = @plan.parse_plan(plan_source)
    @plan.SuiteCase::new(name, cassette, plan, mode~)
  })
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
