import Foundation

/// 领域编排：业务规则只在这里，适配器保持薄壳（ADR-0005 决策 3）。
public struct ScheduleService: Sendable {
    private let store: any EventStoring

    /// ADR-0002：自动创建条目的备注首行溯源标记。
    private static let notesTag = "[AppleToDo]"

    public init(store: any EventStoring) {
        self.store = store
    }

    // MARK: - 事件

    /// 新建事件（备注自动附溯源标记）。
    @discardableResult
    public func addEvent(title: String, start: Date, end: Date, notes: String? = nil) async throws -> CalendarEvent {
        guard start < end else { throw ScheduleError.invalidRange }
        let event = CalendarEvent(title: title, start: start, end: end, notes: Self.tagged(notes))
        return try await store.save(event: event)
    }

    /// 改期：移动到新起点，时长与备注保持不变。
    @discardableResult
    public func moveEvent(id: String, to newStart: Date) async throws -> CalendarEvent {
        guard let event = try await store.event(id: id) else {
            throw ScheduleError.notFound(id: id)
        }
        let duration = event.end.timeIntervalSince(event.start)
        let moved = CalendarEvent(id: event.id, title: event.title, start: newStart,
                                  end: newStart.addingTimeInterval(duration), notes: event.notes)
        return try await store.save(event: moved)
    }

    /// 查询范围内事件（按开始时间升序）。
    public func listEvents(in range: DateRange) async throws -> [CalendarEvent] {
        guard range.start <= range.end else { throw ScheduleError.invalidRange }
        return try await store.events(in: range)
    }

    /// 按 id 取事件；不存在返回 nil（agent 查重/确认用）。
    public func event(id: String) async throws -> CalendarEvent? {
        try await store.event(id: id)
    }

    /// 删除事件。
    public func deleteEvent(id: String) async throws {
        try await store.delete(eventID: id)
    }

    /// 编辑事件：仅应用补丁中的非 nil 字段；时长需为正，否则 invalidRange。
    @discardableResult
    public func editEvent(id: String, with patch: EventPatch) async throws -> CalendarEvent {
        guard let event = try await store.event(id: id) else {
            throw ScheduleError.notFound(id: id)
        }
        if let minutes = patch.durationMinutes, minutes <= 0 {
            throw ScheduleError.invalidRange
        }
        var updated = event
        if let title = patch.title {
            updated.title = title
        }
        if let notes = patch.notes {
            updated.notes = notes.isEmpty ? nil : Self.tagged(notes)
        }
        if let minutes = patch.durationMinutes {
            updated.end = updated.start.addingTimeInterval(Double(minutes) * 60)
        }
        return try await store.save(event: updated)
    }

    // MARK: - 提醒事项

    /// 新建提醒（备注自动附溯源标记）。
    @discardableResult
    public func addReminder(title: String, due: Date? = nil, notes: String? = nil) async throws -> Reminder {
        let reminder = Reminder(title: title, due: due, notes: Self.tagged(notes))
        return try await store.save(reminder: reminder)
    }

    /// 完成提醒。
    @discardableResult
    public func completeReminder(id: String) async throws -> Reminder {
        guard var reminder = try await store.reminder(id: id) else {
            throw ScheduleError.notFound(id: id)
        }
        reminder.isCompleted = true
        return try await store.save(reminder: reminder)
    }

    /// 查询提醒；`includingCompleted` 为 false 时只返回未完成项。
    public func listReminders(includingCompleted: Bool = false) async throws -> [Reminder] {
        try await store.reminders(includingCompleted: includingCompleted)
    }

    /// 按 id 取提醒；不存在返回 nil（agent 查重/确认用）。
    public func reminder(id: String) async throws -> Reminder? {
        try await store.reminder(id: id)
    }

    /// 编辑提醒：仅应用补丁中的非 nil 字段。
    @discardableResult
    public func editReminder(id: String, with patch: ReminderPatch) async throws -> Reminder {
        guard var reminder = try await store.reminder(id: id) else {
            throw ScheduleError.notFound(id: id)
        }
        if let title = patch.title {
            reminder.title = title
        }
        if let notes = patch.notes {
            reminder.notes = notes.isEmpty ? nil : Self.tagged(notes)
        }
        if case let .some(due) = patch.due {
            reminder.due = due
        }
        return try await store.save(reminder: reminder)
    }

    /// 删除提醒。
    public func deleteReminder(id: String) async throws {
        try await store.delete(reminderID: id)
    }

    // MARK: - 私有

    private static func tagged(_ notes: String?) -> String {
        guard let notes, !notes.isEmpty else { return notesTag }
        return notesTag + "\n" + notes
    }
}
