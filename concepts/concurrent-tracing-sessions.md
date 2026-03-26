# 并发 trace 会话

Perfetto 支持多个并发 trace 会话。会话彼此隔离，每个会话可以在其 [配置](config.md) 中选择不同的生产者和数据源组合，并且通常它只接收该配置指定的事件。这是一个强大的机制，允许在从实验室或现场收集 trace 时具有很大的灵活性。然而，并发 trace 会话有一些注意事项：

1. [某些数据源不支持并发会话](#某些数据源不支持并发会话)
2. [某些设置是每个会话的，而其他设置是每个生产者的](#某些设置是每个会话的而其他设置是每个生产者的)
3. 由于 [atrace 的工作方式](#atrace)，如果会话请求 *任何* atrace 类别或应用程序，它将接收 *所有* 在设备上启用的 atrace 事件
4. 应用[各种限制](#各种限制)

## 某些数据源不支持并发会话

虽然使用 Perfetto SDK 实现的大多数数据源以及 Perfetto 团队提供的大多数数据源确实支持并发 trace 会话，但有些不支持。这可能是由于：

- 硬件或驱动程序约束
- 实现配置多路复用的困难
- Perfetto SDK：用户可以[选择不支持多个会话](https://cs.android.com/android/platform/superproject/main/+/main:external/perfetto/include/perfetto/tracing/data_source.h;l=266;drc=f988c792c18f93841b14ffa71019fdedf7ab2f03)

### 已知可以工作
- `traced_probes` 数据源（[linux.ftrace](/docs/reference/trace-config-proto.autogen#FtraceConfig）、[linux.process_stats](/docs/reference/trace-config-proto.autogen#ProcessStatsConfig)、[linux.sys_stats](/docs/reference/trace-config-proto.autogen#SysStatsConfig)、[linux.system_info](https://perfetto.dev/docs/reference/trace-config-proto.autogen#SystemInfoConfig) 等)

### 已知可以工作但有注意事项
- `heapprofd` 支持多个会话，但每个进程只能在一个会话中。
- `traced_perf` 通常支持多个会话，但内核对 Counters 有限制，因此可能会拒绝配置。

### 已知不能工作
- `traced metatracing`

## 某些设置是每个会话的而其他设置是每个生产者的

配置中指定的大多数缓冲区大小和时间是每个会话的。例如缓冲区[大小](https://cs.android.com/android/platform/superproject/main/+/main:external/perfetto/protos/perfetto/config/trace_config.proto;l=32?q=f:perfetto%20f:trace_config&ss=android%2Fplatform%2Fsuperproject%2Fmain)。

但是，某些参数配置每个生产者的设置：例如，生产者和 traced 之间的 shmem 缓冲区的[大小和布局](https://cs.android.com/android/platform/superproject/main/+/main:external/perfetto/protos/perfetto/config/trace_config.proto;l=182;drc=488df1649781de42b72e981c5e79ad922508d1e5)。虽然这是通用数据源设置，但同样适用于数据源特定设置。例如， ftrace [内核缓冲区大小和排空周期](https://cs.android.com/android/platform/superproject/main/+/main:external/perfetto/protos/perfetto/config/ftrace/ftrace_config.proto;l=32;drc=6a3d3540e68f3d5949b5d86ca736bfd7f811deff）是必须在 `traced_probes` 的所有用户之间共享的设置。

请记住
- 某些资源（如 shmem 缓冲区）由所有会话共享
- 正如上面链接的代码注释所建议的那样，某些设置最好被视为"提示"，因为另一个配置可能已经在你有机会之前就已经设置了它们。

## Atrace

Atrace 是 Android 特定的机制，用于进行用户空间检测，并且是将 Perfetto SDK 引入 Android 之前唯一可用的 trace 方法。它仍然为 [os.Trace](https://developer.android.com/reference/android/os/Trace)（由平台和应用程序 Java 代码使用）和 [ATRACE_*](https://cs.android.com/android/platform/superproject/main/+/main:system/core/libcutils/include/cutils/trace.h;l=188;drc=0c44d8d68d56c7aecb828d8d87fba7dcb114f3d9)（由平台 C++ 使用）提供支持。


Atrace（Perfetto 之前和通过 Perfetto）的工作方式如下：
- 配置：
  - 用户从硬编码列表中选择零个或多个"类别"
  - 用户选择零个或多个包名称，包括 glob
- 这设置：
  - 某些内核 ftrace 事件
  - [系统属性位掩码](https://cs.android.com/android/platform/superproject/main/+/main:frameworks/native/cmds/atrace/atrace.cpp;l=306;drc=c8af4d3407f3d6be46fafdfc044ace55944fb4b7)(对于 atrace 类别)
  - 每个包的 [系统属性](https://cs.android.com/android/platform/superproject/main/+/main:frameworks/native/cmds/atrace/atrace.cpp;l=306;bpv=1;bpt=1)
- 当调用 Java 或 C++ trace API 时，我们检查系统属性。
- 如果启用了相关类别或包，我们将事件写入 `trace_marker`

如上所述，每个类别可能启用多个内核 ftrace 事件。例如，"sched" atrace 类别启用 `sched/sched_switch` ftrace 事件。内核 ftrace 事件不受当前会话问题的影响，因此不会进一步描述。

对于用户空间检测：
- Perfetto 确保安装所有 atrace 包类别的并集
- 然而，由于：
  - atrace 系统属性是全局的
  - 我们无法判断事件来自哪个类别/包
请求 *任何* atrace 事件的每个会话都会获得 *所有* 启用的 atrace 事件。

## 各种限制
- Perfetto SDK：每个生产者每种数据源类型最多 8 个数据源实例
- `traced`:[15 个并发会话的限制](https://cs.android.com/android/platform/superproject/main/+/main:external/perfetto/src/tracing/service/tracing_service_impl.cc;l=114?q=kMaxConcurrentTracingSessions%20)
- `traced`:[每个 UID 5 个（statsd 为 10 个）并发会话的限制](https://cs.android.com/android/platform/superproject/main/+/main:external/perfetto/src/tracing/service/tracing_service_impl.cc;l=115;drc=17d5806d458e214bdb829deeeb08b098c2b5254d)
