# ATrace：Android 系统和应用 trace 事件

ATrace 是向 Android 应用程序和服务添加自定义 trace 点的标准方法。这些 trace 点可以在 Perfetto UI 中可视化为 Slice 和 Counters。

ATrace API 通过以下表面暴露：

- **Java/Kotlin 应用（SDK）:** [`android.os.Trace`](https://developer.android.com/reference/android/os/Trace)
- **原生进程(NDK):** [`ATrace_beginSection()`](https://developer.android.com/ndk/reference/group/tracing) 和 `ATrace_setCounter()`
- **Android 内部进程：** [`libcutils/trace.h`](https://cs.android.com/android/platform/superproject/main/+/main:system/core/libcutils/include/cutils/trace.h?q=f:trace%20libcutils) 中的 `ATRACE_BEGIN()` 和 `ATRACE_INT()`

此 API 自 Android 4.3（API 级别 18）起可用，早于 Perfetto。所有这些注释（在内部都通过内部 libcutils API 路由）都已被 Perfetto 支持，并将继续受支持。

有两种类型的 atrace 事件：系统事件和应用事件。

**系统事件**：仅由 Android 内部使用 libcutils 发出。这些事件按类别（也称为 _标签_）分组，例如，"am"（ActivityManager）、"pm"（PackageManager）。有关类别的完整列表，请参见 [Perfetto UI](https://ui.perfetto.dev) 的 _采集新 trace_ 页面。

类别可用于跨多个进程启用事件组，而无需担心哪个特定的系统进程发出它们。

**应用事件**：具有与系统事件相同的语义。然而，与系统事件不同，它们没有任何标签过滤能力（所有应用事件共享相同的标签 `ATRACE_TAG_APP`），但可以基于每个应用启用。

有关如何启用系统和应用事件的说明，请参见下面的 [TraceConfig](#traceconfig) 部分。

#### 插桩开销

ATrace 插桩每个事件有 1-10us 的不可忽略的成本。这是因为每个事件涉及字符串化、如果来自托管执行环境则涉及 JNI 调用，以及用户空间 <-> 内核空间往返以将标记写入 `/sys/kernel/debug/tracing/trace_marker`（这是最昂贵的部分）。

鉴于新引入的 [Tracing SDK](/docs/instrumentation/tracing-sdk.md)，我们的团队正在研究 Android 的迁移路径。目前建议继续在 Android 上使用现有的 ATrace API。

[libcutils]: https://cs.android.com/android/platform/superproject/main/+/main:system/core/libcutils/include/cutils/trace.h?q=f:trace%20libcutils

## UI

在 UI 级别，这些函数在进程 track 组的范围内创建 slice 和 counter，如下所示：

![](/docs/images/atrace-slices.png "UI 中的 ATrace Slice")

## SQL

在 SQL 级别，ATrace 事件在标准的 `slice` 和 `counter` 表中可用，以及来自其他数据源的其他 Counter 和 Slice。

### Slice

```sql
select s.ts, t.name as thread_name, t.tid, s.name as slice_name, s.dur
from slice as s left join thread_track as trk on s.track_id = trk.id
left join thread as t on trk.utid = t.utid
```

ts | thread_name | tid | slice_name | dur
---|-------------|-----|------------|----
261190068051612 | android.anim | 1317 | dequeueBuffer | 623021
261190068636404 | android.anim | 1317 | importBuffer | 30312
261190068687289 | android.anim | 1317 | lockAsync | 2269428
261190068693852 | android.anim | 1317 | LockBuffer | 2255313
261190068696300 | android.anim | 1317 | MapBuffer | 36302
261190068734529 | android.anim | 1317 | CleanBuffer | 2211198

### Counter

```sql
select ts, p.name as process_name, p.pid, t.name as counter_name, c.value
from counter as c left join process_counter_track as t on c.track_id = t.id
left join process as p on t.upid = p.upid
```

ts | process_name | pid | counter_name | value
---|--------------|-----|--------------|------
261193227069635 | com.android.systemui | 1664 | GPU completion | 0
261193268649379 | com.android.systemui | 1664 | GPU completion | 1
261193269787139 | com.android.systemui | 1664 | HWC release | 1
261193270330890 | com.android.systemui | 1664 | GPU completion | 0
261193271282244 | com.android.systemui | 1664 | GPU completion | 1
261193277112817 | com.android.systemui | 1664 | HWC release | 0

## TraceConfig

```protobuf
buffers {
 size_kb: 102400
 fill_policy: RING_BUFFER
}

data_sources {
 config {
 name: "linux.ftrace"
 ftrace_config {
 # 启用特定的系统事件标签。
 atrace_categories: "am"
 atrace_categories: "pm"

 # 启用特定应用的事件。
 atrace_apps: "com.google.android.apps.docs"

 # 为所有应用启用所有事件。
 atrace_apps: "*"
 }
 }
}
```
