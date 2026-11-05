@testable import AppleToDoCore
import XCTest

final class ScheduleServiceTests: XCTestCase {
    private var service: ScheduleService!

    override func setUp() {
        super.setUp()
        service = ScheduleService(store: InMemoryStore())
    }

    // MARK: - 事件

    func testAddEventAppliesNotesTag() async throws {
        let start = Date(timeIntervalSince1970: 1000)
        let event = try await service.addEvent(title: "牙医", start: start, end: start.addingTimeInterval(3600), notes: "带病历本")
        XCTAssertEqual(event.notes, "[AppleToDo]\n带病历本")
        let listed = try await service.listEvents(in: .forever)
        XCTAssertEqual(listed.map(\.id), [event.id])
    }

    func testAddEventWithoutNotesStillTagged() async throws {
        let start = Date(timeIntervalSince1970: 1000)
        let event = try await service.addEvent(title: "周会", start: start, end: start.addingTimeInterval(1800))
        XCTAssertEqual(event.notes, "[AppleToDo]")
    }

    func testAddEventRejectsNonPositiveDuration() async {
        let moment = Date(timeIntervalSince1970: 1000)
        do {
            _ = try await service.addEvent(title: "零时长", start: moment, end: moment)
            XCTFail("应当抛出 invalidRange")
        } catch let error as ScheduleError {
            XCTAssertEqual(error, .invalidRange)
        } catch {
            XCTFail("意外错误类型: \(error)")
        }
    }

    func testMoveEventKeepsDurationAndNotes() async throws {
        let start = Date(timeIntervalSince1970: 1000)
        let event = try await service.addEvent(title: "健身", start: start, end: start.addingTimeInterval(5400))
        let newStart = Date(timeIntervalSince1970: 999_999)
        let moved = try await service.moveEvent(id: event.id, to: newStart)
        XCTAssertEqual(moved.start, newStart)
        XCTAssertEqual(moved.end.timeIntervalSince(moved.start), 5400, accuracy: 0.001)
        XCTAssertEqual(moved.notes, event.notes)
    }

    func testMoveUnknownEventThrowsNotFound() async {
        do {
            _ = try await service.moveEvent(id: "missing", to: Date(timeIntervalSince1970: 0))
            XCTFail("应当抛出 notFound")
        } catch let error as ScheduleError {
            XCTAssertEqual(error, .notFound(id: "missing"))
        } catch {
            XCTFail("意外错误类型: \(error)")
        }
    }

    func testListEventsRejectsInvertedRange() async {
        do {
            _ = try await service.listEvents(in: DateRange(start: Date(timeIntervalSince1970: 10), end: Date(timeIntervalSince1970: 0)))
            XCTFail("应当抛出 invalidRange")
        } catch let error as ScheduleError {
            XCTAssertEqual(error, .invalidRange)
        } catch {
            XCTFail("意外错误类型: \(error)")
        }
    }

    func testDeleteEventThenAgainThrows() async throws {
        let moment = Date(timeIntervalSince1970: 1000)
        let event = try await service.addEvent(title: "临时", start: moment, end: moment.addingTimeInterval(60))
        try await service.deleteEvent(id: event.id)
        do {
            try await service.deleteEvent(id: event.id)
            XCTFail("应当抛出 notFound")
        } catch let error as ScheduleError {
            XCTAssertEqual(error, .notFound(id: event.id))
        }
    }

    // MARK: - 提醒事项

    func testAddAndCompleteReminder() async throws {
        let due = Date(timeIntervalSince1970: 5000)
        let reminder = try await service.addReminder(title: "买书", due: due)
        XCTAssertEqual(reminder.notes, "[AppleToDo]", "提醒也应带 ADR-0002 溯源标记")
        let completed = try await service.completeReminder(id: reminder.id)
        XCTAssertTrue(completed.isCompleted)
        let open = try await service.listReminders()
        XCTAssertTrue(open.isEmpty, "已完成项不应出现在默认列表")
        let all = try await service.listReminders(includingCompleted: true)
        XCTAssertEqual(all.map(\.id), [reminder.id])
    }

    func testCompleteUnknownReminderThrowsNotFound() async {
        do {
            _ = try await service.completeReminder(id: "missing")
            XCTFail("应当抛出 notFound")
        } catch let error as ScheduleError {
            XCTAssertEqual(error, .notFound(id: "missing"))
        } catch {
            XCTFail("意外错误类型: \(error)")
        }
    }
}

/// 存储端口语义：范围相交判定与按 id 存取。
final class InMemoryStoreTests: XCTestCase {
    func testEventsOverlapFiltering() async throws {
        let store = InMemoryStore()
        // 事件 [10, 20) 与 [30, 40)
        let earlyEvent = CalendarEvent(title: "a", start: Date(timeIntervalSince1970: 10), end: Date(timeIntervalSince1970: 20))
        let lateEvent = CalendarEvent(title: "b", start: Date(timeIntervalSince1970: 30), end: Date(timeIntervalSince1970: 40))
        try await store.save(event: earlyEvent)
        try await store.save(event: lateEvent)

        // 相交命中；恰好接壤（查询 [20,30)）不算相交
        let hit = try await store.events(in: DateRange(start: Date(timeIntervalSince1970: 15), end: Date(timeIntervalSince1970: 25)))
        XCTAssertEqual(hit.map(\.id), [earlyEvent.id])
        let touching = try await store.events(in: DateRange(start: Date(timeIntervalSince1970: 20), end: Date(timeIntervalSince1970: 30)))
        XCTAssertTrue(touching.isEmpty)
    }

    func testRemindersSortedByDueWithNilLast() async throws {
        let store = InMemoryStore()
        let late = Reminder(title: "晚", due: Date(timeIntervalSince1970: 200))
        let nilDue = Reminder(title: "无期限")
        let early = Reminder(title: "早", due: Date(timeIntervalSince1970: 100))
        try await store.save(reminder: late)
        try await store.save(reminder: nilDue)
        try await store.save(reminder: early)
        let listed = try await store.reminders(includingCompleted: true)
        XCTAssertEqual(listed.map(\.title), ["早", "晚", "无期限"])
    }

    func testDeleteReminderThenAgainThrows() async throws {
        let store = InMemoryStore()
        let saved = try await store.save(reminder: Reminder(title: "待删"))
        try await store.delete(reminderID: saved.id)
        let gone = try await store.reminder(id: saved.id)
        XCTAssertNil(gone)
        do {
            try await store.delete(reminderID: saved.id)
            XCTFail("应当抛出 notFound")
        } catch let error as ScheduleError {
            XCTAssertEqual(error, .notFound(id: saved.id))
        } catch {
            XCTFail("意外错误类型: \(error)")
        }
    }
}

/// ADR-0005 工具形状：领域类型可 JSON 往返。
final class DomainCodableTests: XCTestCase {
    func testEventAndReminderRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let event = CalendarEvent(title: "t", start: Date(timeIntervalSince1970: 1), end: Date(timeIntervalSince1970: 2), notes: "n")
        XCTAssertEqual(try decoder.decode(CalendarEvent.self, from: encoder.encode(event)), event)
        let reminder = Reminder(title: "r", due: Date(timeIntervalSince1970: 3), notes: nil, isCompleted: true)
        XCTAssertEqual(try decoder.decode(Reminder.self, from: encoder.encode(reminder)), reminder)
        let range = DateRange(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 9))
        XCTAssertEqual(try decoder.decode(DateRange.self, from: encoder.encode(range)), range)
    }

    func testScheduleErrorCodable() throws {
        let error = ScheduleError.notFound(id: "abc")
        let data = try JSONEncoder().encode(error)
        XCTAssertEqual(try JSONDecoder().decode(ScheduleError.self, from: data), error)
    }

    func testReminderPatchDistinguishesMissingAndNullDue() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // 字段缺失 → nil（不变）
        let missing = try decoder.decode(ReminderPatch.self, from: Data(#"{"title":"t"}"#.utf8))
        XCTAssertNil(missing.due)

        // "due": null → .some(nil)（清除）
        let nullDue = try decoder.decode(ReminderPatch.self, from: Data(#"{"due":null}"#.utf8))
        XCTAssertEqual(nullDue.due, .some(nil))

        // 有值 → .some(date)；编码往返保持三态
        let date = Date(timeIntervalSince1970: 42)
        let roundTrip = try decoder.decode(ReminderPatch.self, from: encoder.encode(ReminderPatch(due: .some(date))))
        XCTAssertEqual(roundTrip.due, .some(date))
        let clearedRoundTrip = try decoder.decode(ReminderPatch.self, from: encoder.encode(ReminderPatch(due: .some(nil))))
        XCTAssertEqual(clearedRoundTrip.due, .some(nil))
    }
}

/// 补丁语义：edit / delete 服务层操作。
final class ServiceEditTests: XCTestCase {
    private var service: ScheduleService!

    override func setUp() {
        super.setUp()
        service = ScheduleService(store: InMemoryStore())
    }

    func testEditEventAppliesOnlyProvidedFields() async throws {
        let start = Date(timeIntervalSince1970: 1000)
        let event = try await service.addEvent(title: "旧标题", start: start, end: start.addingTimeInterval(3600), notes: "旧备注")
        let edited = try await service.editEvent(id: event.id, with: EventPatch(title: "新标题", notes: nil, durationMinutes: 90))
        XCTAssertEqual(edited.title, "新标题")
        XCTAssertEqual(edited.notes, "[AppleToDo]\n旧备注", "notes 未传应保持不变")
        XCTAssertEqual(edited.end.timeIntervalSince(edited.start), 5400, accuracy: 0.001)
    }

    func testEditEventEmptyNotesClears() async throws {
        let start = Date(timeIntervalSince1970: 1000)
        let event = try await service.addEvent(title: "带备注", start: start, end: start.addingTimeInterval(3600), notes: "内容")
        let edited = try await service.editEvent(id: event.id, with: EventPatch(notes: ""))
        XCTAssertNil(edited.notes)
    }

    func testEditEventRejectsNonPositiveDuration() async throws {
        let start = Date(timeIntervalSince1970: 1000)
        let event = try await service.addEvent(title: "x", start: start, end: start.addingTimeInterval(60))
        do {
            _ = try await service.editEvent(id: event.id, with: EventPatch(durationMinutes: 0))
            XCTFail("应当抛出 invalidRange")
        } catch let error as ScheduleError {
            XCTAssertEqual(error, .invalidRange)
        } catch {
            XCTFail("意外错误类型: \(error)")
        }
    }

    func testEditUnknownEventThrowsNotFound() async {
        do {
            _ = try await service.editEvent(id: "missing", with: EventPatch(title: "t"))
            XCTFail("应当抛出 notFound")
        } catch let error as ScheduleError {
            XCTAssertEqual(error, .notFound(id: "missing"))
        } catch {
            XCTFail("意外错误类型: \(error)")
        }
    }

    func testEditReminderDueThreeSemantics() async throws {
        let originalDue = Date(timeIntervalSince1970: 5000)
        let reminder = try await service.addReminder(title: "r", due: originalDue)

        // nil = 不变
        var edited = try await service.editReminder(id: reminder.id, with: ReminderPatch(title: "改名"))
        XCTAssertEqual(edited.title, "改名")
        XCTAssertEqual(edited.due, originalDue)

        // .some(date) = 设置新值
        let newDue = Date(timeIntervalSince1970: 9999)
        edited = try await service.editReminder(id: reminder.id, with: ReminderPatch(due: .some(newDue)))
        XCTAssertEqual(edited.due, newDue)

        // .some(nil) = 清除
        edited = try await service.editReminder(id: reminder.id, with: ReminderPatch(due: .some(nil)))
        XCTAssertNil(edited.due)
    }

    func testEditReminderNotesClearAndNotFound() async throws {
        let reminder = try await service.addReminder(title: "r", notes: "备注")
        let cleared = try await service.editReminder(id: reminder.id, with: ReminderPatch(notes: ""))
        XCTAssertNil(cleared.notes, "空字符串应清空备注")

        let retagged = try await service.editReminder(id: reminder.id, with: ReminderPatch(notes: "新内容"))
        XCTAssertEqual(retagged.notes, "[AppleToDo]\n新内容", "非空备注编辑应重打 ADR-0002 标记")

        do {
            _ = try await service.editReminder(id: "missing", with: ReminderPatch(title: "t"))
            XCTFail("应当抛出 notFound")
        } catch let error as ScheduleError {
            XCTAssertEqual(error, .notFound(id: "missing"))
        } catch {
            XCTFail("意外错误类型: \(error)")
        }
    }

    func testDeleteReminderViaService() async throws {
        let reminder = try await service.addReminder(title: "待删提醒")
        try await service.deleteReminder(id: reminder.id)
        let all = try await service.listReminders(includingCompleted: true)
        XCTAssertTrue(all.isEmpty)
        do {
            try await service.deleteReminder(id: reminder.id)
            XCTFail("应当抛出 notFound")
        } catch let error as ScheduleError {
            XCTAssertEqual(error, .notFound(id: reminder.id))
        } catch {
            XCTFail("意外错误类型: \(error)")
        }
    }

    func testServiceGettersById() async throws {
        let start = Date(timeIntervalSince1970: 1000)
        let event = try await service.addEvent(title: "查我", start: start, end: start.addingTimeInterval(600))
        let reminder = try await service.addReminder(title: "查提醒")
        let fetchedEvent = try await service.event(id: event.id)
        XCTAssertEqual(fetchedEvent?.id, event.id)
        let fetchedReminder = try await service.reminder(id: reminder.id)
        XCTAssertEqual(fetchedReminder?.id, reminder.id)
        let missingEvent = try await service.event(id: "missing")
        XCTAssertNil(missingEvent)
        let missingReminder = try await service.reminder(id: "missing")
        XCTAssertNil(missingReminder)
    }
}
