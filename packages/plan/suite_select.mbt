///|
// ASCII case names, h < 2147483647; the intermediate fits Int64 on every target.
fn suite_shard(name : String, count : Int32) -> Int32 {
  let mut hash = 0L
  for c in name.iter() {
    hash = (hash * 131L + c.to_int().to_int64()) % 2147483647L
  }
  (hash % count.to_int64()).to_int()
}

///|
/// Select from the current subset, preserving manifest order. Empty names means all current cases.
/// Optional sharding uses zero-based indices and a stable name hash; empty shards are explicit.
pub fn SuiteManifest::select(
  self : SuiteManifest,
  names~ : Array[String] = [],
  shard_index? : Int32,
  shard_count? : Int32,
) -> SuiteManifest raise @replay.ReplayError {
  let shard = match (shard_index, shard_count) {
    (None, None) => None
    (Some(index), Some(count)) if count >= 1 &&
      count <= 1024 &&
      index >= 0 &&
      index < count => Some((index, count))
    _ =>
      suite_fail(
        "invalid_shard", "$selection.shard", "provide both shard_index and shard_count; count must be 1-1024 and index must be zero-based within it",
      )
  }
  let available : Map[String, Bool] = Map([])
  for spec in self.specs {
    available.set(spec.name, true)
  }
  let chosen : Map[String, Bool] = Map([])
  for i, name in names {
    if chosen.get(name) is Some(_) {
      suite_fail(
        "duplicate_selection",
        "$selection.names[\{i}]",
        "selected case names must be unique",
      )
    }
    if available.get(name) is None {
      suite_fail(
        "unknown_case",
        "$selection.names[\{i}]",
        "selected case is absent from the current manifest subset",
      )
    }
    chosen.set(name, true)
  }
  let specs = self.specs.filter(spec => {
    let in_shard = match shard {
      None => true
      Some((index, count)) => suite_shard(spec.name, count) == index
    }
    (names.is_empty() || chosen.get(spec.name) is Some(_)) && in_shard
  })
  { source: self.source, specs, all_names: self.all_names, shard, }
}

///|
/// Final membership relative to the original source, never HTTP paths or values.
pub fn SuiteManifest::selection_json(self : SuiteManifest) -> Json {
  let names = self.names()
  let selected : Map[String, Bool] = Map([])
  for name in names {
    selected.set(name, true)
  }
  let excluded = self.all_names.filter(name => selected.get(name) is None)
  let shard : Json = match self.shard {
    None => Json::null()
    Some((index, count)) =>
      { "index": index, "count": count, "algorithm": "poly131-v1" }
  }
  {
    "schema": 1,
    "total": self.all_names.length(),
    "selected": names,
    "excluded": excluded,
    "shard": shard,
  }
}
