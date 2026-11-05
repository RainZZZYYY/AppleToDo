import AppleToDoCore
import SwiftUI

/// appletodo-bar 菜单栏 App（M5，NAN-164/165）。
/// 快速录入：标题 + 时间/时长 → 预览 → 写入 iCloud「AppleToDo」日历。
@main
struct AppletodoBar: App {
    @State private var scheduleStore = ScheduleStore()

    var body: some Scene {
        MenuBarExtra {
            QuickEntryView(store: scheduleStore)
        } label: {
            Image(systemName: "calendar.badge.plus")
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - 状态管理

@MainActor @Observable
final class ScheduleStore {
    var title = ""
    var date = Date()
    var durationMinutes = 60
    var status: Status = .idle
    var previewText: String?

    enum Status {
        case idle
        case writing
        case success(String)
        case failure(String)
    }

    private var service: ScheduleService?

    func requestAccess() async {
        let store = EventKitStore()
        do {
            try await store.requestAccess()
            service = ScheduleService(store: store)
        } catch {
            status = .failure("权限未获得（\(error)）")
        }
    }

    func preview() {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            status = .failure("请输入标题")
            return
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        let endTime = date.addingTimeInterval(Double(durationMinutes) * 60)
        previewText = "将创建事件：\(title) \(formatter.string(from: date))–\(formatter.string(from: endTime))（\(durationMinutes) 分钟）"
        status = .idle
    }

    func write() async {
        guard let service else {
            status = .failure("权限未就绪")
            return
        }
        status = .writing
        do {
            let event = try await service.addEvent(title: title, start: date,
                                                   end: date.addingTimeInterval(Double(durationMinutes) * 60))
            status = .success("已创建：\(event.title) id=\(event.id.suffix(8))")
            title = ""
            previewText = nil
        } catch {
            status = .failure("失败：\(error)")
        }
    }
}

// MARK: - 视图

struct QuickEntryView: View {
    let store: ScheduleStore

    var body: some View {
        VStack(spacing: 10) {
            // 标题
            TextField("事件标题", text: Bindable(store).title)
                .textFieldStyle(.roundedBorder)

            // 时间与时长
            HStack {
                DatePicker("", selection: Bindable(store).date)
                    .labelsHidden()
                Spacer()
                Picker("时长", selection: Bindable(store).durationMinutes) {
                    Text("30分").tag(30)
                    Text("60分").tag(60)
                    Text("90分").tag(90)
                    Text("2时").tag(120)
                }
                .frame(width: 100)
            }

            // 预览 / 确认
            if let preview = store.previewText {
                Text(preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Button("重新编辑") {
                        store.previewText = nil
                    }
                    Button("确认写入") {
                        Task { await store.write() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Button("预览") {
                    store.preview()
                }
                .buttonStyle(.bordered)
                .disabled(store.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            // 状态
            switch store.status {
            case .idle:
                EmptyView()
            case .writing:
                ProgressView("写入中…")
                    .controlSize(.small)
            case let .success(msg):
                Label(msg, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            case let .failure(msg):
                Label(msg, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Divider()
            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding()
        .frame(minWidth: 280, minHeight: 180)
        .task {
            await store.requestAccess()
        }
    }
}
