///|
test "request plans validate presence-list types before constructing expectations" {
  let prefix = "[{\"method\":\"GET\",\"url\":\"https://example.invalid/a\","
  assert_eq(
    @plan.parse_plan(
      prefix +
      "\"expect_json_present\":[\"/owner\"],\"expect_json_absent\":[\"/token\"]}]",
    ).length(),
    1,
  )
  for
    field in [
      "\"expect_json_present\":\"/owner\"", "\"expect_json_present\":[1]", "\"expect_json_absent\":null",
    ] {
    try @plan.parse_plan(prefix + field + "}]") catch {
      @replay.ReplayError(d) => {
        assert_eq(d.code, "manifest_error")
        assert_true(d.path.has_prefix("$[0].expect_json_"))
      }
    } noraise {
      _ => fail("malformed presence list accepted")
    }
  }
}
