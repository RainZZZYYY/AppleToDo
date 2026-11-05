import AppleToDoCore
import ArgumentParser
import Foundation

// MARK: - 查询

struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "查看某天的日程与未完成提醒")

    @Option(help: "日期（yyyy-MM-dd），默认今天")
    var date: String?

    @Flag(help: "输出 JSON（供 agent/脚本消费）")
    var json = false

    mutating func run() async throws {
        try await CLI.runList(dateString: date, json: json)
    }
}

struct Today: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "今天的日程与未完成提醒（等价 list）")

    @Flag(help: "输出 JSON（供 agent/脚本消费）")
    var json = false

    mutating func run() async throws {
        try await CLI.runList(dateString: nil, json: json)
    }
}

extension CLI {
    struct DayOutput: Codable {
        let date: Date
        let events: [CalendarEvent]
        let reminders: [Reminder]
    }

    /// list/today 的共享实现（Today 不能直接构造 List——属性包装器的值仅来自命令行解析）。
    static func runList(dateString: String?, json: Bool) async throws {
        let day = try dateString.map(CLI.parseDate) ?? Calendar.current.startOfDay(for: Date())
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        do {
            let service = try await CLI.makeService()
            let events = try await service.listEvents(in: DateRange(start: day, end: nextDay))
            let reminders = try await service.listReminders()
            if json {
                let data = try CLI.jsonEncoder().encode(DayOutput(date: day, events: events, reminders: reminders))
                print(CLI.text(data))
            } else {
                CLI.printDay(day, events: events, reminders: reminders)
            }
        } catch let error as ScheduleError {
            throw CLI.exitFailure(error, json: json)
        }
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

    @Flag(help: "演练：只展示将发生什么，不实际写入")
    var dryRun = false

    @Flag(help: "输出 JSON")
    var json = false

    mutating func run() async throws {
        let start = try CLI.parseDate(startTime)
        do {
            let service = try await (dryRun ? CLI.dryRunService() : CLI.makeService())
            let event = try await service.addEvent(title: title, start: start,
                                                   end: start.addingTimeInterval(Double(duration) * 60), notes: notes)
            try CLI.emit(event, human: dryRun ? "将创建事件" : "已创建事件", json: json, dryRun: dryRun)
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

    @Flag(help: "演练：只展示将发生什么，不实际写入")
    var dryRun = false

    @Flag(help: "输出 JSON")
    var json = false

    mutating func run() async throws {
        let dueDate = try due.map(CLI.parseDate)
        do {
            let service = try await (dryRun ? CLI.dryRunService() : CLI.makeService())
            let reminder = try await service.addReminder(title: title, due: dueDate, notes: notes)
            try CLI.emit(reminder, human: dryRun ? "将创建提醒" : "已创建提醒", json: json, dryRun: dryRun)
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

    @Flag(help: "演练：只展示将发生什么，不实际写入")
    var dryRun = false

    @Flag(help: "输出 JSON")
    var json = false

    mutating func run() async throws {
        let target = try CLI.parseDate(newStart)
        do {
            let service = try await (dryRun ? CLI.dryRunService(seedEventID: id) : CLI.makeService())
            let event = try await service.moveEvent(id: id, to: target)
            try CLI.emit(event, human: dryRun ? "将改期" : "已改期", json: json, dryRun: dryRun)
        } catch let error as ScheduleError {
            throw CLI.exitFailure(error, json: json)
        }
    }
}

struct Complete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "完成提醒")

    @Argument(help: "提醒 id")
    var id: String

    @Flag(help: "演练：只展示将发生什么，不实际写入")
    var dryRun = false

    @Flag(help: "输出 JSON")
    var json = false

    mutating func run() async throws {
        do {
            let service = try await (dryRun ? CLI.dryRunService(seedReminderID: id) : CLI.makeService())
            let reminder = try await service.completeReminder(id: id)
            try CLI.emit(reminder, human: dryRun ? "将完成" : "已完成", json: json, dryRun: dryRun)
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

    @Flag(help: "演练：只展示将发生什么，不实际写入")
    var dryRun = false

    @Flag(help: "输出 JSON")
    var json = false

    mutating func run() async throws {
        let patch = EventPatch(title: title, notes: notes, durationMinutes: duration)
        do {
            let service = try await (dryRun ? CLI.dryRunService(seedEventID: id) : CLI.makeService())
            let event = try await service.editEvent(id: id, with: patch)
            try CLI.emit(event, human: dryRun ? "将编辑事件" : "已编辑事件", json: json, dryRun: dryRun)
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

    @Flag(help: "演练：只展示将发生什么，不实际写入")
    var dryRun = false

    @Flag(help: "输出 JSON")
    var json = false

    mutating func run() async throws {
        if noDue, due != nil {
            throw ValidationError("--no-due 与 --due 不能同时使用")
        }
        let dueValue: Date?? = noDue ? .some(nil) : try due.map { try .some(CLI.parseDate($0)) }
        let patch = ReminderPatch(title: title, notes: notes, due: dueValue)
        do {
            let service = try await (dryRun ? CLI.dryRunService(seedReminderID: id) : CLI.makeService())
            let reminder = try await service.editReminder(id: id, with: patch)
            try CLI.emit(reminder, human: dryRun ? "将编辑提醒" : "已编辑提醒", json: json, dryRun: dryRun)
        } catch let error as ScheduleError {
            throw CLI.exitFailure(error, json: json)
        }
    }
}

struct DeleteEvent: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "删除事件")

    @Argument(help: "事件 id")
    var id: String

    @Flag(help: "演练：只展示将发生什么，不实际写入")
    var dryRun = false

    @Flag(help: "输出 JSON")
    var json = false

    mutating func run() async throws {
        do {
            let service = try await (dryRun ? CLI.dryRunService(seedEventID: id) : CLI.makeService())
            try await service.deleteEvent(id: id)
            CLI.emitDeleted(id: id, kind: "事件", json: json, dryRun: dryRun)
        } catch let error as ScheduleError {
            throw CLI.exitFailure(error, json: json)
        }
    }
}

struct DeleteReminder: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "删除提醒")

    @Argument(help: "提醒 id")
    var id: String

    @Flag(help: "演练：只展示将发生什么，不实际写入")
    var dryRun = false

    @Flag(help: "输出 JSON")
    var json = false

    mutating func run() async throws {
        do {
            let service = try await (dryRun ? CLI.dryRunService(seedReminderID: id) : CLI.makeService())
            try await service.deleteReminder(id: id)
            CLI.emitDeleted(id: id, kind: "提醒", json: json, dryRun: dryRun)
        } catch let error as ScheduleError {
            throw CLI.exitFailure(error, json: json)
        }
    }
}

// MARK: - 输出

extension CLI {
    /// 变更类命令的统一输出：人类可读一行（含 id）或完整 JSON 实体；dry-run 时附加标记。
    static func emit(_ value: some Codable, human: String, json: Bool, dryRun: Bool = false) throws {
        if json {
            let data = try jsonEncoder().encode(value)
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if dryRun, let object {
                var wrapped = object
                wrapped["dryRun"] = true
                let out = try JSONSerialization.data(withJSONObject: wrapped, options: [.prettyPrinted, .sortedKeys])
                print(text(out))
            } else {
                print(text(data))
            }
        } else {
            if let event = value as? CalendarEvent {
                print("\(human)：\(event.title)  id=\(event.id)")
            } else if let reminder = value as? Reminder {
                print("\(human)：\(reminder.title)  id=\(reminder.id)")
            } else {
                print(human)
            }
            if dryRun {
                print("（dry-run：未实际写入）")
            }
        }
    }

    /// 删除类命令的统一输出。
    static func emitDeleted(id: String, kind: String, json: Bool, dryRun: Bool) {
        if json {
            print(#"{"deleted": "\#(id)"\#(dryRun ? ", \"dryRun\": true" : "")}"#)
        } else {
            print("\(dryRun ? "将删除" : "已删除")\(kind) \(id)\(dryRun ? "（dry-run：未实际写入）" : "")")
        }
    }
}
