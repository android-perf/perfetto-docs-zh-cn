# 使用 Perfetto 可视化外部 Trace 格式

在本指南中，你将了解：

- Perfetto 支持的不同外部 trace 格式。
- 如何在 Perfetto UI 中生成和可视化这些格式。
- 每种格式的限制以及何时使用它们。

Perfetto 能够打开和分析由各种外部工具和系统生成的 trace 文件，而不仅仅是其自己的原生 protobuf 格式。你可能已经拥有这些格式的 traces，如果：

- 你已经在使用其他 tracing 工具并积累了数据。
- Perfetto 的采集功能不适合你的数据收集需求，但你希望使用其分析工具。
- 你有自定义的时间戳数据，可以将其转换为 Perfetto 理解的外部格式之一（详见下文）。
  - 或者，你可能考虑将你的数据直接转换为 Perfetto 的[原生 TrackEvent protobuf 格式](/docs/reference/synthetic-track-event.md)，这可以提供更强大的功能和灵活性。

使用 Perfetto 检查这些外部 traces 的主要优势是其强大的 profile 和可视化能力：

- **Perfetto UI：** 一种通用的基于 Web 的 trace 查看器，旨在处理大型和复杂的 Timeline 数据，提供丰富的交互式分析。
- **Trace Processor：** 一个强大的基于 SQL 的引擎，允许对这些多样化格式的时间戳数据进行程序化查询和深入分析。

下面，我们详细介绍支持的格式，提供关于其典型用例的上下文，并概述将它们加载到 Perfetto 时期望的内容。

## Chrome JSON 格式

**描述：** Chrome JSON trace 格式由事件对象的 JSON 数组组成。每个对象代表单个 trace 事件，通常包括 `pid`(进程 ID)、`tid`(线程 ID)、`ts`(以微秒为单位的时间戳)、`ph`(阶段，指示事件类型，如 begin、end、instant、counter 等)、`name`(事件名称)、`cat`（类别）和 `args`（特定于事件的参数）等字段。此格式最初是为 Chrome 的 `about:tracing`（现在为 `chrome://tracing`）工具开发的。

**常见场景：** 虽然 Chromium 浏览器开发者现在主要使用 Perfetto 的原生 protobuf 格式进行 trace 收集，但在几种情况下仍会遇到 Chrome JSON 格式：

- **第三方工具和库：** 由于其悠久性和相对简单的结构，许多外部工具、自定义 C++ 插桩库和其他语言（如 Node.js、Python、Java）中的库采用了 Chrome JSON 格式来发出 trace 数据。它通常因为易于生成和作为已知格式的既定"稳定性"而被选择。
- **从 Chrome DevTools 导出：** 现代 Chrome DevTools 中的 "Performance" 面板仍然可以以这种 JSON 格式导出配置文件。
- **旧版 Traces：** 你可能拥有来自 Chrome 的旧版 traces，它们处于这种格式。

**Perfetto 支持：**

- **Perfetto UI：** Chrome JSON 文件可以直接在 Perfetto UI 中打开。UI 可视化常见事件类型，包括：
  - `B`(begin) 和 `E`(end) 事件作为 slices。
  - `X`(complete) 事件作为 slices。
  - `I`(instant) 事件作为 Timeline 上的单点。
  - `C`(counter) 事件作为 counter tracks。
  - `M`(metadata) 事件用于进程和线程名称等。
  - `s`、`t`、`f`(flow) 事件作为连接 slices 的箭头。
- **Trace Processor：** 这些事件被解析为 Perfetto 的标准 SQL 表（例如，`slice`、`track`、`process`、`thread`、`counter`、`args`）。这允许你使用 SQL 查询分析 Chrome JSON traces。
- **重要说明：**
  - Perfetto 旨在遵守 [Trace Event Format specification](https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU/preview)。它不会尝试复制旧版 `chrome://tracing` 工具的特定渲染怪癖或未记录行为，除非它们对基本 trace 理解至关重要。
  - Perfetto 对持续时间事件（`B` 和 `E` 对）强制执行严格嵌套。重叠的、非嵌套事件可能无法像在更宽松的旧版 `chrome://tracing` 查看器中那样被可视化或处理。有关更多详细信息，请参阅[关于重叠 JSON 事件的 FAQ](/docs/faq.md#why-are-overlapping-events-in-json-traces-not-displayed-correctly)。
  - 对 JSON 格式的某些不常见或高度特定功能的支持可能有限。请参阅[关于模糊 JSON 功能的 FAQ](/docs/faq.md#why-does-perfetto-not-support-some-obscure-json-format-feature)。

**如何生成：**

- **通过外部工具和库以编程方式：** 这是当今生成此格式最常见的方式。由于其既定性质和简单结构，各种不同语言的库和工具（例如，用于 Node.js、Python、Java、C++）可以生成 Chrome JSON 格式的 trace 文件。
- **从 Chrome DevTools 导出：** 基于 Chromium 的浏览器中的 "Performance" 面板允许你记录活动，然后使用 "Save profile..."（下载）选项获取 JSON 文件。
- **历史上从 `chrome://tracing`：** 旧版 Chrome 使用此界面保存 traces。

**外部资源：**

- **格式规范：** [Trace Event Format (Google Docs)](https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU/preview)
- **原始 `about:tracing` 工具上下文：** [The Trace Event Profiling Tool (Chromium Docs)](https://www.chromium.org/developers/how-tos/trace-event-profiling-tool/)

## {#firefox-json-format} Firefox Profiler JSON 格式

**描述：** Firefox Profiler JSON 格式主要用于 [Firefox Profiler](https://profiler.firefox.com/)，这是一个基于 Web 的性能 profiling 工具。虽然该格式可以描述各种类型的 Timeline 数据，包括"markers"(类似于 trace 事件)，但其主要优势以及 Perfetto 对它的主要兴趣在于表示 **CPU profiling 数据**，特别是采样调用栈。这使其成为可视化来自各种 profiling 源的火焰图和调用树的绝佳目标格式。

**常见场景：** Perfetto 用户遇到此格式的最常见原因是：

- **可视化 Linux `perf`(或 Android `simpleperf`)CPU profiles：** 开发者经常使用 Linux 上的 `perf record` 或 Android 上的 `simpleperf` 收集 CPU 样本。然后可以将这些原生 profiles 转换为 Firefox Profiler JSON 格式，以利用 `profiler.firefox.com` 等工具提供的交互式和用户友好的可视化，或者在这里，导入 Perfetto。
- **使用跨平台 profiling 工具：** 一些 profiling 工具和库旨在输出或将其数据转换为此格式，以便使用 Firefox Profiler UI 进行 profile。
- **分析来自 Firefox 的 profiles：** 对于 Perfetto 用户来说较少见，可能是在 Firefox 浏览器本身内直接捕获的 profiles。

**Perfetto 支持：**

- **Perfetto UI & Trace Processor：** Perfetto 为 Firefox Profiler JSON 格式提供 _部分支持_，重点关注 **CPU 采样数据**。
  - 当你打开 Firefox Profiler JSON 文件时，Perfetto 尝试解析调用栈、样本时间戳以及线程/进程信息。
  - 此数据被导入到标准的 Perfetto SQL 表中，如 `perf_sample`、`stack_profile_callsite`、`stack_profile_frame` 和 `stack_profile_mapping`。
  - 在 Perfetto UI 中，这允许将 CPU profiles 可视化为火焰图。
- **支持的格式变体：** Perfetto 支持 Firefox Profiler JSON 格式的两种变体：
  - **旧版格式：** 使用 `stringTable` 和带有 `schema` + `data` 数组的表（例如，`frameTable.schema` 和 `frameTable.data`）。这是历史上由 `perf script report gecko` 等工具生成的格式。
  - **预处理格式：** 使用 `stringArray` 和带有单独列数组的表（例如，`frameTable.func`、`funcTable.name`）。这是 Firefox Profiler 预处理输出使用的格式，由 `meta.preprocessedProfileVersion` 字段指示。
- **限制：**
  - Perfetto 通常 **不支持** Firefox Profiler "markers"(Timeline 事件，如 slices 或 instants)。
  - Firefox Profiler 内部数据表示或 UI 提示的其他高级功能（如自定义 track 颜色或丰富的浏览器特定元数据）通常不会被导入。
  - **将此格式加载到 Perfetto 时的主要期望应该是分析 CPU 调用栈样本。**

**如何生成：** 对于 Perfetto 用户最相关的生成路径涉及将 Linux `perf` 或 Android `simpleperf` 的原生 CPU profiles 进行转换。

<?tabs>

TAB: <code>perf</code> Linux 上的 profiles

1.  **使用 `perf record` 记录 profile：** 以 99Hz 采样 1 秒，使用 DWARF 调用图捕获特定命令/进程或系统范围的 CPU 样本，生成 `perf.data` 文件。

    ```bash
    # 示例：以 99Hz 采样 1 秒，使用 DWARF 调用图
    sudo perf record -F 99 -g --call-graph dwarf --output perf.data --  find ~ -name 'foo'
    ```

    有关详细命令选项，请参阅 `man perf-record`。确保二进制文件的调试符号可访问，以便正确进行符号化。

2.  **将 `perf.data` 转换为 Firefox Profiler JSON：** 使用 `gecko` 报告脚本与 `perf script`。

    ```bash
    sudo perf script report gecko --save-only my_linux_profile.json
    ```

    此命令处理 `perf.data` 文件并输出 `my_linux_profile.json`，格式与 Firefox Profiler 兼容。如果你的 `perf` 版本中 `report gecko` 不可用，请查阅发行版的文档以获取替代方案或额外的 `perf` 脚本包。

3. **在 ui.perfetto.dev 中打开此 trace**

    导航到 [ui.perfetto.dev](https://ui.perfetto.dev) 并将 `my_linux_profile.json` 文件上传到 UI。一旦 trace 打开，你应该能够选择单个 CPU 样本或包含 CPU 样本的时间范围，以获得该区域中所有样本的火焰图。

    这是一个示例效果图

    ![](/docs/images/perf-profile-in-ui.png)

TAB: Android 上的 <code>simpleperf</code> profiles

在 Android 上，`simpleperf` 用于 CPU profiling。可以从 Android 开源项目 (AOSP) 使用 git 直接下载必要的 Python 脚本（`app_profiler.py`、`gecko_profile_generator.py`）。你还需要 NDK。

1.  **下载 `simpleperf` 脚本：**
    ```bash
    git clone https://android.googlesource.com/platform/system/extras --depth=1
    ```

    克隆后，脚本将位于 `extras/simpleperf/scripts` 子目录中。
    注意:此方法提供后处理脚本，但你还需要一个兼容的 `simpleperf` 二进制文件来记录 profile。此二进制文件通常在你的 Android 设备上可用，`app_profiler.py` 会自动找到它。

2.  **使用 `app_profiler.py` 记录 profile：** 此脚本在设备上调用记录，并通过 ADB 将 profile 拉到主机机器。

    ```bash
    # 替换 <your.app.package.name>
    python extras/simpleperf/scripts/app_profiler.py \
        --app <your.app.package.name> \
        -r "-g --duration 10" \
        -o perf.data
    ```

    - 此命令使用 DWARF 调用图（`-g`）对指定应用进行 10 秒的 profiling。
    - 它写入 `perf.data` 和一个 `binary_cache/`(用于符号)。
    - 有关更多详细信息，请参阅 [simpleperf 文档](https://android.googlesource.com/platform/system/extras/+/refs/heads/main/simpleperf/doc/README.md))。

3.  **将 `simpleperf` 数据转换为 Firefox Profiler JSON：** 使用来自同一 AOSP checkout 的 `gecko_profile_generator.py` 脚本。
      ```bash
      python extras/simpleperf/scripts/gecko_profile_generator.py \
          --symfs binary_cache \
          -i perf.data \
          > gecko_profile.json
      ```

    - 这将使用 `binary_cache` 中的符号将 `simpleperf` 数据转换为 Firefox Profiler JSON 格式。

4. **在 ui.perfetto.dev 中打开此 trace**
    导航到 [ui.perfetto.dev](https://ui.perfetto.dev) 并将 `gecko_profile.json` 文件上传到 UI。一旦 trace 打开，你应该能够选择单个 CPU 样本或包含 CPU 样本的时间范围，以获得该区域中所有样本的火焰图。

    这是一个示例效果图

    ![](/docs/images/perf-profile-in-ui.png)

</tabs?>

其他方法(对于 Perfetto 导入场景较少见)：

- **从 Firefox 浏览器：** 使用内置的 profiler（例如，通过 `about:profiling` 或开发者工具）并保存 profile。

**外部资源：**

- **Firefox Profiler 工具：** [profiler.firefox.com](https://profiler.firefox.com/)
- **格式文档(可能比较技术性)：**
  - [Gecko Profile Format (GitHub)](https://github.com/firefox-devtools/profiler/blob/main/docs-developer/gecko-profile-format.md)
  - [Processed Profile Format (GitHub)](https://github.com/firefox-devtools/profiler/blob/main/docs-developer/processed-profile-format.md)
- **Linux `perf` 工具：** [perf Wiki](https://perf.wiki.kernel.org/index.php/Main_Page), [man page](https://man7.org/linux/man-pages/man1/perf.1.html)
- **Android `simpleperf` 工具：** [Simpleperf usage](https://android.googlesource.com/platform/system/extras/+/refs/heads/main/simpleperf/doc/README.md)

## Android systrace 格式

**描述：** Android Systrace 是 Android 的**旧版**系统级 tracing 工具，主要在 Android 9 (Pie) 引入 Perfetto 之前使用。它通过 `ftrace` 捕获内核活动（例如，CPU 调度、I/O）并通过 ATrace 捕获用户空间注释（例如，`android.os.Trace`）。Systrace 通常生成一个交互式 HTML 文件，将 trace 数据嵌入到基于文本的格式中。

**常见场景(主要是旧版)：** 你通常只会在处理**旧数据或旧工作流**时遇到 Android Systrace 格式，例如：

- 分析在 Android 9 (Pie) 之前的 Android 系统上生成的 traces。
- 使用 `systrace.py` 命令行工具采集的历史 traces。
- 检查来自非常旧版本的 Android Studio profiler 的 traces。

**对于 Android 上的任何当前或新 tracing(9 Pie 及更新版本)，Perfetto 是标准且强烈推荐的工具。**

**Perfetto 支持：**

- **Perfetto UI：** Perfetto 可以直接打开 Android Systrace HTML 文件，解析嵌入的 ftrace 和 ATrace 数据进行可视化。这主要是为了与历史 traces 兼容。
- **Trace Processor：** Trace Processor 还支持解析 Systrace 报告中找到的原始文本 ftrace 数据。此数据被导入到标准的 Perfetto SQL 表中（例如，`slice`、`sched_slice`、`ftrace_event`），使其可通过 SQL 查询。
- **重要说明：** Perfetto 对 Systrace 的支持是为了**向后兼容。** Systrace 是现代 Android（Android 9 Pie 及更新版本）上已弃用的 trace 收集工具。Perfetto 已经取代它，提供更多数据源、更低开销和更高级的分析能力。**新的 tracing 工作应专门使用 Perfetto。**

**如何生成(旧版方法)：** 以下方法描述了 Systrace 文件的历史创建方式，为了在处理旧 traces 时提供上下文。**这些方法已弃用，不应在 Android 9 (Pie) 或更新版本上用于新的 trace 收集。**

- **使用 `systrace.py`(已弃用)：** 历史上，这些 traces 是使用 Android SDK Platform Tools 中的 `systrace.py` 脚本生成的。示例命令可能如下所示：
  ```bash
  # python <sdk>/platform-tools/systrace/systrace.py -a <your.app.package.name> -o mytrace.html sched freq idle am wm
  ```
- **Android Studio(旧版本 - 已弃用)：** Android Studio 的早期版本的 profiler 使用 Systrace。现代 Android Studio 现在使用 Perfetto。

**外部资源：**

- **Systrace 命令行参考(旧版)：** [developer.android.com/topic/performance/tracing/command-line](https://developer.android.com/topic/performance/tracing/command-line) (此页面还强调 Perfetto 取代 Android 9+ 的 Systrace)
- **了解 ATrace(用户空间注释 - 与 Systrace 中的数据相关)：** [ATrace: Android 系统和应用 trace 事件](/docs/data-sources/atrace.md)

## Perf 文本格式(来自 `perf script`)

**描述：** "Perf 文本格式"通常指 Linux 上 `perf script` 命令生成的人类可读的文本输出。此命令处理 `perf.data` 文件（由 `perf record` 创建）并按时间顺序打印记录的事件日志。输出通过 `perf script` 选项高度可配置，但通常包括 CPU 样本及其调用栈、时间戳、进程/线程标识符、CPU 编号和事件名称。

**常见场景：** 此格式通常用于：

- 手动检查 `perf.data` 文件的内容以进行快速分析或调试。
- 作为各种第三方脚本和工具的中间输入，例如 Brendan Gregg 的 [FlameGraph](https://github.com/brendangregg/FlameGraph) 脚本，它解析 `perf script` 输出来生成火焰图。
- 处理来自旧 profiling 会话或自动化系统的现有 `perf script` 输出。

**Perfetto 支持：**

- **Perfetto UI & Trace Processor：** Perfetto 的 Trace Processor 可以解析 `perf script` 生成的文本输出。
  - 此导入器的主要重点是 **CPU 样本及其关联的调用栈**。
  - 当解析此类数据时，它会填充 Perfetto 的标准 profiling 表（例如，`cpu_profile_stack_sample_table` 用于样本，`stack_profile_callsite`、`stack_profile_frame`、`stack_profile_mapping` 用于调用栈信息）。
  - 这允许将 `perf script` 输出的 CPU profile 数据在 Perfetto UI 中可视化为火焰图，并使用 SQL 进行查询。
- **限制：**
  - `perf script` 的输出格式根据传递的参数（例如，使用 `-F` 标志）非常灵活。Perfetto 的解析器可能期望样本的常见或默认输出结构。高度定制或不寻常的 `perf script` 文本输出可能无法正确或完全解析。
  - 对于 `perf script` 可能输出的其他类型事件(除了带调用栈的 CPU 样本之外)(例如，如果使用 `-D` 的原始 tracepoints，或其他事件类型)，直接作为 "Perf 文本格式"导入时的支持可能有限。
  - 为了从 `perf.data` 稳健地可视化 CPU profiles，考虑将 `perf.data` 转换为 [Firefox Profiler JSON 格式](#firefox-profiler-json-format)，Perfetto 也支持样本数据。

**如何生成：**

1.  **使用 `perf record` 记录 profile：** 首先，使用 `perf record` 捕获 profiling 数据。这会创建一个 `perf.data` 文件。

    ```bash
    # 示例：以 99Hz 采样 1 秒，使用 DWARF 调用图
    sudo perf record -F 99 -g --call-graph dwarf --output perf.data --  find ~ -name 'foo'
    ```

    有关详细命令选项，请参阅 `man perf-record`。确保二进制文件的调试符号可访问，以便 `perf script` 正确进行符号化。

2.  **使用 `perf script` 生成文本输出：** 处理 `perf.data` 文件以生成文本输出。

    ```bash
    # 默认输出
    sudo perf script -i perf.data > my_perf_output.txt
    ```

    对于通常对其他工具有用（以及可能对 Perfetto 的解析器有用，如果它查找特定字段）的更详细输出，你可以指定字段：

    ```bash
    perf script -i perf.data -F comm,pid,tid,cpu,time,event,ip,sym,dso,trace > my_perf_output_detailed.txt
    ```

    有关其广泛的格式化选项，请参阅 `man perf-script`。

3.  **在 ui.perfetto.dev 中打开此 trace**

    导航到 [ui.perfetto.dev](https://ui.perfetto.dev) 并将 `my_perf_output.txt` 文件上传到 UI。一旦 trace 打开，你应该能够选择单个 CPU 样本或包含 CPU 样本的时间范围，以获得该区域中所有样本的火焰图。

    这是一个示例效果图

    ![](/docs/images/perf-profile-in-ui.png)

**外部资源：**

- **`perf-script` man page：** `man perf-script` (或在线搜索，例如 [perf-script Linux man page](https://man7.org/linux/man-pages/man1/perf-script.1.html))
- **`perf` 工具一般信息：** [perf Wiki (kernel.org)](https://perf.wiki.kernel.org/index.php/Main_Page)
- **Brendan Gregg 的 `perf` 示例：** [Brendan Gregg's perf page](https://www.brendangregg.com/perf.html) (包含许多 `perf script` 使用示例，特别是用于火焰图)

## Simpleperf proto 格式

**描述：** Simpleperf 是 Android 基于 Linux perf 框架构建的 profiling 工具。"Simpleperf proto 格式"指 `simpleperf report-sample --protobuf` 命令生成的二进制 protobuf 格式。此格式包含 CPU 样本及调用栈、进程/线程信息、文件映射和符号表，以紧凑的二进制表示。Android Studio 的 CPU profiler 在显示 simpleperf profiles 时在内部使用此格式。

**常见场景：** 此格式用于：

- 使用 simpleperf 对 Android 应用和系统服务进行 profiling
- 分析 Android 设备上的 CPU 性能
- 捕获原生代码和托管代码的带符号信息的栈样本
- 处理由 Android Studio 的 CPU profiler 收集的 profiles(它将 simpleperf 数据转换为此 proto 格式)

**Perfetto 支持：**

- **Perfetto UI & Trace Processor：** Perfetto 的 Trace Processor 可以直接解析 simpleperf 的 protobuf 格式。
  - 导入器处理 **CPU 样本及调用栈**、文件映射和符号表
  - 样本被导入到 `cpu_profile_stack_sample` 表中，包含完整的调用栈信息
  - 调用栈存储在标准的 profiling 表中(`stack_profile_callsite`、`stack_profile_frame`、`stack_profile_mapping`)
  - 线程和进程信息被提取并存储在进程/线程表中
  - 这允许在 Perfetto UI 中将 simpleperf profiles 可视化为火焰图，并使用 SQL 进行查询
- **限制：**
  - simpleperf 格式中的上下文切换记录尚未导入
  - 事件类型元数据已存储但尚未用于过滤或分类

**如何生成：**

1.  **使用 simpleperf 记录 profile：** 首先，使用 `simpleperf record` 捕获 profiling 数据。

    ```bash
    # 示例：使用调用图对 Android 应用进行 profiling
    adb shell simpleperf record -p <pid> -g --duration 10
    adb pull /data/local/tmp/perf.data simpleperf.data
    ```

    有关详细命令选项，请参阅 `simpleperf record --help`。

2.  **转换为 proto 格式：** 使用 `simpleperf report-sample` 将原始记录转换为 protobuf 格式：

    ```bash
    # 使用调用链转换为 proto 格式
    simpleperf report-sample --protobuf --show-callchain \
      -i simpleperf.data -o simpleperf.proto

    # 可选提供符号目录以获得更好的符号化
    simpleperf report-sample --protobuf --show-callchain \
      -i simpleperf.data -o simpleperf.proto \
      --symdir /path/to/symbols
    ```

    `--show-callchain` 标志是必需的，以在输出中包含调用栈信息。

3.  **在 ui.perfetto.dev 中打开**

    导航到 [ui.perfetto.dev](https://ui.perfetto.dev) 并上传 `simpleperf.proto` 文件。trace 将被导入，你可以在 UI 中选择时间范围来查看 CPU 样本的火焰图。

## Linux ftrace 文本格式

**描述：** Linux ftrace 文本格式是 Linux 内核 `ftrace` tracing 基础设施生成的原始、人类可读的输出。此基于文本的格式中的每一行通常代表单个 trace 事件，并遵循常见结构：`TASK-PID CPU# [MARKERS] TIMESTAMP FUNCTION --- ARGS`。例如，`sched_switch` 事件可能如下所示：`bash-1234 [002] ...1 5075.958079: sched_switch: prev_comm=bash prev_pid=1234 prev_prio=120 prev_state=R ==> next_comm=trace-cmd next_pid=5678 next_prio=120`。此格式可能非常详细，但它是 ftrace 运行方式的基础，并通过 `tracefs` 文件系统公开（通常挂载在 `/sys/kernel/tracing`）。

**常见场景：** 你可能会在以下情况下遇到或使用此格式：

- 分析使用 `trace-cmd` 工具捕获的 ftrace 数据，特别是使用 `trace-cmd report` 或 `trace-cmd stream` 等命令。
- 直接从 `tracefs` 中的 ftrace 缓冲区文件读取，例如 `/sys/kernel/tracing/trace`。
- 处理较旧的 Linux 内核调试工作流或生成此文本输出的自定义脚本。
- 检查 Android Systrace HTML 文件中嵌入的原始数据，因为它们使用这种底层格式。

**Perfetto 支持：** Perfetto 对 ftrace 文本格式的支持主要是为了**遗留兼容性，并以尽最大努力的方式维护。**

- **Perfetto UI：** Perfetto UI 可以直接打开 ftrace 文本日志文件（通常带有 `.txt` 或 `.ftrace` 扩展名）。它通过解析文本行来可视化已知的事件类型。例如：
  - `sched_switch` 事件显示为 CPU tracks 上的调度 slices。
  - 匹配 ATrace 格式的 `print` 事件显示为用户空间 slices。
  - 文本文件中存在的其他 ftrace 事件如果无法映射到识别的 Perfetto UI 元素，则可能无法可视化。
- **Trace Processor：** 解析 ftrace 文本日志时，Perfetto 的 Trace Processor 将：
  - 将识别的事件（例如，`sched_switch`、`sched_waking`、`cpu_frequency`、atrace 兼容的 `print` 事件）解析到其对应的结构化 SQL 表中（例如，`sched_slice`、`slice`、`counter`）。
  - **与 Perfetto 的原生 ftrace protobuf 摄取不同，文本 ftrace 文件中未识别或通用的 ftrace 事件通常不会填充到广泛的 `ftrace_event` 全捕获表中。** 支持通常限于具有用于创建结构化表的特定解析器的事件。
- **建议：** 对于在 Perfetto 可用系统上的新 tracing 活动（特别是 Android 9+ 或安装了 Perfetto 的 Linux 系统），**强烈建议使用 Perfetto 的原生 ftrace 数据源。** Perfetto 的直接收集将 ftrace 数据记录到其自己的高效二进制 protobuf 格式中，提供更好的性能、更丰富的功能（包括将通用 ftrace 事件解析为 protobuf `GenericFtraceEvent` 类型）和更稳健的支持。导入文本格式应保留用于分析预先存在的日志。

**如何生成(关于现有日志的上下文)：** 这些方法描述了如何使用 `tracefs`（通常挂载在 `/sys/kernel/tracing`）创建 ftrace 文本日志。**对于新的 tracing，首选直接使用 Perfetto 的 ftrace 数据源。**

- **使用 `trace-cmd`：** `trace-cmd` 是 ftrace 的用户空间前端。

  ```bash
  # 示例：记录调度和系统调用事件
  sudo trace-cmd record -e sched -e syscalls
  # 停止后(Ctrl-C 或按持续时间)，生成文本报告：
  trace-cmd report > my_ftrace_log.txt
  ```

  或者进行实时流式传输：

  ```bash
  sudo trace-cmd stream -e sched:sched_waking -e irq:irq_handler_entry > my_ftrace_log.txt
  ```

  (使用 Ctrl-C 停止)。有关更多选项，请参阅 `man trace-cmd`。

- **直接从 `tracefs`(更手动)：** 你可以通过 `/sys/kernel/tracing/` 接口与 ftrace 交互。
  ```bash
  # 示例：启用 sched_switch 和 printk 事件
  sudo sh -c 'echo sched:sched_switch print > /sys/kernel/tracing/set_event'
  # 启用 tracing
  sudo sh -c 'echo 1 > /sys/kernel/tracing/tracing_on'
  # ... 允许系统运行或执行你想要 trace 的操作 ...
  # 捕获 trace 缓冲区
  sudo cat /sys/kernel/tracing/trace > my_ftrace_log.txt
  # 禁用 tracing 并清除事件
  sudo sh -c 'echo 0 > /sys/kernel/tracing/tracing_on'
  sudo sh -c 'echo > /sys/kernel/tracing/set_event'   # 清除事件
  ```

**外部资源：**

- **官方 Ftrace 文档：** [Ftrace - Function Tracing (kernel.org)](https://www.kernel.org/doc/html/latest/trace/ftrace.html) (主要来源：Linux 内核源代码中的 `Documentation/trace/ftrace.txt` 或 `ftrace.rst`)
- **`trace-cmd` Man Page：** `man trace-cmd` (或在线查找，例如在 [Arch Linux man pages](https://man.archlinux.org/man/trace-cmd.1.en))
- **Tracefs 文档：** [The Tracefs Pseudo Filesystem (kernel.org)](https://www.kernel.org/doc/html/latest/trace/tracefs.html)

## ART method tracing 格式

**描述：** Android Runtime (ART) method tracing 格式（通常在 `.trace` 文件中找到）是 Android 特定的二进制格式。它捕获关于 Android 应用内 Java 和 Kotlin 方法执行的详细信息，本质上是记录每个被调用方法的进入和退出点。这允许对应用的运行时行为进行细粒度的方法级分析。

**常见场景：** 此格式通常在以下情况下使用：

- 需要深入分析 Android 应用中特定 Java 或 Kotlin 代码路径的性能，以识别性能瓶颈或理解复杂的调用序列。
- 分析由 Android Studio 的 CPU Profiler 生成的 traces，特别是使用 "Trace Java Methods" 记录配置时。
- 处理使用 `android.os.Debug.startMethodTracing()` API 从应用内部以编程方式创建的 traces。

**Perfetto 支持：**

- **Perfetto UI：** `.trace` 文件可以直接在 Perfetto UI 中打开。方法调用通常可视化为火焰图，提供一种直观的方式来查看时间花在哪里。它们还显示为每个线程 Timeline 上的嵌套 slices。
- **Trace Processor：** Perfetto 的 Trace Processor 内置支持解析 ART method trace 文件（`.trace`）。
  - 每个方法调用（进入和退出）作为不同的 slice 导入到 `slice` 表中。这些 slices 与它们各自的线程和进程相关联。
  - 这支持基于 SQL 的方法执行时间、调用计数、栈深度以及不同方法之间关系的详细分析。
- **关于开销的重要说明：** ART method tracing 由于其对每个方法调用进行插桩的性质，可能会对被分析的应用引入显著的性能开销。这种开销可能会改变你试图测量的行为。对于 Java/Kotlin 代码的侵入性较小的 CPU profiling，考虑使用 Android Studio 的 "Sample Java Methods" 选项或 Perfetto 的系统级调用栈采样功能，尽管这些提供统计数据而不是所有方法调用的精确日志。

**如何生成：**

- **Android Studio CPU Profiler：**
  1.  打开 Android Studio Profiler(View > Tool Windows > Profiler)。
  2.  选择你的设备和要分析的应用进程。
  3.  在 CPU profiler 部分，从下拉菜单中选择 "Trace Java Methods" 记录配置。
  4.  点击 "Record"，在应用中执行要分析的操作，然后点击 "Stop"。
  5.  然后可以从 Android Studio profiler 界面导出收集的 `.trace` 文件，以便在 Perfetto 中使用。
- **在应用内部以编程方式：** 你可以使用 `android.os.Debug` 类来插桩应用的 Java/Kotlin 代码以开始和停止 method tracing：

  ```java
  import android.os.Debug;
  // ...
  // 在你的应用代码中：
  // 开始 tracing：
  // Debug.startMethodTracing("myAppTraceName");
  // .trace 文件通常会保存到以下位置：
  // /sdcard/Android/data/<your_app_package_name>/files/myAppTraceName.trace
  // 或 /data/data/<your_app_package_name>/files/myAppTraceName.trace，具体取决于 Android 版本和权限。

  // ... 执行你要分析的代码 ...

  // 停止 tracing：
  // Debug.stopMethodTracing();
  ```

  停止后，你需要使用 ADB 从设备拉取生成的 `.trace` 文件（例如，`adb pull /sdcard/Android/data/<your_app_package_name>/files/myAppTraceName.trace .`）。确切的路径可能有所不同，因此请检查应用的特定文件存储位置。

**外部资源：**

- **Android 开发者 - `Debug` 类文档：** [developer.android.com/reference/android/os/Debug](https://developer.android.com/reference/android/os/Debug) (请参阅 `startMethodTracing()` 和 `stopMethodTracing()`)
- **Android 开发者 - 使用 CPU Profiler 检查 CPU 活动：** [developer.android.com/studio/profile/cpu-profiler](https://developer.android.com/studio/profile/cpu-profiler) (提供 "Trace Java Methods" 的详细信息)

## macOS Instruments 格式(XML 导出)

**描述：** Apple 的 Instruments 工具是 Xcode 的一部分，用于 macOS 和 iOS 的性能分析。虽然 Instruments 将其完整数据保存在专有的 `.trace` 包格式中，但 Perfetto 的支持专注于可以从这些 Instruments traces 导出的 **XML 格式**。此 XML 导出主要用于提取 CPU profiling 数据（栈样本）。

**常见场景：** 此导入路径在以下情况下相关：

- 你拥有使用 Apple Instruments 收集的 CPU 性能数据（例如，来自 Time Profiler instrument）。
- 你希望将此 CPU 栈样本数据可视化为火焰图或使用 Perfetto 的工具进行 profile。

**Perfetto 支持：**

- **Perfetto UI & Trace Processor：** Perfetto 可以解析从 macOS Instruments trace 导出的 XML 文件。
  - 此导入的主要重点是 **CPU 栈样本**。
  - 诸如调用栈、样本时间戳和线程信息等数据被提取并加载到 Perfetto 的 profiling 表中，特别是 `cpu_profile_stack_sample` 用于样本本身，`stack_profile_callsite`、`stack_profile_frame`、`stack_profile_mapping` 用于调用栈信息。
  - 这允许在 Perfetto UI 中将 CPU profile 可视化为火焰图，并允许对样本数据进行基于 SQL 的查询。
- **限制：**
  - 支持主要针对来自 XML 导出的 CPU 栈样本数据。
  - Instruments 中各种工具的其他丰富数据类型或特定功能（例如，详细的内存分配、自定义 os_signpost 数据，如果不在 XML 的兼容部分中）可能不受支持或通过此 XML 导入路径完全表示。

**如何生成：** Traces 最初使用 Xcode 中的 Instruments 应用程序或 `xctrace` 命令行实用程序收集，生成 `.trace` 包。Perfetto 摄取的 XML 文件是从此类 trace 导出的。(在 Instruments 工具本身中导出到此 XML 格式的具体步骤需要遵循；Perfetto 然后消费生成的 XML 文件)。

**外部资源：**

- **Apple 开发者 - Instruments：** 有关 Instruments 可以做什么的一般信息，请参阅官方 [Instruments User Guide](https://developer.apple.com/library/archive/documentation/DeveloperTools/Conceptual/InstrumentsUserGuide/) 或在 [developer.apple.com](https://developer.apple.com) 上搜索当前的 Instruments 文档。

## Ninja logs 格式(`.ninja_log`)

**描述：** Ninja 构建系统，以其速度和在 Chromium 和 Android 等项目中的使用而闻名，生成一个通常名为 `.ninja_log` 的日志文件。此文件是一个制表符分隔的文本文件，记录关于构建过程中执行的每个命令（构建步骤）的元数据。每个条目的关键信息包括开始时间（毫秒）、结束时间（毫秒）、restat mtime(毫秒)、构建步骤的主要输出文件路径以及命令本身的哈希值。该格式是版本化的，新版本偶尔添加字段。

**常见场景：** 此格式在以下情况下使用：

- 分析使用 Ninja 构建系统的软件构建的性能。
- 识别哪些构建步骤耗时最长，了解构建中的并行程度，以及诊断减慢编译或链接速度的潜在瓶颈。
- 随时间可视化构建过程。

**Perfetto 支持：**

- **Perfetto UI & Trace Processor：** Perfetto 的 Trace Processor 可以解析 `.ninja_log` 文件。
  - `.ninja_log` 中记录的每个构建步骤通常作为不同的 slice 导入到 `slice` 表中。
  - 为了在 Timeline 上可视化这些构建步骤，Perfetto 通常会合成进程和线程信息。例如，所有构建步骤可能在单个 "Ninja Build" 进程下分组，可能会为每个唯一的输出文件路径创建单独的 tracks，或基于其他启发式方法来表示并发性。
  - 时间戳（开始和结束时间）从毫秒转换为纳秒以与 Perfetto 保持一致。
  - 这允许在 Perfetto UI 中可视化构建过程，显示各种编译、链接和其他构建任务的持续时间和并发性，这对于理解构建的临界路径非常有帮助。
- **限制：** `.ninja_log` 仅记录已完成的命令。它不会直接在其每步日志格式中提供关于依赖项的信息，尽管有时可以通过分析输出文件的序列和时间来推断。

**如何生成：**

- **由 Ninja 自动生成：** Ninja 构建系统每次运行构建时都会自动创建并增量更新 `.ninja_log` 文件，位于构建输出目录的根目录中（例如，`out/Default/`、`build/` 等）。
- 通常不需要特殊标志来启用 `.ninja_log` 的生成，因为它是构建审计和 `ninja -t recompact` 使用的标准功能。

**外部资源：**

- **Ninja 构建系统手册 - 日志文件：** [ninja-build.org/manual.html#\_log_file](https://ninja-build.org/manual.html#_log_file)
- **Ninja 构建系统主页：** [ninja-build.org](https://ninja-build.org/)

## {#logcat-format} Android logcat 文本格式

**描述：** Android logcat 是用于访问来自 Android 系统级日志服务 `logd` 的消息的命令行工具。`adb logcat` 的文本输出是 Perfetto 可以导入的。此输出可以根据指定的格式化选项（例如，通过 `adb logcat -v <format>`）而有很大差异，但通常包括时间戳、日志优先级（Verbose、Debug、Info、Warn、Error、Fatal/Assert）、标识日志来源的 tag、进程 ID（PID）、通常是线程 ID（TID）以及日志消息本身。

**常见场景：** 你可能会在以下情况下处理文本 logcat 文件：

- 使用其文本日志输出执行 Android 应用或系统服务的传统调试。
- 分析先前从 `adb logcat` 会话保存的日志文件。
- 从 Android bug 报告（其中 logcat 数据嵌入在 `bugreport.txt` 中或作为单独文件）中提取 logcat 信息。

**Perfetto 支持：**

- **Perfetto UI & Trace Processor：** Perfetto 的 Trace Processor 可以解析文本 logcat 文件。
  - 导入的日志消息被填充到 `android_logs` SQL 表中。这与 Perfetto 通过其 [Android Log 数据源]（/docs/data-sources/android-log.md）本机收集 logcat 数据时使用的表相同。
  - 在 Perfetto UI 中，这些日志出现在 "Android Logs" 面板中，按时间顺序显示并可以过滤。这允许将日志消息与主 Timeline 上的其他 trace 事件相关联。
- **支持的格式：** Perfetto 的解析器设计用于处理常见的 `adb logcat` 输出格式，对 `logcat -v long` 和 `logcat -v threadtime` 有很好的支持。其他更奇特或高度定制的 logcat 格式可能无法完全解析。

**如何生成文本 Logcat 文件：**

- **使用 `adb logcat`：** 主要方法是通过 `adb logcat` 命令，将其输出重定向到文件。
  - 转储日志缓冲区的当前内容然后退出(对于快照很有用)：
    ```bash
    # 以 'long' 格式转储日志
    adb logcat -d -v long > logcat_dump_long.txt
    # 以 'threadtime' 格式转储日志(时间戳、PID、TID、优先级、tag、消息)
    adb logcat -d -v threadtime > logcat_dump_threadtime.txt
    ```
  - 将实时日志流式传输到文件(按 Ctrl-C 停止)：
    ```bash
    adb logcat -v long > logcat_stream_long.txt
    # 或者，对于更适合解析的流式格式：
    adb logcat -v threadtime > logcat_stream_threadtime.txt
    ```
- **来自 Android Bug 报告：** Logcat 数据是 `adb bugreport` 生成的 bug 报告的标准组件。你通常可以在主 `bugreport.txt` 文件中找到 logcat 输出，或作为 bug 报告存档中的单独日志文件。

**外部资源：**

- **`logcat` 命令行工具(官方 Android 文档)：** [developer.android.com/studio/command-line/logcat](https://developer.android.com/studio/command-line/logcat)
- **读取和写入日志(概述)：** [developer.android.com/studio/debug/am-logcat](https://developer.android.com/studio/debug/am-logcat)

## {#bugreport-format} Android bugreport zip 格式(.zip)

**描述：** Android bugreport 是由 Android 设备生成的 `.zip` 存档，包含特定时间点来自 Android 设备的全面诊断信息快照。此存档捆绑了各种日志（如 logcat）、系统属性、进程信息、ANR 和崩溃的堆栈跟踪，以及重要的是系统 trace(通常是在现代 Android 版本上的 Perfetto trace)。它还包含详细的 `dumpstate` 输出，其中包括板级信息和特定服务转储，如 `batterystats`。

**常见场景：** Bugreport zip 文件主要用于：

- 在报告 bug 或分析 Android 设备上的复杂问题时捕获广泛的诊断数据，无论是用于应用开发还是平台级调试。
- 向 Google、设备制造商 (OEM) 或其他开发者提供详细的系统状态信息以帮助诊断问题。

**Perfetto 支持：**

- **Perfetto UI & Trace Processor：** Perfetto 可以直接打开和处理 Android bugreport `.zip` 文件。
  - 当加载 bugreport zip 时，Perfetto 自动：
    - 在已知位置（例如，`FS/data/misc/perfetto-traces/`、`proto/perfetto-trace.gz`）扫描 **Perfetto trace 文件**(`.pftrace`、`.perfetto-trace`)。加载找到的主要 Perfetto trace 以进行可视化和 SQL 查询。
    - 将主要的 **`dumpstate` 板级信息**（通常在 `bugreport-*.txt` 或 `dumpstate_board.txt` 等文件中找到）解析到 `dumpstate` SQL 表中。此表包括系统属性、内核版本、构建指纹和其他硬件/软件详细信息。
    - 将 `batterystats` 部分的详细 **电池统计信息**提取到 `battery_stats` SQL 表中。这提供有关电池电量、充电状态和随时间的电源事件的信息。
  - 这种集成方法允许用户在统一的 Perfetto 环境中分析系统 trace，以及来自 bugreport 的关键系统状态（来自 `dumpstate`）和电池信息（来自 `batterystats`），无需手动提取这些组件。
  - **注意：** Perfetto 处理 bugreport 时的重点是它自己的原生 trace 格式和 `dumpstate` 的特定结构化部分，如 `batterystats`。它通常 **不会** 尝试导入或解析可能存在于旧 bugreport 中的旧版 Systrace 文件（`systrace.html` 或 `systrace.txt`）。要分析这些，你通常会手动提取它们并按照 [Android systrace 格式]（#android-systrace-format）部分打开它们。

**如何生成：**

- **使用 `adb bugreport`(从连接到设备的计算机)：** 这是开发者最常用的方法。

  ```bash
  adb bugreport ./my_bugreport_filename.zip
  ```

  此命令指示连接的 Android 设备生成 bug 报告，并将其作为 `.zip` 文件保存到计算机上的指定路径。

- **从 Android 设备上的开发者选项：**
  1.  在 Android 设备上启用开发者选项（通常通过转到设置 > 关于手机并点击 "Build number" 七次）。
  2.  导航到设置 > 系统 > 开发者选项。
  3.  找到并点击 "Bug report" 或 "Take bug report" 选项。确切的措辞和子菜单可能因 Android 版本和设备制造商而略有不同。
  4.  你可能会被提示选择 bug 报告的类型（例如，"Interactive report" 以在捕获期间获取更多详细信息，或 "Full report" 以获取最全面的数据）。
  5.  生成 bug 报告后（可能需要几分钟），会出现通知。点击此通知通常允许你共享 `.zip` 文件（例如，通过电子邮件、文件共享应用或将其保存到云存储）。

**外部资源：**

- **捕获和读取 bug 报告(官方 Android 文档)：** [developer.android.com/studio/debug/bug-report](https://developer.android.com/studio/debug/bug-report)

## Fuchsia tracing 格式(.fxt)

**描述：** Fuchsia trace 格式（通常在 `.fxt` 文件中找到）是 Fuchsia 操作系统使用的二进制格式。它设计用于从用户空间组件和 Zircon 内核进行高性能、低开销的诊断信息记录。该格式具有紧凑、内存对齐的记录，并且是可扩展的，trace 数据通常直接写入 Zircon 虚拟机对象 (VMO) 以提高效率。

**常见场景：** 此格式主要在以下情况下遇到：

- 处理在 Fuchsia OS 设备或模拟器上采集的 traces，用于调试系统行为或分析性能。
- 在某些特殊的、非 Fuchsia 用例中，需要一种二进制、紧凑且可流式传输的格式，与 Chrome JSON 的事件结构有相似之处。
  - 但是，对于 Fuchsia 生态系统之外的此类自定义 tracing 需求，通常建议生成 Perfetto 的[原生 TrackEvent protobuf 格式](/docs/reference/synthetic-track-event.md)，因为它功能更丰富且 Perfetto 工具的支持更好。

**Perfetto 支持：**

- **Perfetto UI：** `.fxt` 文件可以直接在 Perfetto UI 中打开进行可视化。UI 可以显示各种 Fuchsia 特定的事件和系统活动。
- **Trace Processor：** Perfetto 的 Trace Processor 支持解析 Fuchsia 二进制格式。这允许将 trace 数据，包括事件、调度记录和日志，导入到标准的 Perfetto SQL 表中，使其可用于基于查询的分析。

**如何生成：**

- **在 Fuchsia OS 上：**
  - **使用 `ffx`(Fuchsia 的开发者工具)：** 从开发主机在 Fuchsia 系统上采集 traces 的主要方式是使用 `ffx trace start` 命令。
  - **目标上的 `trace` 实用程序：** Fuchsia 设备还包括一个可以控制 tracing 并保存 trace 数据的 `trace` 实用程序。
  - **使用 `ktrace` 进行内核特定 tracing：** 对于 Zircon 内核级 tracing，可以使用 `ktrace` 命令行实用程序。
- **由自定义工具以编程方式：** 某些项目可能也会以编程方式为特定的非 Fuchsia 用例生成此格式，特别是如果需要二进制、紧凑且可流式传输的 trace 格式。

**外部资源：**

- **官方 Fuchsia Tracing 文档：** [Fuchsia Tracing Guides](https://fuchsia.dev/fuchsia-src/development/tracing)
- **Fuchsia Trace 格式规范：** [Fuchsia trace format](https://fuchsia.dev/fuchsia-src/reference/tracing/trace-format)
- **关于记录和可视化的教程：** [Record and visualize a trace (Fuchsia Docs)](https://fuchsia.dev/fuchsia-src/development/tracing/tutorial/record-and-visualize-a-trace)

## pprof 格式

**描述：** `pprof` 格式是一种基于 protocol buffer 的格式，用于存储 CPU profile 数据。`pprof` 是一个用于可视化和 profile profiling 数据的工具。它读取 `profile.proto` 格式的 profiling 样本集合，并生成报告以可视化和帮助profile 数据。它是为 [Go 编程语言的 pprof profiler](https://pkg.go.dev/runtime/pprof) 开发的，但后来被许多其他语言的其他 profilers 广泛采用（例如 Python、C++、Rust 等）。

**常见场景：** Perfetto 用户遇到此格式的最常见原因是：

- **可视化 Go CPU profiles：** 开发者经常使用 Go pprof profiler 收集 CPU 样本，并需要一种方式来可视化它们。
- **使用跨平台 profiling 工具：** 一些 profiling 工具和库旨在输出或将其数据转换为此格式，以便使用与 pprof 兼容的工具进行 profile。
- **分析 Linux `perf` profiles：** `pprof` 可以使用 [perf_data_converter](https://github.com/google/perf_data_converter) 包中的 `perf_to_profile` 程序读取 [Linux perf](https://perf.wiki.kernel.org/index.php/Main_Page) 工具生成的 `perf.data` 文件。

**Perfetto 支持：**

- **Perfetto UI：** 当打开 `pprof` 文件时，Perfetto 将 profiling 数据可视化为交互式火焰图。如果 `pprof` 文件包含多个 metrics(例如，CPU 时间和内存分配)，UI 允许你在它们之间切换，为每个 metric 显示单独的火焰图。这支持调用栈的直观分析，并帮助识别跨不同维度的性能热点。

  这是一个示例效果图

  ![](/docs/images/pprof-in-ui.png)

**如何生成：** 对于 Perfetto 用户最相关的生成路径涉及从 Go 程序收集 CPU profiles 或转换 `perf.data` 文件。

1.  **从 Go 程序收集 CPU profile：** 你可以使用 `runtime/pprof` 包以编程方式收集 profile，或使用 `net/http/pprof` 包在运行的服务器上公开 profiling 端点。

    要从运行的服务器收集 profile，你可以使用 `go tool pprof` 命令：

    ```bash
    go tool pprof http://localhost:6060/debug/pprof/profile?seconds=30
    ```

    这将收集 30 秒的 CPU profile 并在 pprof 工具中打开它。然后你可以使用 pprof 工具中的 `save` 命令将 profile 保存到文件。

2.  **将 Linux `perf.data` 转换为 pprof 格式：** 使用 `perf_data_converter` 包中的 `perf_to_profile` 工具。

    ```bash
    perf_to_profile -i perf.data -o perf.pprof
    ```

**外部资源：**

- **pprof GitHub 仓库：** [https://github.com/google/pprof](https://github.com/google/pprof)
- **Go pprof 文档：** [https://pkg.go.dev/runtime/pprof](https://pkg.go.dev/runtime/pprof)
- **pprof 格式规范：** [https://github.com/google/pprof/blob/main/proto/profile.proto](https://github.com/google/pprof/blob/main/proto/profile.proto)
- **Linux `perf` 工具：** [perf Wiki](https://perf.wiki.kernel.org/index.php/Main_Page)
- **`perf_data_converter` GitHub 仓库：** [https://github.com/google/perf_data_converter](https://github.com/google/perf_data_converter)

## Collapsed Stack 格式

**描述：** Collapsed Stack 格式是一种简单的基于文本的格式，用于表示 profiling 数据，通常与 Brendan Gregg 的 FlameGraph 工具一起使用。每行包含一个分号分隔的栈跟踪（从根到叶），后跟一个空格和样本计数。此格式因其简单性而受欢迎，并且通常在用各种 profiling 源生成火焰图时用作中间格式。

**格式规范：**

```
frame1;frame2;frame3 count
# 以 # 开头的行是注释
```

- 每行代表具有其样本计数的唯一栈跟踪
- 帧由分号（`;`）分隔
- 根帧在前，叶帧在后
- 计数是一个正整数，与栈之间用空格分隔
- 以 `#` 开头的行被视为注释
- 空行和前导/尾随空白被忽略

**常见场景：** 此格式通常在以下情况下使用：

- 处理通过 `stackcollapse-perf.pl` 或类似工具处理的 `perf script` 输出。
- 使用 Brendan Gregg 的 FlameGraph 工具链生成 SVG 火焰图。
- 将来自各种来源的 profiles 转换为通用、简单的格式。
- 分析已聚合或预处理的 profiles。

**Perfetto 支持：**

- **Perfetto UI：** 当打开 collapsed stack 文件时，Perfetto 将 profiling 数据可视化为交互式火焰图，类似于 pprof 文件。

**如何生成：**

最常见的生成路径涉及处理 `perf` 输出：

```bash
# 记录 profile
sudo perf record -F 99 -g -- ./my_program

# 转换为 collapsed stack 格式
perf script | stackcollapse-perf.pl > profile.collapsed

# 在 Perfetto 中打开
# 导航到 ui.perfetto.dev 并上传 profile.collapsed
```

**外部资源：**

- **FlameGraph GitHub 仓库：** [https://github.com/brendangregg/FlameGraph](https://github.com/brendangregg/FlameGraph)
- **Brendan Gregg 的 Flame Graphs 页面：** [https://www.brendangregg.com/flamegraphs.html](https://www.brendangregg.com/flamegraphs.html)
