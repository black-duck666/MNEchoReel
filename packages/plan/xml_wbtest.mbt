///|
test "JUnit diagnostic text escapes all XML markup without losing Unicode" {
  assert_eq(
    xml_escape("<&>'\"拾响 &amp;"),
    "&lt;&amp;&gt;&apos;&quot;拾响 &amp;amp;",
  )
  let report : RunReport = {
    outcomes: [Failed],
    completion: None,
    diagnostic: Some({ code: "test", path: "$", message: "<&>'\"拾响", }),
    explanation: None,
  }
  assert_true(report.render_junit().contains("&lt;&amp;&gt;&apos;&quot;拾响"))
}

///|
test "JUnit output has stable exact bytes and unique case names" {
  let report : RunReport = {
    outcomes: [Passed],
    completion: Some(Passed),
    diagnostic: None,
    explanation: None,
  }
  let expected : String =
    #|<?xml version="1.0" encoding="UTF-8"?>
    #|<testsuite name="EchoReel" tests="2" failures="0" errors="0" skipped="0">
    #|  <properties><property name="committed" value="true"/></properties>
    #|  <testcase classname="echoreel.plan" name="step.0"></testcase>
    #|  <testcase classname="echoreel.plan" name="completion"></testcase>
    #|</testsuite>
  assert_eq(report.render_junit(), expected + "\n")
}
