# AppleToDo

个人日程规划中枢：从 Linear 任务与自然语言输入收集待办，经 AI 规划写入苹果系统日历/提醒事项，经 iCloud 全端同步。

## 架构

```
大脑（可替换的外部客户：agent / MCP 客户端 / 未来内置 LLM）
   ↓ 能力契约（工具形状的操作，ADR-0005）
AppleToDo 本体：Core 领域 API + 薄壳适配器
   写入：EventKitStore → 系统日历/提醒事项 → iCloud → iPhone
   信息源/接口：Linear / CLI / MCP server / App（可插拔）
```

三种形态共享同一核心模块：agent CLI（阶段一）→ 独立 CLI / 菜单栏 App（阶段二）→ 内置 LLM API 的 App（阶段三）。

## 模块

| 模块 | 职责 |
|---|---|
| `AppleToDoCore` | 领域模型 + EventKit 封装 + 规划逻辑（纯库，零依赖） |
| `appletodo` | CLI 壳（仅 swift-argument-parser 一个依赖） |

## 开发

```bash
swift build                  # 构建
swift test                   # 测试
swift run appletodo --help   # CLI 用法
```

> 首次执行访问日历/提醒事项的命令（如 `list`）时，系统会弹授权框；后台环境无法弹框会被系统静默拒绝（见 ADR-0003，Terminal 下运行正常）。

> 本机若报 `no such module 'XCTest'`：先 `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`（已写入 ~/.zshrc；原因见 [ADR-0004](docs/adr/0004-toolchain-and-process.md)）。

## CLI 用法

```bash
swift run appletodo list --date 2026-11-06          # 某天日程 + 未完成提醒
swift run appletodo today                            # 今天
swift run appletodo add-event "牙医" --at "2026-11-07 15:00" --duration 60 --notes "带病历"
swift run appletodo add-reminder "买书" --due "2026-11-08"
swift run appletodo move <id> --at "2026-11-07 16:00"   # 事件改期（保时长）
swift run appletodo edit-reminder <id> --due "2026-11-09 10:00"
swift run appletodo complete <id>
swift run appletodo delete-event <id>
```

所有命令支持 `--json`（供 agent/脚本消费；错误同样输出 JSON 到 stderr，退出码 1）。

## 文档

- [PRD — 产品需求与路线图](docs/PRD.md)
- [ADR — 架构决策记录](docs/adr/)

**状态**：M2 完成，v0.1.0 已发布。任务跟踪：Linear Project「AppleToDo」（Nankai 团队）。
