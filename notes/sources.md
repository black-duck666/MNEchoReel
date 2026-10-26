# 生态边界与来源

调研日期：2026-10-25。定位是**互补层**，不主张生态唯一性。
核心价值是执行已有完整 HTTP 记录，以验证真实客户端请求、消费次序和业务返回。

| MoonBit 项目 | 公开边界 | 许可证 | 关系 |
| --- | --- | --- | --- |
| [har-toolkit](https://github.com/cpypypypy/moonbit-har-toolkit) / [API](https://mooncakes.io/docs/cpypypypy/har-toolkit) | parse_har、validate_har、redact_har、serialize_har、性能统计 | Apache-2.0 | 复用 0.1.0 的结构解析与验证；本项目不重做通用 HAR 分析或脱敏 |
| [gaato/http](https://github.com/gaato/mbt-sdk) / [API](https://mooncakes.io/docs/gaato/http) | Request、Response、Transport、BodyStream、脚本 FakeTransport | Apache-2.0 | 复用 0.4.1 HTTP 词汇；增加从真实 HAR 编译、严格匹配、歧义与消费断言 |
| [MoonContract](https://github.com/Han-Wentao/mooncontract) | openapi.parse_json、contract.compile、validate_request、MockEngine::respond | MIT | 从接口规格生成 mock/契约；此处执行实际记录，不编译 OpenAPI |

调查时 har-toolkit 仓库最新推送为 2026-08-15，gaato/mbt-sdk 为 2026-10-24，
MoonContract 为 2026-09-14。它们是当时的仓库级活动信号，不等于每个包版本发布日。
Mooncakes 文档索引可能落后；实现固定版本并以实际下载接口为准。

跨语言需求验证：[VCR.py](https://github.com/kevin1024/vcrpy)（MIT，约 3k stars）、
[Polly.JS](https://github.com/Netflix/pollyjs)（Apache-2.0，约 10k stars）、
[Playwright HAR 工作流](https://playwright.dev/docs/mock#mocking-with-har-files)。
热度是调查快照，不是采用量或质量保证。上述代码和测试未移植。

检索覆盖 Mooncakes、GitHub、MoonBit 文档/社区索引，关键词包括
`MoonBit HAR replay cassette VCR HTTP mock record playback`、
`site:mooncakes.io har http transport mock`、`MoonContract mock replay`，以及中文
`MoonBit 录制 回放 离线 HTTP 测试`。替代方案还检索了 webhook inbox/idempotency
与 PostgreSQL EXPLAIN plan regression。检索不保证覆盖新发布、未索引、私有或
改名项目；差异化结论限于已检查的公开项目与 API。

复用清单：

- har-toolkit 0.1.0：依赖调用，Apache-2.0；未复制其序列化逻辑。未知重放语义
  由本项目在原始 JSON 上额外检查，全部原文保存在 Cassette 中。
- gaato/http 0.4.1：依赖调用与实现公开 Transport/BodyStream trait，Apache-2.0。
  未复制其 FakeTransport 实现或测试。
- moonbitlang/core：编译器附带的 JSON、UTF-8、base64、容器等，Apache-2.0。
- moonbitlang/x 0.5.5、moonbitlang/async 0.22.5：文件、退出码、演示与自动化运行，
  Apache-2.0。异步运行时不是回放核心的 I/O 依赖。
- [hustcer/setup-moonbit](https://github.com/hustcer/setup-moonbit)：CI 安装工具，MIT；
  固定 action commit，工具链使用稳定 latest。checkout/setup-node 与 msvc-dev-cmd
  作为 CI action 引用，各自由上游许可证约束，没有复制进本项目。
- [HAR 1.2 历史草案](https://webperfwg.org/specs/HAR/Overview.html)：格式语义参考；
  文档已停止维护，不称其为现行 W3C 标准。
- [RFC 6901](https://www.rfc-editor.org/rfc/rfc6901.html)：JSON 字符串 pointer 的语法与求值参考。
  本项目只实现响应字段选择所需形式；没有复制 RFC 示例、代码或上游测试。
  数字采用本项目明确规定的 token 精确比较，不宣称实现通用 JSON Schema/JSON Patch。
- [GitLab JUnit 报告文档](https://docs.gitlab.com/ci/testing/unit_test_reports/)：采用其公开
  列出的常用 testsuite/testcase/failure/skipped 元素；没有复制实现、schema 或测试数据，
  没有把 JUnit 方言说成统一标准。libxml2 的 xmllint（MIT）仅用于 Linux CI 良构性验证。
  upload-artifact action（MIT）固定到已核对的 v4 commit，保存生成的报告，不调用外部私有服务。
- 真实 API 数据、获取命令、许可不确定性与包裹 HAR 的来源见
  [examples/provenance.md](../examples/provenance.md)。单元测试边界数据和项目实现
  在本仓库新编写，按根目录 MIT 许可发布。

请求流适配通过公开的 gaato/http 0.4.1 StreamBody::take/length 使用其一次性读取与长度
校验（Apache-2.0），没有复制 FakeTransport 的 drain 或 stream 实现。响应分块和请求
预算逻辑、测试及演示均为本项目编写；upload_demo 的派生 POST 使用既有真实响应数据，
来源与许可限制仍见 examples/provenance.md，不声称该合成请求是实际网络录制。

源码采用与分发配置参考当前工具链实际命令及官方
[本地模块工作区说明](https://tour.moonbitlang.com/basics/module-and-package/index.html)、
[模块打包与 .moonignore 说明](https://docs.moonbitlang.com/en/stable/toolchain/moon/module.html)。
未复制其示例代码或测试；源码包由 moon package 生成，验证通过系统 tar.exe/unzip
解压自建归档，不移植 ZIP 编解码器。后者是构建环境工具，不是库的运行期依赖。
