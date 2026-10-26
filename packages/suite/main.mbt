///|
#cfg(target="js")
const ARG_START : Int32 = 2

///|
#cfg(not(target="js"))
const ARG_START : Int32 = 1

///|
suberror SuiteError {
  SuiteError(@replay.Diagnostic)
}

///|
fn[T] invalid(
  code : String,
  path : String,
  message : String,
) -> T raise SuiteError {
  raise SuiteError({ code, path, message, })
}

///|
fn read_shard(text : String) -> (Int32, Int32) raise SuiteError {
  guard text.split_once("/") is Some((index, count)) else {
    invalid("usage_error", "$args", "--shard requires zero-based INDEX/COUNT")
  }
  let index = @string.parse_int(index, base=10) catch {
    _ =>
      invalid("usage_error", "$args", "shard index must be a decimal integer")
  }
  let count = @string.parse_int(count, base=10) catch {
    _ =>
      invalid("usage_error", "$args", "shard count must be a decimal integer")
  }
  (index, count)
}

///|
fn run(args : Array[String]) -> Unit raise {
  guard args.length() >= ARG_START + 1 else {
    invalid(
      "usage_error", "$args", "usage: moon run packages/suite -- <suite.json> [--case NAME] [--shard INDEX/COUNT] [--list] [--explain] [--junit NEW_FILE.xml]",
    )
  }
  let mut explain = false
  let mut junit_path = None
  let selected_names : Array[String] = []
  let mut shard : (Int32, Int32)? = None
  let mut list_only = false
  let flags = args.iter().drop(ARG_START + 1)
  for flag in flags {
    match flag {
      "--explain" if !explain => explain = true
      "--list" if !list_only => list_only = true
      "--case" => {
        guard flags.next() is Some(name) && !name.is_empty() else {
          invalid("usage_error", "$args", "--case requires a case name")
        }
        selected_names.push(name)
      }
      "--shard" if shard == None => {
        guard flags.next() is Some(value) else {
          invalid("usage_error", "$args", "--shard requires INDEX/COUNT")
        }
        shard = Some(read_shard(value))
      }
      "--junit" if junit_path == None => {
        guard flags.next() is Some(path) &&
          !path.is_empty() &&
          !path.has_prefix("--") else {
          invalid(
            "usage_error", "$args", "--junit requires a new output file path",
          )
        }
        if @fs.path_exists(path) {
          invalid(
            "output_exists", "$output", "JUnit output already exists; choose a new path",
          )
        }
        junit_path = Some(path)
      }
      _ =>
        invalid(
          "usage_error", "$args", "unknown or repeated option; consult --case, --shard, --list, --explain and --junit usage",
        )
    }
  }
  if list_only && (explain || junit_path != None) {
    invalid(
      "usage_error", "$args", "--list cannot be combined with execution or JUnit options",
    )
  }
  let original = @plan.parse_suite_manifest(
    @fs.read_file_to_string(args[ARG_START]),
  )
  let has_selection = !selected_names.is_empty() || shard != None
  let manifest = if has_selection {
    original.select(
      names=selected_names,
      shard_index?=shard.map(pair => pair.0),
      shard_count?=shard.map(pair => pair.1),
    )
  } else {
    original
  }
  if list_only {
    println(manifest.selection_json().stringify())
    return
  }
  let cases = manifest.load(path => @fs.read_file_to_string(path))
  let report = @plan.verify_suite(cases, explain_mismatches=explain)
  if junit_path is Some(path) {
    @fs.write_string_to_file(path, report.render_junit()) catch {
      _ =>
        invalid(
          "output_error", "$output", "cannot write JUnit artifact; check parent directory and permissions",
        )
    }
  }
  if has_selection {
    let output = @json.parse(report.render_json())
    guard output is Object(fields) else { abort("suite report invariant") }
    fields.set("selection", manifest.selection_json())
    println(output.stringify())
  } else {
    println(report.render_json())
  }
  if !report.passed() {
    @sys.exit(1)
  }
}

///|
fn main {
  run(@env.args()) catch {
    @replay.ReplayError(d) | SuiteError(d) => {
      let error : Json = {
        "schema": 1,
        "passed": false,
        "diagnostic": { "code": d.code, "path": d.path, "message": d.message },
        "cases": [],
      }
      println(error.stringify())
      @sys.exit(2)
    }
    _ => {
      let error : Json = {
        "schema": 1,
        "passed": false,
        "diagnostic": {
          "code": "input_error",
          "path": "$input",
          "message": "cannot read complete UTF-8 inputs; check paths and permissions",
        },
        "cases": [],
      }
      println(error.stringify())
      @sys.exit(2)
    }
  }
}
