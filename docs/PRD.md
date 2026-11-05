# AppleToDo PRD — 产品需求与路线图

版本 1.3（2026-11-06）· 状态：M4+M5 完成（dev 分支）；M6 进行中 · 维护：agent，重大变更需 owner 确认

## 1. 愿景

个人日程规划中枢：从多个信息源（Linear 任务、自然语言指令）收集待办，经 AI 规划，写入苹果系统日历/提醒事项，经 iCloud 全端同步。

```
大脑（可替换的外部客户：agent / 任意 MCP 客户端 / 未来 App 内置 LLM）
   ↓ 只依赖能力契约（工具形状的操作，ADR-0005）
AppleToDo 程序本体
   ├─ Core 领域 API（真正资产：领域模型 + 规划逻辑）
   ├─ 写入适配器：EventKitStore → 系统日历/提醒事项 → iCloud → iPhone
   ├─ 信息源适配器：LinearSource / …（薄壳，可插拔）
   └─ 接口适配器：CLI / MCP server / App UI（薄壳，可插拔）
```

三种产品形态共享同一核心模块（换壳不换芯）：

1. **阶段一**：ZCode agent 经 CLI + skill 操作（agent 即 LLM）
2. **阶段二**：独立 CLI / 菜单栏 App
3. **阶段三**：内置 LLM API 的完整 App

## 2. 目标 / 非目标

**目标**：三形态共享核心；数据永远落在官方 app 并 iCloud 同步；过程产出规范工程资产；训练 owner 的工程能力。

**非目标**：不自建数据库；不走 iCloud 私有 API；不替代日历 app 的展示功能；初期不做 iOS App。

## 3. 核心场景

1. 自然语言录入：「明天下午 3 点牙医，提前 1 小时提醒」→ 日历事件 + 提醒
2. 周规划：从 Linear 拉取本周到期/进行中任务 → 生成待安排清单 → 确认后 time-block 写入日历
3. 日程维护：改期、顺延、完成，均保持官方 app 与 iPhone 同步正确

## 4. 模块

| 模块 | 职责 | 引入 |
|---|---|---|
| `AppleToDoCore` | 领域模型 + EventKit 封装 + 规划逻辑（纯库，零依赖） | M1 |
| `appletodo` | CLI 壳（仅 swift-argument-parser 一个依赖，ADR-0006） | M2 |
| `AppleToDoLLM` | 内置大脑（契约的客户端之一）：`LLMProviding` 协议 + 智谱 GLM-5.3 实现（ADR-0004/0005） | M6 |
| `AppleToDoLinear` | Linear 信息源适配器（先只读；若官方 MCP 编排方案成立则可能取消，ADR-0005） | M7 |

接口壳（CLI / MCP server / App UI）不设独立模块，随里程碑以薄壳形式挂接 Core。

## 5. 里程碑路线图

| 里程碑 | 内容 | 验收要点 |
|---|---|---|
| M0 项目奠基 | 仓库/CI/lint/文档/ADR（本 PRD 即 M0 产物） | 本地门禁绿，文档齐备 |
| M1 核心域层 | 领域模型 + `EventStoring` 协议 + EventKit 增删改查 + mock 单测 | 单测覆盖核心路径；真实事件写入 iPhone 可见 |
| M2 CLI v0.1 | list/today/add/move/complete；`--json` 输出；退出码规范 | v0.1.0 tag + CHANGELOG |
| M3 Agent 集成 | skill 文档 + 安全规则（查重/确认/dry-run） | 会话内实测日程管理 |
| M4 加固与可观测 | 结构化日志、错误码、幂等、本地集成测试 | 集成测试可重复执行 |
| M5 菜单栏 App | SwiftUI，复用 Core | 模块复用验证 |
| M6 LLM 接入 | GLM-5.3 接入，自然语言→结构化管线，key 走 Keychain | 端到端自然语言建日程 |
| M7 Linear 集成 | 到期任务→待安排清单→time-block；优先评估 Linear 官方 MCP 编排（ADR-0005）；可选自有 MCP server / App Intents | 周规划场景跑通 |

## 6. Linear 的双重角色

- **过程管理**（M0 起）：本项目开发任务由 Linear 跟踪（Project「AppleToDo」+ 里程碑 + issues，Nankai 团队）
- **信息源**（M7 起）：产品功能——读取 owner 的 Linear 任务辅助排期，先只读

## 7. 协作模式

执行者：agent（逐步执行、维护 Linear、做常规决策并留 ADR）；owner：方向决策与验收。流程规范见 [AGENTS.md](../AGENTS.md)，决策记录见 [adr/](adr/)。

## 8. 开放问题

- ADR-0002 数据规范为暂行版，M1 实施时与 owner 盘点现有日历/清单后复核
- Linear 写回（更新任务状态）是否需要，M7 前再议
- TaskSource 插件协议延迟到第二个信息源出现时再抽象（ADR-0005）
- M7 在「官方 MCP 编排」与「自研 GraphQL 适配器」间的取舍，届时以集成复杂度决定（ADR-0005）
- 备忘录适配器延后至系统成熟与 owner 工作流成形（NAN-154，技术边界已勘明：Shortcuts 优先）

（已解决：远端仓库于 2026-11-05 接入 GitHub，同日转为公开仓库（MIT），CI 激活，NAN-118 闭环。）
