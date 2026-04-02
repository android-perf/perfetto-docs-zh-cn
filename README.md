# Perfetto 中文文档

[![在线预览](https://img.shields.io/badge/在线预览-GitHub%20Pages-blue)](https://gugu-perf.github.io/perfetto-docs-zh-cn/)
[![License](https://img.shields.io/badge/License-Apache%202.0-yellow.svg)](LICENSE)

[Perfetto Docs](https://perfetto.dev/docs) 的中文翻译。

**在线阅读**: https://gugu-perf.github.io/perfetto-docs-zh-cn/


## 快速开始

### 本地部署

```bash
# 克隆仓库
git clone https://github.com/GuGu-Perf/perfetto-docs-zh-cn.git
cd perfetto-docs-zh-cn

# 本地部署（自动构建并启动服务器）
bash .project/deploy.sh

# 访问 http://localhost:8082/docs/
```

### GitHub Pages 部署

```bash
bash .project/deploy.sh --gh-pages
```

## 参与贡献

欢迎参与翻译改进！请查看 [CONTRIBUTING.md](CONTRIBUTING.md) 了解详细指南。

快速贡献步骤：
1. Fork 本仓库
2. 创建分支 `git checkout -b translate/your-branch`
3. 翻译文档并本地预览
4. 提交 PR

## 项目文档

- [CONTRIBUTING.md](CONTRIBUTING.md) - 贡献指南
- [DEPLOYMENT.md](.project/DEPLOYMENT.md) - 部署指南
- [TRANSLATION_GUIDE.md](.project/TRANSLATION_GUIDE.md) - 翻译规范

## 上游同步

本项目跟踪的官方仓库：[google/perfetto/docs](https://github.com/google/perfetto/tree/main/docs)

**检测上游更新**
```bash
bash .project/sync-check.sh
```

**最新同步记录**: [.project/LAST_SYNC](.project/LAST_SYNC)

## 许可证

[Apache 2.0 License](LICENSE)

## 致谢

voidice@gmail.com;zhuyong7@honor.com;xiaolu5@honor.com;
