///|
fn bounded_integer(value : String, limit : Int64) -> Int64 raise AuditError {
  if value.is_empty() || value.length() > 20 {
    return invalid("expected nonnegative integer")
  }
  let mut result = 0L
  for char in value {
    if char < '0' || char > '9' {
      return invalid("expected nonnegative integer")
    }
    result = result * 10L + (char.to_int() - '0'.to_int()).to_int64()
    if result > limit {
      return invalid("integer exceeds supported bounds")
    }
  }
  result
}

///|
fn parse_row(line : String, number : Int32) -> Reading raise AuditError {
  let cells = line.split(",").map(cell => cell.trim().to_owned()).collect()
  if cells.length() != 6 {
    return invalid("expected six comma-delimited fields")
  }
  let start = bounded_integer(cells[1], 1_001_000_000_000L)
  let end = bounded_integer(cells[2], 1_001_000_000_000L)
  let unit = match cells[4] {
    "Wh" => Wh
    "kWh" => Kwh
    "mean_kW" => MeanKw
    _ => return invalid("unit must be Wh, kWh, or mean_kW")
  }
  let seconds = end - start
  {
    meter: cells[0],
    start,
    end,
    amount: energy_microwatt_seconds(cells[3], unit, seconds),
    tolerance: energy_microwatt_seconds(cells[5], unit, seconds),
    line: number,
  }
}

///|
/// The narrow CSV dialect contains unquoted IDs and numeric fields. An omitted
/// reading is represented by an absent record. A recorded zero uses value 0.
pub fn readings_from_csv(input : String) -> Array[Reading] raise AuditError {
  let readings = []
  let mut number = 0
  for raw in input.split("\n") {
    number = number + 1
    let line = raw.trim().to_owned()
    if number == 1 {
      if line != "meter,start,end,value,unit,tolerance" &&
        line != "\u{feff}meter,start,end,value,unit,tolerance" {
        return invalid(
          "expected CSV header meter,start,end,value,unit,tolerance",
        )
      }
    } else if line != "" {
      if readings.length() == 200_000 {
        return invalid("too many CSV readings")
      }
      let reading = parse_row(line, number) catch {
        AuditError::Invalid(problem) =>
          return invalid("line " + number.to_string() + ": " + problem)
      }
      readings.push(reading)
    }
  }
  if number == 0 {
    return invalid("missing CSV header")
  }
  readings
}

///|
test "CSV normalizes units and preserves physical lines across blank rows" {
  let readings = readings_from_csv(
    "\u{feff}meter,start,end,value,unit,tolerance\r\nroot,0,60,4.216,mean_kW,0.001\r\n\r\nsub,0,60,1,Wh,0\r\n",
  )
  assert_eq(readings.length(), 2)
  assert_eq(readings[0].amount, 252_960_000_000L)
  assert_eq(readings[0].tolerance, 60_000_000L)
  assert_eq(readings[1].amount, 3_600_000_000L)
  assert_eq(readings[1].line, 4)
}

///|
test "CSV rejects unsupported units and identifies the source row" {
  let message = try {
    ignore(
      readings_from_csv(
        "meter,start,end,value,unit,tolerance\nroot,0,60,1,kW,0\n",
      ),
    )
    ""
  } catch {
    AuditError::Invalid(message) => message
  }
  assert_eq(message, "line 2: unit must be Wh, kWh, or mean_kW")
}
