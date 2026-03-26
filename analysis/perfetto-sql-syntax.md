# PerfettoSQL 语法
*本文档记录了 PerfettoSQL 的语法，这是一种用于 trace processor 和其他 Perfetto 分析工具查询 trace 的 SQL 方言。*

PerfettoSQL 是[SQLite 实现的 SQL 方言](https://www.sqlite.org/lang.html）的直接后代。具体来说，在 SQLite 中有效的任何 SQL 在 PerfettoSQL 中也有效。

然而，仅 SQLite 语法是不够的，原因有两个：
1. 它非常基本，例如，它不支持创建函数或宏
2. 它不能用于访问仅在 Perfetto 工具中可用的功能，例如，它不能用于创建高效的分析表、从 PerfettoSQL 标准库导入模块等。

因此，PerfettoSQL 添加了新的语法片段，使编写 SQL 查询的体验更好。所有此类添加都包含关键字 `PERFETTO` 以明确表明它们仅限 PerfettoSQL。

<!-- TODO(b/290185551)：我们应该真正谈论我们的"建议"(例如，
使用 CREATE PERFETTO TABLE 而不是 CREATE TABLE)并在某处引用它
这里。 -->

## 导入 PerfettoSQL 模块
`INCLUDE PERFETTO MODULE` 用于导入 PerfettoSQL 模块中定义的所有表/视图/函数/宏（例如，从[PerfettoSQL 标准库](/docs/analysis/stdlib-docs.autogen)）。

请注意，此语句的行为更类似于 C++ 中的 `#include` 语句，而不是 Java/Python 中的 `import` 语句。具体来说，模块中的所有对象都可以在全局命名空间中使用，而无需使用模块名称进行限定。

示例：

```sql
-- 从标准库中的 android.startup.startups 模块
-- 包含所有表/视图/函数。
INCLUDE PERFETTO MODULE android.startup.startups;

-- 使用 android.startup.startups 模块中定义的 android_startups 表。
SELECT *
FROM android_startups;
```

对于交互式开发，键可以包含通配符：
```sql
-- 包含 android/ 下的所有模块。
INCLUDE PERFETTO MODULE android.*;

-- 或所有 stdlib 模块:
INCLUDE PERFETTO MODULE *;

-- 但是，请注意，这两种模式在 stdlib 中都不允许。
```

## 类型

PerfettoSQL 支持以下类型，这些类型可用于表和视图架构、函数参数和返回类型：

| 类型 | 描述 |
|------|-------------|
| `LONG` | 64 位有符号整数 |
| `DOUBLE` | 双精度浮点数 |
| `BOOLEAN` | 布尔值（true/false） |
| `STRING` | 文本字符串 |
| `BYTES` | 二进制数据 |
| `TIMESTAMP` | 纳秒绝对时间戳 |
| `DURATION` | 纳秒持续时间 |
| `ARGSETID` | 一组参数的标识符。可以通过与 `args` 表的 `arg_set_id` 列连接来获取此集合。 |
| `ID` | 此表的 ID 列。每个表只能有一个 ID 列，其值应该是唯一的并且适合 `uint32`。 |
| `JOINID(table.column)` | 对给定表的外键引用。`table` 应该存在，应该有一个名为 `column` 的 `ID` 类型列。 |
| `ID(table.column)` | `ID` 类型的变体，它既是此表的主键，同时也是对另一个表的外键引用。当给定表基于另一个表的行子集时很有用（例如 `slice`）。 |

## 定义函数
`CREATE PERFETTO FUNCTION` 允许在 SQL 中定义函数，这些函数可以是标量（返回单个值）或表值（返回一组行）。语法类似于 PostgreSQL 或 GoogleSQL 中的语法：
- 标量： `CREATE PERFETTO FUNCTION function_name(arg_list) RETURNS return_type AS sql_select_statement;`
- 表值： `CREATE PERFETTO FUNCTION function_name(arg_list) RETURNS TABLE(column_list) AS sql_select_statement;`

`arg_list` 和 `column_list` 是任意数量的 `argument_name argument_type` 对的逗号分隔列表。

`sql_select_statement` 应该是一个有效的 SQL 语句，它可以使用 `$argument_name` 语法引用参数值。

示例：
```sql
-- 创建一个不带参数的标量函数。
CREATE PERFETTO FUNCTION constant_fn() RETURNS LONG AS SELECT 1;

-- 创建一个接受两个参数的标量函数。
CREATE PERFETTO FUNCTION add(x LONG, y LONG) RETURNS LONG AS SELECT $x + $y;

-- 创建一个不带参数的表函数
CREATE PERFETTO FUNCTION constant_tab_fn()
RETURNS TABLE(ts LONG, dur LONG) AS
SELECT column1 as ts, column2 as dur
FROM (
 VALUES
 (100, 10),
 (200, 20)
);

-- 创建一个接受一个参数的表函数
CREATE PERFETTO FUNCTION sched_by_utid(utid LONG)
RETURNS TABLE(ts LONG, dur LONG, utid LONG) AS
SELECT ts, dur, utid
FROM sched
WHERE utid = $utid;
```

## 创建高效表
`CREATE PERFETTO TABLE` 允许定义针对 trace 分析查询优化的表。这些表比使用 `CREATE TABLE` 创建的 SQLite 原生表性能更高且内存效率更高。

但是请注意，`CREATE TABLE` 的完整功能集不支持：
1. Perfetto 表不能插入数据，并且在创建后是只读的
2. Perfetto 表必须使用 `SELECT` 语句定义和填充。它们不能通过列名和类型定义。

示例：

```sql
-- 创建一个具有常量值的 Perfetto 表。
CREATE PERFETTO TABLE constant_table AS
SELECT column1 as ts, column2 as dur
FROM (
 VALUES
 (100, 10),
 (200, 20)
);

-- 使用对另一个表的查询创建 Perfetto 表。
CREATE PERFETTO TABLE slice_sub_table AS
SELECT *
FROM slice
WHERE name = 'foo';
```

### 架构

Perfetto 表可以具有可选的显式架构。架构语法与函数参数或从函数返回的表相同，即表或视图名称后的括号内的逗号分隔的（列名，列类型）对列表。

```sql
CREATE PERFETTO TABLE foo(x LONG, y STRING) AS
SELECT 1 as x, 'test' as y
```

### 索引

`CREATE PERFETTO INDEX` 允许你在 Perfetto 表上创建索引，类似于在 SQLite 数据库中创建索引。这些索引构建在特定列上，Perfetto 内部以排序顺序维护这些列。这意味着从在索引列（或列组）上排序中受益的操作将明显更快，就像你在已经在排序的列上操作一样。

NOTE: 索引具有不可忽略的内存成本，因此只有在需要性能改进时才使用它们很重要。

NOTE: 索引将在创建于索引表上的视图中使用，但不会被任何子表继承，如下面的 SQL 所示。

NOTE: 如果查询对表的 `id` 列（即表的主键）进行过滤/连接，则无需添加 Perfetto 索引，因为 Perfetto 表已经具有针对可以从排序中受益的操作的特殊性能优化。

使用示例：
```sql
CREATE PERFETTO TABLE foo AS
SELECT * FROM slice;

-- 在表 foo 的列 `track_id` 上创建并存储索引 `foo_track`。
CREATE PERFETTO INDEX foo_track ON foo(track_id);
-- 创建或替换在两列上创建的索引。它将用于
-- `track_id` 上的操作，并且仅当
-- 在 `track_id` 上也有相等约束时,才可用于 `name` 上的操作。
CREATE OR REPLACE PERFETTO INDEX foo_track_and_name ON foo(track_id, name);
```

这两个查询的性能现在应该非常不同：
```sql
-- 这没有索引,必须线性扫描整个列。
SELECT * FROM slice WHERE track_id = 10 AND name > "b";

-- 这有索引，可以使用二分搜索。
SELECT * FROM foo WHERE track_id = 10 AND name > "b";

-- 最大的区别应该在连接上明显:
-- 此连接:
SELECT * FROM slice JOIN track WHERE slice.track_id = track.id;
-- 将明显慢于此:
SELECT * FROM foo JOIN track WHERE slice.track_id = track.id;
```

可以删除索引：
```sql
DROP PERFETTO INDEX foo_track ON foo;
```


## 使用架构创建视图

可以通过 `CREATE PERFETTO VIEW` 创建视图，它采用可选架构。除了架构之外，它们的行为与常规 SQLite 视图完全相同。

NOTE: 在标准库中必须使用 `CREATE PERFETTO VIEW` 而不是 `CREATE VIEW`，因为每个列都需要被记录。

```sql
CREATE PERFETTO VIEW foo(x LONG, y STRING) AS
SELECT 1 as x, 'test' as y
```

## 定义宏
`CREATE PERFETTO MACRO` 允许在 SQL 中定义宏。宏的设计灵感来自 Rust 中的宏。

以下是宏的推荐用法：
- 将表作为参数传递给"类似函数"的 SQL 片段
- 为性能敏感的查询定义简单常量

宏很强大，但如果使用不当也很危险，使调试极其困难。因此，建议仅在需要时谨慎使用它们，并且仅用于上述描述的推荐用法。

如果只传递标量 SQL 值，函数通常因其清晰性而更受青睐。但是，对于在性能敏感查询中多次使用的简单常量，宏可能更高效，因为它避免了大量函数调用的潜在开销。

NOTE: 宏在任何执行发生*之前*通过预处理步骤扩展。扩展是纯语法操作，涉及用宏定义中的 SQL 标记替换宏调用。

由于宏是语法，宏中的参数类型和返回类型与函数中使用的类型不同，并且对应于 SQL 解析树的部分。以下是支持的类型：

| 类型名称 | 描述 |
| --------- | ----------- |
| `Expr` | 对应于任何 SQL 标量表达式。 |
| `TableOrSubquery` | 对应于 SQL 表或子查询 |
| `ColumnName` | 对应于表的列名 |

示例：

```sql
-- 创建一个不带参数的宏。注意返回的 SQL 片段如何
-- 需要用括号括起来以使其成为有效的 SQL 表达式。
--
-- 注意:这是强烈不鼓励使用宏的用法,因为简单的 SQL
-- 函数也可以在这里工作。
CREATE PERFETTO MACRO constant_macro() RETURNS Expr AS (SELECT 1);

-- 使用上述宏。通过在其名称后附加 ! 来调用宏。
-- 这类似于在 Rust 中调用宏的方式。
SELECT constant_macro!();

-- 这导致以下 SQL 实际执行:
-- SELECT (SELECT 1);

-- 上述的变体。同样,强烈不鼓励。
CREATE PERFETTO MACRO constant_macro_no_bracket() RETURNS Expr AS 2;

-- 使用上述宏。
SELECT constant_macro_no_bracket!();

-- 这导致以下 SQL 实际执行:
-- SELECT 2;

-- 创建一个接受单个标量参数并返回标量的宏。
-- 注意：同样，这是强烈不鼓励使用宏的用法，因为函数也可以
-- 执行此操作。
CREATE PERFETTO MACRO single_arg_macro(x Expr) RETURNS Expr AS (SELECT $x);
SELECT constant_macro!() + single_arg_macro!(100);

-- 创建一个接受表和标量表达式作为参数
-- 并返回表的宏。再次注意返回的 SQL 语句如何
-- 用括号括起来以使其成为子查询。这允许它用在任何
-- 允许表或子查询的地方。
--
-- 注意:如果表被多次使用,建议它们被
-- "缓存"为通用表表达式(CTE),以提高性能。
CREATE PERFETTO MACRO multi_arg_macro(x TableOrSubquery, y Expr)
RETURNS TableOrSubquery AS
(
 SELECT input_tab.input_col + $y
 FROM $x AS input_tab;
)
```
