///|
#cfg(target="js")
const ARG_START : Int32 = 2

///|
#cfg(not(target="js"))
const ARG_START : Int32 = 1

///|
fn main {
  let args = @env.args()
  guard args.length() == ARG_START + 2 else {
    println("usage: moon run packages/review -- <before.har> <after.har>")
    @sys.exit(2)
    return
  }
  try {
    let before = @replay.compile_har(@fs.read_file_to_string(args[ARG_START]))
    let after = @replay.compile_har(
      @fs.read_file_to_string(args[ARG_START + 1]),
    )
    let report = before.compare(after)
    println(report.render_json())
    if !report.is_empty() {
      @sys.exit(1)
    }
  } catch {
    @replay.ReplayError(d) => {
      println(d.format())
      @sys.exit(2)
    }
    _ => {
      println("input_error: check both HAR file paths and UTF-8 encoding")
      @sys.exit(2)
    }
  }
}
