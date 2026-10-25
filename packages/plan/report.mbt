///|
/// Passed means a check succeeded; the overall transaction may still roll back.
pub(all) enum StepOutcome {
  Passed
  Failed
  Skipped
} derive(Eq, Debug)

///|
pub extend StepOutcome with Eq::{equal, not_equal}

///|
pub extend StepOutcome with @debug.Debug::{to_repr}

///|
pub struct RunReport {
  priv outcomes : Array[StepOutcome]
  priv completion : StepOutcome?
  priv diagnostic : @replay.Diagnostic?
  priv explanation : @replay.MatchReport?
}

///|
/// Execute once with atomic consumption, retaining attempted checks after rollback.
/// Expected replay failures become report data; unexpected errors still propagate.
pub fn Plan::verify(
  self : Plan,
  session : @replay.Session,
  require_complete~ : Bool = true,
  explain_mismatches~ : Bool = false,
) -> RunReport raise {
  let outcomes = Array::make(self.length(), Skipped)
  let mut diagnostic = None
  let explanations : Array[@replay.MatchReport] = []
  try
    self.execute(
      session,
      require_complete,
      outcomes,
      if explain_mismatches {
        Some(explanations)
      } else {
        None
      },
    )
  catch {
    @replay.ReplayError(d) => diagnostic = Some(d)
    e => raise e
  } noraise {
    _ => ()
  }
  let completion = if !require_complete {
    None
  } else if outcomes.contains(Failed) {
    Some(Skipped)
  } else if diagnostic == None {
    Some(Passed)
  } else {
    Some(Failed)
  }
  { outcomes, completion, diagnostic, explanation: explanations.get(0), }
}

///|
pub fn RunReport::passed(self : RunReport) -> Bool {
  self.diagnostic == None
}

///|
pub fn RunReport::outcomes(self : RunReport) -> Array[StepOutcome] {
  self.outcomes.copy()
}

///|
pub fn RunReport::completion(self : RunReport) -> StepOutcome? {
  self.completion
}

///|
pub fn RunReport::diagnostic(self : RunReport) -> @replay.Diagnostic? {
  self.diagnostic
}

///|
pub fn RunReport::explanation(self : RunReport) -> @replay.MatchReport? {
  self.explanation
}

///|
fn outcome_name(outcome : StepOutcome) -> String {
  match outcome {
    Passed => "passed"
    Failed => "failed"
    Skipped => "skipped"
  }
}

///|
pub fn RunReport::render_json(self : RunReport) -> String {
  let diagnostic : Json = match self.diagnostic {
    None => Json::null()
    Some(d) => { "code": d.code, "path": d.path, "message": d.message }
  }
  let completion : Json = match self.completion {
    None => Json::null()
    Some(s) => Json(outcome_name(s))
  }
  let value : Json = {
    "schema": 1,
    "committed": self.passed(),
    "diagnostic": diagnostic,
    "steps": self.outcomes.mapi((i, state) => {
      let step : Json = { "index": i, "outcome": outcome_name(state) }
      step
    }),
    "completion": completion,
  }
  if self.explanation is Some(explanation) && value is Object(fields) {
    fields.set("explanation", explanation.to_json())
  }
  value.stringify()
}

///|
fn xml_escape(value : String) -> String {
  value
  .replace_all(old="&", new="&amp;")
  .replace_all(old="<", new="&lt;")
  .replace_all(old=">", new="&gt;")
  .replace_all(old="\"", new="&quot;")
  .replace_all(old="'", new="&apos;")
}

///|
fn xml_case(
  output : StringBuilder,
  name : String,
  outcome : StepOutcome,
  diagnostic : @replay.Diagnostic?,
) -> Unit {
  output.write_string(
    "  <testcase classname=\"echoreel.plan\" name=\"" + name + "\">",
  )
  match outcome {
    Passed => ()
    Skipped =>
      output.write_string(
        "<skipped>not executed after an earlier failure</skipped>",
      )
    Failed => {
      let message = diagnostic
        .map(d => d.format())
        .unwrap_or("replay check failed")
      output.write_string(
        "<failure message=\"replay check failed\">" +
        xml_escape(message) +
        "</failure>",
      )
    }
  }
  output.write_string("</testcase>\n")
}

///|
/// Minimal JUnit XML: stable names, no timings, HTTP payloads, URLs or raw headers.
pub fn RunReport::render_junit(self : RunReport) -> String {
  let tests = self.outcomes.length() +
    (if self.completion == None { 0 } else { 1 })
  let skipped = self.outcomes.iter().filter(s => s == Skipped).count() +
    (if self.completion == Some(Skipped) { 1 } else { 0 })
  let failures = if self.passed() { 0 } else { 1 }
  let output = StringBuilder()
  output.write_string("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
  output.write_string(
    "<testsuite name=\"EchoReel\" tests=\"\{tests}\" failures=\"\{failures}\" errors=\"0\" skipped=\"\{skipped}\">\n",
  )
  output.write_string(
    "  <properties><property name=\"committed\" value=\"\{self.passed()}\"/></properties>\n",
  )
  for i, outcome in self.outcomes {
    xml_case(output, "step.\{i}", outcome, self.diagnostic)
  }
  if self.completion is Some(state) {
    xml_case(output, "completion", state, self.diagnostic)
  }
  output.write_string("</testsuite>\n")
  output.to_string()
}
