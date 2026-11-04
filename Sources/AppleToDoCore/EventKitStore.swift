import EventKit
import Foundation

/// EventKitStore 配置（ADR-0002：默认落点为 iCloud 账户专属日历/清单）。
public struct EventKitStoreConfig: Sendable {
    /// 事件默认写入的日历名。
    public var eventCalendarName = "AppleToDo"
    /// 提醒默认写入的清单名。
    public var reminderListName = "AppleToDo"

    public init() {}
}

/// EventKit 生产适配器：薄壳，只做协议转换（ADR-0005 决策 3；ADR-0001 唯一写入层）。
public actor EventKitStore: EventStoring {
    private let store = EKEventStore()
    private let config: EventKitStoreConfig
    private var calendarCache: [EKEntityType: EKCalendar] = [:]

    public init(config: EventKitStoreConfig = EventKitStoreConfig()) {
        self.config = config
    }

    /// 请求日历与提醒事项的完整权限（macOS 14+）；拒绝或失败抛 `accessDenied`。
    public func requestAccess() async throws {
        let granted: Bool
        do {
            let events = try await store.requestFullAccessToEvents()
            let reminders = try await store.requestFullAccessToReminders()
            granted = events && reminders
        } catch {
            throw ScheduleError.accessDenied
        }
        guard granted else { throw ScheduleError.accessDenied }
    }

    // MARK: - EventStoring（事件）

    public func events(in range: DateRange) throws -> [CalendarEvent] {
        let predicate = try store.predicateForEvents(withStart: range.start, end: range.end, calendars: [ensureCalendar(for: .event)])
        return store.events(matching: predicate).map(\.domain)
    }

    public func event(id: String) -> CalendarEvent? {
        store.event(withIdentifier: id)?.domain
    }

    @discardableResult
    public func save(event: CalendarEvent) throws -> CalendarEvent {
        let ekEvent = store.event(withIdentifier: event.id) ?? EKEvent(eventStore: store)
        ekEvent.calendar = try ensureCalendar(for: .event)
        ekEvent.title = event.title
        ekEvent.startDate = event.start
        ekEvent.endDate = event.end
        ekEvent.notes = event.notes
        try store.save(ekEvent, span: .thisEvent, commit: true)
        return ekEvent.domain
    }

    public func delete(eventID: String) throws {
        guard let ekEvent = store.event(withIdentifier: eventID) else {
            throw ScheduleError.notFound(id: eventID)
        }
        try store.remove(ekEvent, span: .thisEvent, commit: true)
    }

    // MARK: - EventStoring（提醒）

    public func reminders(includingCompleted: Bool) async throws -> [Reminder] {
        let predicate = try store.predicateForReminders(in: [ensureCalendar(for: .reminder)])
        let fetched = await fetchReminders(matching: predicate)
        let mapped: [Reminder] = fetched.map(\.domain)
        return mapped
            .filter { includingCompleted || !$0.isCompleted }
            .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
    }

    /// fetchReminders 无异步重载，用 continuation 包装（此 SDK 的 completion 为单参数版）。
    /// EKReminder 非 Sendable：数组仅在此 actor 内使用，跨隔离域转移用 nonisolated(unsafe) 标注。
    private func fetchReminders(matching predicate: NSPredicate) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            nonisolated(unsafe) let safeContinuation = continuation
            store.fetchReminders(matching: predicate) { reminders in
                nonisolated(unsafe) let result = reminders ?? []
                safeContinuation.resume(returning: result)
            }
        }
    }

    public func reminder(id: String) -> Reminder? {
        (store.calendarItem(withIdentifier: id) as? EKReminder)?.domain
    }

    @discardableResult
    public func save(reminder: Reminder) throws -> Reminder {
        let ekReminder = (store.calendarItem(withIdentifier: reminder.id) as? EKReminder) ?? EKReminder(eventStore: store)
        ekReminder.calendar = try ensureCalendar(for: .reminder)
        ekReminder.title = reminder.title
        ekReminder.notes = reminder.notes
        ekReminder.isCompleted = reminder.isCompleted
        if let due = reminder.due {
            ekReminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
        } else {
            ekReminder.dueDateComponents = nil
        }
        try store.save(ekReminder, commit: true)
        return ekReminder.domain
    }

    public func delete(reminderID: String) throws {
        guard let ekReminder = store.calendarItem(withIdentifier: reminderID) as? EKReminder else {
            throw ScheduleError.notFound(id: reminderID)
        }
        try store.remove(ekReminder, commit: true)
    }

    // MARK: - 目标日历/清单解析（ADR-0002：缺失则建，无源可写则报错）

    /// 按实体类型解析 iCloud 源。注意：事件与提醒的 iCloud 是**两个不同的 EKSource**
    /// （实测本机 id 不同），必须按目标类型的日历归属选源，否则提醒会落到事件源上。
    private func writableSource(for type: EKEntityType) -> EKSource? {
        let candidates = store.sources.filter {
            $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud")
        }
        let withWritableCalendars = candidates.first { source in
            store.calendars(for: type).contains {
                $0.source.sourceIdentifier == source.sourceIdentifier && $0.allowsContentModifications
            }
        }
        return withWritableCalendars ?? candidates.first
    }

    private func ensureCalendar(for type: EKEntityType) throws -> EKCalendar {
        if let cached = calendarCache[type] {
            return cached
        }
        guard let source = writableSource(for: type) else {
            throw ScheduleError.noWritableTarget(kind: kindName(of: type))
        }
        let name = type == .event ? config.eventCalendarName : config.reminderListName
        let found = store.calendars(for: type)
            .first { $0.source.sourceIdentifier == source.sourceIdentifier && $0.title == name }
        let calendar: EKCalendar = if let found {
            found
        } else {
            try createCalendar(title: name, for: type, in: source)
        }
        calendarCache[type] = calendar
        return calendar
    }

    private func createCalendar(title: String, for type: EKEntityType, in source: EKSource) throws -> EKCalendar {
        let calendar = EKCalendar(for: type, eventStore: store)
        calendar.title = title
        calendar.source = source
        do {
            try store.saveCalendar(calendar, commit: true)
        } catch {
            throw ScheduleError.noWritableTarget(kind: kindName(of: type))
        }
        return calendar
    }

    private func kindName(of type: EKEntityType) -> String {
        type == .event ? "event" : "reminder"
    }
}

// MARK: - EventKit → 领域映射

extension EKEvent {
    var domain: CalendarEvent {
        CalendarEvent(id: eventIdentifier ?? "", title: title ?? "", start: startDate, end: endDate, notes: notes)
    }
}

extension EKReminder {
    var domain: Reminder {
        let due = dueDateComponents.flatMap { Calendar.current.date(from: $0) }
        return Reminder(id: calendarItemIdentifier, title: title ?? "", due: due, notes: notes, isCompleted: isCompleted)
    }
}
