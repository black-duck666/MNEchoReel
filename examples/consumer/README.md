# Consume EchoReel from a separate module

This is a private example module, not another library release. Its `moon.mod`
declares the real public module dependency and `moon.pkg` imports only exported
packages. The local `moon.work` resolves the repository root as that dependency;
it does not download an unpublished EchoReel version from Mooncakes.

From the repository root:

```sh
moon -C examples/consumer run . --target wasm -- ../repository.har ../repository.requests.json
moon -C examples/consumer run sdk --target wasm -- ../repository.har
```

The first command verifies a request plan, derives header/JSON contracts and
runs an independent suite through the public API. It also runs on Wasm-GC, JS
and native. The SDK command compiles and uses the public gaato/http Transport
implementation with bounded input and chunked output; it runs on Wasm, JS and
native. Both use the unchanged real capture and require no network after the
toolchain and external dependencies are available.

To use the source in your own app, put your app and the EchoReel checkout in
one `moon.work` members list, add `black-duck666/mnechoreel@0.1.0` to your
app's `moon.mod`, and import replay/plan/transport in its `moon.pkg` as needed.
Keep the external dependency versions consistent with EchoReel's `moon.mod`.
Member paths are relative to `moon.work`; this checked-in example uses `../..`.

MIT, as specified in the repository LICENSE. Workspace behavior is documented
in the [official module tour](https://tour.moonbitlang.com/basics/module-and-package/index.html).
