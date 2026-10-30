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
swift build   # 构建
swift test    # 测试
```

## 文档

- [PRD — 产品需求与路线图](docs/PRD.md)
- [ADR — 架构决策记录](docs/adr/)

**状态**：M0 项目奠基进行中。任务跟踪：Linear Project「AppleToDo」（Nankai 团队）。
