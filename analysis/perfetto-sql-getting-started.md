# PerfettoSQL 入门指南

PerfettoSQL 是 Perfetto 中 trace 分析的基础。它是一种 SQL 方言，允许你将 trace 内容作为数据库进行查询。本文介绍了使用 PerfettoSQL 进行 trace 查询的核心概念，并提供了如何编写查询的指导。

## Trace 查询概述

Perfetto UI 是一个强大的可视化分析工具，提供调用栈、Timeline 视图、线程 track 和 slice。它还包括一个强大的 SQL 查询语言（PerfettoSQL），由查询引擎（[TraceProcessor](trace-processor.md)）解释，使你能够以编程方式提取数据。

虽然 UI 对于多种分析场景功能强大，但用户能够在 Perfetto UI 中编写和执行查询用于多种目的，例如：

- 从 trace 中提取性能数据
- 创建自定义可视化（Debug track）以执行更复杂的分析
- 创建派生 metrics
- 使用数据驱动的逻辑识别性能瓶颈

除了 Perfetto UI 之外，你可以使用 [Python Trace Processor API](trace-processor-python.md) 或 [C++ Trace Processor](trace-processor.md) 以编程方式查询 trace。

Perfetto 还支持通过 [Batch Trace Processor](batch-trace-processor.md) 进行批量 trace 分析。此系统的一个关键优势是查询可重用性：用于单个 trace 的相同 PerfettoSQL 查询无需修改即可应用于大型数据集。

## 核心概念

在编写查询之前，了解 Perfetto 如何构造 trace 数据的基础概念很重要。

### 事件

在最一般的意义上，trace 只是一组带时间戳的"事件"。事件可以具有关联的元数据和上下文，使它们能够被解释和分析。时间戳以纳秒为单位；值本身取决于 TraceConfig 中选择的 [clock](https://cs.android.com/android/platform/superproject/main/+/main:external/perfetto/protos/perfetto/config/trace_config.proto;l=114;drc=c74c8cf69e20d7b3261fb8c5ab4d057e8badce3e)。

事件构成了 trace processor 的基础，并且有两种类型：slice 和 counter。

#### Slice

![Slice 示例](/docs/images/slices.png)

Slice 指的是一段时间间隔，其中包含一些描述该期间内发生情况的数据。一些 slice 的示例包括：

- 每个 CPU 的调度 slice
- Android 上的 atrace slice
- 来自 Chrome 的用户空间 slice

#### Counter

![Counter 示例](/docs/images/counters.png)

Counter 是随时间变化的连续值。一些 counter 的示例包括：

- 每个 CPU 核心的 CPU 频率
- RSS 内存事件 - 来自内核和从 /proc/stats 轮询
- Android 上的 atrace counter 事件
- Chrome counter 事件

### Track

Track 是相同类型和相同关联上下文的事件的命名分区。例如：

- 调度 slice 每个 CPU 有一个 track
- 同步用户空间 slice 每个发出事件的线程有一个 track
- 异步用户空间 slice 每个链接一组异步事件的"cookie"有一个 track

思考 track 的最直观方式是想象它们将如何在 UI 中绘制；如果所有事件都在单行中，则它们属于同一个 track。例如，CPU 5 的所有调度事件都在同一个 track 上：

![CPU slice track](/docs/images/cpu-slice-track.png)

Track 可以根据它们包含的事件类型和它们关联的上下文分为各种类型。示例包括：

- 全局 track 不与任何上下文关联并包含 slice
- 线程 track 与单个线程关联并包含 slice
- Counter track 不与任何上下文关联并包含 counter
- CPU counter track 与单个 CPU 关联并包含 counter

### 线程和进程标识符

在 trace 的上下文中考虑时，线程和进程的处理需要特别小心；线程和进程的标识符（例如 Android/macOS/Linux 中的 `pid`/`tgid` 和 `tid`）可以在 trace 过程中被操作系统重用。这意味着当查询 trace processor 中的表时，不能将它们作为唯一标识符依赖。

为了解决此问题，trace processor 使用 `utid`（_unique_ tid）表示线程，使用 `upid`（_unique_ pid）表示进程。所有对线程和进程的引用（例如，在 CPU 调度数据、线程 track 中）都使用 `utid` 和 `upid` 而不是系统标识符。

### 在 Perfetto UI 中查询 trace

既然你了解了核心概念，就可以开始编写查询了。

Perfetto 直接在 UI 中提供了一个用于执行自由格式查询的 SQL 自由格式多行文本输入 UI。要访问它：

1. 在 [Perfetto UI](https://ui.perfetto.dev/) 中打开 trace。

2. 单击导航栏中的 **Query (SQL)** 标签（见下图）。

![Query (SQL) 标签](/docs/images/perfettosql_query_tab.png)

选择此标签后，查询 UI 将显示，你可以自由格式编写 PerfettoSQL 查询，该界面支持编写查询、显示查询结果和查询历史记录，如下图所示。

![查询 UI](/docs/images/perfetto-sql-cli-description.png)

3. 在查询 UI 区域中输入你的查询，然后按 Ctrl + Enter（或 Cmd + Enter）执行。

执行查询后，查询结果将在同一窗口中显示。

当你对如何查询以及查询什么有一定了解时，这种查询方法很有用。

为了了解如何编写查询，请参阅 [语法指南](perfetto-sql-syntax.md)，然后为了查找可用的表、模块、函数等，请参阅 [标准库](stdlib-docs.autogen)。

很多时候，将查询结果转换为 track 对于在 UI 中执行复杂分析很有用，我们鼓励读者查看[Debug Tracks](debug-tracks.md）以获取有关如何实现此操作的更多信息。

### 示例：执行基本查询

探索 trace 的最简单方法是从原始表中进行选择。例如，要查看 trace 中的前 10 个 slice，你可以运行：

```sql
SELECT ts, dur, name FROM slice LIMIT 10;
```

你可以通过在 PerfettoSQL 查询 UI 中单击 **Run Query** 来编写和执行它，下面是来自 trace 的示例。

![基本查询](/docs/images/perfetto-sql-basic-query.png)

### 使用 JOIN 获取更多上下文

在 trace processor 中查询表时的一个常见问题是："我如何获取 slice 的进程或线程？"。更一般地说，问题是"我如何获取事件的上下文？"。

在 trace processor 中，track 上所有事件关联的上下文都可在关联的 `track` 表上找到。

例如，要获取发出 `measure` slice 的任何线程的 `utid`

```sql
SELECT utid
FROM slice
JOIN thread_track ON thread_track.id = slice.track_id
WHERE slice.name = 'measure'
```

类似地，要获取值大于 1000 的 `mem.swap` counter 的任何进程的 `upid`

```sql
SELECT upid
FROM counter
JOIN process_counter_track ON process_counter_track.id = counter.track_id
WHERE process_counter_track.name = 'mem.swap' AND value > 1000
```

### 线程和进程表

虽然获取 `utid` 和 `upid` 是向正确方向迈出的一步，但通常用户想要原始的 `tid`、`pid` 和进程/线程名称。

`thread` 和 `process` 表分别将 `utid` 和 `upid` 映射到线程和进程。例如，要查找 `utid` 为 10 的线程

```sql
SELECT tid, name
FROM thread
WHERE utid = 10
```

`thread` 和 `process` 表也可以直接与关联的 track 表连接，以直接从 slice 或 counter 跳转到有关进程和线程的信息。

例如，要获取发出 `measure` slice 的所有线程的列表：

```sql
SELECT thread.name AS thread_name
FROM slice
JOIN thread_track ON slice.track_id = thread_track.id
JOIN thread USING(utid)
WHERE slice.name = 'measure'
GROUP BY thread_name
```

## 使用标准库简化查询

虽然总是可以通过连接原始表从头开始编写查询，但 PerfettoSQL 提供了丰富的**[标准库](stdlib-docs.autogen)** 预构建模块以简化常见分析任务。

要使用标准库中的模块，你需要使用 `INCLUDE PERFETTO MODULE` 语句导入它。例如，代替直接与线程和进程连接，你可以使用 `slices.with_context` 模块：

```sql
INCLUDE PERFETTO MODULE slices.with_context;

SELECT thread_name, process_name, name, ts, dur
FROM thread_or_process_slice;
```

导入后，你可以在查询中使用模块提供的表和函数。有关可用模块的更多信息，请参阅[标准库文档](stdlib-docs.autogen)。

有关 `INCLUDE PERFETTO MODULE` 语句和其他 PerfettoSQL 功能的更多详细信息，请参阅 [PerfettoSQL 语法](perfetto-sql-syntax.md）文档。

## 高级查询

对于需要超越标准库或构建自己的抽象的用户，PerfettoSQL 提供了几种高级功能。

### 辅助函数

辅助函数是内置在 C++ 中的函数，用于减少需要在 SQL 中编写的样板代码。

#### 提取参数

`EXTRACT_ARG` 是一个辅助函数，用于从 `args` 表中检索事件（例如 slice 或 counter）的属性。

它接受 `arg_set_id` 和 `key` 作为输入，并返回在 `args` 表中查找的值。

例如，要从 `ftrace_event` 表中检索 `sched_switch` 事件的 `prev_comm` 字段。

```sql
SELECT EXTRACT_ARG(arg_set_id, 'prev_comm')
FROM ftrace_event
WHERE name = 'sched_switch'
```

在幕后，上述查询将脱糖为以下内容：

```sql
SELECT
 (
 SELECT string_value
 FROM args
 WHERE key = 'prev_comm' AND args.arg_set_id = raw.arg_set_id
 )
FROM ftrace_event
WHERE name = 'sched_switch'
```

### 运算符表

SQL 查询通常足以从 trace processor 检索数据。但有时，某些构造很难用纯 SQL 表示。

在这些情况下，trace processor 具有特殊的"运算符表"，它们用 C++ 解决特定问题，但公开 SQL 接口以供查询利用。

#### Span join

Span join 是一个自定义运算符表，用于计算来自两个表或视图的时间段的交集。在此概念中，span 是表/视图中包含"ts"（时间戳）和"dur"（持续时间）列的一行。

可以指定一个列（称为 _partition_ ），在计算交集之前将每个表的行划分为分区。

![Span join 框图](/docs/images/span-join.png)

```sql
-- 获取所有调度 slice
CREATE VIEW sp_sched AS
SELECT ts, dur, cpu, utid
FROM sched;

-- 获取所有 cpu frequency slice
CREATE VIEW sp_frequency AS
SELECT
 ts,
 lead(ts) OVER (PARTITION BY track_id ORDER BY ts) - ts as dur,
 cpu,
 value as freq
FROM counter
JOIN cpu_counter_track ON counter.track_id = cpu_counter_track.id
WHERE cpu_counter_track.name = 'cpufreq';

-- 创建将 cpu frequency 与
-- 调度 slice 结合的 span joined 表。
CREATE VIRTUAL TABLE sched_with_frequency
USING SPAN_JOIN(sp_sched PARTITIONED cpu, sp_frequency PARTITIONED cpu);

-- 此 span joined 表可以正常查询，并具有来自两个表
-- 的列。
SELECT ts, dur, cpu, utid, freq
FROM sched_with_frequency;
```

NOTE: 可以在两个表、一个表或都不表上指定分区。如果在两个表上指定，则必须在每个表上指定相同的列名称。

WARNING: span joined 表的一个重要限制是，同一分区中同一表的 span _不能_重叠。出于性能原因，span join 不会尝试检测并在这种情况下出错；相反，将 silently 产生错误的行。

WARNING: 分区必须是整数。重要的是，不支持字符串分区；请注意，可以通过将 `HASH` 函数应用于字符串列将字符串转换为整数。

还支持左连接和外 span join;两者的功能类似于 SQL 中的左连接和外连接。

```sql
-- 左表分区 + 右表未分区。
CREATE VIRTUAL TABLE left_join
USING SPAN_LEFT_JOIN(table_a PARTITIONED a, table_b);

-- 两个表都未分区。
CREATE VIRTUAL TABLE outer_join
USING SPAN_OUTER_JOIN(table_x, table_y);
```

NOTE: 如果分区表为空，并且是 a) 外连接的一部分 b) 左连接的右侧，则存在细微差别。在这种情况下，即使另一个表非空，也不会发出任何 slice。在考虑实际中如何使用 span join 之后，决定此方法是最自然的。

#### Ancestor slice

ancestor_slice 是一个自定义运算符表，它接受[slice 表的 id 列](/docs/analysis/sql-tables.autogen#slice)，并计算同一 track 上在该 id 上方的所有直接父 slice(即给定一个 slice id，它将作为行返回通过跟随 parent_id 列到顶部 slice 可以找到的所有 slice(depth = 0))。

返回的格式与[slice 表](/docs/analysis/sql-tables.autogen#slice）相同

例如，以下查找给定一堆感兴趣的 slice 的顶层 slice。

```sql
CREATE VIEW interesting_slices AS
SELECT id, ts, dur, track_id
FROM slice WHERE name LIKE "%interesting slice name%";

SELECT
 *
FROM
 interesting_slices LEFT JOIN
 ancestor_slice(interesting_slices.id) AS ancestor ON ancestor.depth = 0
```

#### Ancestor slice by stack

ancestor_slice_by_stack 是一个自定义运算符表，它接受[slice 表的 stack_id 列](/docs/analysis/sql-tables.autogen#slice)，查找具有该 stack_id 的所有 slice id，然后对于每个 id，计算所有祖先 slice，类似于[ancestor_slice](/docs/analysis/trace-processor#ancestor-slice)。

返回的格式与[slice 表](/docs/analysis/sql-tables.autogen#slice）相同

例如，以下查找具有给定名称的所有 slice 的顶层 slice。

```sql
CREATE VIEW interesting_stack_ids AS
SELECT stack_id
FROM slice WHERE name LIKE "%interesting slice name%";

SELECT
 *
FROM
 interesting_stack_ids LEFT JOIN
 ancestor_slice_by_stack(interesting_stack_ids.stack_id) AS ancestor
 ON ancestor.depth = 0
```

#### Descendant slice

descendant_slice 是一个自定义运算符表，它接受[slice 表的 id 列](/docs/analysis/sql-tables.autogen#slice)，并计算同一 track 上嵌套在该 id 下的所有 slice(即同一 track 上在相同时间帧内深度大于给定 slice 的深度的所有 slice。

返回的格式与[slice 表](/docs/analysis/sql-tables.autogen#slice）相同

例如，以下查找每个感兴趣的 slice 下的 slice 数量。

```sql
CREATE VIEW interesting_slices AS
SELECT id, ts, dur, track_id
FROM slice WHERE name LIKE "%interesting slice name%";

SELECT
 *
FROM
 interesting_slices
JOIN (
 SELECT
 COUNT(*) AS total_descendants
 FROM descendant_slice(interesting_slice.id)
 )
FROM interesting_slices
```

#### Descendant slice by stack

descendant_slice_by_stack 是一个自定义运算符表，它接受[slice 表的 stack_id 列](/docs/analysis/sql-tables.autogen#slice)，查找具有该 stack_id 的所有 slice id，然后对于每个 id，计算所有后代 slice，类似于[descendant_slice](/docs/analysis/trace-processor#descendant-slice)。

返回的格式与[slice 表](/docs/analysis/sql-tables.autogen#slice）相同

例如，以下查找具有给定名称的所有 slice 的下一级后代。

```sql
CREATE VIEW interesting_stacks AS
SELECT stack_id, depth
FROM slice WHERE name LIKE "%interesting slice name%";

SELECT
 *
FROM
 interesting_stacks LEFT JOIN
 descendant_slice_by_stack(interesting_stacks.stack_id) AS descendant
 ON descendant.depth = interesting_stacks.depth + 1
```

#### Connected/Following/Preceding flows

DIRECTLY_CONNECTED_FLOW、FOLLOWING_FLOW 和 PRECEDING_FLOW 是自定义运算符表，它们接受[slice 表的 id 列](/docs/analysis/sql-tables.autogen#slice)，并收集[flow 表](/docs/analysis/sql-tables.autogen#flow）的所有条目，这些条目与给定的起始 slice 直接或间接连接。

`DIRECTLY_CONNECTED_FLOW(start_slice_id)` - 包含[flow 表](/docs/analysis/sql-tables.autogen#flow）的所有条目，这些条目存在于任何类型的链中：`flow[0] -> flow[1] -> ... -> flow[n]`，其中 `flow[i].slice_out = flow[i+1].slice_in` 和 `flow[0].slice_out = start_slice_id OR start_slice_id = flow[n].slice_in`。

NOTE: 与以下/前置流函数不同，此函数在从 slice 搜索流时不会包含连接到祖先或后代的流。它仅包含直接连接的链中的 slice。

`FOLLOWING_FLOW(start_slice_id)` - 包含所有可以通过从流的传出 slice 递归跟随到其传入 slice 以及从到达的 slice 到其子 slice 而从给定 slice 到达的流。返回表包含[flow 表](/docs/analysis/sql-tables.autogen#flow）的所有条目，这些条目存在于任何类型的链中：`flow[0] -> flow[1] -> ... -> flow[n]`，其中 `flow[i+1].slice_out IN DESCENDANT_SLICE(flow[i].slice_in) OR flow[i+1].slice_out = flow[i].slice_in` 和 `flow[0].slice_out IN DESCENDANT_SLICE(start_slice_id) OR flow[0].slice_out = start_slice_id`。

`PRECEDING_FLOW(start_slice_id)` - 包含所有可以通过从流的传入 slice 递归跟随到其传出 slice 以及从到达的 slice 到其父 slice 而从给定 slice 到达的流。返回表包含[flow 表](/docs/analysis/sql-tables.autogen#flow）的所有条目，这些条目存在于任何类型的链中：`flow[n] -> flow[n-1] -> ... -> flow[0]`，其中 `flow[i].slice_in IN ANCESTOR_SLICE(flow[i+1].slice_out) OR flow[i].slice_in = flow[i+1].slice_out` 和 `flow[0].slice_in IN ANCESTOR_SLICE(start_slice_id) OR flow[0].slice_in = start_slice_id`。

```sql
--每个 slice 的后续流数量
SELECT (SELECT COUNT(*) FROM FOLLOWING_FLOW(slice_id)) as following FROM slice;
```

## 下一步

既然你对 PerfettoSQL 有了基础了解，你可以探索以下主题以加深你的知识：

- **[PerfettoSQL 语法](perfetto-sql-syntax.md)** ： 了解 Perfetto 支持的 SQL 语法，包括用于创建函数、表和视图的特殊功能。
- **[标准库](stdlib-docs.autogen)** ： 探索标准库中可用的丰富模块集，用于分析常见场景，如 CPU 使用率、内存和功耗。
- **[Trace Processor (C++)](trace-processor.md)** ： 了解如何使用交互式 shell 和底层 C++ 库。
- **[Trace Processor (Python)](trace-processor-python.md)** ： 利用 Python API 将 trace 分析与丰富的数据科学和可视化生态系统结合起来。
