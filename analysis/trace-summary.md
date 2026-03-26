# Trace 汇总

本指南解释如何使用 Perfetto 的 trace 汇总功能从 trace 中提取结构化、可操作的数据。

## 为什么要使用 Trace 汇总？

PerfettoSQL 是一个强大的工具，用于交互式探索 trace。你可以编写任何想要的查询，结果立即可用。但是，这种灵活性给自动化和大规模分析带来了挑战。`SELECT` 语句的输出具有任意架构（列名和类型），可能会从一个查询更改为下一个查询。这使得构建消费此数据的通用工具、仪表板或回归检测系统变得困难，因为它们无法依赖稳定的数据结构。

**Trace 汇总解决了这个问题。**它提供了一种为要从 trace 中提取的数据定义稳定、结构化架构的方法。它不是生成任意表，而是生成一致的 protobuf 消息([`TraceSummary`](https://source.chromium.org/chromium/chromium/src/+/main:third_party/perfetto/protos/perfetto/trace_summary/file.proto;l=53?q=tracesummaryspec))，工具很容易解析和处理。

这对于**跨 trace 分析**尤其强大。通过在数百或数千个 trace 上运行相同的汇总规范，你可以可靠地聚合结果，以跟踪一段时间内的性能 metrics，比较应用程序的不同版本，并自动检测回归。

简而言之，当你需要以下情况时，使用 trace 汇总：

- 为自动化工具提取数据
- 确保分析的稳定输出架构
- 执行大规模、跨 trace 分析

## 使用标准库生成汇总

最简单的方法是使用 [PerfettoSQL 标准库](/docs/analysis/stdlib-docs.autogen）中的模块。

让我们通过一个示例。假设我们想要计算 trace 中每个进程的平均内存使用量（具体来说，RSS + Swap）。`linux.memory.process` 模块已经提供了一个表 `memory_rss_and_swap_per_process`，非常适合此目的。

我们可以定义一个 `TraceSummarySpec` 来计算此 metrics：

```protobuf
// spec.textproto
metric_spec {
 id: "memory_per_process"
 dimensions: "process_name"
 value: "avg_rss_and_swap"
 query: {
 table: {
 table_name: "memory_rss_and_swap_per_process"
 }
 referenced_modules: "linux.memory.process"
 group_by: {
 column_names: "process_name"
 aggregates: {
 column_name: "rss_and_swap"
 op: DURATION_WEIGHTED_MEAN
 result_column_name: "avg_rss_and_swap"
 }
 }
 }
}
```

要运行此操作，请将上述内容保存为 `spec.textproto` 并使用你首选的工具。

<?tabs>

TAB: Python API

```python
from perfetto.trace_processor import TraceProcessor

with open('spec.textproto', 'r') as f:
 spec_text = f.read()

with TraceProcessor(trace='my_trace.pftrace') as tp:
 summary = tp.trace_summary(
 specs=[spec_text],
 metric_ids=["memory_per_process"]
 )
 print(summary)
```

TAB: Command-line shell

```bash
trace_processor_shell --summary \
 --summary-spec spec.textproto \
 --summary-metrics-v2 memory_per_process \
 my_trace.pftrace
```

</tabs?>

## 使用模板减少重复

通常，你希望计算几个相关的 metrics，这些 metrics 共享相同的底层查询和维度。例如，对于给定进程，你可能想知道最小、最大和平均内存使用量。

与其为每个 metrics 编写单独的 `metric_spec`，这将涉及重复相同的 `query` 和 `dimensions` 块，你可以使用[`TraceMetricV2TemplateSpec`](/protos/perfetto/trace_summary/v2_metric.proto)。这更简洁，更不容易出错，并且性能更高，因为底层查询只运行一次。

让我们扩展我们的内存示例，计算每个进程的 RSS+Swap 的最小值、最大值和持续时间加权平均值。

```protobuf
// spec.textproto
metric_template_spec {
 id_prefix: "memory_per_process"
 dimensions: "process_name"
 value_columns: "min_rss_and_swap"
 value_columns: "max_rss_and_swap"
 value_columns: "avg_rss_and_swap"
 query: {
 table: {
 table_name: "memory_rss_and_swap_per_process"
 }
 referenced_modules: "linux.memory.process"
 group_by: {
 column_names: "process_name"
 aggregates: {
 column_name: "rss_and_swap"
 op: MIN
 result_column_name: "min_rss_and_swap"
 }
 aggregates: {
 column_name: "rss_and_swap"
 op: MAX
 result_column_name: "max_rss_and_swap"
 }
 aggregates: {
 column_name: "rss_and_swap"
 op: DURATION_WEIGHTED_MEAN
 result_column_name: "avg_rss_and_swap"
 }
 }
 }
}
```

这个单一模板生成三个 metrics：

- `memory_per_process_min_rss_and_swap`
- `memory_per_process_max_rss_and_swap`
- `memory_per_process_avg_rss_and_swap`

然后你可以运行它，请求任何或所有生成的 metrics，如下所示。

<?tabs>

TAB: Python API

```python
from perfetto.trace_processor import TraceProcessor

with open('spec.textproto', 'r') as f:
 spec_text = f.read()

with TraceProcessor(trace='my_trace.pftrace') as tp:
 summary = tp.trace_summary(
 specs=[spec_text],
 metric_ids=[
 "memory_per_process_min_rss_and_swap",
 "memory_per_process_max_rss_and_swap",
 "memory_per_process_avg_rss_and_swap",
 ]
 )
 print(summary)
```

TAB: Command-line shell

```bash
trace_processor_shell --summary \
 --summary-spec spec.textproto \
 --summary-metrics-v2 memory_per_process_min_rss_and_swap,memory_per_process_max_rss_and_swap,memory_per_process_avg_rss_and_swap \
 my_trace.pftrace
```

</tabs?>

## 添加单位和极性

为了使 metrics 的自动化 profile 和可视化更强大，你可以为 metrics 添加单位和极性（即，较高还是较低的值更好）。

这是通过在 `TraceMetricV2TemplateSpec` 中使用 `value_column_specs` 字段而不是简单的 `value_columns` 来完成的。这允许你为模板生成的每个 metrics 指定 `unit` 和 `polarity`。

让我们调整之前的内存示例以包含此信息。我们将指定内存值以 `BYTES` 为单位，较低的值更好。

```protobuf
// spec.textproto
metric_template_spec {
 id_prefix: "memory_per_process"
 dimensions: "process_name"
 value_column_specs: {
 name: "min_rss_and_swap"
 unit: BYTES
 polarity: LOWER_IS_BETTER
 }
 value_column_specs: {
 name: "max_rss_and_swap"
 unit: BYTES
 polarity: LOWER_IS_BETTER
 }
 value_column_specs: {
 name: "avg_rss_and_swap"
 unit: BYTES
 polarity: LOWER_IS_BETTER
 }
 query: {
 table: {
 table_name: "memory_rss_and_swap_per_process"
 }
 referenced_modules: "linux.memory.process"
 group_by: {
 column_names: "process_name"
 aggregates: {
 column_name: "rss_and_swap"
 op: MIN
 result_column_name: "min_rss_and_swap"
 }
 aggregates: {
 column_name: "rss_and_swap"
 op: MAX
 result_column_name: "max_rss_and_swap"
 }
 aggregates: {
 column_name: "rss_and_swap"
 op: DURATION_WEIGHTED_MEAN
 result_column_name: "avg_rss_and_swap"
 }
 }
 }
}
```

这将为每个生成 metrics 的 `TraceMetricV2Spec` 添加指定的 `unit` 和 `polarity`，使输出更丰富，对自动化工具更有用。

## 使用自定义 SQL 模块生成汇总

虽然标准库很强大，但你经常需要分析特定于你的应用程序的自定义事件。你可以通过编写自己的 SQL 模块并将它们加载到 Trace Processor 中来实现此目的。

SQL 包只是一个包含 `.sql` 文件的目录。此目录可以加载到 Trace Processor 中，其文件可作为模块使用。

假设你有名为 `game_frame` 的自定义 slice，并且想要计算平均、最小和最大帧持续时间。

**1. 创建自定义 SQL 模块：**

创建这样的目录结构：

```
my_sql_modules/
└── my_game/
 └── metrics.sql
```

在 `metrics.sql` 内部，定义一个计算帧统计的视图：

```sql
-- my_sql_modules/my_game/metrics.sql
CREATE PERFETTO VIEW game_frame_stats AS
SELECT
 'game_frame' AS frame_type,
 MIN(dur) AS min_duration_ns,
 MAX(dur) AS max_duration_ns,
 AVG(dur) AS avg_duration_ns
FROM slice
WHERE name = 'game_frame'
GROUP BY 1;
```

**2. 在汇总规范中使用模板：**

同样，我们可以使用 `TraceMetricV2TemplateSpec` 从单个共享配置生成这些相关 metrics。

创建一个引用你的自定义模块和视图的 `spec.textproto`:

```protobuf
// spec.textproto
metric_template_spec {
 id_prefix: "game_frame"
 dimensions: "frame_type"
 value_columns: "min_duration_ns"
 value_columns: "max_duration_ns"
 value_columns: "avg_duration_ns"
 query: {
 table: {
 // 模块名称是相对于包根目录的目录路径,
 // 去掉了 .sql 扩展名。
 table_name: "game_frame_stats"
 }
 referenced_modules: "my_game.metrics"
 }
}
```

**3. 使用你的自定义包运行汇总：**

你现在可以使用 Python API 或命令行 shell 计算汇总，告诉 Trace Processor 在哪里找到你的自定义包。

<?tabs>

TAB: Python API

在 `TraceProcessorConfig` 中使用 `add_sql_packages` 参数。

```python
from perfetto.trace_processor import TraceProcessor, TraceProcessorConfig

# 自定义 SQL 模块目录的路径
sql_package_path = './my_sql_modules'

config = TraceProcessorConfig(
 add_sql_packages=[sql_package_path]
)

with open('spec.textproto', 'r') as f:
 spec_text = f.read()

with TraceProcessor(trace='my_trace.pftrace', config=config) as tp:
 # 请求一个、一些或所有生成的 metrics。
 summary = tp.trace_summary(
 specs=[spec_text],
 metric_ids=[
 "game_frame_min_duration_ns",
 "game_frame_max_duration_ns",
 "game_frame_avg_duration_ns"
 ]
 )
 print(summary)
```

TAB: Command-line shell

使用 `--add-sql-package` 标志。你可以显式列出 metrics 或使用 `all` 关键字。

```bash
trace_processor_shell --summary \
 --add-sql-package ./my_sql_modules \
 --summary-spec spec.textproto \
 --summary-metrics-v2 game_frame_min_duration_ns,game_frame_max_duration_ns,game_frame_avg_duration_ns \
 my_trace.pftrace
```

</tabs?>

## 常见模式和技巧

### 列转换

`select_columns` 字段提供了一种强大的方法来操作查询结果的列。你可以使用 SQL 表达式重命名列并执行转换。

每个 `SelectColumn` 消息有两个字段：

- `column_name_or_expression`：源中的列名或 SQL 表达式。
- `alias`：列的新名称。

#### 示例：重命名和转换列

此示例显示如何从 `slice` 表中选择 `ts` 和 `dur` 列，将 `ts` 重命名为 `timestamp`，并通过将 `dur` 从纳秒转换为毫秒来创建新列 `dur_ms`。

```protobuf
query: {
 table: {
 table_name: "slice"
 }
 select_columns: {
 column_name_or_expression: "ts"
 alias: "timestamp"
 }
 select_columns: {
 column_name_or_expression: "dur / 1000"
 alias: "dur_ms"
 }
}
```

### 使用 `interval_intersect` 分析时间间隔

常见的分析模式是分析来自一个源（例如，CPU 使用率）的数据在来自另一个源（例如，"关键用户旅程"slice）的特定时间窗口内。`interval_intersect` 查询使这变得容易。

它的工作原理是采用一个 `base` 查询和一个或多个 `interval` 查询。结果仅包含与 _每个_ `interval` 查询的至少一行在时间上重叠的 `base` 查询的行。

**用例：**

- 在定义的 CUJ 期间计算特定线程的 CPU 使用率
- 分析用户交互（由 slice 定义）期间的进程内存消耗
- 查找仅在多个条件同时为真时发生的系统事件（例如，"应用程序在前台" AND "滚动活动"）。

#### 示例：特定 CUJ Slice 期间的 CPU 时间

此示例演示如何使用 `interval_intersect` 查找线程 `bar` 在来自 "system_server" 进程的任何 "baz_*" slice 的持续时间内的总 CPU 时间。

```protobuf
// 在 id 为 "bar_cpu_time_during_baz_cujs" 的 metric_spec 中
query: {
 interval_intersect: {
 base: {
 // 基础数据是每个线程的 CPU 时间。
 table: {
 table_name: "thread_slice_cpu_time"
 }
 referenced_modules: "slices.cpu_time"
 filters: {
 column_name: "thread_name"
 op: EQUAL
 string_rhs: "bar"
 }
 }
 interval_intersect: {
 // 间隔是 "baz_*" slice。
 simple_slices: {
 slice_name_glob: "baz_*"
 process_name_glob: "system_server"
 }
 }
 }
 group_by: {
 // 我们对相交间隔的 CPU 时间求和。
 aggregates: {
 column_name: "cpu_time"
 op: SUM
 result_column_name: "total_cpu_time"
 }
 }
}
```

### 使用 `dependencies` 组合查询

`Sql` 源中的 `dependencies` 字段允许你通过从其他结构化查询组合它们来构建复杂查询。这对于将复杂分析分解为更小的、可重用的部分特别有用。

每个依赖项都有一个 `alias`，这是一个字符串，可以在 SQL 查询中用于引用依赖项的结果。SQL 查询然后可以像使用表一样使用此别名。

#### 示例：将 CPU 数据与 CUJ Slice 连接

此示例显示如何使用 `dependencies` 将 CPU 调度数据与 CUJ slice 连接。我们定义两个依赖项，一个用于 CPU 数据，一个用于 CUJ slice，然后在主 SQL 查询中连接它们。

```protobuf
query: {
 sql: {
 sql: "SELECT s.id, s.ts, s.dur, t.track_name FROM $slice_table s JOIN $track_table t ON s.track_id = t.id"
 column_names: "id"
 column_names: "ts"
 column_names: "dur"
 column_names: "track_name"
 dependencies: {
 alias: "slice_table"
 query: {
 table: {
 table_name: "slice"
 }
 }
 }
 dependencies: {
 alias: "track_table"
 query: {
 table: {
 table_name: "track"
 }
 }
 }
 }
}
```

### 添加 trace 范围的元数据

你可以将键值元数据添加到汇总中，以为 metrics 提供上下文，例如设备型号或操作系统版本。这在分析多个 trace 时特别有用，因为它允许你基于此元数据分组或过滤结果。

元数据与你在同一运行中请求的任何 metrics 一起计算。

**1. 在规范中定义元数据查询：**

此查询必须返回 "key" 和 "value" 列。

```protobuf
// 在 spec.textproto 中,与你的 metric_spec 定义一起
query {
 id: "device_info_query"
 sql {
 sql: "SELECT 'device_name' AS key, 'Pixel Test' AS value"
 column_names: "key"
 column_names: "value"
 }
}
```

**2. 使用 metrics 和元数据运行汇总：**

运行汇总时，你指定要计算的 metrics 和用于元数据的查询。

<?tabs>

TAB: Python API

传递 `metric_ids` 和 `metadata_query_id`:

```python
summary = tp.trace_summary(
 specs=[spec_text],
 metric_ids=["game_frame_avg_duration_ns"],
 metadata_query_id="device_info_query"
)
```

TAB: Command-line shell

使用 `--summary-metrics-v2` 和 `--summary-metadata-query`:

```bash
trace_processor_shell --summary \\
 --summary-spec spec.textproto \\
 --summary-metrics-v2 game_frame_avg_duration_ns \\
 --summary-metadata-query device_info_query \\
 my_trace.pftrace
```

</tabs?>

### 输出格式

汇总的结果是 `TraceSummary` protobuf 消息。此消息包含 `metric_bundles` 字段，这是一个 `TraceMetricV2Bundle` 消息列表。

每个 bundle 可以包含一起计算的一个或多个 metrics 的结果。使用 `TraceMetricV2TemplateSpec` 是创建 bundle 的最常见方式。从单个模板生成的所有 metrics 都自动放置在同一个 bundle 中，共享相同的 `specs` 和 `row` 结构。这非常高效，因为维度值通常是重复的，每行只写入一次。

#### 示例输出

对于 `memory_per_process` 模板示例，输出 `TraceSummary` 将包含一个 `TraceMetricV2Bundle`，如下所示：

```protobuf
# 在 TraceSummary 的 metric_bundles 字段中:
metric_bundles {
 # 模板生成的所有三个 metrics 的规范。
 specs {
 id: "memory_per_process_min_rss_and_swap"
 dimensions: "process_name"
 value: "min_rss_and_swap"
 # ... 查询详细信息 ...
 }
 specs {
 id: "memory_per_process_max_rss_and_swap"
 dimensions: "process_name"
 value: "max_rss_and_swap"
 # ... 查询详细信息 ...
 }
 specs {
 id: "memory_per_process_avg_rss_and_swap"
 dimensions: "process_name"
 value: "avg_rss_and_swap"
 # ... 查询详细信息 ...
 }
 # 每行包含一组维度和三个值，对应于
 # `specs` 中的三个 metrics。
 row {
 values { double_value: 100000 } # min
 values { double_value: 200000 } # max
 values { double_value: 123456.789 } # avg
 dimension { string_value: "com.example.app" }
 }
 row {
 values { double_value: 80000 } # min
 values { double_value: 150000 } # max
 values { double_value: 98765.432 } # avg
 dimension { string_value: "system_server" }
 }
 # ...
}
```

## 与旧版 metrics 系统的比较

Perfetto 以前有一个不同的系统来计算 metrics，通常称为"v1 metrics"。Trace 汇总是此系统的后继者，设计为更健壮且更易于使用。

以下是主要区别：

- **输出架构** ：旧系统要求用户定义自己的输出 protobuf 架构。这很强大，但学习曲线陡峭，导致不一致、难以维护的输出。Trace 汇总使用单个、定义良好的输出 proto（`TraceSummary`），确保所有汇总的结构一致。
- **易于使用** ：使用 trace 汇总，你不需要为输出编写或管理任何 `.proto` 文件。你只需要定义要计算的数据（查询）及其形状（维度和值）。Perfetto 处理其余部分。
- **灵活性与工具** ：虽然旧系统在输出结构方面提供了更多的灵活性，但这是以可工具化为代价的。trace 汇总的标准化输出使构建用于分析、可视化和回归跟踪的可靠、长期工具变得容易得多。

## 参考

### 运行汇总

你可以使用不同的 Perfetto 工具计算汇总。

<?tabs>

TAB: Python API

对于编程工作流，使用 `TraceProcessor` 类的 `trace_summary` 方法。

```python
from perfetto.trace_processor import TraceProcessor

# 假设 'tp' 是一个初始化的 TraceProcessor 实例
# 而 'spec_text' 包含你的 TraceSummarySpec。

summary_proto = tp.trace_summary(
 specs=[spec_text],
 metric_ids=["example_metric"],
 metadata_query_id="device_info_query"
)

print(summary_proto)
```

`trace_summary` 方法接受以下参数：

- **specs** ： `TraceSummarySpec` 定义的列表（作为文本或字节）。
- **metric_ids** ： 要计算的可选 metrics ID 列表。如果为 `None`，则计算规范中的所有 metrics。
- **metadata_query_id** ： 用于 trace 范围元数据的查询的可选 ID。

TAB: Command-line shell

`trace_processor_shell` 允许你使用专用标志从 trace 文件计算 trace 汇总。

- **按 ID 运行特定 metrics** ：使用 `--summary-metrics-v2` 标志提供逗号分隔的 metrics ID 列表。
 ```bash
 trace_processor_shell --summary \\
 --summary-spec YOUR_SPEC_FILE \\
 --summary-metrics-v2 METRIC_ID_1,METRIC_ID_2 \\
 TRACE_FILE
 ```
- **运行规范中定义的所有 metrics** ：使用关键字 `all`。
 ```bash
 trace_processor_shell --summary \\
 --summary-spec YOUR_SPEC_FILE \\
 --summary-metrics-v2 all \\
 TRACE_FILE
 ```
- **输出格式** ：使用 `--summary-format` 控制输出格式。
  - `text`：人类可读的文本 protobuf(默认)。
  - `binary`：二进制 protobuf。

</tabs?>

### [`TraceSummarySpec`](/protos/perfetto/trace_summary/file.proto)

用于配置汇总的顶级消息。它包含：

- **`metric_spec` (repeated
 [`TraceMetricV2Spec`](/protos/perfetto/trace_summary/v2_metric.proto))**:
 定义各个 metrics。
- **`query` (repeated
 [`PerfettoSqlStructuredQuery`](/protos/perfetto/perfetto_sql/structured_query.proto))**:
 定义可以被 metrics 引用或用于 trace 范围元数据的共享查询。

### [`TraceSummary`](/protos/perfetto/trace_summary/file.proto)

汇总输出的顶级消息。它包含：

- **`metric_bundles` (repeated
 [`TraceMetricV2Bundle`](/protos/perfetto/trace_summary/v2_metric.proto))**:
 每个 metrics 的计算结果。
- **`metadata` (repeated `Metadata`)** ：trace 级元数据的键值对。

### [`TraceMetricV2Spec`](/protos/perfetto/trace_summary/v2_metric.proto)

定义单个 metrics。

- **`id` (string)** ：metrics 的唯一标识符。
- **`dimensions` (repeated string)** ：作为维度的列。
- **`value` (string)** ：包含 metrics 数值值的列。
- **`unit` (oneof)** ：metrics 值的单位（例如，`TIME_NANOS`、`BYTES`）。也可以是 `custom_unit` 字符串。
- **`polarity` (enum)** ：较高还是较低的值更好（例如，`HIGHER_IS_BETTER`、`LOWER_IS_BETTER`）。
- **`query`
 ([`PerfettoSqlStructuredQuery`](/protos/perfetto/perfetto_sql/structured_query.proto))**:
 计算数据的查询。

### [`TraceMetricV2TemplateSpec`](/protos/perfetto/trace_summary/v2_metric.proto)

定义用于从单个共享配置生成多个相关 metrics 的模板。当你有几个共享相同查询和维度的 metrics 时，这对于减少重复很有用。

使用模板会自动将生成的 metrics 捆绑到输出中的单个 [`TraceMetricV2Bundle`](/protos/perfetto/trace_summary/v2_metric.proto) 中。

- **`id_prefix` (string)** ：所有生成 metrics 的 ID 的前缀。
- **`dimensions` (repeated string)** ：所有 metrics 的共享维度。
- **`value_columns` (repeated string)** ：查询中的列列表。每列将使用 ID `<id_prefix>_<value_column>` 生成唯一的 metrics。
- **`value_column_specs` (repeated `ValueColumnSpec`)** ：值列规范的列表，允许每个列具有唯一的 `unit` 和 `polarity`。
- **`query`
 ([`PerfettoSqlStructuredQuery`](/protos/perfetto/perfetto_sql/structured_query.proto))**:
 计算所有 metrics 数据的共享查询。

### [`TraceMetricV2Bundle`](/protos/perfetto/trace_summary/v2_metric.proto)

包含捆绑在一起的一个或多个 metrics 的结果。

- **`specs` (repeated `TraceMetricV2Spec`)** ：bundle 中所有 metrics 的规范。
- **`row` (repeated `Row`)** ：每行包含维度值和该组维度的所有 metrics 值。

### [`PerfettoSqlStructuredQuery`](/protos/perfetto/perfetto_sql/structured_query.proto)

`PerfettoSqlStructuredQuery` 消息提供了一种结构化的方法来定义 PerfettoSQL 查询。它是通过定义数据 `source` 然后选择性地应用 `filters`、`group_by` 操作和 `select_columns` 转换来构建的。

#### 查询源

查询的源可以是以下之一：

- **table** ：PerfettoSQL 表或视图。
- **sql** ：任意 SQL `SELECT` 语句。
- **simple_slices** ：查询 `slice` 表的便利方法。
- **inner_query** ：嵌套结构化查询。
- **inner_query_id** ：对共享结构化查询的引用。
- **interval_intersect** ：`base` 数据源与一个或多个 `interval` 数据源的基于时间的交集。

#### 查询操作

这些操作按顺序应用于来自源的数据：

- **filters** ：用于过滤行的条件列表。
- **group_by** ：对行进行分组并应用聚合函数。
- **select_columns** ：选择并可选地重命名列。

#### 聚合运算符

`group_by` 操作允许你使用以下聚合函数：

| 运算符 | 描述 |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `COUNT` | 计算每个组中的行数。如果未指定 `column_name`，则变为 `COUNT(*)`(计算所有行)。 |
| `SUM` | 计算数值列的总和。 |
| `MIN` | 查找数值列的最小值。 |
| `MAX` | 查找数值列的最大值。 |
| `MEAN` | 计算数值列的平均值。 |
| `MEDIAN` | 计算数值列的第 50 百分位数。 |
| `DURATION_WEIGHTED_MEAN` | 计算数值列的持续时间加权平均值。这对于应根据持续时间加权的时序数据很有用。 |
| `PERCENTILE` | 计算数值列的给定百分位数。百分位数在 `Aggregate` 消息的 `percentile` 字段中指定。 |

##### 聚合字段要求

- **COUNT** ：`column_name` 是可选的。如果省略，则默认为 `COUNT(*)`。
- **`SUM`、`MIN`、`MAX`、`MEAN`、`MEDIAN`、`DURATION_WEIGHTED_MEAN`** ：需要 `column_name`。
- **PERCENTILE** ：需要 `column_name` 和 `percentile`。

##### 示例：计算第 99 百分位数

此示例显示如何计算 `slice` 表中 `dur` 列的第 99 百分位数。

```protobuf
query: {
 table: {
 table_name: "slice"
 }
 group_by: {
 aggregates: {
 column_name: "dur"
 op: PERCENTILE
 result_column_name: "p99_dur"
 percentile: 99
 }
 }
}
```
