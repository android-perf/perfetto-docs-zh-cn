# 在 Chrome 上采集 Traces

Perfetto 可以直接从桌面上的 Chrome 浏览器捕获 traces。它捕获所有打开的选项卡的 traces。

> NOTE: 要从 Android 上的 Chrome 采集 traces，请遵循[采集 Android 系统 traces 的说明](/docs/getting-started/system-tracing.md）并启用 Chrome Probe。如果你使用的是 [Android 的用户构建版本](https://source.android.com/docs/setup/build/building#lunch)，你必须通过将 `chrome://flags#enable-perfetto-system-tracing` 切换为"已启用"并重启 Chrome 来启用与系统 Perfetto 的集成。

## 手动采集 trace

> NOTE: 如果需要自动 trace 收集，请遵循 [crossbench 说明](#使用-crossbench-自动化采集-trace)。

1. 导航到 [ui.perfetto.dev](https://ui.perfetto.dev/) 并从左侧菜单中选择 [**"采集新 trace"**](https://ui.perfetto.dev/#!/record)。
 > 如果你是第一次使用 Perfetto UI，你必须安装
 > [Perfetto UI Chrome 扩展](https://chrome.google.com/webstore/detail/perfetto-ui/lfmkphfpdbjijhpomgecfikhfohaoine)。
2. 在[概览设置](https://ui.perfetto.dev/#!/record/target）中选择 **"Chrome"** 作为 **"目标平台"**。

3. 在 [**"录制设置"**](https://ui.perfetto.dev/#!/record/config）中配置设置。

 ![Perfetto UI 的记录页面](/docs/images/record-trace-chrome.png)
 > NOTE: "Long trace"模式尚不适用于 Chrome 桌面版。
 > TIP:
 >
 > - 要保存当前配置设置并稍后应用，请转到"保存的配置"菜单。
 > - 要共享你的配置设置，请转到"记录命令"菜单。

4. 在 [**Chrome 浏览器**](https://ui.perfetto.dev/#!/record/chrome）探针部分中选择你想要的类别（或顶级标签）。

 > NOTE: 顶部的标签启用相关类别的组，但目前没有直接的方法在针对 Chrome 时看到它们。但是，你可以将目标切换到"Android"，然后在"记录命令"部分生成的配置中查看类别，如果你好奇的话。

 底部的列表可用于选择其他类别。

 ![Chrome 的跟踪类别](/docs/images/tracing-categories-chrome.png)

5. 现在你可以开始 trace 采集了。准备好时按 **"开始采集"**按钮。
6. 继续使用浏览器捕获你要跟踪的操作，并等待 trace 完成。你也可以通过按"停止"按钮手动停止 trace。

 **不要关闭 perfetto UI 选项卡！**否则，跟踪将停止并且 trace 数据将丢失。

7. 一旦 trace 准备好，你可以在左侧菜单 **"当前 Trace"** 中找到并分析它。

 > NOTE: 如果你想共享 trace，请记住它将包含所有打开选项卡的 URL 和标题、每个选项卡使用的子资源的 URL、扩展 ID、硬件标识详细信息以及你可能不想公开的其他类似信息。

## 使用 crossbench 自动化采集 trace

如果你需要自动化收集 traces 或需要对 chrome 标志进行更精确的控制，我们建议使用 [crossbench](https://chromium.googlesource.com/crossbench)。它支持在所有主要平台上为 chrome 收集 traces。

1. 按照[手动过程](#手动采集-trace)中的步骤 1-4 创建 trace 配置。
2. 从 [cmdline 说明页面](https://ui.perfetto.dev/#!/record/cmdline) 下载 textproto 配置并将其本地保存为 `config.txtpb`
3. 使用你的配置运行 crossbench
 ```bash
 ./tools/perf/crossbench load \
 --probe='perfetto:/tmp/config.txtpb' \
 --url="http://test.com" \
 --browser=path/to/chrome \
 -- $CUSTOM_CHROME_FLAGS
 ```
