# EchoReel · 拾响

把完整的 HTTP 交互记录变成可重复执行的 MoonBit 离线回归测试。
面向维护 API 客户端、SDK 与 HTTP 业务流程的开发者：提交经过净化的 HAR，
向应用注入 replay transport，断言业务结果，并检查每次预期调用都已发生。
测试无需 API 密钥，也不会在未命中时联网。

本轮以 0.1.0 源码初版收口。完整验收步骤、分发方式和范围边界见
[初版交付](notes/initial-release.md)，已实现能力见 [CHANGELOG](CHANGELOG.md)。

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

已提供[独立消费模块](examples/consumer/README.md)，使用当前工具链的 `moon.work`
从源码解析真实模块依赖；无需先发布本项目，也无需把代码复制到应用包中：

```sh
moon -C examples/consumer run . --target wasm -- ../repository.har ../repository.requests.json
moon -C examples/consumer run sdk --target wasm -- ../repository.har
```

在自己的 workspace 中，将应用和本仓库加入 members，在应用 moon.mod 声明
`black-duck666/mnechoreel@0.1.0`，再按需导入 replay、plan、transport。工作区会使用
本地成员源码；版本号不表示已发布到 Mooncakes。完整配置见消费模块的 moon.mod/moon.pkg/moon.work。

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
响应头保留重复值与顺序。`send_stream` 默认返回有限内存正文，读取一次后结束；
关闭后继续读取返回 `None`。它不模拟网络分块、延时、背压或取消。

`Cassette` 可复用，`session()` 的消费状态相互独立。默认 `Ordered` 按录制顺序
匹配，支持同一请求先 429 后 200 的重试回归。`session(mode=ByRequest)`
允许不同路径乱序调用；若多个匹配记录返回不同响应，则拒绝歧义。
等价的重复记录按原序消费。`remaining()` 查询剩余量，`reset()` 显式重置。
`finish()` 用于断言没有遗漏调用。

### 定位请求漂移

`session.explain(request)` 只读地探测实际匹配结果，并返回最接近的记录索引和
差异字段 method/url/body/selected_headers。报告不包含 HTTP 值，不消费或重置 session，
不改变匹配规则，也不执行响应断言。可用 matched_index() 观察实际会消费哪项；
Ordered 另给出 next_ordered_index，帮助区别“后面有相同请求”和“现在允许消费”。

候选按差异字段数量、未消费优先、原索引排序；已消费项仍可用于定位重复调用。
默认保留 5 项，max_candidates 可设 0–100，始终扫描全部记录并标明截断情况。
候选并不表示允许模糊匹配。candidates() 返回嵌套数组副本，to_json()/render_json()
提供确定性快照，之后的回放或修改返回值不影响报告。

```sh
moon run packages/check -- examples/repository.har examples/repository.requests.json --explain
```

--explain 隐含 JSON 报告模式；仅在请求未命中、顺序不符或歧义时加入候选解释，
成功及响应断言失败时 explanation 为 null。库使用 plan.verify(session,
explain_mismatches=true)，并读取 report.explanation()。解释快照来自失败发生时，
可能包含此前通过但随后回滚的消费；外层 consumption 仍反映原子回滚后的有效状态。

### 精确响应断言

`Expectation::new(status=200, body=b"ok", headers=[("Set-Cookie", ["a=1", "b=2"])])`
可以选择检查状态、完整正文 bytes 和指定头的全部有序值；空值列表断言该头不存在。
`session.take_checked(request, expected)` 将请求匹配、响应断言和消费合并为一次原子操作：
任意断言失败都不消费记录。也可用 `expected.check(response)` 检查已取得的响应。
重复的断言头名称会拒绝，构造时复制嵌套数组。诊断只标识字段，不输出实际值。

JSON API 响应可按业务字段断言，避免把易变时间戳写进整段正文期望：
`Expectation::new(json=[("/full_name", "\"moonbitlang/core\""), ("/private", "false")])`。
每项是 RFC 6901 字符串形式的 pointer 和一个 JSON 文本值；空 pointer 检查根值，
`~0` / `~1` 分别表示 `~` / `/`，数组只接受无前导零的非负索引，不接受 `-` 或 URI fragment。
对象忽略成员顺序，数组保持顺序；数字采用原始 token 精确比较（`1` 与 `1.0` 不相等），
防止超过 Double 精度的 ID 被误判相同。缺失与 null 不相等，不执行类型转换或 schema 校验。
正文必须是严格 UTF-8 JSON，无重复 key，深度不超过 64；选择器最多 64 段、4096 UTF-16 units，
最多 256 项，每个期望 JSON 文本最多 1,048,576 units。失败不消费，诊断不打印 pointer 或值。
真实 GitHub 请求清单已经使用 `/full_name`、`/private`、`/owner/login` 验证业务字段。

可用 `Expectation::new(json_present=["/owner"], json_absent=["/access_token"])`
检查字段是否存在，适合验证必要业务字段和不应返回的凭据字段。null 算作存在，缺失父对象
算作路径不存在；数组索引必须是规范非负十进制，非法索引不会被当成“字段不存在”而通过。
三类 JSON 检查合计最多 256 项，同一路径的 absent 与 present/精确值断言互斥。
清单使用 `expect_json_present` / `expect_json_absent` 字符串数组；单独使用缺失断言也要求
完整、合法的 UTF-8 JSON 正文。失败不消费记录，诊断不回显路径内容或实际值。

请求身份是精确方法、完整 URL、正文 bytes 和显式选择的请求头。
头名称忽略 ASCII 大小写，重复值的顺序参与匹配；不规范化 URL/query/body。
默认不比较请求头，使用 `match_headers` 选择影响业务结果的头。
失败通过 `ReplayError(Diagnostic)` 返回 `code/path/message`，不消费记录，
可修正请求后继续。诊断不回显请求值、正文、令牌或 URL。

### 多调用试验与分支

```sh
moon run packages/branch_demo -- examples/repository.har
```

`session.fork()` 复制当前消费位置和匹配模式，子分支与父分支的 take/reset 不互相
影响。适用于同一夹具上验证不同业务路径。`session.transaction(s => { ... })`
将多次消费作为一组：回调成功保留状态并返回结果，抛错则恢复进入回调前的全部消费
位置，并原样传播错误。可嵌套；回调中的 reset 也包含在回滚范围内。

SDK 异步流程使用 `transaction_async(async fn(s) { ... })`。通过 `errdefer`
恢复状态，测试覆盖业务异常、transport 失败和取消后的清理完成。事务期间必须
独占该 session；并行测试使用 fork。它不撤销外部 I/O、响应对象或其他副作用，
不处理进程 abort/崩溃，也不承诺共享 session 的并发同步。

## 首版接受的记录

- HAR 1.2，自包含、已净化、完整嵌入正文的有限 HTTP(S) 交互。
- 请求正文是 `postData.text` 的 UTF-8 bytes；无正文请求需 `bodySize=0`。
- 响应正文是 UTF-8 文本或严格、带 padding 的 canonical base64。
- 最终状态 200–599；HEAD、204、304 强制空正文。
- 正文长度与可用的长度声明一致；HEAD/304 的 Content-Length 可描述原表示。
- 原始输入字符串完整保存在 `Cassette.source()`，不会输出有损重写后的 HAR。

默认 Identity profile 拒绝缺失正文、params/form 文件重建、multipart、SSE、Upgrade/CONNECT/TRACE、
压缩或 Transfer-Encoding、非 UTF-8 charset、非法 URL authority、重复 JSON key、
未知重放字段及超限输入。不会静默删除头、猜测字节、跳过交互或降级联网。
响应编码/传输头必须与重建正文一致。含压缩头的记录需要下述显式适配；不要盲目删除头来绕过校验。
仅用于元数据的顶层/log 扩展保留在原文中；交互对象内的未知字段保守拒绝。
接受的浏览器元数据扩展仅 `_initiator`、`_priority`、`_resourceType`。
Cookie/redirect 元数据不能替代缺失的 Cookie、Set-Cookie、Location 头。

默认上限：输入 16,777,216 个 UTF-16 code units、10,000 次交互、每条请求或
响应正文 4,194,304 bytes、JSON 深度 64。`compile_har` 的三个上限可配置；
这些是接受上限，不是进程内存配额。解析会保留原文与编译结果。

### 显式适配已解码的 HAR 正文

```sh
moon run packages/check -- examples/repository-gzip.har examples/repository.requests.json --decoded
```

库入口为 `compile_har(source, body_profile=DecodedContent)`。HAR 的嵌入正文按格式
约定已经解码，本库不会执行 gzip/br/deflate 解压。显式选择此 profile，表示调用方
确认记录遵循该约定；不能将压缩 wire bytes 放进 text/base64 冒充解码内容。
只适配 gzip、br、deflate（含有序组合），移除 Content-Encoding，并将已有的
Content-Length 改为解码后的 byte 长度，不合成原来不存在的头。

CLI 输出每项修改的 JSON；`cassette.adaptations()` 和 `adaptation_report_json()`
提供原始 entry/header 索引、原值和新值（移除时为 null）。原始 HAR、正文及其余
头保持可追溯，重复头顺序保持。要求已知 encoded bodySize，核对原 Content-Length、
decoded content.size 与可用的 compression 元数据。拒绝 Transfer-Encoding、
HEAD/204/304 的编码适配、范围/摘要/签名元数据、缺失正文和未知编码。
它是有限 SDK 测试的头适配，不承诺还原 wire capture 或支持签名 HTTP 消息。

## 验证 SDK 的跨块读取

`ReplayTransport::new(session).with_response_chunks(7)` 返回共享同一 session 的新适配器，
将 `send_stream` 的正文划分为最多 7 字节的连续块；`send` 仍返回完整正文。块大小必须
为正，非法配置返回 invalid_transport_option，不改变消费状态；原适配器保留原配置。

```sh
moon run packages/stream_demo -- examples/repository.har
```

示例从真实 HAR 分块读取，重组并解析 GitHub JSON，最后检查全部消费。分块不改动
HTTP 头或正文字节，UTF-8 字符可能跨块；EOF 和 close 均终止该流，旧流独立于后续
session reset。请求在取得响应时已消费，提前关闭响应流不会撤销消费。
此选项用于有限录制的客户端读取测试，不模拟传输编码、时序、背压或无限事件流。

### 验证有界的请求流

`transport.with_request_streams(max_bytes=4194304, max_chunks=65536)` 显式开启请求流支持，
同样返回共享 session 的新配置，可与响应分块组合。默认适配器仍在读取前拒绝流；
缓冲请求不受此选项的预算影响。max_bytes 允许 0，max_chunks 必须为正。

每个 `Some(chunk)` 都计入块预算，包括空块；正好达到上限时允许再读一次以确认 EOF，
若仍有数据则拒绝，最多执行 max_chunks+1 次读取。每块在追加前检查字节预算。
声明长度超过预算时不接管或关闭源流，源仍归调用方；接管后的成功、读取错误、长度
不符、超限或取消都会关闭源流。只有完整读取后才按原有方法、URL、头和字节匹配录制。
读取阶段失败不消费 HAR；源一旦接管仍是一次性的，重试需新建源，不能回滚已读输入。
源流原有 HttpError 原样传播；预算限制字节和读取次数，不为单次阻塞读取增加超时。

```sh
moon run packages/upload_demo -- examples/repository.har
```

示例读取满足库上限的单交互、完整 UTF-8 请求 HAR，按其原始请求构造 5 字节输入块并核对完整
响应。现有真实 GitHub 样例是零正文 GET；非空 POST 的往返、取消和恢复由单元测试验证，
CI 还将真实 API JSON 作为正文派生合成 POST 运行相同示例。派生输入不宣称是线上上传录制。

## 请求清单与命令行

从记录生成初始计划，减少手抄 URL、重复请求头和正文：

```sh
moon run packages/prepare -- examples/repository.har requests.generated.json --assert-bodies
moon run packages/check -- examples/repository.har requests.generated.json
```

要锁定响应的媒体类型或缓存契约，可重复指定响应头：

```sh
moon run packages/prepare -- examples/repository.har headers.generated.json --assert-header Content-Type --assert-header X-Optional
moon run packages/check -- examples/repository.har headers.generated.json
```

`--assert-header NAME` 从每个响应生成 `expect_headers`；名称匹配忽略 ASCII 大小写，
值与重复值顺序保持精确，录制中没有该头则生成空数组断言其缺失。未选择的响应头不受约束。
库使用 `request_plan(assert_headers=["Content-Type", "X-Optional"])`；最多 256 个唯一 HTTP
token 名称，重复名称（忽略大小写）、非法名称和超限均拒绝，空记录也预检。
可与 `--assert-bodies`、`--decoded` 组合；decoded 断言使用适配后真正回放的头，完整修改
审计仍保留。摘要额外记录所选头名，不回显响应值；不指定时保持原生成结果和摘要格式。

只锁定稳定业务字段，避免把易变时间戳也冻结在测试中：

```sh
moon run packages/prepare -- examples/repository.har fields.generated.json --assert-json /full_name --assert-json /owner/login
moon run packages/check -- examples/repository.har fields.generated.json
```

库使用 `request_plan(assert_json=["/full_name", "/owner/login"])`。每个响应均需是严格
UTF-8 JSON，所有所选路径都必须存在；`null` 是有效值，缺失、非法数组索引、重复 key、
畸形正文或深度超过 64 会拒绝整个导出。`--assert-json` 可重复，接受空字符串选择根值；
最多 256 个唯一 RFC 6901 字符串 pointer，每个最多 4096 UTF-16 units、64 个 token。
数字保留原 token（包括大整数和小数写法），数组有序，对象成员顺序不影响后续断言。
选定值最多 1,048,576 UTF-16 units、60 层容器，为计划外层保留 4 层；过大或过深时
报 plan_json_limit，可选择更窄的路径。总导出上限仍适用，绝不静默省略断言。
与头断言、完整正文断言及 decoded 组合时同时约束；只选 JSON 时未选业务字段可变化。
摘要仅增加 pointer 配置，不输出实际值；生成文件包含所选值，需按原夹具方式管理。

输出文件需尚不存在，父目录需已存在。prepare 保留方法、完整 URL、全部有序请求头、
精确 UTF-8 请求正文，并为每步加入状态断言；--assert-bodies 额外加入 canonical base64
响应正文断言。生成后可改成业务字段断言。文件包含原记录的 HTTP 数据，请只使用已净化
夹具。stdout 是生成摘要，不回显 HTTP 值；退出 0 成功，2 表示输入/输出/选项错误。
压缩记录需显式 --decoded；摘要包含全部头适配审计。

库方法 `cassette.request_plan(assert_bodies=true)` 返回相同确定性 JSON 清单。它生成
下游测试输入，保留原 HAR 在 source() 中，不改写 HAR，也不导出其计时或其他元数据。
不规范化 URL、头或正文；空记录生成空计划，不消费任何 session。
默认生成上限为 4,194,304 个 UTF-16 units，与 parse_plan 默认输入上限一致；超限拒绝。
较大夹具可在库中同时提高 request_plan / parse_plan 的 max_input_units，CLI 采用默认上限。

清单是数组，每项支持 `method`、`url`、可选 UTF-8 `body`、有序
`headers: [{"name":"Accept","value":"application/json"}]`、可选 `expect_status`、
`expect_body` 或 `expect_body_base64`（互斥），以及
`expect_headers: [{"name":"Content-Type","values":["application/json"]}]`。
`expect_json: [{"pointer":"/private","value":false}]` 使用相同 JSON 字段断言语义。
正文做完整字节比较，base64 必须 canonical 且带 padding。
未知字段和类型错误会拒绝整个计划。命令按顺序执行并检查全部消费。
退出码：0 成功，1 回放或响应断言诊断，2 清单/输入错误。诊断输出到 stdout。
CLI 默认不按头匹配；`--match-header NAME` 可重复选择不同的头，对应库的 `match_headers`。
CLI 头名参数不能以 `--` 开头；此类头名可通过库 API 选择。
`--mode ordered|by-request|per-request` 选择匹配模式，默认 ordered；两项均可与 --report/--decoded 组合。

### 交错调用与独立重试序列

`cassette.session(mode=PerRequest)` 允许不同请求身份之间重排，同时为每个精确身份
逐次返回其原记录顺序的响应。例如 A:429、B:503、A:200、B:201，可重放为
B:503、B:201、A:429、A:200，便于测试独立 API 分支的重试。
URL、方法、正文、选定头仍精确匹配；同身份中永远先取最早未消费项，断言失败不能
跳过该响应。只有业务确实允许跨身份重排时才显式采用此模式；无法分辨身份相同的
并发逻辑调用，需选择区分头或保持 Ordered。ByRequest 仍拒绝同身份不同响应。
fork、reset、事务与计划执行都保留所选模式；它不实现并发同步、重试策略或时间模拟。

```sh
moon run packages/check -- examples/repository.har examples/repository.requests.json --mode per-request --match-header Accept --report
```

### 将清单嵌入自己的测试

导入 `black-duck666/mnechoreel/plan`，调用 `parse_plan(json_text)`；也可用
`Plan::new([(request, expectation), ...])` 从已构造的请求与断言建立计划。
`plan.run(session)` 返回按步骤排列的响应数组，默认在全部步骤结束后检查 `finish()`。
任一步匹配/断言或完成检查失败，整个计划的消费都会回滚到进入前状态；成功才提交。
同一计划可复用于多个独立 session，匹配模式与选定请求头由传入的 session 决定。
需要组合部分计划时显式使用 `require_complete=false`，最后自行 `finish()`。
失败诊断包含 `$plan[步骤]`，不回显请求数据。它只回滚 session 消费，不撤销外部副作用。

解析默认限制输入 4,194,304 个 UTF-16 units、10,000 步、JSON 深度 64；前两项通过
`max_input_units` / `max_steps` 调整。先验证整个清单，拒绝未知字段、重复 JSON key 和
畸形断言；构造器复制调用方步骤数组。CLI 复用同一 API，只在整组成功提交后输出成功行。
`packages/branch_demo` 用真实夹具演示同一库计划在两个独立 session 上执行。

### 保存 CI 消费报告

```sh
moon run packages/check -- examples/repository.har examples/repository.requests.json --report
moon run packages/check -- examples/repository-gzip.har examples/repository.requests.json --decoded --report
```

`--report` 让 stdout 只输出一份 JSON，包含 `schema:1`、`passed`、`diagnostic`、
`consumption` 和 `adaptations`。退出码与普通模式相同。回放失败时记录原子回滚后的
有效消费状态；输入尚未成功编译/验证时消费及适配字段为 null。适配字段包含完整头修改清单。
报告不包含 URL、请求/响应正文或任意原始头值；适配清单仅包含已修改的编码/长度头。

库调用 `session.report()` 获得不可变快照，`consumed_indices()` 与 `remaining_indices()`
返回按 HAR 原始顺序递增的索引副本，`render_json()` 输出稳定 JSON。报告是有效消费状态，
不记录尝试次序，也不能用来恢复 session。分支、reset 或后续消费不修改旧快照。
多调用事务回滚后取新报告即可看到恢复结果；异步操作需等取消清理完成后再取快照。

### 把回归检查交给 CI 展示

```sh
moon run packages/check -- examples/repository.har examples/repository.requests.json --junit replay.xml --report
```

输出路径必须尚不存在；父目录需已存在。CLI 在开始执行前拒绝已有路径，不覆盖夹具或
旧报告；不要让多个进程同时写同一输出路径。计划执行后，无论通过还是回放失败都会
写出 JUnit XML；输入验证失败不创建报告，写入失败退出 2。可与 --report、--decoded、
--mode 和 --match-header 组合。回放失败仍退出 1，CI 不应仅靠报告文件判断成功。

库 API `plan.verify(session)` 与 `run` 共享执行引擎和原子消费语义，返回 `RunReport`。
预期的回放错误进入报告；调用方必须检查 `passed()`，意外错误仍传播。
`outcomes()` 返回各步骤 Passed/Failed/Skipped 的副本，`completion()` 独立记录最终
消费检查（显式关闭时为 None），`diagnostic()` 保留失败类别和步骤位置。
`render_json()` / `render_junit()` 提供确定性报告。

步骤在后续失败前通过，不代表消费已提交；报告的 `committed` 明确给出整组结果。
首次失败后的步骤及尚未执行的完成检查标为 skipped。JUnit 使用稳定的 step.N 与
completion 名称，不写 HTTP 内容、真实 URL 或耗时；实现常用 testsuite/testcase/failure/
skipped 子集，没有承诺所有 JUnit 消费器扩展兼容性。CI 保存真实夹具成功报告及明确
命名的故意失败样例，在 Linux 使用 xmllint 检查两者的 XML 良构性。

## 验证与布局

### 批量执行回归夹具

```sh
moon run packages/suite -- examples/regression.suite.json --explain --junit suite.xml
```

示例同时验证真实 identity 与 gzip 记录。清单为数组，每项要求 name、har、requests，
可选 decoded 布尔值、mode（ordered/by-request/per-request）与 match_headers 字符串数组。
文件路径按进程工作目录解析，也可填写绝对路径；上述命令在仓库根目录运行。
name 是公开 CI 标识：1–128 个 ASCII 字母、数字、点、下划线或连字符，区分大小写且唯一。

先编译所有输入并校验预算，再按清单顺序执行；每个用例使用独立的新 session，检查
完整消费。一项回放失败仍继续后续用例。stdout 始终是汇总 JSON，保留每项诊断、可选
匹配解释和完整 decoded 头修改审计。退出码 0 全部通过、1 存在回放失败、2 输入/输出错误。
输入无效时 cases 为空，且不创建 JUnit；--junit 拒绝已有路径。
JUnit 中 suite、classname 与 testcase 名称均区分用例，避免多组 step.0 发生结果冲突。

库入口 `SuiteCase::new(name, cassette, plan, mode=Ordered)` 与 `verify_suite(cases)`，
返回 SuiteReport，可查询 passed()/cases()，并生成稳定 JSON/JUnit。失败不会消费调用方
的 cassette 或其他 session。库默认最多 1000 项和 1,000,000 次检查（每项完成检查也计入），
可通过 max_cases/max_checks 调整；库可显式运行空集合，CLI 原始清单要求 1–1000 项。
CLI 清单最多 4,194,304 UTF-16 units，编译输入预算默认最多 67,108,864 units；
每份输入仍受原有编译上限约束。这些是接受上限，不是进程内存配额。

清单预检和共享输入加载也可直接用于下游工具：`parse_suite_manifest(text)` 返回
SuiteManifest，source() 保留原文，names() 返回用例名副本；`manifest.load(path =>
read_text(path))` 通过调用方读取器生成 SuiteCase 数组，再交给 verify_suite。
全部元数据在第一次读取前验证，读取器异常原样传播；格式错误补充原始用例索引和输入类别。

一次 load 内，同一精确路径只读取一次；相同 HAR 路径/decoded/请求头配置及相同请求计划
路径分别复用编译结果，匹配模式仍由各用例的独立 session 决定。不同路径别名不自动合并。
预算按清单原文、每个不同 HAR 编译配置和每个请求计划路径的源文本各计算一次，可通过
max_total_input_units 调整。下次 load 使用新快照，不保留全局缓存；CLI 使用相同 API。

选择部分用例或在 CI 中分片：

```sh
moon run packages/suite -- examples/regression.suite.json --case identity --list
moon run packages/suite -- examples/regression.suite.json --case identity --shard 0/2 --junit shard-0.xml
```

--case 可重复，要求名称存在且不重复，始终保留清单原序；--shard 使用从 0 开始的
INDEX/COUNT，COUNT 为 1–1024。先按名称选择，再按名称哈希分片，新增其他用例不会
改变既有分配；数量不保证均衡。算法固定为 ASCII 名称的 131 多项式哈希，先模
2,147,483,647 再模片数，审计标识为 poly131-v1。

--list 只预览完整选择范围，不加载 HAR/计划或执行回放，不能同时要求 --explain/--junit。
执行选择后，JSON 新增 selection：原始总数、selected/excluded 名称、分片参数与算法。
空分片显式成功且产生零用例报告；只有选择的文件会读入，排除项不计作已验证。
默认不加选择参数时保留原报告格式。库使用 manifest.select(names=["identity"],
shard_index=0, shard_count=2)，names() 表示当前子集，selection_json() 审计相对原始清单
的最终范围。继续 select 只会缩小当前子集；source() 与原始诊断索引保留。

### 审查夹具更新

```sh
moon run packages/review -- examples/repository.har examples/repository.har
```

将两个文件路径替换为更新前/后的记录。退出码为 0（回放行为相同）、1（存在变化）、
2（输入或预算错误）。输出是确定性的 JSON，报告原始记录索引与 added/removed/status/
headers/body，不回显 URL、正文或头值。记录时间和浏览器元数据不参与行为比较。

库 API `before.compare(after)` 先按请求身份做 LCS 对齐，再比较响应，避免插入一个
调用导致其后所有响应都被误报。重复请求按原序对齐，平局先移除旧记录；重排表示为
移除/新增，修改请求身份同样表示为移除/新增。两个 cassette 必须采用相同请求头
匹配规则。`ignore_response_headers=["Date"]` 仅排除显式列出的响应头，排除清单仍
写入报告。默认 `max_cells=1000000` 限制 `(旧交互数+1)*(新交互数+1)`，超限拒绝，
不退化成近似结果。`report.changes()` 返回副本；原始 HAR 保持在各自 cassette 中。

需要忽略易变响应字段时，显式选择 JSON 比较范围：

```sh
moon run packages/review -- before.har after.har --json-pointer /full_name --ignore-header Date --ignore-header Content-Length
```

库调用 `before.compare(after, json_pointers=["/full_name"])`。仍按相同请求身份做 LCS 对齐，
状态和未排除的头继续比较；正文只检查选定路径。缺失与 null 不同，数组保持顺序，
对象忽略成员顺序，数字仍按 token 精确比较。空 pointer 比较整个 JSON 值。
必须指定 1–256 个唯一合法 pointer；所有响应正文（包括新增/删除且未对齐的项）都
必须是严格 UTF-8 JSON，非法数组选择器也拒绝，不回退到忽略或近似比较。

JSON 模式报告新增 body_mode、json_pointers 和 json_changes，后者含前后记录索引、
pointer_index 及 added/removed/changed；路径本身作为显式配置写入报告，实际值不会输出。
`report.json_changes()` 返回副本。未指定 json_pointers 时保留原始字节比较和原报告格式。
CLI 的 --json-pointer 与 --ignore-header 均可重复；压缩记录使用 --decoded，并在同一 JSON
中保留 before_adaptations / after_adaptations 的完整审计。

```sh
moon fmt --check
moon fmt --check tools/import_capture.mbtx tools/verify.mbtx tools/verify_distribution.mbtx
moon info --target all
moon run tools/verify.mbtx wasm
moon run tools/verify.mbtx wasm-gc
moon run tools/verify.mbtx js
moon run tools/verify.mbtx native
moon run tools/verify_distribution.mbtx wasm
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

当前已完成从完整 HAR 导入、精确回放、原子断言与恢复，到契约生成、夹具审查、
独立套件及 JSON/JUnit 报告的完整路径。SDK 适配支持可控响应分块和有界请求源；
独立消费模块验证公开 API，源码 ZIP 解压后重新构建消费模块。

当前交付 Git 源码及可验证的源码包，尚未发布 Mooncakes。CI 会保存 ZIP 和分发验证摘要；
脚本不进行发布。后续依据采用反馈增加可完整还原的请求正文 profile。录制代理、自动脱敏、
OpenAPI、通用 HTTP 客户端和真实网络调度模拟不在本轮范围。
详细场景见 [contract](notes/contract.md)，生态定位与复用来源见 [sources](notes/sources.md)。

MIT，见 [LICENSE](LICENSE)。
