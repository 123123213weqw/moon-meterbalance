///|
fn state_text(state : State) -> String {
  match state {
    Leaf => "leaf"
    Feasible => "feasible"
    Inconsistent => "inconsistent"
    Incomplete => "incomplete"
    Blocked => "blocked"
  }
}

///|
fn int_string(value : Int64) -> Json {
  Json::string(value.to_string())
}

///|
fn[T] nullable(value : T?, encode : (T) -> Json) -> Json {
  match value {
    None => Json::null()
    Some(value) => encode(value)
  }
}

///|
fn band_json(band : Band) -> Json {
  Json::object({
    "lower": int_string(band.lower),
    "upper": int_string(band.upper),
  })
}

///|
fn witness_json(witness : Witness) -> Json {
  Json::object({
    "measured": band_json(witness.measured),
    "required": band_json(witness.required),
  })
}

///|
fn evidence_json(evidence : Evidence) -> Json {
  Json::object({
    "meter": Json::string(evidence.meter),
    "line": Json(evidence.line),
    "amount": int_string(evidence.amount),
    "tolerance": int_string(evidence.tolerance),
  })
}

///|
fn node_json(node : NodeResult) -> Json {
  Json::object({
    "meter": Json::string(node.meter),
    "local_state": Json::string(state_text(node.local_state)),
    "tree_state": Json::string(state_text(node.tree_state)),
    "nominal_residual": nullable(node.nominal_residual, int_string),
    "residual_band": nullable(node.residual_band, band_json),
    "feasible_band": nullable(node.feasible_band, band_json),
    "local_witness": nullable(node.local_witness, witness_json),
    "tree_witness": nullable(node.tree_witness, witness_json),
    "own": nullable(node.own, evidence_json),
    "children": Json::array(node.children.map(evidence_json)),
    "missing": Json::array(node.missing.map(Json::string)),
    "blockers": Json::array(node.blockers.map(Json::string)),
  })
}

///|
/// Energy and time are serialized as decimal strings for exact JS interop.
pub fn report_json(report : Report) -> Json {
  Json::object({
    "schema": Json::string("meterbalance/report/v1"),
    "unit": Json::string("microwatt_second"),
    "root": Json::string(report.root),
    "windows": Json::array(
      report.windows.map(window => {
        Json::object({
          "start": int_string(window.start),
          "end": int_string(window.end),
          "nodes": Json::array(window.nodes.map(node_json)),
        })
      }),
    ),
  })
}
