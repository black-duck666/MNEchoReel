///|
test "response chunks roundtrip all bytes at boundary lengths and stay at EOF" {
  for length in 0..<=256 {
    let bytes = Bytes::makei(length, i => i.to_byte())
    for size in [1, 2, 3, 7, 256, 2147483647] {
      let stream = MemoryBody::{ body: bytes, offset: 0, chunk_bytes: size, }
      let output = Buffer()
      let mut count = 0
      while stream.next_chunk() is Some(chunk) {
        assert_true(chunk.length() > 0 && chunk.length() <= size)
        output.write_bytes(chunk)
        count += 1
      }
      assert_eq(output.to_bytes(), bytes)
      assert_eq(count, if length == 0 { 0 } else { 1 + (length - 1) / size })
      assert_eq(stream.next_chunk(), None)
      assert_eq(stream.next_chunk(), None)
    }
  }
}

///|
test "closing a partially read chunk body releases it and cannot resume" {
  let stream = MemoryBody::{ body: b"abcd", offset: 0, chunk_bytes: 1, }
  assert_eq(stream.next_chunk(), Some(b"a"))
  let body : &@http.BodyStream = stream
  body.close()
  body.close()
  assert_eq(stream.body, b"")
  assert_eq(stream.next_chunk(), None)
}
