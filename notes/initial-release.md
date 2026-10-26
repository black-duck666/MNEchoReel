# 初版交付与验收

EchoReel 0.1.0 的初版目标是让 SDK/HTTP 业务维护者，把已净化的完整 HAR 记录变成
无需第三方账号的离线回归测试。定位仍是 HAR 工具和 gaato/http 的互补层，生态调研
证据及不确定性见 [sources](sources.md)，不主张生态唯一性。

## 三条可直接验收的工作流

1. **真实 SDK 回归**：运行 README 的 check/demo，再运行 stream_demo。
   预期真实 GitHub JSON 中的 full_name 为 moonbitlang/core，所有记录恰好消费；
   不匹配时没有联网后备路径。upload_demo 可进一步验证有界请求源。
2. **维护可编辑契约**：用 prepare 的 --assert-header、--assert-json 生成新计划文件，
   check 执行；review 检查新旧 HAR 的显式行为范围。默认精确比较不做模糊匹配，
   修改选中字段失败，失败后消费回滚，未支持的数据拒绝并保留原始 source。
3. **下游与 CI 接入**：按 examples/consumer/README.md 从独立模块运行公开 API，
   用 suite 的 --case/--shard 组织用例，保存 JSON/JUnit；范围报告明确列出排除项。
   单项失败不阻止其他独立用例，空分片不代表排除项通过。

所有演示命令从仓库根目录执行；依赖准备后不需要服务或密钥。真实和派生合成输入的
区别见 [provenance](../examples/provenance.md) 与 [validation](validation.md)。

## 源码包验证

```sh
moon package --list
moon run tools/verify_distribution.mbtx wasm
```

验证脚本调用当前工具链的 moon package，预检 ZIP 的相对路径和必需文件，拒绝工作区
状态目录；解压到全新的 _build 子目录，逐文件比对内容，再从包内独立消费模块严格编译
和运行。不会复制当前工作区的缓存或用根项目替代包内库。Windows 使用系统 tar.exe，
Linux/macOS 使用 unzip；脚本不执行发布、登录或注册命令。

生成物位于 _build/publish，验证摘要为 _build/echoreel-distribution-TARGET.json。
相同命令也接受 wasm-gc、js、native；本机原生运行需要配置对应编译器和 SDK。
每次验证使用新目录，保留结果便于检查；清理时可用 moon clean。

这里验证源码文件内容与包内采用路径，不承诺 ZIP 元数据或压缩字节跨机器一致。
CI 保存源码 ZIP、验证摘要与回归报告；单元测试在打包前按验证矩阵执行，不重复声称
所有测试均在包内重跑。包内会重新构建公开消费模块。

## 当前完成与边界

初版已具备导入、严格回放、原子断言、契约生成、夹具审查、独立套件、SDK 集成和
源码采用/打包验证的完整路径。公开接口以三个库包的生成 mbti 为准；下游可固定本轮
提交来使用。当前提供 Git 源码和本地源码包，尚未发布 Mooncakes 或创建正式发行标签。

Wasm、Wasm-GC、JS 与原生编译均受 CI 检查；原生实际运行覆盖 Linux、macOS、Windows。
Wasm-GC 跳过异步测试，SDK 异步演示由其他目标执行；本地没有 Windows 原生 SDK，
实际原生成功以相应 CI 为证，详细数量和命令见 validation。

请求正文仍只接受能精确还原的 UTF-8 text。multipart、SSE、协议升级、外部正文、
自动脱敏、录制代理、OpenAPI 和真实网络调度模拟不在本轮交付范围。后续只在真实
采用反馈支持下扩展可完整还原的 profile；本轮在此冻结范围。

## 开源交接

项目代码与自编测试使用根 MIT 许可证；依赖、格式参考和数据许可边界见 sources
及 examples/provenance.md。请勿把公开 API 数据的来源许可误写成仓库代码许可证。
当前验证不依赖私有基础设施，也不以测试数量证明性能或广泛兼容性。
