# ADR-0006：引入首个第三方依赖 swift-argument-parser

- 状态：已接受（2026-11-05）
- 关联：NAN-156；AGENTS.md 核心原则 2（依赖最小化）

## 背景

M2 的 CLI 需要参数解析（子命令、类型化选项、帮助文档、退出码）。此前仓库保持零第三方依赖；「应用类仓库应提交 lockfile」的决策产生于 M0 提交审查（commit 2dd051d 审查记录），但当时未落 ADR，本篇补记。

## 决策

1. 引入 `apple/swift-argument-parser`（声明 `from: 1.5.0`，实际解析 1.8.2），仅用于 `appletodo` 可执行 target；**AppleToDoCore 保持零依赖**。
2. `Package.resolved` 入库（可复现构建）。
3. 后续新增依赖：过审查协议，并在本 ADR 追记或另立 ADR。

## 后果

- 「零依赖」承诺改写为「Core 零依赖；CLI 壳最小依赖」（AGENTS.md 已同步）
- lockfile 随仓库分发，远端接入后 CI 直接复用
