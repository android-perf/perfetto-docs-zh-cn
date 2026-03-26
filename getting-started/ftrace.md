# 使用 ftrace 插桩 Linux 内核

在本指南中，你将学习如何：
- 使用 ftrace 事件插桩你的内核代码。
- 使用 `tracebox` 采集 ftrace 事件。
- 在 `trace_processor` 中将 ftrace 事件解释为 tracks。
- 在 Perfetto UI 中查看原始事件和解释的 tracks。

本指南适用于想要向 Linux 内核添加自定义插桩并将其与 perfetto 集成的**内核和系统开发者**。

在本地内核上试验并希望简单的 track 可视化而不接触 perfetto 代码的人可以浏览[C部分][section-c-link]。

## 介绍

[Ftrace][ftrace-link] 是内置于 Linux 内核中的可配置 tracing 框架。它允许开发者使用 tracepoints 和 probes 插桩内核，这些 probes 可以在运行时动态启用以记录事件（例如，在给定 CPU 上从一个线程到另一个线程的上下文切换）。用户空间配置要记录的内容，并通过 `tracefs` 文件系统读取生成的 traces，通常挂载在 `/sys/kernel/tracing`。内核预先插桩了数百个可用于理解调度、内存和其他子系统的 tracepoints。

Perfetto 可以[配置][cfg-link]将一组 ftrace 事件记录为 perfetto trace 的一部分。系统采集实现（内置于 traced\_probes 或 tracebox 中）配置 tracefs 并将生成的事件流转换为 perfetto 的 protobuf trace 格式。

查询引擎和 UI 依次具有 ftrace 事件的特定于域的解析。例如，原始上下文切换和唤醒事件在 UI 中转换为每个 CPU 和每个线程的调度 tracks，并由可查询的 SQL 表支持。

TIP: 如果你只是想可视化内核函数的执行，perfetto 对 ftrace 内置的 `function_graph` tracer 具有内置的可视化，不需要任何额外的插桩。有关更多详细信息，请参阅[这些配置选项][funcgraph-cfg-link]。

本页面分为三个部分：
- [A部分][section-a-link]：涵盖创建一个带有静态 tracepoint 的示例内核模块，使用 perfetto 记录事件，以及在 perfetto UI 中查看基本事件数据。
- [B部分][section-b-link](高级)：涵盖通过修改 perfetto 源代码为 tracepoint 添加专用解析。这让你可以充分利用将事件转换为结构化的 SQL 表和 UI tracks。
- [C部分][section-c-link]：作为上述内容的替代，描述了构建 tracepoints 的约定，以便 perfetto 可以自动将它们转换为 slices/instants/counters，**而无需修改 perfetto 源代码**。

[funcgraph-cfg-link]: https://source.chromium.org/chromium/chromium/src/+/main:third_party/perfetto/protos/perfetto/config/ftrace/ftrace_config.proto?q=enable_function_graph
[ftrace-link]: https://www.kernel.org/doc/html/latest/trace/ftrace.html
[cfg-link]: https://source.chromium.org/chromium/chromium/src/+/main:third_party/perfetto/protos/perfetto/config/ftrace/ftrace_config.proto?q=FtraceConfig
[section-a-link]: #part-a-instrumenting-the-kernel-and-recording-tracepoints
[section-b-link]: #part-b-integrating-new-tracepoints-with-perfetto
[section-c-link]: #part-c-simple-slice-counter-visualisations-without-modifying-perfetto-code-kernel-track-events-

## A部分：插桩内核并采集 tracepoints

### 创建内核模块源文件

对于这个示例，我们将创建一个名为 `ticker` 的内核模块，它包含一个名为 `ticker_tick` 的 tracepoint，每秒调用一次，并以递增的 Counter 作为参数。

创建一个新目录并将以下文件内容复制到以下目录结构：

```
.
├── Makefile
├── ticker.c
└── trace
    └── events
        └── ticker.h
```

主要源代码：

```c
// ticker.c

#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/timer.h>
#include <linux/version.h>

#define CREATE_TRACE_POINTS
#include "trace/events/ticker.h"

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Perfetto");
MODULE_DESCRIPTION("Ticker: A kernel module emitting example static tracepoint events.");
MODULE_VERSION("0.1");

static struct timer_list my_timer;
static unsigned int tick_count = 0;
static unsigned long timer_interval_ms = 1000;

static void my_timer_callback(struct timer_list *timer)
{
    // 触发 tracepoint，每次递增 tick 计数。
    // 函数名是头文件中的 trace_<event_name>。
    trace_ticker_tick(tick_count++);

    // 重新设置定时器。
    mod_timer(&my_timer, jiffies + msecs_to_jiffies(timer_interval_ms));
}

static int __init ticker_init(void)
{
    pr_info("Ticker: Initializing...\n");

    timer_setup(&my_timer, my_timer_callback, 0);
    mod_timer(&my_timer, jiffies + msecs_to_jiffies(timer_interval_ms));

    pr_info("Ticker: Timer started.\n");
    pr_info("Ticker: View events under /sys/kernel/tracing/events/ticker/\n");

    return 0;
}

static void __exit ticker_exit(void)
{
    pr_info("Ticker: Exiting...\n");

#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 15, 0)
    timer_delete_sync(&my_timer);
#else
    del_timer_sync(&my_timer);
#endif

    pr_info("Ticker: Timer stopped and module unloaded.\n");
}

module_init(ticker_init);
module_exit(ticker_exit);
```

定义 tracepoints 的头文件。注意，头文件必须位于 `trace/events/` 下，而不是目录的根目录。否则内核宏将无法正确展开：

```h
// trace/events/ticker.h

#undef TRACE_SYSTEM
#define TRACE_SYSTEM ticker

#if !defined(_TRACE_TICKER_H_) || defined(TRACE_HEADER_MULTI_READ)
#define _TRACE_TICKER_H_

#include <linux/tracepoint.h>

TRACE_EVENT(ticker_tick,

    TP_PROTO(unsigned int count),

    TP_ARGS(count),

    TP_STRUCT__entry(
        __field(unsigned int, count)
    ),

    TP_fast_assign(
        __entry->count = count;
    ),

    TP_printk("count=%u",
        __entry->count
    )
);

#endif /* _TRACE_TICKER_H_ */

/* 这部分必须在保护之外 */
#include <trace/define_trace.h>
```

最后，用于构建模块的 makefile：

```makefile
# Makefile

obj-m += ticker.o
ccflags-y += -I$(src)
KDIR ?= /lib/modules/$(shell uname -r)/build
PWD := $(shell pwd)

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean

.PHONY: all clean
```

### 构建和加载模块

确保你的内核头文件已安装并运行 `make` 来构建内核模块。

你现在可以使用以下命令安装内核模块：
```bash
sudo insmod ticker.ko
```

NOTE: 你可以随时使用以下命令卸载内核模块：
```bash
sudo rmmod ticker.ko
```

### （可选）手动验证 tracepoint

我们可以使用 `tracefs` 文件系统查看事件的文本表示来手动验证 tracepoint。

首先，确认事件存在于 tracefs 中：
```bash
ls /sys/kernel/tracing/events/ticker/ticker_tick
```

启用我们的 ticker 事件和 tracing：
```bash
echo 1 | sudo tee /sys/kernel/tracing/events/ticker/ticker_tick/enable
echo 1 | sudo tee /sys/kernel/tracing/tracing_on
```

使用以下命令监听 ftrace 事件流：
```bash
sudo cat /sys/kernel/tracing/trace_pipe
```

你应该会看到 ticker 事件大约每秒触发一次，并带有递增的 "count" 字段。文本事件表示使用上面 tracepoint 定义中的 `TP_printk(...)` 部分打印。

```
# cat /sys/kernel/tracing/trace_pipe
          <idle>-0       [011] ..s1. 850584.176058: ticker_tick: count=38
          <idle>-0       [011] ..s1. 850585.200042: ticker_tick: count=39
           <...>-2904431 [015] ..s1. 850586.224031: ticker_tick: count=40
          puppet-2904431 [015] ..s.. 850587.248080: ticker_tick: count=41
          <idle>-0       [011] ..s1. 850588.272137: ticker_tick: count=42
          <idle>-0       [011] ..s1. 850589.296040: ticker_tick: count=43
          <idle>-0       [011] ..s1. 850590.320049: ticker_tick: count=44
          <idle>-0       [011] ..s1. 850591.344048: ticker_tick: count=45
          <idle>-0       [011] ..s1. 850592.372038: ticker_tick: count=46
          <idle>-0       [011] ..s1. 850593.392033: ticker_tick: count=47
          <idle>-0       [003] ..s1. 850594.416049: ticker_tick: count=48
          <idle>-0       [011] ..s1. 850595.440054: ticker_tick: count=49
```

### 使用 tracebox 采集 perfetto trace

为了记录我们的 ticker 事件，我们将使用 `tracebox` 记录系统 trace。首先，我们需要创建一个配置为执行此操作的记录配置文件：

```
# ticker.cfg

buffers {
  size_kb: 20480
  fill_policy: DISCARD
}

# 仅记录我们的 ticker 事件。
data_sources {
  config {
    name: "linux.ftrace"
    target_buffer: 0
    ftrace_config {
      ftrace_events: "ticker/ticker_tick"
    }
  }
}

# 10s trace，但可以提前停止。
duration_ms: 10000
```

请参阅[系统 tracing 页面](/docs/getting-started/system-tracing.md）以设置 tracebox。对于此示例，我们将使用刚刚创建的配置文件从命令行采集 trace：
```bash
./tracebox -c ticker.cfg --txt -o ticker.pftrace
```

NOTE: tracebox 将负责启用 tracing 和 ticker 事件（如我们在前面的步骤中所做的）。

这将向 `ticker.pftrace` 写入一个 perfetto protobuf trace。

### 在 UI 中查看 perfetto trace

我们现在可以在 perfetto UI 中探索采集的 trace。导航到 https://ui.perfetto.dev 并将文件拖放到窗口中（或按 `Ctrl+O` 打开文件对话框）。

展开 "Ftrace Events" track 组以获取每个 CPU 的事件视图，可以选择这些事件以显示其字段。此外，`Ctrl+shift+P -> "Show Ftrace Tab"` 会打开一个带有文本输出近似的标签页。但是请注意，由于 perfetto 记录事件的二进制表示，它不会根据 `TP_printk(..)` 说明符将事件文本化。

![Raw ticker events](https://storage.googleapis.com/perfetto-misc/ticker-raw.gif)

事件也可以使用如下查询进行查询：
```sql
SELECT * FROM ftrace_event JOIN args USING (arg_set_id)
```

## B部分：将新的 tracepoints 与 perfetto 集成

要为此新 tracepoint 在 Perfetto 中添加专用解析，我们需要：
- 生成事件的 protobuf 描述，以便序列化代码（在 traced\_probes 或 tracebox 中）可以将事件写入该 protobuf 类型，而不是上面隐式使用的通用回退编码。
- 向 trace\_processor（查询引擎）添加解码器，在解析 protobuf trace 时从事件中创建所需的 tracks。

作为示例，我们将把 ticker 事件解析为全局 Counter track。

(我们将修改 perfetto 源代码，因此如果你还没有这样做，请克隆仓库。其余的说明假设你当前的目录是仓库的根目录。)

### 在 perfetto 中生成 protobuf 事件描述

首先，将 tracefs 文件系统中描述事件的 "format" 文件复制到 perfetto：
```sh
DEST=src/traced/probes/ftrace/test/data/synthetic/events/ticker/ticker_tick; \
mkdir -p $DEST && \
cp /sys/kernel/tracing/events/ticker/ticker_tick/format $DEST/format
```

然后将事件添加到以下列表：
```sh
echo "ticker/ticker_tick" >> src/tools/ftrace_proto_gen/event_list
```

然后运行生成器脚本为序列化和解码代码创建 protobuf 描述和其他编译时文件：
```sh
tools/run_ftrace_proto_gen
tools/gen_all out/YOUR_BUILD_DIRECTORY
```

这应该至少创建/修改以下文件：
`protos/perfetto/trace/ftrace/ftrace_event.proto`、
`protos/perfetto/trace/ftrace/ticker.proto`、
`src/traced/probes/ftrace/event_info.cc`、
`protos/perfetto/trace/perfetto_trace.proto`。

这对于序列化逻辑开始使用专用 protobuf 类型处理你的事件已经足够。注意:记录时，perfetto 在运行时读取 tracefs 中事件的 format 文件，并且只序列化在 perfetto 编译时已知的字段。

使用你的更改在本地重建 `tracebox` 并重新采集 trace。

### 在 trace\_processor 中解析事件

现在我们可以向 trace\_processor 中的 [ftrace\_parser.cc][ftrace-parser-link] 添加解码和解析逻辑。

作为示例，要为所有事件创建单个全局 Counter track：
- 向大的 `ParseFtraceEvent` switch-case 添加一个 case。
- 添加一个函数，用于 intern 一个 track 并附加所有带时间戳的值作为计数。

示例添加(省略头文件更改)：

```c++
// ftrace_parser.cc

static constexpr auto kTickerCountBlueprint = tracks::CounterBlueprint(
      "ticker",
      tracks::UnknownUnitBlueprint(),
      tracks::DimensionBlueprints(),
      tracks::StaticNameBlueprint("Ticker"));

// ~~ 省略 ~~

      case FtraceEvent::kTickerEventFieldNumber: {
        ParseTickerEvent(cpu, ts, fld_bytes);
        break;
      }

// ~~ 省略 ~~

void FtraceParser::ParseTickerEvent(uint32_t cpu,
                                    int64_t timestamp,
                                    protozero::ConstBytes data) {
  protos::pbzero::TickerEventFtraceEvent::Decoder ticker_event(data);

  PERFETTO_LOG("Parsing ticker event: %" PRId64 ", %" PRIu32 ", %d",
               timestamp,
               cpu,
               static_cast<int>(ticker_event.count()));

  // 推送全局 Counter。
  TrackId track = context_->track_tracker->InternTrack(kTickerCountBlueprint);
  context_->event_tracker->PushCounter(
      timestamp, static_cast<double>(ticker_event.count()), track);
}
```

重建 `trace_processor`（或整个 UI）后，可以从 Counter 表中查询数据：
```
SELECT *
FROM counter
JOIN counter_track ct ON ct.id = counter.track_id
WHERE ct.type = 'ticker'
```

### 在 UI 中可视化 track

为了真正在 UI 中看到这个 track，它需要由一些 UI 代码添加（在 perfetto 中组织为插件）。我们将使用最简单的选项，`dev.perfetto.TraceProcessorTrack`。进行以下编辑以将所有类型为 "ticker" 的 Counter tracks 添加到 `SYSTEM` 顶级组：

```ts
// ui/src/plugins/dev.perfetto.TraceProcessorTrack/counter_tracks.ts
~~ 省略 ~~
  {
    type: 'ticker',
    topLevelGroup: 'SYSTEM',
    group: undefined,
  },
~~ 省略 ~~
```

重建本地 UI(`ui/run-dev-server`)。打开重新采集的 trace(使用具有事件编译时知识的 tracebox)。你现在应该看到一个专用 UI track 显示你事件的数据。

![Ticker counter track](https://storage.googleapis.com/perfetto-misc/ticker-counter-track.gif)

这是将 ftrace 事件添加到 perfetto 栈的最完整方式。步骤相当多，需要上游你的更改，但这让你有能力在 trace\_processor 代码中进行任意解析，并使结果可供所有 perfetto 用户使用。

[ftrace-parser-link]: https://source.chromium.org/chromium/chromium/src/+/main:third_party/perfetto/src/trace_processor/importers/ftrace/ftrace_parser.cc?q=FtraceParser

## C部分：无需修改 perfetto 代码的简单 slice/counter 可视化(内核 track 事件)

有一种更简单的方法可以让 perfetto 自动从事件创建基本的 slice 和 counter tracks，更适合在本地内核上试验或编写不会上游到主线内核的模块的人。这让你专注于插桩代码，而不是更改 perfetto 本身。

考虑 slice 的情况，通常源自一对事件——一个表示 slice 的开始，另一个结束它。需要有一个约定让 perfetto 知道给定的 tracepoint 应该被这样解释。

perfetto 所做的是查找具有特定名称的 tracepoint 字段(`TP_STRUCT__entry(..)` 定义部分)。如果你的 tracepoint 符合此约定，trace\_processor 和 UI 将自动尝试将事件分组到 tracks 上。分组（范围）由进一步的约定控制。

以下部分给出了几种常见情况的示例 tracepoint 模板及其预期的可视化：
- 用于同步代码的 slice tracks，其中操作在与启动它们的同一线程上结束，例如在单个函数中的循环前后。
- 用于在进程级别分组时最佳可视化的事件的进程范围 slice tracks。
- 用于表示每 CPU Counters 的事件的 CPU 范围 counter tracks。

NOTE: 有关范围和 track 命名选项的详细信息，请参阅完整参考["Kernel track events: format and conventions"][trackevent-reference-link]。

[trackevent-reference-link]: /docs/reference/kernel-track-event

### 线程范围 slice tracks

如果你想要可视化（可能嵌套的）代码区域的持续时间，其中开始和结束发生在同一线程上，这是最简单的情况。

Perfetto 可以通过在 tracepoint 的布局中具有两个具有"众所周知"的名称和类型的字段来提示你的 tracepoint 应该被解析为线程范围 slice tracks(`TP_STRUCT__entry(...`))：
- `char track_event_type`
- `__string slice_name`

Perfetto 将根据实际带时间戳事件中的 `track_event_type` 值将事件解释为 slices 或 instants：
- `'B'` 在活动线程上打开一个命名 slice(来自 `slice_name`)。
- `'E'` 结束线程上最后打开的 slice(`slice_name` 被忽略)。
- `'I'` 设置一个 instant（零持续时间）事件，名称取自 `slice_name`。

线程 id 和时间戳已经隐式地是每个 ftrace 事件的一部分，不需要指定。

Tracepoint 声明示例，名为 `trk_example/tid_track_example`：

_注意:在早于 v6.10 的内核上，\_\_assign\_str 需要两个参数，请参阅[this patch](https://lore.kernel.org/linux-trace-kernel/20240516133454.681ba6a0@rorschach.local.home/)。_

```h
// trace/events/trk_example.h
#undef TRACE_SYSTEM
#define TRACE_SYSTEM trk_example

#if !defined(_TRACE_TRK_EXAMPLE_H_) || defined(TRACE_HEADER_MULTI_READ)
#define _TRACE_TRK_EXAMPLE_H_

#include <linux/tracepoint.h>

TRACE_EVENT(tid_track_example,
    TP_PROTO(
        char track_event_type,
        const char *slice_name
    ),
    TP_ARGS(track_event_type, slice_name),
    TP_STRUCT__entry(
        __field(char, track_event_type)
        __string(slice_name, slice_name)
    ),
    TP_fast_assign(
        __entry->track_event_type = track_event_type;
        /* v6.10 之前的内核：__assign_str(slice_name, slice_name) */
        __assign_str(slice_name);
    ),
    TP_printk(
        "type=%c slice_name=%s",
        __entry->track_event_type,
        __get_str(slice_name)
    )
);

#endif

/* 这部分必须在保护之外 */
#include <trace/define_trace.h>
```

注意，只有 `TP_STRUCT__entry` 的类型和名称很重要，对额外字段、printk 说明符甚至字段顺序没有限制。

为方便起见，tracepoint 调用可以用宏包装：
```h
// 便捷宏
#define TRACE_EX_BEGIN(name)   trace_tid_track_example('B', name)
#define TRACE_EX_END()         trace_tid_track_example('E', "")
#define TRACE_EX_INSTANT(name) trace_tid_track_example('I', name)
```

插桩代码示例，演示嵌套 slices 和 instants：
```c
TRACE_EX_BEGIN("outer");
udelay(500);
for (int i=0; i < 3; i++) {
    TRACE_EX_BEGIN("nested");
    udelay(1000);
    TRACE_EX_INSTANT("instant");
    TRACE_EX_END();
}
TRACE_EX_END();
```

我们可以使用以下配置采集 trace(在撰写本文时，`denser_generic_event_encoding` 是必要的，但可能会成为默认值)：

```
// trace.txtpb
duration_ms: 10000

buffers: {
  size_kb: 40960
  fill_policy: DISCARD
}

data_sources: {
  config: {
    name: "linux.ftrace"
    ftrace_config: {
      denser_generic_event_encoding: true
      ftrace_events: "trk_example/*"
    }
  }
}
```

由 perfetto trace\_processor 和 UI 自动派生的结果 tracks。注意每个线程都有自己的独立 track，并且 tracks 自动嵌套在进程 track 组下：

![thread scoped slice UI](/docs/images/kernel-trackevent-tid-slice.png)

### 进程范围 slice tracks

与前面的示例类似，但 slice 事件在进程级别分组。注意:这允许从与启动操作不同的线程终止 slices，但分组的 slices *必须*具有严格的嵌套——所有 slices 必须在它们的父项之前终止（有关更多详细信息，请参阅 [async slices][async-slice-link] 的概念）。

[async-slice-link]: /docs/getting-started/converting#asynchronous-slices-and-overlapping-events

这种解析类型在 `TP_STRUCT__entry` 中的预期字段：
- `char track_event_type`
- `__string slice_name`
- `int scope_tgid`

前两个字段的解释与前面的示例相同，而 `scope_tgid` 必须填充该特定事件应分组在下的进程 id(又名 TGID)。进程 id 应该是真实的（不要硬编码任意常量），但触发线程不必在该进程中。

Tracepoint 声明示例，名为 `trk_example/tgid_track_example`：

```h
// trace/events/trk_example.h
#undef TRACE_SYSTEM
#define TRACE_SYSTEM trk_example

#if !defined(_TRACE_TRK_EXAMPLE_H_) || defined(TRACE_HEADER_MULTI_READ)
#define _TRACE_TRK_EXAMPLE_H_

#include <linux/tracepoint.h>

TRACE_EVENT(tgid_counter_example,
    TP_PROTO(
        u64 counter_value,
        int scope_tgid
    ),
    TP_ARGS(counter_value, scope_tgid),
    TP_STRUCT__entry(
        __field(u64, counter_value)
        __field(int, scope_tgid)
    ),
    TP_fast_assign(
        __entry->counter_value = counter_value;
        __entry->scope_tgid = scope_tgid;
    ),
    TP_printk(
        "counter_value=%llu tgid=%d",
        (unsigned long long)__entry->counter_value,
        __entry->scope_tgid
    )
);

#endif

/* 这部分必须在保护之外 */
#include <trace/define_trace.h>
```

示例便捷宏，使用当前进程上下文（`current->tgid`）对事件进行分组：

```h
// 便捷宏
#define TRACE_EX_BEGIN(name)   trace_tgid_track_example('B', name, current->tgid)
#define TRACE_EX_END()         trace_tgid_track_example('E', "", current->tgid)
#define TRACE_EX_INSTANT(name) trace_tgid_track_example('I', name, current->tgid)
```

插桩代码示例，与之前相同：
```c
TRACE_EX_BEGIN("outer");
udelay(500);
for (int i=0; i < 3; i++) {
    TRACE_EX_BEGIN("nested");
    udelay(1000);
    TRACE_EX_INSTANT("instant");
    TRACE_EX_END();
}
TRACE_EX_END();
```

使用前面示例中的配置采集时的结果可视化。所有 slice 堆栈都在进程级别聚合：

![process scoped slice UI](/docs/images/kernel-trackevent-tgid-slice.png)

### CPU 范围 counter tracks

与 slices 和 instants 类似，tracepoints 有约定可以自动在 perfetto 中显示为 tracks。counters 也可以按线程/进程分组，但此示例演示每 CPU 分组。

这种解析类型在 `TP_STRUCT__entry` 中的预期字段：
- `u64 counter_value`(接受任何整数类型)
- `int scope_cpu`

Tracepoint 声明示例，名为 `trk_example/cpu_counter_example`：

```h
// trace/events/trk_example.h
#undef TRACE_SYSTEM
#define TRACE_SYSTEM trk_example

#if !defined(_TRACE_TRK_EXAMPLE_H_) || defined(TRACE_HEADER_MULTI_READ)
#define _TRACE_TRK_EXAMPLE_H_

#include <linux/tracepoint.h>

TRACE_EVENT(cpu_counter_example,

    TP_PROTO(
        u64 counter_value,
        int scope_cpu
    ),

    TP_ARGS(counter_value, scope_cpu),
    TP_STRUCT__entry(
        __field(u64, counter_value)
        __field(int, scope_cpu)
    ),
    TP_fast_assign(
        __entry->counter_value = counter_value;
        __entry->scope_cpu = scope_cpu;
    ),
    TP_printk(
        "counter_value=%llu cpu=%d",
        (unsigned long long)__entry->counter_value,
        __entry->scope_cpu
    )
);

#endif

/* 这部分必须在保护之外 */
#include <trace/define_trace.h>
```

插桩代码示例：
```c
static unsigned int n = 0

trace_cpu_counter_example(n++, smp_processor_id());
```

使用前面示例中的配置采集时的结果可视化。Counter 增量归因于执行 tracepoint 的 CPU(由于使用 `smp_processor_id()` 作为 CPU 索引，但如果对 tracepoint 更有意义，我们可以同样使用静态索引)：

![cpu scoped counter UI](/docs/images/kernel-trackevent-cpu-counter.png)
