# 为 Perfetto 做贡献

## 快速入门

如果你是第一次为 Perfetto 做贡献，请遵循以下步骤。

### 设置

**先决条件：** git 和 python3。

```sh
# 克隆 Perfetto 仓库并进入目录
git clone https://github.com/google/perfetto.git
cd perfetto

# 安装依赖项
# 添加 --android 以拉取 Android NDK 和模拟器
tools/install-build-deps

# 设置所有构建配置
# 添加 --android 以生成 Android 构建配置
tools/setup_all_configs.py
```

### 构建

_在 Linux 上_

```sh
# 生产构建
tools/ninja -C out/linux_clang_release

# 调试构建
tools/ninja -C out/linux_clang_debug
```

_在 Mac 上_

```sh
# 生产构建
tools/ninja -C out/mac_release

# 调试构建
tools/ninja -C out/mac_debug
```

_在 Android 上(在桌面操作系统上交叉编译)_

```sh
# 生产构建 (arm64)
tools/ninja -C out/android_release_arm64

# 调试构建 (arm64)
tools/ninja -C out/android_debug_arm64
```

_UI_

```sh
# 构建 UI
ui/build

# 运行开发服务器
ui/run-dev-server
```

有关构建 Perfetto 的更多信息，请参阅[构建说明](build-instructions)。

### 贡献

NOTE: 2025 年 3 月，我们的团队已将 Perfetto 的主要开发迁移到 GitHub(之前在 Android Gerrit 上)。

#### Google 员工

NOTE: 遵循 [go/perfetto-github-instructions](http://go/perfetto-github-instructions) 中的说明。

1. 确保你/你的组织已在 [cla.developers.google.com](https://cla.developers.google.com/) 签署 Google CLA。
2. 使用更改创建分支：

```sh
git checkout -b first-contribution
```

3. 在仓库中进行更改。
4. 添加、提交并上传更改：

```sh
git add .
git commit -m "我的第一次贡献"
gh pr create # 需要 cli.github.com
```

请注意，我们的项目遵循 [Google C++ 风格](https://google.github.io/styleguide/cppguide.html)，目标为 `-std=c++17`。

#### 外部贡献者

请像为任何其他 GitHub 仓库做贡献一样进行贡献。有关如何进行的良好解释，可以在[这里](https://docs.github.com/en/get-started/exploring-projects-on-github/contributing-to-a-project）找到。

### 测试

由于 Perfetto 具有相当复杂的测试策略，我们将在每次推送到仓库时自动运行我们的 presubmit。
手动运行：`tools/run_presubmit`。
有关测试 Perfetto 的更多信息，请参阅[测试页面](testing)。

## 接下来做什么？

你可能想要为 UI、Trace Processor、SDK 或各种数据导入器做贡献。

- 如果你想为 UI 添加新功能，最可能的下一步是 [UI 快速入门](ui-getting-started)。
- 如果你想编辑 UI 的核心功能：这是一个大得多的更改，需要深入了解 Perfetto UI。大多数请求/错误现在与各种插件相关，而不是核心。
- 如果你想添加新的 ftrace 事件，请查看[常见任务页面](common-tasks)。
- 如果你想为 Perfetto SQL 标准库添加新表/视图/函数，你需要先理解 [Perfetto SQL 语法](/docs/analysis/perfetto-sql-syntax.md)，然后阅读[常见任务页面](common-tasks）中更新标准库的详细信息。
- 如果你想为 Perfetto 添加对新文件类型的支持，你需要向 Trace Processor C++ 代码添加新的导入器。

## {#community} 社区交流

### 联系

我们的主要交流渠道是我们的邮件列表：https://groups.google.com/forum/#!forum/perfetto-dev。

你也可以在我们的 [Discord 频道](https://discord.gg/35ShE3A) 上联系我们，但我们在那里的支持只是尽力而为。

本项目遵循
[Google 开源社区准则](https://opensource.google/conduct/)。

### 错误

对于影响 Android 或 trace 内部的错误：

- **Googlers**： 使用内部错误跟踪器 [go/perfetto-bugs](http://goto.google.com/perfetto-bugs)
- **非 Googlers**： 使用 [GitHub issues](https://github.com/google/perfetto/issues)。

对于影响 Chrome Tracing 的错误：

- 使用 http://crbug.com `Component:Speed>Tracing 标签：Perfetto`。

## 贡献者许可协议

对此项目的贡献必须附有贡献者许可协议。你（或你的雇主）保留对你贡献的版权；这仅授予我们使用和分发你的贡献作为项目一部分的许可。前往 <https://cla.developers.google.com/> 查看你在文件上的当前协议或签署新协议。

你通常只需要提交一次 CLA，所以如果你已经提交过一个（即使是为不同的项目），你可能不需要再次执行。
