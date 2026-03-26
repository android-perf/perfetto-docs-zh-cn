# 将任意时间戳数据转换为 Perfetto

在本指南中，你将学习如何：

- 将你自己的时间戳数据转换为 Perfetto trace 格式。
- 创建自定义 tracks、slices 和 counters。
- 在 Perfetto UI 中可视化你的自定义数据。

如果你有来自自己系统的现有日志或时间戳数据，你不需要错过 Perfetto 强大的可视化和 profile 功能。通过将你的数据转换为 Perfetto 的原生基于 protobuf 的 trace 格式，你可以创建可以在 Perfetto UI 中打开并使用 Trace Processor 查询的合成 traces。

本页面提供了如何以编程方式生成这些合成 traces 的指南。

## 基础：Perfetto 的 Trace 格式

Perfetto trace 文件（`.pftrace` 或 `.perfetto-trace`）是一系列 [TracePacket](/protos/perfetto/trace/trace_packet.proto) 消息，包装在根 [Trace](/protos/perfetto/trace/trace.proto) 消息中。每个 `TracePacket` 可以包含各种类型的数据。

对于从自定义数据生成 traces，在 `TracePacket` 中最常用和最灵活的负载是 [TrackEvent](/protos/perfetto/trace/track_event/track_event.proto)。`TrackEvent` 允许你定义：

- **Tracks**：一段时间内事件的单一序列（slices 或 counter）。对应于 Perfetto UI 中的单个"泳道"。
- **Slices**：具有名称、开始时间戳和持续时间的事件（例如，函数调用、任务）。
- **Counters**：随时间变化的数值（例如，内存使用、自定义 metrics）。
- **Flows**：连接不同 tracks 上相关 slices 的箭头。

## 以编程方式生成 Traces

本指南中的示例使用 Python 和 `perfetto` Python 库中的帮助器类来演示如何构造这些 protobuf 消息。但是，底层原理和 protobuf 定义与语言无关。你可以在任何具有 Protocol Buffer 支持的编程语言中生成 Perfetto traces。

- **官方 Protobuf 库：** Google 为以下语言提供官方 protobuf 编译器和运行时库：
  [Java](https://protobuf.dev/reference/java/java-generated/)、
  [C++](https://protobuf.dev/reference/cpp/cpp-generated/)、
  [Python](https://protobuf.dev/reference/python/python-generated/)、
  [Go](https://protobuf.dev/reference/go/go-generated/) 和
  [更多](https://protobuf.dev/reference/)。
- **第三方库：** 许多第三方库也为广泛的语言提供 protobuf 支持。

无论使用什么语言，核心任务都是根据 Perfetto [protobuf schemas](https://source.chromium.org/chromium/chromium/src/+/main:third_party/perfetto/protos/perfetto/trace/) 构造 `TracePacket` 消息并将它们序列化为二进制文件。

### Python 脚本模板

对于以下部分中的 Python 示例，我们将使用脚本模板。此脚本处理创建 trace 文件和序列化 `TracePacket` 消息的基础知识。你将使用要创建的 trace 数据类型的特定逻辑填充 `populate_packets` 函数。

首先，确保你已安装 `perfetto` 库，它提供了必要的 protobuf 类，可能还有一个构建器实用程序（如你设计的 `TraceProtoBuilder` 类或库中的等效项）。

```bash
pip install perfetto
```

这是 Python 脚本模板。将此保存为 `trace_converter_template.py` 或类似名称。每个后续示例将向你展示在 `populate_packets` 函数中放置什么代码。

<details>
<summary><b>点击展开/折叠 Python 代码</b></summary>

```python
#!/usr/bin/env python3
import uuid

from perfetto.trace_builder.proto_builder import TraceProtoBuilder
from perfetto.protos.perfetto.trace.perfetto_trace_pb2 import TrackEvent, TrackDescriptor, ProcessDescriptor, ThreadDescriptor

def populate_packets(builder: TraceProtoBuilder):
    """
    在这里，你将定义并将 TracePackets 添加到 trace。
    以下部分中的示例将提供要在此处插入的特定代码。

    参数:
        builder: 一个 TraceProtoBuilder 实例，用于添加 packets。
    """
    # ======== 在此处开始你的数据包创建代码 ========
    # 示例(稍后将由特定示例替换)：
    #
    # packet = builder.add_packet()
    # packet.timestamp = 1000
    # packet.track_event.type = TrackEvent.TYPE_SLICE_BEGIN
    # packet.track_event.name = "My Example Event"
    # packet.track_event.track_uuid = 12345
    #
    # packet2 = builder.add_packet()
    # packet2.timestamp = 2000
    # packet2.track_event.type = TrackEvent.TYPE_SLICE_END
    # packet2.track_event.track_uuid = 12345
    #
    # ========  在此处结束你的数据包创建代码  ========

    # 添加代码时删除此 'pass'
    pass


def main():
    """
    初始化 TraceProtoBuilder，调用 populate_packets 填充它，
    然后将生成的 trace 写入文件。
    """
    builder = TraceProtoBuilder()
    populate_packets(builder)

    output_filename = "my_custom_trace.pftrace"
    with open(output_filename, 'wb') as f:
      f.write(builder.serialize())

    print(f"Trace written to {output_filename}")
    print(f"Open with [https://ui.perfetto.dev](https://ui.perfetto.dev).")

if __name__ == "__main__":
    main()
```

</details>

**使用此模板：**

1. 将上面的代码保存为 Python 文件（例如 `trace_converter_template.py`）。
2. 对于以下部分中的每个示例（例如，"Thread-scoped slices"、"Counters"），复制该部分提供的 Python 代码并将其粘贴到 `trace_converter_template.py` 文件中的 `populate_packets` 函数中，替换示例占位符内容。
3. 运行脚本：`python trace_converter_template.py`。这将生成 `my_custom_trace.pftrace`。

TraceProtoBuilder 类（从 `perfetto` pip 包导入）帮助管理构成 `Trace` 的 `TracePacket` 消息列表。`populate_packets` 函数是你根据特定数据定义这些 packets 内容的地方。

## 创建基本 Timeline Slices

在 Perfetto 中表示活动的最基本方式是"slice"。slice 只是一个具有开始时间和持续时间的命名事件。Slices 存在于"tracks"上，tracks 是 Perfetto UI 中的可视 Timeline。本质上，slices 用于任何你想说"一个命名活动发生在特定时间间隔内"的情况。

Slices 可以表示的常见示例包括：

- 特定**函数正在执行**的时间间隔。
- 等待服务器响应网络请求的**时间间隔**。
- **资源（如图像、脚本或数据文件）加载**所需的时间。
- 应用生命周期中特定阶段的持续时间，如"解析数据"或"渲染帧"。

要从自定义数据创建 slices，你通常需要：

1.  定义一个 **track**，你的 slices 将出现在其中。这是使用 `TrackDescriptor` 数据包完成的。对于基本自定义数据，你可以创建一个不绑定到特定进程或线程的通用 track。
2.  对于数据中的每个事件，发出 `TrackEvent` 数据包以标记 slice 的开始和结束。

### Python 示例

假设你有表示任务的数据，具有名称、开始时间和结束时间。以下是如何将它们转换为自定义 track 上的 Perfetto slices。此第一个示例将显示不同的、非嵌套的 slices 和单个 instant 事件。

将以下 Python 代码复制到 `trace_converter_template.py` 脚本中的 `populate_packets(builder)` 函数。

<details>
<summary><b>点击展开/折叠 Python 代码</b></summary>

```python
    # 定义此 packets 序列的唯一 ID(每个 trace 生产者生成一次)
    TRUSTED_PACKET_SEQUENCE_ID = 1001 # 选择任何唯一的整数

    # 为你的自定义 track 定义唯一的 UUID(生成一个 64 位随机数)
    CUSTOM_TRACK_UUID = 12345678 # 示例 UUID

    # 1. 定义自定义 Track
    # 此数据包描述将显示事件的 track。
    # 在 trace 开始时发出一次。
    packet = builder.add_packet()
    packet.track_descriptor.uuid = CUSTOM_TRACK_UUID
    packet.track_descriptor.name = "My Custom Data Timeline"

    # 2. 为此自定义 track 发出事件
    # 示例事件 1："Task A"
    packet = builder.add_packet()
    packet.timestamp = 1000  # 开始时间(纳秒)
    packet.track_event.type = TrackEvent.TYPE_SLICE_BEGIN
    packet.track_event.track_uuid = CUSTOM_TRACK_UUID # 与 track 关联
    packet.track_event.name = "Task A"
    packet.trusted_packet_sequence_id = TRUSTED_PACKET_SEQUENCE_ID

    packet = builder.add_packet()
    packet.timestamp = 1500  # 结束时间(纳秒)
    packet.track_event.type = TrackEvent.TYPE_SLICE_END
    packet.track_event.track_uuid = CUSTOM_TRACK_UUID
    packet.trusted_packet_sequence_id = TRUSTED_PACKET_SEQUENCE_ID

    # 示例事件 2："Task B" - 稍后发生的单独、非嵌套任务
    packet = builder.add_packet()
    packet.timestamp = 1600  # 开始时间(纳秒)
    packet.track_event.type = TrackEvent.TYPE_SLICE_BEGIN
    packet.track_event.track_uuid = CUSTOM_TRACK_UUID
    packet.track_event.name = "Task B"
    packet.trusted_packet_sequence_id = TRUSTED_PACKET_SEQUENCE_ID

    packet = builder.add_packet()
    packet.timestamp = 1800  # 结束时间(纳秒)
    packet.track_event.type = TrackEvent.TYPE_SLICE_END
    packet.track_event.track_uuid = CUSTOM_TRACK_UUID
    packet.trusted_packet_sequence_id = TRUSTED_PACKET_SEQUENCE_ID

    # 示例事件 3：瞬时事件
    packet = builder.add_packet()
    packet.timestamp = 1900 # 时间戳(纳秒)
    packet.track_event.type = TrackEvent.TYPE_INSTANT
    packet.track_event.track_uuid = CUSTOM_TRACK_UUID
    packet.track_event.name = "Milestone Y"
    packet.trusted_packet_sequence_id = TRUSTED_PACKET_SEQUENCE_ID
```

</details>

运行脚本后，在 [Perfetto UI](https://ui.perfetto.dev) 中打开生成的 `my_custom_trace.pftrace` 将显示以下输出：

![Basic Timeline Slices](/docs/images/converting-basic-slices.png)

你可以在 Perfetto UI 的 Query 标签页中使用 SQL 或使用 [Trace Processor](/docs/analysis/getting-started.md) 查询这些 slices：
```sql
SELECT ts, dur, name FROM slice 
JOIN track ON slice.track_id = track.id 
WHERE track.name = 'My Custom Data Timeline';
```

## 嵌套 Slices(分层活动)

通常，一个活动或操作由几个子活动组成，这些子活动必须在主活动完成之前完成。嵌套 slices 非常适合表示这些分层关系。关键规则是子 slices 必须在父 slice 开始之后开始，并在父 slice 结束之前结束。

这在以下情况非常常见：

- **函数执行：** 函数调用（父 slice）包含对其他函数的调用（子 slices）。
- **结构化并发：** 诸如 Kotlin Coroutines 之类的操作，其中子 coroutines 在父 coroutine 的范围内启动，并且必须在父级完成之前完成。
- **较大操作的阶段：** 诸如"编译模块"（父级）之类的复杂任务可能有不同的阶段，如"词法分析"、"解析"、"优化"和"代码生成"作为嵌套的子 slices。
- **UI 渲染管道：** "RenderFrame" slice 可能包含"Measure Pass"、"Layout Pass"和"Draw Pass"作为子 slices。
- **带有子操作的请求处理：** 处理"ProcessHTTPRequest"（父级）的 Web 服务器可能有嵌套的 slices，如"ParseHeaders"、"AuthenticateUser"、"FetchDataFromDB"和"RenderResponse"。

Perfetto UI 将直观地嵌套这些 slices，使层次结构清晰。

### Python 示例

此示例演示在自定义 track 上创建多个嵌套 slices 堆栈。packets 按时间戳顺序发出以正确表示嵌套。我们将在 `populate_packets` 中定义一个小的帮助函数 `add_event` 以减少样板代码。

将以下 Python 代码复制到 `trace_converter_template.py` 脚本中的 `populate_packets(builder)` 函数。

<details>
<summary><b>点击展开/折叠 Python 代码</b></summary>

```python
    # 定义此 packets 序列的唯一 ID
    TRUSTED_PACKET_SEQUENCE_ID = 2002 # 为此示例使用新的 ID

    # 为此示例的自定义 track 定义唯一的 UUID
    NESTED_SLICE_TRACK_UUID = 987654321 # 示例 UUID

    # 1. 定义用于嵌套 Slices 的自定义 Track
    # 开始时发出一次。
    packet = builder.add_packet()
    packet.track_descriptor.uuid = NESTED_SLICE_TRACK_UUID
    packet.track_descriptor.name = "My Nested Operations Timeline"

    # 添加 TrackEvent 数据包的帮助函数
    def add_event(ts, event_type, name=None):
        packet = builder.add_packet()
        packet.timestamp = ts
        packet.track_event.type = event_type
        packet.track_event.track_uuid = NESTED_SLICE_TRACK_UUID
        if name:
            packet.track_event.name = name
        packet.trusted_packet_sequence_id = TRUSTED_PACKET_SEQUENCE_ID

    # --- 堆栈 1：Operation Alpha ---
    add_event(ts=2000, event_type=TrackEvent.TYPE_SLICE_BEGIN, name="Operation Alpha")
    add_event(ts=2050, event_type=TrackEvent.TYPE_SLICE_BEGIN, name="Alpha.LoadConfig")
    add_event(ts=2150, event_type=TrackEvent.TYPE_SLICE_END) # 关闭 Alpha.LoadConfig
    add_event(ts=2200, event_type=TrackEvent.TYPE_SLICE_BEGIN, name="Alpha.Execute")
    add_event(ts=2250, event_type=TrackEvent.TYPE_SLICE_BEGIN, name="Alpha.Execute.SubX")
    add_event(ts=2350, event_type=TrackEvent.TYPE_SLICE_END) # 关闭 Alpha.Execute.SubX
    add_event(ts=2400, event_type=TrackEvent.TYPE_SLICE_BEGIN, name="Alpha.Execute.SubY")
    add_event(ts=2500, event_type=TrackEvent.TYPE_SLICE_END) # 关闭 Alpha.Execute.SubY
    add_event(ts=2800, event_type=TrackEvent.TYPE_SLICE_END) # 关闭 Alpha.Execute
    add_event(ts=3000, event_type=TrackEvent.TYPE_SLICE_END) # 关闭 Operation Alpha

    # --- 堆栈 2：Operation Beta(在同一 track 上) ---
    add_event(ts=3200, event_type=TrackEvent.TYPE_SLICE_BEGIN, name="Operation Beta")
    add_event(ts=3250, event_type=TrackEvent.TYPE_SLICE_BEGIN, name="Beta.Initialize")
    add_event(ts=3350, event_type=TrackEvent.TYPE_SLICE_END) # 关闭 Beta.Initialize
    add_event(ts=3400, event_type=TrackEvent.TYPE_SLICE_BEGIN, name="Beta.Process")
    add_event(ts=3700, event_type=TrackEvent.TYPE_SLICE_END) # 关闭 Beta.Process
    add_event(ts=3800, event_type=TrackEvent.TYPE_SLICE_END) # 关闭 Operation Beta

    # --- 所有堆栈后的独立 slice ---
    add_event(ts=4000, event_type=TrackEvent.TYPE_SLICE_BEGIN, name="Cleanup")
    add_event(ts=4100, event_type=TrackEvent.TYPE_SLICE_END) # 关闭 Cleanup
```

</details>

运行脚本后，在 [Perfetto UI](https://ui.perfetto.dev) 中打开生成的 `my_custom_trace.pftrace` 将显示以下输出：

![Nested Slices](/docs/images/converting-nested.png)

你可以在 Perfetto UI 的 Query 标签页中使用 SQL 或使用 [Trace Processor](/docs/analysis/getting-started.md) 查询这些嵌套 slices 并查看它们的层次结构：
```sql
SELECT ts, dur, name, depth FROM slice
JOIN track ON slice.track_id = track.id
WHERE track.name = 'My Nested Operations Timeline'
ORDER BY ts;
```

## 异步 Slices 和重叠事件

许多系统处理异步操作，其中多个活动可以同时进行，并且它们的生命周期可以重叠而无需严格嵌套。示例包括：

- **网络请求：** 进程可能并发发出多个网络请求。
- **广播接收器(Android)：** 应用可以接收多个广播 intents。每个的处理可以重叠。
- **Wakelocks(Android/Linux)：** 多个组件可以同时持有 wakelocks。
- **文件 I/O 操作：** 程序可能启动多个对不同文件的异步读取或写入操作。

在这些场景中，如果你使用的是开始/结束 slice 语义，则无法将所有这些重叠事件表示在单个 track 上，因为 `TYPE_SLICE_END` 总是关闭该特定 track 上最近打开的 slice。

Perfetto 对此进行建模的方式是将每个并发的、可能重叠的操作分配到其**自己的唯一 track(具有唯一的 UUID)**。为了在 Perfetto UI 中实现这些相关异步操作的视觉分组，你可以给这些单独的操作 tracks 的每个 `TrackDescriptor` 指定**相同的 `name`**(例如，"Network Connections"或"File I/O")。slices 本身在这些 tracks 上可以有不同的名称（例如，"GET :/api/data"、"Read /config.txt"）。

Perfetto UI 将组合或视觉上合并具有相同名称的 tracks。这是约定，可以由用户控制。有关更多详细信息，请参阅有关控制合并的部分：
[synthetic track event reference docs](/docs/reference/synthetic-track-event.md#controlling-track-merging)。

### Python 示例

假设我们正在跟踪活动网络连接。每个连接都是一个独立的异步事件。我们将给所有连接 tracks 相同的名称以鼓励 UI 对它们进行分组。我们将使用帮助函数来定义 tracks 和添加事件。

将以下 Python 代码复制到 `trace_converter_template.py` 脚本中的 `populate_packets(builder)` 函数：

<details>
<summary><b>点击展开/折叠 Python 代码</b></summary>

```python
    TRUSTED_PACKET_SEQUENCE_ID = 3003
    # 用于 UI 分组的所有单个连接 tracks 的通用名称
    ASYNC_TRACK_GROUP_NAME = "HTTP Connections"

    # 使用唯一 UUID 定义新 track 的帮助函数
    def define_track(group_name):
        track_uuid = uuid.uuid4().int & ((1 << 63) - 1)
        packet = builder.add_packet()
        packet.track_descriptor.uuid = track_uuid
        packet.track_descriptor.name = group_name
        return track_uuid

    # 向特定 track 添加开始或结束 slice 事件的帮助函数
    def add_slice_event(ts, event_type, event_track_uuid, name=None):
        packet = builder.add_packet()
        packet.timestamp = ts
        packet.track_event.type = event_type
        packet.track_event.track_uuid = event_track_uuid
        if name:
            packet.track_event.name = name
        packet.trusted_packet_sequence_id = TRUSTED_PACKET_SEQUENCE_ID

    # --- 网络连接 1 ---
    conn1_track_uuid = define_track(ASYNC_TRACK_GROUP_NAME)
    add_slice_event(ts=1000, event_type=TrackEvent.TYPE_SLICE_BEGIN, event_track_uuid=conn1_track_uuid, name="GET /data/config")
    add_slice_event(ts=1500, event_type=TrackEvent.TYPE_SLICE_END, event_track_uuid=conn1_track_uuid)

    # --- 网络连接 2(与连接 1 重叠) ---
    conn2_track_uuid = define_track(ASYNC_TRACK_GROUP_NAME)
    add_slice_event(ts=1100, event_type=TrackEvent.TYPE_SLICE_BEGIN, event_track_uuid=conn2_track_uuid, name="POST /submit/form")
    add_slice_event(ts=2000, event_type=TrackEvent.TYPE_SLICE_END, event_track_uuid=conn2_track_uuid)

    # --- 网络连接 3(在 1 结束后开始，与 2 重叠) ---
    conn3_track_uuid = define_track(ASYNC_TRACK_GROUP_NAME)
    add_slice_event(ts=1600, event_type=TrackEvent.TYPE_SLICE_BEGIN, event_track_uuid=conn3_track_uuid, name="GET /status/check")
    add_slice_event(ts=2200, event_type=TrackEvent.TYPE_SLICE_END, event_track_uuid=conn3_track_uuid)
```

</details>

运行脚本后，在 [Perfetto UI](https://ui.perfetto.dev) 中打开生成的 `my_custom_trace.pftrace` 将显示以下输出：

![Asynchronous Slices](/docs/images/converting-async-slices.png)

你可以在 Perfetto UI 的 Query 标签页中使用 SQL 或使用 [Trace Processor](/docs/analysis/getting-started.md) 查询跨所有 HTTP 连接 tracks 的这些重叠 slices：
```sql
SELECT ts, dur, name FROM slice
JOIN track ON slice.track_id = track.id
WHERE track.name = 'HTTP Connections'
ORDER BY ts;
```

## Counters(随时间变化的值)

Counters 用于表示随时间变化的数值。它们非常适合跟踪非基于事件的 metrics 或状态，而是反映连续或采样数量的 metrics 或状态。

Counters 可以表示的常见示例包括：

- **内存使用：** 进程消耗的总内存，或特定的内存池。
- **CPU 频率：** CPU 核心的当前运行频率。
- **队列大小：** 网络队列或工作队列中未完成请求的数量。
- **电池百分比：** 剩余的电池电量。
- **资源限制：** 资源（如文件描述符或正在利用的网络带宽）的当前值。

要创建 counter track，你需要：

1.  为你的 counter 定义一个 `TrackDescriptor`。此 track 需要一个 `uuid`、一个 `name`，重要的是，它的 `counter` 字段应该被填充。这告诉 Perfetto 将此 track 视为 counter。
2.  发出带有 `type: TYPE_COUNTER` 的 `TrackEvent` packets。每个这样的 packet 应该有一个 `timestamp` 和一个 `counter_value`(可以是整数或双精度浮点数)。

### Python 示例

假设我们想要跟踪随时间变化的未完成网络请求的数量。

将以下 Python 代码复制到 `trace_converter_template.py` 脚本中的 `populate_packets(builder)` 函数。

<details>
<summary><b>点击展开/折叠 Python 代码</b></summary>

```python
    TRUSTED_PACKET_SEQUENCE_ID = 4004
    # Counter track 的 UUID
    OUTSTANDING_REQUESTS_TRACK_UUID = uuid.uuid4().int & ((1 << 63) - 1)

    # 1. 定义 Counter Track
    packet = builder.add_packet()
    track_desc = packet.track_descriptor
    track_desc.uuid = OUTSTANDING_REQUESTS_TRACK_UUID
    track_desc.name = "Outstanding Network Requests"
    # 要将此标记为 counter track，请设置 'counter' 字段为存在。
    track_desc.counter.SetInParent()

    # 添加 counter 事件的帮助函数
    def add_counter_event(ts, value):
        packet = builder.add_packet()
        packet.timestamp = ts
        packet.track_event.type = TrackEvent.TYPE_COUNTER
        packet.track_event.track_uuid = OUTSTANDING_REQUESTS_TRACK_UUID
        packet.track_event.counter_value = value
        packet.trusted_packet_sequence_id = TRUSTED_PACKET_SEQUENCE_ID

    # 2. 随时间发出 counter 值
    add_counter_event(ts=1000, value=0)
    add_counter_event(ts=1100, value=1) # 一个请求开始
    add_counter_event(ts=1200, value=2) # 第二个请求开始
    add_counter_event(ts=1300, value=3) # 第三个请求开始
    add_counter_event(ts=1400, value=2) # 第一个请求完成
    add_counter_event(ts=1500, value=2) # 无变化
    add_counter_event(ts=1600, value=1) # 第二个请求完成
    add_counter_event(ts=1700, value=0) # 第三个请求完成
    add_counter_event(ts=1800, value=1) # 新请求开始
    add_counter_event(ts=1900, value=0) # 最后一个请求完成
```

</details>

运行脚本后，在 [Perfetto UI](https://ui.perfetto.dev) 中打开生成的 `my_custom_trace.pftrace` 将显示以下输出：

![Counters](/docs/images/converting-counters.png)

你可以在 Perfetto UI 的 Query 标签页中使用 SQL 或使用 [Trace Processor](/docs/analysis/getting-started.md) 查询 counter 值：
```sql
SELECT ts, value FROM counter
JOIN track ON counter.track_id = track.id
WHERE track.name = 'Outstanding Network Requests';
```

## Flows(连接因果关系事件)

Flows 用于在视觉上连接具有显式因果或依赖关系的 slices，特别是当这些 slices 发生在不同的 tracks 上时（如不同的线程甚至不同的进程）。它们对于理解系统一个部分中的操作如何触发或启用另一个部分中的操作至关重要。

将 flows 视为从"原因"或"调度"事件到"结果"或"处理"事件绘制箭头。常见场景包括：

- UI 线程将任务调度到工作线程：flow 将调度 slice 连接到工作线程上的执行 slice。
- 服务对另一个服务进行 RPC/IPC 调用：flow 可以将客户端调用启动链接到服务器端请求处理。
- 事件被发布到消息队列并稍后处理：flow 可以显示从发布到处理的链接。

在 Perfetto 的 `TrackEvent` 模型中，你通过以下方式建立 flow：

1.  将一个或多个唯一的 64 位 `flow_id` 分配给属于 flow 的 `TrackEvent`。此 ID 充当链接。
2.  通常，`flow_id` 被添加到 `TYPE_SLICE_BEGIN` 或 `TYPE_SLICE_END` 事件，以标记从/到该 slice 的因果链接的起点或终点。
3.  然后将相同的 `flow_id` 添加到另一个 `TrackEvent`(通常是不同 track 上的 `TYPE_SLICE_BEGIN`)，以显示该因果链接操作的继续或处理。

Perfetto UI 将绘制箭头连接共享共同 `flow_id` 的 slices，使依赖链显式化。

**替代方案：Correlation IDs** 对于属于相同逻辑操作但不是因果连接的事件，请考虑使用 correlation IDs 代替或除了 flows。Correlation IDs 将相关事件视觉上分组（例如，使用一致的颜色）而不暗示因果关系。有关详细信息，请参阅高级指南中的
[Linking Related Events with Correlation IDs](/docs/reference/synthetic-track-event.md#linking-related-events-with-correlation-ids）部分。

### Python 示例

让我们建模一个简单的系统，其中"Request Handler" track 将工作调度到"Data Processor" track。我们将使用 flows 将请求调度链接到其处理，然后将处理完成链接回处理程序确认完成。

将以下 Python 代码复制到 `trace_converter_template.py` 脚本中的 `populate_packets(builder)` 函数。

<details>
<summary><b>点击展开/折叠 Python 代码</b></summary>

```python
    TRUSTED_PACKET_SEQUENCE_ID = 5005

    # --- 定义自定义 Tracks ---
    REQUEST_HANDLER_TRACK_UUID = uuid.uuid4().int & ((1 << 63) - 1)
    DATA_PROCESSOR_TRACK_UUID = uuid.uuid4().int & ((1 << 63) - 1)

    # Request Handler Track
    packet = builder.add_packet()
    packet.track_descriptor.uuid = REQUEST_HANDLER_TRACK_UUID
    packet.track_descriptor.name = "Request Handler"

    # Data Processor Track
    packet = builder.add_packet()
    packet.track_descriptor.uuid = DATA_PROCESSOR_TRACK_UUID
    packet.track_descriptor.name = "Data Processor"

    # 添加 slice 事件(BEGIN 或 END)的帮助函数
    def add_slice_event(ts, event_type, event_track_uuid, name=None, flow_ids=None):
        packet = builder.add_packet()
        packet.timestamp = ts
        packet.track_event.type = event_type
        packet.track_event.track_uuid = event_track_uuid
        if name:
            packet.track_event.name = name
        if flow_ids:
            for flow_id in flow_ids:
                packet.track_event.flow_ids.append(flow_id)
        packet.trusted_packet_sequence_id = TRUSTED_PACKET_SEQUENCE_ID

    # --- 为因果链接定义唯一的 flow IDs ---
    DISPATCH_TO_PROCESS_FLOW_ID = uuid.uuid4().int & ((1<<63)-1)
    PROCESS_COMPLETION_FLOW_ID = uuid.uuid4().int & ((1<<63)-1)

    # 1. Request Handler：调度数据处理(第一个 flow 的起点)
    add_slice_event(ts=1000, event_type=TrackEvent.TYPE_SLICE_BEGIN,
                    event_track_uuid=REQUEST_HANDLER_TRACK_UUID, name="DispatchProcessing",
                    flow_ids=[DISPATCH_TO_PROCESS_FLOW_ID])
    add_slice_event(ts=1050, event_type=TrackEvent.TYPE_SLICE_END,
                    event_track_uuid=REQUEST_HANDLER_TRACK_UUID)

    # 2. Data Processor：处理数据(来自处理程序的调度的 flow)
    # 此 slice 的 BEGIN 事件包含 DISPATCH_TO_PROCESS_FLOW_ID，链接它。
    # 它也从其 BEGIN 事件开始 PROCESS_COMPLETION_FLOW_ID。
    add_slice_event(ts=1100, event_type=TrackEvent.TYPE_SLICE_BEGIN,
                    event_track_uuid=DATA_PROCESSOR_TRACK_UUID, name="ProcessDataItem",
                    flow_ids=[DISPATCH_TO_PROCESS_FLOW_ID, PROCESS_COMPLETION_FLOW_ID])
    add_slice_event(ts=1300, event_type=TrackEvent.TYPE_SLICE_END,
                    event_track_uuid=DATA_PROCESSOR_TRACK_UUID)

    # 3. Request Handler：确认完成(PROCESS_COMPLETION_FLOW_ID 在此结束)
    add_slice_event(ts=1350, event_type=TrackEvent.TYPE_SLICE_BEGIN,
                    event_track_uuid=REQUEST_HANDLER_TRACK_UUID, name="AcknowledgeCompletion",
                    flow_ids=[PROCESS_COMPLETION_FLOW_ID])
    add_slice_event(ts=1400, event_type=TrackEvent.TYPE_SLICE_END,
                    event_track_uuid=REQUEST_HANDLER_TRACK_UUID)
```

</details>

运行脚本后，在 [Perfetto UI](https://ui.perfetto.dev) 中打开生成的 `my_custom_trace.pftrace` 将显示以下输出：

![Flows](/docs/images/converting-flows.png)

你可以在 Perfetto UI 的 Query 标签页中使用 SQL 或使用 [Trace Processor](/docs/analysis/getting-started.md) 查询 slices 之间的 flow 连接：
```sql
SELECT slice_out.name AS source_slice, slice_in.name AS dest_slice
FROM flow
JOIN slice AS slice_out ON flow.slice_out = slice_out.id
JOIN slice AS slice_in ON flow.slice_in = slice_in.id;
```

## 使用层次结构对 Tracks 进行分组

随着 traces 变得更加复杂，你可能希望将相关的 tracks 组合在一起，以创建更有组织且易于理解的可视化。Perfetto 允许你使用 `TrackDescriptor` 中的 `parent_uuid` 字段定义 tracks 之间的父子关系。

这在以下情况下很有用：

- 你有一个高级组件（父 track），包含几个子组件（子 tracks），并且你希望在 UI 中看到它们分组。
- 你想要为不同类型的异步事件或不同的 counters 集创建逻辑分组。
- 你正在表示具有固有层次结构的系统（例如，具有多个 GPU 的机器，每个 GPU 具有多个引擎）。

父 track 可以服务于两个主要目的：

- **纯分组：** 父 track 本身可能没有任何直接事件（slices 或 counters），但仅作为将其子 tracks 分组在 UI 中的容器。
- **摘要 Track：** 父 track 也可以有自己的 slices 或 counters。这些可以代表其子 tracks 中详细活动的概述或摘要，或与其自身相关的独立事件集。

Perfetto UI 通常会将这些渲染为可展开的树。

### Python 示例

让我们创建一个层次结构：

- 一个"Main System" track，它也将有自己的 summary slice。
- "Main System" 的两个子 tracks："Subsystem A"和"Subsystem B"。
- "Subsystem A" 将进一步拥有自己的子 track，"Detail A.1"。
- 然后我们将在父"Main System" track、"Subsystem B"和最深的子 track "Detail A.1"上放置 slices。

将以下 Python 代码复制到 `trace_converter_template.py` 脚本中的 `populate_packets(builder)` 函数。

<details>
<summary><b>点击展开/折叠 Python 代码</b></summary>

```python
    TRUSTED_PACKET_SEQUENCE_ID = 6006

    # --- 定义 Track UUIDs ---
    main_system_track_uuid = uuid.uuid4().int & ((1 << 63) - 1)
    subsystem_a_track_uuid = uuid.uuid4().int & ((1 << 63) - 1)
    subsystem_b_track_uuid = uuid.uuid4().int & ((1 << 63) - 1)
    detail_a1_track_uuid = uuid.uuid4().int & ((1 << 63) - 1)

    # 定义 TrackDescriptor 的帮助函数
    def define_custom_track(track_uuid, name, parent_track_uuid=None):
        packet = builder.add_packet()
        desc = packet.track_descriptor
        desc.uuid = track_uuid
        desc.name = name
        if parent_track_uuid:
            desc.parent_uuid = parent_track_uuid

    # 添加 slice 事件的帮助函数
    def add_slice_event(ts, event_type, event_track_uuid, name=None):
        packet = builder.add_packet()
        packet.timestamp = ts
        packet.track_event.type = event_type
        packet.track_event.track_uuid = event_track_uuid
        if name:
            packet.track_event.name = name
        packet.trusted_packet_sequence_id = TRUSTED_PACKET_SEQUENCE_ID

    # 1. 定义 Track 层次结构
    define_custom_track(main_system_track_uuid, "Main System")
    define_custom_track(subsystem_a_track_uuid, "Subsystem A", parent_track_uuid=main_system_track_uuid)
    define_custom_track(subsystem_b_track_uuid, "Subsystem B", parent_track_uuid=main_system_track_uuid)
    define_custom_track(detail_a1_track_uuid, "Detail A.1", parent_track_uuid=subsystem_a_track_uuid)

    # 2. 在层次结构中的各种 tracks 上发出 slices

    # 在父"Main System" track 上的 slice(摘要/总体活动)
    add_slice_event(ts=4800, event_type=TrackEvent.TYPE_SLICE_BEGIN,
                    event_track_uuid=main_system_track_uuid, name="System Initialization Phase")
    add_slice_event(ts=7000, event_type=TrackEvent.TYPE_SLICE_END,
                    event_track_uuid=main_system_track_uuid)

    # 在"Detail A.1"(子"Subsystem A")上的 slice
    add_slice_event(ts=5000, event_type=TrackEvent.TYPE_SLICE_BEGIN,
                    event_track_uuid=detail_a1_track_uuid, name="Activity in A.1")
    add_slice_event(ts=5500, event_type=TrackEvent.TYPE_SLICE_END,
                    event_track_uuid=detail_a1_track_uuid)

    # 在"Subsystem B"上的 slice
    add_slice_event(ts=6000, event_type=TrackEvent.TYPE_SLICE_BEGIN,
                    event_track_uuid=subsystem_b_track_uuid, name="Work in Subsystem B")
    add_slice_event(ts=6200, event_type=TrackEvent.TYPE_SLICE_END,
                    event_track_uuid=subsystem_b_track_uuid)

    # 在"Detail A.1"上的另一个 slice
    add_slice_event(ts=5600, event_type=TrackEvent.TYPE_SLICE_BEGIN,
                    event_track_uuid=detail_a1_track_uuid, name="Further Activity in A.1")
    add_slice_event(ts=5800, event_type=TrackEvent.TYPE_SLICE_END,
                    event_track_uuid=detail_a1_track_uuid)
```

</details>

运行脚本后，在 [Perfetto UI](https://ui.perfetto.dev) 中打开生成的 `my_custom_trace.pftrace` 将显示以下输出：

![Grouping Tracks with Hierarchies](/docs/images/converting-track-groups.png)

你可以在 Perfetto UI 的 Query 标签页中使用 SQL 或使用 [Trace Processor](/docs/analysis/getting-started.md) 查询跨 track 层次结构的 slices：
```sql
SELECT slice.ts, slice.dur, slice.name, track.name AS track_name
FROM slice 
JOIN track ON slice.track_id = track.id 
WHERE track.name IN ('Main System', 'Subsystem A', 'Subsystem B', 'Detail A.1')
ORDER BY slice.ts;
```

## 用于瀑布图 / Trace 视图的 Track 层次结构

Track 层次结构的另一个强大用途是可视化复杂操作或请求的分解，类似于分布式 tracing 系统中显示"trace 视图"或"span 视图"的方式。这在操作涉及跨不同逻辑组件的顺序或并行步骤时非常有用，并且你希望以瀑布图或甘特图样式查看这些步骤的时间和关系。

在此模型中：

- **根 track** 代表整个端到端请求或操作。
- 该操作中的每个**主要步骤、函数调用或 RPC 调用**都表示为**父在根 track 下的子 track**(或如果它是子子步骤，则在另一个步骤下)。
- 每个子 track 上的**slice**显示该特定步骤的持续时间。
- `parent_uuid` 字段创建层次结构。UI 通常会将这些渲染为可展开的树，这些层次结构排列的 tracks 上 slices 的开始/结束时间创建"瀑布"效果。

### Python 示例：服务请求分解

假设前端服务发出一个请求，涉及调用两个后端服务：Authentication Service 和 Data Service。只有在 Authentication Service 调用完成后才能进行 Data Service 调用。

将以下 Python 代码复制到 `trace_converter_template.py` 脚本中的 `populate_packets(builder)` 函数。

<details>
<summary><b>点击展开/折叠 Python 代码</b></summary>

```python
    TRUSTED_PACKET_SEQUENCE_ID = 7007

    # --- 定义 Track UUIDs ---
    root_request_track_uuid = uuid.uuid4().int & ((1 << 63) - 1)
    auth_service_call_track_uuid = uuid.uuid4().int & ((1 << 63) - 1)
    data_service_call_track_uuid = uuid.uuid4().int & ((1 << 63) - 1)
    # data_service_call 中的内部步骤的 UUID
    data_service_internal_step_track_uuid = uuid.uuid4().int & ((1<<63)-1)

    # 定义 TrackDescriptor 的帮助函数
    def define_custom_track(track_uuid, name, parent_track_uuid=None):
        packet = builder.add_packet()
        desc = packet.track_descriptor
        desc.uuid = track_uuid
        desc.name = name
        if parent_track_uuid:
            desc.parent_uuid = parent_track_uuid

    # 添加 slice 事件的帮助函数
    def add_slice_event(ts, event_type, event_track_uuid, name=None):
        packet = builder.add_packet()
        packet.timestamp = ts
        packet.track_event.type = event_type
        packet.track_event.track_uuid = event_track_uuid
        if name:
            packet.track_event.name = name
        packet.trusted_packet_sequence_id = TRUSTED_PACKET_SEQUENCE_ID

    # 1. 定义整体请求的根 Track
    define_custom_track(root_request_track_uuid, "Frontend Request: /api/user/profile")

    # 在其自己的 track 上为前端请求的总持续时间添加 slice
    add_slice_event(ts=10000, event_type=TrackEvent.TYPE_SLICE_BEGIN,
                    event_track_uuid=root_request_track_uuid, name="Total Request Duration")

    # 2. 将每个服务调用(span)的子 tracks 定义为根请求的子项
    define_custom_track(auth_service_call_track_uuid, "Call: AuthService.AuthenticateUser",
                        parent_track_uuid=root_request_track_uuid)
    define_custom_track(data_service_call_track_uuid, "Call: DataService.GetUserData",
                        parent_track_uuid=root_request_track_uuid)

    # 3. 在这些服务调用 tracks 上发出 slices
    # Auth Service Call
    add_slice_event(ts=10100, event_type=TrackEvent.TYPE_SLICE_BEGIN,
                    event_track_uuid=auth_service_call_track_uuid, name="AuthService.AuthenticateUser")
    add_slice_event(ts=10300, event_type=TrackEvent.TYPE_SLICE_END,
                    event_track_uuid=auth_service_call_track_uuid)

    # Data Service Call(在 Auth 完成后开始)
    add_slice_event(ts=10350, event_type=TrackEvent.TYPE_SLICE_BEGIN,
                    event_track_uuid=data_service_call_track_uuid, name="DataService.GetUserData")

    # 模拟 DataService.GetUserData 内的内部步骤，显示在其自己的子 track 上
    # 此 track 将是"Call: DataService.GetUserData" track 的子项。
    define_custom_track(data_service_internal_step_track_uuid, "Internal: QueryDatabase",
                        parent_track_uuid=data_service_call_track_uuid)

    add_slice_event(ts=10400, event_type=TrackEvent.TYPE_SLICE_BEGIN,
                    event_track_uuid=data_service_internal_step_track_uuid, name="QueryDatabase")
    add_slice_event(ts=10550, event_type=TrackEvent.TYPE_SLICE_END,
                    event_track_uuid=data_service_internal_step_track_uuid)

    add_slice_event(ts=10600, event_type=TrackEvent.TYPE_SLICE_END, # DataService.GetUserData 的结束
                    event_track_uuid=data_service_call_track_uuid)

    # 前端请求总计的结束
    add_slice_event(ts=10700, event_type=TrackEvent.TYPE_SLICE_END,
                    event_track_uuid=root_request_track_uuid)
```

</details>

运行脚本后，在 [Perfetto UI](https://ui.perfetto.dev) 中打开生成的 `my_custom_trace.pftrace` 将显示以下输出：

![Track Hierarchies for Waterfall / Trace Views](/docs/images/converting-waterfall.png)

你可以在 Perfetto UI 的 Query 标签页中使用 SQL 或使用 [Trace Processor](/docs/analysis/getting-started.md) 查询此请求分解以分析时间：
```sql
SELECT slice.ts, slice.dur, slice.name, track.name AS service
FROM slice 
JOIN track ON slice.track_id = track.id 
WHERE track.name LIKE '%Request%' OR track.name LIKE '%Service%'
ORDER BY slice.ts;
```

## 向事件添加调试注解

调试注解允许你将任意键值数据附加到任何 `TrackEvent`。它们在你检查 Perfetto UI 中的各个事件时出现，对于提供关于特定 slices 或 instants 期间发生情况的额外上下文非常有用。

调试注解可用于：

- 添加对象 IDs、请求 IDs 或其他标识符
- 包括配置值或状态信息
- 附加错误消息或状态码
- 提供结构化数据，如数组或嵌套对象
- 任何丰富你的 trace 事件的上下文数据

调试注解支持各种数据类型，包括基本值（字符串、整数、布尔值、双精度浮点数）、嵌套字典和数组。它们使用 `DebugAnnotation` protobuf 消息，可以表示复杂的嵌套结构。

### Python 示例：基本调试注解

此示例演示如何向 track 事件添加简单的键值调试注解。这对于附加附加信息（如对象 IDs、状态值或其他上下文数据）很有用。

将以下 Python 代码复制到 `trace_converter_template.py` 脚本中的 `populate_packets(builder)` 函数。

<details>
<summary><b>点击展开/折叠 Python 代码</b></summary>

```python
    # 定义此 packets 序列的唯一 ID
    TRUSTED_PACKET_SEQUENCE_ID = 6001

    # 为你的自定义 track 定义唯一的 UUID
    DEBUG_TRACK_UUID = 87654321

    # 1. 定义自定义 Track
    packet = builder.add_packet()
    packet.track_descriptor.uuid = DEBUG_TRACK_UUID
    packet.track_descriptor.name = "Debug Annotations Example"

    # 添加带有调试注解的 slice 事件的帮助函数
    def add_slice_with_debug_annotations(ts, event_type, name=None, debug_annotations=None):
        packet = builder.add_packet()
        packet.timestamp = ts
        packet.track_event.type = event_type
        packet.track_event.track_uuid = DEBUG_TRACK_UUID
        if name:
            packet.track_event.name = name

        # 添加调试注解
        if debug_annotations:
            for key, value in debug_annotations.items():
                annotation = packet.track_event.debug_annotations.add()
                annotation.name = key

                # 根据类型设置适当的值字段
                if isinstance(value, bool):
                    annotation.bool_value = value
                elif isinstance(value, int):
                    annotation.int_value = value
                elif isinstance(value, float):
                    annotation.double_value = value
                elif isinstance(value, str):
                    annotation.string_value = value

        packet.trusted_packet_sequence_id = TRUSTED_PACKET_SEQUENCE_ID

    # 2. 创建带有各种调试注解的 slices
    add_slice_with_debug_annotations(
        ts=1000,
        event_type=TrackEvent.TYPE_SLICE_BEGIN,
        name="Database Query",
        debug_annotations={
            "query_id": 12345,
            "table_name": "users",
            "is_cached": False,
            "timeout_ms": 5000.0
        }
    )

    add_slice_with_debug_annotations(
        ts=1200,
        event_type=TrackEvent.TYPE_SLICE_END
    )

    # 另一个带有不同类型注解的示例
    add_slice_with_debug_annotations(
        ts=1500,
        event_type=TrackEvent.TYPE_SLICE_BEGIN,
        name="HTTP Request",
        debug_annotations={
            "method": "POST",
            "url": "/api/users/create",
            "content_length": 2048,
            "keep_alive": True
        }
    )

    add_slice_with_debug_annotations(
        ts=1800,
        event_type=TrackEvent.TYPE_SLICE_END
    )
```

</details>

运行脚本后，在 [Perfetto UI](https://ui.perfetto.dev) 中打开生成的 `my_custom_trace.pftrace` 将显示以下输出：

![Adding Debug Annotations](/docs/images/converting-debug-basic.png)

你可以在 Perfetto UI 的 Query 标签页中使用 SQL 或使用 [Trace Processor](/docs/analysis/getting-started.md) 查询调试注解：
```sql
SELECT slice.name, EXTRACT_ARG(slice.arg_set_id, 'debug.query_id') AS query_id
FROM slice 
JOIN track ON slice.track_id = track.id 
WHERE track.name = 'Debug Annotations Example';
```

### Python 示例：嵌套调试注解

调试注解可以表示复杂的嵌套数据结构，包括字典和数组。这在需要附加结构化信息（如配置对象、值数组或层次数据）时非常有用。

将以下 Python 代码复制到 `trace_converter_template.py` 脚本中的 `populate_packets(builder)` 函数。

<details>
<summary><b>点击展开/折叠 Python 代码</b></summary>

```python
    # 定义此 packets 序列的唯一 ID
    TRUSTED_PACKET_SEQUENCE_ID = 6002

    # 为你的自定义 track 定义唯一的 UUID
    NESTED_DEBUG_TRACK_UUID = 87654322

    # 1. 定义自定义 Track
    packet = builder.add_packet()
    packet.track_descriptor.uuid = NESTED_DEBUG_TRACK_UUID
    packet.track_descriptor.name = "Nested Debug Annotations"

    # 2. 创建带有嵌套调试注解的 slice
    packet = builder.add_packet()
    packet.timestamp = 2000
    packet.track_event.type = TrackEvent.TYPE_SLICE_BEGIN
    packet.track_event.track_uuid = NESTED_DEBUG_TRACK_UUID
    packet.track_event.name = "Complex Operation"

    # 添加带有嵌套结构的字典注解
    config_annotation = packet.track_event.debug_annotations.add()
    config_annotation.name = "config"

    # 添加字典条目
    db_entry = config_annotation.dict_entries.add()
    db_entry.name = "database"
    db_entry.string_value = "postgres://localhost:5432/mydb"

    timeout_entry = config_annotation.dict_entries.add()
    timeout_entry.name = "timeout_ms"
    timeout_entry.int_value = 30000

    retry_entry = config_annotation.dict_entries.add()
    retry_entry.name = "retry_enabled"
    retry_entry.bool_value = True

    # 添加数组注解
    servers_annotation = packet.track_event.debug_annotations.add()
    servers_annotation.name = "server_list"

    # 添加数组值
    server1 = servers_annotation.array_values.add()
    server1.string_value = "server-1.example.com"

    server2 = servers_annotation.array_values.add()
    server2.string_value = "server-2.example.com"

    server3 = servers_annotation.array_values.add()
    server3.string_value = "server-3.example.com"

    packet.trusted_packet_sequence_id = TRUSTED_PACKET_SEQUENCE_ID

    # 结束 slice
    packet = builder.add_packet()
    packet.timestamp = 2500
    packet.track_event.type = TrackEvent.TYPE_SLICE_END
    packet.track_event.track_uuid = NESTED_DEBUG_TRACK_UUID
    packet.trusted_packet_sequence_id = TRUSTED_PACKET_SEQUENCE_ID
```

</details>

运行脚本后，在 [Perfetto UI](https://ui.perfetto.dev) 中打开生成的 `my_custom_trace.pftrace` 将显示以下输出：

![Nested Debug Annotations](/docs/images/converting-debug-nested.png)

你可以在 Perfetto UI 的 Query 标签页中使用 SQL 或使用 [Trace Processor](/docs/analysis/getting-started.md) 查询嵌套调试注解：
```sql
SELECT slice.name, 
       EXTRACT_ARG(slice.arg_set_id, 'debug.config.database') AS database,
       EXTRACT_ARG(slice.arg_set_id, 'debug.server_list[0]') AS first_server
FROM slice 
JOIN track ON slice.track_id = track.id 
WHERE track.name = 'Nested Debug Annotations';
```

## {#callstacks} 将调用栈附加到事件

调用栈（也称为堆栈跟踪或回溯）显示导致特定事件的函数调用序列。将调用栈添加到你的 trace 事件对于理解触发特定操作的代码路径非常宝贵。

有两种不同的方式将调用栈与事件关联：

1. **内联调用栈**：将堆栈帧直接嵌入每个事件中，包含函数名称和可选的源位置。这很简单，不需要设置，当 trace 大小不是问题或调用栈是唯一的时非常理想。
2. **Interned 调用栈**：定义一次调用栈结构并从多个事件中通过 ID 引用它。当调用栈频繁重复或需要二进制/映射信息以进行符号化时，这要高效得多。

本指南涵盖内联调用栈，非常适合入门。对于重复的调用栈或需要二进制映射信息时，请改用
[interned callstacks](/docs/reference/synthetic-track-event.md#callstacks)。

### Python 示例

每个帧包括函数名称，以及可选的源文件和行号。

将以下 Python 代码复制到 `trace_converter_template.py` 脚本中的 `populate_packets(builder)` 函数。

<details>
<summary><b>点击展开/折叠 Python 代码</b></summary>

```python
    # 定义此 packets 序列的唯一 ID
    TRUSTED_PACKET_SEQUENCE_ID = 7001

    # 为你的自定义 track 定义唯一的 UUID
    CALLSTACK_TRACK_UUID = 98765432

    def emit_track_event(
        ts,
        event_type,
        name=None,
        frames=None,
    ):
        """用于写入带有可选内联调用栈的 TrackEvent 的帮助函数。"""
        packet = builder.add_packet()
        packet.timestamp = ts
        packet.track_event.type = event_type
        packet.track_event.track_uuid = CALLSTACK_TRACK_UUID
        if name is not None:
            packet.track_event.name = name
        if frames:
            for function, source, line in frames:
                frame = packet.track_event.callstack.frames.add()
                frame.function_name = function
                if source:
                    frame.source_file = source
                if line is not None:
                    frame.line_number = line
        packet.trusted_packet_sequence_id = TRUSTED_PACKET_SEQUENCE_ID

    # 1. 定义自定义 Track
    packet = builder.add_packet()
    packet.track_descriptor.uuid = CALLSTACK_TRACK_UUID
    packet.track_descriptor.name = "Operations with Callstacks"

    # 2. 创建带有内联调用栈的 slice
    emit_track_event(
        ts=3000,
        event_type=TrackEvent.TYPE_SLICE_BEGIN,
        name="ProcessRequest",
        frames=[
            ("main", "/src/app.cc", 42),
            ("HandleIncomingRequests", "/src/server.cc", 128),
            ("ProcessRequest", "/src/request_handler.cc", 256),
        ],
    )

    # 在 slice 完成时结束带有调用栈捕获的 slice
    emit_track_event(
        ts=3500,
        event_type=TrackEvent.TYPE_SLICE_END,
        frames=[
            ("main", None, None),
            ("HandleIncomingRequests", None, None),
            ("FinalizeRequest", "/src/request_handler.cc", 512),
        ],
    )

    # 3. 另一个带有最小调用栈的 slice(仅函数名称)
    emit_track_event(
        ts=4000,
        event_type=TrackEvent.TYPE_SLICE_BEGIN,
        name="AllocateMemory",
        frames=[
            ("main", None, None),
            ("HandleIncomingRequests", None, None),
            ("AllocateMemory", None, None),
        ],
    )

    # 结束 slice
    emit_track_event(
        ts=4200,
        event_type=TrackEvent.TYPE_SLICE_END,
    )
```

</details>

NOTE: 帧从最外层(堆栈底部，例如 `main()`)到最内层（堆栈顶部，事件发生的地方）排序。

当你在 slice 结束事件上提供调用栈时，Trace Processor 会将其与开始调用栈分开存储（在 `slice` 表中的 `end_callsite_id` 参数下）。这对于快速比较进入/退出堆栈非常方便。

运行脚本后，在 [Perfetto UI](https://ui.perfetto.dev) 中打开生成的 `my_custom_trace.pftrace` 将显示以下输出：

![Inline Callstacks](/docs/images/converting-inline-callstacks.png)

请注意，你还可以进行"区域选择"（又称框选）以获取调用栈的火焰图：

![Inline Callstacks Area Select](/docs/images/inline-callstacks-flamegraph.png)

## 下一步

你现在了解了如何使用 Python 和 `TrackEvent` 将自定义时间戳数据转换为 Perfetto traces。通过这些技术，你可以表示 slices、counters、flows、track 层次结构、调试注解和调用栈。

一旦你将自定义数据转换为 Perfetto trace 格式（`.pftrace` 文件），你可以：

- **探索高级的 `TrackEvent` 功能：** 有关对 track 和事件外观、interning 和其他高级功能的更详细控制，请参阅
  [Writing synthetic traces using TrackEvent protobufs](/docs/reference/synthetic-track-event.md)
  参考页面。
- **可视化你的 trace：** 在 [Perfetto UI](https://ui.perfetto.dev) 中打开生成的 `.pftrace` 文件以在交互式 Timeline 上探索你的数据。
- **使用 SQL 分析：** 使用
  [Trace Processor](/docs/analysis/getting-started.md) 查询你的自定义
  trace 数据。你的自定义 tracks 和事件将填充标准表，如
  `slice`、`track`、`counter` 等。
- **处理大型数据集：** 如果你正在生成非常大的 traces 并且想要避免高内存使用，请在
  [Advanced Guide's section on streaming](/docs/reference/synthetic-track-event.md#handling-large-traces-with-streaming) 中了解如何直接将数据流式传输到文件。
