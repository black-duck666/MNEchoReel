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
      message: "usage: moon run packages/prepare -- <recording.har> <NEW_PLAN.json> [--decoded] [--assert-bodies]",
    })
  }
  let mut decoded = false
  let mut assert_bodies = false
  for flag in args.iter().drop(ARG_START + 2) {
    match flag {
      "--decoded" if !decoded => decoded = true
      "--assert-bodies" if !assert_bodies => assert_bodies = true
      _ =>
        raise PrepareError({
          code: "usage_error",
          path: "$args",
          message: "unknown or repeated option; expected --decoded and/or --assert-bodies",
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
  let plan = cassette.request_plan(assert_bodies~)
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
