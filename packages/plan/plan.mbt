///|
/// A validated reusable request-and-expectation workflow.
pub struct Plan {
  priv steps : Array[(@replay.Request, @replay.Expectation)]
}

///|
pub fn Plan::new(steps : Array[(@replay.Request, @replay.Expectation)]) -> Plan {
  { steps: steps.copy(), }
}

///|
pub fn Plan::length(self : Plan) -> Int32 {
  self.steps.length()
}

///|
fn[T] invalid(path : String, message : String) -> T raise @replay.ReplayError {
  raise @replay.ReplayError({ code: "manifest_error", path, message, })
}

///|
fn get(object : Json, key : String) -> Json? {
  match object {
    Object(fields) => fields.get(key)
    _ => None
  }
}

///|
fn step_path(i : Int32, path : String) -> String {
  "$plan[\{i}]" +
  (if path.has_prefix("$.") {
    path[1:].to_owned()
  } else {
    "." + path[1:].to_owned()
  })
}

///|
/// Validate the complete manifest before execution. Limits count UTF-16 units and steps.
pub fn parse_plan(
  source : String,
  max_input_units~ : Int32 = 4194304,
  max_steps~ : Int32 = 10000,
) -> Plan raise @replay.ReplayError {
  if max_input_units < 1 || max_steps < 0 {
    invalid("$", "max_input_units must be positive and max_steps nonnegative")
  }
  if source.length() > max_input_units {
    invalid("$", "manifest exceeds max_input_units")
  }
  let manifest = @json.parse(
    source,
    reject_duplicate_keys=true,
    preserve_number_repr=true,
    max_nesting_depth=64,
  ) catch {
    _ => invalid("$", "invalid JSON, duplicate key or excessive nesting")
  }
  guard manifest is Array(requests) else { invalid("$", "expected an array") }
  if requests.length() > max_steps {
    invalid("$", "manifest exceeds max_steps")
  }

  let plan = requests.mapi((i, item) => {
    let path = "$[\{i}]"
    guard item is Object(fields) else { invalid(path, "expected an object") }
    for key, _ in fields {
      if ![
          "method", "url", "body", "headers", "expect_status", "expect_body", "expect_body_base64",
          "expect_headers", "expect_json",
        ].contains(key) {
        invalid(
          path, "unknown field; consult the documented request manifest fields",
        )
      }
    }
    guard get(item, "method") is Some(String(http_method)) else {
      invalid(path + ".method", "expected a string")
    }
    guard get(item, "url") is Some(String(url)) else {
      invalid(path + ".url", "expected a string")
    }
    let body = match get(item, "body") {
      None => b""
      Some(String(text)) => @utf8.encode(text)
      _ => invalid(path + ".body", "expected a UTF-8 string")
    }
    let headers : Array[(String, String)] = match get(item, "headers") {
      None => []
      Some(Array(values)) =>
        values.map(value => {
          guard value is Object(pairs) else {
            invalid(path + ".headers", "expected objects with name and value")
          }
          guard value is { "name": String(name), "value": String(text), .. } &&
            pairs.length() == 2 else {
            invalid(
              path + ".headers",
              "each header requires exactly name and value strings",
            )
          }
          (name, text)
        })
      _ =>
        invalid(
          path + ".headers",
          "expected an array; repeated headers retain their order",
        )
    }
    let expected : Int32? = match get(item, "expect_status") {
      None => None
      Some(value) => {
        let status : Int32 = @json.from_json(value) catch {
          _ =>
            invalid(
              path + ".expect_status",
              "expected an integer from 200 through 599",
            )
        }
        if status < 200 || status > 599 {
          invalid(
            path + ".expect_status",
            "expected an integer from 200 through 599",
          )
        }
        Some(status)
      }
    }
    let expected_body = match
      (get(item, "expect_body"), get(item, "expect_body_base64")) {
      (None, None) => None
      (Some(String(text)), None) => Some(@utf8.encode(text))
      (None, Some(String(text))) => {
        let bytes = @base64.decode(text) catch {
          _ =>
            invalid(
              path + ".expect_body_base64",
              "expected canonical padded base64",
            )
        }
        if @base64.encode(bytes) != text {
          invalid(
            path + ".expect_body_base64",
            "expected canonical padded base64 without whitespace",
          )
        }
        Some(bytes)
      }
      _ =>
        invalid(
          path, "expect_body and expect_body_base64 must be strings and are mutually exclusive",
        )
    }
    let expected_headers : Array[(String, Array[String])] = match
      get(item, "expect_headers") {
      None => []
      Some(Array(values)) =>
        values.map(value => {
          guard value is Object(fields) && fields.length() == 2 else {
            invalid(
              path + ".expect_headers",
              "each assertion requires exactly name and values",
            )
          }
          guard value is { "name": String(name), "values": Array(items), .. } else {
            invalid(
              path + ".expect_headers",
              "expected name string and values array",
            )
          }
          (
            name,
            items.map(v => {
              match v {
                String(text) => text
                _ => invalid(path + ".expect_headers", "values must be strings")
              }
            }),
          )
        })
      _ => invalid(path + ".expect_headers", "expected an array")
    }
    let expected_json : Array[(String, String)] = match
      get(item, "expect_json") {
      None => []
      Some(Array(values)) =>
        values.map(value => {
          guard value is Object(fields) && fields.length() == 2 else {
            invalid(
              path + ".expect_json",
              "each assertion requires exactly pointer and value",
            )
          }
          guard get(value, "pointer") is Some(String(pointer)) &&
            get(value, "value") is Some(expected) else {
            invalid(
              path + ".expect_json",
              "expected a pointer string and any JSON value",
            )
          }
          (pointer, expected.stringify())
        })
      _ => invalid(path + ".expect_json", "expected an array")
    }
    (
      @replay.Request::new(http_method, url, body~, headers~),
      @replay.Expectation::new(
        status?=expected,
        body?=expected_body,
        headers=expected_headers,
        json=expected_json,
      ) catch {
        @replay.ReplayError(d) =>
          raise @replay.ReplayError({
            code: d.code,
            path: step_path(i, d.path),
            message: d.message,
          })
      },
    )
  })
  Plan::new(plan)
}

///|
/// Execute all steps atomically; completion is part of the transaction by default.
pub fn Plan::run(
  self : Plan,
  session : @replay.Session,
  require_complete~ : Bool = true,
) -> Array[@replay.Response] raise {
  self.execute(
    session,
    require_complete,
    Array::make(self.length(), Skipped),
    None,
  )
}

///|
fn Plan::execute(
  self : Plan,
  session : @replay.Session,
  require_complete : Bool,
  outcomes : Array[StepOutcome],
  explanations : Array[@replay.MatchReport]?,
) -> Array[@replay.Response] raise {
  session.transaction(s => {
    let responses = self.steps.mapi((i, pair) => {
      let response = s.take_checked(pair.0, pair.1) catch {
        @replay.ReplayError(d) => {
          outcomes[i] = Failed
          if explanations is Some(reports) &&
            ["request_mismatch", "no_match", "ambiguous_request"].contains(
              d.code,
            ) {
            reports.push(s.explain(pair.0))
          }
          raise @replay.ReplayError({
            code: d.code,
            path: step_path(i, d.path),
            message: d.message,
          })
        }
      }
      outcomes[i] = Passed
      response
    })
    if require_complete {
      s.finish()
    }
    responses
  })
}
