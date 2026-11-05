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

    /// dry-run 服务：写操作落到内存库，不触达任何真实数据。新增类命令无需种子（也无需任何权限）；
    /// 修改/删除类命令传入目标 id——先从真实库读取并注入内存（保留 notFound 语义），业务逻辑原样执行。
    static func dryRunService(seedEventID: String? = nil, seedReminderID: String? = nil) async throws -> ScheduleService {
        let memory = InMemoryStore()
        if seedEventID != nil || seedReminderID != nil {
            let realStore = EventKitStore()
            try await realStore.requestAccess()
            let real = ScheduleService(store: realStore)
            if let eventID = seedEventID {
                guard let current = try await real.event(id: eventID) else {
                    throw ScheduleError.notFound(id: eventID)
                }
                _ = try await memory.save(event: current)
            }
            if let reminderID = seedReminderID {
                guard let current = try await real.reminder(id: reminderID) else {
                    throw ScheduleError.notFound(id: reminderID)
                }
                _ = try await memory.save(reminder: current)
            }
        }
        return ScheduleService(store: memory)
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
