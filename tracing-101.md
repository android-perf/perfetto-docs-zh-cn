# 什么是 Tracing?

NOTE: 本文档中的 "Trace" 一词用于
**客户端** 软件的上下文（例如，在单个机器上运行的程序）。在
服务器世界中，**Trace** 通常是 _分布式 Tracing_ 的简称，这是一种
从许多不同服务器收集数据以了解 "请求"
在多个服务中流转的方法。因此，如果你对此类 Trace 感兴趣，本文档将对你有用。

本页提供 Profiling 和 Tracing 的鸟瞰图。其目的是为那些不知道 "Trace" 是什么的人提供指导。

## 性能分析简介

性能分析的目标是使软件运行 _更好_ 。_更好_ 的定义差异很大，取决于实际情况。例如：

- 使用更少的资源（CPU、内存、网络、电池等）执行相同的工作
- 增加可用资源的利用率
- 识别并完全消除不必要的工作

改进性能的很大一部分困难来自识别性能问题的根本原因。现代软件系统很复杂，具有很多组件和交叉交互网络。帮助工程师理解系统执行并指出关键问题的技术至关重要。

**Tracing** 和 **Profiling** 是用于性能分析的两种广泛使用的技术。

## Tracing 简介

**Tracing** 涉及收集有关系统执行的非常详细的数据。单个连续采集会话称为 Trace 文件或简称 **Trace**。

Trace 包含足够的细节以完全重建事件的 Timeline。它们通常包括低级内核事件，如 Scheduler 上下文切换、线程唤醒、系统调用等。使用 "正确" 的 Trace，不需要重现性能错误，因为 Trace 提供了所有必要的上下文。

应用程序代码也在程序中被认为是 _重要的_ 区域进行 **插桩**。这种插桩程序随着时间的推移在做什么（例如，哪些函数正在运行，或每次调用花了多长时间）以及关于执行的上下文（例如，函数调用的参数是什么，或为什么要运行函数）。

Trace 中的细节级别使得在几乎所有最简单的情况下都不可能像 Log 文件那样直接读取 Trace。相反，使用 **Trace 分析** 库和 **Trace 查看器** 的组合。Trace 分析库为用户提供了一种以编程方式提取和汇总 Trace 事件的方法。Trace 查看器在 Timeline 上可视化 Trace 中的事件，为用户提供系统随着时间的推移在做什么的图形视图。

### Logging 与 Tracing

一个很好的直觉是，logging 对于功能测试来说就像 Tracing 对于性能分析一样。在某种意义上，Tracing 是 "结构化" Logging：不是从系统的各个部分发出任意字符串，而是以结构化方式反映系统的详细状态，以允许重建事件的 Timeline。

此外，Tracing 框架（如 Perfetto）非常强调具有最小开销。这一点至关重要，因为框架不会显著干扰被测量的任何内容：现代框架足够快，可以在纳秒级别测量执行，而不会显著影响程序的执行速度。

_小插曲：理论上，Tracing 框架也足够强大，可以作为 Logging 系统。然而，每个框架在实践中都足够不同，以至于两者往往是分开的。_

### metrics vs Tracing

metrics 是系统随时间变化的性能的数值。通常，metrics 映射到高级概念。metrics 的示例包括：CPU 使用率、内存使用率、网络带宽等。metrics 在程序运行时直接从应用程序或操作系统收集。

瞥见 Tracing 的强大功能后，自然会问：为什么要费心使用高级 metrics？为什么不直接使用 Trace 并在结果 Trace 上计算 metrics？在某些情况下，这确实是正确的方法。在本地和实验室情况下，使用 **基于 Trace 的 metrics**，即从 Trace 计算 metrics 而不是直接收集它们，是一种强大的方法。如果 metrics 裂化，很容易打开 Trace 以根本原因为什么会发生这种情况。

然而，基于 Trace 的 metrics 不是通用解决方案。在生产环境中运行时，Trace 数据本身较为重量级，因此难以做到 7×24 小时持续采集。使用 Trace 计算 metrics 可能需要兆字节数量级的数据，而直接 metrics 收集只需要字节数量级。

当你想了解系统随时间的性能但不想或不能承担采集 Trace 的成本时，使用 metrics 是正确的选择。在这些情况下，Trace 应作为 **根本原因分析** 工具。当你的 metrics 显示出现了问题时，可以有针对性地使用 Trace 以了解为什么会性能变差。

## Profiling 简介

**Profiling** 涉及对程序使用某种资源进行采样。单个连续采集会话称为 **Profile**。

每个样本收集函数调用堆栈（即代码行以及所有调用函数）。通常，此信息在整个 profile 中聚合。对于每个看到的调用堆栈，聚合给出该调用堆栈使用的资源百分比。到目前为止，最常见的 profiling 类型是
**memory profiling** 和 **CPU profiling**。

memory profiling 用于了解程序的哪些部分在堆上分配内存。profiler 通常 hook 到原生（C/C++/Rust 等）程序的 `malloc`（和 `free`）调用，以采样调用 `malloc` 的调用堆栈。还保留有关分配了多少字节的信息。CPU profiling 用于了解程序在哪里花费 CPU 时间。profiler 捕获一段时间内 CPU 上运行的调用堆栈。通常，这是定期完成的（例如，每 50 毫秒），但也可以在操作系统中发生某些事件时完成。

### Profiling 与 Tracing

比较 Profiling 和 Tracing 有两个主要问题：

1. 当我可以直接 Trace _所有内容_ 时，为什么要统计地 Profile 我的程序？
2. 当 Profile 给我使用最多资源的准确代码行时，为什么要使用 Tracing 来重建事件的 Timeline？

#### 何时使用 Profiling 而不是 Tracing

Tracing 不能可行地捕获极高频率事件的执行，例如每个函数调用。Profiling 工具填补了这个需求：通过采样，它们可以显著减少它们存储的信息量。Profiler 的统计性质很少成为问题;Profiler 的采样算法专门设计用于捕获高度代表真实资源使用的数据。

*插曲：存在一些非常专门的 Tracing 工具，可以捕获每个函数调用(例如，
[magic-trace](https://github.com/janestreet/magic-trace))，但它们每秒输出 *千兆字节*的数据，这使得它们除了调查微小的代码片段之外的任何事情都不切实际。它们通常也比通用 Tracing 工具有更高的开销。*

#### 何时使用 Tracing 而不是 Profiling

虽然 Profiler 给出了使用资源的调用堆栈，但它们缺乏关于为什么会发生这种情况的信息。例如，为什么函数 _foo()_ 如此频繁地调用 malloc？它们只说 _foo()_ 在 Y 次对 `malloc` 的调用中分配了 X 字节。Tracing 非常适合提供这种确切的上下文：应用程序插桩和低级内核事件一起提供了深入了解为什么最初运行代码。

NOTE: Perfetto 支持同时收集、profile 和可视化 Profiling 和 Tracing 数据，让你能够兼得两者优势！

## 下一步

现在你对 Tracing 和 Profiling 有了更好的了解，你可以使用 Perfetto 来：

- 采集你的应用程序和系统的 Trace 以了解其行为。
- 分析 Trace 以识别性能瓶颈。
- 可视化 Trace 以查看事件 Timeline。

要了解如何执行此操作，请转到我们的
[如何开始使用 Perfetto?](/docs/getting-started/start-using-perfetto.md)
页面。