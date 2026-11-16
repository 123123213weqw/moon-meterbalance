///|
fn validate_windows(
  windows : WindowSpec,
  meter_count : Int32,
) -> Unit raise AuditError {
  if windows.start < 0L || windows.start > 1_000_000_000_000L {
    return invalid("window start must be between 0 and 1000000000000")
  }
  if windows.step < 1L || windows.step > 86_400L {
    return invalid("window step must be between 1 and 86400 seconds")
  }
  if windows.count < 1 ||
    windows.count > 4096 ||
    windows.count * meter_count > 200_000 {
    return invalid("invalid window count or too many meter-window cells")
  }
}

///|
fn index_readings(
  tree : Topology,
  windows : WindowSpec,
  readings : Array[Reading],
) -> Array[Reading?] raise AuditError {
  let meter_count = tree.meters.length()
  validate_windows(windows, meter_count)
  let slots : Array[Reading?] = Array::make(windows.count * meter_count, None)
  let stop = windows.start + windows.step * windows.count.to_int64()
  for reading in readings {
    let source = "line " + reading.line.to_string() + ": "
    if reading.line < 1 {
      return invalid("reading evidence line must be positive")
    }
    let index = match tree.positions.get(reading.meter) {
      Some(index) => index
      None => return invalid(source + "unknown meter " + reading.meter)
    }
    if reading.start < windows.start ||
      reading.start >= stop ||
      reading.end != reading.start + windows.step ||
      (reading.start - windows.start) % windows.step != 0L {
      return invalid(source + "interval does not match a configured window")
    }
    if reading.amount < 0L ||
      reading.amount > maximum_energy ||
      reading.tolerance < 0L ||
      reading.tolerance > maximum_energy {
      return invalid(source + "amount or tolerance is outside supported bounds")
    }
    let interval = ((reading.start - windows.start) / windows.step).to_int()
    let slot = interval * meter_count + index
    if slots[slot] is Some(existing) {
      return invalid(
        source + "duplicates reading at line " + existing.line.to_string(),
      )
    }
    slots[slot] = Some(reading)
  }
  slots
}

///|
test "reading index distinguishes absent samples from exact zero and accepts unordered input" {
  let tree = topology([
    test_meter("root", None),
    test_meter("child", Some("root")),
  ])
  let windows : WindowSpec = { start: 100L, step: 60L, count: 2, }
  let zero : Reading = {
    meter: "child",
    start: 100L,
    end: 160L,
    amount: 0L,
    tolerance: 0L,
    line: 3,
  }
  let second = { ..zero, meter: "root", start: 160L, end: 220L, line: 2, }
  let slots = index_readings(tree, windows, [second, zero])
  assert_true(slots[0] is None)
  assert_true(slots[1] is Some({ amount: 0L, line: 3, .. }))
  assert_true(slots[2] is Some({ amount: 0L, line: 2, .. }))
  assert_true(slots[3] is None)
}

///|
test "reading index rejects duplicates, out-of-range data and partial windows" {
  let tree = topology([test_meter("root", None)])
  let windows : WindowSpec = { start: 100L, step: 60L, count: 2, }
  let good : Reading = {
    meter: "root",
    start: 100L,
    end: 160L,
    amount: 0L,
    tolerance: 0L,
    line: 2,
  }
  for
    readings in [
      [good, { ..good, line: 7, }],
      [{ ..good, meter: "unknown", }],
      [{ ..good, start: 220L, end: 280L, }],
      [{ ..good, start: 101L, end: 161L, }],
      [{ ..good, end: 130L, }],
      [{ ..good, amount: -1L, }],
    ] {
    let rejected = try {
      ignore(index_readings(tree, windows, readings))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}
