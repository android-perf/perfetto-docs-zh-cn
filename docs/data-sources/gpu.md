# GPU

Perfetto 支持在多种使用场景下 Tracing GPU 活动，从 Android 移动端图形处理到高端多 GPU 计算负载。

![](/docs/images/gpu-counters.png)

## 数据源

以下数据源可用于 GPU Tracing：

| 数据源 | 配置 | 用途 |
|---|---|---|
| `gpu.counters` | [gpu\_counter\_config.proto](/protos/perfetto/config/gpu/gpu_counter_config.proto) | 周期性或插桩式 GPU Counter 采样 |
| `gpu.renderstages` | [gpu\_renderstages\_config.proto](/protos/perfetto/config/gpu/gpu_renderstages_config.proto) | GPU 渲染阶段和计算活动时间线 |
| `vulkan.memory_tracker` | [vulkan\_memory\_config.proto](/protos/perfetto/config/gpu/vulkan_memory_config.proto) | Vulkan 内存分配和绑定 Tracing |
| `gpu.log` | *(无)* | GPU 调试日志消息 |
| `linux.ftrace` | [ftrace\_config.proto](/protos/perfetto/config/ftrace/ftrace_config.proto) | GPU 频率、内存总量、DRM 调度器事件 |

GPU 生产者通常会使用硬件特定的后缀注册数据源，例如 `gpu.counters.adreno` 或 `gpu.renderstages.mali`。Tracing 服务使用精确名称匹配，因此 trace 配置必须使用相同的带后缀名称。Trace Processor 根据 proto 字段类型解析 GPU 数据，因此所有带后缀的变体都会被相同处理。当针对特定 GPU 厂商的生产者时，请在 trace 配置中使用带后缀的名称：

```
data_sources: {
    config {
        name: "gpu.counters"
        gpu_counter_config {
            counter_period_ns: 1000000
            counter_ids: 1
        }
    }
}
```

Trace 包含 `gpu_id` 字段用于区分不同的 GPU，以及 `machine_id` 字段用于在多机环境中区分不同的机器。GPU 硬件元数据（名称、厂商、架构、UUID、PCI BDF）通过 [GpuInfo](/protos/perfetto/trace/system_info/gpu_info.proto) trace packet 记录。

## Android

### GPU 频率

GPU 频率通过 ftrace 收集：

```
data_sources: {
    config {
        name: "linux.ftrace"
        ftrace_config {
            ftrace_events: "power/gpu_frequency"
        }
    }
}
```

### GPU Counter

Android GPU 生产者必须使用 Counter 描述符模式 1：`GpuCounterDescriptor` 直接嵌入到会话的第一个 `GpuCounterEvent` packet 中，并且 Counter ID 是全局的。这是 CDD/CTS 合规性所要求的。

GPU Counter 通过指定设备特定的 Counter ID 进行采样。可用的 Counter ID 在数据源描述符的 `GpuCounterSpec` 中描述。

```
data_sources: {
    config {
        name: "gpu.counters"
        gpu_counter_config {
            counter_period_ns: 1000000
            counter_ids: 1
            counter_ids: 3
            counter_ids: 106
            counter_ids: 107
            counter_ids: 109
        }
    }
}
```

`counter_period_ns` 设置所需的采样间隔。

### GPU 内存

每个进程的总 GPU 内存使用量通过 ftrace 收集：

```
data_sources: {
    config {
        name: "linux.ftrace"
        ftrace_config {
            ftrace_events: "gpu_mem/gpu_mem_total"
        }
    }
}
```

### GPU 渲染阶段

渲染阶段 Tracing 提供 GPU 活动（图形和计算提交）的时间线：

```
data_sources: {
    config {
        name: "gpu.renderstages"
    }
}
```

### Vulkan 内存

Vulkan 内存分配和绑定事件可以通过以下方式 Tracing：

```
data_sources: {
    config {
        name: "vulkan.memory_tracker"
        vulkan_memory_config {
            track_driver_memory_usage: true
            track_device_memory_usage: true
        }
    }
}
```

### GPU 日志

GPU 调试日志消息可以通过启用该数据源来收集：

```
data_sources: {
    config {
        name: "gpu.log"
    }
}
```

## 高端 GPGPU

对于高性能和数据中心 GPU 负载（CUDA、OpenCL、HIP），Perfetto 支持多 GPU 和多机 Tracing，并提供插桩式 Counter 采样。

### 插桩式 Counter 采样

除了全局采样外，还可以通过在 GPU 命令缓冲区中插桩来采样 Counter。这提供了每次提交级别的 Counter 值：

```
data_sources: {
    config {
        name: "gpu.counters"
        gpu_counter_config {
            counter_ids: 1
            counter_ids: 2
            instrumented_sampling: true
        }
    }
}
```

对于 GPGPU 使用场景，推荐使用 Counter 描述符模式 2：生产者发送通过 IID 引用的 `InternedGpuCounterDescriptor`，为每个可信序列提供独立的局部 Counter ID。这避免了模式 1 所需的全局协调，并自然地支持多个生产者和 GPU。有关两种模式的详细信息，请参阅 [gpu\_counter\_event.proto](/protos/perfetto/trace/gpu/gpu_counter_event.proto)。

Counter 名称和 ID 由 GPU 生产者通过数据源描述符中的 `GpuCounterSpec` 发布。Counter 按组分类（SYSTEM、VERTICES、FRAGMENTS、PRIMITIVES、MEMORY、COMPUTE、RAY_TRACING），并包含度量单位和描述。

### 多 GPU

系统中的每个 GPU 都分配了一个 `gpu_id`。Counter 事件、渲染阶段和其他 GPU trace 数据都携带此 ID，以便 UI 可以按 GPU 对 Track 进行分组。GPU 硬件详细信息通过 [GpuInfo](/protos/perfetto/trace/system_info/gpu_info.proto) 消息记录，包括：

- `name`、`vendor`、`model`、`architecture`
- `uuid`（16 字节标识符）
- `pci_bdf`（PCI 总线/设备/功能）

### 多机

在跨多台机器进行 Tracing 时，每个 GPU trace 事件还携带 `machine_id`，用于区分该 GPU 属于哪台机器。Perfetto UI 在 GPU Track 旁显示机器标签。

### 渲染阶段事件关联

GPU 渲染阶段事件可以使用 `GpuRenderStageEvent` 上的 `event_wait_ids` 字段声明对其他渲染阶段事件的依赖关系。每个条目是该事件在运行前需要等待的另一个渲染阶段事件的 `event_id`。trace processor 使用这些信息在关联的 GPU 切片之间创建流箭头。

示例：一个依赖于先前异步 memcpy 的 matmul kernel：

```
gpu_render_stage_event {
    event_id: 1
    duration: 50000
    hw_queue_iid: 1
    stage_iid: 2
    context: 0
    name: "Memcpy HtoD"
}

gpu_render_stage_event {
    event_id: 2
    duration: 40000
    hw_queue_iid: 3
    stage_iid: 4
    context: 0
    name: "matmul_kernel"
    event_wait_ids: 1
}
```

这会创建一个从 memcpy 事件（event\_id 1）到 matmul kernel（event\_id 2）的流，在 Perfetto UI 中可视化依赖关系。
