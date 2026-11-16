///|
fn propagate(
  tree : Topology,
  slots : Array[Reading?],
  offset : Int32,
  nodes : Array[NodeResult],
) -> Unit {
  for index in tree.leaf_first {
    let node = nodes[index]
    let mut lower = 0L
    let mut upper = 0L
    let missing = []
    let conflicts = []
    for child in tree.children[index] {
      let result = nodes[child]
      match result.tree_state {
        Inconsistent | Blocked => conflicts.push(result.meter)
        Incomplete => missing.push(result.meter)
        Leaf | Feasible =>
          if result.feasible_band is Some(bounds) {
            lower = lower + bounds.lower
            upper = upper + bounds.upper
          }
      }
    }
    if node.local_state is Inconsistent {
      nodes[index] = {
        ..node,
        tree_state: Inconsistent,
        tree_witness: node.local_witness,
      }
      continue
    }
    if !conflicts.is_empty() {
      nodes[index] = { ..node, tree_state: Blocked, blockers: conflicts, }
      continue
    }
    guard slots[offset + index] is Some(reading) else {
      nodes[index] = { ..node, blockers: missing, }
      continue
    }
    if !missing.is_empty() {
      nodes[index] = { ..node, blockers: missing, }
      continue
    }
    let measured = measured(reading)
    if tree.children[index].is_empty() {
      nodes[index] = {
        ..node,
        tree_state: Leaf,
        feasible_band: Some(measured),
      }
      continue
    }
    let limit = residual_limit(tree.meters[index])
    let required : Band = {
      lower: lower + limit.lower,
      upper: upper + limit.upper,
    }
    nodes[index] = match intersection(measured, required) {
      Some(feasible) =>
        { ..node, tree_state: Feasible, feasible_band: Some(feasible), }
      None =>
        {
          ..node,
          tree_state: Inconsistent,
          tree_witness: Some({ measured, required, }),
        }
    }
  }
}

///|
test "leaf evidence narrows its parent and disproves a locally feasible root" {
  let tree = topology([
    test_meter("root", None),
    { ..test_meter("floor", Some("root")), residual_max: Some(0L), },
    test_meter("device", Some("floor")),
  ])
  let report = audit(tree, { start: 0L, step: 60L, count: 1, }, [
    sample("root", 0L, 5L, 0L, 2),
    sample("floor", 0L, 5L, 1L, 3),
    sample("device", 0L, 6L, 0L, 4),
  ])
  let nodes = report.windows[0].nodes
  assert_true(nodes[0].local_state is Feasible)
  assert_true(nodes[0].tree_state is Inconsistent)
  assert_true(
    nodes[0].tree_witness
    is Some({ measured: { upper: 5L, .. }, required: { lower: 6L, .. }, }),
  )
  assert_true(nodes[1].feasible_band is Some({ lower: 6L, upper: 6L, }))
  assert_true(nodes[2].own is Some({ line: 4, .. }))
}

///|
test "missing and conflicting descendants remain visible to the root with no root reading" {
  let tree = topology([
    test_meter("root", None),
    test_meter("floor", Some("root")),
    test_meter("device", Some("floor")),
  ])
  let report = audit(tree, { start: 0L, step: 60L, count: 2, }, [
    sample("floor", 0L, 4L, 0L, 2),
    sample("device", 0L, 6L, 0L, 3),
    sample("root", 60L, 9L, 0L, 4),
    sample("floor", 60L, 4L, 0L, 5),
  ])
  assert_true(report.windows[0].nodes[0].tree_state is Blocked)
  assert_eq(report.windows[0].nodes[0].blockers, ["floor"])
  assert_true(report.windows[1].nodes[0].local_state is Feasible)
  assert_true(report.windows[1].nodes[0].tree_state is Incomplete)
  assert_eq(report.windows[1].nodes[0].blockers, ["floor"])
}
