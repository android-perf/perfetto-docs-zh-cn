# Tracing API 和 ABI：接口和稳定性

本文档描述了 [Perfetto 客户端库][cli_lib] 的 API 和 ABI 接口，哪些可以预期长期稳定，哪些不可以。

#### 总结

- `include/perfetto/tracing/` 中的公共 C+- API 大部分是稳定的，但在 2020 年期间可能偶尔在编译时中断。
- `include/perfetto/ext/` 中的 C+- API 仅限内部，仅供 Chromium 使用。
- 用于 trace 共享库的新 C API/ABI 正在 `include/perfetto/public` 中开发。它尚未稳定。
- trace 协议 ABI 基于 protobuf-over-UNIX-socket 和共享内存。它是长期稳定的，并在两个方向上保持兼容性（旧服务 - 较新的客户端，反之亦然）。
- [DataSourceDescriptor][data_source_descriptor.proto]、[DataSourceConfig][data_source_config.proto] 和 [TracePacket][trace-packet-ref] proto 在更新时保持向后兼容，除非消息被标记为实验性。Trace Processor 处理导入较旧的 trace 格式。
- trace 文件和 trace 协议中都没有版本号，并且永远不会有版本号。在必要时使用功能标志。

## C++ API

客户端库 C++ API 允许应用程序通过自定义 trace 事件为 trace 做出贡献。其头文件位于 [`include/perfetto/`](/include/perfetto)。

此 API 有三个不同的层级，提供越来越高的表达能力，但代价是增加了复杂性。这三个层级彼此构建。(Google 员工，有关更多详细信息，另请参见 [go/perfetto-client-api](http://go/perfetto-client-api))。

![C++ API](/docs/images/api-and-abi.png)

### Track Event (公共)

这主要由 [`track_event.h`](/include/perfetto/tracing/track_event.h) 中定义的 `TRACE_EVENT*` 宏组成。这些宏为应用程序提供了一种快速简便的方法来添加常见类型的检测点（Slice、Counter、即时事件）。有关详细信息和说明，请参见 [客户端库文档][cli_lib]。

### 自定义数据源(公共)

这包括 [`tracing.h`](/include/perfetto/tracing.h) 中定义的 `perfetto::DataSource` 基类和 `perfetto::Tracing` 控制器类。这些类允许应用程序创建自定义数据源，这些数据源可以获取有关 trace 会话生命周期的通知并在 trace 中发出自定义 proto(例如，内存快照、合成器图层等)。

有关详细信息和说明，请参见 [客户端库文档][cli_lib]。

Track Event API 和自定义数据源都旨在作为公共 API。

WARNING: 团队仍在迭代此 API 接口。虽然我们尽量避免有意破坏，但在更新库时可能会偶尔遇到一些编译时中断。接口预计到 2020 年底稳定下来。

### 生产者/消费者 API(内部)

这包括 [`include/perfetto/ext`](/include/perfetto/ext) 目录中定义的所有接口。这些提供对 Perfetto 内部最低级别的访问（手动注册生产者和数据源、处理所有 IPC）。

这些接口将始终高度不稳定。我们强烈不建议任何项目依赖此 API，因为它太复杂且极难正确实现。此 API 接口仅适用于 Chromium 项目，该项目具有独特的挑战（例如，其自己的 IPC 系统、复杂的沙箱模型），并且有十多年来 chrome://tracing 遗留积累的数十个微妙用例。团队正在不断重塑此接口，以逐步将所有 Chrome Tracing 用例迁移到 Perfetto。

## Tracing 协议 ABI

Tracing 协议 ABI 包括以下二进制接口，允许操作系统中的各种进程为 trace 会话做出贡献并将 trace 数据注入 trace 服务：

  - [Socket 协议](#socket-protocol)
  - [共享内存布局](#shmem-abi)
  - [Protobuf 消息](#protos)

整个 trace 协议 ABI 在跨平台之间是二进制稳定的，并且在更新时保持向后和向前兼容。自 Android 9 (Pie, 2018) 的第一个修订以来，没有引入任何破坏性更改。另请参见下面的 [ABI 稳定性](#abi-stability) 部分。

![Tracing protocol](/docs/images/tracing-protocol.png)

### {#socket-protocol} Socket 协议

在最低级别，trace 协议通过类型为 `SOCK_STREAM` 的 UNIX socket 到 trace 服务启动。trace 服务在两个不同的 socket 上监听：producer 和 consumer。

![Socket protocol](/docs/images/socket-protocol.png)

两个 socket 使用相同的线路协议，即 [wire_protocol.proto](/protos/perfetto/ipc/wire_protocol.proto) 中定义的 `IPCFrame` 消息。线路协议简单基于以下形式的长度前缀消息序列：
```
< 4 字节 len little-endian > < proto 编码的 IPCFrame >

04 00 00 00 A0 A1 A2 A3 05 00 00 00 B0 B1 B2 B3 B4 ...
{ len: 4 } [ Frame 1 ] { len: 5 } [ Frame 2 ]
```

`IPCFrame` proto 消息定义了与 [protobuf 服务语法][proto_rpc] 兼容的请求/响应协议。`IPCFrame` 定义以下帧类型：

1. `BindService {producer, consumer} -> service`<br>
 绑定到两个服务端口之一（`producer_port` 或 `consumer_port`）。

2. `BindServiceReply service -> {producer, consumer}`<br>
 回复绑定请求，列出所有可用的 RPC 方法以及它们的方法 ID。

3. `InvokeMethod {producer, consumer} -> service`<br>
 调用由 `BindServiceReply` 返回的 ID 标识的 RPC 方法。调用将唯一的参数作为 proto 子消息。每个方法定义一对 _请求_ 和 _响应_ 方法类型。<br>
 例如，[producer_port.proto] 中定义的 `RegisterDataSource` 接受 `perfetto.protos.RegisterDataSourceRequest` 并返回 `perfetto.protos.RegisterDataSourceResponse`。

4. `InvokeMethodReply service -> {producer, consumer}`<br>
 返回相应调用的结果或错误标志。如果方法返回签名被标记为 `stream`(例如 `returns (stream GetAsyncCommandResponse)`)，则方法调用后可以跟多个 `InvokeMethodReply`，所有 `InvokeMethodReply` 都具有相同的 `request_id`。流中的所有回复（最后一个除外）都将具有 `has_more: true`，以通知客户端同一调用的更多回复将跟随。

以下是 IPC socket 上的流量外观：

```
# [Prd > Svc] 绑定到名为 "producer_port" 的远程服务的请求
request_id: 1
msg_bind_service { service_name: "producer_port" }

# [Svc > Prd] 服务回复。
request_id: 1
msg_bind_service_reply: {
 success: true
 service_id: 42
 methods: {id: 2; name: "InitializeConnection" }
 methods: {id: 5; name: "RegisterDataSource" }
 methods: {id: 3; name: "UnregisterDataSource" }
 ...
}

# [Prd > Svc] 方法调用(RegisterDataSource)
request_id: 2
msg_invoke_method: {
 service_id: 42 # "producer_port"
 method_id: 5 # "RegisterDataSource"

 # RegisterDataSourceRequest 消息的 proto 编码字节。
 args_proto: [XX XX XX XX]
}

# [Svc > Prd] RegisterDataSource 方法调用的结果。
request_id: 2
msg_invoke_method_reply: {
 success: true
 has_more: false # 此请求的 EOF

 # RegisterDataSourceResponse 消息的 proto 编码字节。
 reply_proto: [XX XX XX XX]
}
```

#### 生产者 socket

生产者 socket 公开 [producer_port.proto] 中定义的 RPC 接口。它允许进程通告数据源及其功能，接收有关 trace 会话生命周期的通知（trace 启动、停止）并发出 trace 数据提交和刷新请求。

此 socket 还用于生产者和服务在初始化期间交换 tmpfs 文件描述符，以设置将写入 trace 数据的[共享内存缓冲区](/docs/concepts/buffers.md)(异步)。

在 Android 上，此 socket 链接到 `/dev/socket/traced_producer`。在所有平台上，它可以通过 `PERFETTO_PRODUCER_SOCK_NAME` 环境变量覆盖。

在 Android 上，所有应用程序和大多数系统进程都可以连接到它（请参见 [SELinux 策略中的 `perfetto_producer`][selinux_producer]）。

在 Perfetto 代码库中，[`traced_probes`](/src/traced/probes/) 和 [`heapprofd`](/src/profiling/memory) 进程使用生产者 socket 来注入系统范围的 trace/profiling 数据。

#### 消费者 socket

消费者 socket 公开 [consumer_port.proto] 中定义的 RPC 接口。消费者 socket 允许进程控制 trace 会话（启动/停止 trace）并读回 trace 数据。

在 Android 上，此 socket 链接到 `/dev/socket/traced_consumer`。在所有平台上，它可以通过 `PERFETTO_CONSUMER_SOCK_NAME` 环境变量覆盖。

Trace 数据包含泄露系统活动（例如，哪些进程/线程正在运行）的敏感信息，并且可能允许侧信道攻击。因此，消费者 socket 仅打算向少数特权进程公开。

在 Android 上，只有 `adb shell` 域（由各种 UI 工具使用，如 [Perfetto UI](https://ui.perfetto.dev/）、[Android Studio](https://developer.android.com/studio) 或 [Android GPU Inspector](https://github.com/google/agi))和其他少数受信任的系统服务被允许访问消费者 socket(请参见 [SELinux 中的 traced_consumer][selinux_consumer])。

在 Perfetto 代码库中，[`perfetto`](/docs/reference/perfetto-cli) 二进制文件（Android 上的 `/system/bin/perfetto`）提供了消费者实现，并通过命令行界面公开它。

#### Socket 协议常见问题

_为什么使用 SOCK_STREAM 而不是 DGRAM/SEQPACKET？_

1. 允许通过 `adb forward localabstract` 直接通过 Android 上的 consumer socket，并允许主机工具直接与设备内 trace 服务通信。如今，Perfetto UI 和 Android GPU Inspector 都这样做。
2. 允许将来通过 TCP 或 SSH 隧道直接控制远程服务。
3. 因为 `SOCK_DGRAM` 的 socket 缓冲区极其有限，并且 MacOS 上不支持 `SOCK_SEQPACKET`。

_为什么不使用 gRPC？_

团队在 2017 年底评估了 gRPC 作为替代方案，但由于以下原因排除了它：（i）二进制大小和内存占用；（ii）在 UNIX socket 上运行完整的 HTTP/2 栈的复杂性和开销；（iii）缺乏对背压的细粒度控制。

_UNIX socket 协议在 Chrome 进程中使用吗？_

不。在 Chrome 进程内(浏览器应用程序，而非 CrOS)Perfetto 不使用任何 unix socket。相反，它使用功能等效的 Mojo 端点 [`Producer{Client,Host}` 和 `Consumer{Client,Host}`][mojom]。

### {#shmem-abi} 共享内存

本节描述生产者进程和 trace 服务之间共享的内存缓冲区的二进制接口（SMB）。

SMB 是一个暂存区域，用于解耦驻留在生产者中的数据源，并允许它们进行非阻塞异步写入。SMB 相对较小，通常为几百 KB。其大小由生产者在连接时配置。有关 SMB 的更多架构详细信息，另请参见 [缓冲区和数据流文档](/docs/concepts/buffers.md) 和 [shared_memory_abi.h] 源代码。

#### 获取 SMB

SMB 通过在 producer socket 上传递 tmpfs 文件描述符并从生产者和服务对其进行内存映射来获取。生产者在向服务发送 [`InitializeConnectionRequest`][producer_port.proto] 请求时指定所需的 SMB 大小和内存布局，这是连接后发送的第一个 IPC。默认情况下，服务创建 SMB 并通过 [`InitializeConnectionResponse`][producer_port.proto] IPC 回复将其文件描述符传递回生产者。服务的较新版本（Android R / 11） 允许由生产者创建 FD 并在请求中将其传递给服务。当服务支持此功能时，它通过设置 `InitializeConnectionResponse.using_shmem_provided_by_producer = true` 来确认请求。在撰写本文时，此功能仅由 Chrome 用于处理启动 trace 期间延迟的 Mojo 初始化。

#### SMB 内存布局：页面、块、片段和数据包

SMB 分区为固定大小的页面。SMB 页面必须是 4KB 的整数倍。唯一有效的尺寸是：4KB、8KB、16KB、32KB。

SMB 页面的大小由每个生产者在连接时通过 `InitializeConnectionRequest` 的 `shared_memory_page_size_hint_bytes` 字段确定，并且之后无法更改。SMB 中的所有页面都具有相同的大小，在生产者进程的整个生命周期中保持不变。

![Shared Memory ABI Overview](/docs/images/shmem-abi-overview.png)

**页面**是共享内存缓冲区的固定大小分区，只是块的容器。生产者可以使用有限的预定布局（1 页：1 块;1 页：2 块等）来分区每个页面 SMB。页面布局存储在页面头部的 32 位原子字中。相同的 32 位字还包含每个块的状态（每个块 2 位）。

固定总 SMB 大小（因此总内存开销）后，页面大小是以下之间的三角权衡：

1. IPC 流量：较小的页面 -> 较多的 IPC。
2. 生产者无锁自由度：较大的页面 -> 较大的块 -> 数据源可以写入更多数据而无需交换块和同步。
3. 写入饿死 SMB 的风险：较大的页面 -> 服务无法排空它们并且 SMB 保持充满的可能性更高。

另一方面，页面大小对由于碎片（请参见下面的块）导致的内存浪费没有影响。

**块**是页面的一部分，包含 [`TracePacket(s)`][trace-packet-ref](根 trace proto）的线性序列。

块定义了生产者和 trace 服务之间交互的粒度。当生产者填满块时，它会向服务发送 `CommitData` IPC，要求服务将其内容复制到中央非共享缓冲区。

块可以处于以下四种状态之一：

- `Free`：块是空闲的。服务永远不应触及它，生产者可以在写入时获取它并将其转换为 `BeingWritten` 状态。

- `BeingWritten`：块正在被生产者写入，并且尚未完成（即，仍有空间写入其他 trace 数据包）。服务永远不会改变 `BeingWritten` 状态的块的状态（但在刷新时仍会读取它们，即使它们不完整）。

- `Complete`：生产者已完成写入块，并且不会再次触及它。服务可以将其移动到其非共享环形缓冲区，并在完成后将块标记为 `BeingRead` -> `Free`。

- `BeingRead`：服务正在将页面移动到其非共享环形缓冲区中。生产者永远不应触及此状态的块。
 _注意:此状态最终从未使用，因为服务直接将块从 `Complete` 转换回 `Free`_。

块由生产者的一个数据源的一个线程独占拥有。

块本质上是单写入者单线程无锁竞技场。锁定仅在块已满并且需要获取新块时发生。

锁定仅在生产者进程范围内发生。通常不允许进程间锁定。生产者无法锁定服务，反之亦然。在最坏的情况下，两者中的任何一个都可以饿死 SMB，通过将所有块标记为正在被读取或写入。但这只有丢失 trace 数据的副作用。

只有当生产者中的数据源选择使用 [`BufferExhaustedPolicy.kStall`](/docs/concepts/buffers.md) 策略并且 SMB 已满时，才会在写入端（生产者）发生停滞。

**[TracePacket][trace-packet-ref]** 是 trace 的原子。撇开页面和块，trace 在概念上只是 TracePacket 的串联。TracePacket 可以很大（最多 64 MB），并且可以跨越多个块，因此跨越多个页面。因此，TracePacket 可以 >> 块大小，>> 页面大小，甚至 >> SMB 大小。块头带有用于处理 TracePacket 分割的元数据。

页面、块、片段和数据包概念概述：<br>
![Shared Memory ABI concepts](/docs/images/shmem-abi-concepts.png)

页面的内存布局：<br>
![SMB Page layout](/docs/images/shmem-abi-page.png)

因为数据包可以大于页面，所以块中的第一个和最后一个数据包可能是片段。

![TracePacket spanning across SMB chunks](/docs/images/shmem-abi-spans.png)

#### 通过 IPC 事后修补

如果 TracePacket 特别大，则包含其初始片段的块很可能在写入相同数据包的最后片段时已被提交到中央缓冲区并从 SMB 中移除。

Protobuf 中的嵌套消息以其长度为前缀。在零拷贝直接序列化场景（如 trace）中，仅当写入子消息的最后一个字段时才知道长度，并且无法预先知道。

因此，当写入数据包的最后一个片段时，写入者可能需要回填较早片段中的长度前缀，该片段现在可能已从 SMB 中消失。

为了做到这一点，trace 协议允许在 trace 服务将其复制到中央缓冲区后，通过 `CommitData` IPC（请参见 [`CommitDataRequest.ChunkToPatch`][commit_data_request.proto]）来修补块的内容。不保证片段仍将存在（例如，它可以在环形缓冲区模式中被覆盖）。只有当块仍在缓冲区中时，服务才会修补它，并且只有当写入它的生产者 ID 与通过 IPC 的修补请求的生产者 ID 匹配时才会修补（生产者 ID 不可伪造，并且与 IPC socket 文件描述符绑定）。

### {#protos} Proto 定义

以下 protobuf 消息是整个 trace 协议 ABI 的一部分，并在更新时保持向后兼容，除非在注释中标记为实验性。

TIP: 另请参见 [Protobuf 语言指南](https://developers.google.com/protocol-buffers/docs/proto#updating) 的 _更新消息类型_ 部分，了解在更新 protobuf 消息模式时的有效 ABI 兼容更改。

#### DataSourceDescriptor

在 [data_source_descriptor.proto] 中定义。此消息在生产者初始化期间通过 Producer socket 通过 IPC 从生产者 -> 服务发送，在任何 trace 会话启动之前。此消息用于注册通告数据源及其功能（例如，支持哪些 GPU HW Counters、它们的可能采样率）。

#### DataSourceConfig

在 [data_source_config.proto] 中定义。发送此消息：

- 通过 Consumer socket 通过 IPC 从消费者 -> 服务，作为消费者启动新 trace 会话时 [TraceConfig](/docs/concepts/config.md) 的一部分。

- 通过 Producer socket 通过 IPC 从服务 -> 生产者，作为对上述内容的反应。服务将通过 `TraceConfig` 中定义的每个 `DataSourceConfig` 部分传递给通告该数据源的相应生产者。

#### TracePacket

在 [trace_packet.proto] 中定义。这是任何数据源在生成任何形式的 trace 事件时写入 SMB 的根对象。有关完整详细信息，请参见 [TracePacket 参考][trace-packet-ref]。

## {#abi-stability} ABI 稳定性

trace 协议 ABI 的所有层都是长期稳定的，只能在保持向后兼容性时进行更改。

这是因为在每次 Android 版本中，`traced` 服务都会冻结在系统镜像中，而未捆绑的应用程序（例如 Chrome）和主机工具（例如 Perfetto UI）可以以更频繁的节奏更新。

以下两种情况都是可能的：

#### 生产者/消费者客户端比 trace 服务旧

这通常发生在 Android 开发期间。在某些时候，一些较新的代码会被放入 Android 平台并运送给用户，而客户端软件和主机工具将落后（或者仅仅是用户没有更新其应用程序/工具）。

trace 服务需要支持客户端与旧版本的生产者或消费者 trace 协议通信。

- 不要从服务中删除 IPC 方法。
- 假定稍后添加到现有方法的字段可能不存在。
- 对于较新的生产者/消费者行为，通过连接到服务时的功能标志通告这些行为。这方面的好例子是 [data_source_descriptor.proto] 中的 `will_notify_on_stop` 或 `handles_incremental_state_clear` 标志。

#### 生产者/消费者客户端比 trace 服务新

这是最可能的情况。在 2022 年的某个时候，大量手机仍将运行 Android P 或 Q，因此运行来自 ~2018-2020 的 trace 服务快照，但将运行最新版本的 Google Chrome。Chrome，在系统 trace 模式下配置时（即系统范围内 + 应用程序内 trace），连接到 Android 的 `traced` 生产者 socket 并谈论最新版本的 trace 协议。

生产者/消费者客户端代码需要能够与较旧版本的服务通信，该服务可能不支持一些较新的功能。

- [producer_port.proto] 中定义的较新的 IPC 方法在较旧的服务中将不存在。在 socket 上连接时，服务列出其 RPC 方法，客户端能够检测方法是否可用。在 C+- IPC 层，调用服务上不存在的方法会导致 `Deferred<>` promise 被拒绝。

- 现有 IPC 方法中的较新字段将被较旧版本的服务忽略。

- 如果生产者/消费者客户端依赖于服务的新行为，并且该行为无法通过方法的存在来推断，则必须通过 `QueryCapabilities` 方法公开新的功能标志。

## 静态链接 vs 共享库

Perfetto C++ 客户端库仅以静态库和单源合并 SDK 的形式可用（实际上它是静态库）。该库实现了 Tracing 协议 ABI，因此，一旦静态链接，仅取决于 socket 和共享内存协议 ABI，这些被保证是稳定的。

没有可用的 C++ 共享库分发。我们强烈不建议团队尝试将 C++ trace 库构建为共享库并从不同的链接器单元使用它。只要不导出任何 perfetto C++ API，就可以在同一共享库中链接并使用客户端库。

`PERFETTO_EXPORT_COMPONENT` 注释仅在 chromium 组件构建中构建客户端库的第三层时使用，不能轻易地重新用于划分其他两个 API 层的共享库边界。

这是因为客户端库 C++ API 的前两层大量使用内联头文件和 C++ 模板，以允许编译器查看大部分抽象层。

维护跨数百个内联函数和共享库的 C++ ABI 极其昂贵，并且极有可能以极其微妙的方式中断。因此，团队暂时排除了共享库分发。

正在开发新的 C 客户端库 API/ABI，但它尚未稳定。

[cli_lib]: /docs/instrumentation/tracing-sdk.md
[selinux_producer]: https://cs.android.com/search?q=perfetto_producer%20f:sepolicy.*%5C.te&sq=
[selinux_consumer]:https://cs.android.com/search?q=f:sepolicy%2F.*%5C.te%20traced_consumer&sq=
[mjom]: https://source.chromium.org/chromium/chromium/src/+/master:services/tracing/public/mojom/perfetto_service.mojom?q=producer%20f:%5C.mojom$%20perfetto&ss=chromium&originalUrl=https:%2F%2Fcs.chromium.org%2F
[proto_rpc]: https://developers.google.com/protocol-buffers/docs/proto#services
[producer_port.proto]: /protos/perfetto/ipc/producer_port.proto
[consumer_port.proto]: /protos/perfetto/ipc/consumer_port.proto
[trace_packet.proto]: /protos/perfetto/trace/trace_packet.proto
[data_source_descriptor.proto]: /protos/perfetto/common/data_source_descriptor.proto
[data_source_config.proto]: /protos/perfetto/config/data_source_config.proto
[trace-packet-ref]: /docs/reference/trace-packet-proto.autogen
[shared_memory_abi.h]: /include/perfetto/ext/tracing/core/shared_memory_abi.h
[commit_data_request.proto]: /protos/perfetto/common/commit_data_request.proto
[proto-updating]: https://developers.google.com/protocol-buffers/docs/proto#updating
