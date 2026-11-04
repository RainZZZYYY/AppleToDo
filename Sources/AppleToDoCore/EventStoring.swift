import Foundation

/// 存储端口：Core 与具体存储（EventKit / 内存）之间的契约（ADR-0003）。
/// 接口随 M2/M3 真实需求生长，不预设计。
public protocol EventStoring: Sendable {
    /// 查询范围内的事件（事件区间与范围相交即命中）。
    func events(in range: DateRange) async throws -> [CalendarEvent]
    /// 按 id 取事件；不存在返回 nil。
    func event(id: String) async throws -> CalendarEvent?
    /// 保存事件：id 已存在则更新，否则创建；返回落库后的规范实体（生产适配器以 EventKit 标识符为准）。
    @discardableResult
    func save(event: CalendarEvent) async throws -> CalendarEvent
    /// 删除事件。
    func delete(eventID: String) async throws
    /// 查询提醒事项（未指定顺序约定时按 due 升序、无 due 靠后）。
    func reminders(includingCompleted: Bool) async throws -> [Reminder]
    /// 按 id 取提醒；不存在返回 nil。
    func reminder(id: String) async throws -> Reminder?
    /// 保存提醒：id 已存在则更新，否则创建；返回落库后的规范实体。
    @discardableResult
    func save(reminder: Reminder) async throws -> Reminder
    /// 删除提醒。
    func delete(reminderID: String) async throws
}
