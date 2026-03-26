# Trace Processor (Python)

Trace Processor Python API 构建在 Trace Processor [C++ 库](/docs/analysis/trace-processor.md）之上。通过与 Python 集成，该库允许利用 Python 丰富的数据分析生态系统来处理 trace。

## 设置

```
pip install perfetto
```

NOTE: 该 API 仅与 Python3 兼容。

API 的主要入口点是 `TraceProcessor` 类。

## 示例用法

以下示例演示了 Python API 的基本用法。

### 查询 Slice

此示例展示如何查询 slice 并打印其名称。

```python
from perfetto.trace_processor import TraceProcessor
tp = TraceProcessor(trace='trace.perfetto-trace')

qr_it = tp.query('SELECT name FROM slice')
for row in qr_it:
 print(row.name)
```

**输出**

```
eglSwapBuffersWithDamageKHR
onMessageReceived
queueBuffer
bufferLoad
query
...
```

### 查询为 Pandas DataFrame

对于更高级的分析，你可以将查询结果转换为 Pandas DataFrame。

```python
from perfetto.trace_processor import TraceProcessor
tp = TraceProcessor(trace='trace.perfetto-trace')

qr_it = tp.query('SELECT ts, name FROM slice')
qr_df = qr_it.as_pandas_dataframe()
print(qr_df.to_string())
```

**输出**

```
ts name
-------------------- ---------------------------
 261187017446933 eglSwapBuffersWithDamageKHR
 261187017518340 onMessageReceived
 261187020825163 queueBuffer
 261187021345235 bufferLoad
 261187121345235 query
 ...
```

## 初始化

`TraceProcessor` 可以通过多种方式初始化，具体取决于 trace 的位置，以及你是想连接到现有的 `trace_processor` 实例还是启动一个新的实例。

**1. 使用 trace 文件或对象（启动新的 `trace_processor` 实例）：**

这是最常见的用例。可以通过以下几种方式提供 trace：

- trace 文件的路径： `TraceProcessor(trace='trace.perfetto-trace')`
- 文件类对象（例如，`io.BytesIO`）: `TraceProcessor(trace=file_obj)`
- 生成字节的生成器： `TraceProcessor(trace=byte_generator)`
- trace URI: `TraceProcessor(trace='resolver_name:key=value')`

```python
from perfetto.trace_processor import TraceProcessor

# 使用 trace 文件路径初始化 TraceProcessor
tp = TraceProcessor(trace='trace.perfetto-trace')
```

**2. 连接到正在运行的 `trace_processor` 实例：**

如果你已经有一个正在运行的 `trace_processor` 实例（例如，从命令行启动），可以通过提供其地址来连接它。

```python
# 连接到正在运行的实例
tp = TraceProcessor(addr='localhost:9001')

# 连接到正在运行的实例并向其加载新的 trace
tp = TraceProcessor(trace='trace.perfetto-trace', addr='localhost:9001')
```

### 配置

可以使用 `TraceProcessorConfig` 类自定义 `TraceProcessor`。

```python
from perfetto.trace_processor import TraceProcessor, TraceProcessorConfig, SqlPackage

config = TraceProcessorConfig(
 bin_path='/path/to/trace_processor', # 自定义二进制文件的路径
 verbose=True,
 add_sql_packages=[
 '/path/to/my/sql/modules', # 使用目录名称作为包名称
 SqlPackage('/path/to/other', package='custom.pkg') # 自定义包名称
 ]
)
tp = TraceProcessor(trace='trace.perfetto-trace', config=config)
```

`TraceProcessorConfig` 提供了许多用于自定义 `trace_processor` 实例的选项。其中最重要的是：

- `add_sql_packages`：要加载的 PerfettoSQL 包列表。每个元素可以是字符串路径（目录名称成为包名称）或 `SqlPackage` 对象（允许指定自定义包名称）。这些包中的所有 SQL 模块都可以使用 `INCLUDE PERFETTO MODULE` PerfettoSQL 语句包含。
- `verbose`：如果为 `True`，`trace_processor` 将向 stdout 打印详细输出。这对于调试和查看更详细的错误消息很有用。
- `bin_path`: `trace_processor` 二进制文件的路径。如果未提供，将下载最新的预构建版本。

## API

`TraceProcessor` 类提供了多种函数来与加载的 trace 交互。

### 查询

`query()` 函数接受 SQL 查询作为输入，并返回结果行的迭代器。有关如何编写查询的更多信息，请参阅 [PerfettoSQL 入门指南](perfetto-sql-getting-started.md)。

```python
from perfetto.trace_processor import TraceProcessor
tp = TraceProcessor(trace='trace.perfetto-trace')

qr_it = tp.query('SELECT ts, dur, name FROM slice')
for row in qr_it:
 print(row.ts, row.dur, row.name)
```

**输出**

```
261187017446933 358594 eglSwapBuffersWithDamageKHR
261187017518340 357 onMessageReceived
261187020825163 9948 queueBuffer
261187021345235 642 bufferLoad
261187121345235 153 query
...
```

`QueryResultIterator` 也可以转换为 Pandas DataFrame，这对于数据profile 和可视化很有用。这需要安装 `numpy` 和 `pandas`。

```python
# 需要 pandas 和 numpy
# pip install pandas numpy
import numpy as np

qr_it = tp.query('SELECT ts, dur, name FROM slice')
qr_df = qr_it.as_pandas_dataframe()
print(qr_df.to_string())
```

**输出**

```
ts dur name
-------------------- -------------------- ---------------------------
 261187017446933 358594 eglSwapBuffersWithDamageKHR
 261187017518340 357 onMessageReceived
 261187020825163 9948 queueBuffer
 261187021345235 642 bufferLoad
 261187121345235 153 query
 ...
```

可以使用 Pandas DataFrame 轻松地从 trace 数据创建可视化。

```python
from perfetto.trace_processor import TraceProcessor
tp = TraceProcessor(trace='trace.perfetto-trace')

qr_it = tp.query('SELECT ts, value FROM counter WHERE track_id=50')
qr_df = qr_it.as_pandas_dataframe()
qr_df = qr_df.replace(np.nan,0)
qr_df = qr_df.set_index('ts')['value'].plot()
```

**输出**

![从查询结果创建的图表](/docs/images/example_pd_graph.png)

### Trace 汇总

`trace_summary()` 函数计算 trace 的结构化汇总。这对于创建供其他工具使用的结构化 protobuf 消息很有用。此函数替换了已弃用的 `metric()` 函数。

有关此功能的深入探讨，请参阅 [Trace 汇总文档](/docs/analysis/trace-summary.md)。

```python
from perfetto.trace_processor import TraceProcessor

spec = """
metric_spec {
 id: "memory_per_process"
 dimensions: "process_name"
 value: "avg_rss_and_swap"
 query: {
 table: {
 table_name: "memory_rss_and_swap_per_process"
 module_name: "linux.memory.process"
 }
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
"""
with TraceProcessor(trace='trace.perfetto-trace') as tp:
 summary = tp.trace_summary(specs=[spec])
 print(summary)
```

### Metatracing

Metatracing 允许 Tracing `trace_processor` 本身的性能。

```python
# 启用 metatracing
tp.enable_metatrace()

# 运行一些查询
tp.query('select * from slice')
tp.query('select * from slice')

# 禁用并读取 metatrace
metatrace_bytes = tp.disable_and_read_metatrace()

# 你现在可以将其加载到另一个 TraceProcessor 实例中
with open('tp_metatrace.pftrace', 'wb') as f:
 f.write(metatrace_bytes)
tp_meta = TraceProcessor(trace='tp_metatrace.pftrace')
tp_meta.query('select * from slice')
```

### metric（已弃用）

`metric()` 函数接受 trace metrics 列表并将结果以 Protobuf 格式返回。

**注意：**此函数已弃用，但没有计划删除它。建议改用 `trace_summary()`，这是一个间接的替代方案，以更灵活的方式提供许多相同的功能。

```python
from perfetto.trace_processor import TraceProcessor
tp = TraceProcessor(trace='trace.perfetto-trace')

ad_cpu_metrics = tp.metric(['android_cpu'])
print(ad_cpu_metrics)
```

**输出**

```
metrics {
 android_cpu {
 process_info {
 name: "/system/bin/init"
 threads {
 name: "init"
 core {
 id: 1
 metrics {
 mcycles: 1
 runtime_ns: 570365
 min_freq_khz: 1900800
 max_freq_khz: 1900800
 avg_freq_khz: 1902017
 }
 }
 core {
 id: 3
 metrics {
 mcycles: 0
 runtime_ns: 366406
 min_freq_khz: 1900800
 max_freq_khz: 1900800
 avg_freq_khz: 1902908
 }
 }
 ...
 }
 ...
 }
 process_info {
 name: "/system/bin/logd"
 threads {
 name: "logd.writer"
 core {
 id: 0
 metrics {
 mcycles: 8
 runtime_ns: 33842357
 min_freq_khz: 595200
 max_freq_khz: 1900800
 avg_freq_khz: 1891825
 }
 }
 core {
 id: 1
 metrics {
 mcycles: 9
 runtime_ns: 36019300
 min_freq_khz: 1171200
 max_freq_khz: 1900800
 avg_freq_khz: 1887969
 }
 }
 ...
 }
 ...
 }
 ...
 }
}
```
