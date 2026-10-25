# EchoReel · 拾响

把完整的 HTTP 交互记录变成可重复执行的 MoonBit 离线回归测试。
面向维护 API 客户端、SDK 与 HTTP 业务流程的开发者：提交经过净化的 HAR，
向应用注入 replay transport，断言业务结果，并检查每次预期调用都已发生。
测试无需 API 密钥，也不会在未命中时联网。

## 运行真实示例

需要当前稳定版 [MoonBit](https://www.moonbitlang.com/download/)。
已核对 2026-10-23 稳定工具链；JavaScript 使用 Node.js 22。

```sh
moon update
moon run packages/check -- examples/repository.har examples/repository.requests.json
moon run packages/demo -- examples/repository.har
```

预期结果：

```text
0: status=200 bytes=6228
all 1 recorded exchanges consumed
offline SDK result: moonbitlang/core; all interactions verified
```

夹具来自 MoonBit 官方仓库的真实公开 GitHub API 响应，获取方式与数据边界见
[provenance](examples/provenance.md)。两条演示命令在依赖安装完成后可断网运行。

## 在自己的测试中采用

目前提供源码仓库，尚未发布到 Mooncakes。导入包分别为
`black-duck666/mnechoreel/replay` 与 `black-duck666/mnechoreel/transport`。
由调用方读取 HAR 字符串，核心库不依赖文件系统或网络。

```moonbit
let cassette = @replay.compile_har(har_text, match_headers=["Accept"])
let session = cassette.session()
let response = session.take(@replay.Request::new(
  "GET", "https://api.example.com/items", headers=[("Accept", "application/json")],
))
assert_eq(response.status(), 200)
session.finish()
```

SDK 接入只需将 `@transport.ReplayTransport::new(session)` 作为
`&@http.Transport` 传给接受 [gaato/http](https://mooncakes.io/docs/gaato/http)
的客户端；[demo](packages/demo/main.mbt) 执行业务函数并断言真实返回字段。
响应头保留重复值与顺序。`send_stream` 返回有限内存正文，读取一次后结束；
关闭后继续读取返回 `None`。它不模拟网络分块、延时、背压或取消。

`Cassette` 可复用，`session()` 的消费状态相互独立。默认 `Ordered` 按录制顺序
匹配，支持同一请求先 429 后 200 的重试回归。`session(mode=ByRequest)`
允许不同路径乱序调用；若多个匹配记录返回不同响应，则拒绝歧义。
等价的重复记录按原序消费。`remaining()` 查询剩余量，`reset()` 显式重置。
`finish()` 用于断言没有遗漏调用。

请求身份是精确方法、完整 URL、正文 bytes 和显式选择的请求头。
头名称忽略 ASCII 大小写，重复值的顺序参与匹配；不规范化 URL/query/body。
默认不比较请求头，使用 `match_headers` 选择影响业务结果的头。
失败通过 `ReplayError(Diagnostic)` 返回 `code/path/message`，不消费记录，
可修正请求后继续。诊断不回显请求值、正文、令牌或 URL。

## 首版接受的记录

- HAR 1.2，自包含、已净化、完整嵌入正文的有限 HTTP(S) 交互。
- 请求正文是 `postData.text` 的 UTF-8 bytes；无正文请求需 `bodySize=0`。
- 响应正文是 UTF-8 文本或严格、带 padding 的 canonical base64。
- 最终状态 200–599；HEAD、204、304 强制空正文。
- 正文长度与可用的长度声明一致；HEAD/304 的 Content-Length 可描述原表示。
- 原始输入字符串完整保存在 `Cassette.source()`，不会输出有损重写后的 HAR。

拒绝缺失正文、params/form 文件重建、multipart、SSE、Upgrade/CONNECT/TRACE、
压缩或 Transfer-Encoding、非 UTF-8 charset、非法 URL authority、重复 JSON key、
未知重放字段及超限输入。不会静默删除头、猜测字节、跳过交互或降级联网。
响应编码/传输头必须与重建正文一致；首版不能直接接受大部分含压缩头的浏览器 HAR。
请采集 identity 响应，不要盲目删除头来绕过校验。
仅用于元数据的顶层/log 扩展保留在原文中；交互对象内的未知字段保守拒绝。
接受的浏览器元数据扩展仅 `_initiator`、`_priority`、`_resourceType`。
Cookie/redirect 元数据不能替代缺失的 Cookie、Set-Cookie、Location 头。

默认上限：输入 16,777,216 个 UTF-16 code units、10,000 次交互、每条请求或
响应正文 4,194,304 bytes、JSON 深度 64。`compile_har` 的三个上限可配置；
这些是接受上限，不是进程内存配额。解析会保留原文与编译结果。

## 请求清单与命令行

清单是数组，每项支持 `method`、`url`、可选 UTF-8 `body`、有序
`headers: [{"name":"Accept","value":"application/json"}]`、可选 `expect_status`。
未知字段和类型错误会拒绝整个计划。命令按顺序执行并检查全部消费。
退出码：0 成功，1 回放诊断，2 清单/输入/状态断言错误。诊断输出到 stdout。
CLI 默认不按头匹配；需要自定义头身份时使用库的 `match_headers`。

## 验证与布局

```sh
moon fmt --check
moon fmt --check tools/import_capture.mbtx tools/verify.mbtx
moon info --target all
moon run tools/verify.mbtx wasm
moon run tools/verify.mbtx wasm-gc
moon run tools/verify.mbtx js
moon run tools/verify.mbtx native
```

`packages/replay` 持有记录编译、匹配、消费与诊断；`packages/transport` 是 SDK
适配；`packages/check` 与 `packages/demo` 承担文件工作流。`examples` 保存真实
记录与来源，`tools` 保存 MoonBit 自动化，`notes` 记录契约和验证边界。
CI 在 Ubuntu 执行三个可移植目标，在 Linux/macOS/Windows 执行原生测试与示例；
Windows native 需要 MSVC C++ Build Tools 与 Windows SDK。
Moon 当前跳过 Wasm-GC 的 async tests，因此该目标验证核心与同步适配路径及 CLI；
异步 transport 与 SDK 示例由 Wasm、JS、native 执行。
实际结果见 [validation](notes/validation.md)。

## 能力边界与后续

当前已实现：完整 HAR 导入、严格请求匹配、独立消费状态、有限正文 transport、
可执行诊断、状态断言 CLI、真实数据 SDK 示例。

后续按能力推进：显式记录每项修改的 decoded-body 头适配；夹具更新时的实质差异
审查；更多可以完整还原的请求正文 profile。录制代理、自动脱敏、OpenAPI 校验和
通用 HTTP 客户端不在边界内。详细场景见 [contract](notes/contract.md)，生态定位与
复用来源见 [sources](notes/sources.md)。

MIT，见 [LICENSE](LICENSE)。
