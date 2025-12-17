#!/bin/bash

# Mihomo 安装/更新脚本
# 使用: mihomo-install [install|update|version]

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 配置
INSTALL_PATH="/usr/local/bin/mihomo"
TEMP_DIR=$(mktemp -d)
GITHUB_API_URL="https://api.github.com/repos/MetaCubeX/mihomo/releases/latest"
GITHUB_REPO="MetaCubeX/mihomo"

# 清理临时文件
cleanup() {
    rm -rf "$TEMP_DIR"
}

trap cleanup EXIT

# 打印日志
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# 检查权限
check_permission() {
    if [ ! -w "/usr/local/bin" ]; then
        log_error "没有 /usr/local/bin 的写权限，请使用 sudo"
        exit 1
    fi
}

# 初始化目录
init_directory() {
    if [ ! -d "/usr/local/bin" ]; then
        log_info "创建 /usr/local/bin 目录..."
        mkdir -p /usr/local/bin
    fi
}

# 获取最新稳定版本信息
get_latest_release() {
    log_info "正在获取最新稳定版本信息..."
    local release_info=$(curl -L \
        --connect-timeout 5 \
        --max-time 10 \
        --retry 2 \
        --retry-delay 0 \
        --retry-max-time 20 \
        -H "Accept: application/vnd.github+json" \
        "${GITHUB_API_URL}" 2>/dev/null)

    if [ -z "$release_info" ]; then
        log_error "获取版本信息失败"
        exit 1
    fi
    echo "$release_info"
}

# 从 release 信息中提取版本号
get_version_from_release() {
    local release_info=$1
    local version=$(echo "$release_info" | grep -o '"tag_name": *"[^"]*"' | head -1 | sed 's/"tag_name": *"\(.*\)"/\1/')

    if [ -z "$version" ]; then
        log_error "解析版本号失败"
        exit 1
    fi
    echo "$version"
}

# 获取系统架构
get_arch() {
    arch=$(arch | sed 's/aarch64/arm64/' | sed 's/i386/amd64/')
    echo "$arch"
}

# 下载 Mihomo
download_mihomo() {
    local version=$1
    local arch=$2

    log_info "系统架构: $arch"
    log_info "版本号: $version"

    local url="https://github.com/${GITHUB_REPO}/releases/download/${version}/mihomo-darwin-${arch}-${version}.gz"
    log_info "下载地址: $url"

    log_info "正在下载..."
    if ! curl -L \
        --connect-timeout 5 \
        --max-time 30 \
        --retry 3 \
        --retry-delay 1 \
        --retry-max-time 30 \
        "$url" -o "${TEMP_DIR}/mihomo.gz"; then
        log_error "下载失败"
        exit 1
    fi

    log_info "下载完成"
}

# 解压并安装
install_mihomo() {
    log_info "正在解压..."
    gunzip -f "${TEMP_DIR}/mihomo.gz"

    if [ ! -f "${TEMP_DIR}/mihomo" ]; then
        log_error "解压失败"
        exit 1
    fi

    log_info "设置权限..."
    chmod 755 "${TEMP_DIR}/mihomo"

    log_info "安装到 $INSTALL_PATH..."
    mv "${TEMP_DIR}/mihomo" "$INSTALL_PATH"

    log_info "验证安装..."
    if ! "$INSTALL_PATH" -h > /dev/null 2>&1; then
        log_error "验证失败"
        exit 1
    fi

    log_info "安装成功！"
}

# 检查当前版本
check_current_version() {
    if [ -f "$INSTALL_PATH" ]; then
        log_info "当前已安装 Mihomo"
        "$INSTALL_PATH" -v 2>/dev/null || echo "版本信息获取失败" >&2
    else
        log_warn "Mihomo 未安装"
    fi
}

# 检查是否已安装
is_installed() {
    [ -f "$INSTALL_PATH" ]
}

# 获取当前安装的版本号
get_installed_version() {
    if [ -f "$INSTALL_PATH" ]; then
        # 尝试从 mihomo -v 输出中提取版本号
        "$INSTALL_PATH" -v 2>/dev/null | head -n 1 || echo ""
    else
        echo ""
    fi
}

# 卸载 Mihomo
uninstall_mihomo() {
    log_info "正在卸载 Mihomo..."
    if [ -f "$INSTALL_PATH" ]; then
        rm -f "$INSTALL_PATH"
        if [ $? -eq 0 ]; then
            log_info "Mihomo 卸载成功"
        else
            log_error "卸载失败，请检查权限"
            exit 1
        fi
    else
        log_warn "Mihomo 未安装"
    fi
}

# 清理安装脚本
cleanup_script() {
    log_info "正在清理安装脚本..."
    local script_path=$(realpath "$0" 2>/dev/null || echo "$0")
    if [ -f "$script_path" ]; then
        log_info "脚本路径: $script_path"
        echo -n "确定要删除脚本文件吗？(y/N): " >&2
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            rm -f "$script_path"
            if [ $? -eq 0 ]; then
                log_info "脚本删除成功"
            else
                log_error "脚本删除失败，请检查权限"
                exit 1
            fi
        else
            log_info "取消删除"
        fi
    else
        log_warn "脚本文件不存在或无法确定路径"
    fi
}

# 完全卸载（Mihomo + 脚本）
purge_all() {
    log_info "开始完全卸载..."
    uninstall_mihomo
    cleanup_script
}

# 主函数
main() {
    local action=${1:-install}

    case "$action" in
        install)
            log_info "开始安装..."

            # 检查是否已安装
            if is_installed; then
                log_warn "检测到 Mihomo 已安装"
                check_current_version
                echo -n "是否要重新安装？(y/N): " >&2
                read -r response
                if [[ ! "$response" =~ ^[Yy]$ ]]; then
                    log_info "取消安装"
                    exit 0
                fi
            fi

            check_permission
            init_directory

            local release_info=$(get_latest_release)
            local version=$(get_version_from_release "$release_info")
            local arch=$(get_arch)

            download_mihomo "$version" "$arch"
            install_mihomo

            log_info "安装完成！"
            check_current_version
            ;;
        update)
            log_info "开始更新..."

            # 检查是否已安装
            if ! is_installed; then
                log_error "Mihomo 未安装，请先使用 'install' 命令安装"
                exit 1
            fi

            log_info "检查当前版本..."
            local current_version=$(get_installed_version)
            log_info "当前版本: $current_version"

            log_info "检查最新版本..."
            local release_info=$(get_latest_release)
            local latest_version=$(get_version_from_release "$release_info")
            log_info "最新版本: $latest_version"

            # 比较版本号
            if echo "$current_version" | grep -q "$latest_version"; then
                log_info "已经是最新版本，无需更新"
                exit 0
            fi

            log_info "发现新版本，开始更新..."
            check_permission
            init_directory

            local arch=$(get_arch)

            download_mihomo "$latest_version" "$arch"
            install_mihomo

            log_info "更新完成！"
            check_current_version
            ;;
        version)
            check_current_version
            ;;
        uninstall)
            uninstall_mihomo
            ;;
        cleanup)
            cleanup_script
            ;;
        purge)
            purge_all
            ;;
        *)
            cat << EOF
Mihomo 安装/更新脚本

用法:
    mihomo-install [命令]

命令:
    install    安装 Mihomo（默认）
    update     更新 Mihomo
    version    查看当前版本
    uninstall  卸载 Mihomo
    cleanup    删除安装脚本
    purge      完全卸载（Mihomo + 脚本）

示例:
    mihomo-install install
    mihomo-install update
    mihomo-install version
    mihomo-install uninstall
    mihomo-install cleanup
    mihomo-install purge
EOF
            exit 1
            ;;
    esac
}

main "$@"
