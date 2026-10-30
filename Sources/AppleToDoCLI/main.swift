import AppleToDoCore

print("appletodo \(AppleToDoCore.version)")
if !CommandLine.arguments.contains("--version") {
    print("用法：appletodo --version（完整命令集在 M2 提供；当前二进制名为 AppleToDoCLI）")
}
