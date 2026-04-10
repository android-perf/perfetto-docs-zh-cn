#!/bin/bash
#
# 上游同步检测脚本
# 手动检查官方仓库是否有更新
#
# 用法:
#   bash sync-check.sh           # 检查上游更新
#   bash sync-check.sh --update  # 更新 LAST_SYNC 为上游最新
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
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
# perfetto 仓库放在与中文文档项目平级的目录
PERFETTO_DIR="$(dirname "$PROJECT_ROOT")/perfetto"
LAST_SYNC_FILE="$SCRIPT_DIR/LAST_SYNC"

# 显示帮助
show_help() {
    echo ""
    echo "Perfetto 上游同步检测工具"
    echo ""
    echo "用法:"
    echo "  bash sync-check.sh --check    检查 docs/ 目录是否有更新"
    echo "  bash sync-check.sh --update   更新 LAST_SYNC 为上游最新"
    echo "  bash sync-check.sh --help     显示此帮助信息"
    echo ""
    echo "说明:"
    echo "  本工具用于检查官方 perfetto/docs 目录是否有更新"
    echo "  并在翻译完成后更新同步记录"
    echo ""
}

# 检查参数
UPDATE_MODE=false
CHECK_MODE=false

if [[ "$1" == "--help" || "$1" == "-h" || -z "$1" ]]; then
    show_help
    exit 0
elif [[ "$1" == "--check" ]]; then
    CHECK_MODE=true
elif [[ "$1" == "--update" ]]; then
    UPDATE_MODE=true
else
    echo "错误: 未知参数 '$1'"
    show_help
    exit 1
fi

echo ""
echo "========================================"
echo "Perfetto 上游同步检测"
echo "========================================"
echo ""

# 检查 perfetto 目录是否存在
if [ ! -d "$PERFETTO_DIR/.git" ]; then
    print_warning "Perfetto 仓库不存在，正在克隆到平级目录..."
    cd "$(dirname "$PROJECT_ROOT")"
    git clone https://github.com/google/perfetto.git perfetto
    print_success "Perfetto 仓库克隆完成: $PERFETTO_DIR"
fi

# 从 LAST_SYNC 文件读取上次同步的 commit
if [ -f "$LAST_SYNC_FILE" ]; then
    # 读取第一行（跳过注释行）
    LAST_SYNC_LINE=$(grep -v "^#" "$LAST_SYNC_FILE" | grep -v "^$" | head -1)
    LAST_SYNC_COMMIT=$(echo "$LAST_SYNC_LINE" | awk '{print $1}')
else
    print_warning "未找到 LAST_SYNC 文件"
    print_info "请创建 .project/LAST_SYNC 文件记录上次同步点"
    LAST_SYNC_COMMIT="unknown"
fi

cd "$PERFETTO_DIR"

# 强制同步本地仓库与远程一致
print_info "正在强制同步本地仓库与远程一致..."
git clean -fd 2>/dev/null || true
git reset --hard HEAD 2>/dev/null || true
git checkout main 2>/dev/null || git checkout -b main origin/main
git pull origin main --ff-only
print_success "本地仓库已同步到最新"

# 远程最新 commit（只看 docs/ 目录）
REMOTE_COMMIT=$(git rev-parse HEAD)
REMOTE_SHORT=$(git log -1 --format="%h" HEAD -- docs/)
REMOTE_DATE=$(git log -1 --format=%cd --date=short HEAD -- docs/)
REMOTE_MSG=$(git log -1 --format=%s HEAD -- docs/)

echo ""
# 检查模式
if [[ "$CHECK_MODE" == true ]]; then
    print_info "上次同步点（LAST_SYNC 记录）:"
    if [ "$LAST_SYNC_COMMIT" != "unknown" ]; then
        echo "  $LAST_SYNC_LINE"
    else
        echo "  unknown"
    fi
    echo ""

    print_info "上游最新:"
    echo "  Commit: $REMOTE_SHORT"
    echo "  日期: $REMOTE_DATE"
    echo "  描述: $REMOTE_MSG"
    echo ""

    # 对比（只检查 docs/ 目录）
    cd "$PERFETTO_DIR"
    if git cat-file -e "$LAST_SYNC_COMMIT" 2>/dev/null; then
        # commit 存在，正常对比 docs/ 目录
        DOCS_CHANGES=$(git diff --name-only "$LAST_SYNC_COMMIT" HEAD -- docs/ 2>/dev/null || echo "")
    else
        # commit 不存在（可能被 squash 或重新 clone），显示警告
        print_warning "LAST_SYNC 中的 commit 在本地不存在，可能已重新 clone 或历史被修改"
        print_info "建议手动检查: cd perfetto && git log --oneline -10 -- docs/"
        DOCS_CHANGES=""
    fi

    if [ -z "$DOCS_CHANGES" ]; then
        print_success "docs/ 目录已是最新，无需同步"
        echo ""
        exit 0
    else
        print_warning "发现 docs/ 目录有更新！"
        echo ""
        
        # 显示变更文件列表
        echo "变更的文件列表:"
        echo "----------------------------------------"
        echo "$DOCS_CHANGES" | head -20
        
        CHANGED_COUNT=$(echo "$DOCS_CHANGES" | wc -l)
        echo ""
        echo "共 $CHANGED_COUNT 个文件有变更"
        echo ""
        
        # 提示操作步骤
        echo "========================================"
        echo "建议操作步骤:"
        echo "========================================"
        echo ""
        echo "1. 查看详细变更:"
        echo "   cd perfetto && git log --oneline $LAST_SYNC_COMMIT..HEAD -- docs/"
        echo ""
        echo "2. 对比变更并翻译:"
        echo "   git diff $LAST_SYNC_COMMIT -- docs/"
        echo ""
        echo "4. 翻译完成后更新 LAST_SYNC:"
        echo "   bash .project/sync-check.sh --update"
        echo ""
        
        exit 1
    fi
fi

# 更新模式：将 LAST_SYNC 更新为上游最新
if [[ "$UPDATE_MODE" == true ]]; then
    echo ""
    print_info "正在更新 LAST_SYNC 文件..."
    
    # 获取上游 docs/ 最新信息: <hash> <date> <time> <tz> <message>
    REMOTE_HASH=$(git log -1 --format="%h" origin/main -- docs/)
    REMOTE_DATE=$(git log -1 --format="%ci" origin/main -- docs/ | awk '{print $1}')
    REMOTE_TIME=$(git log -1 --format="%ci" origin/main -- docs/ | awk '{print $2, $3}')
    REMOTE_MSG=$(git log -1 --format="%s" origin/main -- docs/)
    REMOTE_LINE="$REMOTE_HASH $REMOTE_DATE $REMOTE_TIME $REMOTE_MSG"
    
    # 写入 LAST_SYNC 文件（保留注释）
    cat > "$LAST_SYNC_FILE" << EOF
# LAST_SYNC - 上游同步记录文件
#
# 格式: git log --oneline 单行格式
#   <short-hash> <date> <message>
#
# 更新方式:
#   bash .project/sync-check.sh --update

$REMOTE_LINE
EOF
    
    print_success "LAST_SYNC 已更新"
    echo ""
    echo "更新内容:"
    echo "  $REMOTE_LINE"
    echo ""
fi
