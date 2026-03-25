# 后台 Tracing

本文档描述如何在后台运行 Perfetto，允许你断开与设备的连接并在稍后收集 trace 文件。

## 用例

假设你想在 Android 设备或 Linux 服务器上开始采集长时间运行的 trace，然后终止你的 adb/ssh shell 并稍后返回停止 tracing 会话并收集 trace 文件。本页面向你展示如何执行此操作，同时确保 trace 保持完整。

要在后台运行 tracing，请使用 `perfetto` 命令的 `--background-wait` 参数。这将使 Perfetto 守护进程化（即，作为后台进程运行）并打印其进程 ID (PID)。

NOTE: 建议使用 `--background-wait` 而不是 `--background`，因为前者在退出之前等待所有
 数据源启动。这确保了在 trace 的开头没有数据丢失。

## 用法

使用 `tracebox` 或 `perfetto` 开始采集 trace。

```bash
perfetto -c config.cfg --txt -o trace.pftrace --background-wait
```

这将把后台 perfetto 进程的 pid 打印到 stdout。

当你准备好停止 Tracing 时，你需要向后台 Perfetto 进程发送 `SIGINT` 或 `SIGTERM` 信号。然而，简单地杀死进程会创建竞态条件：`kill` 命令立即返回，但 Perfetto 可能仍在将 trace 文件的最后部分写入磁盘。

如果你过早收集文件，它可能不完整。为了防止这种情况，你必须等待 trace 文件上的 `close_write` 事件，这确认 Perfetto 已完成写入并关闭了文件。你可以使用特定于平台的 `inotify` 工具来实现这一点。

<?tabs>

TAB: Linux

在 Debian Linux 上，我们可以使用 `inotify-tools` 包中的 `inotifywait`。

```bash
kill <pid> && inotifywait -e close_write trace.pftrace
```

TAB: Android

在 Android 上，我们可以使用 toybox 中的 `inotifyd`。

```sh
kill <pid> && inotifyd - trace.pftrace:w | head -n0
```

</tabs?>
