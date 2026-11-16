///|
let maximum_meters : Int32 = 256

///|
/// Validated single-root meter tree. Indices preserve input meter order.
pub struct Topology {
  meters : Array[Meter]
  positions : Map[String, Int32]
  children : Array[Array[Int32]]
  leaf_first : Array[Int32]
  root : Int32
}

///|
fn valid_id(id : String) -> Bool {
  if id.length() < 1 || id.length() > 64 {
    return false
  }
  for c in id {
    if !((c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '_' ||
      c == '-' ||
      c == '.') {
      return false
    }
  }
  true
}

///|
pub fn topology(specs : Array[Meter]) -> Topology raise AuditError {
  let length = specs.length()
  if length < 1 || length > maximum_meters {
    return invalid("meter count must be between 1 and 256")
  }
  let meters = specs.copy()
  let positions : Map[String, Int32] = Map([])
  let parent : Array[Int32?] = Array::make(length, None)
  let children : Array[Array[Int32]] = []
  for index, meter in meters {
    if !valid_id(meter.id) {
      return invalid("invalid meter id: " + meter.id)
    }
    if positions.contains(meter.id) {
      return invalid("duplicate meter id: " + meter.id)
    }
    if meter.residual_min < 0L || meter.residual_min > maximum_energy {
      return invalid("invalid lower residual bound for " + meter.id)
    }
    if meter.residual_max is Some(upper) &&
      (upper < meter.residual_min || upper > maximum_energy) {
      return invalid("invalid upper residual bound for " + meter.id)
    }
    positions[meter.id] = index
    children.push([])
  }
  let mut root = -1
  for index, meter in meters {
    match meter.parent {
      None =>
        if root >= 0 {
          return invalid("topology must have a single root")
        } else {
          root = index
        }
      Some(id) =>
        match positions.get(id) {
          None => return invalid("unknown parent " + id + " for " + meter.id)
          Some(owner) => {
            parent[index] = Some(owner)
            children[owner].push(index)
          }
        }
    }
  }
  if root < 0 {
    return invalid("topology has no root")
  }
  let pending = children.map(group => group.length())
  let leaf_first = []
  for index, remaining in pending {
    if remaining == 0 {
      let meter = meters[index]
      if meter.residual_min != 0L || meter.residual_max is Some(_) {
        return invalid("residual bounds require children for " + meter.id)
      }
      leaf_first.push(index)
    }
  }
  let mut cursor = 0
  while cursor < leaf_first.length() {
    let index = leaf_first[cursor]
    if parent[index] is Some(owner) {
      pending[owner] = pending[owner] - 1
      if pending[owner] == 0 {
        leaf_first.push(owner)
      }
    }
    cursor = cursor + 1
  }
  if leaf_first.length() != length {
    return invalid("topology contains a cycle disconnected from the root")
  }
  { meters, positions, children, leaf_first, root, }
}

///|
pub fn Topology::root_id(self : Topology) -> String {
  self.meters[self.root].id
}

///|
pub fn Topology::meter_ids(self : Topology) -> Array[String] {
  self.meters.map(meter => meter.id)
}

///|
fn test_meter(id : String, parent : String?) -> Meter {
  { id, parent, residual_min: 0L, residual_max: None, }
}

///|
test "topology accepts arbitrary input order and constructs leaf-first order" {
  let result = topology([
    test_meter("device", Some("floor")),
    test_meter("main", None),
    test_meter("floor", Some("main")),
  ])
  assert_eq(result.root_id(), "main")
  assert_eq(result.meter_ids(), ["device", "main", "floor"])
  assert_eq(result.leaf_first, [0, 2, 1])
  assert_eq(result.children[1], [2])
  assert_eq(result.positions.get("floor"), Some(2))
}

///|
test "topology rejects disconnected cycles and duplicate identifiers" {
  for
    bad in [
      [
        test_meter("main", None),
        test_meter("a", Some("b")),
        test_meter("b", Some("a")),
      ],
      [test_meter("main", None), test_meter("main", Some("main"))],
      [test_meter("main", None), test_meter("a", Some("missing"))],
      [test_meter("main", None), test_meter("branch", None)],
    ] {
    let rejected = try {
      ignore(topology(bad))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}
