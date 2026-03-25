# 使用 Perfetto 记录性能 Counters 和 CPU profiling

在本指南中，你将学习如何：

- 使用 Perfetto 记录 CPU profiles 和性能 Counters。
- 收集调用栈 profiles 以识别性能瓶颈。
- 在 Perfetto UI 中可视化和 profile CPU profiles。

在 linux 和 android 上，perfetto 可以记录每个 CPU 的 [perf Counters](https://perfwiki.github.io/main/)，例如执行的指令或缓存未命中等硬件事件。此外，perfetto 可以配置为基于这些性能 Counters 采样运行进程的调用栈。这两种模式都类似于 perf 工具的 `perf record` 命令，并使用相同的系统调用（`perf_event_open`）。

如果你只对 profiling（即火焰图）感兴趣，请跳转到["Collecting a callstack profile"](#collecting-a-callstack-profile)。

## 使用 perf counters 收集 trace

记录使用通常的 perfetto config protobuf 定义，并且可以自由地与 ftrace 等其他数据源组合。这允许混合 trace 在单个时间轴上显示采样 Counter 值以及其他 trace 数据，例如进程调度。

数据源配置([PerfEventConfig](https://source.chromium.org/chromium/chromium/src/+/main:third_party/perfetto/protos/perfetto/config/profiling/perf_event_config.proto?q=PerfEventConfig))定义以下内容：

- **[Timebase](https://source.chromium.org/chromium/chromium/src/+/main:third_party/perfetto/protos/perfetto/common/perf_events.proto?q=Timebase)(或组领导者)**： 正在计数的主要事件。此事件在每个 CPU 上分别计数。
- **采样周期/频率**： Counter 采样的频率。这可以是一个固定的 `period`（例如，每 1000 个事件）或一个 `frequency`(例如，每秒 100 次)。
- **[Followers](https://source.chromium.org/chromium/chromium/src/+/main:third_party/perfetto/protos/perfetto/common/perf_events.proto?q=FollowerEvent)**： 要记录的任何其他 Counters。这些 Counters 在 timebase 事件的同时被快照。

一个 trace 配置可以为单独的采样组定义多个"linux.perf"数据源。但请注意，如果计算硬件事件，你需要小心不要超过平台的 PMU 容量。否则内核将多路复用（重复切换进出）事件组，导致计数不足（参见[this perfwiki page](https://perfwiki.github.io/main/tutorial/#multiplexing-and-scaling-events）了解更多信息)。

### 配置示例

此配置为每个 CPU 定义一组三个 Counters。定时器事件（`SW_CPU_CLOCK`）用作领导者，提供稳定的采样速率。每个采样还包括自 trace 开始以来的 cpu 周期（`HW_CPU_CYCLES`）和执行的指令（`HW_INSTRUCTIONS`）的计数。

```protobuf
duration_ms: 10000

buffers: {
 size_kb: 40960
 fill_policy: DISCARD
}

# sample per-cpu counts of instructions and cycles
data_sources {
 config {
 name: "linux.perf"
 perf_event_config {
 timebase {
 frequency: 1000
 counter: SW_CPU_CLOCK
 timestamp_clock: PERF_CLOCK_MONOTONIC
 }
 followers { counter: HW_CPU_CYCLES }
 followers { counter: HW_INSTRUCTIONS }
 }
 }
}

# include scheduling data via ftrace
data_sources: {
 config: {
 name: "linux.ftrace"
 ftrace_config: {
 ftrace_events: "sched/sched_switch"
 ftrace_events: "sched/sched_waking"
 }
 }
}

# include process names and grouping via procfs
data_sources: {
 config: {
 name: "linux.process_stats"
 process_stats_config {
 scan_all_processes_on_start: true
 }
 }
}
```

在 UI 中展开"Perf Counters"track 组后，应该看起来类似于以下内容。counter tracks 默认将值显示为计数率。

![Perf counter trace in the UI](/docs/images/perf-counter-ui.png)

counter 数据可以查询如下：

```sql
select ts, cpu, name, value
from counter c join perf_counter_track pct on (c.track_id = pct.id)
order by 1, 2 asc
```

### 录制说明

<?tabs>

TAB: Android (command line)

先决条件：
- 主机上已安装 [ADB](https://developer.android.com/studio/command-line/adb)。
- 一台运行 Android 15+ 的设备，使用 USB 连接到主机并已授权 ADB。

从 perfetto repo 下载 `tools/record_android_trace` python 脚本。该脚本自动将配置推送到设备，调用 perfetto，从设备拉取写入的 trace，并在 UI 中打开它。
```bash
curl -LO https://raw.githubusercontent.com/google/perfetto/main/tools/record_android_trace
```

假设上面的示例配置保存为 `/tmp/config.txtpb`，开始记录：
```bash
python3 record_android_trace -c /tmp/config.txtpb -o /tmp/trace.pb
```

采集将在 10 秒后停止（由配置中的 duration_ms 设置），可以通过按 ctrl-c 提前停止。停止后，脚本应该会自动打开 perfetto UI 并显示 trace。

TAB: Linux (command line)

下载(或从源代码构建)`tracebox` 二进制文件，它将大多数 perfetto 数据源的记录实现打包在一起。
```bash
curl -LO https://get.perfetto.dev/tracebox
chmod +x tracebox
```

更改 ftrace 和 perf 事件记录的 Linux 权限。以下内容可能就足够了，具体取决于你的特定发行版：
```bash
sudo chown -R $USER /sys/kernel/tracing
echo -1 | sudo tee /proc/sys/kernel/perf_event_paranoid
```

**或者**，在后续步骤中以 root 身份（使用 sudo）运行 `tracebox`。

假设上面的示例配置保存为 `/tmp/config.txtpb`，开始记录。
```bash
./tracebox -c /tmp/config.txtpb --txt -o /tmp/trace.pb
```

在 [Perfetto UI](https://ui.perfetto.dev) 中打开 `/tmp/trace.pb` 文件。

</tabs?>

## 收集调用栈 profile

Counter 记录也可以配置为包含在 Counter 采样时被中断进程的调用栈（相互调用的函数帧列表）。这是通过要求内核在每个样本中记录额外的状态（用户空间寄存器状态，栈内存顶部），并在 profiler 中展开 + 符号化调用栈来实现的。展开在进程外部发生，不需要在被 profile 的进程中进行插桩或注入库。

要启用调用栈 profiling，请在数据源配置中设置 [`callstack_sampling`]（https://source.chromium.org/chromium/chromium/src/+/main:third_party/perfetto/protos/perfetto/config/profiling/perf_event_config.proto?q=%22optional%20CallstackSampling%20callstack_sampling%20%3D%2016;%22）字段。请注意，采样仍将按每个 CPU 执行，但你可以设置 [`scope`]（https://source.chromium.org/chromium/chromium/src/+/main:third_party/perfetto/protos/perfetto/config/profiling/perf_event_config.proto?q=%22optional%20Scope%20scope%20%3D%201;%22）字段，以便 profiler 仅展开匹配进程的调用栈（这反过来有助于防止 profiler 因展开运行时成本而过载）。

### 配置示例

以下是基于时间进行周期性采样的配置示例（即每个 CPU 定时器领导者），仅在运行给定名称的进程时展开调用栈。

通过更改 `timebase`，你可以改为在其他事件上捕获调用栈，例如，你可以通过将"sched/sched_waking"设置为 `tracepoint` timebase 来查看进程唤醒其他线程时的调用栈。

Android 注意:该示例使用"com.android.settings"作为示例，但要成功进行调用栈采样，应用必须在 manifest 中声明为 [profileable 或 debuggable](https://developer.android.com/guide/topics/manifest/profileable-element)(或者你必须处于 Android 操作系统的 debuggable 构建上)。

```protobuf
duration_ms: 10000

buffers: {
 size_kb: 40960
 fill_policy: DISCARD
}

# periodic sampling per cpu, unwinding callstacks if
# "com.android.settings" is running.
data_sources {
 config {
 name: "linux.perf"
 perf_event_config {
 timebase {
 counter: SW_CPU_CLOCK
 frequency: 100
 timestamp_clock: PERF_CLOCK_MONOTONIC
 }
 callstack_sampling {
 scope {
 target_cmdline: "com.android.settings"
 }
 kernel_frames: true
 }
 }
 }
}

# include scheduling data via ftrace
data_sources: {
 config: {
 name: "linux.ftrace"
 ftrace_config: {
 ftrace_events: "sched/sched_switch"
 ftrace_events: "sched/sched_waking"
 }
 }
}

# include process names and grouping via procfs
data_sources: {
 config: {
 name: "linux.process_stats"
 process_stats_config {
 scan_all_processes_on_start: true
 }
 }
}
```

### 录制说明

<?tabs>

TAB: Android (command line)

先决条件：
- 主机上已安装 [ADB](https://developer.android.com/studio/command-line/adb)。
- 一台运行 Android 15+ 的设备，使用 USB 连接到主机并已授权 ADB。
- 一个 [_Profileable_ 或 _Debuggable_](https://developer.android.com/topic/performance/benchmarking/macrobenchmark-instrumentation#profileable-apps) 应用。如果你在 Android 的"user"构建上运行（相对于"userdebug"或"eng"），你的应用需要在 manifest 中标记为 profileable 或 debuggable。

对于 android,`tools/cpu_profile` 辅助 python 脚本简化了 trace config 的构建，并具有用于 profile 的后符号化（对于没有符号信息的库）以及转换为更适合纯火焰图可视化的 [pprof](https://github.com/google/pprof) 格式的附加选项。它可以按如下方式下载：
```bash
curl -LO https://raw.githubusercontent.com/google/perfetto/main/tools/cpu_profile
```

开始使用基于时间的周期性采样记录（即每个 CPU 定时器领导者），仅在运行给定名称的进程时展开调用栈。请注意，非 native 调用栈展开起来可能很昂贵，因此我们建议将采样频率保持在每 CPU 200 Hz 以下。
```bash
python3 cpu_profile -n com.android.example -f 100
```

可以通过按 ctrl-c 停止采集。然后脚本将在 /tmp/ 下打印一个路径，其中放置了输出，该目录中的 `raw-trace` 文件可以在 [Perfetto UI](https://ui.perfetto.dev) 中打开，而 `profile.*.pb` 是"pprof"文件格式中每个进程的聚合 profiles。

有关更多标志，请参见 `cpu_profile --help`，特别是 `-c` 允许你提供自己的 textproto config，同时利用脚本化记录和输出转换。

#### 缺失符号和反混淆

如果你的 profiles 缺少 native 库的函数名称，但你有权访问库的调试版本（带有符号数据），你可以按照[这些说明]（/docs/data-sources/native-heap-profiler#symbolization）指示 `cpu_profile` 脚本在主机上符号化 profile，同时替换脚本名称。

TAB: Linux (command line)

下载(或从源代码构建)`tracebox` 二进制文件，它将大多数 perfetto 数据源的记录实现打包在一起。
```bash
curl -LO https://get.perfetto.dev/tracebox
chmod +x tracebox
```

更改 ftrace 和 perf 事件记录的 Linux 权限。以下内容可能就足够了，具体取决于你的特定发行版（请注意添加的 kptr_restrict 覆盖，如果你想查看内核函数名称）。
```bash
sudo chown -R $USER /sys/kernel/tracing
echo -1 | sudo tee /proc/sys/kernel/perf_event_paranoid
echo 0 | sudo tee /proc/sys/kernel/kptr_restrict
```

**或者**，在后续步骤中以 root 身份（使用 sudo）运行 `tracebox`。

假设上面的示例配置保存为 `/tmp/config.txtpb`(已将 target_cmdline 选项更改为你机器上的进程)，开始记录。
```bash
./tracebox -c /tmp/config.txtpb --txt -o /tmp/trace.pb
```

采集停止后，在 [Perfetto UI](https://ui.perfetto.dev) 中打开 `/tmp/trace.pb` 文件。

要将 trace 转换为"pprof"格式的每个进程 profiles，你可以按如下方式使用 `traceconv` 脚本：

```bash
python3 traceconv profile --perf /tmp/trace.pb
```

#### 缺失符号和反混淆

如果你的 profiles 缺少 native 库的函数名称，但你有权访问库的调试版本（带有符号数据），你可以按照[这些说明]（/docs/data-sources/native-heap-profiler#symbolization）事后符号化 profile，跳过 heap profiling 脚本，而是直接使用 `traceconv symbolize` 脚本命令。

</tabs?>

### 在 Perfetto UI 中可视化 profile

在 UI 中，调用栈样本将显示为时间轴上的即时事件，在被采样进程的进程 track 组内。每个被采样的线程都有一个 track，以及一个结合该进程所有样本的单个 track。通过选择具有 perf 样本的时间区域，底部窗格将显示所选调用栈的动态火焰图视图。

![callstack profile in the UI](/docs/images/perf-callstack-ui.png)

样本数据也可以通过 SQL 从 [`perf_sample`](/docs/analysis/sql-tables.autogen#perf_sample) 表查询。

### 查询 trace

除了在时间轴上可视化 trace 之外，Perfetto 还支持使用 SQL 查询 trace。执行此操作的最简单方法是使用 UI 中直接可用的查询引擎。

1. 在 Perfetto UI 中，点击左侧菜单中的"Query (SQL)"标签。

 ![Perfetto UI Query SQL](/docs/images/perfetto-ui-query-sql.png)

2. 这将打开一个两部分窗口。你可以在顶部部分编写 PerfettoSQL 查询，并在底部部分查看结果。

 ![Perfetto UI SQL Window](/docs/images/perfetto-ui-sql-window.png)

3. 然后你可以执行查询 Ctrl/Cmd + Enter:

例如，通过运行：

```
INCLUDE PERFETTO MODULE linux.perf.samples;

SELECT
 -- 调用栈的 id。在此上下文中，调用栈是直到根的唯一帧集。
 id,
 -- 此调用栈的父调用栈的 id。
 parent_id,
 -- 此调用栈的帧的函数名称。
 name,
 -- 包含帧的映射的名称。这可以是 native 二进制文件、库、JAR 或 APK。
 mapping_name,
 -- 包含函数的文件的名称。
 source_file,
 -- 文件中函数所在的行号。
 line_number,
 -- 以此函数为叶帧的样本数。
 self_count,
 -- 以此函数出现在调用栈上任何位置的样本数。
 cumulative_count
FROM linux_perf_samples_summary_tree;
```

你可以看到在 trace 中捕获的所有调用栈的摘要树。

### 替代方案

perfetto profiling 实现是为连续（流式）收集构建的，因此对于短期、高频 profiling 的优化较少。如果你只需要聚合火焰图，请考虑 Android 上的 `simpleperf` 和 Linux 上的 `perf`。这些工具对此用例更成熟，并且具有更简单的用户界面。

## 后续步骤

现在你已经记录了你的第一个 CPU profile，你可以探索更高级的主题：

### 更多关于 trace 分析

- **[Perfetto UI](/docs/visualization/perfetto-ui.md)** ： 了解 trace viewer 的所有功能。
- **[Trace Analysis with SQL](/docs/analysis/getting-started.md)** ： 学习如何使用 Trace Processor 和 PerfettoSQL 分析 trace。

### 与其他数据源结合

你也可以在与 CPU 采样相同的时间轴上包括其他数据源，以获得更完整的系统性能图。

- **[Scheduling events](/docs/data-sources/cpu-scheduling.md)** ： 获取有关哪些线程在哪些 CPU 上运行的详细信息。
- **[CPU Frequency](/docs/data-sources/cpu-freq.md)** ： 查看 CPU 频率如何随时间变化。
- **[System Calls](/docs/data-sources/syscalls.md)** ： Trace 系统调用的入口和出口。
