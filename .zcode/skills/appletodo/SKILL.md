---
name: appletodo
description: 当用户想查看、创建、修改、删除日历事件或提醒事项（含"日程安排/规划/待办/提醒我/周规划"类意图）时，用 appletodo CLI 操作系统日历与提醒事项（EventKit，iCloud 同步）。Use for any calendar/reminders/schedule intent.
---

# appletodo 日程管理

## 执行环境

- 仓库：`~/Projects/personal/AppleToDo`（`DEVELOPER_DIR` 已在 `~/.zshrc`）
- **直连优先**：`cd ~/Projects/personal/AppleToDo && swift run appletodo <命令>`
- **Terminal 兜底**：直连报「未获得日历/提醒事项权限」（accessDenied，后台环境无 GUI 归属被系统静默拒绝）时，自动改走 Terminal 通道（Terminal.app 已获授权；本机已启用「干净退出即关窗」偏好）：

```bash
osascript -e 'tell application "Terminal" to do script "cd ~/Projects/personal/AppleToDo && swift run appletodo <命令> > /tmp/appletodo_out.log 2>&1; echo EXIT=$? >> /tmp/appletodo_out.log; exit"'
# 等待 30–60 秒后读 /tmp/appletodo_out.log（首次构建较慢）；尾接 exit 自动关窗
# ⚠️ 转义：AppleScript 字符串外的 <命令> 里，shell 双引号必须写成 \"（如 add-event \"牙医\" ...），
#    否则 osascript 直接语法错误；单引号参数则原样保留
```

## 命令速查

| 命令 | 用途 | 示例 |
|---|---|---|
| `today` / `list [--date yyyy-MM-dd]` | 查某天事件 + 全部未完成提醒 | `list --date 2026-11-08` |
| `add-event <标题> --at <时间> [--duration 分] [--notes ...]` | 新建事件（默认 60 分钟） | `add-event "牙医" --at "2026-11-08 15:00" --duration 90` |
| `add-reminder <标题> [--due <时间>] [--notes ...]` | 新建提醒（截止可省略） | `add-reminder "买书" --due "2026-11-09"` |
| `move <id> --at <时间>` | 事件改期（保时长） | `move <id> --at "2026-11-08 16:00"` |
| `complete <id>` | 完成提醒 | |
| `edit-event <id> [--title] [--notes] [--duration]` | 改事件字段（未传不变；notes 空串=清空） | |
| `edit-reminder <id> [--title] [--notes] [--due / --no-due]` | 改提醒字段（--no-due 清除截止） | |
| `delete-event <id>` / `delete-reminder <id>` | 删除 | |

通用旗标：`--json`（机器输出，ISO8601；错误也输出 `{"error":...}` 到 stderr，退出码 1）；`--dry-run`（全部写命令演练不落盘；新增类命令免任何权限，直连可用）。
日期格式：`yyyy-MM-dd HH:mm` 或 `yyyy-MM-dd`（纯日期按 00:00）。**相对时间（明天/下周三）由你换算为绝对时间再执行。**

## 安全规则（强制）

1. **创建前查重**：先 `list` 相应日期，发现同类条目（标题相近/时间重叠）先向用户报告再行动
2. **写前演练**：写操作先跑 `--dry-run`，把计划展示给用户，得到明确同意后才去掉旗标真写
3. **删除/改期复述确认**：执行前向用户复述目标条目（标题 + 时间 + id 末 8 位），确认后才执行；不确认就停
4. **批量逐条确认**：多条写操作不得打包执行
5. **id 只取自 `--json` 输出**：禁止从人类模式文本行解析 id（排版不稳定）

## 输出解读（`--json`）

- list：`{"date", "events": [{id,title,start,end,notes}], "reminders": [...]}`；时间 ISO8601（UTC），展示给用户时转为本地时间
- 变更命令：返回落库后的完整实体（id 为 EventKit 规范标识）
- dry-run：实体外包 `"dryRun": true`；`notes` 里的 `[AppleToDo]` 首行是系统自动附加的溯源标记（ADR-0002），向用户展示时说明即可
- 错误：`{"error": {...}}`——notFound(id 不存在)/invalidRange(时间非法)/accessDenied(走 Terminal 通道)/noWritableTarget。**注意：权限检查先于 id 查找**——无权限环境下错误 id 也报 accessDenied
