///|
pub(all) enum State {
  Leaf
  Feasible
  Inconsistent
  Incomplete
  Blocked
}

///|
pub(all) struct Evidence {
  meter : String
  line : Int32
  amount : Int64
  tolerance : Int64
}

///|
/// A witness compares disjoint measured and required parent intervals.
pub(all) struct Witness {
  measured : Band
  required : Band
}

///|
pub(all) struct NodeResult {
  meter : String
  local_state : State
  nominal_residual : Int64?
  residual_band : Band?
  own : Evidence?
  children : Array[Evidence]
  missing : Array[String]
  local_witness : Witness?
}

///|
pub(all) struct WindowResult {
  start : Int64
  end : Int64
  nodes : Array[NodeResult]
}

///|
pub(all) struct Report {
  root : String
  windows : Array[WindowResult]
}

///|
fn measured(reading : Reading) -> Band {
  {
    lower: if reading.amount > reading.tolerance {
      reading.amount - reading.tolerance
    } else {
      0L
    },
    upper: reading.amount + reading.tolerance,
  }
}

///|
fn evidence(reading : Reading) -> Evidence {
  {
    meter: reading.meter,
    line: reading.line,
    amount: reading.amount,
    tolerance: reading.tolerance,
  }
}

///|
fn intersection(left : Band, right : Band) -> Band? {
  let lower = if left.lower > right.lower { left.lower } else { right.lower }
  let upper = if left.upper < right.upper { left.upper } else { right.upper }
  if lower > upper {
    None
  } else {
    Some({ lower, upper, })
  }
}

///|
fn residual_limit(meter : Meter) -> Band {
  {
    lower: meter.residual_min,
    upper: meter.residual_max.unwrap_or(maximum_energy * 2L),
  }
}

///|
fn local_balance(
  tree : Topology,
  slots : Array[Reading?],
  offset : Int32,
  index : Int32,
) -> NodeResult {
  let meter = tree.meters[index]
  let own = slots[offset + index].map(evidence)
  let children = []
  let missing = []
  if own is None {
    missing.push(meter.id)
  }
  let mut children_amount = 0L
  let mut children_min = 0L
  let mut children_max = 0L
  for child in tree.children[index] {
    match slots[offset + child] {
      None => missing.push(tree.meters[child].id)
      Some(reading) => {
        let bounds = measured(reading)
        children.push(evidence(reading))
        children_amount = children_amount + reading.amount
        children_min = children_min + bounds.lower
        children_max = children_max + bounds.upper
      }
    }
  }
  let pending : NodeResult = {
    meter: meter.id,
    local_state: Incomplete,
    nominal_residual: None,
    residual_band: None,
    own,
    children,
    missing,
    local_witness: None,
  }
  if missing.length() > 0 {
    return pending
  }
  guard slots[offset + index] is Some(reading) else { return pending }
  if tree.children[index].is_empty() {
    return { ..pending, local_state: Leaf, }
  }
  let measured = measured(reading)
  let residual : Band = {
    lower: measured.lower - children_max,
    upper: measured.upper - children_min,
  }
  let limit = residual_limit(meter)
  let ready = {
    ..pending,
    nominal_residual: Some(reading.amount - children_amount),
    residual_band: Some(residual),
  }
  match intersection(residual, limit) {
    Some(_) => { ..ready, local_state: Feasible, }
    None =>
      {
        ..ready,
        local_state: Inconsistent,
        local_witness: Some({
          measured,
          required: {
            lower: children_min + limit.lower,
            upper: children_max + limit.upper,
          },
        }),
      }
  }
}

///|
pub fn audit(
  tree : Topology,
  windows : WindowSpec,
  readings : Array[Reading],
) -> Report raise AuditError {
  let slots = index_readings(tree, windows, readings)
  let meter_count = tree.meters.length()
  let results = Array::makei(windows.count, interval => {
    let offset = interval * meter_count
    let start = windows.start + interval.to_int64() * windows.step
    {
      start,
      end: start + windows.step,
      nodes: Array::makei(meter_count, index => {
        local_balance(tree, slots, offset, index)
      }),
    }
  })
  { root: tree.root_id(), windows: results, }
}

///|
fn sample(
  meter : String,
  start : Int64,
  amount : Int64,
  tolerance : Int64,
  line : Int32,
) -> Reading {
  { meter, start, end: start + 60L, amount, tolerance, line, }
}

///|
test "local balance reports raw residual, supported absence and disjoint-band witness" {
  let tree = topology([
    test_meter("root", None),
    test_meter("child", Some("root")),
  ])
  let report = audit(tree, { start: 0L, step: 60L, count: 3, }, [
    sample("child", 0L, 5L, 1L, 3),
    sample("root", 0L, 4L, 0L, 2),
    sample("root", 60L, 9L, 0L, 4),
    sample("root", 120L, 3L, 0L, 5),
    sample("child", 120L, 5L, 1L, 6),
  ])
  let below_nominal = report.windows[0].nodes[0]
  assert_true(below_nominal.local_state is Feasible)
  assert_eq(below_nominal.nominal_residual, Some(-1L))
  assert_true(below_nominal.residual_band is Some({ lower: -2L, upper: 0L, }))
  assert_true(below_nominal.children[0] is { line: 3, .. })
  let partial = report.windows[1].nodes[0]
  assert_true(partial.local_state is Incomplete)
  assert_eq(partial.missing, ["child"])
  assert_eq(partial.nominal_residual, None)
  let conflict = report.windows[2].nodes[0]
  assert_true(conflict.local_state is Inconsistent)
  assert_true(
    conflict.local_witness
    is Some({ measured: { upper: 3L, .. }, required: { lower: 4L, .. }, }),
  )
}
