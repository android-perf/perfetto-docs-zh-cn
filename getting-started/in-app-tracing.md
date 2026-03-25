# 使用 Perfetto 采集应用内 trace

在本指南中，你将学习如何：

- 使用 Perfetto SDK 向 C++ 应用程序添加自定义 trace 点。
- 记录包含自定义事件的 trace。
- 在 Perfetto UI 中可视化 trace。
- 使用 PerfettoSQL 以编程方式分析 trace。

Perfetto SDK 是一个 C++ 库，允许你为你的应用程序添加插桩以记录 trace 事件。这些事件随后可以使用 Perfetto UI 和 Trace Processor 进行可视化和 profile。

## 添加你的第一个插桩

### 设置

签出最新的 SDK 版本

```
git clone https://github.com/google/perfetto.git -b v50.1
```

SDK 由两个文件组成，`sdk/perfetto.h` 和 `sdk/perfetto.cc`。这些是客户端 API 的 amalgamation，旨在易于集成到现有构建系统。源代码是自包含的，只需要符合 C++17 的标准库。

将它们复制到你的项目中。接下来的步骤假设它们在 `perfetto/sdk` 文件夹中。假设你的构建看起来像这样：

<?tabs>

TAB: CMake

```
cmake_minimum_required(VERSION 3.13)
project(Example)

# Main executable
add_executable(example example.cc)
```

</tabs?>

你可以这样添加 perfetto 静态库：

<?tabs>

TAB: CMake

```
# 建议使用最新版本的 CMake。
cmake_minimum_required(VERSION 3.13)

# 项目名称。
project(Example)

# 查找线程库，这是 Perfetto 的依赖项。
find_package(Threads)

# 将 Perfetto SDK 源文件添加到静态库。
include_directories(perfetto/sdk)
add_library(perfetto STATIC perfetto/sdk/perfetto.cc)

# 将应用程序的源文件添加到可执行文件。
add_executable(example example.cc)

# 将 Perfetto 库和线程库链接到你的可执行文件。
target_link_libraries(example perfetto ${CMAKE_THREAD_LIBS_INIT})

# Windows 特定设置。
if (WIN32)
 # Perfetto 库包含许多符号，因此需要"big object"格式。
 target_compile_options(perfetto PRIVATE "/bigobj")

 # 禁用 windows.h 中的旧功能。
 add_definitions(-DWIN32_LEAN_AND_MEAN -DNOMINMAX)

 # 在 Windows 上，我们需要链接到 WinSock2 库。
 target_link_libraries(example ws2_32)
endif (WIN32)

# 使用 Visual Studio 编译器时启用标准兼容模式。
if (MSVC)
 target_compile_options(example PRIVATE "/permissive-")
endif (MSVC)
```

</tabs?>

在你的程序中初始化 perfetto 并定义你的 trace categories:

<?tabs>

TAB: C++

```
#include <perfetto.h>

PERFETTO_DEFINE_CATEGORIES(
 perfetto::Category("rendering")
 .SetDescription("Events from the graphics subsystem"),
 perfetto::Category("network")
 .SetDescription("Network upload and download statistics"));

PERFETTO_TRACK_EVENT_STATIC_STORAGE();

int main(int argc, char** argv) {
 perfetto::TracingInitArgs args;
 args.backends |= perfetto::kInProcessBackend;
 perfetto::Tracing::Initialize(args);
 perfetto::TrackEvent::Register();
 //...
}
```

</tabs?>

你现在可以向代码添加插桩点。它们将在启用 tracing 时发出事件。

`TRACE_EVENT` 宏记录作用域事件。事件在调用宏时开始，并在当前作用域结束时结束（例如，当函数返回时）。这是最常见的事件类型，对于跟踪函数的持续时间很有用。

`TRACE_EVENT_BEGIN` 和 `TRACE_EVENT_END` 宏可用于记录不遵循函数作用域的事件。`TRACE_EVENT_BEGIN` 开始事件，`TRACE_EVENT_END` 默认结束同一线程上开始的最近事件，但可以配置为跨线程甚至跨进程工作(有关更多详细信息，请参见 [Track Event 文档](/docs/instrumentation/track-events.md#tracks))。这对于跟踪跨越多个函数的操作很有用。

`TRACE_COUNTER` 宏记录 Counter 在特定时间点的值。这对于跟踪内存使用或队列中的项目数之类的内容很有用。

<?tabs>

TAB: C++

```
void DrawPlayer(int player_number) {
 TRACE_EVENT("rendering", "DrawPlayer", "player_number", player_number);
 // ...
}

void DrawGame() {
 TRACE_EVENT_BEGIN("rendering", "DrawGame");
 DrawPlayer(1);
 DrawPlayer(2);
 TRACE_EVENT_END("rendering");

 // ...
 TRACE_COUNTER("rendering", "Framerate", 120);
}
```

</tabs?>

## 收集你的第一个 app trace

你可以开始使用以下方法收集事件：

<?tabs>

TAB: C++

```
 // 创建一个 trace 配置对象。这用于定义缓冲区、数据源和 trace 的其他设置。
 perfetto::TraceConfig cfg;

 // 向配置添加一个缓冲区。Trace 被写入内存中的此缓冲区。
 cfg.add_buffers()->set_size_kb(1024); // 1 MB

 // 向配置添加一个数据源。这指定要收集的数据类型。在这种情况下，我们正在收集 track events。
 auto* ds_cfg = cfg.add_data_sources()->mutable_config();
 ds_cfg->set_name("track_event");

 // 配置 track event 数据源。我们可以指定要启用或禁用哪些 categories 的事件。
 perfetto::protos::gen::TrackEventConfig te_cfg;
 te_cfg.add_disabled_categories("*"); // 默认禁用所有 categories。
 te_cfg.add_enabled_categories("rendering"); // 启用我们的"rendering" category。
 ds_cfg->set_track_event_config_raw(te_cfg.SerializeAsString());

 // 创建一个新的 tracing session。
 std::unique_ptr<perfetto::TracingSession> tracing_session =
 perfetto::Tracing::NewTrace();

 // 使用配置设置 tracing session。
 tracing_session->Setup(cfg);

 // 开始 tracing。这将阻塞直到 trace 停止。
 tracing_session->StartBlocking();

 // tracing_session 对象必须在 trace 期间保持活动状态。

 // ...
```

</tabs?>

你可以使用以下方法停止并将它们保存到文件：

<?tabs>

TAB: C++

```
 // 停止 tracing session。这将阻塞直到所有 trace 数据都被刷新。
 tracing_session->StopBlocking();

 // 从 session 读取 trace 数据。
 std::vector<char> trace_data(tracing_session->ReadTraceBlocking());

 // 将 trace 数据写入文件。
 std::ofstream output;
 output.open("example.pftrace", std::ios::out | std::ios::binary);
 output.write(trace_data.data(), std::streamsize(trace_data.size()));
 output.close();
```

</tabs?>

## 可视化你的第一个 app trace

你现在可以使用 https://ui.perfetto.dev/ 打开 `example.pftrace` 文件

它将显示通过执行你的插桩点捕获的事件：

![Track event example](/docs/images/track_event_draw_game.png)

## 查询你的第一个 app trace

除了在时间轴上可视化 trace 之外，Perfetto 还支持使用 SQL 查询 trace。执行此操作的最简单方法是使用 UI 中直接可用的查询引擎。

1. 在 Perfetto UI 中，点击左侧菜单中的"Query (SQL)"标签。

 ![Perfetto UI Query SQL](/docs/images/perfetto-ui-query-sql.png)

2. 这将打开一个两部分窗口。你可以在顶部部分编写 PerfettoSQL 查询，并在底部部分查看结果。

 ![Perfetto UI SQL Window](/docs/images/perfetto-ui-sql-window.png)

3. 然后你可以执行查询 Ctrl/Cmd + Enter:

例如，通过运行：

```
SELECT
 dur AS duration_ns,
 EXTRACT_ARG(slice.arg_set_id, 'debug.player_number') AS player_number
FROM slice
WHERE slice.name = 'DrawPlayer';
```

你可以查看 `DrawPlayer` 插桩点被命中了多少次，每次执行了多长时间以及它的 `player_number` 注释。

![SQL query example](/docs/images/sql_draw_player.png)

帧率 Counter 在 `counter` 表中可用：

```sql
SELECT ts AS timestamp_ns, value AS frame_rate
FROM counter
JOIN track ON track.id = counter.track_id
WHERE name = 'Framerate';
```

## Combined In-App and System Tracing

虽然应用内 tracing 对于理解应用程序在隔离中的行为很有用，但它的真正力量来自于将其与系统范围的 trace 结合。这使你能够查看应用的事件如何与 CPU 调度、内存使用和 I/O 等系统事件相关联，在整个系统上下文中提供应用程序性能的完整图景。

要启用组合 tracing，你需要更改应用程序以连接到系统范围的 tracing 服务，然后使用标准系统 tracing 工具采集 trace。

1. **修改你的应用程序代码**：

  - 更改初始化以连接到系统后端（`kSystemBackend`）。这告诉 Perfetto SDK 将 trace 事件发送到中央系统 tracing 服务，而不是在应用程序内收集它们。
  - 删除所有与管理 tracing session 相关的代码(`perfetto::Tracing::NewTrace()`, `tracing_session->Setup()`, `tracing_session->StartBlocking()` 等)。你的应用程序现在仅充当 trace 数据的生产者，系统 tracing 服务将控制何时开始和停止 tracing。

 你的 `main` 函数现在应该看起来像这样：

 ```cpp
 #include <perfetto.h>

 // 像以前一样定义你的 categories。
 PERFETTO_DEFINE_CATEGORIES(
 perfetto::Category("rendering")
 .SetDescription("Events from the graphics subsystem"),
 perfetto::Category("network")
 .SetDescription("Network upload and download statistics"));

 PERFETTO_TRACK_EVENT_STATIC_STORAGE();

 int main(int argc, char** argv) {
 // 连接到系统 tracing 服务。
 perfetto::TracingInitArgs args;
 args.backends |= perfetto::kSystemBackend;
 perfetto::Tracing::Initialize(args);

 // 注册你的 track event 数据源。
 perfetto::TrackEvent::Register();

 // 你的应用程序逻辑放在这里。
 // 当在外部启用 tracing 时,TRACE_EVENT 宏现在将写入系统 trace 缓冲区。
 // ...
 }
 ```

2. **采集系统 trace**：

 运行你的应用程序，你现在可以使用 [采集 system traces](/docs/getting-started/system-tracing.md) 指南中描述的方法采集组合 trace。

 配置 trace 时，除了你想要收集的任何系统数据源（例如，`linux.ftrace`）之外，你还需要启用 `track_event` 数据源。这将确保你的应用程序的自定义事件包含在 trace 中。

 当你在 Perfetto UI 中打开生成的 trace 文件时，你将看到应用程序的自定义 tracks 与系统级别 tracks 一起显示。

## 后续步骤

现在你已经采集了你的第一个应用内 trace，你可以了解更多有关为代码添加插桩的信息：

- **[Tracing SDK](/docs/instrumentation/tracing-sdk.md)** ： 深入了解 SDK 的功能。
- **[Track Events](/docs/instrumentation/track-events.md)** ： 了解有关不同类型的 track events 以及如何使用它们的更多信息。
