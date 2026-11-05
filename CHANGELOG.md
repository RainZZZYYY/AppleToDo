# 更新日志（Changelog）

本项目的显著变更记录于此。格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [SemVer](https://semver.org/lang/zh-CN/)。

## [未发布]

### 修复

- `today` 命令运行即崩（手动构造 `List()` 违反 ArgumentParser 属性包装器约束）；查询逻辑抽为 `CLI.runList` 共享实现，`list`/`today` 均委托之。v0.1.0 的审查与冒烟未覆盖 `today` 实际执行，已吸取教训

## [0.1.0] - 2026-11-05

首个正式版本：M0（工程奠基）+ M1（核心域层）+ M2（CLI v0.1）。

### 新增

- `appletodo` CLI（ADR-0006：swift-argument-parser，Core 保持零依赖）
  - 命令：`list` / `today` / `add-event` / `add-reminder` / `move` / `complete` / `edit-event` / `edit-reminder` / `delete-event` / `delete-reminder`
  - `--json` 机器可读输出（ISO8601 日期；错误输出 `{"error":...}` 至 stderr）
  - 退出码：0 成功 / 1 业务失败 / 64 参数错误
- AppleToDoCore
  - 领域模型：工具形状值类型（Codable/Sendable、错误即数据，ADR-0005）
  - `EventStoring` 端口 + `InMemoryStore`（单测 mock / 将来 dry-run，ADR-0003）
  - `EventKitStore` 生产适配器：iCloud「AppleToDo」日历/清单落点（ADR-0002），按实体类型选源
  - `ScheduleService` 全量 CRUD：含补丁语义（nil=不变、""=清空、due 三态）与 `[AppleToDo]` 溯源标记
- 工程基建：SwiftLint/SwiftFormat、CI workflow（待远端激活）、AGENTS.md 协作规范（含 3-agent×3-轮提交审查协议）、PRD 与 ADR-0001~0006
- 测试：23 个单测（CI 可跑）+ 2 个 env 门控集成测试（实跑通过）

### 已知限制

- 后台环境（无 GUI 宿主）首次运行会被 TCC 静默拒绝授权（ADR-0003）；首次授权请在 Terminal 中执行
- `EventKitStore` 的日历缓存在目标日历被外部删除后可能过期（M3 前处理）
