///|
fn plan_pointers(
  names : Array[String],
) -> Array[Array[String]] raise ReplayError {
  if names.length() > 256 {
    fail(
      "invalid_plan_option", "$plan.assert_json", "at most 256 unique JSON pointers are supported",
    )
  }
  let tokens = []
  for i, name in names {
    let pointer = pointer_tokens(name) catch {
      ReplayError(_) =>
        fail(
          "invalid_plan_option",
          "$plan.assert_json[\{i}]",
          "expected an RFC 6901 string pointer within 4096 UTF-16 units and 64 tokens",
        )
    }
    if tokens.contains(pointer) {
      fail(
        "invalid_plan_option",
        "$plan.assert_json[\{i}]",
        "JSON pointers must be unique",
      )
    }
    tokens.push(pointer)
  }
  tokens
}

///|
// The plan adds four containers around each expected value; parse_plan permits depth 64.
fn plan_json_depth(value : Json, remaining : Int32) -> Bool {
  match value {
    Array(items) =>
      remaining > 0 &&
      items.iter().all(item => plan_json_depth(item, remaining - 1))
    Object(fields) =>
      remaining > 0 &&
      fields.iter().all(pair => plan_json_depth(pair.1, remaining - 1))
    _ => true
  }
}

///|
fn plan_json_assertions(
  bytes : Bytes,
  names : Array[String],
  pointers : Array[Array[String]],
  entry_index : Int32,
) -> Array[Json] raise ReplayError {
  let path = "$.log.entries[\{entry_index}].response.content"
  let text = @utf8.decode(bytes, ignore_bom=false) catch {
    _ =>
      fail(
        "plan_json_invalid", path, "JSON contract generation requires strict UTF-8 response bytes",
      )
  }
  let root = @json.parse(
    text,
    reject_duplicate_keys=true,
    preserve_number_repr=true,
    max_nesting_depth=64,
  ) catch {
    _ =>
      fail(
        "plan_json_invalid", path, "response JSON is malformed, has duplicate keys or exceeds depth 64",
      )
  }
  pointers.mapi((i, tokens) => {
    let value = match pointer_lookup(root, tokens) {
      Located(value) => value
      NotFound =>
        fail(
          "plan_json_missing",
          path + ".pointers[\{i}]",
          "selected JSON pointer does not resolve; no plan generated",
        )
      BadIndex =>
        fail(
          "plan_json_selector",
          path + ".pointers[\{i}]",
          "array selector must be a canonical nonnegative decimal index",
        )
    }
    if value.stringify().length() > 1048576 || !plan_json_depth(value, 60) {
      fail(
        "plan_json_limit",
        path + ".pointers[\{i}]",
        "selected JSON value exceeds 1048576 UTF-16 units or depth 60; choose a narrower pointer",
      )
    }
    let assertion : Json = { "pointer": names[i], "value": value }
    assertion
  })
}
