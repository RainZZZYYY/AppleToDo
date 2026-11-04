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
}
