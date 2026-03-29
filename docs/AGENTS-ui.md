# AI Agent 的 Perfetto UI 开发

Perfetto UI 是一个使用 Mithril 框架用 TypeScript 编写的单页 Web 应用程序。它位于 `ui/` 中，并为 ui.perfetto.dev 提供动力。UI 通过 WebAssembly 嵌入 TraceProcessor。

## 一般原则

- **不要过度设计** - 解决手头的问题，而不是假设的未来问题。
- **优先选择更简单的方法** - 如果有简单解决方案和复杂解决方案，请选择简单解决方案。
- **创建之前先搜索** - 编写新实用程序之前，始终搜索现有实用程序。
- **保持一致** - 遵循周围代码中建立的模式。
- **优先选择具有不可变只读成员的接口** - 我们喜欢不可变性，使代码更容易调试。

## 目录结构

UI 代码库组织如下：

```text
ui/src/
├── base/ # 核心实用程序(时间、颜色、数组、记录、可处置对象)
├── widgets/ # 可重用的 UI 组件(Button、Menu、Modal、Popup 等)
├── components/ # 更高级别的组件(聚合面板、查询表)
├── core/ # 核心应用程序逻辑和管理器
├── public/ # 插件的公共 API 表面
├── plugins/ # 可选的第三方/外部插件
├── core_plugins/ # 必需的核心插件(无法禁用)
├── frontend/ # 主要前端渲染代码
├── trace_processor/# 引擎通信层(查询结果、SQL 实用程序)
├── test/ # Playwright 集成测试
└── assets/ # SCSS 样式表和静态资产
```

在可能的情况下（如果 API 表面允许），功能功能应封装在 src/plugins 中的插件内。
- `core_plugins/`（例如，`dev.perfetto.CoreCommands`、`dev.perfetto.Notes`）包含必需功能。用户无法禁用它们，并且它们始终处于活动状态。
- `plugins/`（例如，`dev.perfetto.Sched`、`com.android.AndroidStartup`）是可选的。用户可以通过功能标志启用/禁用它们。这些按反向 DNS 命名组织（例如，`com.android.*`、`dev.perfetto.*`、`org.chromium.*`）。
- 这种区别主要是历史性的。如今，在 90% 的情况下，事物可以（并且应该）仅放在 plugins/ 内部
- 查看 /docs/contributing/ui-plugins.md，因为它包含对插件作者额外的有用内容。

## 构建和运行 UI

要为开发构建和服务 UI:

```sh
# 从仓库根目录
ui/build    # 构建 UI
ui/build --typecheck # 运行 tsc --noEmit，不打包（更快）
ui/run-dev-server    # 启动具有实时重新加载的开发服务器
```

UI 使用：

- **TypeScript** 以实现类型安全
- **Mithril** 作为 UI 框架
- **Rollup** 用于打包
- **pnpm** 用于包管理
- **ESLint** 用于 linting(基于 Google 风格)
- **Playwright** 用于集成测试

## 构建运行时进行类型检查

每个构建在工作时都会声明一个锁文件，除非传递了 --no-build 选项。如果你尝试运行构建但由于其中一个锁文件存在而遇到失败，你可以尝试仅使用以下命令检查类型，而不会干扰当前构建。

```sh
ui/build --typecheck --no-build
```

## 插件架构

插件是 UI 的主要扩展机制。它们遵循此结构：

```typescript
import {PerfettoPlugin} from '../../public/plugin';
import {Trace} from '../../public/trace';
import {App} from '../../public/app';

export default class MyPlugin implements PerfettoPlugin {
 // 唯一的反向 DNS 标识符
 static readonly id = 'com.example.MyPlugin';

 // 可选:可读描述
 static readonly description = 'Does something useful';

 // 可选:声明对其他插件的依赖
 static readonly dependencies = [OtherPlugin];

 // 当插件被激活时调用(在 trace 加载之前)
 static onActivate(app: App): void {
 // 注册不需要 trace 的命令、侧边栏项、页面
 }

 // 当加载 trace 时调用
 async onTraceLoad(trace: Trace): Promise<void> {
 // 注册需要 trace 数据的 Track、选项卡、命令
 // 查询 trace processor,将 Track 添加到工作区
 }
}
```

**插件生命周期：**

1. `onActivate()` - 当插件被启用时，在加载任何 trace 之前调用。用于注册全局命令、页面和侧边栏项。
2. `onTraceLoad()` - 当加载 trace 时调用。用于注册依赖于 trace 数据的 Track、选项卡和命令。
3. `trace.onTraceReady` 事件 - 在所有插件完成 `onTraceLoad()` 后触发。用于需要所有 Track 可用的自动化。

**插件可用的关键 API:**

- `trace.engine` - 针对 TraceProcessor 运行 SQL 查询
- `trace.tracks` - 注册和查找 Track
- `trace.selection` - 管理选择状态
- `trace.commands` - 注册命令
- `trace.tabs` - 在详细信息面板中注册选项卡
- `trace.timeline` - 访问时间轴状态
- `trace.workspace` - 管理 Track 树结构

## Mithril 模式和最佳实践

UI 使用 Mithril.js。遵循这些模式：

**组件结构：**
```typescript
import m from 'mithril';

interface MyComponentAttrs {
 readonly value: string;
 readonly onChange: (newValue: string) => void;
}

export class MyComponent implements m.ClassComponent<MyComponentAttrs> {
 // 本地状态
 private expanded = false;

 view({attrs}: m.CVnode<MyComponentAttrs>): m.Children {
 return m('.my-component',
 m(Button, {label: attrs.value, onclick: () => this.expanded = !this.expanded}),
 this.expanded && m('.details', 'Expanded content'),
 );
 }
}
```

**Mithril 规则：**

- 大多数时候不需要调用 `m.redraw()`。我们自动安排重新绘制：(1) 在 Mithril 的 DOM 事件处理程序中;(2) 在 trace processor 查询完成之后。但不在手动注册的 JS 事件处理程序之后。
- 如果不需要 DOM 访问，请使用 `constructor` 进行初始化，如果需要 DOM，则使用 `onCreate`。
- 优先使用现有小部件库（`ui/src/widgets/`）而不是创建新组件。
- 对 attrs 属性使用 `readonly` 以防止意外修改。我们喜欢事物是不可变的。

**保持状态的条件渲染：**
当需要条件显示/隐藏内容同时保持组件状态时，请使用 `Gate` 组件：

```typescript
import {Gate} from '../base/mithril_utils';

m(Gate, {open: this.isVisible}, m(ExpensiveComponent));
```

### 小部件库

`ui/src/widgets/` 目录包含可重用组件。在创建新 UI 元素之前，始终先在此处检查：

- `Button`、`ButtonBar`、`ButtonGroup` - 各种按钮样式
- `PopupMenu`、`Menu`、`MenuItem`、`MenuDivider` - 下拉菜单
- `Popup` - 浮动弹出容器
- `Modal` - 模态对话框
- `TextInput`、`Select`、`Checkbox`、`Switch` - 表单控件
- `Tree` - 树视图组件
- `DataGrid` - 表格数据网格组件
- `Tabs` - 选项卡界面
- `Spinner` - 加载指示器
- `EmptyState` - 空状态占位符

**使用小部件：**

```typescript
import {Button, ButtonVariant} from '../widgets/button';
import {Popup} from '../widgets/popup';

m(Button, {
 label: 'Click me',
 icon: 'search',
 variant: ButtonVariant.Filled,
 onclick: () => { /* 处理点击 */ },
});
```

## TypeScript 代码风格

遵循 TypeScript 代码的这些指南：

- **尽可能避免 `any`**：如果你真的需要它，请使用 `@typescript-eslint/no-explicit-any` 规则。在大多数情况下，使用 `unknown` 和类型保护就足够了。
- **未使用的变量**：使用下划线前缀（`_unused`）以满足 `@typescript-eslint/no-unused-vars`。
- **严格的布尔表达式**：不要在布尔上下文中隐式使用数字或字符串。
- **默认只读**：对接口属性和函数参数使用 `readonly`。
- **使用现有实用程序**：在编写自己的实用程序之前，请检查 `ui/src/base/`:
  - `time.ts`、`duration.ts` - 时间处理
  - `logging.ts` - `assertTrue()`、`assertExists()`、`assertFalse()`
  - `disposable_stack.ts` - 资源清理
  - `deferred.ts` - Promise 实用程序
  - `string_utils.ts` - 字符串操作
  - `array_utils.ts` - 数组助手

## 使用 TraceProcessor

插件通过 TraceProcessor 引擎使用 SQL 查询数据：

```typescript
async onTraceLoad(trace: Trace): Promise<void> {
 const result = await trace.engine.query(`
 SELECT ts, dur, name
 FROM slice
 WHERE name LIKE '%mySlice%'
 LIMIT 100
 `);

 // 使用类型化迭代
 const iter = result.iter({
 ts: LONG, // bigint
 dur: LONG, // bigint
 name: STR, // string
 });

 for (; iter.valid(); iter.next()) {
 console.log(iter.ts, iter.dur, iter.name);
 }
}
```

## Track 创建

很少需要从头创建新 Track。
在大多数情况下，你可以使用 ui/src/components/tracks/ 中的更高级别组件，尤其是 DatasetSliceTrack(/docs/contributing/ui-plugins.md 中的示例)。
首先查看这些示例，并将通过 trace.tracks.registerTrack 创建 Track 作为最后手段。

## CSS/SCSS 约定

样式表位于 `ui/src/assets/` 中，以及组件旁边的组件特定 `.scss` 文件。

- 对所有 CSS 类使用 `pf-` 前缀(Perfetto 命名空间)
- 遵循 BEM 类似的命名：`.pf-component`、`.pf-component__element`、`.pf-component--modifier`
- 使用 `theme_provider.scss` 中定义的 CSS 自定义属性（变量）作为颜色
- 使用语义颜色变量同时支持浅色和深色主题

## 要避免的常见陷阱

1. **不检查现有小部件就创建新小部件** - 小部件库是全面的。
2. **尽可能使用 Trace 对象** - 在需要的地方通过层次结构传递 Trace 对象。

## 代码审查偏好和风格偏好

在代码审查期间一致地强制执行以下模式。遵循这些模式将显著加快审查过程。

### TypeScript/JavaScript 风格

**优先选择 `undefined` 而非 `null`:**

```typescript
// 不好
function getValue(): string | null { return null; }

// 好
function getValue(): string | undefined { return undefined; }
```

**对不应修改的数组使用 `ReadonlyArray<T>`:**

```typescript
// 不好
function process(items: string[]): void { ... }

// 好
function process(items: ReadonlyArray<string>): void { ... }
```

**使用 `classNames()` 实用程序构建 CSS 类字符串：**

```typescript
import {classNames} from '../base/classnames';

// 不好
const cls = 'pf-row' + (isSelected ? ' pf-row--selected' : '') + (isDisabled ? ' pf-row--disabled' : '');

// 好
const cls = classNames('pf-row', isSelected && 'pf-row--selected', isDisabled && 'pf-row--disabled');
```

**在 switch 默认情况下使用 `assertUnreachable()`:**

```typescript
import {assertUnreachable} from '../base/logging';

switch (value) {
 case 'a': return handleA();
 case 'b': return handleB();
 default:
 assertUnreachable(value); // 如果情况不详尽,TypeScript 将报错
}
```

**变量应为驼峰命名法：**

```typescript
// 不好
const trace_processor_id = 123;

// 好
const traceProcessorId = 123;
```

### CSS/SCSS 风格

**永远不要使用内联样式 - 使用样式表：**

```typescript
// 不好
m('div', {style: {color: 'red', padding: '10px'}}, 'content')

// 好
m('.pf-my-component', 'content') // 带有 .scss 文件中的样式
```

**所有 CSS 类必须具有 `pf-` 前缀：**

```scss
// 不好
.my-component { ... }
.row { ... }

// 好
.pf-my-component { ... }
.pf-my-component__row { ... }
```

**永远不要硬编码颜色 - 使用主题变量：**

```scss
// 不好
.pf-my-component {
 color: #333;
 background: white;
}

// 好
.pf-my-component {
 color: var(--pf-color-foreground);
 background: var(--pf-color-background);
}
```

### Mithril 特定规则

**不要为可以在 `view()` 中完成的事情使用 `oncreate`/生命周期钩子：**

```typescript
// 不好 - 在生命周期方法之间拆分代码会损害可读性。
oncreate() {
 this.computedValue = inexpensiveComputation();
}

// 好 - 在 view 中计算。如果昂贵，请在构造函数中初始化。
view() {
 const computedValue = inexpensiveComputation();
 return m('div', computedValue);
}
```

### 小部件使用

**对链接使用 `Anchor` 小部件：**

```typescript
import {Anchor} from '../widgets/anchor';
import {Icons} from '../widgets/icons';

// 不好
m('a', {href: 'https://example.com', target: '_blank'}, 'Link')

// 好
m(Anchor, {href: 'https://example.com', icon: Icons.ExternalLink}, 'Link')
```

### 命名约定

**设置/标志应使用反向 DNS 格式：**

```typescript
// 不好
const settingId = 'trackHeightMinPx';

// 好
const settingId = 'dev.perfetto.TrackHeightMinPx';
```

**命令 ID 应该是描述性的，但省略多余的插件名称：**

```typescript
// 不好(如果插件是 com.android.OrganizeNestedTracks)
const commandId = 'com.android.OrganizeNestedTracks#organizeNestedTracks';

// 好
const commandId = 'com.android.OrganizeNestedTracks';
```

**创建新文件时版权年份应该是当前的：**
但在编辑现有文件时不要触摸年份。

```typescript
// 不好(如果当前年份是 2025)
// Copyright (C) 2024 The Android Open Source Project

// 好
// Copyright (C) 2025 The Android Open Source Project
```

## 测试

**使用 Zod 解析未知类型的对象：**

```typescript
import {z} from 'zod';

// 不好 - 不安全的类型断言
const config = JSON.parse(data) as MyConfig;

// 好 - 验证解析
const ConfigSchema = z.object({
 name: z.string(),
 value: z.number(),
});
const config = ConfigSchema.parse(JSON.parse(data));
```

### UI 单元测试

单元测试运行使用：

```sh
$ui/run-unittests
```

TypeScript 单元测试遵循 `*_unittest.ts` 模式并使用 Jest。

### UI 集成测试

集成测试使用 Playwright:

```sh
ui/run-integrationtests
```
