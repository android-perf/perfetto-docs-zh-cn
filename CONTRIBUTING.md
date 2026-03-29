# 贡献指南

本文档将帮助你了解如何参与翻译工作。

## 翻译工作流

### 1. 检查上游更新

运行同步检查脚本获取官方文档更新：

```bash
bash .project/sync-check.sh --check
```

### 2. 使用 AI 翻译

借助 AI 工具按照[翻译规范指南](.project/TRANSLATION_GUIDE.md)进行初步翻译。


### 4. 本地预览

运行部署脚本查看效果：

```bash
bash .project/deploy.sh
```

### 5. 人工校对

检查翻译质量，修正不通顺的地方。

### 6. 更新同步记录

翻译完成后更新同步点：

```bash
bash .project/sync-check.sh --update
```

### 7. 提交审核

```bash
git add .
git commit -m "translate: 翻译 XXX 文档"
git push origin translate/your-branch-name
```

然后在 GitHub 上创建 Pull Request，等待审核合并。

## 翻译规范

详细的翻译规范请参考 **[翻译规范指南](.project/TRANSLATION_GUIDE.md)**。

## 提交规范

### Commit Message 格式

```
<type>: <subject>

<body>
```

### Type 类型

| 类型 | 说明 |
|------|------|
| `translate` | 翻译新文档 |
| `fix` | 修正翻译错误 |
| `improve` | 改进翻译质量 |
| `chore` | 构建/工具相关 |

### 示例

```bash
# 翻译新文档
git commit -m "translate: 完成 concepts/buffers.md 翻译"

# 修正错误
git commit -m "fix: 修正 analysis/metrics.md 中的术语错误"

# 改进翻译
git commit -m "improve: 优化 getting-started.md 的表达"
```

## 常见问题

### Q: 翻译过程中遇到不理解的术语怎么办？

A: 
1. 首先查看术语表
2. 参考已有翻译文件中的处理方式
3. 在 Issue 中讨论确认

### Q: 可以修改已经翻译好的文件吗？

A: 可以！如果发现翻译错误或有更好的表达方式，欢迎提交改进。

## 同步官方更新

项目维护者会定期同步官方文档。我们提供了同步检查工具来帮助检测上游更新。

### 检查上游更新

```bash
# 检查是否有新的文档更新
bash .project/sync-check.sh --check
```

### 更新同步记录

翻译完成后，更新同步记录：

```bash
bash .project/sync-check.sh --update
```


### 如何参与维护

1. **同步官方更新** - 检查官方文档是否有新增或修改
2. **改进翻译质量** - 优化现有文档的表达
3. **修正错误** - 修复翻译错误或术语不一致

## 联系我们

- 提交 Issue：[GitHub Issues](https://github.com/GuGu-Perf/perfetto-docs-zh-cn/issues)
- 讨论区：[GitHub Discussions](https://github.com/GuGu-Perf/perfetto-docs-zh-cn/discussions)

感谢你的贡献！
