# Changelog

## 0.1.0 — initial source baseline

This version is available as source; it has not been published to Mooncakes.

- Compile complete sanitized HAR 1.2 captures into offline HTTP regression tests,
  with strict request identities, explicit decoded-content audits and bounded inputs.
- Replay ordered workflows, independent request identities and per-request retry
  sequences; fork sessions and roll back multi-call failures atomically.
- Assert response status, ordered headers, exact bytes and selected JSON values
  or presence; derive editable request plans and contracts from recordings.
- Review recording changes with deterministic request alignment and explicit JSON
  comparison scope, without printing HTTP values in matching diagnostics.
- Run reusable plans and isolated suites with JSON/JUnit reports, named selection,
  stable CI sharding, input snapshots and complete-consumption checks.
- Inject gaato/http Transport into SDKs, optionally chunk finite responses and
  materialize request streams with byte/chunk budgets and cleanup on cancellation.
- Exercise real captures, public APIs from a separate consumer module, and the
  extracted source distribution in the CI target/OS matrix.

The accepted profiles, exclusions and verification limits are documented in
[the initial delivery guide](notes/initial-release.md), [contract](notes/contract.md)
and [validation record](notes/validation.md). No registry release or performance
claim is implied by this source version.
