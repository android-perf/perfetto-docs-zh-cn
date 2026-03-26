# TRACED(8)

## 名称

traced - Perfetto tracing 服务

## 描述

`traced` 是 Perfetto
[基于服务的架构](/docs/concepts/service-model.md）中的中央守护程序。它充当系统上所有tracing 活动的总站，调解想要记录数据的实体（生产者）和想要控制和读取 traces 的实体（消费者）之间的交互。

在典型的系统范围 tracing设置中（如 Android 或 Linux 上）,`traced` 作为长期运行的后台守护程序运行，通常在系统启动时启动。

## 架构

Perfetto 的架构旨在提高安全性和稳健性，以 `traced`
为核心。该模型由三个主要组件组成：

- **消费者：** 受信任的客户端，用于配置和启动Tracing Session。
 `perfetto` 命令行工具是消费者的常见示例。
- **服务(`traced`):** 中央守护程序，管理Tracing Session、
 缓冲区和数据源注册表。
- **生产者：** 不受信任的客户端，生成 trace data。生产者
 向 `traced` 公告其可用的数据源。生产者的关键示例是
 [`traced_probes`](/docs/reference/traced_probes.md)，它提供广泛系统级别的数据源。

这种解耦架构允许多个独立的生产者和消费者同时与 tracing system 交互而不会相互干扰。

## 核心职责

`traced` 本身不生成 trace data。其主要作用是管理一个或多个Tracing Session的后勤：

- **会话管理**： 它可以处理多个并发的Tracing Session，
 每个会话都有自己的配置。它有效地多路复用这些会话，
 确保来自不同会话的数据保持分离。
- **缓冲区管理**： 它拥有中央trace 缓冲区，最终的
 trace data 在这些缓冲区中组装。它负责根据 trace 配置分配、管理和释放这些缓冲区(例如，环形
 缓冲区与满时停止策略)。
- **生产者和数据源注册表**： 它维护所有
 连接的生产者及其公告的数据源的注册表。
- **配置路由**： 当消费者启动 trace 时，它将 trace
 配置发送到 `traced`。然后，服务解析此配置并将
 相关的子配置转发到适当的生产者以启动其数据
 源。
- **数据整合与安全**： 它促进从生产者的不受信任的共享内存页到其自身的安全
 中央 trace 缓冲区的安全数据移动。这种隔离防止恶意或有缺陷的生产者
 损坏其他人的 trace data。

## 交互模型

实体主要通过两个通道与 `traced` 交互：

1. **IPC 通道**： 用于相对低频的控制信号。
  - **生产者**使用它来注册自己、公告数据源，并
 接收开始/停止命令。
  - **消费者**使用它来发送trace 配置、启动/停止会话，并
 读回最终 trace data。
  - 在 POSIX 系统上，这通常是 UNIX 流套接字。
2. **共享内存**： 用于高频、低开销的数据传输。
  - 每个生产者都有一个专用共享内存区域，仅与
 `traced` 共享。
  - 生产者将 trace data 包写入此内存而不会阻塞。
  - `traced` 定期扫描这些内存区域并将有效的、
 完成的数据包复制到其中央 trace 缓冲区中。

### 命令行选项

`traced` 支持以下命令行选项：

- `--background`：立即退出并继续在后台运行。
- `--version`：打印版本号并退出。
- `--set-socket-permissions
 <prod_group>:<prod_mode>:<cons_group>:<cons_mode>`：设置生产者和消费者套接字的组所有权和权限模式。这对于控制哪些用户和进程可以作为生产者或消费者连接到 `traced` 很重要。
- `--enable-relay-endpoint`：通过 `traced_relay` 启用多机 tracing的端点。

## 内置生产者

在 Android 上，`traced` 还包括一个具有几个关键
职责的内置生产者：

- **metatrace**： 它提供 `perfetto.metatrace` 数据源，该
 数据源启用 `traced` 服务本身的 tracing。这对于调试
 Perfetto 和捕获内部统计信息(如时钟快照和
 有关连接的生产者的详细信息)很有用。
- **惰性服务启动**： 它可以按需动态启动其他 tracing 守护程序
 (如 `heapprofd` 和 `traced_perf`)。when trace 配置请求其中一个守护程序提供的数据源时，内置
 生产者确保启动相应的服务。它还会在不再需要时在延迟后停止该服务。
- **系统级别集成**： 它处理与
 Android 平台的各种其他集成，例如管理 heap memory profiling session 的 Counters 和控制系统属性以在图形组件中启用 tracing。

## 安全

基于服务的架构考虑了安全性。生产者是不受信任的，彼此隔离并与中央服务隔离。UNIX 套接字权限的使用允许管理员控制谁可以作为生产者或消费者连接到 tracing 服务。