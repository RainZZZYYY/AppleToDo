# ADR-0007：LLM 原生接入延后，优先 MCP 服务端与 App 设计

- 状态：已接受（2026-11-10，owner 决策）
- 关联：ADR-0004（密钥管理，M6 重启时适用）；ADR-0005（大脑即客户端）；PRD §5 路线图；NAN-167/44b8931

## 背景

M6 计划原生接入 GLM-5.3。首项（`LLMProviding` 协议 + `GLMProvider`）已在 dev 分支实现（44b8931）并通过真实 API 往返验证（2026-11-10 实测：自然语言 → 结构化 JSON）。审批批次 3 时 owner 调整路线。

## 决策

1. **LLM 原生接入整体延后**。理由：自建的 LLM 集成可靠性不及成熟系统；当前决策大脑由 ZCode（成熟 agent 客户端）承担即可，AppleToDo 接收结构化指令。
2. **44b8931 不并入 main**，保留在 dev 分支；重启时从 dev 捡起（合并前补 DTO 单测的复核点随之延续）。
3. 当前优先级（原 M6 让位）：
   - **M8 · MCP 服务端**：AppleToDo 作为 MCP server，把 CLI 现有全部能力（10 个子命令）暴露为 MCP 工具，ZCode 及任意 MCP 客户端原生直连——对标 Linear 官方 MCP 的集成体验；CLI + skill 降级为兼容路径。（ADR-0005 后果所述「M7 的 MCP server」事项移此成为主线，该表述以本篇为准）
   - **M9 · App 设计与完善**：桌面 App 与菜单栏 App 功能集、交互设计先行，评审后实现；含 .app bundle 化（NAN-170）
4. `dev` 分支保留（承载 44b8931），不删除。

## 后果

- main 无 AppleToDoLLM 模块；PRD 模块表与里程碑表同步改写（v1.3）
- agent ↔ AppleToDo 的第一公民通道从「CLI+skill」转向「MCP」
- 自然语言解析在过渡期由外部大脑完成（agent 调 CLI/未来 MCP），端到端自然语言建日程的目标后移至 M6 重启
- 重启条件（开放）：MCP 与 App 功能面成熟、owner 工作流成形
