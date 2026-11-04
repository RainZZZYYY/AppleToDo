import Foundation

/// 日历事件的领域视图（与 EventKit 解耦；ADR-0005 工具形状：Codable 值类型）。
public struct CalendarEvent: Equatable, Codable, Sendable {
    public let id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var notes: String?

    public init(id: String = UUID().uuidString, title: String, start: Date, end: Date, notes: String? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.notes = notes
    }
}

/// 提醒事项的领域视图。
public struct Reminder: Equatable, Codable, Sendable {
    public let id: String
    public var title: String
    public var due: Date?
    public var notes: String?
    public var isCompleted: Bool

    public init(id: String = UUID().uuidString, title: String, due: Date? = nil, notes: String? = nil, isCompleted: Bool = false) {
        self.id = id
        self.title = title
        self.due = due
        self.notes = notes
        self.isCompleted = isCompleted
    }
}

/// 时间查询范围。
public struct DateRange: Equatable, Codable, Sendable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    /// 覆盖全部时间的范围（全量查询与测试用）。
    public static let forever = DateRange(start: .distantPast, end: .distantFuture)
}

/// 领域错误：作为数据返回（可编码、语义稳定），ADR-0005「错误即数据」。
public enum ScheduleError: Error, Equatable, Codable, Sendable {
    /// 指定 id 的条目不存在。
    case notFound(id: String)
    /// 时间范围非法（start > end，或事件时长非正）。
    case invalidRange
    /// 用户未授予日历/提醒事项权限。
    case accessDenied
    /// 找不到可写入的日历/清单（kind 为 "event" 或 "reminder"）。
    case noWritableTarget(kind: String)
}
