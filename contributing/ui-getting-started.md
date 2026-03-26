# UI 开发

## 入门

此命令拉取 UI 相关依赖(特别是，NodeJS 二进制文件)
并在 `ui/node_modules` 中安装 `node_modules`:

```bash
tools/install-build-deps --ui
```

### 构建 UI

```bash
# 默认将构建到 ./out/ui。可以使用 --out path/ 更改
# 最终包将在 ./ui/out/dist/ 中可用。
# 构建脚本从 ./ui/out 到 $OUT_PATH/ui/ 创建符号链接。
ui/build
```

### 运行开发服务器

开发服务器具有实时重新加载功能：一旦你在 TypeScript 文件中进行更改，
结果代码将被重新编译，页面将自动重新加载。
默认情况下，此逻辑使用超时以防止在快速更改时连续重新加载。
可以通过 UI 中仅限开发的"快速实时重新加载"标志禁用此逻辑。
禁用它将更早重新加载页面，代价是有时会连续多次重新加载。

```bash
# 这将自动构建 UI。无需在运行 ui/run-dev-server 之前手动运行
# ui/build。
ui/run-dev-server
```

导航到 http://localhost:10000/ 查看更改。

NOTE: 如果你对 Trace Processor 进行了更改，则需要重新启动服务器。

### 测试更改

UI 单元测试位于被测试的功能旁边，并具有
`_unittest.ts` 或 `_jsdomtest.ts` 后缀。以下命令运行所有单元
测试：

```bash
ui/run-unittests
```

此命令将首先执行构建；如果你已经运行开发服务器，则不需要。
在这种情况下，为了避免与开发服务器完成的重建的干扰
并更快地获得结果，你可以使用

```bash
ui/run-unittests --no-build
```

跳过构建步骤。

脚本 `ui/run-unittests` 还支持 `--watch` 参数，当底层源文件更改时，该参数将重新启动测试。
这可以与 `--no-build` 结合使用，也可以单独使用。

## 开发环境

如果你正在寻找一个用于编写 TypeScript 代码的 IDE，Visual Studio Code 开箱即用。
WebStorm 或 IntelliJ Idea Ultimate(Community 版本
没有 JavaScript/TypeScript 支持)也工作得非常好。代码
位于 `ui` 文件夹中。

对于 VSCode 用户，我们建议使用 eslint & prettier 扩展来完全在 IDE 内部处理此问题。
请参阅[有用扩展](#useful-extensions）部分了解如何设置。

### 格式化和 Linting

我们使用 `eslint` 来 lint TypeScript 和 JavaScript，并使用 `prettier` 来格式化 TypeScript、JavaScript 和 SCSS。

要自动格式化所有源文件，请运行 ui/format-sources，它负责在更改的文件上运行 prettier 和 eslint:

```bash
# 默认情况下，它仅格式化来自上游 Git 分支（通常为 origin/main）更改的文件。
# 传递 --all 以格式化 ui/src 下的所有文件。
ui/format-sources
```

预提交检查要求没有格式化或 linting 问题，因此在提交补丁之前使用上述命令修复所有问题。

## Mithril 组件

Perfetto UI 使用 [Mithril](https://mithril.js.org/) 库来渲染接口。
代码库中的大多数组件使用
[类组件](https://mithril.js.org/components.html#classes)。当 Mithril 通过 `m` 别名导入（就像代码库中通常做的那样）时，类
组件应该扩展 `m.ClassComponent`，它有一个可选的泛型参数允许组件接受输入。
类组件的入口点是一个 `view` 方法，返回一个要在组件存在于页面上时渲染的虚拟 DOM 元素树。

## 提示

### 组件状态

组件的本地状态可以驻留在类成员中，并通过访问 `this` 直接在方法中访问。
在不同组件之间共享的状态存储在 `State` 类定义中，应该通过在 `src/common/actions.ts` 中实现新操作来修改。
添加到 `State` 的新字段应该在 `src/common/empty_state.ts` 中初始化。

对于全局状态中可以使用的内容有限制：普通 JS 对象是可以的，但类实例不行（此限制是由于状态序列化：状态应该是有效的 JSON 对象）。
如果存储类实例（如 `Map` 和 `Set` 数据结构）是必要的，这些可以存储在状态的 `NonSerializableState` 部分中，该部分在保存到 JSON 对象时被省略。
