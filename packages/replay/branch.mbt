///|
/// Fork the current consumption state; future take/reset calls are independent.
pub fn Session::fork(self : Session) -> Session {
  { cassette: self.cassette, used: self.used.copy(), mode: self.mode, }
}

///|
fn Session::restore(self : Session, snapshot : Array[Bool]) -> Unit {
  for i in 0..<self.used.length() {
    self.used[i] = snapshot[i]
  }
}

///|
/// Commit consumption on success, restore it on a raised error (including nested calls).
/// Only session state is rolled back. The callback must not use this session concurrently.
pub fn[T] Session::transaction(
  self : Session,
  action : (Session) -> T raise,
) -> T raise {
  let snapshot = self.used.copy()
  errdefer self.restore(snapshot)
  action(self)
}

///|
/// Async counterpart for SDK workflows. Does not roll back external I/O or side effects.
/// Keep the parent session exclusive until the callback finishes; fork for parallel tests.
pub async fn[T] Session::transaction_async(
  self : Session,
  action : async (Session) -> T,
) -> T {
  let snapshot = self.used.copy()
  errdefer self.restore(snapshot)
  action(self)
}
