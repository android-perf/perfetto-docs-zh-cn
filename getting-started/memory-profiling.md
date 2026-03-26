# 使用 Perfetto 记录 memory profiles

在本指南中，你将学习如何：

- 使用 Perfetto 记录 native 和 Java heap profiles。
- 在 Perfetto UI 中可视化和 profile heap profiles。
- 了解不同的 memory profiling 模式以及何时使用它们。

进程的内存使用在进程的性能中起着关键作用，并影响整个系统的稳定性。了解进程在何处以及如何使用内存可以提供重要的见解，以理解为什么你的进程可能比预期运行更慢，或者只是帮助你使程序更高效。

当涉及到应用和内存时，进程使用内存主要有两种方式：

- **Native C/C++/Rust 进程**： 通常通过 libc 的 malloc/free（或其上的包装器，如 C++ 的 new/delete）分配内存。请注意，当使用具有 JNI 对应物的 Java API 时，native 分配仍然是可能的（并且相当频繁）。一个典型的例子是 `java.util.regex.Pattern`，它通常拥有 Java 堆上的**托管内存**和由于底层使用 native regex 库而产生的**native 内存**。

- **Java/KT 应用**： 应用程序内存占用的大部分位于**托管堆**中（在 Android 的情况下，由 ART 的垃圾收集器管理）。这是每个 `new X()` 对象所在的地方。

Perfetto 提供了两种补充技术来调试上述内容：

- [**heap profiling**](#native-c-c-rust-heap-profling) 用于 native 代码：这是基于在 malloc/free 时采样调用栈并显示聚合火焰图以按调用站点分解内存使用。

- [**heap dumps**](#java-managed-heap-dumps) 用于 Java/托管代码：这是基于创建堆保留图，显示对象之间的保留依赖关系（但没有调用站点）。

## Native (C/C++/Rust) Heap Profiling

C/C++/Rust 等 native 语言通常通过使用 libc 系列的 `malloc`/`free` 函数在最低级别分配和释放内存。Native heap profiling 通过_拦截_对这些函数的调用并注入跟踪已分配但未释放内存的调用栈的代码来工作。这允许跟踪每个分配的"代码来源"。malloc/free 可能是繁重堆进程中的性能热点：为了减轻 memory profiler 的开销，我们支持[采样](/docs/design-docs/heapprofd-sampling）以权衡准确性和开销。

NOTE: 使用 Perfetto 的 native heap profiling 仅适用于 Android 和 Linux;这是由于我们用于拦截 malloc 和 free 的技术仅在这些操作系统上工作。

需要注意的一个非常重要的点是，heap profiling **不是追溯性的**。它只能报告在 tracing 开始_之后_发生的分配。它无法提供有关在 trace 开始之前发生的分配的任何见解。如果你需要从进程开始 profiling内存使用，必须在进程启动之前开始 tracing。

如果你的问题是_"为什么这个进程现在这么大？"_，你不能使用 heap profiling 来回答有关过去发生的问题。然而，我们的轶事经验是，如果你正在 Tracing 内存泄漏，很有可能泄漏会随着时间的推移继续发生，因此你将能够看到未来的增量。

### 采集你的第一个 heap profile

<?tabs>

TAB: Android (Perfetto UI)

在 Android 上，Perfetto heap profiling hooks 无缝集成到 libc 实现中。

#### 先决条件

- 一台运行 Android 10- 的设备。
- 一个 [_Profileable_ 或 _Debuggable_](https://developer.android.com/topic/performance/benchmarking/macrobenchmark-instrumentation#profileable-apps) 应用。如果你在 Android 的 _"user"_ 构建上运行（相对于 _"userdebug"_ 或 _"eng"_），你的应用需要在 manifest 中标记为 profileable 或 debuggable。有关更多详细信息，请参见 [heapprofd documentation][hdocs]。

[hdocs]: /docs/data-sources/native-heap-profiler.md#heapprofd-targets

#### 说明
- 打开 https://ui.perfetto.dev/#!/record
- 选择 Android 作为目标设备并使用可用的传输之一。如果有疑问，WebUSB 是最简单的选择。
- 点击左侧的 `Memory` Probe，然后切换 `Native Heap Profiling` 选项。
- 在 `Names` 框中输入进程名称。
- 你必须输入的进程名称是（第一个参数的）进程 cmdline。即 `adb shell ps -A` 的最右列（NAME）。
- 在 `Buffers and duration` 页面选择观察时间。这将决定 profile 拦截 malloc/free 调用的时间。
- 按红色按钮开始采集 trace。
- 在采集 trace 时，与被 profile 的进程交互。运行你的用户旅程，测试模式，与应用交互。

![UI Recording](/docs/images/heapprofd-ui.png)

TAB: Android (Command line)

在 Android 上，Perfetto heap profiling hooks 无缝集成到 libc 实现中。

#### 先决条件

- 已安装 [ADB](https://developer.android.com/studio/command-line/adb)。
- _Windows 用户_：确保下载的 adb.exe 在 PATH 中。`set PATH=%PATH%;%USERPROFILE%\Downloads\platform-tools`
- 一台运行 Android 10- 的设备。
- 一个 [_Profileable_ 或 _Debuggable_](https://developer.android.com/topic/performance/benchmarking/macrobenchmark-instrumentation#profileable-apps) 应用。如果你在 Android 的 _"user"_ 构建上运行（相对于 _"userdebug"_ 或 _"eng"_），你的应用需要在 manifest 中标记为 profileable 或 debuggable。有关更多详细信息，请参见 [heapprofd documentation][hdocs]。

[hdocs]: /docs/data-sources/native-heap-profiler.md#heapprofd-targets

#### 说明

```bash
:$ adb devices -l
List of devices attached
24121FDH20006S device usb:2-2.4.2 product:panther model:Pixel_7 device:panther transport_id:1
```

如果报告了多个设备或模拟器，你必须预先选择一个，如下所示：

```bash
export ANDROID_SERIAL=24121FDH20006S
```

下载 `tools/heap_profile`(如果你没有 perfetto checkout):

```bash
curl -LO https://raw.githubusercontent.com/google/perfetto/main/tools/heap_profile
```

然后开始 profile:

```bash
python3 heap_profile -n com.google.android.apps.nexuslauncher
```

运行你的测试模式，与进程交互，完成后按 Ctrl-C(或传递 `-d 10000` 进行限时 profiling)

当你按 Ctrl-C 时，heap_profile 脚本将拉取 traces 并将它们存储在 /tmp/heap_profile-latest 中。查找说：

```bash
Wrote profiles to /tmp/53dace (symlink /tmp/heap_profile-latest)
The raw-trace file can be viewed using https://ui.perfetto.dev
```

TAB: Linux (Command line)

#### 先决条件

- 你需要从 Perfetto checkout 构建 `libheapprofd_glibc_preload.so` 库([说明](/docs/data-sources/native-heap-profiler#-non-android-linux-support))

#### 说明

下载 tracebox 和 heap_profile 脚本
```bash
curl -LO https://get.perfetto.dev/tracebox
curl -LO https://raw.githubusercontent.com/google/perfetto/main/tools/heap_profile
chmod +x tracebox heap_profile
```

启动 tracing 服务
```bash
./tracebox traced &
```

生成 heapprofd 配置并启动 tracing session。
```bash
# 将 trace_processor_shell 替换为你想要 profile 的进程名称。
./heap_profile -n trace_processor_shell --print-config | \
 ./tracebox perfetto --txt -c - -o ~/trace_processor_memory.pftrace
```

打开另一个终端（或标签），启动你想要 profile 的进程，预加载 heapprofd 的 .so。示例：
```bash
PERFETTO_HEAPPROFD_BLOCKING_INIT=1 \
LD_PRELOAD=out/lnx/libheapprofd_glibc_preload.so \
trace_processor_shell /dev/null

# 键入这将导致 40MB 分配。
> CREATE TABLE x as SELECT randomblob(40000000) as data
```

默认情况下，heapprofd 懒惰初始化以避免阻塞你的程序主线程。但是，如果你的程序在启动时进行内存分配，这些可能会被错过。为了避免这种情况，设置环境变量 `PERFETTO_HEAPPROFD_BLOCKING_INIT=1`;在第一次 malloc 上，你的程序将被阻塞，直到 heapprofd 完全初始化，但意味着每次分配都将被正确跟踪。

此时：

- 如果你的进程首先终止，它将把所有 profiling 数据刷新到 tracing 缓冲区中。
- 如果不是，你可以通过停止 trace 请求刷新 profiling 数据。

在任何情况下：在上一步的 `tracebox perfetto` 命令上按 Ctrl-C。这将写入 trace 文件（例如 `~/trace_processor_memory.pftrace`），你可以使用 Perfetto UI 打开它。

完成后还要记得杀死 `tracebox traced` 服务。
```bash
fg
# Ctrl-C
```
</tabs?>

### 可视化你的第一个 heap profile

在 [Perfetto UI](https://ui.perfetto.dev) 中打开 `/tmp/heap_profile-latest` 文件，并点击 UI 中标记为_"Heap profile"_的 UI track 中的 V 形标记。

![Profile Diamond](/docs/images/profile-diamond.png)
![Native Flamegraph](/docs/images/native-heap-prof.png)

默认情况下，聚合火焰图显示按调用栈聚合的未释放内存（即尚未 free(） 的内存)。顶部的帧代表调用栈中的最早入口点(通常是 `main()` 或 `pthread_start()`)。当你向底部移动时，你将更接近最终调用 `malloc()` 的帧。

你也可以将聚合更改为以下模式：

![Heap Profiling modes](/docs/images/heapprof-modes.png)

- **Unreleased Malloc Size**：默认模式，按 SUM（未释放内存字节）聚合调用栈。
- **Unreleased Malloc Count**：按计数聚合未释放的分配，忽略每个分配的大小。这对于发现小尺寸的泄漏很有用，其中每个对象都很小，但大量对象随时间累积。
- **Total Malloc Size**：按通过 malloc() 分配的字节聚合调用栈，无论它们是否已释放。这有助于调查堆流失，对分配器造成很大压力的代码路径，即使它们最终释放内存。
- **Total Malloc Count**：与上述类似，但按调用 `malloc()` 的次数聚合，并忽略每个分配的大小。

### 查询你的第一个 heap profile

除了在时间轴上可视化 trace 之外，Perfetto 还支持使用 SQL 查询 trace。执行此操作的最简单方法是使用 UI 中直接可用的查询引擎。

1. 在 Perfetto UI 中，点击左侧菜单中的"Query (SQL)"标签。

 ![Perfetto UI Query SQL](/docs/images/perfetto-ui-query-sql.png)

2. 这将打开一个两部分窗口。你可以在顶部部分编写 PerfettoSQL 查询，并在底部部分查看结果。

 ![Perfetto UI SQL Window](/docs/images/perfetto-ui-sql-window.png)

3. 然后你可以执行查询 Ctrl/Cmd + Enter:

例如，通过运行：

```
INCLUDE PERFETTO MODULE android.memory.heap_graph.heap_graph_class_aggregation;

SELECT
 -- 类名(如果可用,则去混淆)
 type_name,
 -- 类实例计数
 obj_count,
 -- 类实例大小
 size_bytes,
 -- 类实例的 native 大小
 native_size_bytes,
 -- 可访问类实例计数
 reachable_obj_count,
 -- 可访问类实例大小
 reachable_size_bytes,
 -- 可访问类实例的 native 大小
 reachable_native_size_bytes
FROM android_heap_graph_class_aggregation;
```

你可以看到可访问聚合对象大小和对象计数的摘要。

## Java/Managed Heap Dumps

Java 以及基于它构建的托管语言（如 Kotlin）使用运行时环境来处理内存管理和垃圾收集。在这些语言中，（几乎）每个对象都是堆分配。内存通过对象引用进行管理：对象保留其他对象，一旦对象变得不可访问，内存就会由垃圾收集器自动回收。没有像手动内存管理那样的 free() 调用。

因此，托管语言的大多数 profiling 工具通过捕获和分析完整的堆转储来工作，其中包括所有活动对象及其保留关系——一个完整的对象图。

这种方法的优点是追溯性分析：它提供整个堆的一致快照，而无需先前的插桩。然而，它有一个权衡：虽然你可以看到哪些对象使其他对象保持活动，但你通常无法看到分配这些对象的确切调用站点。这可能会使推理内存使用变得更加困难，特别是当从代码中的多个位置分配相同类型的对象时。

NOTE: 使用 Perfetto 的 Java heap dumps 仅适用于 Android。这是由于需要与 JVM（Android Runtime - ART）深度集成才能在不影响进程性能的情况下高效捕获堆转储。

### 采集你的第一个 heap dump

<?tabs>

TAB: Android (Perfetto UI)

在 Android 上，Perfetto heap profiling hooks 无缝集成到 libc 实现中。

#### 先决条件

- 一台运行 Android 10- 的设备。
- 一个 [_Profileable_ 或 _Debuggable_](https://developer.android.com/topic/performance/benchmarking/macrobenchmark-instrumentation#profileable-apps) 应用。如果你在 Android 的 _"user"_ 构建上运行（相对于 _"userdebug"_ 或 _"eng"_），你的应用需要在 manifest 中标记为 profileable 或 debuggable。

#### 说明
- 打开 https://ui.perfetto.dev/#!/record
- 选择 Android 作为目标设备并使用可用的传输之一。如果有疑问，WebUSB 是最简单的选择。
- 点击左侧的 `Memory` Probe，然后切换 `Java heap dumps` 选项。
- 在 `Names` 框中输入进程名称。
- 你必须输入的进程名称是（第一个参数的）进程 cmdline。即 `adb shell ps -A` 的最右列（NAME）。
- 在 `Buffers and duration` 页面选择短持续时间（10 秒或更少）。trace 持续时间对于此特定数据源没有意义，因为它在 trace 结束时发出整个转储。更长的 trace 不会导致更多或更好的数据。
- 按红色按钮开始采集 trace。

![UI Recording](/docs/images/jheapprof-ui.png)

TAB: Android (Command line)

在 Android 上，Perfetto heap profiling hooks 无缝集成到 libc 实现中。

#### 先决条件

- 已安装 [ADB](https://developer.android.com/studio/command-line/adb)。
- _Windows 用户_：确保下载的 adb.exe 在 PATH 中。`set PATH=%PATH%;%USERPROFILE%\Downloads\platform-tools`
- 一台运行 Android 10- 的设备。
- 一个 [_Profileable_ 或 _Debuggable_](https://developer.android.com/topic/performance/benchmarking/macrobenchmark-instrumentation#profileable-apps) 应用。如果你在 Android 的 _"user"_ 构建上运行（相对于 _"userdebug"_ 或 _"eng"_），你的应用需要在 manifest 中标记为 profileable 或 debuggable。

#### 说明

```bash
:$ adb devices -l
List of devices attached
24121FDH20006S device usb:2-2.4.2 product:panther model:Pixel_7 device:panther transport_id:1
```

如果报告了多个设备或模拟器，你必须预先选择一个，如下所示：

```bash
export ANDROID_SERIAL=24121FDH20006S
```

下载 `tools/java_heap_dump`(如果你没有 perfetto checkout):

```bash
curl -LO https://raw.githubusercontent.com/google/perfetto/main/tools/java_heap_dump
```

然后开始 profile:

```bash
python3 java_heap_dump -n com.google.android.apps.nexuslauncher
```
脚本将采集带有堆转储的 trace 并打印 trace 文件的路径(例如 /tmp/tmpmhuvqmnqprofile)

```bash
Wrote profile to /tmp/tmpmhuvqmnqprofile
This can be viewed using https://ui.perfetto.dev.
```
</tabs?>

### 可视化你的第一个 heap dump

在 Perfetto UI 中打开 `/tmp/xxxx` 文件，并点击标记为"Heap profile"的 UI track 中的 V 形标记。

UI 将显示堆图的扁平版本，采用火焰图的形状。火焰图将共享相同可访问性路径的相同类型的对象聚合在一起。两种扁平化策略是可能的：

- **Shortest path**：这是在火焰图标题中选择 `Object Size` 时的默认选项。这基于最小化它们之间距离的启发式方法排列对象。

- **Dominator tree**：选择 `Dominated Size` 时，它使用支配者树算法扁平化图。

你可以在 [Debugging memory usage](/docs/case-studies/memory#java-hprof) 案例研究中了解更多有关它们的信息

![Sample heap dump in the UI](/docs/images/jheapprof-dump.png)

### 查询你的第一个 heap profile

除了在时间轴上可视化 trace 之外，Perfetto 还支持使用 SQL 查询 trace。执行此操作的最简单方法是使用 UI 中直接可用的查询引擎。

1. 在 Perfetto UI 中，点击左侧菜单中的"Query (SQL)"标签。

 ![Perfetto UI Query SQL](/docs/images/perfetto-ui-query-sql.png)

2. 这将打开一个两部分窗口。你可以在顶部部分编写 PerfettoSQL 查询，并在底部部分查看结果。

 ![Perfetto UI SQL Window](/docs/images/perfetto-ui-sql-window.png)

3. 然后你可以执行查询 Ctrl/Cmd + Enter:

例如，通过运行：

```
INCLUDE PERFETTO MODULE android.memory.heap_profile.summary_tree;

SELECT
 -- 调用栈的 id。在此上下文中,调用栈是直到根的唯一帧集。
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
 -- 以此函数为叶帧分配且*未释放*的内存量。
 self_size,
 -- 以此函数出现在调用栈上任何位置分配且*未释放*的内存量。
 cumulative_size,
 -- 以此函数为叶帧分配的内存量。这可能包括后来被释放的内存。
 self_alloc_size,
 -- 以此函数出现在调用栈上任何位置分配的内存量。这可能包括后来被释放的内存。
 cumulative_alloc_size
FROM android_heap_profile_summary_tree;
```

你可以查看 trace 中每个唯一调用栈分配的内存。

## 其他类型的内存

除了标准的 native 和 Java 堆之外，还可以以默认不 profile 的其他方式分配内存。以下是一些常见示例：

- **直接 `mmap()` 调用**：应用程序可以使用 `mmap()` 直接从内核请求内存。这通常用于大分配或将文件映射到内存。Perfetto 目前没有自动 profile 这些分配的方法。

- **自定义分配器**：某些应用程序出于性能原因使用自己的内存分配器。这些分配器通常使用 `mmap()` 从系统获取内存，然后在内部管理它。虽然 Perfetto 无法自动 profile 这些，但你可以使用 [heapprofd Custom Allocator API](/docs/instrumentation/heapprofd-api) 为你的自定义分配器添加插桩以启用 heap profiling。

- **DMA 缓冲区(`dmabuf`)** ：这些是用于在不同硬件组件（例如，CPU、GPU 和相机）之间共享内存的特殊缓冲区。这在图形密集型应用程序中很常见。你可以通过在你的 trace 配置中启用 `dmabuf_heap/dma_heap_stat` ftrace 事件来跟踪 `dmabuf` 分配。

## 后续步骤

现在你已经记录并分析了你的第一个 memory profile，你可以探索更高级的主题：

- **了解更多有关内存调试：** [Android 上的内存使用指南](/docs/case-studies/memory.md) 深入介绍在 Android 上调试内存问题。
- **探索 heapprofd 数据源：** [heapprofd 数据源文档](/docs/data-sources/native-heap-profiler.md) 提供有关 native heap profiler 的更多详细信息。
