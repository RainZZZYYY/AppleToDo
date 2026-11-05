import SwiftUI

/// appletodo-bar 菜单栏 App（M5 骨架，NAN-164）。
/// 骨架阶段：仅显示标识与退出；快速录入在 NAN-165 实现。
@main
struct AppletodoBar: App {
    var body: some Scene {
        MenuBarExtra {
            ContentView()
        } label: {
            Image(systemName: "calendar.badge.plus")
        }
        .menuBarExtraStyle(.window)
    }
}

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("appletodo-bar")
                .font(.headline)
            Text("M5 骨架 — 快速录入即将到来")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding()
        .frame(minWidth: 200, minHeight: 120)
    }
}
