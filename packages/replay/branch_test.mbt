///|
suberror WorkflowFailure {
  WorkflowFailure(String)
}

///|
test "transaction commits its result or restores all consumption on the original error" {
  let session = @replay.compile_har(fixture([entry(), entry()])).session()
  let request = @replay.Request::new("GET", "https://example.invalid/a")
  try
    session.transaction(fn(s) -> Unit raise {
      ignore(s.take(request))
      raise WorkflowFailure("business validation failed")
    })
  catch {
    WorkflowFailure(message) => assert_eq(message, "business validation failed")
    _ => fail("transaction replaced the original error")
  } noraise {
    _ => fail("expected business failure")
  }
  assert_eq(session.remaining(), 2)
  let value = session.transaction(s => {
    ignore(s.take(request))
    ignore(s.take(request))
    s.finish()
    42
  })
  assert_eq(value, 42)
  session.finish()
}

///|
test "nested rollback restores prior consumption even after reset and successful inner calls" {
  let session = @replay.compile_har(fixture([entry(), entry(), entry()])).session()
  let request = @replay.Request::new("GET", "https://example.invalid/a")
  ignore(session.take(request))
  try
    session.transaction(fn(s) -> Unit raise {
      s.reset()
      s.transaction(inner => {
        ignore(inner.take(request))
        ignore(inner.take(request))
      })
      raise WorkflowFailure("outer failed")
    })
  catch {
    WorkflowFailure(_) => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected rollback")
  }
  assert_eq(session.remaining(), 2)
  session.transaction(s => {
    ignore(s.take(request))
    try
      s.transaction(inner => {
        ignore(inner.take(request))
        ignore(
          inner.take(@replay.Request::new("GET", "https://wrong.invalid/")),
        )
      })
    catch {
      @replay.ReplayError(_) => ()
      _ => fail("unexpected inner error")
    } noraise {
      _ => fail("expected inner rejection")
    }
    assert_eq(s.remaining(), 1)
    ignore(s.take(request))
  })
  session.finish()
}

///|
test "fork snapshots every consumption prefix and retains ByRequest mode" {
  let cassette = @replay.compile_har(
    fixture([entry(), entry(), entry(), entry()]),
  )
  let request = @replay.Request::new("GET", "https://example.invalid/a")
  for prefix in 0..<=4 {
    let parent = cassette.session(mode=ByRequest)
    for _ in 0..<prefix {
      ignore(parent.take(request))
    }
    let child = parent.fork()
    assert_eq(child.remaining(), 4 - prefix)
    for _ in prefix..<4 {
      ignore(child.take(request))
    }
    child.finish()
    assert_eq(parent.remaining(), 4 - prefix)
    child.reset()
    assert_eq(child.remaining(), 4)
    assert_eq(parent.remaining(), 4 - prefix)
  }
  let out_of_order = @replay.compile_har(fixture([named("a"), named("b")]))
    .session(mode=ByRequest)
    .fork()
  ignore(
    out_of_order.take(@replay.Request::new("GET", "https://example.invalid/b")),
  )
  ignore(
    out_of_order.take(@replay.Request::new("GET", "https://example.invalid/a")),
  )
  out_of_order.finish()
}
