# MoonCompat 项目申报书

## 基本信息

- 项目名称：MoonCompat
- 参赛者：404-32
- 联系方式：待填写
- GitHub：https://github.com/404-32/byc002
- 项目方向：开发者工具 / MoonBit 包管理与发布工程
- 项目性质：原创项目，非移植
- 项目状态：v0.1.0 已发布，Apache-2.0 开源

## 项目简介

MoonCompat 是用 MoonBit 实现的 MoonBit 包公开接口兼容性检查工具。它读取 `moon info` 生成的 `.mbti` 文件，比较函数、类型、字段、枚举、Trait 实现和包名，识别破坏性变更，给出 major/minor/patch 建议，并输出文本或 JSON。工具通过退出码接入 CI，在发布前发现会导致下游代码失效的接口变化。

## 项目方向与通用性

项目属于开发者工具方向，服务于 MoonBit 包在 SemVer 和最小版本选择下的发布流程。任何能够生成 `.mbti` 的 MoonBit 库、应用或多包仓库都可接入。核心库只处理公共接口数据，CLI 负责文件访问，同一比较引擎可用于命令行、CI 和后续编辑器工具，不依赖特定业务领域。

## 预期使用场景

1. **版本发布。** 维护者为新旧版本生成接口并运行 `mooncompat check base/ head/`；工具显示前后签名、判定破坏性并返回退出码 1，帮助作者决定是否发布 major 版本。
2. **PR 自动门禁。** GitHub Actions 检出基线和当前提交，生成 `.mbti` 后执行检查并上传 JSON；破坏性变更阻止合并，兼容新增返回 0 并建议 minor。
3. **多包仓库升级。** 工具递归扫描多个包的接口，按包名匹配新旧版本，报告包删除、新增及包内 API 变化，可用于 monorepo 的统一发布检查。

## 已实现核心功能

- 解析函数、类型、结构体、枚举、错误、Trait、实现、常量和公开别名；
- 规范化空白、成员顺序、`derive` 与等价显式 `impl`、`Int`/`Int32` 等差异；
- 比较单包及多包 API，识别删除、签名、字段、枚举、实现和包名变化；
- 输出文本、固定 schema 的 JSON、接口快照，并提供 0/1/2 退出码；
- 在未知公开语法、未闭合结构和缺失包名时失败关闭，避免静默漏检；
- 已提供 33 个 MoonBit 测试、CLI 集成测试和真实包回归，四个编译后端 CI 通过；
- 已发布 WASM、Linux 可执行文件及 Mooncakes 包。

验证包括 `moonbitlang/x v0.5.6 → v0.5.7` 的 854 个声明，以及 `moonbitlang/async/fs v0.21.3 → v0.22.7` 的 3 个破坏变更、11 个兼容新增和 60 个不变声明。项目运行时不依赖大模型，解析、分类和拒错均由 MoonBit 代码与测试决定。

## 原创性与参考说明

本项目为原创项目，不是移植，也不是现有工具的简单封装。比较规则、规范化逻辑、报告结构和测试 fixture 均在本仓库实现。使用 MoonBit 标准库（Apache-2.0）及 `moonbitlang/async` v0.22.7（https://github.com/moonbitlang/async，Apache-2.0）作为运行依赖；完整来源见仓库 `THIRD_PARTY_NOTICES.md`。

## GitHub 仓库

https://github.com/404-32/byc002

当前 `main` 分支包含不少于 10 个有效提交，覆盖核心引擎、CLI、fixture、跨平台规范化、CI、文档和发布流程，未使用空提交或重复提交满足次数要求。
