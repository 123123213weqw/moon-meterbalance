///|
pub let maximum_energy : Int64 = 10_000_000_000_000_000L

///|
fn[T] invalid(reason : String) -> T raise AuditError {
  raise AuditError::Invalid(reason)
}

///|
/// Parse a nonnegative decimal into millionths with no floating point.
fn decimal_micros(value : String) -> Int64 raise AuditError {
  if value.length() == 0 || value.length() > 24 {
    return invalid("expected a bounded nonnegative decimal")
  }
  let mut whole = 0L
  let mut fraction = 0L
  let mut fraction_digits = 0
  let mut whole_digits = 0
  let mut decimal = false
  for code in value {
    if code == '.' {
      if decimal || whole_digits == 0 {
        return invalid("invalid decimal point")
      }
      decimal = true
    } else if code >= '0' && code <= '9' {
      let digit = (code.to_int() - '0'.to_int()).to_int64()
      if decimal {
        fraction_digits += 1
        if fraction_digits > 6 {
          return invalid("energy precision exceeds six decimal places")
        }
        fraction = fraction * 10L + digit
      } else {
        whole_digits += 1
        if whole > 1_000_000_000L {
          return invalid("energy decimal exceeds bound")
        }
        whole = whole * 10L + digit
      }
    } else {
      return invalid("unexpected character in energy decimal")
    }
  }
  if whole_digits == 0 || (decimal && fraction_digits == 0) {
    return invalid("missing decimal digits")
  }
  for _ in fraction_digits..<6 {
    fraction *= 10L
  }
  whole * 1_000_000L + fraction
}

///| Mean kW requires a measured window length in seconds. The result is

///|
/// exact in microwatt-seconds for all supported units.
pub fn energy_microwatt_seconds(
  decimal : String,
  unit : UnitKind,
  seconds : Int64,
) -> Int64 raise AuditError {
  if seconds < 1L || seconds > 86_400L {
    return invalid("interval must be between one second and one day")
  }
  let micros = decimal_micros(decimal)
  let factor = match unit {
    Wh => 3_600L
    Kwh => 3_600_000L
    MeanKw => 1_000L * seconds
  }
  if micros > maximum_energy / factor {
    return invalid("energy exceeds supported range")
  }
  micros * factor
}

///|
test "unit conversion preserves UCI nonintegral Wh exactly in watt-seconds" {
  assert_eq(energy_microwatt_seconds("4.216", MeanKw, 60L), 252_960_000_000L)
  assert_eq(energy_microwatt_seconds("1", Wh, 60L), 3_600_000_000L)
  assert_eq(energy_microwatt_seconds("0.001", Kwh, 60L), 3_600_000_000L)
  assert_eq(energy_microwatt_seconds("0.000001", MeanKw, 60L), 60_000L)
}

///|
test "energy input rejects rounded or overflowing values" {
  for value in ["NaN", "-0.1", "1e5", "1.", ".5", "1.0000021", "1000000000"] {
    let rejected = try {
      ignore(energy_microwatt_seconds(value, Kwh, 60L))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  assert_true(
    try {
      ignore(energy_microwatt_seconds("1", MeanKw, 0L))
      false
    } catch {
      _ => true
    },
  )
}
