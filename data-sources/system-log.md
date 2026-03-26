## 系统调用
可以在 Perfetto trace 中跟踪所有系统调用的进入和退出。


以下 ftrace 事件需要添加到 trace 配置以收集系统调用：

```protobuf
data_sources: {
 config {
 name: "linux.ftrace"
 ftrace_config {
 ftrace_events: "raw_syscalls/sys_enter"
 ftrace_events: "raw_syscalls/sys_exit"
 }
 }
}
```

## Linux 内核 trace
Perfetto 与 [Linux 内核事件 trace](https://www.kernel.org/doc/Documentation/trace/ftrace.txt）集成。虽然 Perfetto 对某些事件有特殊支持（例如，请参见 [CPU 调度](#cpu-scheduling)），但 Perfetto 可以收集任意事件。
此配置收集四个 Linux 内核事件：

```protobuf
data_sources {
 config {
 name: "linux.ftrace"
 ftrace_config {
 ftrace_events: "ftrace/print"
 ftrace_events: "sched/sched_switch"
 ftrace_events: "task/task_newtask"
 ftrace_events: "task/task_rename"
 }
 }
}
```

可以在 [ftrace_config.proto](/protos/perfetto/config/ftrace/ftrace_config.proto) 中查看 ftrace 的完整配置选项。

## Android 系统日志

### Android logcat
在 trace 中包含 Android Logcat 消息，并与其他 trace 数据一起查看它们。

![](/docs/images/android_logs.png)

你可以配置哪些 Log buffer 包含在 trace 中。如果未指定缓冲区，则将包含所有缓冲区。

```protobuf
data_sources: {
 config {
 name: "android.log"
 android_log_config {
 log_ids: LID_DEFAULT
 log_ids: LID_SYSTEM
 log_ids: LID_CRASH
 }
 }
}
```

你可能还想使用 `filter_tags` 参数对标签添加过滤，或使用 `min_prio` 设置要包含在 trace 中的最小优先级。有关配置选项的详细信息，请参见 [android\_log\_config.proto](/protos/perfetto/config/android/android_log_config.proto)。

可以使用 [Perfetto UI](https://ui.perfetto.dev) 与 trace 中的其他信息一起调查 Log，如上面的屏幕截图所示。

如果使用 `trace_processor`，这些 Log 将在 [android\_logs](/docs/analysis/sql-tables.autogen#android_logs) 表中。要查看带有标签 'perfetto' 的 Log，你将使用以下查询：

```sql
select * from android_logs where tag = "perfetto" order by ts
```

### Android 应用程序 trace
你可以通过 Perfetto 启用 atrace。

![](/docs/images/userspace.png)

将所需的类别添加到 `atrace_categories`，并将 `atrace_apps` 设置为特定应用程序，以从该应用程序收集用户空间注释。

```protobuf
data_sources: {
 config {
 name: "linux.ftrace"
 ftrace_config {
 atrace_categories: "view"
 atrace_categories: "webview"
 atrace_categories: "wm"
 atrace_categories: "am"
 atrace_categories: "sm"
 atrace_apps: "com.android.phone"
 }
 }
}
```
