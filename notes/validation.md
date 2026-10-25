# Validation record

Tested 2026-10-25 on Windows with stable MoonBit:

```text
moon 0.1.20261023 (3778465 2026-10-23)
moonc v0.10.17+d971670cd (2026-10-23)
moonrun 0.1.20261023 (3778465 2026-10-23)
```

The three binaries match the SHA-256 values in the official stable
[Windows checksum manifest](https://cli.moonbitlang.com/binaries/latest/moonbit-windows-x86_64.sha256)
retrieved on the test date. `moon.mod` / `moon.pkg` are parsed and formatted by
that toolchain, including `pkgtype(kind: "executable")`.

`moon check --target all --deny-warn` passed. Portable runtime verification
executes unit tests, the real capture file workflow, negative CLI plans and
the SDK example where supported. CI performs native execution, not just native
type checking, on Linux, macOS and Windows.

| Local runtime | Unit tests | End-to-end result |
| --- | --- | --- |
| Wasm | 77 passed | Identity/gzip HAR CLI, review, branch demo, SDK and rejection plans passed |
| Wasm-GC | 72 passed | Identity/gzip HAR CLI, review, branch demo and rejection plans passed; five async tests skipped by Moon |
| JavaScript / Node.js | 77 passed | Identity/gzip HAR CLI, review, branch demo, SDK and rejection plans passed |

`moon fmt --check`, explicit formatting checks for both `.mbtx` tools, and
`moon info --target all` also passed. Generated interfaces are committed.

Local Windows native execution is unavailable because this machine has no
MSVC C++ Build Tools/Windows SDK. A MinGW clang driver is not accepted by the
current Windows native backend. Attempts to fetch the current Linux toolchain
for WSL failed due to DNS/download failures. No local native runtime success is
claimed. Native CI must succeed before treating native execution as verified.

Wasm-GC's Moon test runner skips `async test` blocks. Its results cover the
synchronous core, synchronous adapter rejection path and file CLI. Async
send/send_stream and SDK behavior are exercised by Wasm, JavaScript and native
jobs; no streaming scheduling semantics are claimed.

Reproducible verification commands are in the root README. `tools/verify.mbtx`
runs strict checks, unit tests, the real capture CLI, the SDK example where
supported, and negative CLI plans. It verifies nonzero exit codes and
diagnostic categories. Tests include byte/base64 roundtrips over lengths 0–256,
all truncated prefixes of a valid HAR, duplicate keys, invalid Unicode escapes,
resource boundaries, repeated headers, source preservation, deterministic
sessions, ambiguous requests, recovery, reset and state isolation.

## Subsequent capabilities

The expanded portable test suite below was rerun on 2026-10-26 (Asia/Taipei)
with the same verified toolchain. Native runtime and XML parser results come
from the linked GitHub Actions runs rather than local Windows execution.

The same CI matrix now executes response expectations, bounded LCS fixture
review, audited decoded-content adaptation, and fork/transaction workflows.
The gzip fixture is a second real capture (1426 encoded / 6228 decoded bytes),
with provenance in `examples/provenance.md`. Negative plans verify failures as
well as successful playback. JSON report tests check nullable scalar fields,
deterministic output and omission of response secrets.

Transaction tests cover original-error propagation, successful return values,
all consumption prefixes, independent resets, nested rollback and async SDK
failures. A queue-synchronized cancellation test waits for actual consumption,
cancels the structured child workflow, then checks restored state after cleanup;
it uses no timing assumptions. Wasm-GC skips async tests; its synchronous branch
demo and transaction tests still execute.

JSON field assertions run against the real GitHub fixture in the CLI on every
target. Focused tests cover escaped/empty pointers, absent versus null,
ordered arrays, reordered object members, IDs beyond Double precision,
numeric spelling, malformed UTF-8/JSON, duplicate keys, depth/count/text limits,
nonconsumption after failure and recovery through raw replay.

Reusable plans execute through the same CLI path. Tests verify whole-plan and
completion rollback, partial composition, repeated independent execution,
caller-array isolation, supplied matching modes, every truncated manifest prefix,
late invalid steps and parser limits. E2E checks exact CLI exit codes and ensures
failed plans emit no success lines from rolled-back earlier steps.

Consumption reports are checked over all masks for zero through eight entries,
including reverse arrival order: sortedness, disjointness, complete partition,
determinism, copied return arrays and frozen snapshots after reset. Additional
tests cover branch isolation and assertion/transaction recovery. End-to-end JSON
reports cover success, whole-plan rollback, malformed input, exact exit codes,
decoded adaptation audit and both flag orders. Duplicate/unknown flags are
rejected. CLI input compilation/expectation validation errors consistently exit 2;
execution mismatches exit 1. Reports contain no HTTP URLs or payload values.

PerRequest tests exhaust all six interleavings of two two-response retry streams,
check header-selected identities, assertion non-skipping, exhaustion, reset,
fork and transactional recovery. Existing Ordered/ByRequest behavior remains
covered. CLI E2E exercises all modes, a real captured Accept header, missing
selected headers and malformed/duplicate mode/header flags.

Reported execution shares the Plan.run engine. Tests cover every failure position
after an existing consumed prefix, completion failures, partial and empty plans,
copied outcomes, stable JSON/XML, exact XML bytes and repeated markup escaping.
A regression test also checks every occurrence of repeated JSON pointer escapes.
CLI tests create success/failure JUnit artifacts, preserve existing output bytes,
reject malformed flags, and create no report for preflight errors. Linux CI runs
xmllint on both generated XML files; every runtime job uploads the two artifacts.
The failure artifact is an intentional negative test, not a failed CI job.

Prepared request manifests run against both real captures on every target.
Tests check deterministic export, unmodified source and consumption state,
UTF-8 BOM/Unicode/escapes, ordered duplicate headers, empty recordings and all
256 response byte values. Generated plans parse and execute through the public
plan API. Existing outputs are rejected without modifying their bytes.

Match explanations follow actual Ordered/ByRequest/PerRequest behavior through
a fork, including ambiguity, exhausted records, empty recordings and matched
indices. Tests verify complete field differences without secret values, bounded
stable ranking, nested-array/JSON isolation, scalar nulls and unchanged sessions.
Plan/CLI tests distinguish failure-point snapshots from rolled-back final state,
and retain default behavior and output when explanation is not requested.

Suite tests cover continued execution after failure, fresh-session isolation,
unique stable CI identities, inclusive case/check budgets, empty library suites,
and deterministic aggregate JSON/XML. The real two-capture suite runs on every
target; E2E tests verify decoded audits, mixed failed/passing cases, failure-point
explanations, preflight rejection, preserved outputs and no partial report on
input errors. Linux CI validates both suite XML samples with xmllint. Original
single-plan JUnit bytes remain covered by the existing exact-output regression.

JSON presence guards distinguish null from missing, enforce canonical array
indices, reject contradictory configuration and share the combined assertion
budget. Tests cover malformed bodies, copied caller arrays and nonconsumption.
The real request plan now checks required owner fields and absent access_token;
CLI rejection tests exercise both failed guards and malformed list types.

Scoped JSON review tests cover large IDs, object order, arrays, absent/null,
request insertion alignment, copied reports, option limits and invalid bodies
even when unaligned or byte-identical. CLI tests mutate a copy of the real
fixture, update byte-length declarations and distinguish untracked versus
tracked field changes. Decoded review reports retain both adaptation audits.

Suite manifest tests use counted in-memory readers to verify one read per exact
path, fresh later loads, original reader-error propagation, source/name isolation
and preflight-before-I/O. Inclusive input budgets charge shared units once and
distinct HAR variants separately. A selected-header regression proves shared
snapshots do not merge different matchers. The CLI delegates to the same API.
