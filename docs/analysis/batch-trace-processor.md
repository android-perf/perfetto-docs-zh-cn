# Batch Trace Processor

_Batch Trace Processor 是一个 Python 库，封装了 [Trace Processor](/docs/analysis/trace-processor.md)：它允许对大量 trace（最多约 1000 个）执行快速（<1 秒）的交互式查询。_

## 安装

Batch Trace Processor 是 `perfetto` Python 库的一部分，可以通过运行以下命令安装：

```shell
pip3 install pandas # Batch Trace Processor 的前置依赖
pip3 install perfetto
```

## 加载 trace

NOTE: 如果你是 Google 员工，请查看 [go/perfetto-btp-load-internal](http://goto.corp.google.com/perfetto-btp-load-internal) 了解如何从 Google 内部源加载 trace。

加载 trace 的最简单方法是传递要加载的文件路径列表：

```python
from perfetto.batch_trace_processor.api import BatchTraceProcessor

files = [
 'traces/slow-start.pftrace',
 'traces/oom.pftrace',
 'traces/high-battery-drain.pftrace',
]
with BatchTraceProcessor(files) as btp:
 btp.query('...')
```

可以使用 [glob](https://docs.python.org/3/library/glob.html) 加载目录中的所有 trace：

```python
from perfetto.batch_trace_processor.api import BatchTraceProcessor

files = glob.glob('traces/*.pftrace')
with BatchTraceProcessor(files) as btp:
 btp.query('...')
```

NOTE: 加载过多 trace 可能会导致内存不足问题：详见[内存使用](/docs/analysis/batch-trace-processor#memory-usage）部分。

常见需求是加载位于云端的 trace 或通过向服务器发送请求加载。为了支持这种用例，可以使用 [trace URIs](/docs/analysis/batch-trace-processor#trace-uris) 加载 trace：

```python
from perfetto.batch_trace_processor.api import BatchTraceProcessor
from perfetto.batch_trace_processor.api import BatchTraceProcessorConfig
from perfetto.trace_processor.api import TraceProcessorConfig
from perfetto.trace_uri_resolver.registry import ResolverRegistry
from perfetto.trace_uri_resolver.resolver import TraceUriResolver

class FooResolver(TraceUriResolver):
 # 关于如何实现 URI resolver 的信息，请参阅下面的 "Trace URIs" 部分。

config = BatchTraceProcessorConfig(
 # 参见下面的 "Trace URIs"
)
with BatchTraceProcessor('foo:bar=1,baz=abc', config=config) as btp:
 btp.query('...')
```

## 编写查询

使用 batch trace processor 编写查询的方式与 [Python API](/docs/analysis/batch-trace-processor#python-api) 非常相似。

例如，要获取用户态 slice 的数量：

```python
>>> btp.query('select count(1) from slice')
[ count(1)
0 2092592, count(1)
0 156071, count(1)
0 121431]
```

`query` 的返回值是一个 [Pandas](https://pandas.pydata.org/) dataframe 列表，每个加载的 trace 对应一个。

常见需求是将所有 trace 扁平化为单个 dataframe，而不是每个 trace 获得一个 dataframe。为了支持这一点，可以使用 `query_and_flatten` 函数：

```python
>>> btp.query_and_flatten('select count(1) from slice')
 count(1)
0 2092592
1 156071
2 121431
```

[Polars](https://pola.rs/) DataFrames 也作为 Pandas 的替代方案受支持。`query_polars` 镜像 `query` 并返回 Polars DataFrames 列表（每个 trace 一个）；`query_and_flatten_polars` 镜像 `query_and_flatten` 并将它们连接成单个 DataFrame。Polars 支持需要一个可选依赖：

```shell
pip3 install perfetto[polars]
```

```python
>>> btp.query_polars('select count(1) from slice')
[shape: (1, 1)
┌──────────┐
│ count(1) │
│ ---      │
│ i64      │
╞══════════╡
│  2092592 │
└──────────┘, shape: (1, 1)
┌──────────┐
│ count(1) │
│ ---      │
│ i64      │
╞══════════╡
│   156071 │
└──────────┘, ...]

>>> btp.query_and_flatten_polars('select count(1) from slice')
shape: (3, 1)
┌──────────┐
│ count(1) │
│ ---      │
│ i64      │
╞══════════╡
│  2092592 │
│   156071 │
│   121431 │
└──────────┘
```

`query_and_flatten` 还会隐式添加指示来源 trace 的列。添加的确切列取决于所使用的 resolver：请查阅你的 resolver 文档以获取更多信息。

## Trace URI

Trace URIs 是 batch trace processor 的一个强大功能。URI 将 trace 的"路径"概念与文件系统解耦。相反，URI 描述了*如何*获取 trace（即通过向服务器发送 HTTP 请求、从云存储等）。

Trace URIs 的语法类似于 Web [URLs](https://en.wikipedia.org/wiki/URL)。形式上，trace URI 具有以下结构：

```
Trace URI = protocol:key1=val1(;keyn=valn)*
```

例如：

```
gcs:bucket=foo;path=bar
```

表示应使用协议 `gcs`（[Google Cloud Storage](https://cloud.google.com/storage)）获取 trace，trace 位于存储桶 `foo` 的路径 `bar` 中。

NOTE: `gcs` resolver *并未*实际包含在内：这只是作为一个易于理解的示例。

URI 只是谜题的一部分：最终 batch trace processor 仍需要 trace 的字节才能解析和查询它们。将 URI 转换为 trace 字节的工作由 *resolvers* 完成——与每个 *protocol* 关联的 Python 类，使用 URI 中的键值对来查找要解析的 trace。

默认情况下，batch trace processor 仅附带一个知道如何查找文件系统路径的 resolver；但可以轻松创建和注册自定义 resolver。有关如何执行此操作的信息，请参阅 [TraceUriResolver 类](https://cs.android.com/android/platform/superproject/main/+/main:external/perfetto/python/perfetto/trace_uri_resolver/resolver.py;l=56?q=resolver.py) 的文档。

## 内存使用

使用 batch trace processor 时，内存使用是一个需要特别注意的问题。每个加载的 trace 都完全驻留在内存中：这是使查询快速（<1 秒）的关键，即使处理数百个 trace。

这也意味着你可以加载的 trace 数量受到可用内存量的严重限制。根据经验法则，如果平均 trace 大小为 S 并且你尝试加载 N 个 trace，你将有 2 * S * N 的内存使用量。请注意，这可能根据 trace 的确切内容和大小而有很大差异。

## 高级功能

### 在 TP 和 BTP 之间共享计算

有时，将代码参数化以使用 trace processor 或 batch trace processor 会很有用。`execute` 或 `execute_and_flatten` 可用于此目的：

```python
def some_complex_calculation(tp):
 res = tp.query('...').as_pandas_dataframe()
 # ... 使用 res 进行一些计算
 return res

# |some_complex_calculation| 可以使用 [TraceProcessor] 对象调用：
tp = TraceProcessor('/foo/bar.pftrace')
some_complex_calculation(tp)

# |some_complex_calculation| 也可以传递给 |execute| 或
# |execute_and_flatten|
btp = BatchTraceProcessor(['...', '...', '...'])

# 像 |query| 一样，|execute| 每个返回一个结果。请注意，返回的
# 值*不必*是 Pandas dataframe。
[a, b, c] = btp.execute(some_complex_calculation)

# 像 |query_and_flatten| 一样，|execute_and_flatten| 将每个 trace 返回的
# Pandas dataframe 合并为单个 dataframe，添加 resolver 请求的任何列。
flattened_res = btp.execute_and_flatten(some_complex_calculation)
```
