///|
#cfg(target="js")
const ARG_START : Int32 = 2

///|
#cfg(not(target="js"))
const ARG_START : Int32 = 1

///|
suberror CliError {
  CliError(String)
}

///|
fn[T] invalid(path : String, message : String) -> T raise CliError {
  raise CliError("manifest_error at \{path}: \{message}")
}

///|
fn get(object : Json, key : String) -> Json? {
  match object {
    Object(fields) => fields.get(key)
    _ => None
  }
}

///|
fn run(args : Array[String]) -> Unit raise {
  guard args.length() == ARG_START + 2 else {
    raise CliError(
      "usage: moon run packages/check -- <recording.har> <requests.json>",
    )
  }
  let cassette = @replay.compile_har(@fs.read_file_to_string(args[ARG_START]))
  let manifest = @json.parse(
    @fs.read_file_to_string(args[ARG_START + 1]),
    reject_duplicate_keys=true,
    max_nesting_depth=16,
  ) catch {
    _ =>
      raise CliError(
        "manifest_error at $: invalid JSON, duplicate key or excessive nesting",
      )
  }
  guard manifest is Array(requests) else { invalid("$", "expected an array") }
  // Validate the entire plan before consuming any exchange.
  let plan = requests.mapi((i, item) => {
    let path = "$[\{i}]"
    guard item is Object(fields) else { invalid(path, "expected an object") }
    for key, _ in fields {
      if ![
          "method", "url", "body", "headers", "expect_status", "expect_body", "expect_body_base64",
          "expect_headers",
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
    (
      @replay.Request::new(http_method, url, body~, headers~),
      @replay.Expectation::new(
        status?=expected,
        body?=expected_body,
        headers=expected_headers,
      ),
    )
  })
  let session = cassette.session()
  for i, (request, expected) in plan {
    let response = session.take_checked(request, expected)
    println(
      "\{i}: status=\{response.status()} bytes=\{response.body().length()}",
    )
  }
  session.finish()
  println("all \{cassette.length()} recorded exchanges consumed")
}

///|
fn main {
  run(@env.args()) catch {
    @replay.ReplayError(d) => {
      println(d.format())
      @sys.exit(1)
    }
    CliError(message) => {
      println(message)
      @sys.exit(2)
    }
    _ => {
      println(
        "input_error: cannot read the input file; check its path, permissions and UTF-8 encoding",
      )
      @sys.exit(2)
    }
  }
}
