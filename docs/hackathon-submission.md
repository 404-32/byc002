# MoonCompat 项目说明

## 项目名称

MoonCompat

## 一句话介绍

MoonCompat 是一个 MoonBit 原生的包 API 兼容性检查工具：比较两个版本的 `.mbti` 公共接口，识别破坏性变更，给出 SemVer 建议，并作为 CI 发布门禁。

## 解决的问题

MoonBit 包管理遵循 SemVer 和 minimal version selection，但修改函数参数、公开字段、枚举构造器、Trait 实现或包名时，作者不一定能及时发现下游代码会失效。

MoonCompat 把这一风险变成可运行的检查结果。输入是 MoonBit 官方 `moon info` 生成的接口，不依赖模型猜测。

## MoonBit 的作用

MoonBit 是项目的主要实现语言，负责：

- `.mbti` 解析；
- 公共声明规范化；
- derive 与显式 `pub impl` 的等价处理；
- `Int`/`Int32` 别名规范化；
- 单包和多包比较；
- SemVer 推荐；
- 文本与 JSON 报告；
- CLI 参数、文件扫描和退出码。

文件系统与进程相关逻辑位于独立 CLI 包，核心引擎保持跨目标可测试。

## 实际演示

```bash
moon run cmd/main -- check fixtures/demo/base fixtures/demo/head
```

结果：

```text
3 breaking, 1 compatible, 2 unchanged
Recommended bump: major
Exit code: 1
```

`--format json` 输出固定字段和稳定排序的结果，可用于 CI 和后续工具链。

## 工程质量

- 32 个 MoonBit 库测试；
- 覆盖破坏、兼容、无变化、畸形输入和不支持语法的 fixture；
- JSON 报告拥有固定 schema 与快照断言；
- 未知公共 `.mbti` 语法显式失败，不静默漏检；
- 目录扫描排除依赖缓存与构建目录；
- CI 覆盖 `wasm`、`wasm-gc`、`js`、`native`；
- 对 `moonbitlang/x` 和 `moonbitlang/async` 已发布版本做真实回归；
- Apache-2.0 开源，第三方来源单独记录。

## 创新点

1. 直接利用 MoonBit 官方生成的 `.mbti`，输入边界明确。
2. 将 derive 能力与显式 Trait 实现统一建模，避免格式差异造成误报。
3. 同时提供库 API、CLI、JSON 和退出码，不只停留在展示页面。
4. 采用失败关闭策略，无法识别的新公开语法不会被误判为兼容。

## 当前边界

MoonCompat 检查源码公共接口兼容性，不检查 ABI、运行时行为、性能或协议兼容性。对签名变化采用保守策略。文档和帮助信息均明确这些边界。
