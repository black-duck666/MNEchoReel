///|
#cfg(target="js")
const ARG_START : Int32 = 2

///|
#cfg(not(target="js"))
const ARG_START : Int32 = 1

///|
fn main raise {
  let args = @env.args()
  guard args.length() == ARG_START + 2 else {
    abort("usage: consumer <recording.har> <requests.json>")
  }
  let cassette = @replay.compile_har(@fs.read_file_to_string(args[ARG_START]))
  let plan = @plan.parse_plan(@fs.read_file_to_string(args[ARG_START + 1]))
  let session = cassette.session()
  let result = plan.verify(session)
  assert_true(result.passed())
  session.finish()
  let derived = @plan.parse_plan(
    cassette.request_plan(assert_headers=["Content-Type"], assert_json=[
      "/full_name",
    ]),
  )
  assert_true(derived.verify(cassette.session()).passed())
  let suite = @plan.verify_suite([
    @plan.SuiteCase::new("external-consumer", cassette, plan),
  ])
  assert_true(suite.passed())
  assert_eq(suite.cases().length(), 1)
  assert_true(suite.render_junit().contains("external-consumer.step.0"))
  println("external consumer: replay, generated contracts and suite passed")
}
