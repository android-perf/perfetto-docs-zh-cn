# 基于 Service 的模型

![Perfetto Stack](https://storage.googleapis.com/perfetto/markdown_img/producer-service-consumer.png)

## 服务

trace Service 是一个长期存在的实体（Linux/Android 上的系统守护进程，Chrome 中的服务），具有以下职责：

- 维护活跃生产者及其数据源的注册表。
- 拥有 Trace 缓冲区。
- 处理多个 Trace 会话的多路复用。
- 将 Trace 配置从消费者路由到相应的生产者。
- 告诉生产者何时 Trace 以及 Trace 什么。
- 将数据从生产者的共享内存缓冲区移动到中央非共享 Trace 缓冲区。

## 生产者

生产者是一个不受信任的实体，提供为 Trace 做出贡献的能力。在多进程模型中，生产者几乎总是对应于 Trace Service 的客户端进程。它通告其使用一个或多个数据源为 Trace 做出贡献的能力。每个生产者具有确切地：

- 一个共享内存缓冲区，与 Trace Service 独占共享。
- 与 Trace Service 的一个 IPC 通道。

生产者与消费者完全解耦（技术上和概念上）。生产者对以下一无所知：

- 有多少消费者连接到服务。
- 有多少 Trace 会话处于活动状态。
- 有多少其他生产者被注册或处于活动状态。
- 由其他生产者编写的 Trace 数据。

NOTE: 在极少数情况下，一个进程可以托管多个生产者，因此有多个共享内存缓冲区。对于捆绑第三方库的进程可能是这种情况，而这些库又包括 Perfetto 客户端库。具体示例：在未来某个时候，Chrome 可能会为一个 Producer 用于主项目中的 Trace，一个用于 V8，一个用于 Skia(对于每个子进程)。

## 消费者

消费者是一个受信任的实体（Linux/Android 上的命令行客户端，Chrome 中浏览器进程的接口），它（非独占地）控制 Trace Service 并回读(破坏性地)Trace 缓冲区。消费者有能力：

- 将 [Trace 配置](#）发送到服务，确定：
  - 创建多少个 Trace 缓冲区。
  - Trace 缓冲区应该有多大。
  - 每个缓冲区的策略（*环形缓冲区* 或 *满时停止*）。
  - 启用哪些数据源。
  - 每个数据源的配置。
  - 每个配置的数据源生成的数据的目标缓冲区。
- 启用和禁用 Trace。
- 回读 Trace 缓冲区：
  - 通过 IPC 通道流式传输数据。
  - 将文件描述符传递给服务并指示它定期将 Trace 缓冲区保存到文件中。

## 数据源

数据源是生产者公开的提供某些 Trace 数据的能力。数据源几乎总是定义自己的模式（一个 protobuf），由以下组成：

- 最多一个 `DataSourceConfig` 子消息：

 ([示例](/protos/perfetto/config/ftrace/ftrace_config.proto))
- 一个或多个 `TracePacket` 子消息
 ([示例](/protos/perfetto/Trace/ps/process_tree.proto))

不同的生产者可能会公开相同的数据源。一个具体的示例是使用 [Tracing SDK 中的 Track Event](/docs/instrumentation/track-events) 的进程的情况。它在每个参与的进程中公开相同的 `track_event` 数据源。


## IPC 通道

在多进程场景中，每个生产者和每个消费者使用 IPC 通道与 Service 交互。IPC 仅用于非快速路径交互，主要是握手，例如启用/禁用 Trace(消费者)、（取消）注册和启动/停止数据源（生产者）。IPC 通常不用于传输 Trace 的 protobuf。Perfetto 提供了一个 POSIX 友好的 IPC 实现，基于 UNIX socket 上的 protobuf(参见 [Socket 协议](/docs/design-docs/api-and-abi#socket-protocol))。

不强制要求该 IPC 实现。Perfetto 允许嵌入器：

- 包装其自己的 IPC 子系统（例如，Chromium 中的 Perfetto 使用 Mojo）
- 完全不使用 IPC 机制，只需通过 `PostTask(s)` 短路生产者 <> Service <> 消费者交互。

## 共享内存缓冲区

生产者使用称为 [ProtoZero](/docs/design-docs/protozero.md) 的特殊库，以 protobuf 编码的二进制 blob 的形式，将 Trace 数据直接写入其共享内存缓冲区。共享内存缓冲区：

- 具有固定的且通常较小的尺寸（可配置，默认：128 KB）。
- 是 ABI 并且必须保持向后兼容性。
- 由生产者的所有数据源共享。
- 独立于 Trace 缓冲区的数量和大小。
- 独立于消费者的数量。
- 分成可变大小的 *块*。

每个块：

- 由一个生产者线程独占拥有（或通过互斥锁共享）。
- 包含 `TracePacket(s)` 的线性序列，或其片段。`TracePacket` 可以跨越多个块，分段不会暴露给消费者（消费者总是看到完整的包，就好像它们从未被分段一样）。
- 可以由恰好一个 `TraceWriter` 拥有和写入。
- 是可靠且有序序列的一部分，由 `WriterID` 标识：序列中的包保证按顺序回读，没有间隙和重复。

有关此缓冲区的二进制格式的更多详细信息，请参见 [shared_memory_abi.h](/include/perfetto/ext/tracing/core/shared_memory_abi.h) 中的注释。
