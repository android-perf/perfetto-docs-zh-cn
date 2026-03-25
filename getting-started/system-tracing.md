# 使用 Perfetto 采集 system traces

在本指南中，你将学习如何：

- 在 Android 和 Linux 上采集 system-wide trace。
- 在 Perfetto UI 中可视化 trace。
- 使用 PerfettoSQL 以编程方式分析 trace。

Perfetto 的一个强大用途是从单台机器上的许多不同进程和数据源收集 tracing 信息，并将它们全部合并到一个 trace 中。这允许调试广泛的性能和功能问题，包括复杂的问题。示例包括可能跨越多个进程的问题、应用程序和操作系统之间的问题，甚至硬件和操作系统之间的交互。此类 traces 称为 **system traces** 或通常简称为 **systraces**。

NOTE: 开箱即用，Perfetto 仅在 **Android** 和 **Linux** 上支持采集 system traces。虽然 trace 采集守护进程在 Windows 和 macOS 上工作，但没有与系统级数据源的集成，这意味着 traces 可能不太有用。

## 采集你的第一个 system trace

本节将指导你完成采集第一个 system-wide trace 的过程。根据你是想在 Android 上使用 GUI 采集、在 Android 上使用命令行采集还是在 Linux 上采集（仅命令行），有多种路径。

<?tabs>

TAB: Android (Perfetto UI)

**先决条件**

- 任何运行 R+ 的 Android 设备（如果使用旧版本的 Android，请改用 _Android (command line)_ 标签页）。
- 通过 USB 线连接 Android 设备的台式机/笔记本电脑。
- 设备上必须启用开发者选项和 USB 调试。

**说明**

1. 首先导航到 [ui.perfetto.dev](https://ui.perfetto.dev)。这是 **Perfetto UI**，我们用于采集、profile 和可视化 traces 的多合一图形 UI；在本指南的其余部分，我们将大量使用它。
2. 点击左侧边栏上的 "Record New Trace"。
3. 这应该会将你带到 UI 的 _Recording page_，看起来像这样：
   ![Perfetto UI 的录制页面](/docs/images/record-trace-adb-websocket-success.png)
4. 你可以在不同的连接 Android 设备的方式之间进行选择。
   按照屏幕上的说明连接到你的设备。Perfetto UI 将检查是否满足所有条件，否则将显示描述性错误消息。例如，对于 _ABD+Websocket_ 传输，成功消息将如上面的屏幕截图所示。

5. 在 **Recording Settings** 页面上，你可以为本指南保留默认设置。这些设置控制 trace 的录制方式：

    - **Recording Mode**: 此设置确定如何收集 trace。
      - **Stop when full**: 当内存缓冲区满时停止 tracing。
      - **Ring buffer**: 当缓冲区满时覆盖最旧的数据。
      - **Long trace**: 定期将 trace 从内存保存到文件，允许非常长的 traces。
    - **In-memory buffer size**: 设置设备上用于存储 trace 数据到写入文件之前的内存量。
    - **Max duration**: 设置 trace 的时间限制。你也可以随时手动停止它。

6. 现在我们可以在 **Probes** 部分配置我们想要收集的确切类型的 tracing 信息。随意探索标签页及其包含的选项：UI 应该简要解释每个选项的作用以及为什么它可能有用。就本指南而言，我们将希望启用以下 probes：

    - **CPU**:
      - **Scheduling details**: 查看每个 CPU 上随时间运行的进程/线程。
      - **CPU frequency and idle states**: 查看每个 CPU 运行的频率。
    - **Android Apps and Svcs**:
      - **Atrace userspace annotations**: 获取有关系统和应用程序正在做什么的上下文。启用 "System server"、"View system" 和 "Input" 类别（按 Ctrl/Cmd 同时单击可多选）。
      - **Event log (logcat)**: 在 trace 中包含 `logcat` 消息。

7. 点击绿色的 "Start Recording" 按钮，当 trace 正在录制时，在 Android 设备上执行一些操作（例如打开应用程序、解锁手机等）。
8. 10 秒后，trace 将自动停止，你将切换到收集的 trace 的 Timeline 视图；这将在下一节中讨论。

TAB: Android (command line)

**先决条件**

- 任何运行 M+ 的 Android 设备
- 通过 USB 线连接 Android 设备的台式机/笔记本电脑
- `adb` (Android Debug Bridge) 可执行文件在你的 `PATH` 上可用
  - 可以从 https://developer.android.com/studio/releases/platform-tools 下载适用于 Linux、Mac 或 Windows 的 ADB 二进制文件

Perfetto 团队提供了一个名为 `record_android_trace` 的帮助脚本，用于在 Android 上从命令行采集 traces。这负责收集 trace、从服务器拉取它，甚至在 Perfetto UI 中打开它的大部分繁重工作：

```bash
curl -O https://raw.githubusercontent.com/google/perfetto/main/tools/record_android_trace

# 有关更多详细信息，请参阅 python3 record_android_trace --help。
python3 record_android_trace \
   -o trace_file.perfetto-trace
   # 此选项将 trace 配置为运行 10 秒。
   -t 10s \
   # 此选项将主缓冲区大小配置为 32MB。
   -b 32mb \
   # 此选项启用来自系统上所有应用程序的 atrace annotations。
   -a '*' \
   # 这些选项指定设备上一些最重要的插桩：CPU scheduling/frequency 以了解 CPU 上正在运行什么以及
   # 系统对工作的重要性，以及 atrace annotations 以了解 userspace 进程（平台和应用程序）内部发生的情况。
   sched freq view ss input
```

上述命令应该会导致收集一个持续 10 秒的 trace：当它运行时，在 Android 设备上执行一些操作（例如打开应用程序、解锁手机等）。采集完成后，trace 将在浏览器窗口中自动在 Perfetto UI 中打开。

NOTE: 如果你在远程机器上运行此操作（即通过 SSH），你应该传递标志 `--no-open`（防止自动打开 Perfetto UI）并手动下载打印路径处的文件（例如使用 `scp`）并在 UI 中打开；下一节提供了有关此操作的说明。

TAB: Linux (command line)

Perfetto 可以在 Linux 上采集 system traces。支持所有基于 ftrace 的数据源和大多数其他基于 procfs / sysfs 的数据源。

由于 Perfetto 的 [service-based architecture](/docs/concepts/service-model.md)，为了采集 trace，`traced` (session daemon) 和 `traced_probes` (probes 和 ftrace-interop daemon) 需要正在运行。根据 Perfetto v16，`tracebox` 二进制文件将你需要的所有二进制文件捆绑在一个静态链接的可执行文件中（有点像 `toybox` 或 `busybox`），这使得在不同机器上复制和运行变得容易。

你可以从 GitHub 下载 `tracebox` 二进制文件：
```bash
curl -LO https://get.perfetto.dev/tracebox
chmod +x tracebox
```

## 采集 trace

要采集 trace，你需要将配置文件传递给下载的 `tracebox` 二进制文件。我们在 [/test/configs/](/test/configs/) 目录中有一些示例配置文件。
假设你想采集带有 scheduling 信息的 trace。你可以通过下载配置文件来执行此操作
```bash
curl -LO https://raw.githubusercontent.com/google/perfetto/refs/heads/main/test/configs/scheduling.cfg
```
并运行以下命令：
```bash
./tracebox -o trace_file.perfetto-trace --txt -c scheduling.cfg
```
scheduling 信息是使用 ftrace 采集的，因此你可能需要以 root 权限启动 `tracebox`。

</tabs?>

## 查看你的第一个 trace

我们现在可以通过使用基于 Web 的 trace 可视化工具：Perfetto UI 来直观地探索采集的 trace。

NOTE: Perfetto UI 在浏览器中使用 JavaScript + WebAssembly 完全在本地运行。默认情况下，trace 文件 **不会** 上传到任何地方，除非你明确点击 "Share" 链接。

NOTE: "Share" 链接仅对 Googlers 可用。

上面的采集说明都应该导致 trace 在浏览器中自动打开。但是，如果由于某种原因它们不起作用（最可能的是如果你通过 SSH 运行命令），你也可以手动打开 traces：

1. 在浏览器中导航到 [ui.perfetto.dev](https://ui.perfetto.dev)。
2. 点击左侧菜单上的 **Open trace file**，并加载采集的 traces 或简单地将你的 trace 拖放到 Perfetto UI 中。

![Perfetto UI 打开 trace](/docs/images/perfetto-ui-open-trace.png)

![Perfetto UI 加载 trace](/docs/images/system-tracing-trace-view.png)

- 通过使用 WASD 缩放/平移来探索 trace，并使用鼠标将进程 tracks（行）展开为其组成的线程 tracks。按 "?" 获取更多导航控件。
- 还请查看我们的 Perfetto UI [文档页面](/docs/visualization/perfetto-ui.md)

## 查询你的第一个 trace

除了在 Timeline 上可视化 traces 之外，Perfetto 还支持使用 SQL 查询 traces。最简单的方法是使用直接在 UI 中可用的查询引擎。

1.  在 Perfetto UI 中，点击左侧菜单中的 "Query (SQL)" 标签页。

    ![Perfetto UI Query SQL](/docs/images/perfetto-ui-query-sql.png)

2.  这将打开一个两部分窗口。你可以在顶部部分编写你的 PerfettoSQL 查询，并在底部部分查看结果。

    ![Perfetto UI SQL 窗口](/docs/images/perfetto-ui-sql-window.png)

3.  你现在可以执行查询。例如，要查看 trace 中采集的所有进程，请运行以下查询（你可以使用 Ctrl/Cmd + Enter 作为快捷方式）：

例如，要查询我们录制的 CPU scheduling 信息，你可以使用：

```sql
INCLUDE PERFETTO MODULE sched.with_context;

SELECT *
FROM sched_with_thread_process
LIMIT 100;
```

对于 CPU frequency 信息，你可以执行以下操作：

```sql
INCLUDE PERFETTO MODULE linux.cpu.frequency;

SELECT *
FROM cpu_frequency_counters
LIMIT 100;
```

对于 Android traces，要查询 `atrace` slices，你可以执行以下操作：

```sql
INCLUDE PERFETTO MODULE slices.with_context;

SELECT *
FROM thread_or_process_slice
LIMIT 100;
```

atrace counters 可通过以下方式获得：

```sql
SELECT *
FROM counter
LIMIT 100;
```

## 下一步

现在你已经采集并分析了你的第一个 system trace，你可以探索更多主题：

### 更多数据源

System trace 可以包含来自系统许多不同部分的数据。了解更多关于一些最常见的数据源：

- **[Scheduling events](/docs/data-sources/cpu-scheduling.md)**: 获取有关哪些线程在哪个 CPU 上运行的详细信息。
- **[CPU Frequency](/docs/data-sources/cpu-freq.md)**: 查看 CPU frequency 如何随时间变化。
- **[System Calls](/docs/data-sources/syscalls.md)**: Tracing 系统调用的进入和退出。

对于 Android 开发者，通常还包括：

- **[ATrace](/docs/data-sources/atrace.md)**: 来自 Android 应用程序和服务的事件。
- **[Logcat](/docs/data-sources/android-log.md)**: Logcat 消息。

### 更多关于 trace 录制

- **[Trace Configuration](/docs/concepts/config.md)**: 更深入地了解如何配置 traces。
- **[Tracing in the Background](/docs/learning-more/tracing-in-background.md)**:
  了解如何长时间采集 traces。

### 更多关于 trace 分析

要充分利用 Perfetto UI，请查看详细的 **[Perfetto UI 文档](/docs/visualization/perfetto-ui.md)**。

要了解更多关于程序化分析的信息，请参阅：

- **[Trace Analysis with SQL](/docs/analysis/getting-started.md)**: 了解如何使用 Trace Processor 和 PerfettoSQL 分析 traces。
- **[Android Analysis Cookbooks](/docs/getting-started/android-trace-analysis.md)**:
  用于处理 Android traces 的有用查询和可视化技巧集合。
