# AppleToDo

个人日程规划中枢：从 Linear 任务与自然语言输入收集待办，经 AI 规划写入苹果系统日历/提醒事项，经 iCloud 全端同步。

## 架构

```
信息源（Linear / 自然语言） → 大脑（agent → 内置 LLM） → AppleToDoCore → EventKit → iCloud → iPhone
```

三种形态共享同一核心模块：agent CLI（阶段一）→ 独立 CLI / 菜单栏 App（阶段二）→ 内置 LLM API 的 App（阶段三）。

## 模块

| 模块 | 职责 |
|---|---|
| `AppleToDoCore` | 领域模型 + EventKit 封装 + 规划逻辑（纯库） |
| `AppleToDoCLI` | 命令行壳 |

## 开发

```bash
swift build                       # 构建
swift test                        # 测试
swift run AppleToDoCLI --version  # 运行（M2 起更名为 appletodo）
```

> 本机若报 `no such module 'XCTest'`：说明激活的是纯 CLT，需 `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`（已写入 ~/.zshrc）。

## 文档

PRD 与 ADR 决策记录将在 M0 内提交至 `docs/`（进行中）。

**状态**：M0 项目奠基进行中。任务跟踪：Linear Project「AppleToDo」（Nankai 团队）。
