# 命令和宏

本页面介绍如何使用命令、启动命令和宏来自动化常见的 Perfetto UI 任务。有关扩展 UI 的所有方法概述，请参阅[扩展 UI](/docs/visualization/extending-the-ui.md)。

## 运行命令

命令是单独的 UI 操作 —— 固定 track、运行查询、创建 debug track。通过以下方式运行它们：

- **命令面板：** `Ctrl+Shift+P` (Windows/Linux) 或 `Cmd+Shift+P` (Mac)
- **Omnibox：** 输入 `>` 将其转换为命令面板

命令支持模糊匹配和自动补全。有关稳定命令的完整列表，请参阅[命令自动化参考](/docs/visualization/commands-automation-reference.md)。

## 设置启动命令

启动命令在每次打开任何 trace 时自动运行。在**设置 > 启动命令**中配置它们。

启动命令是 command 对象的 JSON 数组：

```json
[
  {"id": "command.id", "args": ["arg1", "arg2"]}
]
```

命令按顺序执行。这些仅影响 UI 显示 —— trace 文件保持不变。

### 自动固定重要的 tracks

```json
[
  {
    "id": "dev.perfetto.PinTracksByRegex",
    "args": [".*CPU [0-3].*"]
  }
]
```

### 为自定义 metrics 创建 debug tracks

```json
[
  {
    "id": "dev.perfetto.AddDebugSliceTrack",
    "args": [
      "SELECT ts, thread.name, dur FROM thread_state JOIN thread USING(utid) WHERE state = 'R' AND dur > 1000000",
      "Long Scheduling Delays (>1ms)"
    ]
  }
]
```

### 在 debug tracks 中使用 Perfetto SQL 模块

当你的查询使用 Perfetto 模块时，首先作为单独的命令包含该模块：

```json
[
  {
    "id": "dev.perfetto.RunQuery",
    "args": ["include perfetto module android.screen_state"]
  },
  {
    "id": "dev.perfetto.AddDebugSliceTrack",
    "args": [
      "SELECT ts, dur FROM android_screen_state WHERE simple_screen_state = 'on'",
      "Screen On Events"
    ]
  }
]
```

Debug tracks 将 SQL 查询结果可视化在 Timeline 上。查询必须返回：

- `ts` (timestamp)
- 对于 slice tracks：`dur` (duration)
- 对于 counter tracks：`value` (metric 值)
- 可选的 pivot 列 —— 结果按唯一值分组，每个值在其自己的 track 中。

**命令参数模式：**

- 无 pivot：`AddDebugSliceTrack` —— `[query, title]`
- 有 pivot：`AddDebugSliceTrackWithPivot` —— `[query, pivot_column, title]`

### 标准分析设置

这个全面的启动配置为系统分析准备 UI：

```json
[
  {
    "id": "dev.perfetto.CollapseTracksByRegex",
    "args": [".*"]
  },
  {
    "id": "dev.perfetto.PinTracksByRegex",
    "args": [".*CPU \\d+$"]
  },
  {
    "id": "dev.perfetto.ExpandTracksByRegex",
    "args": [".*freq.*"]
  },
  {
    "id": "dev.perfetto.AddDebugSliceTrackWithPivot",
    "args": [
      "SELECT ts, blocked_function as name, dur FROM thread_state WHERE state = 'D' AND blocked_function IS NOT NULL",
      "name",
      "Blocking Functions"
    ]
  }
]
```

## 创建宏

宏是你从命令面板手动触发的命名命令序列。在**设置 > 宏**中配置它们。

宏是 macro 对象的 JSON 数组：

```json
[
  {
    "id": "user.example.MacroName",
    "name": "Display Name",
    "run": [
      {"id": "command.id", "args": ["arg1"]}
    ]
  }
]
```

- **id**：唯一标识符。使用反向域名命名（例如，`user.myteam.MemoryAnalysis`）。保持 ID 稳定 —— 它们在从启动命令引用宏时使用。
- **name**：在命令面板中显示的显示名称。可以包含空格。
- **run**：按顺序执行的命令。

通过在命令面板中输入 `>name` 来运行宏（例如，`>Memory Analysis`）。

> **注意（迁移）：** 宏格式从字典更改为数组结构。如果你有现有的宏，它们会自动迁移到新格式。迁移后的宏使用格式为 `dev.perfetto.UserMacro.<old_name>` 的 ID。

### 专注于特定子系统

这个宏创建一个 workspace 来隔离与内存相关的 tracks：

```json
[
  {
    "id": "user.example.MemoryAnalysis",
    "name": "Memory Analysis",
    "run": [
      {
        "id": "dev.perfetto.CreateWorkspace",
        "args": ["Memory Analysis"]
      },
      {
        "id": "dev.perfetto.CopyTracksToWorkspaceByRegexWithAncestors",
        "args": [".*mem.*|.*rss.*", "Memory Analysis"]
      },
      {
        "id": "dev.perfetto.SwitchWorkspace",
        "args": ["Memory Analysis"]
      },
      {
        "id": "dev.perfetto.AddDebugCounterTrackWithPivot",
        "args": [
          "SELECT ts, process.name as process, value FROM counter JOIN process_counter_track ON counter.track_id = process_counter_track.id JOIN process USING (upid) WHERE counter.name = 'mem.rss' AND value > 50000000",
          "process",
          "High Memory Processes (>50MB)"
        ]
      }
    ]
  }
]
```

### 调查延迟

这个宏帮助识别性能瓶颈：

```json
[
  {
    "id": "user.example.FindLatency",
    "name": "Find Latency",
    "run": [
      {
        "id": "dev.perfetto.PinTracksByRegex",
        "args": [".*CPU.*"]
      },
      {
        "id": "dev.perfetto.RunQueryAndShowTab",
        "args": [
          "SELECT thread.name, COUNT(*) as blocks, SUM(dur)/1000000 as total_ms FROM thread_state JOIN thread USING(utid) WHERE state = 'D' GROUP BY thread.name ORDER BY total_ms DESC LIMIT 10"
        ]
      },
      {
        "id": "dev.perfetto.AddDebugSliceTrackWithPivot",
        "args": [
          "SELECT ts, 'blocked' as name, thread.name as thread_name, dur FROM thread_state JOIN thread USING (utid) WHERE state IN ('R', 'D+') AND dur > 5000000",
          "thread_name",
          "Long Waits (>5ms)"
        ]
      }
    ]
  }
]
```

## 与 trace 录制结合

采集 traces 时，指定打开 trace 时运行的启动命令：

```bash
./record_android_trace \
  --app com.example.app \
  --ui-startup-commands '[
    {"id":"dev.perfetto.PinTracksByRegex","args":[".*CPU.*"]},
    {"id":"dev.perfetto.AddDebugSliceTrackWithPivot","args":["SELECT ts, thread.name, dur FROM thread_state JOIN thread USING(utid) WHERE state = \"R\"","thread","Runnable Time"]}
  ]'
```

## 技巧

1. **始终需要的视图的启动命令。** 如果你总是想要某些 tracks 被固定，使用启动命令。

2. **特定调查的宏。** 为你偶尔运行的工作流创建宏（内存分析、延迟 tracing等）。

3. **首先交互式测试。** 在将它们添加到设置之前，使用命令面板 (`Ctrl/Cmd+Shift+P`) 尝试命令。

4. **从干净状态开撕。** 使用 `".*"` 的 `CollapseTracksByRegex` 开始命令序列，首先折叠所有 tracks。

5. **常见正则表达式模式：**
    - 转义包名中的点：`"com\\.example\\.app"`
    - 匹配任何数字：`\\d+`
    - 匹配开头/结尾：`^` 和 `$`

6. **Debug tracks 需要好的查询。** 确保 SQL 返回 `ts` 和 `dur`（对于 slices）或 `value`（对于 counters）。对于 Android 用例，请参阅 [Android Trace Analysis Cookbook](/docs/getting-started/android-trace-analysis.md)。

## 与团队共享

如果你想与其他人共享宏和 SQL 模块，而不是在本地维护它们，使用[扩展服务器](/docs/visualization/extension-servers.md)。

## 常见问题

- **JSON 语法错误**：缺少逗号、尾随逗号或未转义的引号。
- **无效的 command IDs**：使用命令面板中的自动补全来查找有效的 ID，或参阅[命令自动化参考](/docs/visualization/commands-automation-reference.md)。
- **错误的参数类型**：所有参数必须是字符串，即使是数字。
- **错误的参数数量**：每个命令期望特定数量的参数。
- **模块依赖错误**：如果你的 debug track 查询使用 Perfetto 模块（例如，`android.screen_state`），首先使用 `RunQuery` 命令包含该模块。

## 另请参阅

- [扩展 UI](/docs/visualization/extending-the-ui.md) —— 所有扩展机制的概述
- [命令自动化参考](/docs/visualization/commands-automation-reference.md) —— 稳定自动化命令的完整参考
- [扩展服务器](/docs/visualization/extension-servers.md) —— 与团队共享宏和 SQL 模块
- [Perfetto UI 指南](/docs/visualization/perfetto-ui.md) —— 一般 UI 文档
- [深度链接](/docs/visualization/deep-linking-to-perfetto-ui.md) —— 通过 URLs 打开带有预配置命令的 traces
