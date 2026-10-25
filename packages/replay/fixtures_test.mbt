///|
/// Project-authored synthetic HAR entries for focused boundary tests.
fn entry() -> Json {
  {
    "startedDateTime": "2026-10-25T00:00:00Z",
    "time": 0,
    "request": {
      "method": "GET",
      "url": "https://example.invalid/a",
      "httpVersion": "HTTP/1.1",
      "headers": [],
      "cookies": [],
      "queryString": [],
      "headersSize": -1,
      "bodySize": 0,
    },
    "response": {
      "status": 200,
      "statusText": "OK",
      "httpVersion": "HTTP/1.1",
      "headers": [],
      "cookies": [],
      "content": {
        "size": 2,
        "mimeType": "text/plain; charset=utf-8",
        "text": "ok",
      },
      "redirectURL": "",
      "headersSize": -1,
      "bodySize": 2,
    },
    "cache": {},
    "timings": { "send": 0, "wait": 0, "receive": 0 },
  }
}

///|
fn at(value : Json, key : String) -> Json {
  guard value is Object(fields) else { abort("test fixture object expected") }
  fields.get(key).unwrap()
}

///|
fn put(value : Json, key : String, replacement : Json) -> Unit {
  guard value is Object(fields) else { abort("test fixture object expected") }
  fields.set(key, replacement)
}

///|
fn fixture(entries : Array[Json]) -> String {
  let value : Json = {
    "log": {
      "version": "1.2",
      "creator": { "name": "test", "version": "1" },
      "entries": entries,
    },
    "vendorMetadata": { "keep": [1, "拾响", true] },
  }
  value.stringify()
}

///|
fn rejected(source : String, code : String) -> Unit raise {
  try @replay.compile_har(source) catch {
    @replay.ReplayError(d) => {
      assert_eq(d.code, code)
      assert_true(d.path.has_prefix("$"))
    }
  } noraise {
    _ => fail("expected a rejected recording")
  }
}
