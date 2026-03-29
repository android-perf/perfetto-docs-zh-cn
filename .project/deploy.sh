#!/bin/bash

set -e

# =============================================================================
# Perfetto 中文文档部署脚本
# 支持平台：macOS、Linux、Windows (Git Bash/WSL)
#
# 使用方法:
#   bash deploy.sh              # 本地部署（默认）
#   bash deploy.sh --gh-pages   # 部署到 GitHub Pages
#   bash deploy.sh --help       # 显示帮助
# =============================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 调试模式（可通过环境变量开启）
DEBUG="${DEBUG:-false}"

# 超时设置（秒）
TIMEOUT_CLONE=300        # 克隆仓库超时
TIMEOUT_BUILD=600        # 构建超时
TIMEOUT_COPY=60          # 复制文件超时

# 日志文件
LOG_FILE="/tmp/perfetto-deploy-$(date +%Y%m%d-%H%M%S).log"

# 部署模式
DEPLOY_MODE="${1:-local}"  # local 或 gh-pages
AUTO_MODE="${2:-}"  # --auto 用于自动化环境

# 显示帮助
show_help() {
    echo ""
    echo "Perfetto 中文文档部署脚本"
    echo ""
    echo "使用方法:"
    echo "  bash deploy.sh                    本地部署并启动服务器"
    echo "  bash deploy.sh --gh-pages         部署到 GitHub Pages（交互式）"
    echo "  bash deploy.sh --gh-pages --auto  部署到 GitHub Pages（自动模式，跳过确认）"
    echo "  bash deploy.sh --help             显示此帮助信息"
    echo ""
    echo "选项:"
    echo "  --gh-pages    部署到 GitHub Pages"
    echo "  --auto        自动模式（不等待用户确认）"
    echo "  --help, -h    显示帮助信息"
    echo ""
    echo "环境变量:"
    echo "  DEBUG=true    开启调试模式"
    echo ""
}

# 检查参数
if [[ "$DEPLOY_MODE" == "--help" || "$DEPLOY_MODE" == "-h" ]]; then
    show_help
    exit 0
fi

if [[ "$DEPLOY_MODE" == "--gh-pages" ]]; then
    DEPLOY_MODE="gh-pages"
    if [[ "$AUTO_MODE" == "--auto" ]]; then
        AUTO_CONFIRM=true
    fi
fi

# 检测操作系统
 detect_os() {
    case "$(uname -s)" in
        Linux*)     OS="Linux";;
        Darwin*)    OS="macOS";;
        CYGWIN*)    OS="Windows";;
        MINGW*)     OS="Windows";;
        MSYS*)      OS="Windows";;
        *)          OS="Unknown";;
    esac
    echo "$OS"
}

OS=$(detect_os)

# 打印带颜色的信息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    log "INFO: $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
    log "SUCCESS: $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
    log "WARNING: $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
    log "ERROR: $1"
}

print_step() {
    echo ""
    echo -e "${YELLOW}=== 步骤 $1/4: $2 ===${NC}"
    log "STEP $1: $2"
}

print_debug() {
    if [ "$DEBUG" = "true" ]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    fi
    log "DEBUG: $1"
}

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 跨平台命令封装
# 根据操作系统返回相应的命令
get_timeout_cmd() {
    if [ "$OS" = "Linux" ]; then
        if command -v timeout &> /dev/null; then
            echo "timeout"
        elif command -v gtimeout &> /dev/null; then
            echo "gtimeout"
        else
            echo ""
        fi
    elif [ "$OS" = "macOS" ]; then
        if command -v gtimeout &> /dev/null; then
            echo "gtimeout"
        else
            echo ""
        fi
    else
        echo ""
    fi
}

# macOS/Linux 兼容的 timeout 函数
timeout_compat() {
    local duration=$1
    shift
    
    local timeout_cmd=$(get_timeout_cmd)
    
    if [ -n "$timeout_cmd" ]; then
        $timeout_cmd $duration "$@"
    else
        # 使用 perl 实现超时（跨平台）
        perl -e 'alarm shift; exec @ARGV' "$duration" "$@"
    fi
}

# 跨平台的磁盘空间检查
check_disk_space() {
    local dir=$1
    local required_mb=${2:-100}
    
    local available_mb=0
    
    case "$OS" in
        "Linux")
            available_mb=$(df -m "$dir" | tail -1 | awk '{print $4}')
            ;;
        "macOS")
            available_mb=$(df -m "$dir" | tail -1 | awk '{print $4}')
            ;;
        "Windows")
            # Windows (Git Bash/WSL)
            if command -v df &> /dev/null; then
                available_mb=$(df -m "$dir" 2>/dev/null | tail -1 | awk '{print $4}')
            else
                # 假设空间充足
                available_mb=10000
            fi
            ;;
        *)
            available_mb=10000
            ;;
    esac
    
    if [ "$available_mb" -lt "$required_mb" ]; then
        print_error "磁盘空间不足（剩余 ${available_mb}MB，需要 ${required_mb}MB）"
        return 1
    fi
    
    print_debug "磁盘空间充足: ${available_mb}MB"
    return 0
}

# 跨平台的端口检查
check_port() {
    local port=$1
    
    case "$OS" in
        "Linux"|"macOS")
            if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
                return 1
            fi
            ;;
        "Windows")
            if command -v netstat &> /dev/null; then
                if netstat -an | grep -q ":$port "; then
                    return 1
                fi
            fi
            ;;
    esac
    return 0
}

# 跨平台的端口清理
cleanup_port() {
    local port=$1
    print_info "尝试清理端口 $port 占用..."
    
    local pids=""
    case "$OS" in
        "Linux"|"macOS")
            pids=$(lsof -Pi :$port -sTCP:LISTEN -t 2>/dev/null)
            ;;
        "Windows")
            if command -v netstat &> /dev/null && command -v taskkill &> /dev/null; then
                # Windows: 使用 netstat 和 taskkill
                pids=$(netstat -ano | grep ":$port " | awk '{print $5}' | head -1)
            fi
            ;;
    esac
    
    if [ -n "$pids" ]; then
        case "$OS" in
            "Linux"|"macOS")
                echo "$pids" | xargs kill -9 2>/dev/null || true
                ;;
            "Windows")
                taskkill /F /PID $pids 2>/dev/null || true
                ;;
        esac
        sleep 2
        print_success "端口 $port 已清理"
    fi
}

# 监控编译进度函数
monitor_build_progress() {
    local log_file=$1
    local last_line_count=0
    local no_change_count=0
    local max_no_change=60  # 60次无变化（约120秒）视为卡住
    
    print_info "启动编译进度监控..."
    
    while true; do
        sleep 2
        
        # 检查日志文件是否存在
        if [ ! -f "$log_file" ]; then
            continue
        fi
        
        # 获取当前行数（跨平台兼容）
        local current_line_count=0
        if [ "$OS" = "Windows" ]; then
            current_line_count=$(wc -l < "$log_file" 2>/dev/null | tr -d ' ' || echo 0)
        else
            current_line_count=$(wc -l < "$log_file" 2>/dev/null || echo 0)
        fi
        
        # 检查是否有新输出
        if [ "$current_line_count" -eq "$last_line_count" ]; then
            no_change_count=$((no_change_count + 1))
            
            if [ $no_change_count -eq 10 ]; then
                print_warning "编译似乎没有进展（20秒无输出）..."
            elif [ $no_change_count -eq 30 ]; then
                print_warning "编译进展缓慢（60秒无输出）..."
            elif [ $no_change_count -ge $max_no_change ]; then
                print_error "编译似乎卡住了（120秒无输出）"
                return 1
            fi
        else
            # 有新输出，重置计数器
            if [ $no_change_count -ge 10 ]; then
                print_success "编译恢复进行中..."
            fi
            no_change_count=0
            last_line_count=$current_line_count
            
            # 显示最后几行输出
            local last_lines=$(tail -3 "$log_file" 2>/dev/null)
            if [ -n "$last_lines" ]; then
                print_debug "最新输出: $last_lines"
            fi
        fi
        
        # 检查构建是否成功完成（检测 ninja 构建完成标志）
        if grep -qE '\[379/379\].*stamp obj/site\.stamp' "$log_file" 2>/dev/null; then
            print_success "编译成功完成！"
            return 0
        fi
        
        # 检查构建是否完成（检测 "Done!" 或其他成功标志）
        if grep -qE '(Done!|Build completed successfully)' "$log_file" 2>/dev/null; then
            print_success "编译完成！"
            return 0
        fi
        
        # 检查是否有错误
        if grep -qE "(Error:|FAILED|FATAL)" "$log_file" 2>/dev/null; then
            print_error "编译过程中出现错误"
            return 1
        fi
        
        # 检查构建进程是否已退出（通过检查 PID 是否存在）
        if [ -n "$BUILD_PID" ] && ! kill -0 $BUILD_PID 2>/dev/null; then
            # 进程已退出，检查是否成功
            if grep -qE '\[[0-9]+/[0-9]+\].*stamp obj/site\.stamp' "$log_file" 2>/dev/null; then
                print_success "编译进程已完成！"
                return 0
            fi
        fi
    done
}

# 检查命令是否存在
check_command() {
    if ! command -v $1 &> /dev/null; then
        print_error "命令 '$1' 未找到，请先安装"
        return 1
    fi
    print_debug "命令 '$1' 已安装"
    return 0
}

# 检查目录权限
check_directory() {
    local dir=$1
    if [ ! -d "$dir" ]; then
        print_debug "目录不存在，创建: $dir"
        mkdir -p "$dir" || {
            print_error "无法创建目录: $dir"
            return 1
        }
    fi
    
    # Windows 可能不支持 -w 测试
    if [ "$OS" != "Windows" ]; then
        if [ ! -w "$dir" ]; then
            print_error "目录没有写权限: $dir"
            return 1
        fi
    fi
    
    print_debug "目录检查通过: $dir"
    return 0
}

# 自愈：修复常见问题
self_heal() {
    print_info "尝试自动修复常见问题..."
    print_info "当前操作系统: $OS"
    
    # 1. 清理端口占用
    cleanup_port 8082
    
    # 2. 检查磁盘空间
    if ! check_disk_space "$PROJECT_ROOT" 100; then
        return 1
    fi
    
    # 3. 检查 Node.js
    if ! check_command node; then
        print_error "Node.js 未安装"
        print_info "请访问 https://nodejs.org/ 安装 Node.js"
        return 1
    fi
    
    # 4. 检查 Git
    if ! check_command git; then
        print_error "Git 未安装"
        if [ "$OS" = "Windows" ]; then
            print_info "请安装 Git for Windows: https://git-scm.com/download/win"
        else
            print_info "请使用包管理器安装 Git"
        fi
        return 1
    fi
    
    # 5. Windows 特定检查
    if [ "$OS" = "Windows" ]; then
        print_info "检测到 Windows 系统"
        print_info "确保在 Git Bash 或 WSL 环境中运行此脚本"
    fi
    
    print_success "自愈检查完成"
    return 0
}

# 带超时和重试的执行函数
run_with_timeout() {
    local timeout_sec=$1
    local retries=${2:-0}
    local cmd="${@:3}"
    local attempt=0
    
    while [ $attempt -le $retries ]; do
        if [ $attempt -gt 0 ]; then
            print_warning "第 $attempt 次重试..."
            sleep 2
        fi
        
        print_debug "执行命令: $cmd"
        print_debug "超时设置: ${timeout_sec}秒"
        
        # 执行命令并捕获输出
        local output_file=$(mktemp)
        if timeout_compat $timeout_sec bash -c "$cmd" > "$output_file" 2>&1; then
            cat "$output_file" | tee -a "$LOG_FILE"
            rm -f "$output_file"
            return 0
        else
            local exit_code=$?
            cat "$output_file" | tee -a "$LOG_FILE"
            rm -f "$output_file"
            
            if [ $exit_code -eq 124 ] || [ $exit_code -eq 142 ]; then
                print_error "命令执行超时（${timeout_sec}秒）"
                log "TIMEOUT: 命令执行超过 ${timeout_sec} 秒"
            else
                print_error "命令失败，退出码: $exit_code"
                log "FAILED: 命令失败，退出码: $exit_code"
            fi
            
            attempt=$((attempt + 1))
            if [ $attempt -le $retries ]; then
                print_info "等待后重试..."
                sleep 5
            fi
        fi
    done
    
    return 1
}

# 显示欢迎信息
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║      Perfetto 中文文档部署脚本                           ║${NC}"
echo -e "${GREEN}║      支持: macOS / Linux / Windows (Git Bash/WSL)        ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
print_info "操作系统: $OS"
print_info "日志文件: $LOG_FILE"
print_info "调试模式: $DEBUG"
echo ""

# 记录系统信息
log "========================================="
log "开始部署"
log "操作系统: $OS"
log "当前目录: $(pwd)"
log "用户: $(whoami)"
log "系统: $(uname -a)"
log "========================================="

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 脚本在 perfetto-docs-zh-cn/.project/，所以 DOCS_ZH_DIR 是 SCRIPT_DIR 的父目录
DOCS_ZH_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$DOCS_ZH_DIR")"
PERFETTO_DIR="$PROJECT_ROOT/perfetto"

print_debug "SCRIPT_DIR: $SCRIPT_DIR"
print_debug "DOCS_ZH_DIR: $DOCS_ZH_DIR"
print_debug "PROJECT_ROOT: $PROJECT_ROOT"
print_debug "PERFETTO_DIR: $PERFETTO_DIR"

# 执行自愈检查
if ! self_heal; then
    print_error "自愈检查失败，请手动修复问题"
    exit 1
fi

# 步骤 1: 检查并准备 Perfetto 仓库
print_step "1" "检查 Perfetto 仓库"

if [ ! -d "$PERFETTO_DIR/.git" ]; then
    print_warning "Perfetto 仓库不存在"
    print_info "正在从 GitHub 克隆 Perfetto 仓库..."
    
    if check_directory "$PROJECT_ROOT"; then
        cd "$PROJECT_ROOT"
        
        if run_with_timeout $TIMEOUT_CLONE 2 "git clone https://github.com/google/perfetto.git perfetto"; then
            print_success "Perfetto 仓库克隆完成"
        else
            print_error "克隆失败，请检查网络连接"
            exit 1
        fi
    else
        exit 1
    fi
else
    print_success "Perfetto 仓库已存在 ($PERFETTO_DIR)"
    print_debug "Git 远程仓库: $(cd $PERFETTO_DIR && git remote -v 2>/dev/null | head -1)"
fi

cd "$PERFETTO_DIR"

# 步骤 2: 替换为中文文档
print_step "2" "替换为中文文档"

# 检查中文文档目录是否存在
if [ ! -d "$DOCS_ZH_DIR/docs" ]; then
    print_error "中文文档目录不存在: $DOCS_ZH_DIR/docs"
    exit 1
fi

# 删除英文 docs 目录，复制中文 docs 目录
print_info "删除英文 docs 目录..."
rm -rf docs
print_success "英文 docs 目录已删除"

print_info "复制中文 docs 目录..."
cp -r "$DOCS_ZH_DIR/docs" .
print_success "中文 docs 目录已复制"

# 验证复制结果
if [ -f "docs/README.md" ]; then
    print_debug "README.md 验证通过"
    print_info "共复制 $(find docs -name '*.md' 2>/dev/null | wc -l) 个 Markdown 文件"
else
    print_error "复制失败，README.md 不存在"
    exit 1
fi

# 步骤 2b: 修改首页配置（让首页显示README.md内容）
print_step "2b" "修改首页配置"
BUILD_GN_FILE="infra/perfetto.dev/BUILD.gn"

print_info "备份原始 BUILD.gn..."
cp "$BUILD_GN_FILE" "$BUILD_GN_FILE.bak"

print_info "修改首页配置，使用 README.md 作为首页内容..."
# 修改 gen_index 目标，让它渲染 README.md，并使用 markdown 模板
sed -i '' 's/md_to_html("gen_index") {/md_to_html("gen_index") {\n  markdown = "${src_doc_dir}\/README.md"/' "$BUILD_GN_FILE"
sed -i '' 's|html_template = "src/template_index.html"|html_template = "src/template_markdown.html"|' "$BUILD_GN_FILE"

print_success "首页配置已修改"

# 步骤 3: 验证文档复制结果
print_step "3" "验证文档"

print_info "验证中文文档..."
if [ -f "docs/README.md" ]; then
    print_success "README.md 验证通过"
    print_info "共复制 $(find docs -name '*.md' 2>/dev/null | wc -l) 个 Markdown 文件"
else
    print_error "复制失败，docs/README.md 不存在"
    exit 1
fi

# 步骤 4: 构建并启动服务器（官方方式）
echo ""
print_step "4" "构建并启动服务器（官方方式）"

# 检查构建依赖
print_info "检查 Node.js..."
if ! check_command node; then
    exit 1
fi

print_info "Node.js 版本: $(node --version 2>/dev/null || echo '未知')"

# 检查 Perfetto 构建依赖
cd "$PERFETTO_DIR"
print_info "检查构建依赖..."
if ! tools/install-build-deps --check-only --ui --filter=nodejs --filter=pnpm --filter=gn --filter=ninja > /dev/null 2>&1; then
    print_warning "构建依赖不完整，正在自动安装..."
    print_info "运行: install-build-deps --ui --filter=nodejs --filter=pnpm --filter=gn --filter=ninja"
    print_info "这可能需要几分钟时间，请耐心等待..."
    
    if tools/install-build-deps --ui --filter=nodejs --filter=pnpm --filter=gn --filter=ninja 2>&1 | tee -a "$LOG_FILE"; then
        print_success "构建依赖安装完成"
    else
        print_error "构建依赖安装失败"
        print_info "请手动运行: cd perfetto && tools/install-build-deps --ui --filter=nodejs --filter=pnpm --filter=gn --filter=ninja"
        exit 1
    fi
else
    print_success "构建依赖已满足"
fi

# 检查端口
if ! check_port 8082; then
    print_info "端口 8082 被占用，尝试清理..."
    cleanup_port 8082
fi

# ⚠️ 重要：必须重新构建，因为 docs/ 目录已更新为中文文档
print_info "清理旧构建输出..."
rm -rf out/perfetto.dev
print_success "旧构建输出已清理"

# 步骤 4a: 执行构建（不启动服务器）
print_info "执行构建（不启动服务器）..."
print_info "使用命令: node infra/perfetto.dev/build.js"
print_info "首次构建需要 2-5 分钟，请耐心等待..."
echo ""

# 创建临时日志文件用于监控构建进度
BUILD_LOG=$(mktemp)
export BUILD_LOG
print_debug "构建日志: $BUILD_LOG"

# 在后台运行构建，并捕获输出到日志
node infra/perfetto.dev/build.js > "$BUILD_LOG" 2>&1 &
BUILD_PID=$!

print_info "构建进程 PID: $BUILD_PID"
print_info "正在监控编译进度..."

# 启动监控
if monitor_build_progress "$BUILD_LOG"; then
    print_success "构建完成！"
    
    # 额外验证：检查构建输出目录是否存在
    if [ -d "out/perfetto.dev" ]; then
        print_success "构建输出目录验证通过"
    else
        print_warning "未找到标准构建输出目录，但构建可能已成功"
    fi
    
    rm -f "$BUILD_LOG"
    
    # =============================================================================
    # 根据部署模式执行不同操作
    # =============================================================================
    
    if [[ "$DEPLOY_MODE" == "gh-pages" ]]; then
        # GitHub Pages 部署模式 - 构建完成直接部署
        echo ""
        print_success "========================================"
        print_success "构建完成！准备部署到 GitHub Pages"
        print_success "========================================"
        echo ""
        
        # 执行 GitHub Pages 部署
        cd "$DOCS_ZH_DIR"
        bash "$SCRIPT_DIR/deploy-gh-pages.sh"
        exit 0
    fi
    
    # 本地部署模式 - 启动服务器
    echo ""
    print_info "启动 HTTP 服务器..."
    print_info "使用命令: node infra/perfetto.dev/build.js --serve"
    print_info "服务器将在后台运行"
    echo ""
    
    # 创建服务器日志文件
    SERVER_LOG="/tmp/perfetto-server-$(date +%Y%m%d-%H%M%S).log"
    
    # 在后台启动服务器
    node infra/perfetto.dev/build.js --serve > "$SERVER_LOG" 2>&1 &
    SERVER_PID=$!
    
    print_info "服务器进程 PID: $SERVER_PID"
    print_info "服务器日志: $SERVER_LOG"
    
    # 等待服务器启动
    print_info "等待服务器启动..."
    sleep 5
    
    # 验证服务器是否真的在运行
    retry_count=0
    max_retries=6
    
    while [ $retry_count -lt $max_retries ]; do
        if ! check_port 8082; then
            print_success "服务器已正常启动（端口 8082 已被占用）"
            break
        fi
        
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            print_info "服务器启动中... (${retry_count}/${max_retries})"
            sleep 2
        fi
    done
    
    if [ $retry_count -eq $max_retries ]; then
        print_error "服务器未能正常启动（端口 8082 未被占用）"
        print_info "检查服务器日志最后 30 行:"
        tail -30 "$SERVER_LOG"
        exit 1
    fi
    
    # 本地部署成功提示
    print_info ""
    print_success "========================================"
    print_success "本地部署成功！"
    print_success "========================================"
    print_info ""
    print_info "访问地址: http://localhost:8082/docs/"
    print_info ""
    print_info "服务器在后台运行，PID: $SERVER_PID"
    print_info "查看服务器日志: tail -f $SERVER_LOG"
    print_info ""
    print_info "停止服务器命令: kill $SERVER_PID"
    print_info ""
    print_info "日志文件保留在: $LOG_FILE"
    print_info ""
    print_info "========================================"
    print_info "GitHub Pages 部署"
    print_info "========================================"
    print_info ""
    print_info "如需部署到 GitHub Pages，请运行:"
    print_info ""
    print_info "  bash .project/deploy.sh --gh-pages"
    print_info ""
    
else
    # 监控检测到卡住或错误
    print_error "构建过程出现问题"
    print_info "杀死构建进程..."
    kill $BUILD_PID 2>/dev/null || true
    
    print_info "最后 50 行日志:"
    tail -50 "$BUILD_LOG"
    
    rm -f "$BUILD_LOG"
    exit 1
fi
