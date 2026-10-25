///|
/// One independent complete regression workflow. Names are stable non-secret CI identifiers.
pub struct SuiteCase {
  priv name : String
  priv cassette : @replay.Cassette
  priv plan : Plan
  priv mode : @replay.MatchMode
}

///|
pub fn SuiteCase::new(
  name : String,
  cassette : @replay.Cassette,
  plan : Plan,
  mode~ : @replay.MatchMode = Ordered,
) -> SuiteCase raise @replay.ReplayError {
  validate_case_name(name, "$suite")
  { name, cassette, plan, mode, }
}

///|
fn validate_case_name(
  name : String,
  path : String,
) -> Unit raise @replay.ReplayError {
  if name.is_empty() ||
    name.length() > 128 ||
    !name
    .iter()
    .all(c => {
      c.is_ascii_alphabetic() ||
      c.is_ascii_digit() ||
      c == '_' ||
      c == '-' ||
      c == '.'
    }) {
    raise @replay.ReplayError({
      code: "invalid_case_name",
      path,
      message: "case names require 1-128 ASCII letters, digits, dots, underscores or hyphens",
    })
  }
}

///|
priv struct CaseExecution {
  name : String
  report : RunReport
  adaptations : Array[@replay.HeaderChange]
}

///|
pub struct SuiteReport {
  priv cases : Array[CaseExecution]
}

///|
/// Validate every case identity before executing. Failed cases do not stop later cases.
/// Each case uses its own fresh session; no caller session or cassette is consumed.
pub fn verify_suite(
  cases : Array[SuiteCase],
  max_cases~ : Int32 = 1000,
  max_checks~ : Int32 = 1000000,
  explain_mismatches~ : Bool = false,
) -> SuiteReport raise {
  if max_cases < 0 || max_checks < 0 || cases.length() > max_cases {
    raise @replay.ReplayError({
      code: "suite_limit",
      path: "$suite",
      message: "suite limits must be nonnegative and max_cases must cover every case",
    })
  }
  let names : Map[String, Bool] = Map([])
  let mut total = 0
  for i, case in cases {
    if names.get(case.name) is Some(_) {
      raise @replay.ReplayError({
        code: "duplicate_case",
        path: "$suite[\{i}]",
        message: "case names must be unique; no case was executed",
      })
    }
    names.set(case.name, true)
    if case.plan.length() >= max_checks - total {
      raise @replay.ReplayError({
        code: "suite_limit",
        path: "$suite[\{i}]",
        message: "total steps plus completion checks exceed max_checks; no case was executed",
      })
    }
    total += case.plan.length() + 1
  }
  let executions = cases.map(case => {
    let report = case.plan.verify(
      case.cassette.session(mode=case.mode),
      explain_mismatches~,
    )
    CaseExecution::{
      name: case.name,
      report,
      adaptations: case.cassette.adaptations(),
    }
  })
  { cases: executions, }
}

///|
pub fn SuiteReport::passed(self : SuiteReport) -> Bool {
  self.cases.iter().all(case => case.report.passed())
}

///|
pub fn SuiteReport::cases(self : SuiteReport) -> Array[(String, RunReport)] {
  self.cases.map(case => (case.name, case.report))
}

///|
pub fn SuiteReport::render_json(self : SuiteReport) -> String {
  let cases = self.cases.map(case => {
    let adaptations = case.adaptations.map(change => {
      let after : Json = match change.after {
        None => Json::null()
        Some(s) => Json(s)
      }
      let value : Json = {
        "entry_index": change.entry_index,
        "header_index": change.header_index,
        "name": change.name,
        "before": change.before,
        "after": after,
      }
      value
    })
    let value : Json = {
      "name": case.name,
      "report": case.report.json(),
      "adaptations": adaptations,
    }
    value
  })
  let value : Json = { "schema": 1, "passed": self.passed(), "cases": cases }
  value.stringify()
}

///|
/// Unique class names prevent different cases' step.0 results from colliding in CI consumers.
pub fn SuiteReport::render_junit(self : SuiteReport) -> String {
  let mut tests = 0
  let mut failures = 0
  let mut skipped = 0
  for case in self.cases {
    let (t, f, s) = case.report.counts()
    tests += t
    failures += f
    skipped += s
  }
  let output = StringBuilder()
  output.write_string(
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<testsuites tests=\"\{tests}\" failures=\"\{failures}\" errors=\"0\" skipped=\"\{skipped}\">\n",
  )
  for case in self.cases {
    case.report.write_junit(
      output,
      case.name,
      "echoreel." + case.name,
      prefix=case.name + ".",
    )
  }
  output.write_string("</testsuites>\n")
  output.to_string()
}
