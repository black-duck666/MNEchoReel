///|
priv struct SuiteLoadBudget {
  mut used : Int32
  limit : Int32
}

///|
fn SuiteLoadBudget::charge(
  self : SuiteLoadBudget,
  units : Int32,
  path : String,
) -> Unit raise @replay.ReplayError {
  if units > self.limit - self.used {
    suite_fail(
      "suite_limit", path, "compiled input budget exceeded; increase max_total_input_units deliberately",
    )
  }
  self.used += units
}

///|
fn suite_snapshot(
  path : String,
  load : (String) -> String raise,
  files : Map[String, String],
) -> String raise {
  match files.get(path) {
    Some(source) => source
    None => {
      let source = load(path)
      files.set(path, source)
      source
    }
  }
}

///|
fn suite_input_error(
  index : Int32,
  kind : String,
  diagnostic : @replay.Diagnostic,
) -> @replay.ReplayError {
  let original = diagnostic.path
  let suffix = if original == "$" {
    ""
  } else if original.has_prefix("$.") || original.has_prefix("$[") {
    original[1:].to_owned()
  } else if original.has_prefix("$") {
    "." + original[1:].to_owned()
  } else {
    "." + original
  }
  @replay.ReplayError({
    code: diagnostic.code,
    path: "$suite[\{index}]." + kind + suffix,
    message: diagnostic.message,
  })
}

///|
/// Per invocation: read each exact path once, compile each HAR configuration and plan path once.
/// Loader errors propagate unchanged. Caches never survive a later load invocation.
pub fn SuiteManifest::load(
  self : SuiteManifest,
  load : (String) -> String raise,
  max_total_input_units~ : Int32 = 67108864,
) -> Array[SuiteCase] raise {
  if max_total_input_units < self.source.length() {
    suite_fail(
      "suite_limit", "$suite", "max_total_input_units must cover the manifest before loading inputs",
    )
  }
  let budget = SuiteLoadBudget::{
    used: self.source.length(),
    limit: max_total_input_units,
  }
  let files : Map[String, String] = Map([])
  let cassettes : Map[String, @replay.Cassette] = Map([])
  let plans : Map[String, Plan] = Map([])
  self.specs.map(spec => {
    let path = "$suite[\{spec.index}]"
    let key : Json = {
      "har": spec.har,
      "decoded": spec.decoded,
      "headers": spec.headers,
    }
    let cache_key = key.stringify()
    let cassette = match cassettes.get(cache_key) {
      Some(cassette) => cassette
      None => {
        let source = suite_snapshot(spec.har, load, files)
        budget.charge(source.length(), path)
        let cassette = @replay.compile_har(
          source,
          body_profile=if spec.decoded { DecodedContent } else { Identity },
          match_headers=spec.headers,
        ) catch {
          @replay.ReplayError(d) =>
            raise suite_input_error(spec.index, "har", d)
        }
        cassettes.set(cache_key, cassette)
        cassette
      }
    }
    let plan = match plans.get(spec.requests) {
      Some(plan) => plan
      None => {
        let source = suite_snapshot(spec.requests, load, files)
        budget.charge(source.length(), path)
        let plan = parse_plan(source) catch {
          @replay.ReplayError(d) =>
            raise suite_input_error(spec.index, "requests", d)
        }
        plans.set(spec.requests, plan)
        plan
      }
    }
    SuiteCase::new(spec.name, cassette, plan, mode=spec.mode)
  })
}
