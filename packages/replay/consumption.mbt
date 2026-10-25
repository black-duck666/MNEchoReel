///|
/// Immutable effective-state snapshot, not an attempt history or a resumable checkpoint.
pub struct ConsumptionReport {
  priv mode : MatchMode
  priv used : Array[Bool]
}

///|
/// Snapshot after completed synchronous operations or after async cleanup has finished.
pub fn Session::report(self : Session) -> ConsumptionReport {
  { mode: self.mode, used: self.used.copy(), }
}

///|
pub fn ConsumptionReport::consumed_indices(
  self : ConsumptionReport,
) -> Array[Int32] {
  let indices = []
  for i, used in self.used {
    if used {
      indices.push(i)
    }
  }
  indices
}

///|
pub fn ConsumptionReport::remaining_indices(
  self : ConsumptionReport,
) -> Array[Int32] {
  let indices = []
  for i, used in self.used {
    if !used {
      indices.push(i)
    }
  }
  indices
}

///|
/// JSON contains only the matching mode and recorded indices; no HTTP values.
pub fn ConsumptionReport::render_json(self : ConsumptionReport) -> String {
  let value : Json = {
    "schema": 1,
    "mode": match self.mode {
      Ordered => "ordered"
      ByRequest => "by_request"
      PerRequest => "per_request"
    },
    "total": self.used.length(),
    "consumed": self.consumed_indices(),
    "remaining": self.remaining_indices(),
  }
  value.stringify()
}
