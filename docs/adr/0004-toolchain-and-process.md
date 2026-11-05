# ADR-0004：工具链与流程决策集

- 状态：已接受（2026-10-31，含 owner 直接指示项）
- 关联：NAN-115/117/118/119

本 ADR 收录 M0 期间做出的工具链与流程决策及理由。

## 1. Git：暂为本地仓库（owner 指示）

先建本地仓库，远端接入时间未定。CI workflow 已就位但休眠，接入远端后激活（NAN-118，届时评估 brew 工具版本锁定）。休眠期间审查协议在会话内执行（见 AGENTS.md）。

> **修订（2026-11-05）**：远端已接入 GitHub 私有仓库，CI 激活，NAN-118 闭环；Git 策略（日常直推 main，重大变更走短分支 + PR）见 AGENTS.md。

## 2. 测试框架：XCTest 而非 swift-testing

本机裸 CLT 工具链不含 `Testing` 模块（`swift test` 报 no such module）；XCTest 在完整 Xcode 与 CI runner 上均可用。若未来 swift-testing 普及，可再迁移。

## 3. 工具链路径：DEVELOPER_DIR 指向完整 Xcode

`xcode-select` 当前指向纯 CLT（缺 XCTest），切换需 sudo 密码；改为在 `~/.zshrc` 导出 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`（无 sudo、可逆）。

## 4. LLM 供应商：智谱 GLM-5.3（owner 提供密钥）

- 端点：`https://open.bigmodel.cn/api/paas/v4/chat/completions`（OpenAI 兼容，Bearer 认证）
- 模型：`glm-5.3`（混合推理，1M 上下文；注意 `reasoning_content` 字段与推理 token 消耗）
- 密钥：已存入 macOS Keychain（服务名 `com.appletodo.llm`，账户 `zhipu`），**严禁入库**；已用最小请求验证可用（2026-10-31）
- 接入：M6 的 `AppleToDoLLM` 模块，经 `LLMProviding` 协议抽象，便于未来增加供应商

## 5. SwiftLint@Xcode 26 兼容 workaround（本机）

Xcode 26 工具链把 `sourcekitdInProc.framework` 放在 `usr/lib/` 直下，SwiftLint 0.65.1 在 `usr/lib/swift-6.2/macosx/` 找不到而崩溃。本机解法：向 brew Cellar 的 swiftlint `bin/` 目录符号链接该框架（无需 sudo）。brew 升级 swiftlint 后需重建链接；CI runner 不受影响。

## 6. 提交审查协议（owner 强制要求）

每次提交前 3 个 agent × 至少 3 轮审查，3 轮不收敛即重做。此为 owner 明确设定，不是可精简的工程流程；详见 AGENTS.md。
