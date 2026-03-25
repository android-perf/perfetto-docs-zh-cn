# Android Log

_此数据源仅在 Android userdebug 构建上受支持。_

"android.log" 数据源记录来自 Android Log 守护程序（`logd`）的 Log event。这些是通过 `adb logcat` 可用的相同 Log message。

支持来自 [EventLog] 的文本格式事件和二进制格式事件。

这允许你查看与 trace 的其余部分时间同步的 Log event。当采集[长 trace]（/docs/concepts/config#long-traces）时，它允许你无限期地采集 Event log，而不管 Android Log 守护程序缓冲区大小如何（即，Log event 定期获取并复制到 trace 缓冲区中）。

数据源可以配置为过滤来自特定 Log buffer 的事件，并仅保留匹配特定标签或优先级的事件。

[EventLog]: https://developer.android.com/reference/android/util/EventLog

### UI

在 UI 级别，Log event 在两个小部件中显示：

1. 一个摘要 track，允许快速查看事件的分布及其在 Timeline 上的严重性。

2. 一个与视口时间同步的表格，允许在选定的时间范围内查看事件。

![](/docs/images/android_logs.png "UI 中的 Android Log")

### SQL

```sql
select l.ts, t.tid, p.pid, p.name as process, l.prio, l.tag, l.msg
from android_logs as l left join thread as t using(utid) left join process as p using(upid)
```
ts | tid | pid | process | prio | tag | msg
---|-----|-----|---------|------|-----|----
291474737298264 | 29128 | 29128 | traced_probes | 4 | perfetto | probes_producer.cc:231 Ftrace setup (target_buf=1)
291474852699265 | 625 | 625 | surfaceflinger | 3 | SurfaceFlinger | Finished setting power mode 1 on display 0
291474853274109 | 1818 | 1228 | system_server | 3 | SurfaceControl | Excessive delay in setPowerMode()
291474882474841 | 1292 | 1228 | system_server | 4 | DisplayPowerController | Unblocked screen on after 242 ms
291474918246615 | 1279 | 1228 | system_server | 4 | am_pss | Pid=28568 UID=10194 Process Name="com.google.android.apps.fitness" Pss=12077056 Uss=10723328 SwapPss=183296 Rss=55021568 StatType=0 ProcState=18 TimeToCollect=51

### TraceConfig

Trace proto:
[AndroidLogPacket](/docs/reference/trace-packet-proto.autogen#AndroidLogPacket)

Config proto:
[AndroidLogConfig](/docs/reference/trace-config-proto.autogen#AndroidLogConfig)

示例配置：

```protobuf
data_sources: {
 config {
 name: "android.log"
 android_log_config {
 min_prio: PRIO_VERBOSE
 filter_tags: "perfetto"
 filter_tags: "my_tag_2"
 log_ids: LID_DEFAULT
 log_ids: LID_RADIO
 log_ids: LID_EVENTS
 log_ids: LID_SYSTEM
 log_ids: LID_CRASH
 log_ids: LID_KERNEL
 }
 }
}
```
