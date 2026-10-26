///|
#cfg(target="js")
const ARG_START : Int32 = 2

///|
#cfg(not(target="js"))
const ARG_START : Int32 = 1

///|
suberror PrepareError {
  PrepareError(@replay.Diagnostic)
}

///|
fn run(args : Array[String]) -> Unit raise {
  guard args.length() >= ARG_START + 2 else {
    raise PrepareError({
      code: "usage_error",
      path: "$args",
      message: "usage: moon run packages/prepare -- <recording.har> <NEW_PLAN.json> [--decoded] [--assert-bodies] [--assert-header NAME]",
    })
  }
  let mut decoded = false
  let mut assert_bodies = false
  let assert_headers : Array[String] = []
  let flags = args.iter().drop(ARG_START + 2)
  for flag in flags {
    match flag {
      "--decoded" if !decoded => decoded = true
      "--assert-bodies" if !assert_bodies => assert_bodies = true
      "--assert-header" => {
        guard flags.next() is Some(name) && !name.is_empty() else {
          raise PrepareError({
            code: "usage_error",
            path: "$args",
            message: "--assert-header requires a header name",
          })
        }
        assert_headers.push(name)
      }
      _ =>
        raise PrepareError({
          code: "usage_error",
          path: "$args",
          message: "unknown or repeated option; expected --decoded, --assert-bodies or --assert-header NAME",
        })
    }
  }
  let output = args[ARG_START + 1]
  if @fs.path_exists(output) {
    raise PrepareError({
      code: "output_exists",
      path: "$output",
      message: "plan output already exists; choose a new path",
    })
  }
  let cassette = @replay.compile_har(
    @fs.read_file_to_string(args[ARG_START]),
    body_profile=if decoded { DecodedContent } else { Identity },
  )
  let plan = cassette.request_plan(assert_bodies~, assert_headers~)
  @fs.write_string_to_file(output, plan) catch {
    _ =>
      raise PrepareError({
        code: "output_error",
        path: "$output",
        message: "cannot write plan; check the parent directory and write permissions",
      })
  }
  let summary : Json = {
    "schema": 1,
    "steps": cassette.length(),
    "assert_bodies": assert_bodies,
    "adaptations": @json.parse(cassette.adaptation_report_json()),
  }
  if !assert_headers.is_empty() {
    guard summary is Object(fields) else { abort("summary invariant") }
    fields.set("assert_headers", Json(assert_headers))
  }
  println(summary.stringify())
}

///|
fn main {
  run(@env.args()) catch {
    @replay.ReplayError(d) | PrepareError(d) => {
      println(d.format())
      @sys.exit(2)
    }
    _ => {
      println(
        "input_error at $input: cannot read complete UTF-8 input; check path and permissions",
      )
      @sys.exit(2)
    }
  }
}
