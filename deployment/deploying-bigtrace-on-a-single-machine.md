# 在单机上部署 Bigtrace

NOTE: 本文档是为 Bigtrace 服务的管理员而非 Bigtrace 用户设计的。这也为非 Google 员工设计 - Google 员工应查看 `go/bigtrace`。

在单机上部署 Bigtrace 有多种方式：

1. 手动运行 Orchestrator 和 Worker 可执行文件
2. docker-compose
3. minikube

NOTE: 选项 1 和 2 用于开发目的，不推荐用于生产环境。对于生产环境，请遵循[在 Kubernetes 上部署 Bigtrace](deploying-bigtrace-on-kubernetes) 的说明。

## 前提条件

要构建 Bigtrace，你必须首先遵循[快速入门设置和构建](/docs/contributing/getting-started.md#quickstart）步骤，但使用 `tools/install-build-deps --grpc` 以安装 Bigtrace 和 gRPC 所需的依赖项。

## 手动运行 Orchestrator 和 Worker 可执行文件

要使用可执行文件在本地手动运行 Bigtrace，你必须先构建可执行文件，然后按如下方式运行它们：

### 构建 Orchestrator 和 Worker 可执行文件

```bash
tools/ninja -C out/[BUILD] orchestrator_main
tools/ninja -C out/[BUILD] worker_main
```

### 运行 Orchestrator 和 Worker 可执行文件

使用命令行参数运行 Orchestrator 和 Worker 可执行文件：

```bash
./out/[BUILD]/orchestrator_main [args]
./out/[BUILD]/worker_main [args]
```

### 示例

创建一个包含 Orchestrator 和三个 Worker 的服务，可以使用 Python API 在本地与之交互。

```bash
tools/ninja -C out/linux_clang_release orchestrator_main
tools/ninja -C out/linux_clang_release worker_main

./out/linux_clang_release/orchestrator_main -w "127.0.0.1" -p "5052" -n "3"
./out/linux_clang_release/worker_main --socket="127.0.0.1:5052"
./out/linux_clang_release/worker_main --socket="127.0.0.1:5053"
./out/linux_clang_release/worker_main --socket="127.0.0.1:5054"
```

## docker-compose

为了在没有 Kubernetes 开销的情况下测试 gRPC，可以使用 docker-compose，它会构建 infra/bigtrace/docker 中指定的 Dockerfile，并创建 Orchestrator 和指定的一组 Worker 副本的容器化实例。

```bash
cd infra/bigtrace/docker
docker compose up
# 或者如果使用 docker compose 独立二进制文件
docker-compose up
```

这将构建并启动 `compose.yaml` 中指定的 Worker（默认为 3 个）和 Orchestrator。

## minikube

minikube 集群可用于在本地机器上模拟 Kubernetes 集群设置。这可以通过脚本 `tools/setup_minikube_cluster.sh` 创建。

这将启动一个 minikube 集群，构建 Orchestrator 和 Worker 镜像，并将它们部署在集群上。然后可以通过 Python API 等客户端，使用 `minikube ip:5051` 作为 Orchestrator 服务地址与之交互。
