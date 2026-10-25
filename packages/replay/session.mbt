///|
fn selected(headers : Array[(String, String)], name : String) -> Array[String] {
  headers.filter_map(pair => {
    if pair.0.equal_ignore_ascii_case(name) {
      Some(pair.1)
    } else {
      None
    }
  })
}

///|
fn mismatch(a : Request, b : Request, names : Array[String]) -> String? {
  if a.http_method != b.http_method {
    return Some("method")
  }
  if a.url != b.url {
    return Some("url")
  }
  if a.body != b.body {
    return Some("body")
  }
  for name in names {
    if selected(a.headers, name) != selected(b.headers, name) {
      return Some("selected_headers")
    }
  }
  None
}

///|
/// A failed lookup never consumes an exchange. There is no network fallback.
fn Session::take_with(
  self : Session,
  request : Request,
  expected : Expectation?,
) -> Response raise ReplayError {
  let mut chosen : Int32? = None
  for i in 0..<self.used.length() {
    if self.used[i] {
      continue
    }
    let exchange = self.cassette.exchanges[i]
    let difference = mismatch(
      exchange.request,
      request,
      self.cassette.header_names,
    )
    if self.mode == Ordered {
      if difference is Some(field) {
        fail(
          "request_mismatch",
          "$.log.entries[\{i}].request.\{field}",
          "request differs; correct the request or recording; no exchange consumed",
        )
      }
      chosen = Some(i)
      break
    }
    if difference == None {
      if self.mode == PerRequest {
        chosen = Some(i)
        break
      }
      match chosen {
        None => chosen = Some(i)
        Some(first) =>
          if self.cassette.exchanges[first].response != exchange.response {
            fail(
              "ambiguous_request",
              "$.log.entries[\{i}]",
              "multiple matching requests have different responses; use Ordered or select distinguishing headers",
            )
          }
      }
    }
  }
  guard chosen is Some(index) else {
    fail(
      "no_match", "$.log.entries", "no unused matching exchange; check the request and cassette consumption",
    )
  }
  let response = self.cassette.exchanges[index].response
  if expected is Some(check) {
    check.check(response)
  }
  self.used[index] = true
  {
    status: response.status,
    headers: response.headers.copy(),
    body: response.body,
  }
}

///|
/// Match and consume one recorded response without additional assertions.
pub fn Session::take(
  self : Session,
  request : Request,
) -> Response raise ReplayError {
  self.take_with(request, None)
}

///|
/// Match and assert atomically. A failed assertion consumes nothing.
pub fn Session::take_checked(
  self : Session,
  request : Request,
  expected : Expectation,
) -> Response raise ReplayError {
  self.take_with(request, Some(expected))
}

///|
pub fn Session::remaining(self : Session) -> Int32 {
  self.used.iter().filter(used => !used).count()
}

///|
/// Assert that the tested workflow executed every recorded interaction.
pub fn Session::finish(self : Session) -> Unit raise ReplayError {
  let remaining = self.remaining()
  if remaining != 0 {
    fail(
      "unconsumed",
      "$.log.entries",
      "\{remaining} exchange(s) remain; complete the workflow or trim the fixture deliberately",
    )
  }
}

///|
pub fn Session::reset(self : Session) -> Unit {
  for i in 0..<self.used.length() {
    self.used[i] = false
  }
}
