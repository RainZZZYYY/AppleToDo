import AppleToDoCore
import ArgumentParser
import Foundation

@main
struct Appletodo: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "appletodo",
        abstract: "AppleToDo 个人日程 CLI：写入系统日历/提醒事项，经 iCloud 同步",
        version: AppleToDoCore.version,
        subcommands: [
            List.self, Today.self,
            AddEvent.self, AddReminder.self,
            Move.self, Complete.self,
            EditEvent.self, EditReminder.self,
            DeleteEvent.self, DeleteReminder.self
        ]
    )
}

// MARK: - 共用工具

enum CLI {
    /// 解析 `yyyy-MM-dd HH:mm` 或 `yyyy-MM-dd`（本地时区）。
    static func parseDate(_ string: String) throws -> Date {
        for format in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: string) {
                return date
            }
        }
        throw ValidationError("日期格式应为 'yyyy-MM-dd HH:mm' 或 'yyyy-MM-dd'，收到：\(string)")
    }

    /// 生产服务：EventKitStore（ADR-0002 默认落点）+ 权限请求。
    static func makeService() async throws -> ScheduleService {
        let store = EventKitStore()
        try await store.requestAccess()
        return ScheduleService(store: store)
    }

    static func jsonEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    /// Data → UTF-8 文本（编码产物必为合法 UTF-8）。
    static func text(_ data: Data) -> String {
        String(bytes: data, encoding: .utf8) ?? ""
    }

    /// 业务错误统一出口：人类可读消息或 `{"error":...}`，写到 stderr，退出码 1。
    static func exitFailure(_ error: ScheduleError, json: Bool) -> ExitCode {
        let message = "错误：\(describe(error))\n"
        let payload: Data = json ? (try? jsonEncoder().encode(ErrorOutput(error: error))) ?? Data() : Data(message.utf8)
        FileHandle.standardError.write(payload)
        if json {
            FileHandle.standardError.write(Data("\n".utf8))
        }
        return ExitCode.failure
    }

    static func describe(_ error: ScheduleError) -> String {
        switch error {
        case let .notFound(id): "条目不存在（id: \(id)）"
        case .invalidRange: "时间范围非法（如时长非正）"
        case .accessDenied: "未获得日历/提醒事项权限（系统设置 → 隐私与安全性 中授予）"
        case let .noWritableTarget(kind): "找不到可写入的\(kind == "event" ? "日历" : "提醒清单")"
        }
    }

    static func printDay(_ day: Date, events: [CalendarEvent], reminders: [Reminder]) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd EEEE"
        formatter.locale = Locale(identifier: "zh_CN")
        print("== \(formatter.string(from: day)) ==")
        if events.isEmpty, reminders.isEmpty {
            print("（无日程）")
            return
        }
        let time = DateFormatter()
        time.dateFormat = "HH:mm"
        for event in events {
            print("[事件] \(time.string(from: event.start))-\(time.string(from: event.end)) \(event.title)  id=\(event.id)")
        }
        for reminder in reminders {
            let due = reminder.due.map { " 截止\(time.string(from: $0))" } ?? ""
            print("[提醒] \(reminder.title)\(due)  id=\(reminder.id)")
        }
    }

    struct ErrorOutput: Codable {
        let error: ScheduleError
    }
}

// MARK: - 查询

struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "查看某天的日程与未完成提醒")

    @Option(help: "日期（yyyy-MM-dd），默认今天")
    var date: String?

    @Flag(help: "输出 JSON（供 agent/脚本消费）")
    var json = false

    struct Output: Codable {
        let date: Date
        let events: [CalendarEvent]
        let reminders: [Reminder]
    }

    mutating func run() async throws {
        let day = try date.map(CLI.parseDate) ?? Calendar.current.startOfDay(for: Date())
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        do {
            let service = try await CLI.makeService()
            let events = try await service.listEvents(in: DateRange(start: day, end: nextDay))
            let reminders = try await service.listReminders()
            if json {
                let data = try CLI.jsonEncoder().encode(Output(date: day, events: events, reminders: reminders))
                print(CLI.text(data))
            } else {
                CLI.printDay(day, events: events, reminders: reminders)
            }
        } catch let error as ScheduleError {
            throw CLI.exitFailure(error, json: json)
        }
    }
}

struct Today: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "今天的日程与未完成提醒（等价 list）")

    @Flag(help: "输出 JSON（供 agent/脚本消费）")
    var json = false

    mutating func run() async throws {
        var list = List()
        list.json = json
        try await list.run()
    }
}

// MARK: - 新增

struct AddEvent: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "新建日历事件")

    @Argument(help: "标题")
    var title: String

    @Option(name: .customLong("at"), help: "开始时间（yyyy-MM-dd HH:mm 或 yyyy-MM-dd，纯日期按 00:00）")
    var startTime: String

    @Option(help: "时长（分钟），默认 60")
    var duration: Int = 60

    @Option(help: "备注")
    var notes: String?

    @Flag(help: "输出 JSON")
    var json = false

    mutating func run() async throws {
        let start = try CLI.parseDate(startTime)
        do {
            let service = try await CLI.makeService()
            let event = try await service.addEvent(title: title, start: start,
                                                   end: start.addingTimeInterval(Double(duration) * 60), notes: notes)
            try CLI.emit(event, human: "已创建事件", json: json)
        } catch let error as ScheduleError {
            throw CLI.exitFailure(error, json: json)
        }
    }
}

struct AddReminder: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "新建提醒事项")

    @Argument(help: "标题")
    var title: String

    @Option(help: "截止时间（yyyy-MM-dd HH:mm 或 yyyy-MM-dd），可省略")
    var due: String?

    @Option(help: "备注")
    var notes: String?

    @Flag(help: "输出 JSON")
    var json = false

    mutating func run() async throws {
        let dueDate = try due.map(CLI.parseDate)
        do {
            let service = try await CLI.makeService()
            let reminder = try await service.addReminder(title: title, due: dueDate, notes: notes)
            try CLI.emit(reminder, human: "已创建提醒", json: json)
        } catch let error as ScheduleError {
            throw CLI.exitFailure(error, json: json)
        }
    }
}

// MARK: - 变更

struct Move: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "事件改期（保持时长）")

    @Argument(help: "事件 id")
    var id: String

    @Option(name: .customLong("at"), help: "新的开始时间（yyyy-MM-dd HH:mm 或 yyyy-MM-dd，纯日期按 00:00）")
    var newStart: String

    @Flag(help: "输出 JSON")
    var json = false

    mutating func run() async throws {
        let target = try CLI.parseDate(newStart)
        do {
            let service = try await CLI.makeService()
            let event = try await service.moveEvent(id: id, to: target)
            try CLI.emit(event, human: "已改期", json: json)
        } catch let error as ScheduleError {
            throw CLI.exitFailure(error, json: json)
        }
    }
}

struct Complete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "完成提醒")

    @Argument(help: "提醒 id")
    var id: String

    @Flag(help: "输出 JSON")
    var json = false

    mutating func run() async throws {
        do {
            let service = try await CLI.makeService()
            let reminder = try await service.completeReminder(id: id)
            try CLI.emit(reminder, human: "已完成", json: json)
        } catch let error as ScheduleError {
            throw CLI.exitFailure(error, json: json)
        }
    }
}

struct EditEvent: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "编辑事件字段（未传的保持不变）")

    @Argument(help: "事件 id")
    var id: String

    @Option(help: "新标题")
    var title: String?

    @Option(help: "新备注（传空串 \"\" 表示清空）")
    var notes: String?

    @Option(help: "新时长（分钟，需为正）")
    var duration: Int?

    @Flag(help: "输出 JSON")
    var json = false

    mutating func run() async throws {
        let patch = EventPatch(title: title, notes: notes, durationMinutes: duration)
        do {
            let service = try await CLI.makeService()
            let event = try await service.editEvent(id: id, with: patch)
            try CLI.emit(event, human: "已编辑事件", json: json)
        } catch let error as ScheduleError {
            throw CLI.exitFailure(error, json: json)
        }
    }
}

struct EditReminder: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "编辑提醒字段（未传的保持不变）")

    @Argument(help: "提醒 id")
    var id: String

    @Option(help: "新标题")
    var title: String?

    @Option(help: "新备注（传空串 \"\" 表示清空）")
    var notes: String?

    @Option(help: "新截止时间（yyyy-MM-dd HH:mm 或 yyyy-MM-dd）")
    var due: String?

    @Flag(help: "清除截止时间（与 --due 互斥）")
    var noDue = false

    @Flag(help: "输出 JSON")
    var json = false

    mutating func run() async throws {
        if noDue, due != nil {
            throw ValidationError("--no-due 与 --due 不能同时使用")
        }
        let dueValue: Date?? = noDue ? .some(nil) : try due.map { try .some(CLI.parseDate($0)) }
        let patch = ReminderPatch(title: title, notes: notes, due: dueValue)
        do {
            let service = try await CLI.makeService()
            let reminder = try await service.editReminder(id: id, with: patch)
            try CLI.emit(reminder, human: "已编辑提醒", json: json)
        } catch let error as ScheduleError {
            throw CLI.exitFailure(error, json: json)
        }
    }
}

struct DeleteEvent: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "删除事件")

    @Argument(help: "事件 id")
    var id: String

    @Flag(help: "输出 JSON")
    var json = false

    mutating func run() async throws {
        do {
            let service = try await CLI.makeService()
            try await service.deleteEvent(id: id)
            if json {
                print(#"{"deleted": "\#(id)"}"#)
            } else {
                print("已删除事件 \(id)")
            }
        } catch let error as ScheduleError {
            throw CLI.exitFailure(error, json: json)
        }
    }
}

struct DeleteReminder: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "删除提醒")

    @Argument(help: "提醒 id")
    var id: String

    @Flag(help: "输出 JSON")
    var json = false

    mutating func run() async throws {
        do {
            let service = try await CLI.makeService()
            try await service.deleteReminder(id: id)
            if json {
                print(#"{"deleted": "\#(id)"}"#)
            } else {
                print("已删除提醒 \(id)")
            }
        } catch let error as ScheduleError {
            throw CLI.exitFailure(error, json: json)
        }
    }
}

// MARK: - 输出

extension CLI {
    /// 变更类命令的统一输出：人类可读一行（含 id）或完整 JSON 实体。
    static func emit(_ value: some Codable, human: String, json: Bool) throws {
        if json {
            let data = try jsonEncoder().encode(value)
            print(text(data))
        } else if let event = value as? CalendarEvent {
            print("\(human)：\(event.title)  id=\(event.id)")
        } else if let reminder = value as? Reminder {
            print("\(human)：\(reminder.title)  id=\(reminder.id)")
        } else {
            print(human)
        }
    }
}
