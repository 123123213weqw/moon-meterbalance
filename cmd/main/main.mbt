///|
extern "js" fn read_input_file(path : String) -> FixedArray[String] =
  #| path => {
  #|   const fs = process.getBuiltinModule('node:fs');
  #|   try {
  #|     const stat = fs.statSync(path);
  #|     if (!stat.isFile()) return ['', 'expected a regular file'];
  #|     if (stat.size > 16000000) return ['', 'input exceeds 16 MB'];
  #|     const bytes = fs.readFileSync(path);
  #|     if (bytes.length > 16000000) return ['', 'input exceeds 16 MB'];
  #|     return [new TextDecoder('utf-8', {fatal: true}).decode(bytes), ''];
  #|   } catch (error) {
  #|     return ['', error.code ?? 'invalid UTF-8 or input read failed'];
  #|   }
  #| }

///|
extern "js" fn cli_error(message : String) -> Unit =
  #| message => { console.error(message); process.exitCode = 1; }

///|
fn read_input(path : String) -> String raise @meter.AuditError {
  let fields = read_input_file(path)
  if fields[1] != "" {
    raise @meter.Invalid("cannot read " + path + ": " + fields[1])
  }
  fields[0]
}

///|
fn main {
  let args = @env.args()
  let usage = "Usage: moon run cmd/main --target js -- audit CONFIG.json READINGS.csv"
  if args.length() == 3 && args[2] == "--help" {
    println(usage)
    return
  }
  try {
    if args.length() != 5 || args[2] != "audit" {
      raise @meter.Invalid(usage)
    }
    let config = @json.parse(read_input(args[3]))
    let (tree, windows) = @meter.configuration(config)
    let readings = @meter.readings_from_csv(read_input(args[4]))
    let report = @meter.audit(tree, windows, readings)
    println(@meter.report_json(report).stringify())
  } catch {
    error => {
      let message = match error {
        @meter.Invalid(problem) => problem
        _ => error.to_string()
      }
      cli_error(Json::object({ "error": Json::string(message) }).stringify())
    }
  }
}
