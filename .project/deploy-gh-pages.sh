#!/bin/bash
#
# GitHub Pages 部署脚本
# 将构建好的 Perfetto 站点部署到 GitHub Pages
#

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 打印信息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCS_ZH_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$DOCS_ZH_DIR")"
PERFETTO_DIR="$PROJECT_ROOT/perfetto"

# GitHub 仓库名（用于路径修复）
REPO_NAME="perfetto-docs-zh-cn"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║      GitHub Pages 部署脚本                              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# 检查构建输出是否存在
if [ ! -d "$PERFETTO_DIR/out/perfetto.dev/site" ]; then
    print_error "构建输出不存在: $PERFETTO_DIR/out/perfetto.dev/site"
    print_info "请先运行本地部署脚本: ./.project/deploy.sh"
    exit 1
fi

print_success "构建输出已找到"

# 切换到 gh-pages 分支
cd "$DOCS_ZH_DIR"

print_info "切换到 gh-pages 分支..."
# 如果不在 gh-pages 分支，则切换过去
if [ "$(git rev-parse --abbrev-ref HEAD)" != "gh-pages" ]; then
    git checkout gh-pages 2>/dev/null || git checkout -b gh-pages
fi

# 清空旧文件
print_info "清空旧文件..."
git rm -rf . 2>/dev/null || rm -rf ./* ./.[!.]* 2>/dev/null || true

# 复制新构建的文件
print_info "复制构建文件..."
cp -r "$PERFETTO_DIR/out/perfetto.dev/site/"* .

# 创建 .nojekyll 文件（禁用 Jekyll 处理）
touch .nojekyll
print_success "已创建 .nojekyll 文件"

# =============================================================================
# 修复 GitHub Pages 路径（关键步骤！）
# =============================================================================

print_info ""
print_info "修复 GitHub Pages 路径..."
print_info "仓库名: $REPO_NAME"

# 修复 index.html
print_info "  修复 index.html..."
sed -i '' "s|href=\"/assets/|href=\"/$REPO_NAME/assets/|g" index.html
sed -i '' "s|src=\"/assets/|src=\"/$REPO_NAME/assets/|g" index.html
sed -i '' "s|href=\"/docs/|href=\"/$REPO_NAME/docs/|g" index.html
sed -i '' "s|src=\"/docs/|src=\"/$REPO_NAME/docs/|g" index.html
sed -i '' "s|href=\"/\"|href=\"/$REPO_NAME/\"|g" index.html

# 修复所有 docs/*.html
print_info "  修复 docs/*.html..."
for file in $(find docs -name "*.html"); do
    sed -i '' "s|href=\"/assets/|href=\"/$REPO_NAME/assets/|g" "$file"
    sed -i '' "s|src=\"/assets/|src=\"/$REPO_NAME/assets/|g" "$file"
    sed -i '' "s|href=\"/docs/|href=\"/$REPO_NAME/docs/|g" "$file"
    sed -i '' "s|src=\"/docs/|src=\"/$REPO_NAME/docs/|g" "$file"
    sed -i '' "s|data=\"/docs/|data=\"/$REPO_NAME/docs/|g" "$file"
    sed -i '' "s|href=\"/\"|href=\"/$REPO_NAME/\"|g" "$file"
done

# 修复 assets/script.js（mermaid.js 路径）
print_info "  修复 assets/script.js..."
sed -i '' "s|\"\/assets\/mermaid.min.js\"|\"\/$REPO_NAME\/assets\/mermaid.min.js\"|g" assets/script.js

# 修复 assets/style.css（sprite.png 路径）
print_info "  修复 assets/style.css..."
sed -i '' "s|\"\/assets\/sprite.png\"|\"\/$REPO_NAME\/assets\/sprite.png\"|g" assets/style.css

# 为所有 docs 文件添加 .html 扩展名
print_info "  添加 .html 扩展名..."
# 先处理根目录下的无扩展名文件（如 tracing-101）
for file in docs/*; do
    if [ -f "$file" ] && [[ ! "$file" =~ \. ]]; then
        mv "$file" "$file.html"
        print_info "    重命名: $(basename "$file") -> $(basename "$file").html"
    fi
done
# 再处理子目录
find docs -type f ! -name "*.png" ! -name "*.jpg" ! -name "*.gif" ! -name "*.svg" ! -name "*.ico" ! -name "*.html" -exec sh -c 'mv "$1" "$1.html"' _ {} \; 2>/dev/null || true

# 为所有链接添加 .html 后缀
print_info "  为链接添加 .html 后缀..."
find . -name "*.html" ! -path "./.git/*" -exec sed -i '' "s|href=\"\/$REPO_NAME\/docs\/\([^\"]*\)\"|href=\"\/$REPO_NAME\/docs\/\1.html\"|g" {} \;

# 修复错误的 docs/.html 链接
print_info "  修复错误链接..."
find . -name "*.html" ! -path "./.git/*" -exec sed -i '' "s|href=\"\/$REPO_NAME\/docs\/.html\"|href=\"\/$REPO_NAME\/docs\/\"|g" {} \;

print_success "路径修复完成"

# =============================================================================
# 提交并推送
# =============================================================================

print_info ""
print_info "提交更改..."
git add -A
git commit -m "deploy: 更新 GitHub Pages ($(date +%Y-%m-%d-%H:%M:%S))" || print_warning "没有更改需要提交"

print_info "推送到 origin/gh-pages..."
git push origin gh-pages --force

print_success ""
print_success "========================================"
print_success "GitHub Pages 部署成功！"
print_success "========================================"
print_success ""
print_success "访问地址: https://your-username.github.io/$REPO_NAME/"
print_success ""
print_success "注意: GitHub Pages 可能需要 1-2 分钟才能生效"
print_success ""

# 切回 main 分支
git checkout main
