# PERFETTO(1)

## 名称

perfetto - 捕获 traces

## 描述

本节介绍如何使用 `perfetto` 命令行二进制文件捕获 traces。示例以通过 ADB 连接的 Android 设备给出。

`perfetto` 有两种配置 Tracing Session 的模式（即收集什么以及如何收集）：

**轻量级模式**
:：所有配置选项都作为命令行标志提供，但可用的数据源限制为 ftrace 和 atrace。此模式类似于 [`systrace`](https://developer.android.com/topic/performance/tracing/command-line)。

**普通模式**
:：配置在协议缓冲区中指定。这允许对收集的 traces 进行完全自定义。


## 常规选项

以下列出了在任一模式下使用 `perfetto` 时的可用选项。

`-d`, `--background`
:: Perfetto 立即退出命令行界面并在后台继续采集你的 trace。

`-o`, `--out` _OUT_FILE_
:：指定输出 trace 文件的所需路径，或 `-` 用于 stdout。
 `perfetto` 将输出写入上述标志描述的文件。
 输出格式符合 AOSP `trace.proto` 中定义的格式。

`--dropbox` _TAG_
:：通过 [DropBoxManager API](https://developer.android.com/reference/android/os/DropBoxManager.html)
 使用你指定的标签上传你的 trace。仅限 Android。

`--no-guardrails`
:：在测试期间启用 `--dropbox` 标志时，禁用防止过度资源使用的保护措施。

`--reset-guardrails`
:：重置 guardrails 的持久状态并退出（用于测试）。

`--query`
:：查询服务状态并将其作为人类可读的文本打印。

`--query-raw`
:：类似于 `--query`，但打印 `tracing_service_state.proto` 的原始 proto 编码字节。

`-h`, `--help`
:：打印 `perfetto` 工具的帮助文本。

`--attach` _KEY_
:：使用给定的密钥重新附加到已分离的 tracing session。

`--detach` _KEY_
:：使用给定的密钥从 tracing session 分离。这允许中断与当前 tracing session 的连接，但 session 本身会在后台继续运行。

`--is_detached` _KEY_
:：检查 session 是否可以被重新附加。退出代码：0 = 可以附加，2 = 不能附加，1 = 错误。

`--stop`
:：仅在与 `--attach` 一起使用时支持。重新附加后停止 tracing。

`--save-for-bugreport`
:：如果有一个 `bugreport_score > 0` 的 trace 正在运行，则将其保存到文件中，并在完成后输出文件路径。

`--save-all-for-bugreport`
:：克隆所有符合条件的错误报告 session，并将它们保存到错误报告输出文件中。

`--clone` _TSID_
:：创建由 session ID（TSID）标识的现有 tracing session 的只读克隆。

`--clone-by-name` _NAME_
:：创建由 `unique_session_name` 标识的现有 tracing session 的只读克隆。

`--clone-for-bugreport`
:：只能与 `--clone` 或 `--clone-by-name` 一起使用。在克隆的 session 上禁用 `trace_filter`。


## 简单模式

为了便于使用，`perfetto` 命令包括通过命令行参数支持配置子集。在设备上，这些配置的行为与 *CONFIG_FILE*（见下文）提供的相同配置等效。

使用 `perfetto` 在 *简单模式* 中的通用语法如下：

```
 adb shell perfetto [ --time TIMESPEC ] [ --buffer SIZE ] [ --size SIZE ]
 [ ATRACE_CAT | FTRACE_GROUP/FTRACE_NAME]...
```

以下列出了在 *简单模式* 下使用 `perfetto` 时的可用选项。

`-t`, `--time` _TIME[s|m|h]_
:：指定 trace 持续时间（秒、分钟或小时）。
 例如，`--time 1m` 指定 1 分钟的 trace 持续时间。
 默认持续时间为 10 秒。

`-b`, `--buffer` _SIZE[mb|gb]_
:：指定环形缓冲区大小（兆字节或千兆字节）。
 默认参数为 `--buffer 32mb`。

`-s`, `--size` _SIZE[mb|gb]_
:：指定最大文件大小（兆字节或千兆字节）。
 默认情况下，`perfetto` 仅使用内存中的环形缓冲区。


后面跟着事件说明符列表：

`ATRACE_CAT`
:：指定要为其采集 trace 的 atrace 类别。
 例如，以下命令使用 atrace 追踪窗口管理器：
 `adb shell perfetto --out FILE wm`。要记录其他类别，请参阅
 [atrace 类别列表](https://cs.android.com/android/platform/superproject/main/+/main:frameworks/native/cmds/atrace/atrace.cpp)。
 注意:可用类别取决于 Android 版本。

`FTRACE_GROUP/FTRACE_NAME`
:：指定要为其采集 trace 的 ftrace 事件。
 例如，以下命令追踪 sched/sched_switch 事件：
 `adb shell perfetto --out FILE sched/sched_switch`


## 普通模式

使用 `perfetto` 在 *普通模式* 下的通用语法如下：

```
 adb shell perfetto [ --txt ] --config CONFIG_FILE
```

以下列出了在 *普通* 模式下使用 `perfetto` 时的可用选项。

`-c`, `--config` _CONFIG_FILE_
:：指定配置文件的路径。在普通模式下，某些
 配置可以在配置协议缓冲区中编码。
 此文件必须符合 AOSP [`trace_config.proto`](/protos/perfetto/config/trace_config.proto) 中定义的协议缓冲区模式。
 你使用 TraceConfig 的 DataSourceConfig 成员选择和配置数据源，如 AOSP
 [`data_source_config.proto`](/protos/perfetto/config/data_source_config.proto) 中所定义。

`--txt`
:：指示 `perfetto` 将配置文件解析为 pbtxt。此标志
 是实验性的，不建议在生产环境中启用。