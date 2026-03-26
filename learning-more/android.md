# Android 上的高级系统 Tracing

本指南深入探讨在 Android 上采集系统 trace，建立在 [System Tracing](/docs/getting-started/system-tracing.md) 指南中介绍的概念基础上。

在继续之前，你应该熟悉使用 [Perfetto UI](/docs/getting-started/system-tracing.md#android-perfetto-ui) 或 [`record_android_trace`](/docs/getting-started/system-tracing.md#android-command-line) 脚本采集系统 trace 的基础知识。

本指南涵盖这些工具抽象掉的底层详细信息，包括：

- 在旧版 Android 上启用 Perfetto tracing 服务。
- 直接使用设备上的 `/system/bin/perfetto` 二进制文件。
- 编写和使用完整的 trace config 以进行高级自定义。
- 使用独占模式进行 tracing 会话，以防止来自其他 trace 的干扰。

## 前提条件：启用 tracing 服务

Perfetto 的tracing 守护进程（`traced`）内置在 Android 中，但它们仅在 **Android 11 (R) 及更新版本**上默认启用。

如果你使用的是 **Android 9 (P)** 或 **Android 10 (Q)**，你必须首先运行以下命令来启用 tracing 服务：

```bash
# 仅在非 Pixel 手机上的 Android 9 (P) 和 10 (Q) 上需要。
adb shell setprop persist.traced.enable 1
```

NOTE: 如果你使用的是早于 9 (P) 的 Android 版本，设备上的工具将无法工作。
 你必须使用 [`record_android_trace`](/docs/getting-started/system-tracing.md#android-command-line) 脚本。

## 使用设备上的 /system/bin/perfetto 命令进行记录

`record_android_trace` 脚本是设备上 `/system/bin/perfetto` 二进制文件的包装器。对于大多数用例，推荐使用该脚本，但你也可以直接调用二进制文件以获得更多控制权。

```bash
# 直接调用设备上二进制文件的示例。
adb shell perfetto \
 # 设备上输出文件的路径。
 # 采集 trace 的时间。
 -o /data/misc/perfetto-traces/trace_file.perfetto-trace \
 # 采集 trace 的时间。
 -t 20s \
 # 要采集的 atrace 类别。
 sched freq idle am wm gfx view binder_driver hal dalvik input res memory
```

然而，直接使用 `adb shell perfetto` 时有几个注意事项需要注意:

- **停止 trace：** `Ctrl+C` 在 `adb shell perfetto` 中不可靠。它仅在使用基于交互式 PTY 的会话时才正确传播（即，先运行 `adb shell`，然后在 shell 内运行 `perfetto`）。对于长时间运行的 trace，更安全的方法是使用 `--background` 标志并通过其 PID `kill` 进程。有关更多信息，请参阅[后台 Tracing](/docs/learning-more/tracing-in-background.md）指南。

- **传递 trace config：** 在 Android 12 之前的非 root 设备上，SELinux 规则阻止 `perfetto` 进程从世界可写的位置（如 `/data/local/tmp`）读取 config 文件。推荐的解决方法是通过标准输入管道传递 config：`cat config.pbtx | adb shell perfetto -c -`。从 Android 12 开始，你可以将 config 放在 `/data/misc/perfetto-configs` 中并直接传递路径。

- **拉取 trace 文件：** 在 Android 10 之前的设备上，由于权限问题，`adb pull` 可能无法直接访问 trace 文件。解决方法是使用 `adb shell cat`：`adb shell cat /data/misc/perfetto-traces/trace > trace.pftrace`。

## 使用完整的 Trace Config

要完全控制 tracing 过程，你可以提供完整的 trace config 文件，而不是使用命令行标志。这允许你启用多个数据源并微调它们的设置。

有关编写 trace config 的详细指南，请参阅 [Trace Configuration](/docs/concepts/config.md) 页面。

WARNING: 下面的命令在 Android P 上不起作用，因为 `--txt` 选项是在 Q 中引入的。
 应该使用二进制 protobuf 格式；详细信息可以在
 [_Trace configuration_ 页面](https://perfetto.dev/docs/concepts/config#pbtx-vs-binary-format）中找到。

如果你在 Mac 或 Linux 主机上运行，或者在 Windows 上使用基于 bash 的终端，你可以使用以下内容：

```bash
cat<<EOF>config.pbtx
duration_ms: 10000

buffers: {
 size_kb: 8960
 fill_policy: DISCARD
}
buffers: {
 size_kb: 1280
 fill_policy: DISCARD
}
data_sources: {
 config {
 name: "linux.ftrace"
 ftrace_config {
 ftrace_events: "sched/sched_switch"
 ftrace_events: "power/suspend_resume"
 ftrace_events: "sched/sched_process_exit"
 ftrace_events: "sched/sched_process_free"
 ftrace_events: "task/task_newtask"
 ftrace_events: "task/task_rename"
 ftrace_events: "ftrace/print"
 atrace_categories: "gfx"
 atrace_categories: "view"
 atrace_categories: "webview"
 atrace_categories: "camera"
 atrace_categories: "dalvik"
 atrace_categories: "power"
 }
 }
}
data_sources: {
 config {
 name: "linux.process_stats"
 target_buffer: 1
 process_stats_config {
 scan_all_processes_on_start: true
 }
 }
}
EOF

./record_android_trace -c config.pbtx -o trace_file.perfetto-trace
```

或者，当直接使用设备上的命令时：

```bash
cat config.pbtx | adb shell perfetto -c - --txt -o /data/misc/perfetto-traces/trace.perfetto-trace
```

或者，首先推送 trace config 文件，然后调用 perfetto：

```bash
adb push config.pbtx /data/local/tmp/config.pbtx
adb shell 'cat /data/local/tmp/config.pbtx | perfetto --txt -c - -o /data/misc/perfetto-traces/trace.perfetto-trace'
```

NOTE: 由于严格的 SELinux 规则，在 Android 的非 root 版本上，直接将文件路径作为
 `-c /data/local/tmp/config` 传递将失败，因此需要上面的 `-c -` + stdin 管道。
 从 Android 12 (S) 开始，可以使用 `/data/misc/perfetto-configs/` 代替。

使用 `adb pull /data/misc/perfetto-traces/trace ~/trace.perfetto-trace` 拉取文件并在 [Perfetto UI](https://ui.perfetto.dev) 中打开它。

NOTE: 在 Android 10 之前的设备上，adb 无法直接拉取 `/data/misc/perfetto-traces`。
 使用 `adb shell cat /data/misc/perfetto-traces/trace > trace.perfetto-trace` 作为解决方法。

`perfetto` 命令行界面的完整参考可以在[这里](/docs/reference/perfetto-cli.md）找到。

## 独占 Tracing 会话

Perfetto 旨在支持来自不同源（例如，adb、设备上的应用程序、自动化测试）的[多个并发tracing 会话](/docs/concepts/concurrent-tracing-sessions.md)。虽然这适用于大多数数据源，但某些高级功能无法可靠地多路复用，并且敏感的性能测量需要最小化来自其他 trace 的干扰。在这些情况下，Perfetto 需要保证没有其他tracing 会话处于活动状态。

为了解决这个问题，Perfetto 提供了"独占"模式。当在独占模式下启动会话时，它确保没有其他会话正在运行，提供干净的tracing 环境。这由 `TraceConfig` 中的 `exclusive_prio` 字段控制。

### 何时使用独占模式

你应该在以下情况下使用独占会话：

- 对于需要最小化来自其他并发 tracing 活动的干扰的敏感性能测量。
- 当使用高开销的数据源时，例如 ftrace 中的 `function_graph`，以确保它们的行为不受其他会话影响。
- 当配置全局应用且不进行多路复用的参数时，如 ftrace 缓冲区大小（`buffer_size_kb`），它仅由第一个活动会话配置。
- 当使用修改全局内核状态的特定 ftrace 功能时。截至 Perfetto v52 (Android 25Q3+)，这些包括：
  - `tids_to_trace`：按特定的线程 ID (TID) 过滤 ftrace 事件。
  - `tracefs_options`：通过 tracefs/trace_options 控制 tracer 或 trace 输出
  - `tracing_cpumask`：将 Tracing 限制为特定的 CPU 集。

### 行为

独占会话具有以下行为：

- **优先级系统：** `exclusive_prio` 是一个无符号整数，其中较高的数字表示较高的优先级。只有当优先级大于 0 时，会话才被视为"独占"。
- **抢占：** 如果请求的新独占会话的优先级严格高于任何其他活动会话，它将被启动，所有其他现有会话（独占和非独占）都将中止。已中止会话的使用者将收到错误消息（例如，`Aborted due to user requested higher-priority (#priority) exclusive session.`）。
- **阻止：** 当独占会话处于活动状态时，任何启动新的非独占会话或优先级较低或相等的独占会话的尝试都将被拒绝。
- **特权访问：** 在 Android 上，请求独占会话是特权操作，只能由 `root` 或 `shell` 用户执行。

### 如何启用

要启动独占会话，请在你的 trace config 文件中添加 `exclusive_prio` 字段。

此功能从 Perfetto v52 和 Android 的 25Q3+ 开始可用。

```protobuf
duration_ms: 10000

buffers: {
 size_kb: 8192
}

# 请求优先级为 10 的独占会话。
# 这将中止任何正在运行的会话（前提是它们的优先级较低）并阻止
# 优先级较低或相等的新会话。
exclusive_prio: 10

data_sources: {
 config {
 name: "linux.ftrace"
 ftrace_config {
 # 像 funcgraph 这样的高级功能现在可以更可靠地使用。
 function_graph: true
 ftrace_events: "sched/sched_switch"
 }
 }
}
```
