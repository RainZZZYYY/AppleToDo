@testable import AppleToDoCore
import XCTest

/// 真实 EventKit 集成测试（ADR-0003）：默认跳过，仅本地手动运行。
///
/// 运行方式：`APPLETODO_INTEGRATION_TESTS=1 swift test --filter EventKitStoreIntegrationTests`
/// 首次运行会弹出日历/提醒事项权限框。写入 iCloud 账户专属的 `AppleToDoTests` 日历/清单
/// （本机无 On My Mac 本地源且 EventKit 无法编程创建源，ADR-0003 修订），条目通过 teardown
/// 自清理；测试日历/清单本身保留复用（可在系统日历 app 中隐藏）。
final class EventKitStoreIntegrationTests: XCTestCase {
    private func iCloudTestConfig() -> EventKitStoreConfig {
        var config = EventKitStoreConfig()
        config.eventCalendarName = "AppleToDoTests"
        config.reminderListName = "AppleToDoTests"
        return config
    }

    // MARK: - 基本往返（M1 建立）

    func testEventRoundTripThroughEventKit() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["APPLETODO_INTEGRATION_TESTS"] == "1",
                          "需 APPLETODO_INTEGRATION_TESTS=1（ADR-0003：仅本地运行）")
        let store = EventKitStore(config: iCloudTestConfig())
        try await store.requestAccess()
        let service = ScheduleService(store: store)

        let start = Date().addingTimeInterval(3600)
        let created = try await service.addEvent(title: "[IT] 事件往返", start: start, end: start.addingTimeInterval(1800))
        addTeardownBlock { [store] in
            try? await store.delete(eventID: created.id)
        }

        // 落库后的 id 是 EventKit 标识符，按 id 能取回
        let fetched = try await store.event(id: created.id)
        XCTAssertEqual(fetched?.title, "[IT] 事件往返")
        XCTAssertTrue(fetched?.notes?.hasPrefix("[AppleToDo]") == true, "备注应带 ADR-0002 溯源标记")

        // 改期保持时长
        let moved = try await service.moveEvent(id: created.id, to: start.addingTimeInterval(7200))
        let refetched = try await store.event(id: created.id)
        XCTAssertEqual(refetched?.start.timeIntervalSince1970 ?? 0, moved.start.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(refetched.map { $0.end.timeIntervalSince($0.start) } ?? 0, 1800, accuracy: 1)
    }

    func testReminderRoundTripThroughEventKit() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["APPLETODO_INTEGRATION_TESTS"] == "1",
                          "需 APPLETODO_INTEGRATION_TESTS=1（ADR-0003：仅本地运行）")
        let store = EventKitStore(config: iCloudTestConfig())
        try await store.requestAccess()
        let service = ScheduleService(store: store)

        let due = Date().addingTimeInterval(86400)
        let created = try await service.addReminder(title: "[IT] 提醒往返", due: due)
        addTeardownBlock { [store] in
            try? await store.delete(reminderID: created.id)
        }

        let fetched = try await store.reminder(id: created.id)
        XCTAssertEqual(fetched?.title, "[IT] 提醒往返")
        XCTAssertTrue(fetched?.notes?.hasPrefix("[AppleToDo]") == true)

        let completed = try await service.completeReminder(id: created.id)
        XCTAssertTrue(completed.isCompleted)
        let afterComplete = try await store.reminder(id: created.id)
        XCTAssertEqual(afterComplete?.isCompleted, true)
    }

    // MARK: - edit 三态 + delete notFound + dry-run 种子（M4 / NAN-163 扩展）

    func testEventEditAndDeleteThroughEventKit() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["APPLETODO_INTEGRATION_TESTS"] == "1",
                          "需 APPLETODO_INTEGRATION_TESTS=1（ADR-0003：仅本地运行）")
        let store = EventKitStore(config: iCloudTestConfig())
        try await store.requestAccess()
        let service = ScheduleService(store: store)

        let start = Date().addingTimeInterval(7200)
        let created = try await service.addEvent(title: "[IT] 编辑删", start: start, end: start.addingTimeInterval(3600))
        addTeardownBlock { [store] in
            try? await store.delete(eventID: created.id)
        }

        // edit：改标题+时长
        let edited = try await service.editEvent(id: created.id, with: EventPatch(title: "[IT] 编辑后", durationMinutes: 120))
        XCTAssertEqual(edited.title, "[IT] 编辑后")
        XCTAssertEqual(edited.end.timeIntervalSince(edited.start), 7200, accuracy: 1)

        // delete：删掉后再查应 notFound
        try await service.deleteEvent(id: created.id)
        let afterDelete = try await store.event(id: created.id)
        XCTAssertNil(afterDelete, "删除后按 id 应查不到")
        do {
            try await service.deleteEvent(id: created.id)
            XCTFail("重复删除应 notFound")
        } catch let error as ScheduleError {
            XCTAssertEqual(error, .notFound(id: created.id))
        } catch {
            XCTFail("意外错误类型: \(error)")
        }
    }

    func testReminderEditDueThreeStatesThroughEventKit() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["APPLETODO_INTEGRATION_TESTS"] == "1",
                          "需 APPLETODO_INTEGRATION_TESTS=1（ADR-0003：仅本地运行）")
        let store = EventKitStore(config: iCloudTestConfig())
        try await store.requestAccess()
        let service = ScheduleService(store: store)

        let originalDue = Date().addingTimeInterval(86400)
        let created = try await service.addReminder(title: "[IT] 三态", due: originalDue)
        addTeardownBlock { [store] in
            try? await store.delete(reminderID: created.id)
        }

        // nil = 不变（先验证：改标题，due 应保持原值）
        let retitled = try await service.editReminder(id: created.id, with: ReminderPatch(title: "[IT] 三态改"))
        XCTAssertEqual(retitled.title, "[IT] 三态改")
        XCTAssertEqual(retitled.due?.timeIntervalSince1970 ?? 0, originalDue.timeIntervalSince1970, accuracy: 60,
                       "due 未传应保持原值（分钟精度）")

        // .some(date) = 设新截止
        let newDue = Date().addingTimeInterval(172_800)
        let setNew = try await service.editReminder(id: created.id, with: ReminderPatch(due: .some(newDue)))
        XCTAssertEqual(setNew.due?.timeIntervalSince1970 ?? 0, newDue.timeIntervalSince1970, accuracy: 60, "分钟精度")

        // .some(nil) = 清除截止
        let cleared = try await service.editReminder(id: created.id, with: ReminderPatch(due: .some(nil)))
        XCTAssertNil(cleared.due, "清除后 due 应为 nil")
    }

    func testDryRunSeedReadsRealStoreWithoutWriting() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["APPLETODO_INTEGRATION_TESTS"] == "1",
                          "需 APPLETODO_INTEGRATION_TESTS=1（ADR-0003：仅本地运行）")
        let store = EventKitStore(config: iCloudTestConfig())
        try await store.requestAccess()
        let service = ScheduleService(store: store)

        // 真实库创建一条事件和提醒
        let start = Date().addingTimeInterval(10800)
        let event = try await service.addEvent(title: "[IT] dry-run 种子事件", start: start, end: start.addingTimeInterval(3600))
        addTeardownBlock { [store] in
            try? await store.delete(eventID: event.id)
        }
        let reminder = try await service.addReminder(title: "[IT] dry-run 种子提醒", due: start)
        addTeardownBlock { [store] in
            try? await store.delete(reminderID: reminder.id)
        }

        // 模拟 CLI.dryRunService 的种子逻辑（读真实库 → 注入内存 → 对内存执行）。
        // 本测试在 Core 层验证种子模式与 EventKit 数据的兼容性——真实库读回→内存保存→
        // 内存操作→真实库无变化。CLI 层的 --dry-run 旗标接线由冒烟测试覆盖
        // （appletodo add-event --dry-run / move --dry-run 等）。
        let memory = InMemoryStore()
        let realEvent = try await store.event(id: event.id)
        XCTAssertNotNil(realEvent, "种子读取应命中真实库")
        _ = try await memory.save(event: XCTUnwrap(realEvent))

        let memoryService = ScheduleService(store: memory)
        let moved = try await memoryService.moveEvent(id: event.id, to: start.addingTimeInterval(3600))
        XCTAssertEqual(moved.start.timeIntervalSince1970, start.addingTimeInterval(3600).timeIntervalSince1970, accuracy: 1)

        // 真实库应不变（开始时间仍是原值）
        let checkReal = try await store.event(id: event.id)
        XCTAssertEqual(checkReal?.start.timeIntervalSince1970 ?? 0, start.timeIntervalSince1970, accuracy: 1, "dry-run 不应改真实库")

        // 同法验证提醒
        let realReminder = try await store.reminder(id: reminder.id)
        XCTAssertNotNil(realReminder)
        _ = try await memory.save(reminder: XCTUnwrap(realReminder))
        let edited = try await memoryService.editReminder(id: reminder.id, with: ReminderPatch(title: "[IT] dry-run 改"))
        XCTAssertEqual(edited.title, "[IT] dry-run 改")

        let checkRealReminder = try await store.reminder(id: reminder.id)
        XCTAssertEqual(checkRealReminder?.title, "[IT] dry-run 种子提醒", "dry-run 不应改真实库")
    }
}
