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
}
