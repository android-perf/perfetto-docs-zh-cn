# Tracing SDK

Perfetto Tracing SDK 是一个 C++17 库，允许用户空间应用程序发出 Trace 事件，并向 Perfetto trace 中添加更多应用程序特定的上下文。

使用 Tracing SDK 时，需要考虑两个主要方面：

1. 你是只对 Tracing 来自自己应用程序的事件感兴趣，还是想收集完整的全栈 Trace，将应用程序 Trace 事件与系统 Trace 事件（如调度器 trace、系统调用或任何其他 Perfetto 数据源）叠加在一起。

2. 对于应用程序特定的 Tracing，你是需要 Tracing 简单类型的 Timeline 事件（例如 Slice、Counter），还是需要定义具有自定义强类型 Schema 的复杂数据源（例如，将应用程序子系统的状态转储到 trace 中）。

对于仅限 Android 的插桩，如果现有的 [android.os.Trace (SDK)][atrace-sdk] / [ATrace_* (NDK)][atrace-ndk] 能够满足你的使用场景，建议继续使用它们。基于 Atrace 的插桩在 Perfetto 中得到完全支持。有关详情，请参阅 [Data Sources -> Android System -> Atrace Instrumentation][atrace-ds]。

## 快速入门

TIP: 这些示例中的代码也可在[仓库中]（/examples/sdk/README.md）找到。

要开始使用 Client API，首先从最新的 Perfetto 版本下载 SDK 源文件：
1) 访问 https://github.com/google/perfetto/releases/latest
2) 下载 perfetto-cpp-sdk-src.zip 并将文件解压到 sdk/perfetto 目录

或者，用于开发目的，你可以使用 `tools/gen_amalgamated --output sdk/perfetto` 生成它们。

然后，使用 CMake 进行构建：

```bash
cd examples/sdk
cmake -B build
cmake --build build
```

SDK 由两个文件组成，`sdk/perfetto.h` 和 `sdk/perfetto.cc`。这些是 Client API 的合并版本，设计为易于集成到现有的构建系统中。源代码是自包含的，只需要符合 C++17 标准库。

例如，要将 SDK 添加到 CMake 项目中，请编辑你的 CMakeLists.txt：

```cmake
cmake_minimum_required(VERSION 3.13)
project(PerfettoExample)
find_package(Threads)

# 为 Perfetto 定义静态库。
include_directories(perfetto/sdk)
add_library(perfetto STATIC perfetto/sdk/perfetto.cc)

# 将库链接到你的主可执行文件。
add_executable(example example.cc)
target_link_libraries(example perfetto ${CMAKE_THREAD_LIBS_INIT})

if (WIN32)
 # perfetto 库包含许多符号，因此它需要大对象格式。
 target_compile_options(perfetto PRIVATE "/bigobj")
 # 在 windows.h 中禁用旧功能。
 add_definitions(-DWIN32_LEAN_AND_MEAN -DNOMINMAX)
 # 在 Windows 上，我们应该链接到 WinSock2。
 target_link_libraries(example ws2_32)
endif (WIN32)

# 使用 Visual Studio 编译器时启用符合标准的模式。
if (MSVC)
 target_compile_options(example PRIVATE "/permissive-")
endif (MSVC)
```

接下来，在你的程序中初始化 Perfetto：

```C++
#include <perfetto.h>

int main(int argc, char** argv) {
 perfetto::TracingInitArgs args;

 // backends 决定在何处记录 Trace 事件。你可以选择一个或多个：

 // 1) 进程内 backend 仅在应用程序本身内记录。
 args.backends |= perfetto::kInProcessBackend;

 // 2) 系统 backend 将事件写入系统 Perfetto daemon，
 // 允许在同一 Timeline 上合并应用程序和系统事件（例如，ftrace）。
 // 要求 Perfetto `traced` daemon 正在运行（例如，在 Android Pie 和更新版本上）。
 args.backends |= perfetto::kSystemBackend;

 perfetto::Tracing::Initialize(args);
}
```

现在你已经准备好使用 Trace 事件为你的应用程序进行插桩了。

## 自定义数据源 vs Track 事件

SDK 提供两个抽象层来注入tracing 数据，它们彼此构建，在代码复杂度和表现力之间进行权衡：[Track 事件]（#track-events）和[自定义数据源](#custom-data-sources)。

### Track 事件

Track 事件是处理应用程序特定 Tracing 的建议选项，因为它们处理了许多细微之处（例如，线程安全、刷新、字符串驻留）。Track 事件是基于代码库中简单 `TRACE_EVENT` 注释标记的有界事件（例如，slice、counter），如下所示：

```c++
#include <perfetto.h>

PERFETTO_DEFINE_CATEGORIES(
 perfetto::Category("rendering")
 .SetDescription("Events from the graphics subsystem"),
 perfetto::Category("network")
 .SetDescription("Network upload and download statistics"));

PERFETTO_TRACK_EVENT_STATIC_STORAGE();
...

int main(int argc, char** argv) {
 ...
 perfetto::Tracing::Initialize(args);
 perfetto::TrackEvent::Register();
}
...

void LayerTreeHost::DoUpdateLayers() {
 TRACE_EVENT("rendering", "LayerTreeHost::DoUpdateLayers");
 ...
 for (PictureLayer& pl : layers) {
 TRACE_EVENT("rendering", "PictureLayer::Update");
 pl.Update();
 }
}
```

它们在 UI 中的渲染效果如下：

![Track event example](/docs/images/track-events.png)

Track 事件是最佳的默认选项，可以用很低的复杂度满足大多数 Tracing 用例。

要将新的 Track 事件包含在 trace 中，请确保 trace 配置中包含 `track_event` 数据源，并包含已启用和已禁用的类别列表。

```protobuf
data_sources {
 config {
 name: "track_event"
 track_event_config {
 enabled_categories: "rendering"
 disabled_categories: "*"
 }
 }
}
```

有关完整说明，请参阅 [Track 事件页面](track-events.md)。

### 自定义数据源

对于大多数用途，Track 事件是为应用程序进行 tracing 插桩的最直接的方式。然而，在某些罕见情况下，它们不够灵活，例如，当数据不适合 Track 的概念，或者数据量足够大以至于需要强类型 Schema 来最小化每个事件的大小。在这种情况下，你可以为 Perfetto 实现 _自定义数据源_。

与 Track 事件不同，使用自定义数据源时，你还需要在 [Trace Processor](/docs/analysis/trace-processor.md) 中进行相应的更改，以启用导入数据格式。

自定义数据源是 `perfetto::DataSource` 的子类。Perfetto 将自动为每个激活它的 Tracing 会话创建一个该类的实例（通常只有一个）。

```C++
class CustomDataSource : public perfetto::DataSource<CustomDataSource> {
 public:
 void OnSetup(const SetupArgs&) override {
 // 使用此回调根据 SetupArgs 中的 TraceConfig 对你的数据源应用任何自定义配置。
 }

 void OnStart(const StartArgs&) override {
 // 此通知可用于初始化 GPU 驱动程序、启用 Counters 等。
 // StartArgs 将包含 DataSourceDescriptor，可以进行扩展。
 }

 void OnStop(const StopArgs&) override {
 // 撤销在 OnStart 中完成的任何初始化。
 }

 // 数据源也可以有每个实例的状态。
 int my_custom_state = 0;
};

PERFETTO_DECLARE_DATA_SOURCE_STATIC_MEMBERS(CustomDataSource);
```

数据源的静态数据应该在一个源文件中定义，如下所示：

```C++
PERFETTO_DEFINE_DATA_SOURCE_STATIC_MEMBERS(CustomDataSource);
```

自定义数据源需要向 Perfetto 注册：

```C++
int main(int argc, char** argv) {
 ...
 perfetto::Tracing::Initialize(args);
 // 添加以下内容：
 perfetto::DataSourceDescriptor dsd;
 dsd.set_name("com.example.custom_data_source");
 CustomDataSource::Register(dsd);
}
```

与所有数据源一样，需要在 trace 配置中指定自定义数据源以启用 tracing：

```C++
perfetto::TraceConfig cfg;
auto* ds_cfg = cfg.add_data_sources()->mutable_config();
ds_cfg->set_name("com.example.custom_data_source");
```

最后，调用 `Trace()` 方法以使用你的自定义数据源记录事件。传递给该方法的 lambda 函数仅在启用 tracing 时才会被调用。它总是被同步调用，并且如果有多个并发 Tracing 会话处于活动状态，可能会被多次调用。

```C++
CustomDataSource::Trace([](CustomDataSource::TraceContext ctx) {
 auto packet = ctx.NewTracePacket();
 packet->set_timestamp(perfetto::TrackEvent::GetTraceTimeNs());
 packet->set_for_testing()->set_str("Hello world!");
});
```

如果有必要，`Trace()` 方法可以访问自定义数据源状态（上面示例中的 `my_custom_state`）。这样做会获取互斥锁以确保在另一个线程上调用 `Trace()` 方法时不会销毁数据源（例如，因为停止了追踪）。例如：

```C++
CustomDataSource::Trace([](CustomDataSource::TraceContext ctx) {
 auto safe_handle = trace_args.GetDataSourceLocked(); // 持有 RAII 锁。
 DoSomethingWith(safe_handle->my_custom_state);
});
```

## 进程内模式 vs 系统模式

这两种模式不是互斥的。应用程序可以配置为在两种模式下工作，并响应进程内 tracing 请求和系统 tracing 请求。两种模式都生成相同的 trace 文件格式。

### 进程内模式

在此模式下，perfetto 服务和应用程序定义的数据源完全在进程内托管，在被profile 应用程序的同一进程中。不会尝试连接到系统 `traced` daemon。

进程内模式可以通过在初始化 SDK 时设置 `TracingInitArgs.backends = perfetto::kInProcessBackend` 来启用，请参阅下面的示例。

此模式用于生成仅包含应用程序发出的事件的 trace，但不包含其他类型的事件（例如，调度器 trace）。

主要优点是，通过完全在进程内运行，它不需要任何特殊的操作系统特权，被 profile 进程可以控制追踪会话的生命周期。

此模式在 Android、Linux、MacOS 和 Windows 上受支持。

### 系统模式

在此模式下，应用程序定义的数据源将使用 [IPC over UNIX socket][ipc] 连接到外部 `traced` 服务。

系统模式可以通过在初始化 SDK 时设置 `TracingInitArgs.backends = perfetto::kSystemBackend` 来启用，请参阅下面的示例。

此模式的主要优点是可以创建融合的 trace，其中应用程序事件被叠加在同一 OS 事件的 Timeline 上。这启用了全栈性能调查，一直查看到系统调用和内核调度事件。

此模式的主要限制是它要求外部 `traced` daemon 正在运行并可通过 UNIX socket 连接访问。

建议用于本地调试或实验室测试场景，其中用户（或测试工具）可以控制操作系统部署（例如，在 Android 上 sideload 二进制文件）。

使用系统模式时，必须从外部控制追踪会话，使用 `perfetto` 命令行客户端（请参阅[参考](/docs/reference/perfetto-cli)）。这是因为在收集系统 trace 时，不允许tracing 数据生产者读取 trace 数据，因为它可能会披露有关其他进程的信息并允许侧信道攻击。

- 在 Android 9 (Pie) 及更高版本上，traced 作为平台的一部分提供。
- 在旧版本的 Android 上，可以使用[独立的基于 NDK 的工作流]（/docs/contributing/build-instructions.md）从源代码构建 traced，并通过 adb shell sideload。
<!-- * 在 Linux、MacOS 和 Windows 上，`traced` 必须单独构建和运行。有关说明，请参阅 [Linux quickstart](/docs/quickstart/linux-tracing.md)。
- 在 Windows 上，追踪协议通过 TCP/IP 工作 -->
 [127.0.0.1:32278](https://cs.android.com/android/platform/superproject/main/+/main:external/perfetto/src/tracing/ipc/default_socket.cc;l=75;drc=4f88a2fdfd3801c109d5e927b8206f9756288b12)
 ) + 命名 shmem。

## {#recording} 通过 API 采集 Trace

_通过 API 进行 tracing目前仅支持进程内模式。使用系统模式时，请使用 `perfetto` 命令行客户端（请参阅快速入门指南）。_

首先初始化一个 [TraceConfig](/docs/reference/trace-config-proto.autogen) 消息，该消息指定要记录的数据类型。

如果你的应用程序包含 [Track 事件](track-events.md)（即，`TRACE_EVENT`），你通常希望选择为 Tracing 启用的类别。

默认情况下，启用所有非调试类别，但你可以像这样启用特定的类别：

```C++
perfetto::protos::gen::TrackEventConfig track_event_cfg;
track_event_cfg.add_disabled_categories("*");
track_event_cfg.add_enabled_categories("rendering");
```

接下来，将主 trace 配置与 track 事件部分一起构建：

```C++
perfetto::TraceConfig cfg;
cfg.add_buffers()->set_size_kb(1024); // 最多记录 1 MiB。
auto* ds_cfg = cfg.add_data_sources()->mutable_config();
ds_cfg->set_name("track_event");
ds_cfg->set_track_event_config_raw(track_event_cfg.SerializeAsString());
```

如果你的应用程序包含自定义数据源，你也可以在此处启用它：

```C++
ds_cfg = cfg.add_data_sources()->mutable_config();
ds_cfg->set_name("my_data_source");
```

构建 trace 配置后，你可以开始追踪：

```C++
std::unique_ptr<perfetto::TracingSession> tracing_session(
 perfetto::Tracing::NewTrace());
tracing_session->Setup(cfg);
tracing_session->StartBlocking();
```

TIP: 名称中包含 `Blocking` 的 API 方法将挂起调用线程，直到相应的操作完成。还有没有此限制的异步变体。

现在 tracing 处于活动状态，指示你的应用程序执行你想要记录的操作。之后，停止 tracing 并收集 protobuf 格式的 trace 数据：

```C++
tracing_session->StopBlocking();
std::vector<char> trace_data(tracing_session->ReadTraceBlocking());

// 将 trace 写入文件。
std::ofstream output;
output.open("example.perfetto-trace", std::ios::out | std::ios::binary);
output.write(&trace_data[0], trace_data.size());
output.close();
```

为了节省较长时间 trace 的内存，你还可以通过将文件描述符传递给 Setup() 来告诉 Perfetto 直接写入文件，记住在追踪完成后关闭文件：

```C++
int fd = open("example.perfetto-trace", O_RDWR | O_CREAT | O_TRUNC, 0600);
tracing_session->Setup(cfg, fd);
tracing_session->StartBlocking();
// ...
tracing_session->StopBlocking();
close(fd);
```

生成的 trace 文件可以直接在 [Perfetto UI](https://ui.perfetto.dev) 或 [Trace Processor](/docs/analysis/trace-processor.md) 中打开。

[ipc]: /docs/design-docs/api-and-abi.md#socket-protocol
[atrace-ds]: /docs/data-sources/atrace.md
[atrace-ndk]: https://developer.android.com/ndk/reference/group/tracing
[atrace-sdk]: https://developer.android.com/reference/android/os/Trace
