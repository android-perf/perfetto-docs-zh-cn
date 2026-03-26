# 常见问题解答

## 如何从命令行在 UI 中打开 trace?

当从命令行收集 traces 时，打开 traces 的便捷方法是使用 [open\_trace\_in\_ui 脚本](/tools/open_trace_in_ui)。

可以按以下方式使用：

```sh
curl -OL https://github.com/google/perfetto/raw/main/tools/open_trace_in_ui
chmod +x open_trace_in_ui
./open_trace_in_ui -i /path/to/trace
```

如果你已经有 Perfetto 检出，则可以跳过前两个步骤。
从 Perfetto 根目录，运行：

```sh
tools/open_trace_in_ui -i /path/to/trace
```

## 为什么 Perfetto 不支持 \<某些冷门的 JSON 格式功能\>?

JSON trace 格式被视为遗留 trace 格式，并在尽力而为的基础上提供支持。虽然我们尽力保持与 chrome://tracing UI 和 [格式规范](https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU/preview#heading=h.nso4gcezn7n1）在如何解析和显示事件方面的兼容性，但这并不总是可能的。
对于在 Chrome 外部以编程方式生成并依赖 chrome://tracing 实现细节的 traces，尤其如此。

如果支持某个功能会引入不成比例的技术债务，我们通常会做出不支持该功能的选择。建议用户改为发出 [TrackEvent](/docs/instrumentation/track-events.md)，这是 Perfetto 的原生 trace 格式。请参阅[此指南](/docs/reference/synthetic-track-event.md)，了解如何使用 TrackEvent 表示常见的 JSON 事件。

## 为什么 JSON traces 中的重叠事件未正确显示？

Perfetto UI 和 trace processor 不支持重叠的 B/E/X 事件，以符合
[JSON 规范](https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU/preview#heading=h.nso4gcezn7n1)。
如规范中所述，仅允许事件完美嵌套。

建议用户改为发出
[TrackEvent](/docs/instrumentation/track-events.md)，这是 Perfetto 的原生 trace 格式。请参阅[此指南](/docs/reference/synthetic-track-event.md)，了解如何使用 TrackEvent 表示常见的 JSON 事件。

## 如何在不对我的程序进行插桩的情况下使用 Perfetto 工具？

一个常见问题是用户想使用 Perfetto profile 和可视化工具，但他们不想对他们的程序进行插桩。这可能是因为 Perfetto 不适合他们的用例，或者他们可能已经有一个现有的 tracing 系统。

对此的推荐方法是发出 Perfetto 的原生 TrackEvent proto 格式。参考指南可在
[此处](/docs/reference/synthetic-track-event.md）获得。


## 我的应用程序有多个进程。如何在一个 trace 中看到所有这些进程？

在"系统模式"中使用 [Tracing SDK](/docs/instrumentation/tracing-sdk.md#system-mode)。所有进程都将通过套接字连接到 `traced`，traced 将发出一个包含所有进程的 trace。
