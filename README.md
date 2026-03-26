# 什么是 Perfetto?

TIP: 如果你不熟悉 tracing，或者换句话说，对性能领域比较陌生，我们建议先阅读 [什么是 Tracing?](/docs/tracing-101.md) 页面。

Perfetto 是一个开源的 SDK、守护进程和工具套件，使用 **tracing** 帮助开发者理解复杂系统的行为，并在客户端/嵌入式系统上定位功能和性能问题的根本原因。

它包括：

- **高性能 tracing 守护进程**，用于从单个机器上的多个进程捕获 tracing 信息到一个统一的 trace 文件中，以便离线分析和可视化。
- **低开销 tracing SDK**，用于直接在用户空间对 C/C++ 代码的时序和状态变化进行 tracing。
- **Android 和 Linux 上丰富的系统级 Probe**，用于在 trace 期间捕获更广泛的系统级上下文（例如调度状态、CPU 频率、memory profiling、调用栈采样）。
- **完全本地的、基于浏览器的 UI**，用于在 Timeline 上可视化大量复杂的、相互关联的数据。我们的 UI 适用于所有主流浏览器，不需要任何安装，可以离线工作，并且可以打开由其他（非 Perfetto） tracing 工具采集的 trace。
- **强大的、基于 SQL 的分析库**，用于以编程方式分析 Timeline 上的大量复杂的、相互关联的数据，即使这些数据不是用 Perfetto 记录工具收集的。

![](images/perfetto-stack.svg)

## 为什么使用 Perfetto?

Perfetto 从设计之初就作为 Android 操作系统和 Chrome 浏览器的默认 tracing 系统。因此，Perfetto 官方支持收集、分析和可视化：

- **Android 系统级 trace**，用于调试和定位 Android 平台和 Android 应用中的功能和性能问题。Perfetto 适用于调试例如启动缓慢、丢帧（jank）、动画故障、低内存终止、应用无响应（ANR）和一般的异常行为。

- **Android 上的 Java 堆转储和原生 heap profile**，用于分别调试和定位 Android 平台和 Android 应用中 Java/Kotlin 代码和 C++ 代码的高内存使用问题。
- **Android 上的调用栈采样 profiling**，用于调试和定位 Android 平台和 Android 应用中 C++/Java/Kotlin 代码的高 CPU 使用问题。
- **Chrome 浏览器 trace**，用于调试和定位浏览器、V8、Blink 中的问题，在高级用例中，还可以定位网站本身的问题。

除了这些"官方"用例之外，Perfetto 还包含一套高度灵活的工具。这使它能够用作通用 tracing 系统、性能数据分析器或 Timeline 可视化工具。Perfetto 团队投入部分时间支持这些用例，尽管支持级别较低。

Perfetto 的其他常见用例包括：

- **收集、分析和可视化应用内 trace**，用于调试 Windows、macOS 和基于 Linux 的嵌入式系统上的 C/C++ 应用和库中的功能和性能问题。
- **收集、分析和可视化 Linux 上的 heap profile**，用于调试 C/C++/Rust 应用和库的高内存使用问题。
- **分析和可视化 Linux 上的 CPU profile（Linux perf profile）**，用于优化 C/C++/Rust 应用和库中的 CPU 使用。
- **分析和可视化各种 profile 和 tracing 格式**。Perfetto 可以打开来自各种其他工具的 trace 和 profile 文件，允许你在许多数据源上使用 Perfetto UI 及其基于 SQL 的查询引擎，包括：
  - _Chrome JSON 格式_
  - _Firefox Profiler JSON 格式_
  - _Linux perf(二进制和文本格式)_
  - _Linux ftrace 文本格式_
  - _macOS Instruments_
  - _Fuchsia tracing 格式_
- **分析和可视化任意的"类 trace"数据**。Perfetto 分析和可视化工具可用于任何"类 trace"数据（例如，带有时间戳和一些负载的数据），只要它可以转换为 Perfetto protobuf 格式；可能性仅受限于创造力！

## 为什么**不**使用 Perfetto?

Perfetto 有几种类型的场景是不适合或明确不支持的。

- **为分布式/服务器系统采集 trace**

  - Perfetto **不是** OpenTelemetry、Jaeger、Datadog 风格的分布式 tracer。Perfetto 的采集工具完全用于采集客户端 trace，特别是在系统级别。我们的团队认为，分布式/服务器 tracing 领域已经被上述项目很好地覆盖了，而不像 Android 和 Linux/嵌入式系统这样的客户端系统。
  - 但是，如果 trace 转换为 Perfetto 支持的格式，Perfetto UI **可以**用于可视化分布式 trace。事实上，这在 Google 内部很常见。

- **在 Windows 或 macOS 上采集系统 trace**

  - Perfetto 的采集工具**不**与 Windows 或 macOS 上的任何系统级数据源集成。
  - 但是，Perfetto _可以_用于分析和可视化使用 Instruments 收集的 macOS trace，因为我们原生支持 Instruments XML 格式。

- **在关键路径上消费 trace**

  - Perfetto 的生产者代码针对低开销 trace 写入进行了优化，但消费者端_没有_针对低延迟读取进行优化。
  - 这意味着_不_建议将 Perfetto 用于需要端到端低延迟 tracing 的场景。

- **以尽可能低的开销采集 trace**

  - Perfetto SDK 不声称是记录 trace 的最快方式：我们很清楚会有一些库和工具可以以更低的开销捕获 trace。你可以通过在 shmem 环形缓冲区中记录固定大小的事件并移动原子指针来击败我们的 tracing SDK。
  - 相反，Perfetto 的记录库和守护进程专注于在性能、灵活性和安全性之间取得良好的平衡。
  - 例如，Perfetto 支持任意大小的事件（例如高分辨率截图）、协调多进程 tracing、具有不同配置的并发 tracing 会话、动态缓冲区多路复用、附加到 trace 事件的任意嵌套键值**参数**、动态字符串实习、用于将 trace 事件链接在一起的**流**，以及许多其他低开销 tracing 系统不支持的**动态 trace 事件名称**。
  - 但是，如果这些 trace 可以转换为 Perfetto protobuf 格式或我们原生支持的其他格式（例如 _Chrome JSON_、_Fuchsia_ 等），Perfetto UI _可以_用于可视化使用非 Perfetto 工具采集的 trace。

- **为游戏采集、分析或可视化 GPU trace**

  - 游戏的 tracing 和性能分析与通用软件的 tracing 有很大不同，原因很多：整个系统围绕"帧"的方向，对 GPU 及其利用率的重视，游戏引擎的存在以及与它们的集成需求。
  - 由于 Perfetto 没有专注于游戏开发者非常关心的事情，我们觉得 Perfetto 不太适合这个任务。
  - 我们在 Android 上有一些 GPU 渲染阶段和 GPU Counters 记录的支持，但这些功能由 [Android GPU Inspector](https://gpuinspector.dev) 更好地支持（它在底层使用 Perfetto 作为其数据源之一）。

## 如何开始使用 Perfetto?

我们理解 Perfetto 有很多组件，因此对于项目新手来说可能会感到困惑，不知道哪些与他们相关。因此，我们有专门的页面：[如何开始使用 Perfetto?](/docs/getting-started/start-using-perfetto.md)

## {#who-uses-perfetto} 谁在使用 Perfetto?

Perfetto 是 **Android 操作系统**和 **Chromium 浏览器**的**默认 tracing 系统**。因此，Perfetto 被 Google 的这些团队广泛使用，既用于主动识别性能改进，也用于被动地在本地、实验室甚至从现场调试/定位问题。

Google 还有许多其他团队以多种方式使用 Perfetto。这包括 tracing 系统的"非传统"用途。Perfetto 也被业界许多其他公司广泛使用和采用。

以下是在博客文章、文章和视频中公开提及 Perfetto 的非详尽列表：

- [使用 dotnet-trace 和 Perfetto 诊断 .NET 应用程序的性能问题](https://dfamonteiro.com/posts/using-dotnet-trace-with-perfetto/)
- [Google IO 2023 - Dart 和 Flutter 的新特性](https://youtu.be/yRlwOdCK7Ho?t=798)
- [Google IO 2023 - 调试 Jetpack Compose](https://youtu.be/Kp-aiSU8qCU?t=1092)
- [性能：Perfetto Trace 查看器 - MAD Skills](https://www.youtube.com/watch?v=phhLFicMacY)
 "在 MAD Skills 系列关于性能的这一集中，Android 性能工程师 Carmen Jackson 讨论了 Perfetto trace 查看器，这是 Android Studio 查看系统 trace 的替代方案。"
- [Meta Quest 平台上的性能和优化](https://m.facebook.com/RealityLabs/videos/performance-and-optimization-on-meta-quest-platform/488126049869673/)
- [通过比例 trace 进行性能测试](https://www.jviotti.com/2022/09/07/performance-testing-through-proportional-traces.html)
- [性能](https://www.twoscomplement.org/podcast/performance.mp3) 
 [Twoscomplement 播客](https://www.twoscomplement.org/#podcast）的一集"我们最高效的播客。Ben 和 Matt 在不到 30 分钟内谈论性能测试和优化。"
- [Collabora：使用 Perfetto 分析虚拟化 GPU 加速](https://www.collabora.com/news-and-blog/blog/2021/04/22/profiling-virtualized-gpu-acceleration-with-perfetto/)
- [Snap：大规模客户端 Tracing](https://www.droidcon.com/2022/06/28/client-tracing-at-scale/)
 "由于 Android 设备种类繁多，很难找到性能问题的根本原因。通过利用 trace，我们可以开始了解导致糟糕用户体验的确切情况。我们将讨论如何为我们的 Snapchat 应用进行插桩，以便我们能够获得必要的可解释性信号。此外，我们将描述如何将 tracing 纳入我们的开发过程，从本地调试到性能测试，最后到生产。"
- [Microsoft：用于分析 Android、Linux 和 Chromium 浏览器性能的 Perfetto 工具](https://devblogs.microsoft.com/performance-diagnostics/perfetto-tooling-for-analyzing-android-linux-and-chromium-browser-performance-microsoft-performance-tools-linux-android/)
- [Mesa 3D](https://docs.mesa3d.org/perfetto.html) 在其某些驱动程序中嵌入 Perfetto，用于 GPU Counters 和渲染阶段监控。
- [JaneStreet 的 MagicTrace](https://blog.janestreet.com/magic-trace/) 基于 Perfetto 的工具，用于采集和可视化 Intel 处理器 trace。

## 在哪里可以找到更多信息并获得 Perfetto 的帮助？

关于我们的源代码和项目主页：
[GitHub](https://github.com/google/perfetto)

问答：

- [GitHub Discussions](https://github.com/google/perfetto/discussions/categories/q-a) 或我们的
 [公开邮件列表](https://groups.google.com/forum/#!forum/perfetto-dev)。
- **Googlers**： 使用 [YAQS](https://go/perfetto-yaqs) 或我们的
 [内部邮件列表](http://go/perfetto-dev)。

影响 Perfetto 任何部分（Chrome tracing 除外）的错误：

- [GitHub issues](https://github.com/google/perfetto/issues)。
- **Googlers**： 使用内部错误跟踪器
 [go/perfetto-bugs](http://goto.google.com/perfetto-bugs)

影响 Chrome Tracing 的错误：

- 使用 http://crbug.com `Component:Speed>Tracing label:Perfetto`。

直接与 Perfetto 团队聊天：

- 使用 [Discord](https://discord.gg/35ShE3A)
- **Googlers**： 感谢你联系我们。我们的线路目前正忙。你的留言对我们很重要，客服人员会尽快回复你。如果你的咨询确实紧急，请参阅
 [此页面](http://go/perfetto-project)。

Perfetto 遵循
[Google 开源社区指南](https://opensource.google/conduct/)。
