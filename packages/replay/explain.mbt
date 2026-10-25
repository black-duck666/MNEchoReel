///|
/// Field names only: method, url, body, selected_headers. Never includes HTTP values.
pub(all) struct MatchCandidate {
  entry_index : Int32
  consumed : Bool
  differences : Array[String]
}

///|
pub struct MatchReport {
  priv mode : MatchMode
  priv outcome : String
  priv matched_index : Int32?
  priv next_index : Int32?
  priv remaining : Int32
  priv total : Int32
  priv candidates : Array[MatchCandidate]
}

///|
fn mode_name(mode : MatchMode) -> String {
  match mode {
    Ordered => "ordered"
    ByRequest => "by_request"
    PerRequest => "per_request"
  }
}

///|
fn candidate_before(a : MatchCandidate, b : MatchCandidate) -> Bool {
  if a.differences.length() != b.differences.length() {
    return a.differences.length() < b.differences.length()
  }
  if a.consumed != b.consumed {
    return !a.consumed
  }
  a.entry_index < b.entry_index
}

///|
/// Read-only probe of actual matching semantics, followed by bounded nearest-field ranking.
/// Candidates do not authorize fuzzy matching or predict response expectations.
pub fn Session::explain(
  self : Session,
  request : Request,
  max_candidates~ : Int32 = 5,
) -> MatchReport raise ReplayError {
  if max_candidates < 0 || max_candidates > 100 {
    fail(
      "invalid_limit", "$explain", "max_candidates must be between 0 and 100",
    )
  }
  let trial = self.fork()
  let mut outcome = "matched"
  try trial.take(request) catch {
    ReplayError(d) => outcome = d.code
  } noraise {
    _ => ()
  }
  let mut matched_index = None
  let mut next_index = None
  let candidates : Array[MatchCandidate] = []
  for i, exchange in self.cassette.exchanges {
    if !self.used[i] && next_index == None && self.mode == Ordered {
      next_index = Some(i)
    }
    if !self.used[i] && trial.used[i] {
      matched_index = Some(i)
    }
    if max_candidates == 0 {
      continue
    }
    let differences = []
    if exchange.request.http_method != request.http_method {
      differences.push("method")
    }
    if exchange.request.url != request.url {
      differences.push("url")
    }
    if exchange.request.body != request.body {
      differences.push("body")
    }
    if self.cassette.header_names
      .iter()
      .any(name => {
        selected(exchange.request.headers, name) !=
        selected(request.headers, name)
      }) {
      differences.push("selected_headers")
    }
    let candidate = MatchCandidate::{
      entry_index: i,
      consumed: self.used[i],
      differences,
    }
    let mut position = candidates.length()
    for j, other in candidates {
      if candidate_before(candidate, other) {
        position = j
        break
      }
    }
    if position < max_candidates {
      candidates.insert(position, candidate)
      if candidates.length() > max_candidates {
        ignore(candidates.pop())
      }
    }
  }
  {
    mode: self.mode,
    outcome,
    matched_index,
    next_index,
    remaining: self.remaining(),
    total: self.used.length(),
    candidates,
  }
}

///|
pub fn MatchReport::outcome(self : MatchReport) -> String {
  self.outcome
}

///|
pub fn MatchReport::matched_index(self : MatchReport) -> Int32? {
  self.matched_index
}

///|
pub fn MatchReport::candidates(self : MatchReport) -> Array[MatchCandidate] {
  self.candidates.map(c => {
    entry_index: c.entry_index,
    consumed: c.consumed,
    differences: c.differences.copy(),
  })
}

///|
pub fn MatchReport::to_json(self : MatchReport) -> Json {
  let matched_index : Json = match self.matched_index {
    None => Json::null()
    Some(i) => Json(i)
  }
  let next_index : Json = match self.next_index {
    None => Json::null()
    Some(i) => Json(i)
  }
  let candidates = self.candidates.map(c => {
    let value : Json = {
      "entry_index": c.entry_index,
      "consumed": c.consumed,
      "differences": c.differences,
    }
    value
  })
  {
    "schema": 1,
    "mode": mode_name(self.mode),
    "outcome": self.outcome,
    "matched_index": matched_index,
    "next_ordered_index": next_index,
    "remaining": self.remaining,
    "total": self.total,
    "truncated": self.candidates.length() < self.total,
    "candidates": candidates,
  }
}

///|
pub fn MatchReport::render_json(self : MatchReport) -> String {
  self.to_json().stringify()
}
