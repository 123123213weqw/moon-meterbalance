///|
pub(all) suberror AuditError {
  Invalid(String)
}

///|
/// One unit is one millionth of a watt-second, stored as an Int64.
pub(all) struct Reading {
  meter : String
  start : Int64
  end : Int64
  amount : Int64
  tolerance : Int64
  line : Int32
}

///| Bounds constrain the direct residual at an internal node. If the upper

///|
/// bound is absent, any nonnegative unmetered load is admissible.
pub(all) struct Meter {
  id : String
  parent : String?
  residual_min : Int64
  residual_max : Int64?
}

///|
pub(all) struct WindowSpec {
  start : Int64
  step : Int64
  count : Int32
}

///|
pub(all) struct Band {
  lower : Int64
  upper : Int64
}

///|
pub(all) enum UnitKind {
  Wh
  Kwh
  MeanKw
}

///|
test "reading records carry the exact interval and evidence row" {
  let r : Reading = {
    meter: "root",
    start: 1_205_100_000L,
    end: 1_205_100_060L,
    amount: 1_250_000L,
    tolerance: 0L,
    line: 14,
  }
  assert_eq(r.end - r.start, 60L)
  assert_eq(r.line, 14)
  assert_eq(r.amount, 1_250_000L)
}
