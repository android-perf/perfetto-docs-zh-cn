# HEAP_PROFILE(1)

## 名称

heap_profile - 在 Android 设备上记录 heap profile

## 描述

`tools/heap_profile` 允许在 Android 上收集原生 heap profile。有关数据源的更多详细信息，请参见[采集 traces](/docs/data-sources/native-heap-profiler.md)。

```
用法: heap_profile [-h] [-i INTERVAL] [-d DURATION] [--no-start] [-p PIDS]
 [-n NAMES] [-c CONTINUOUS_DUMP] [--disable-selinux]
 [--no-versions] [--no-running] [--no-startup]
 [--shmem-size SHMEM_SIZE] [--block-client]
 [--block-client-timeout BLOCK_CLIENT_TIMEOUT]
 [--no-block-client] [--idle-allocations] [--dump-at-max]
 [--disable-fork-teardown] [--simpleperf]
 [--traceconv-binary TRACECONV_BINARY]
 [--print-config] [-o DIRECTORY]
```

## 选项

`-n`, `--name` _NAMES_
:：要分析的进程名称的逗号分隔列表。

`-p`, `--pid` _PIDS_
:：要分析的 PID 的逗号分隔列表。

`-i`, `--interval`
:：采样间隔。默认 4096 (4KiB)

`-o`, `--output` _DIRECTORY_
:：输出目录。

`--all-heaps`
:：从目标注册的所有堆中收集分配。

`--block-client`
:：当缓冲区已满时，阻塞客户端等待缓冲区空间。谨慎使用，因为这可能会显著降低客户端速度。这是默认选项。

`--block-client-timeout`
:：如果给出了 --block-client，则不要阻止任何分配超过此超时（微秒）。

`-c`, `--continuous-dump`
:：转储间隔（毫秒）。0 禁用连续转储。

`-d`, `--duration`
:：profiling 持续时间（毫秒）。0 运行直到被中断。默认：直到被用户中断。

`--disable-fork-teardown`
:：不要在 forks 中拆除客户端。这对于使用 vfork 的程序很有用。仅限 Android 11+。

`--disable-selinux`
:：在 profiling 持续时间内禁用 SELinux 强制执行。

`--dump-at-max`
:：转储最大内存使用量而不是转储时的内存使用量。

`-h`, `--help`
:：显示此帮助消息并退出

`--heaps` _HEAPS_
:：要收集的堆的逗号分隔列表，例如： malloc,art。需要 Android 12。

`--idle-allocations`
:：trace since 上次转储以来每个调用堆栈有多少字节未使用。

`--no-android-tree-symbolization`
:：不使用 Android 树中当前 lunched 的目标进行符号化。

`--no-block-client`
:：当缓冲区已满时，提前停止分析。

`--no-running`
:：不针对已经运行的进程。需要 Android 11。

`--no-start`
:：不启动 heapprofd。

`--no-startup`
:：不针对在分析期间启动的进程。需要 Android 11。

`--no-versions`
:：不获取关于 APK 的版本信息。

`--print-config`
:：打印配置而不是运行。用于调试。

`--shmem-size`
:：客户端和 heapprofd 之间的缓冲区大小。默认 8MiB。必须是 4096 的 2 次幂的倍数，至少 8192。

`--simpleperf`
:：获取 heapprofd 的 simpleperf 分析。这仅用于 heapprofd 开发。

`--traceconv-binary`
:：到本地 trace 到文本的路径。用于调试。