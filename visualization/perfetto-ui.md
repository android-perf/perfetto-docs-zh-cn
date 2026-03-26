# Perfetto UI

[Perfetto UI](https://ui.perfetto.dev) 使你能够在浏览器中查看和分析 trace。
它支持几种不同的 tracing 格式，包括 perfetto proto trace 格式和传统的 json trace 格式。

## 加载 Trace

单击任务栏"示例 Traces"部分中的一个示例以开始。

从文件资源管理器拖放 trace，或单击侧边栏中的"打开 trace 文件"以打开本地 trace 文件。

## 导航时间轴

使用 WASD 组合键缩放和平移时间轴。W 和 S 分别放大和缩小，A 和 D 分别向左和向右平移。

<video width="800" controls>
 <source src="https://storage.googleapis.com/perfetto-misc/keyboard-nav.webm" type="video/webm">
</video>

或者，你可以使用 Shift+拖动使用鼠标平移。Ctrl+鼠标滚轮放大和缩小。

<video width="800" controls>
 <source src="https://storage.googleapis.com/perfetto-misc/mouse-nav.webm" type="video/webm">
</video>

## Track event 选择

在 trace 上选择实体是深入分析 trace 事件并显示这些事件的更多数据的主要方式。

通过单击选择 Track event。有关所选事件的详细信息将显示在选项卡抽屉中的"当前选择"选项卡中。

<video width="800" controls>
 <source src="https://storage.googleapis.com/perfetto-misc/select-event.webm" type="video/webm">
</video>

使用 '.' 和 ',' 在同一 Track 上的相邻 Slice 之间导航。

<video width="800" controls>
 <source src="https://storage.googleapis.com/perfetto-misc/next-prev-events.webm" type="video/webm">
</video>

按 'F' 将所选实体在视口中居中，再次按 'F' 将该 Slice 适合视口。
这对于当前缩放级别下无法清晰看到的非常短的事件很有用。

<video width="800" controls>
 <source src="https://storage.googleapis.com/perfetto-misc/focus-event.webm" type="video/webm">
</video>

在任何时候，按 'escape' 或单击时间轴中的某个空白空间以清除选择。

## 区域选择

在时间轴上单击并拖动以进行区域选择。区域选择由开始+结束时间和 Track 列表组成。
在标记上单击+拖动以移动开始和结束时间。选中或取消选中 Track 外壳中的复选框以修改选择中的 Track 列表。

<video width="800" controls>
 <source src="https://storage.googleapis.com/perfetto-misc/area-selection.webm" type="video/webm">
</video>

你还可以使用 'R' 热键将单个选择转换为区域选择。这将使用所选事件的边界将当前选中的 Track event 转换为区域选择。

## 命令

命令提供了一种在整个 UI 中运行常见任务的快速方法。
按 'Ctrl+Shift+P'（Mac 上为 'Cmd+Shift+P'）打开命令面板，或在 omnibox 中输入 '>'。
Omnibox 转换为命令面板。可以使用模糊匹配搜索命令。
按向上或向下突出显示命令，按 Enter 运行它。

<video width="800" controls>
 <source src="https://storage.googleapis.com/perfetto-misc/commands.webm" type="video/webm">
</video>

有关使用命令、启动命令和宏自动执行 UI 的全面文档，请参阅
[命令和宏](/docs/visualization/ui-automation.md)。有关所有扩展机制概述，请参阅
[扩展 UI](/docs/visualization/extending-the-ui.md)。

## 显示/隐藏选项卡抽屉

按 'Q' 切换选项卡抽屉。

## 查找 Track

按 'Ctrl+P'（Mac 上为 'Cmd+Shift+P'）打开 Track 查找器并开始输入以模糊查找 Track。

<video width="800" controls>
 <source src="https://storage.googleapis.com/perfetto-misc/finding-tracks.webm" type="video/webm">
</video>

## 固定 Track

单击 track 外壳中的"固定"图标将 track 固定到时间轴顶部。此操作会将 track 移动到工作区的顶部。如果你想在滚动主时间轴时保持重要 track 在视图中，这会很有用。

<video width="800" controls>
 <source src="https://storage.googleapis.com/perfetto-misc/pinning-tracks.webm" type="video/webm">
</video>

## 热键

热键绑定显示在命令面板中命令的右侧，或按 '?' 热键显示所有配置的热键。

## 下一步

一旦你对基本 UI 交互感到舒适，你可以自定义和扩展 UI 以加快分析工作流程：

- **自动化重复任务：** 使用[命令和宏](/docs/visualization/ui-automation.md）配置启动命令，每次打开 trace 时自动固定 track 或创建 debug track，并为你偶尔运行的特定分析工作流创建宏。
- **与团队共享工作流：** 使用[扩展服务器](/docs/visualization/extension-servers.md）向你的团队分发宏、SQL 模块和 proto 描述符。
- **查看所有扩展选项：** [扩展 UI](/docs/visualization/extending-the-ui.md) 涵盖了所有自定义 Perfetto 的方式，从简单的宏到插件。
