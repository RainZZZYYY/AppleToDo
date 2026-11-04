import Foundation

/// 内存实现：单测 mock 与未来 CLI dry-run 共用（ADR-0003）。
public actor InMemoryStore: EventStoring {
    private var events: [String: CalendarEvent] = [:]
    private var reminders: [String: Reminder] = [:]

    public init() {}

    public func events(in range: DateRange) -> [CalendarEvent] {
        events.values
            .filter { $0.start < range.end && $0.end > range.start }
            .sorted { $0.start < $1.start }
    }

    public func event(id: String) -> CalendarEvent? {
        events[id]
    }

    @discardableResult
    public func save(event: CalendarEvent) -> CalendarEvent {
        events[event.id] = event
        return event
    }

    public func delete(eventID: String) throws {
        guard events.removeValue(forKey: eventID) != nil else {
            throw ScheduleError.notFound(id: eventID)
        }
    }

    public func reminders(includingCompleted: Bool) -> [Reminder] {
        reminders.values
            .filter { includingCompleted || !$0.isCompleted }
            .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
    }

    public func reminder(id: String) -> Reminder? {
        reminders[id]
    }

    @discardableResult
    public func save(reminder: Reminder) -> Reminder {
        reminders[reminder.id] = reminder
        return reminder
    }

    public func delete(reminderID: String) throws {
        guard reminders.removeValue(forKey: reminderID) != nil else {
            throw ScheduleError.notFound(id: reminderID)
        }
    }
}
