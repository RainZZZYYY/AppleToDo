import EventKit
import Foundation
import os

/// EventKitStore 配置（ADR-0002：默认落点为 iCloud 账户专属日历/清单）。
public struct EventKitStoreConfig: Sendable {
    /// 事件默认写入的日历名。
    public var eventCalendarName = "AppleToDo"
    /// 提醒默认写入的清单名。
    public var reminderListName = "AppleToDo"

    public init() {}
}

/// EventKit 生产适配器：薄壳，只做协议转换（ADR-0005 决策 3；ADR-0001 唯一写入层）。
/// os.Logger 留审计线索（subsystem `com.appletodo`），不进正常输出（NAN-160）。
public actor EventKitStore: EventStoring {
    private let store = EKEventStore()
    private let config: EventKitStoreConfig
    private var calendarCache: [EKEntityType: EKCalendar] = [:]
    private let log = Logger(subsystem: "com.appletodo", category: "store")

    public init(config: EventKitStoreConfig = EventKitStoreConfig()) {
        self.config = config
    }

    /// 请求日历与提醒事项的完整权限（macOS 14+）；拒绝或失败抛 `accessDenied`。
    public func requestAccess() async throws {
        // EKEventStore 非 Sendable 且仅在本 actor 内使用；传入系统非隔离 async 方法时
        // 用 nonisolated(unsafe) 显式豁免发送检查（CI 工具链比本机更严格，会拦下隐式发送）。
        nonisolated(unsafe) let store = store
        let granted: Bool
        do {
            let events = try await store.requestFullAccessToEvents()
            let reminders = try await store.requestFullAccessToReminders()
            granted = events && reminders
        } catch {
            log.error("权限请求失败：\(error.localizedDescription, privacy: .public)")
            throw ScheduleError.accessDenied
        }
        guard granted else {
            log.error("权限被拒绝（events/reminders 未全授予）")
            throw ScheduleError.accessDenied
        }
        log.notice("权限已授予（日历+提醒事项）")
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
        ekEvent.title = event.title
        ekEvent.startDate = event.start
        ekEvent.endDate = event.end
        ekEvent.notes = event.notes
        do {
            ekEvent.calendar = try ensureCalendar(for: .event)
            try store.save(ekEvent, span: .thisEvent, commit: true)
        } catch {
            log.warning("事件保存首次失败 id=\(event.id, privacy: .public)：\(error.localizedDescription, privacy: .public)——清缓存重试")
            calendarCache.removeValue(forKey: .event)
            do {
                ekEvent.calendar = try ensureCalendar(for: .event)
                try store.save(ekEvent, span: .thisEvent, commit: true)
            } catch {
                log.error("事件保存失败（自愈后仍失败）id=\(event.id, privacy: .public)：\(error.localizedDescription, privacy: .public)")
                throw ScheduleError.noWritableTarget(kind: "event")
            }
        }
        log.notice("事件已保存 id=\(ekEvent.eventIdentifier ?? event.id, privacy: .public) 标题=\(event.title, privacy: .private)")
        return ekEvent.domain
    }

    public func delete(eventID: String) throws {
        guard let ekEvent = store.event(withIdentifier: eventID) else {
            log.warning("删除未命中（事件）id=\(eventID, privacy: .public)")
            throw ScheduleError.notFound(id: eventID)
        }
        do {
            try store.remove(ekEvent, span: .thisEvent, commit: true)
        } catch {
            log.error("事件删除失败 id=\(eventID, privacy: .public)：\(error.localizedDescription, privacy: .public)")
            throw error
        }
        log.notice("事件已删除 id=\(eventID, privacy: .public)")
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
            store.fetchReminders(matching: predicate) { reminders in
                nonisolated(unsafe) let result = reminders ?? []
                continuation.resume(returning: result)
            }
        }
    }

    public func reminder(id: String) -> Reminder? {
        (store.calendarItem(withIdentifier: id) as? EKReminder)?.domain
    }

    @discardableResult
    public func save(reminder: Reminder) throws -> Reminder {
        let ekReminder = (store.calendarItem(withIdentifier: reminder.id) as? EKReminder) ?? EKReminder(eventStore: store)
        ekReminder.title = reminder.title
        ekReminder.notes = reminder.notes
        ekReminder.isCompleted = reminder.isCompleted
        if let due = reminder.due {
            ekReminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
        } else {
            ekReminder.dueDateComponents = nil
        }
        do {
            ekReminder.calendar = try ensureCalendar(for: .reminder)
            try store.save(ekReminder, commit: true)
        } catch {
            log.warning("提醒保存首次失败 id=\(reminder.id, privacy: .public)：\(error.localizedDescription, privacy: .public)——清缓存重试")
            calendarCache.removeValue(forKey: .reminder)
            do {
                ekReminder.calendar = try ensureCalendar(for: .reminder)
                try store.save(ekReminder, commit: true)
            } catch {
                log.error("提醒保存失败（自愈后仍失败）id=\(reminder.id, privacy: .public)：\(error.localizedDescription, privacy: .public)")
                throw ScheduleError.noWritableTarget(kind: "reminder")
            }
        }
        log.notice("提醒已保存 id=\(ekReminder.calendarItemIdentifier, privacy: .public) 标题=\(reminder.title, privacy: .private)")
        return ekReminder.domain
    }

    public func delete(reminderID: String) throws {
        guard let ekReminder = store.calendarItem(withIdentifier: reminderID) as? EKReminder else {
            log.warning("删除未命中（提醒）id=\(reminderID, privacy: .public)")
            throw ScheduleError.notFound(id: reminderID)
        }
        do {
            try store.remove(ekReminder, commit: true)
        } catch {
            log.error("提醒删除失败 id=\(reminderID, privacy: .public)：\(error.localizedDescription, privacy: .public)")
            throw error
        }
        log.notice("提醒已删除 id=\(reminderID, privacy: .public)")
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
        let kind = kindName(of: type)
        guard let source = writableSource(for: type) else {
            log.error("无可写源 kind=\(kind, privacy: .public)——iCloud CalDAV 未找到或无权限")
            throw ScheduleError.noWritableTarget(kind: kind)
        }
        let name = type == .event ? config.eventCalendarName : config.reminderListName
        let found = store.calendars(for: type)
            .first { $0.source.sourceIdentifier == source.sourceIdentifier && $0.title == name }
        let calendar: EKCalendar
        if let found {
            log.notice("目标日历命中 kind=\(kind, privacy: .public) name=\(name, privacy: .public)")
            calendar = found
        } else {
            calendar = try createCalendar(title: name, for: type, in: source)
        }
        calendarCache[type] = calendar
        return calendar
    }

    private func createCalendar(title: String, for type: EKEntityType, in source: EKSource) throws -> EKCalendar {
        let kind = kindName(of: type)
        let calendar = EKCalendar(for: type, eventStore: store)
        calendar.title = title
        calendar.source = source
        do {
            try store.saveCalendar(calendar, commit: true)
        } catch {
            let reason = error.localizedDescription
            log.error("日历/清单创建失败 kind=\(kind, privacy: .public) name=\(title, privacy: .public)：\(reason, privacy: .public)")
            throw ScheduleError.noWritableTarget(kind: kind)
        }
        log.notice("日历/清单已创建 kind=\(kind, privacy: .public) name=\(title, privacy: .public)")
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
