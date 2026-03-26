# Trace Processor (C++)

_Trace Processor 是一个 C++ 库（[/src/trace_processor](/src/trace_processor)），它摄取以多种格式编码的 trace，并公开 SQL 接口来查询存储在一组一致表中的 trace 事件。它还具有其他功能，包括计算 trace 汇总、使用用户友好的描述为 trace 添加注释以及从 trace 的内容派生新事件。_

![Trace processor 框图](/docs/images/trace-processor.png)

## Shell 入门指南

`trace_processor` shell 是一个命令行二进制文件，它包装 C++ 库，提供一种方便的方法来交互式分析 trace。

### 下载 shell

可以从 Perfetto 网站下载 shell:

```bash
# 下载预构建版本(仅限 Linux 和 Mac)
curl -LO https://get.perfetto.dev/trace_processor
chmod +x ./trace_processor
```

### 运行 shell

下载后，你可以立即使用它打开 trace 文件：

```bash
# 启动交互式 shell
./trace_processor trace.perfetto-trace
```

这将打开一个交互式 SQL shell，你可以在其中查询 trace。有关如何编写查询的更多信息，请参阅 [PerfettoSQL 入门指南](perfetto-sql-getting-started.md)。

例如，要查看 trace 中的所有 slice，你可以运行以下查询：

```sql
> SELECT ts, dur, name FROM slice LIMIT 10;
ts dur name
-------------------- -------------------- ---------------------------
 261187017446933 358594 eglSwapBuffersWithDamageKHR
 261187017518340 357 onMessageReceived
 261187020825163 9948 queueBuffer
 261187021345235 642 bufferLoad
 261187121345235 153 query
...
```

或者，要查看所有 counter 的值：

```sql
> SELECT ts, value FROM counter LIMIT 10;
ts value
-------------------- --------------------
 261187012149954 1454.000000
 261187012399172 4232.000000
 261187012447402 14304.000000
 261187012535839 15490.000000
 261187012590890 17490.000000
 261187012590890 16590.000000
...
```


## Python API

trace processor 的 C++ 库也通过 Python 公开。这在[单独的页面](/docs/analysis/trace-processor-python.md）上有文档说明。

## 测试

Trace processor 主要通过两种方式进行测试：

1. 低级构建块的单元测试
2. 解析 trace 并检查查询输出的"差异"测试

### 单元测试

对 trace processor 进行单元测试与 Perfetto 的其他部分和其他 C++ 项目相同。但是，与 Perfetto 的其余部分不同，trace processor 中的单元测试相对较轻。

随着时间的推移，我们发现单元测试在处理解析 trace 的代码时通常太脆弱，导致重构时需要进行痛苦的机械更改。

因此，我们选择专注于大多数领域的差异测试（例如，解析事件、测试表的架构等），并且仅对 trace processor 的其余部分构建的低级构建块使用单元测试。

### 差异测试

差异测试本质上是 trace processor 的集成测试，也是 trace processor 的主要测试方式。

每个差异测试将 a) trace 文件 b) 查询文件 _或_ metrics 名称作为输入。它运行 `trace_processor_shell` 来解析 trace，然后执行查询/metrics。然后将结果与"golden"文件进行比较，并突出显示任何差异。

所有差异测试都在 [test/trace_processor](/test/trace_processor) 下组织在 `tests{_category name}.py` 文件中，作为每个文件中类的方法，并由脚本 [`tools/diff_test_trace_processor.py`](/tools/diff_test_trace_processor.py) 运行。要添加新测试，只需在合适的 python 测试文件中添加一个以 `test_` 开头的新方法。

方法不能接受参数，并且必须返回 `DiffTestBlueprint`:

```python
class DiffTestBlueprint:
 trace: Union[Path, Json, Systrace, TextProto]
 query: Union[str, Path, Metric]
 out: Union[Path, Json, Csv, TextProto]
```

_Trace_ 和 _Out_ ：对于除 `Path` 之外的每种类型，对象的内容将被视为文件内容，因此它必须遵循相同的规则。

_Query_ ：对于 metrics 测试，提供 metrics 名称就足够了。对于查询测试，可以是原始 SQL 语句，例如 `"SELECT * FROM SLICE"` 或 `.sql` 文件的路径。

NOTE: `trace_processor_shell` 和关联的 proto 描述符需要在运行 `tools/diff_test_trace_processor.py` 之前构建。最简单的方法是最初并在对 trace processor 代码的每次更改时运行 `tools/ninja -C <out directory>`。

#### 选择在哪里添加差异测试

`diff_tests/` 文件夹包含四个目录，对应于 trace processor 的不同领域。

1. **stdlib**： 专注于测试 Perfetto 标准库的测试用例，包括前奏和常规模块。此文件夹中的子目录通常应对应于 `perfetto_sql/stdlib` 中的目录。
2. **parser**： 专注于确保正确解析不同的 trace 文件并填充相应的内置表的测试。
3. **syntax**： 专注于测试 PerfettoSQL 核心语法的测试（即 `CREATE PERFETTO TABLE` 或 `CREATE PERFETTO FUNCTION`）。

**场景**： 正在添加一个新的 stdlib 模块 `foo/bar.sql`。

**答案**： 将测试添加到 `stdlib/foo/bar_tests.py` 文件。

**场景**： 正在解析一个新事件，测试的重点是确保正确解析该事件。

**答案**： 在 `parser` 子目录之一中添加测试。如果存在，则更喜欢将测试添加到现有的相关目录（即 `sched`、`power`）。

**场景**： 正在添加一个新的动态表，测试的重点是确保正确计算动态表。..

**答案**： 将测试添加到 `stdlib/dynamic_tables` 文件夹

**场景**： 正在修改 trace processor 的内部，测试是为了确保 trace processor 正确过滤/排序重要的内置表。

**答案**： 将测试添加到 `parser/core_tables` 文件夹。

## {#embedding} 嵌入

### 构建

与 Perfetto 中的所有组件一样，trace processor 可以在几个构建系统中构建：

- GN(原生系统)
- Bazel
- 作为 Android 树的一部分

trace processor 作为静态库 `//:trace_processor` 公开给 Bazel，在 GN 中公开为 `src/trace_processor:trace_processor`；它不公开给 Android（但欢迎添加对此支持的补丁）。

trace processor 还作为 WASM 目标 `src/trace_processor:trace_processor_wasm` 构建，用于 Perfetto UI；欢迎为其他支持的构建系统添加支持的补丁。

trace processor 还作为 shell 二进制文件 `trace_processor_shell` 构建，它支持本文档其他部分描述的 `trace_processor` 工具。这作为 `trace_processor_shell` 目标公开给 Android，作为 `//:trace_processor_shell` 公开给 Bazel，在 GN 中公开为 `src/trace_processor:trace_processor_shell`。

### 库结构

trace processor 库围绕 `TraceProcessor` 类构建；trace processor 公开的所有 API 方法都是此类的成员函数。

此类的 C++ 头文件分为两个文件：[include/perfetto/trace_processor/trace_processor_storage.h](/include/perfetto/trace_processor/trace_processor_storage.h) 和 [include/perfetto/trace_processor/trace_processor.h](/include/perfetto/trace_processor/trace_processor.h)。

### 读取 trace

要将 trace 摄取到 trace processor 中，可以多次调用 `Parse` 函数，使用 trace 的块，并在末尾调用 `NotifyEndOfFile`。

由于这是一个常见任务，因此在 [include/perfetto/trace_processor/read_trace.h](/include/perfetto/trace_processor/read_trace.h) 中提供了辅助函数 `ReadTrace`。这将从文件系统直接读取 trace 文件，并调用适当的 `TraceProcessor`函数来执行解析。

### 执行查询

可以通过 SQL 语句调用 `ExecuteQuery` 函数来执行查询。这将返回一个迭代器，可用于以流式方式检索行。

WARNING: 嵌入者应确保在迭代器上调用任何其他函数之前使用 `Next` 前向迭代器。

WARNING: 嵌入者应确保在每一行之后和迭代结束时检查迭代器的状态，以验证查询是否成功。