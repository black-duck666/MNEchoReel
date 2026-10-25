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
| Wasm | 34 passed | Identity/gzip HAR CLI, review, branch demo, SDK and rejection plans passed |
| Wasm-GC | 29 passed | Identity/gzip HAR CLI, review, branch demo and rejection plans passed; five async tests skipped by Moon |
| JavaScript / Node.js | 34 passed | Identity/gzip HAR CLI, review, branch demo, SDK and rejection plans passed |

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
