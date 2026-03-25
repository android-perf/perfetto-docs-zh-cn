# Trace 配置

与许多始终开启的 Log system（例如 Linux 的 rsyslog、Android 的 logcat）不同，在 Perfetto 中，所有 trace 数据源默认处于空闲状态，仅在收到指令时才记录数据。

<!--
数据源仅在一个（或多个） trace 会话处于活动状态时才记录数据。
通过调用 `perfetto` 命令行客户端并传递配置来启动 trace 会话
(参见 [Android](/docs/quickstart/android-tracing.md)、
[Linux](/docs/quickstart/linux-tracing.md) 或 [桌面版 Chrome](/docs/quickstart/chrome-tracing.md) 的 QuickStart 指南)。
-->

一个简单的 trace 配置如下所示：

```protobuf
duration_ms: 10000

buffers {
 size_kb: 65536
 fill_policy: RING_BUFFER
}

data_sources {
 config {
 name: "linux.ftrace"
 target_buffer: 0
 ftrace_config {
 ftrace_events: "sched_switch"
 ftrace_events: "sched_wakeup"
 }
 }
}

```

使用方式如下：

```bash
perfetto --txt -c config.pbtx -o trace_file.perfetto-trace
```

TIP: 在 repo 中可以找到一些更完整的 trace 配置示例，位于 [`/test/configs/`](/test/configs/)。

NOTE: 如果你在 Android 上使用 adb 进行 trace 并且遇到问题，请参见下面的 [Android 部分](#android)。

## TraceConfig

TraceConfig 是一个 protobuf 消息([参考文档](/docs/reference/trace-config-proto.autogen))，它定义了：

1. 整个 trace 系统的一般行为，例如：

  - trace 的最大持续时间。
  - 内存中缓冲区的数量及其大小。
  - 输出 trace 文件的最大大小。

2. 启用哪些数据源及其配置，例如：

  - 对于 [内核 trace 数据源](/docs/data-sources/cpu-scheduling.md)，启用哪些 ftrace 事件。
  - 对于 [heap profiler](/docs/data-sources/native-heap-profiler.md)，目标进程名称和采样率。

 有关如何配置 Perfetto 捆绑的数据源的详细信息，请参见文档的 _数据源_ 部分。

3. `{数据源} x {缓冲区}` 映射：每个数据源应该写入哪个缓冲区(参见下面的 [缓冲区部分](#buffers))。

trace 服务（`traced`）充当配置分发器：它从 `perfetto` 命令行客户端(或任何其他 [消费者](/docs/concepts/service-model.md#consumer))接收配置，并将配置的部分转发给连接的各种 [生产者](/docs/concepts/service-model.md#producer)。

当消费者启动 trace 会话时，trace 服务将：

- 读取 TraceConfig 的外部部分（例如 `duration_ms`、`buffers`）并使用它来确定自己的行为。
- 读取 `data_sources` 部分中的数据源列表。对于配置中列出的每个数据源，如果注册了相应的名称（在下面的示例中为 `"linux.ftrace"`），服务将要求生产者进程启动该数据源，并将 [`DataSourceConfig` 子部分][dss] 的原始字节原样传递给数据源（参见向后/向前兼容性部分）。

![TraceConfig diagram](/docs/images/trace_config.png)

[dss]: /docs/reference/trace-config-proto.autogen#DataSourceConfig

## 缓冲区

缓冲区部分定义了由 trace 服务拥有的内存中缓冲区的数量、大小和策略。它看起来如下：

```protobuf
# 缓冲区 #0
buffers {
 size_kb: 4096
 fill_policy: RING_BUFFER
}

# 缓冲区 #1
buffers {
 size_kb: 8192
 fill_policy: DISCARD
}
```

每个缓冲区都有一个填充策略，可以是：

- RING_BUFFER(默认)：缓冲区的行为类似于环形缓冲区，并且在写入满时将覆盖并替换缓冲区中最旧的 trace 数据。

- DISCARD：缓冲区在满时停止接受数据。进一步的写入尝试将被丢弃。

WARNING: DISCARD 可能会与在 trace 结束时提交数据的数据源产生意想不到的副作用。

一个 trace 配置必须至少定义一个缓冲区才有效。在最简单的情况下，所有数据源都会将其 trace 数据写入同一个缓冲区。

虽然这对于大多数基本情况都很好，但在不同数据源以显着不同的速率写入的情况下可能会出现问题。

例如，想象一个启用以下两者的 trace 配置：

1. 内核调度器 tracer。在典型的 Android 手机上，这记录约 10000 个事件/秒，将约 1 MB/s 的 trace 数据写入缓冲区。

2. 内存统计轮询。此数据源将 /proc/meminfo 的内容写入 trace 缓冲区，并配置为每 5 秒轮询一次，每次轮询间隔写入约 100 KB。

如果两个数据源都配置为写入同一个缓冲区，并且该缓冲区设置为 4MB，大多数 trace 将只包含一个内存快照。即使第二个数据源工作完美，大多数 trace 根本不包含任何内存快照的可能性也很大。这是因为在 5 秒的轮询间隔期间，调度器数据源最终可能会填满整个缓冲区，将内存快照数据推出缓冲区。

## 动态缓冲区映射

数据源 <> 缓冲区映射在 Perfetto 中是动态的。在最简单的情况下，trace 会话只能定义一个缓冲区。默认情况下，所有数据源都会将数据记录到该缓冲区中。

在上面的示例中，将这些数据源分离到不同的缓冲区可能更好。这可以通过 TraceConfig 的 `target_buffer` 字段来实现。

![Buffer mapping](/docs/images/trace_config_buffer_mapping.png)

可以通过以下方式实现：

```protobuf
data_sources {
 config {
 name: "linux.ftrace"
 target_buffer: 0 # <-- 这进入缓冲区 0。
 ftrace_config { ... }
 }
}

data_sources: {
 config {
 name: "linux.sys_stats"
 target_buffer: 1 # <-- 这进入缓冲区 1。
 sys_stats_config { ... }
 }
}

data_sources: {
 config {
 name: "android.heapprofd"
 target_buffer: 1 # <-- 这也进入缓冲区 1。
 heapprofd_config { ... }
 }
}
```

## PBTX 与二进制格式

使用 `perfetto` 命令行客户端格式时，有两种方法可以传递 trace 配置：

#### 文本格式

这是人工驱动的工作流和探索的首选格式。它允许直接在 PBTX（ProtoBuf 文本表示）语法中传递文本文件，用于在 [trace_config.proto](/protos/perfetto/config/trace_config.proto) 中定义的模式(参见[参考文档](/docs/reference/trace-config-proto.autogen))

使用此模式时，将 `--txt` 标志传递给 `perfetto` 以指示配置应解释为 PBTX 文件：

```bash
perfetto -c /path/to/config.pbtx --txt -o trace_file.perfetto-trace
```

NOTE: `--txt` 选项仅在 Android 10 (Q) 中引入。旧版本仅支持二进制格式。

WARNING: 不要将文本格式用于机器对机器交互（基准测试、脚本和工具），因为它更容易中断(例如，如果重命名字段或将枚举转换为整数)

#### 二进制格式

这是机器对机器（M2M）交互的首选格式。它涉及传递 TraceConfig 消息的 protobuf 编码二进制。这可以通过将 PBTX 作为输入传递给 protobuf 的 `protoc` 编译器来获得(可以[在此处下载](https://github.com/protocolbuffers/protobuf/releases))。

```bash
cd ~/code/perfetto # Android 树中的 external/perfetto。

protoc --encode=perfetto.protos.TraceConfig \
 -I. protos/perfetto/config/perfetto_config.proto \
 < config.txpb \
 > config.bin
```

然后将其传递给 perfetto，如下所示，不带 `--txt` 参数：

```bash
perfetto -c config.bin -o trace_file.perfetto-trace
```

## {#long-traces} 流式传输长 trace

默认情况下，Perfetto 将完整的 trace 缓冲区保存在内存中，并且仅在 trace 会话结束时将其写入目标文件（`-o` 命令行参数）。这是为了减少 trace 系统的性能侵入性。然而，这将 trace 的最大大小限制为设备的物理内存大小，这通常太有限了。

在某些情况下（例如，基准测试、难以重现的情况），可能需要捕获比这大得多的 trace，以额外的 I/O 开销为代价。

为此，Perfetto 允许定期将 trace 缓冲区写入目标文件（或 stdout），使用以下 TraceConfig 字段：

- `write_into_file (bool)`：当为 true 时，定期将 trace 缓冲区排空到输出文件中。启用此选项后，用户空间缓冲区只需足够大以容纳两次写入周期之间的 trace 数据。缓冲区大小取决于设备的活动。典型 trace 的数据速率约为 1-4 MB/s。因此，16MB 的内存缓冲区可以容纳长达约 4 秒的写入周期，然后才会开始丢失数据。

- `file_write_period_ms (uint32)`：覆盖默认排空周期（5s）。较短的周期需要较小的用户空间缓冲区，但会增加 trace 的性能侵入性。如果给定的周期小于 100ms，则 trace 服务将使用 100ms 的周期。

- `max_file_size_bytes (uint64)`：如果设置，则在写入 N 字节后停止 trace 会话。用于限制 trace 的大小。

有关长 trace 模式下的工作 trace 配置的完整示例，请参见 [`/test/configs/long_trace.cfg`](/test/configs/long_trace.cfg)。

总结：要捕获长 trace，只需设置 `write_into_file:true`，设置一个长的 `duration_ms`，并使用 32MB 或更大的内存缓冲区大小。

## 数据源特定配置

除了 trace 全局配置参数外，trace 配置还定义了数据源特定的行为。在 proto 模式级别，这在 `TraceConfig` 的 `DataSourceConfig` 部分中定义：

来自 [data_source_config.proto](/protos/perfetto/config/data_source_config.proto):

```protobuf
message TraceConfig {
 ...
 repeated DataSource data_sources = 2; // 见下文。
}

message DataSource {
 optional protos.DataSourceConfig config = 1; // 见下文。
 ...
}

message DataSourceConfig {
 optional string name = 1;
 ...
 optional FtraceConfig ftrace_config = 100 [lazy = true];
 ...
 optional AndroidPowerConfig android_power_config = 106 [lazy = true];
}
```

像 `ftrace_config`、`android_power_config` 这样的字段是数据源特定配置的示例。trace 服务将完全忽略这些字段的内容，并将整个 DataSourceConfig 对象路由到任何注册了相同名称的数据源。

`[lazy=true]` 标记在 [protozero](/docs/design-docs/protozero.md) 代码生成器中具有特殊含义。与标准嵌套消息不同，它生成原始访问器(例如，`const std::string& ftrace_config_raw()` 而不是 `const protos::FtraceConfig& ftrace_config()`)。这是为了避免注入过多的 `#include` 依赖关系，并避免实现数据源的代码中的二进制大小膨胀。

#### 关于向后/向前兼容性的说明

trace 服务将 `DataSourceConfig` 消息的原始二进制 blob 路由到具有匹配名称的数据源，而无需尝试解码和重新编码它。如果 trace 配置的 `DataSourceConfig` 部分包含在构建服务时不存在的新字段，则该服务仍会将 `DataSourceConfig` 传递给数据源。这允许引入新的数据源，而无需服务预先了解它们。

TODO: 我们知道今天使用自定义 proto 扩展 `DataSourceConfig` 需要更改 Perfetto repo 中的 `data_source_config.proto`，这对于外部项目来说并不理想。长期计划是为非上游扩展保留一系列字段，并为客户端代码提供通用模板化访问器。在此之前，我们接受上游补丁以引入你自己的数据源的特殊配置。

## 多进程数据源

某些数据源是单例。例如，在 Android 上提供调度器 trace 的 Perfetto 中，整个系统只有一个数据源，由 `traced_probes` 服务拥有。

然而，在一般情况下，多个进程可以通告相同的数据源。例如，当使用 [Perfetto SDK](/docs/instrumentation/tracing-sdk.md) 进行用户空间插桩时就是这种情况。

如果发生这种情况，当启动指定该数据源的 trace 配置的 trace 会话时，Perfetto 默认将要求通告该数据源的所有进程启动它。

在某些情况下，可能希望进一步将数据源的启用限制到特定进程（或一组进程）。这可以通过 `producer_name_filter` 和 `producer_name_regex_filter` 来实现。

NOTE: 典型的 Perfetto 运行时模型是：一个进程 == 一个 Perfetto Producer;一个 Producer 通常托管多个数据源。

设置这些过滤器后，Perfetto trace 服务将仅在匹配过滤器的 Producer 子集中激活数据源。

示例：

```protobuf
buffers {
 size_kb: 4096
}

data_sources {
 config {
 name: "track_event"
 }
 # 仅在 Chrome 和 Chrome canary 上启用数据源。
 producer_name_filter: "com.android.chrome"
 producer_name_filter: "com.google.chrome.canary"
}
```

## 触发器

在正常条件下，trace 会话的生命周期与 `perfetto` 命令行客户端的调用简单匹配：当 TraceConfig 传递给 `perfetto` 时 trace 数据采集开始，当 `TraceConfig.duration_ms` 已经过去或命令行客户端终止时结束。

Perfetto 支持基于触发器的替代启动或停止 trace 模式。总体思想是在 trace 配置本身中声明：

- 一组触发器，它们只是自由形式的字符串。
- 给定触发器是否应该导致 trace 启动或停止，以及启动/停止延迟。

为什么要使用触发器？为什么不能在需要时直接启动 perfetto 或 kill（SIGTERM）它？所有这一切的基本原理是安全模型：在大多数 Perfetto 部署中（例如，在 Android 上），只有特权实体（例如，adb shell）可以配置/启动/停止 trace。应用程序在这方面是非特权的，它们无法控制 trace。

触发器提供了一种让非特权应用程序以有限方式控制 trace 会话生命周期的方法。概念模型是：

- 特权 Consumer(参见 [_服务模型_](/docs/concepts/service-model.md))，即通常被授权启动 trace 的实体（例如，Android 中的 adb shell），预先声明 trace 的可能触发器名称及其将执行的操作。
- 非特权实体（任何随机应用程序进程）可以激活这些触发器。非特权实体对触发器将执行的操作没有发言权，它们只是传达事件已发生。

触发器可以通过命令行工具发出信号

```bash
/system/bin/trigger_perfetto "trigger_name"
```

(或者也可以通过启动一个仅使用配置中的 `activate_triggers: "trigger_name"` 字段的独立 trace 会话)

有两种类型的触发器：

#### 启动触发器

启动触发器允许仅在发生某些重大事件后才激活 trace 会话。传递具有 `START_TRACING` 触发器的 trace 配置会导致 trace 会话保持空闲（即不记录任何数据），直到触发器被击中或 `trigger_timeout_ms` 超时被击中。

`trace_duration_ms` 和触发的 trace 不能同时使用。

示例配置：

```protobuf
# 如果击中 "myapp_is_slow",trace 开始记录数据并将在
# 5 秒后停止。
trigger_config {
 trigger_mode: START_TRACING
 triggers {
 name: "myapp_is_slow"
 stop_delay_ms: 5000
 }
 # 如果没有触发器被击中,trace 将在 30 秒后结束而不记录任何数据
 trigger_timeout_ms: 30000
}

# 配置的其余部分照常。
buffers { ... }
data_sources { ... }
```

#### 停止触发器

STOP_TRACING 触发器允许在触发器被击中时过早地完成 trace。在此模式下，trace 在调用 `perfetto` 客户端时立即启动（就像在正常情况下一样）。触发器充当过早完成信号。

这可以用于以飞行记录器模式使用 perfetto。通过启动一个在 `RING_BUFFER` 模式下配置缓冲区并使用 `STOP_TRACING` 触发器的 trace,trace 将被循环记录并在检测到罪魁祸首事件时完成。这对于根本原因在最近过去的事件（例如，应用程序检测到滚动缓慢或丢失帧）是关键。

示例配置：

```protobuf
# 如果没有触发器被击中,trace 将在 30 秒后结束。
trigger_timeout_ms: 30000

# 如果击中 "missed_frame",trace 将在 1 秒后停止。
trigger_config {
 trigger_mode: STOP_TRACING
 triggers {
 name: "missed_frame"
 stop_delay_ms: 1000
 }
}

# 配置的其余部分照常。
buffers { ... }
data_sources { ... }
```

## Android

在 Android 上，使用 `adb shell` 有一些注意事项

- Ctrl+C，通常会导致 trace 的正常终止，在使用 `adb shell perfetto` 时不会被 ADB 传播，但仅在使用通过 `adb shell` 的基于交互式 PTY 的会话时传播。
- 在 Android 12 之前的非 root 设备上，由于过于严格的 SELinux 规则，配置只能作为 `cat config | adb shell perfetto -c -`（-: stdin）传递。从 Android 12 开始，`/data/misc/perfetto-configs` 可用于存储配置。
- 在 Android 10 之前的设备上，adb 无法直接拉取 `/data/misc/perfetto-traces`。使用 `adb shell cat /data/misc/perfetto-traces/trace > trace` 来解决。
- 当捕获较长的 trace 时，例如在基准测试或 CI 的上下文中，使用 `PID=$(perfetto --background)` 然后使用 `kill $PID` 停止。

## 其他资源

- [TraceConfig 参考](/docs/reference/trace-config-proto.autogen)
- [缓冲区和数据流](/docs/concepts/buffers.md)
