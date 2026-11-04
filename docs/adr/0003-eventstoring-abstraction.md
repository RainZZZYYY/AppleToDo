# ADR-0003：EventStoring 协议抽象与测试策略

- 状态：已接受（2026-10-31）
- 关联：ADR-0001；NAN-122

## 背景

两个硬约束：（1）CI（GitHub Actions macOS runner）无法弹 TCC 权限框，真实 `EKEventStore` 在 CI 上不可用；（2）单测需要确定性，不能依赖真实日历数据库的状态。因此核心逻辑不能直接依赖 `EKEventStore` 具体类型。

## 决策

1. `AppleToDoCore` 依赖 `EventStoring` 协议（M1 依实际需求定义接口，**不预先设计**方法集）。
2. 生产侧：`EventKitStore` 适配器包装 `EKEventStore`。
3. 测试侧：内存 mock 实现供单测使用（CI 可跑）。
4. 集成测试：环境变量 `APPLETODO_INTEGRATION_TESTS=1` 门控，仅在本地执行，测试后自清理；不进 CI。原方案「只写本地 On My Mac 测试日历」经实测不可行（**2026-11-04 修订**：本机 EventKit 无 local 源，且 EKSource 由系统管理、无法编程创建），改为写 iCloud 账户专属 `AppleToDoTests` 日历/清单——与生产落点（ADR-0002 的 AppleToDo 日历）同构、命名隔离，条目 teardown 自清理，测试日历常驻可隐藏。

## 后果

- 核心逻辑与苹果框架解耦，可在秒级、无权限的环境下测试
- 代价：协议与适配器各一层。这是被部署环境逼出的必要抽象（非过度设计），接口随 M1 真实需求生长，避免臆造
- 集成测试覆盖 EventKit 真实行为（时区、重复规则等边缘），与单测互补
