# CPU 频率和空闲状态

此数据源在 Linux 和 Android（自 P 起）上可用。它通过 Linux 内核 ftrace 基础架构记录 CPU 电源管理方案的变化。它涉及三个方面：

#### 频率调节

有两种方法获取 CPU 频率数据：

1. 启用 `power/cpu_frequency` ftrace 事件。（参见下面的 [TraceConfig](#traceconfig)）。这将在内核 cpufreq 缩放驱动程序更改频率时记录一个事件。请注意，并非所有平台都支持此功能。根据我们的经验，它在基于 ARM 的 SoC 上可靠工作，但在大多数现代基于 Intel 的平台上不产生数据。这是因为最近的 Intel CPU 使用由 CPU 直接控制的内部 DVFS，并且不向内核公开频率更改事件。另请注意，即使在基于 ARM 的平台上，也仅在 CPU 频率更改时才发出事件。在许多情况下，CPU 频率在几秒钟内不会更改，这将在 trace 的开头显示为空块。我们建议始终将此与轮询（见下文）结合使用，以获得初始频率的可靠快照。
2. 通过启用 `linux.sys_stats` 数据源并将 `cpufreq_period_ms` 设置为 > 0 的值来轮询 sysfs。这将定期轮询 `/sys/devices/system/cpu/cpu*/cpufreq/cpuinfo_cur_freq` 并将当前值记录在 trace 缓冲区中。在基于 Intel 和 ARM 的平台上都可以工作。

在大多数 Android 设备上，频率调节是基于集群的（大/小核心组），因此看到四组 CPU 同时更改频率并不罕见。

#### 可用频率

还可以通过启用 `linux.system_info` 数据源一次性采集每个 CPU 支持的完整频率列表。这将在 trace 采集开始时记录 `/sys/devices/system/cpu/cpu*/cpufreq/scaling_available_frequencies`。此信息通常通过检查 [`cpu_freq` 表](/docs/analysis/sql-tables.autogen#cpu_freq）来区分大/小核心。

由于上述 `power/cpu_frequency` 的相同原因，现代 Intel 平台不支持此功能。

#### 空闲状态

当没有线程有资格执行时（例如，它们都处于睡眠状态），内核将 CPU 设置为空闲状态，关闭一些电路以减少空闲功耗。大多数现代 CPU 有不止一个空闲状态：更深的空闲状态使用更少的功耗，但也需要更多时间从中恢复。

请注意，空闲转换相对快速且便宜，CPU 每秒可以进入和离开空闲状态数百次。空闲性不得与完全设备挂起混淆，后者是一种更强且更具侵入性的省电状态（见下文）。即使屏幕打开且设备看起来可操作，CPU 也可以处于空闲状态。

关于有多少空闲状态可用及其语义的详细信息高度特定于 CPU/SoC。在 trace 级别，空闲状态 0 表示非空闲，大于 0 的值表示越来越深的省电状态（例如，单核空闲 -> 完整包空闲）。

请注意，只要插入 USB 电缆，大多数 Android 设备就不会进入空闲状态（USB 驱动程序堆栈保持唤醒锁）。通过 USB 收集的 trace 中只看到一个空闲状态并不罕见。

在大多数 SoC 上，当 CPU 空闲时，频率值几乎没有意义，因为 CPU 在空闲状态下通常是被时钟门控的。在这些情况下，trace 中的频率值恰好是 CPU 变为空闲之前运行的最后一个频率。

已知问题：

- 仅在频率更改时才发出事件。这可能长时间不会发生。在短 trace 中，某些 CPU 可能不会报告任何事件，显示 trace 左侧的间隙，或者根本没有。Perfetto 目前在启动 trace 时不记录初始 cpu 频率。

- 当前，如果不捕获空闲状态（见下文），UI 不会呈现 cpufreq track。这是一个仅 UI 的错误，即使未显示，数据也已采集并可通过 Trace Processor 查询。

### UI

在 UI 中，CPU 频率和空闲性显示在同一 track 上。track 的高度表示频率，颜色表示空闲状态（彩色：非空闲，灰色：空闲）。悬停或单击 track 中的点将显示频率和空闲状态：

![](/docs/images/cpu-frequency.png "UI 中的 CPU 频率和空闲状态")

### SQL

在 SQL 级别，频率和空闲状态都建模为 Counters。请注意，cpuidle 值 0xffffffff (4294967295) 意味着 _返回非空闲_。

```sql
select ts, t.name, cpu, value from counter as c
left join cpu_counter_track as t on c.track_id = t.id
where t.name = 'cpuidle' or t.name = 'cpufreq'
```

ts | name | cpu | value
---|------|------|------
261187013242350 | cpuidle | 1 | 0
261187013246204 | cpuidle | 1 | 4294967295
261187013317818 | cpuidle | 1 | 0
261187013333027 | cpuidle | 0 | 0
261187013338287 | cpufreq | 0 | 1036800
261187013357922 | cpufreq | 1 | 1036800
261187013410735 | cpuidle | 1 | 4294967295
261187013451152 | cpuidle | 0 | 4294967295
261187013665683 | cpuidle | 1 | 0
261187013845058 | cpufreq | 0 | 1900800

已知 CPU 频率列表可以使用 [`cpu_freq` 表](/docs/analysis/sql-tables.autogen#cpu_freq) 查询。

### TraceConfig

```protobuf
# 频率和空闲状态更改的事件驱动记录。
data_sources: {
 config {
 name: "linux.ftrace"
 ftrace_config {
 ftrace_events: "power/cpu_frequency"
 ftrace_events: "power/cpu_idle"
 ftrace_events: "power/suspend_resume"
 }
 }
}

# 轮询当前 cpu 频率。
data_sources: {
 config {
 name: "linux.sys_stats"
 sys_stats_config {
 cpufreq_period_ms: 500
 }
 }
}

# 报告每个 CPU 的可用频率列表。
data_sources {
 config {
 name: "linux.system_info"
 }
}
```

### 完整设备挂起

当笔记本电脑进入"睡眠"模式（例如，通过合上盖子）或智能手机显示器关闭足够长时间时，会发生完整设备挂起。

当设备挂起时，大多数硬件单元关闭，进入可能的最高省电状态（除了完全关机）。

请注意，大多数 Android 设备在调暗显示器后不会立即挂起，但如果通过电源按钮强制关闭显示器，则倾向于这样做。细节高度特定于设备/制造商/内核。

已知问题：

- UI 没有清楚地显示挂起状态。当 Android 设备挂起时，看起来好像所有 CPU 都在运行 kmigration 线程，一个 CPU 在运行 power HAL。
