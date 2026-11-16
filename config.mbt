///|
fn required(fields : Map[String, Json], name : String) -> Json raise AuditError {
  match fields.get(name) {
    Some(value) => value
    None => invalid("missing configuration field: " + name)
  }
}

///|
fn text_field(value : Json, name : String) -> String raise AuditError {
  match value {
    String(text) => text
    _ => invalid("configuration field must be a string: " + name)
  }
}

///|
fn verify_keys(
  fields : Map[String, Json],
  allowed : Array[String],
) -> Unit raise AuditError {
  for key, _ in fields {
    if !allowed.contains(key) {
      return invalid("unknown configuration field: " + key)
    }
  }
}

///|
fn small_integer(
  value : Json,
  name : String,
  max : Int32,
) -> Int32 raise AuditError {
  guard value is Number(n, ..) else {
    return invalid("configuration field must be a number: " + name)
  }
  if !(n >= 1.0 && n <= max.to_double()) || n.to_int().to_double() != n {
    return invalid("configuration field must be an in-range integer: " + name)
  }
  n.to_int()
}

///|
fn parse_meter(value : Json) -> Meter raise AuditError {
  guard value is Object(fields) else {
    return invalid("meter configuration must be an object")
  }
  verify_keys(fields, ["id", "parent", "residual_min_uws", "residual_max_uws"])
  let id = text_field(required(fields, "id"), "id")
  let parent = match required(fields, "parent") {
    Null => None
    value => Some(text_field(value, "parent"))
  }
  let residual_min = match fields.get("residual_min_uws") {
    None => 0L
    Some(value) =>
      bounded_integer(text_field(value, "residual_min_uws"), maximum_energy)
  }
  let residual_max = match fields.get("residual_max_uws") {
    None | Some(Null) => None
    Some(value) =>
      Some(
        bounded_integer(text_field(value, "residual_max_uws"), maximum_energy),
      )
  }
  { id, parent, residual_min, residual_max, }
}

///|
/// Inspect a parsed configuration document and validate before accepting readings.
pub fn configuration(input : Json) -> (Topology, WindowSpec) raise AuditError {
  guard input is Object(fields) else {
    return invalid("configuration must be an object")
  }
  verify_keys(fields, ["schema", "window", "meters"])
  guard required(fields, "schema") is String("meterbalance/v1") else {
    return invalid("schema must be meterbalance/v1")
  }
  guard required(fields, "window") is Object(window) else {
    return invalid("window configuration must be an object")
  }
  verify_keys(window, ["start", "step", "count"])
  let start = bounded_integer(
    text_field(required(window, "start"), "start"),
    1_000_000_000_000L,
  )
  let step = small_integer(required(window, "step"), "step", 86_400).to_int64()
  let count = small_integer(required(window, "count"), "count", 4096)
  let windows : WindowSpec = { start, step, count, }
  guard required(fields, "meters") is Array(items) else {
    return invalid("meters configuration must be an array")
  }
  if items.length() > maximum_meters {
    return invalid("too many meter definitions")
  }
  let meters = []
  for item in items {
    meters.push(parse_meter(item))
  }
  let tree = topology(meters)
  validate_windows(windows, meters.length())
  (tree, windows)
}

///|
test "configuration enforces the schema and exact residual-bound representation" {
  let doc : Json = {
    "schema": "meterbalance/v1",
    "window": { "start": "42", "step": 60, "count": 2 },
    "meters": [
      { "id": "main", "parent": null, "residual_max_uws": "3600000000" },
      { "id": "sub", "parent": "main" },
    ],
  }
  let (tree, windows) = configuration(doc)
  assert_eq(tree.root_id(), "main")
  assert_eq(tree.meters[tree.root].residual_max, Some(3_600_000_000L))
  assert_eq(windows.start, 42L)
  assert_eq(windows.step, 60L)
  assert_eq(windows.count, 2)
}
