///|
/// Derive an editable request manifest. Includes HTTP values from the sanitized input.
/// Does not serialize or modify the original HAR; decoded-body audits remain on Cassette.
pub fn Cassette::request_plan(
  self : Cassette,
  assert_bodies~ : Bool = false,
  max_input_units~ : Int32 = 4194304,
) -> String raise ReplayError {
  if max_input_units < 1 {
    fail("invalid_limit", "$plan", "max_input_units must be positive")
  }
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
    if assert_bodies {
      guard step is Object(fields) else {
        abort("manifest construction invariant")
      }
      fields.set(
        "expect_body_base64",
        Json(@base64.encode(exchange.response.body)),
      )
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
