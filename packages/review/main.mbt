///|
#cfg(target="js")
const ARG_START : Int32 = 2

///|
#cfg(not(target="js"))
const ARG_START : Int32 = 1

///|
suberror ReviewOption {
  ReviewOption(String)
}

///|
fn run(args : Array[String]) -> Unit raise {
  guard args.length() >= ARG_START + 2 else {
    raise ReviewOption(
      "usage: moon run packages/review -- <before.har> <after.har> [--json-pointer POINTER] [--ignore-header NAME] [--decoded]",
    )
  }
  let pointers = []
  let ignored = []
  let mut decoded = false
  let options = args.iter().drop(ARG_START + 2)
  for option in options {
    match option {
      "--json-pointer" => {
        guard options.next() is Some(pointer) else {
          raise ReviewOption("--json-pointer requires a string pointer")
        }
        pointers.push(pointer)
      }
      "--ignore-header" => {
        guard options.next() is Some(name) else {
          raise ReviewOption("--ignore-header requires a header name")
        }
        ignored.push(name)
      }
      "--decoded" if !decoded => decoded = true
      _ =>
        raise ReviewOption(
          "unknown or repeated option; consult --json-pointer, --ignore-header and --decoded usage",
        )
    }
  }
  let profile : @replay.BodyProfile = if decoded {
    DecodedContent
  } else {
    Identity
  }
  let before = @replay.compile_har(
    @fs.read_file_to_string(args[ARG_START]),
    body_profile=profile,
  )
  let after = @replay.compile_har(
    @fs.read_file_to_string(args[ARG_START + 1]),
    body_profile=profile,
  )
  let report = before.compare(
    after,
    ignore_response_headers=ignored,
    json_pointers?=if pointers.is_empty() { None } else { Some(pointers) },
  )
  if decoded {
    let output = @json.parse(report.render_json())
    guard output is Object(fields) else { abort("review report invariant") }
    fields.set(
      "before_adaptations",
      @json.parse(before.adaptation_report_json()),
    )
    fields.set("after_adaptations", @json.parse(after.adaptation_report_json()))
    println(output.stringify())
  } else {
    println(report.render_json())
  }
  if !report.is_empty() {
    @sys.exit(1)
  }
}

///|
fn main {
  run(@env.args()) catch {
    @replay.ReplayError(d) => {
      println(d.format())
      @sys.exit(2)
    }
    ReviewOption(message) => {
      println("usage_error at $args: " + message)
      @sys.exit(2)
    }
    _ => {
      println("input_error: check both HAR file paths and UTF-8 encoding")
      @sys.exit(2)
    }
  }
}
