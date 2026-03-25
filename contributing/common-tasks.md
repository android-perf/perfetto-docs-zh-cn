# 常见任务

大多数对 Perfetto 的贡献都属于以下类别之一。

## UI

由于 UI 的插件化，对 UI 的大部分贡献应该与创建/修改插件有关。
转到 [UI 插件页面](ui-plugins) 了解如何操作。

## Trace Processor

### 贡献给 SQL 标准库

1. 在 `perfetto/src/trace_processor/stdlib/` 内添加或编辑 SQL 文件。该 SQL 文件将是一个新的标准库模块。
2. 对于现有包内的新文件，将该文件添加到相应的 `BUILD.gn` 中。
3. 对于新包（`/stdlib/` 的子目录），包名（目录名）必须添加到 `/stdlib/BUILD.gn` 中的列表中。

标准库内的文件必须以非常特定的方式格式化，因为其结构用于生成文档。有预提交检查，但它们并非万无一失。

- 运行文件不能生成任何数据。内部只能有 `CREATE PERFETTO {FUNCTION|TABLE|VIEW|MACRO}` 语句。
- 每个标准库对象的名称必须以 `{module_name}_` 开头，对于内部对象以下划线（`_`）为前缀。
 名称必须仅包含大小写字母和下划线。当包含模块时（使用 `INCLUDE PERFETTO MODULE`），内部对象不应被视为 API。
- 每个表或视图都应该有 [架构](/docs/analysis/perfetto-sql-syntax.md#tableview-schema)。

#### 文档

- 每个非内部对象及其函数参数和架构中的列都必须带有 SQL 注释，对其进行文档化。
- 任何文本都将被解析为 markdown，因此鼓励使用 markdown 功能（代码、链接、列表）。
  除描述外的任何内容中的空格都将被忽略，因此可以整齐地格式化注释。
  如果带有描述的行超过 80 个字符，可以在后续行中继续描述。
  - **表/视图**：每个都必须有架构、对象描述和架构中每个列定义上方的注释。
    - 描述是 `CREATE PERFETTO {TABLE,VIEW}` 语句上方注释中的任何文本。
    - 列的注释是架构中列定义上方的文本。
  - **标量函数**：每个都必须有函数描述和返回值描述，按此顺序。
    - 函数描述是 `CREATE PERFETTO FUNCTION` 语句上方注释中的任何文本。
    - 每个参数必须有参数定义正上方的注释行。
    - 返回注释应紧接在 `RETURNS` 之前。
  - **表函数**：每个都必须有函数描述、参数列表（名称、类型、描述）和列列表。
    - 函数描述是 `CREATE PERFETTO FUNCTION` 语句上方注释中的任何文本。
    - 每个参数必须有参数定义正上方的注释行。
    - 每个列必须有列定义正上方的注释行。

NOTE: 导入描述外的换行将被忽略。

模块 `android` 中格式正确的视图示例：

```sql
-- 计算每个进程的 Binder 事务。
CREATE PERFETTO VIEW android_binder_metrics_by_process(
 -- 启动 binder 事务的进程名称。
 process_name STRING,
 -- 启动 binder 事务的进程的 PID。
 pid INT,
 -- 带有 binder 事务的 slice 名称。
 slice_name STRING,
 -- slice 中进程内的 binder 事务数。
 event_count INT
) AS
SELECT
 process.name AS process_name,
 process.pid AS pid,
 slice.name AS slice_name,
 COUNT(*) AS event_count
FROM slice
JOIN thread_track ON slice.track_id = thread_track.id
JOIN thread ON thread.utid = thread_track.utid
JOIN process ON thread.upid = process.upid
WHERE
 slice.name GLOB 'binder*'
GROUP BY
 process_name,
 slice_name;
```

模块 `android` 中的表函数示例：

```sql
-- 给定启动 ID 和 slice 名称的 GLOB,返回匹配 slice 的列。
CREATE PERFETTO FUNCTION ANDROID_SLICES_FOR_LAUNCH_AND_SLICE_NAME(
 -- 启动的 ID。
 launch_id INT,
 -- 带有启动的 slice 名称。
 slice_name STRING
)
RETURNS TABLE(
 -- 带有启动的 slice 名称。
 slice_name STRING,
 -- slice 开始的时间戳。
 slice_ts TIMESTAMP,
 -- slice 的持续时间。
 slice_dur DURATION,
 -- 带有 slice 的线程名称。
 thread_name STRING,
 -- 参数集 ID。
 arg_set_id ARGSETID
)
AS
SELECT
 slice_name,
 slice_ts,
 slice_dur,
 thread_name,
 arg_set_id
FROM thread_slices_for_all_launches
WHERE launch_id = $launch_id AND slice_name GLOB $slice_name;
```

### 添加新的 trace processor 表

1. 通过复制其中一个现有的宏定义，在 [src/trace_processor/tables](/src/trace_processor/tables) 中的相应头文件中创建新表。

- 确保了解是否需要根表或派生表，并复制适当的一个。有关更多信息，请参阅 [trace processor](/docs/analysis/trace-processor.md) 文档。

2. 在 [TraceProcessorImpl 类](/src/trace_processor/trace_processor_impl.cc) 的构造函数中向 trace processor 注册表。
3. 如果还实现事件到表中的摄取：
   1. 修改 [src/trace_processor/importers](/src/trace_processor/importers) 中的相应解析器类，并添加代码以将行添加到新添加的表中。
   2. 为添加的解析代码和表添加新的差异测试。
   3. 使用 `tools/diff_test_trace_processor.py <path to trace processor shell binary>` 运行新添加的测试。
4. 像往常一样上传和合并你的更改。

### 更新 `TRACE_PROCESSOR_CURRENT_API_VERSION`

通常，你不必担心 UI 和 `trace_processor` 之间的版本偏差，因为它们在同一提交处一起构建。但是，当使用允许原生 `trace_processor` 实例与 UI 一起使用的 `--httpd` 模式时，可能会发生版本偏差。

常见情况是 UI 比 `trace_processor` 更新，并且依赖于新的表定义。在 `--httpd` 模式下使用旧版本的 `trace_processor` 时，UI 尝试查询不存在的表时会崩溃。为了避免这种情况，我们使用版本号。如果 `trace_processor` 报告的版本号低于 UI 构建时的版本号，我们会提示用户更新。

1. 转到 `protos/perfetto/trace_processor/trace_processor.proto`
2. 增加 `TRACE_PROCESSOR_CURRENT_API_VERSION`
3. 添加注释解释发生了什么变化。

### {#new-metric} 添加新的基于 trace 的 metric

1. 在 [protos/perfetto/metrics](/protos/perfetto/metrics) 文件夹中创建包含 metric 的 proto 文件。还应该更新相应的 `BUILD.gn` 文件。
2. 在 [protos/perfetto/metrics/metrics.proto](/protos/perfetto/metrics/metrics.proto) 中导入 proto 并为新消息添加字段。
3. 运行 `tools/gen_all out/YOUR_BUILD_DIRECTORY`。这将更新包含 proto 描述符的生成的头文件。

- NOTE: 修改任何与 metric 相关的 proto 时都必须执行此步骤。
- 如果在 `out/` 目录中看不到任何内容，你可能需要
 重新运行 `tools/setup_all_configs.py`。

4. 为 metric 在 [src/trace_processor/metrics](/src/trace_processor/metrics) 中添加新的 SQL 文件。还应该更新相应的 `BUILD.gn` 文件。

- 要了解如何编写新的 metric，请参阅 [基于 trace 的 metric 文档](/docs/analysis/metrics.md)。

5. 使用 `tools/ninja -C out/YOUR_BUILD_DIRECTORY` 构建输出目录中的所有目标。
6. 为 metric 添加新的差异测试。可以通过将文件添加到适当的 [test/trace_processor](/test/trace_processor) 子文件夹中的 `tests_*.py` 文件来完成。
7. 使用 `tools/diff_test_trace_processor.py <path to trace processor binary>` 运行新添加的测试。
8. 像往常一样上传和合并你的更改。

## Ftrace

### 添加新的 ftrace 事件

1. 找到事件的 `format` 文件。文件的位置取决于 `tracefs` 的挂载位置，但通常可以在 `/sys/kernel/debug/tracing/events/EVENT_GROUP/EVENT_NAME/format` 找到。
2. 将格式文件复制到代码库中的 `src/traced/probes/ftrace/test/data/synthetic/events/EVENT_GROUP/EVENT_NAME/format`。
3. 将事件添加到 [src/tools/ftrace_proto_gen/event_list](/src/tools/ftrace_proto_gen/event_list)。
4. 运行 `tools/run_ftrace_proto_gen`。这将更新 `protos/perfetto/trace/ftrace/ftrace_event.proto` 和 `protos/perfetto/trace/ftrace/GROUP_NAME.proto`。
5. 运行 `tools/gen_all out/YOUR_BUILD_DIRECTORY`。这将更新 `src/traced/probes/ftrace/event_info.cc` 和 `protos/perfetto/trace/perfetto_trace.proto`。
6. 如果需要在 `trace_processor` 中进行特殊处理，请更新 [src/trace_processor/importers/ftrace/ftrace_parser.cc](/src/trace_processor/importers/ftrace/ftrace_parser.cc) 以解析事件。
7. 像往常一样上传和合并你的更改。

这是一个 [示例更改](https://android-review.googlesource.com/c/platform/external/perfetto/+/3343525)，它添加了一个新事件。NOTE: Perfetto 的权威来源自该更改以来已移至 GitHub，因此虽然该更改的内容是准确的，但你应该通过 GitHub 而不是在 AOSP Gerrit 上发送补丁。

要测试你的更改，你可以在 Android 设备上 sideload 本地构建的 `tracebox` 二进制文件。有关更多详细信息，请参阅 [Android Sideloading](#sideloading)。

## {#sideloading} Android Sideloading

要在 Android 设备上测试更改（例如，添加新的 ftrace 事件时）,
你可以使用 `record_android_trace` 脚本来 sideload 本地构建的
`tracebox` 二进制文件。

1. 为 Android 构建 `tracebox`。
   有关如何为 Android 配置构建的说明，请参阅 [入门](getting-started.md#building)。
   ```bash
   # 这假设你已按照上述链接的说明配置了 out/android。
   tools/ninja -C out/android_release_arm64 tracebox
   ```

2. 使用 `record_android_trace` sideload 并采集 trace:
   ```bash
   tools/record_android_trace \
   --sideload-path out/android_release_arm64/tracebox \
   -o trace.pftrace \
   -t 10s \
   -b 32mb \
   sched/sched_switch
   ```
 `--sideload-path` 参数告诉脚本将本地构建的
 `tracebox` 二进制文件推送到设备并用于记录。

## Statsd

### 更新 statsd 描述符

Perfetto 对它不知道的 statsd 原子有有限的支持。

- 必须在配置中使用 `raw_atom_id` 引用。
- 在 trace processor 中显示为 `atom_xxx.field_yyy`。
- 仅解析顶级消息。

要更新 Perfetto 的描述符并处理来自 AOSP 的新原子而没有这些
限制：

1. 运行 `tools/update-statsd-descriptor`。
2. 像往常一样上传和合并你的更改。
