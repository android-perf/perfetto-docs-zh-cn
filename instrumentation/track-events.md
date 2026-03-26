# Track events (Tracing SDK)

Track events 是 [Perfetto Tracing SDK](tracing-sdk.md) 的一部分。

*Track events* 是应用程序特定的、有界的事件，在应用程序运行时记录到 *trace* 中。Track events 始终与 *track* 关联，track 是单调递增时间的 Timeline。track 对应于独立的执行序列，例如进程中的单个线程。

![Track events shown in the Perfetto UI](
 /docs/images/track-events.png "Track events in the Perfetto UI")

有关如何检出和构建 SDK 的说明，请参阅 Tracing SDK 页面的 [快速入门](/docs/instrumentation/tracing-sdk#getting-started) 部分。

TIP: 这些示例中的代码也可在[仓库中](/examples/sdk/README.md）找到。

有几种主要的 Track event 类型：

- **Slice**，表示嵌套的、有界的操作。例如，Slice 可以覆盖函数开始执行到返回的时间段、从网络加载文件所花费的时间或完成用户旅程的时间。

- **Counter**，是随时间变化的数值的快照。例如，Track event 可以记录进程在执行过程中的瞬时内存使用情况。

- **Flow**，用于连接跨越不同 track 的相关 slice。例如，如果图像文件首先从网络加载，然后在线程池上解码，可以使用 flow event 来突出显示其在系统中的路径。

[Perfetto UI](https://ui.perfetto.dev) 内置了对 Track events 的支持，这提供了一种快速可视化应用程序内部处理的有用方法。例如，[Chrome 浏览器](https://www.chromium.org/developers/how-tos/trace-event-profiling-tool) 深度使用 Track events 进行插桩，以辅助调试、开发和性能分析。

要开始使用 Track events，首先定义事件所属的类别集。每个类别可以单独启用或禁用 tracing（请参阅[类别配置](#category-configuration)）。

将类别列表添加到头文件中（例如，`my_app_tracing_categories.h`），如下所示：

```C++
#include <perfetto.h>

PERFETTO_DEFINE_CATEGORIES(
 perfetto::Category("rendering")
 .SetDescription("Events from the graphics subsystem"),
 perfetto::Category("network")
 .SetDescription("Network upload and download statistics"));
```

然后，在 cc 文件（例如，`my_app_tracing_categories.cc`）中为类别声明静态存储：

```C++
#include "my_app_tracing_categories.h"

PERFETTO_TRACK_EVENT_STATIC_STORAGE();
```

最后，在客户端库启动后初始化 Track events：

```C++
int main(int argc, char** argv) {
 ...
 perfetto::Tracing::Initialize(args);
 perfetto::TrackEvent::Register(); // 添加此行。
}
```

现在你可以像这样向现有函数添加 Track events：

```C++
#include "my_app_tracing_categories.h"

void DrawPlayer() {
 TRACE_EVENT("rendering", "DrawPlayer"); // 开始 "DrawPlayer" slice。
 ...
 // 结束 "DrawPlayer" slice。
}
```

这种类型的 trace event 是有作用域的，在底层使用 C++ [RAII]。事件将覆盖从遇到 `TRACE_EVENT` 注释到块结束（在上面的示例中，直到函数返回）的时间。

对于不遵循函数作用域的事件，使用 `TRACE_EVENT_BEGIN` 和 `TRACE_EVENT_END`：

```C++
void LoadGame() {
 DisplayLoadingScreen();

 TRACE_EVENT_BEGIN("io", "Loading"); // 开始 "Loading" slice。
 LoadCollectibles();
 LoadVehicles();
 LoadPlayers();
 TRACE_EVENT_END("io"); // 结束 "Loading" slice。

 StartGame();
}
```

请注意，你不需要为 `TRACE_EVENT_END` 提供名称，因为它会自动关闭在同一线程上开始的最近事件。换句话说，给定线程上的所有事件共享同一个堆栈。这意味着不建议在单独的函数中使用匹配的 `TRACE_EVENT_BEGIN` 和 `TRACE_EVENT_END` 标记对，因为无关的事件可能会意外终止原始事件；对于跨越函数边界的事件，通常最好在[单独的 track](#tracks）上发出它们。

你还可以与事件一起提供（最多两个）debug 注解。

```C++
int player_number = 1;
TRACE_EVENT("rendering", "DrawPlayer", "player_number", player_number);
```

有关其他类型的支持 Track event 参数，请参阅[下文](#track-event-arguments)。对于更复杂的参数，你可以定义[自己的 protobuf 消息](/protos/perfetto/trace/track_event/track_event.proto)，并将它们作为事件的参数发出。

NOTE: 目前自定义 protobuf 消息需要直接添加到 Perfetto 仓库的 `protos/perfetto/trace` 下，
 并且 Perfetto 本身也必须重新构建。我们正在[努力消除此限制](https://github.com/google/perfetto/issues/11)。

作为自定义 Track event 参数类型的示例，将以下内容保存为 `protos/perfetto/trace/track_event/player_info.proto`：

```protobuf
message PlayerInfo {
 optional string name = 1;
 optional uint64 score = 2;
}
```

这个新文件也应该添加到 `protos/perfetto/trace/track_event/BUILD.gn`：

```json
sources = [
 ...
 "player_info.proto"
]
```

此外，应该在 `protos/perfetto/trace/track_event/track_event.proto` 中的 Track event 消息定义中添加匹配的参数：

```protobuf
import "protos/perfetto/trace/track_event/player_info.proto";

...

message TrackEvent {
 ...
 // 新参数类型放在这里。
 optional PlayerInfo player_info = 1000;
}
```

相应的 trace 点可能如下所示：

```C++
Player my_player;
TRACE_EVENT("category", "MyEvent", [&](perfetto::EventContext ctx) {
 auto player = ctx.event()->set_player_info();
 player->set_name(my_player.name());
 player->set_player_score(my_player.score());
});
```

传递给宏的 lambda 函数仅在给定类别的 tracing 已启用时才会被调用。它总是被同步调用，并且如果有多个并发 tracing 会话处于活动状态，可能会被多次调用。

现在你已经使用 Track events 为你的应用程序进行了插桩，你准备好开始[采集 Trace](tracing-sdk.md#recording）了。

## 类别配置

所有 Track events 都被分配到一个或多个 trace 类别。例如：

```C++
TRACE_EVENT("rendering", ...); // "rendering" 类别中的事件。
```

默认情况下，所有非调试和非慢速 Track event 类别都启用了 tracing。*Debug* 和 *slow* 类别是具有特殊标记的类别：

  - `"debug"` 类别可以为特定子系统提供更详细的调试输出。
  - `"slow"` 类别记录足够多的数据，可能会影响你应用程序的交互性能。

类别标记可以像这样定义：

```C++
perfetto::Category("rendering.debug")
 .SetDescription("Debug events from the graphics subsystem")
 .SetTags("debug", "my_custom_tag")
```

单个 trace event 也可以属于多个类别：

```C++
// "rendering" 和 "benchmark" 类别中的事件。
TRACE_EVENT("rendering,benchmark", ...);
```

必须在类别注册表中添加相应的类别组条目：

```C++
perfetto::Category::Group("rendering,benchmark")
```

还可以有效地查询是否为 tracing 启用了给定类别：

```C++
if (TRACE_EVENT_CATEGORY_ENABLED("rendering")) {
 // ...
}
```

Perfetto 的 `TraceConfig` 中的 `TrackEventConfig` 字段可用于选择为 tracing 启用哪些类别：

```protobuf
message TrackEventConfig {
 // 每个列表项都是一个 glob。每个类别按照下面的说明与列表进行匹配。
 repeated string disabled_categories = 1; // 默认值：[]
 repeated string enabled_categories = 2; // 默认值：[]
 repeated string disabled_tags = 3; // 默认值：["slow", "debug"]
 repeated string enabled_tags = 4; // 默认值：[]
}
```

要确定是否启用了类别，它将按照以下顺序对照过滤器进行检查：

1. 已启用类别中的精确匹配。
2. 已启用标记中的精确匹配。
3. 已禁用类别中的精确匹配。
4. 已禁用标记中的精确匹配。
5. 已启用类别中的模式匹配。
6. 已启用标记中的模式匹配。
7. 已禁用类别中的模式匹配。
8. 已禁用标记中的模式匹配。

如果没有任何步骤产生匹配，则类别：
- 在 C+- API 中默认启用
- 在 C API 中默认禁用

指定 `enabled_categories: "*"` 或 `disabled_categories: "*"` 有助于显式实现一致的行为。

例如：

| 设置 | 所需配置 |
| --------------------------- | ---------------------------------------- |
| 仅启用特定类别 | `enabled_categories = ["foo", "bar", "baz"]` |
| | `disabled_categories = ["*"]` |
| 启用所有非慢速类别 | `enabled_categories = ["*"] ` |
| 启用特定标记 | `disabled_tags = ["*"]` |
| | `enabled_tags = ["foo", "bar"]` |

## 动态和仅测试类别

理想情况下，所有 trace 类别都应该在编译时定义，如上所示，因为这可以确保 trace 点具有最小的运行时和二进制大小开销。然而，在某些情况下，trace 类别只能在运行时确定（例如，它们来自在 WebView 或 NodeJS 引擎中运行的动态加载 JavaScript 的插桩）。这些可以由 trace 点使用，如下所示：

```C++
perfetto::DynamicCategory dynamic_category{"nodejs.something"};
TRACE_EVENT_BEGIN(dynamic_category, "SomeEvent", ...);
```

TIP: 也可以通过将 `nullptr` 作为名称传递并手动填充 `TrackEvent::name` 字段来使用动态事件名称。

一些 trace 类别仅对测试有用，它们不应进入生产二进制文件。这些类型的类别可以用前缀字符串列表定义：

```C++
PERFETTO_DEFINE_TEST_CATEGORY_PREFIXES(
 "test", // 适用于 test.*
 "dontship" // 适用于 dontship.*.
);
```

## 动态事件名称

理想情况下，所有事件名称都应该是编译时字符串常量。例如：

```C++
TRACE_EVENT_BEGIN("rendering", "DrawGame");
```

这里 `"DrawGame"` 是编译时字符串。如果这里传递动态字符串，我们将得到编译时 static_assert 失败。例如：

```C++
const char* name = "DrawGame";
TRACE_EVENT_BEGIN("rendering", name); // 错误。事件名称不是静态的。
```

有两种使用动态事件名称的方法：

1) 如果事件名称实际上是动态的（例如，std::string），使用 `perfetto::DynamicString` 编写它：

```C++
 TRACE_EVENT("category", perfetto::DynamicString{dynamic_name});
```

DANGER: `perfetto::DynamicString` 必须作为纯右值（临时对象）传递。
 这是为了确保底层字符串在记录事件之前保持有效。

NOTE: 以下是使用动态事件名称的旧方法。不再推荐使用。

```C++
TRACE_EVENT("category", nullptr, [&](perfetto::EventContext ctx) {
 ctx.event()->set_name(dynamic_name);
});
```

2) 如果名称是静态的，但指针在运行时计算，用 perfetto::StaticString 包装它：

```C++
TRACE_EVENT("category", perfetto::StaticString{name});
TRACE_EVENT("category", perfetto::StaticString{i % 2 == 0 ? "A" : "B"});
```

DANGER: 对内容动态变化的字符串使用 perfetto::StaticString 可能会导致静默的 trace 数据损坏。

## 高级主题

### Track event 参数

可以将以下可选参数传递给 `TRACE_EVENT` 以向事件添加额外信息：

```C++
TRACE_EVENT("cat", "name"[, track][, timestamp]
 (, "debug_name", debug_value |, TrackEvent::kFieldName, value)*
 [, lambda]);
```

有效组合的一些示例：

1. 用于编写自定义 TrackEvent 字段的 lambda：

 ```C++
 TRACE_EVENT("category", "Name", [&](perfetto::EventContext ctx) {
 auto* debug_annotation = ctx.event()->add_debug_annotations();
 debug_annotation->set_name("key");
 debug_annotation->set_string_value("value");
 });
 ```

2. 时间戳和 lambda：

 ```C++
 TRACE_EVENT("category", "Name", time_in_nanoseconds,
 [&](perfetto::EventContext ctx) {
 auto* debug_annotation = ctx.event()->add_debug_annotations();
 debug_annotation->set_name("key");
 debug_annotation->set_string_value("value");
 });
 ```

 |time_in_nanoseconds| 默认应为 uint64_t。要支持自定义时间戳类型，
 应该定义 |perfetto::TraceTimestampTraits<MyTimestamp>::ConvertTimestampToTraceTimeNs|。
 有关更多详细信息，请参阅 |ConvertTimestampToTraceTimeNs|。

3. 任意数量的 debug 注解：

 ```C++
 TRACE_EVENT("category", "Name", "arg", value);
 TRACE_EVENT("category", "Name", "arg", value, "arg2", value2);
 TRACE_EVENT("category", "Name", "arg", value, "arg2", value2,
 "arg3", value3);
 ```

 有关将自定义类型采集为 debug 注解，请参阅 |TracedValue|。

4. 任意数量的 TrackEvent 字段（包括扩展）：

 ```C++
 TRACE_EVENT("category", "Name",
 perfetto::protos::pbzero::TrackEvent::kFieldName, value);
 ```

5. debug 注解和 TrackEvent 字段的任意组合：

 ```C++
 TRACE_EVENT("category", "Name",
 perfetto::protos::pbzero::TrackEvent::kFieldName, value1,
 "arg", value2);
 ```

6. debug 注解 / TrackEvent 字段和 lambda 的任意组合：

 ```C++
 TRACE_EVENT("category", "Name", "arg", value1,
 pbzero::TrackEvent::kFieldName, value2,
 [&](perfetto::EventContext ctx) {
 auto* debug_annotation = ctx.event()->add_debug_annotations();
 debug_annotation->set_name("key");
 debug_annotation->set_string_value("value");
 });
 ```

7. 覆盖的 track：

 ```C++
 TRACE_EVENT("category", "Name", perfetto::Track(1234));
 ```

 有关可能使用的其他 track 类型，请参阅 |Track|。

8. track 和 lambda：

 ```C++
 TRACE_EVENT("category", "Name", perfetto::Track(1234),
 [&](perfetto::EventContext ctx) {
 auto* debug_annotation = ctx.event()->add_debug_annotations();
 debug_annotation->set_name("key");
 debug_annotation->set_string_value("value");
 });
 ```

9. track 和时间戳：

 ```C++
 TRACE_EVENT("category", "Name", perfetto::Track(1234),
 time_in_nanoseconds);
 ```

10. track、时间戳和 lambda：

 ```C++
 TRACE_EVENT("category", "Name", perfetto::Track(1234),
 time_in_nanoseconds, [&](perfetto::EventContext ctx) {
 auto* debug_annotation = ctx.event()->add_debug_annotations();
 debug_annotation->set_name("key");
 debug_annotation->set_string_value("value");
 });
 ```

11. track 和 debug 注解及 TrackEvent 字段的任意组合：

 ```C++
 TRACE_EVENT("category", "Name", perfetto::Track(1234),
 "arg", value);
 TRACE_EVENT("category", "Name", perfetto::Track(1234),
 "arg", value, "arg2", value2);
 TRACE_EVENT("category", "Name", perfetto::Track(1234),
 "arg", value, "arg2", value2,
 pbzero::TrackEvent::kFieldName, value3);
 ```

### Track

每个 Track event 都与 track 关联，track 指定事件所属的 Timeline。在大多数情况下，track 对应于 Perfetto UI 中的视觉水平 track，如下所示：

![Track timelines shown in the Perfetto UI](
 /docs/images/track-timeline.png "Track timelines in the Perfetto UI")

描述并行序列的事件（例如，单独的线程）应该使用单独的 track，而顺序事件（例如，嵌套函数调用）通常属于同一个 track。

Perfetto 支持三种类型的 track：

- `Track` – 基本 Timeline。

- `ProcessTrack` – 表示系统中单个进程的 Timeline。

- `ThreadTrack` – 表示系统中单个线程的 Timeline。

Track 可以有父 track，父 track 用于将相关的 track 分组在一起。例如，`ThreadTrack` 的父 track 是该线程所属进程的 `ProcessTrack`。默认情况下，track 被分组在当前进程的 `ProcessTrack` 下。

track 由 uuid 标识，uuid 在整个采集的 trace 中必须是唯一的。为了最大限度地减少意外冲突的机会，子 track 的 uuid 与其父 track 的 uuid 组合，每个 `ProcessTrack` 都有一个随机的、每个进程的 uuid。

默认情况下，Track events（例如，`TRACE_EVENT`）使用调用线程的 `ThreadTrack`。可以覆盖它，例如，标记在不同线程上开始和结束的事件：

```C++
void OnNewRequest(size_t request_id) {
 // 在请求进入时打开 slice。
 TRACE_EVENT_BEGIN("category", "HandleRequest", perfetto::Track(request_id));

 // 启动线程来处理请求。
 std::thread worker_thread([=] {
 // ... 生成响应 ...

 // 现在关闭请求的 slice，因为我们完成了处理。
 TRACE_EVENT_END("category", perfetto::Track(request_id));
 });
```

track 还可以选择用元数据注解：

```C++
auto desc = track.Serialize();
desc.set_name("MyTrack");
perfetto::TrackEvent::SetTrackDescriptor(track, desc);
```

线程和进程也可以以类似的方式命名，例如：

```C++
auto desc = perfetto::ProcessTrack::Current().Serialize();
desc.mutable_process()->set_process_name("MyProcess");
perfetto::TrackEvent::SetTrackDescriptor(
 perfetto::ProcessTrack::Current(), desc);
```

元数据在 tracing 会话之间保持有效。要释放 track 的数据，调用 EraseTrackDescriptor：

```C++
perfetto::TrackEvent::EraseTrackDescriptor(track);
```

### Flow

Flow 可用于链接两个（或更多）事件（slice 或 instant），将它们标记为相关。

当选择其中一个事件时，链接在 UI 中显示为箭头：

![A flow between two slices in the Perfetto UI](
 /docs/images/flows.png "A flow between two slices in the Perfetto UI")

```C++
// 在相关的 slice 中使用相同的标识符。
uint64_t request_id = GetRequestId();

{
 TRACE_EVENT("rendering", "HandleRequestPhase1",
 perfetto::Flow::ProcessScoped(request_id));
 //...
}

std::thread t1([&] {
 TRACE_EVENT("rendering", "HandleRequestPhase2",
 perfetto::TerminatingFlow::ProcessScoped(request_id));
 //...
});
```

### Counter

时变数值数据可以使用 `TRACE_COUNTER` 宏记录：

```C++
TRACE_COUNTER("category", "MyCounter", 1234.5);
```

此数据在 Perfetto UI 中显示为 counter track：

![A counter track shown in the Perfetto UI](
 /docs/images/counter-events.png "A counter track shown in the Perfetto UI")

支持整数和浮点 counter 值。Counter 还可以用其他信息注解，例如单位，用于跟踪以每秒帧数或 "fps" 表示的渲染帧率：

```C++
TRACE_COUNTER("category", perfetto::CounterTrack("Framerate", "fps"), 120);
```

作为另一个示例，采集字节但接受千字节作为样本（以减少 trace 二进制大小）的内存 counter 可以这样定义：

```C++
perfetto::CounterTrack memory_track = perfetto::CounterTrack("Memory")
 .set_unit("bytes")
 .set_multiplier(1024);
TRACE_COUNTER("category", memory_track, 4 /* = 4096 bytes */);
```

有关 counter track 的完整属性集，请参阅[counter_descriptor.proto](
/protos/perfetto/trace/track_event/counter_descriptor.proto)。

要在特定时间点（而不是当前时间）记录 counter 值，可以传递自定义时间戳：

```C++
// 首先记录当前时间和 counter 值。
uint64_t timestamp = perfetto::TrackEvent::GetTraceTimeNs();
int64_t value = 1234;

// 稍后，在该时间点发出样本。
TRACE_COUNTER("category", "MyCounter", timestamp, value);
```

### Interning

Interning 可用于避免在整个 trace 中重复相同的常量数据（例如，事件名称）。Perfetto 自动为传递给 `TRACE_EVENT` 的大多数字符串执行 interning，但也可以定义自己的类型 interning 数据。

首先，为你的类型定义 interning 索引。它应该映射到[interned_data.proto](
/protos/perfetto/trace/interned_data/interned_data.proto)的特定字段，并指定在第一次看到时如何将 interning 数据写入该消息。

```C++
struct MyInternedData
 : public perfetto::TrackEventInternedDataIndex<
 MyInternedData,
 perfetto::protos::pbzero::InternedData::kMyInternedDataFieldNumber,
 const char*> {
 static void Add(perfetto::protos::pbzero::InternedData* interned_data,
 size_t iid,
 const char* value) {
 auto my_data = interned_data->add_my_interned_data();
 my_data->set_iid(iid);
 my_data->set_value(value);
 }
};
```

接下来，如下所示在 trace 点中使用你的 interning 数据。仅在第一次命中 trace 点时才会发出 interning 字符串（除非 trace 缓冲区已环绕）。

```C++
TRACE_EVENT(
 "category", "Event", [&](perfetto::EventContext ctx) {
 auto my_message = ctx.event()->set_my_message();
 size_t iid = MyInternedData::Get(&ctx, "Repeated data to be interned");
 my_message->set_iid(iid);
 });
```

请注意，interning 数据是强类型的，即每类 interning 数据使用标识符的单独命名空间。

### Tracing 会话观察者

会话观察者接口允许在 Track event tracing 开始和停止时通知应用程序：

```C++
class Observer : public perfetto::TrackEventSessionObserver {
 public:
 ~Observer() override = default;

 void OnSetup(const perfetto::DataSourceBase::SetupArgs&) override {
 // 配置 tracing 会话时调用。注意 tracing 尚未激活，
 // 所以这里发出的 Track events 不会被记录。
 }

 void OnStart(const perfetto::DataSourceBase::StartArgs&) override {
 // 启动 tracing 会话时调用。可以从此回调发出 Track events。
 }

 void OnStop(const perfetto::DataSourceBase::StopArgs&) override {
 // 停止 tracing 会话时调用。仍然可以从此回调发出 Track events。
 }
};
```

请注意，接口的所有方法都在内部 Perfetto 线程上调用。

例如，以下是等待任何 tracing 会话启动的方法：

```C++
class Observer : public perfetto::TrackEventSessionObserver {
 public:
 Observer() { perfetto::TrackEvent::AddSessionObserver(this); }
 ~Observer() { perfetto::TrackEvent::RemoveSessionObserver(this); }

 void OnStart(const perfetto::DataSourceBase::StartArgs&) override {
 std::unique_lock<std::mutex> lock(mutex);
 cv.notify_one();
 }

 void WaitForTracingStart() {
 printf("Waiting for tracing to start...\n");
 std::unique_lock<std::mutex> lock(mutex);
 cv.wait(lock, [] { return perfetto::TrackEvent::IsEnabled(); });
 printf("Tracing started\n");
 }

 std::mutex mutex;
 std::condition_variable cv;
};

Observer observer;
observer.WaitForTracingToStart();
```

[RAII]: https://en.cppreference.com/w/cpp/language/raii
