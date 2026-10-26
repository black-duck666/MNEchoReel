///|
/// Derive an editable request manifest. Includes HTTP values from the sanitized input.
/// Does not serialize or modify the original HAR; decoded-body audits remain on Cassette.
/// assert_headers snapshots selected ordered values or absence; assert_json requires
/// each selected pointer in every strict JSON response. Empty selections preserve defaults.
pub fn Cassette::request_plan(
  self : Cassette,
  assert_bodies~ : Bool = false,
  assert_headers~ : Array[String] = [],
  assert_json~ : Array[String] = [],
  max_input_units~ : Int32 = 4194304,
) -> String raise ReplayError {
  if max_input_units < 1 {
    fail("invalid_limit", "$plan", "max_input_units must be positive")
  }
  if assert_headers.length() > 256 {
    fail(
      "invalid_plan_option", "$plan.assert_headers", "at most 256 unique response header names are supported",
    )
  }
  let names : Array[String] = []
  for i, name in assert_headers {
    if !token(name) ||
      names.iter().any(previous => previous.equal_ignore_ascii_case(name)) {
      fail(
        "invalid_plan_option",
        "$plan.assert_headers[\{i}]",
        "response header names must be unique HTTP tokens, ignoring ASCII case",
      )
    }
    names.push(name)
  }
  let pointers = plan_pointers(assert_json)
  let steps = self.exchanges.mapi((i, exchange) => {
    let request = exchange.request
    let text = @utf8.decode(request.body, ignore_bom=false) catch {
      _ =>
        fail(
          "unsupported_body",
          "$.log.entries[\{i}].request.postData",
          "request-plan export requires exact UTF-8 request bytes",
        )
    }
    if @utf8.encode(text) != request.body {
      fail(
        "unsupported_body",
        "$.log.entries[\{i}].request.postData",
        "request bytes cannot roundtrip as a JSON text body",
      )
    }
    let headers = request.headers.map(pair => {
      let value : Json = { "name": pair.0, "value": pair.1 }
      value
    })
    let step : Json = {
      "method": request.http_method,
      "url": request.url,
      "headers": headers,
      "body": text,
      "expect_status": exchange.response.status,
    }
    if assert_bodies || !names.is_empty() || !pointers.is_empty() {
      guard step is Object(fields) else {
        abort("manifest construction invariant")
      }
      if assert_bodies {
        fields.set(
          "expect_body_base64",
          Json(@base64.encode(exchange.response.body)),
        )
      }
      if !names.is_empty() {
        let assertions = names.map(name => {
          let assertion : Json = {
            "name": name,
            "values": selected(exchange.response.headers, name),
          }
          assertion
        })
        fields.set("expect_headers", Json(assertions))
      }
      if !pointers.is_empty() {
        fields.set(
          "expect_json",
          Json(
            plan_json_assertions(
              exchange.response.body,
              assert_json,
              pointers,
              i,
            ),
          ),
        )
      }
    }
    step
  })
  let output = Json(steps).stringify(indent=2) + "\n"
  if output.length() > max_input_units {
    fail(
      "plan_limit", "$plan", "generated manifest exceeds max_input_units; raise the export and parse_plan limits together through the library",
    )
  }
  output
}
