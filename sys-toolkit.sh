#!/bin/bash

# ============================================================
# sys-toolkit.sh - 系统工具集统一入口
# 功能：统一管理和调用 fail2ban、网络代理、系统备份等脚本
# 用法：sudo ./sys-toolkit.sh [命令]
# ============================================================

set -e

# ==================== 颜色定义 ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
RESET='\033[0m'

# ==================== 常量定义 ====================
# 远程仓库地址
REPO_BASE_URL="https://raw.githubusercontent.com/sephiroth233/sys-toolkit/master"

# 脚本文件名
FAIL2BAN_SCRIPT_NAME="fail2ban-manager.sh"
PROXY_SCRIPT_NAME="server-proxy.sh"
BACKUP_SCRIPT_NAME="sys-backup-restore.sh"

# 本地缓存目录 - 使用持久化目录而非临时目录
# 这样子脚本可以正确设置 cron 任务等需要稳定路径的功能
CACHE_DIR="/usr/local/lib/sys-toolkit"

# 版本信息
VERSION="1.0.0"

# ==================== 日志函数 ====================
log_info() {
    echo -e "${GREEN}[INFO]${RESET} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${RESET} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${RESET} $1"
}

# ==================== 权限检查 ====================
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}请使用 root 权限执行此脚本！${RESET}"
        exit 1
    fi
}

# ==================== 依赖检查 ====================
check_curl() {
    if ! command -v curl &> /dev/null; then
        log_error "curl 未安装，请先安装 curl"
        log_info "Ubuntu/Debian: sudo apt-get install curl"
        log_info "CentOS/RHEL: sudo yum install curl"
        exit 1
    fi
}

# ==================== 脚本下载和执行 ====================
download_and_run_script() {
    local script_name="$1"
    shift
    local script_args=("$@")

    local script_url="${REPO_BASE_URL}/${script_name}"
    local local_script="${CACHE_DIR}/${script_name}"

    # 创建缓存目录
    mkdir -p "$CACHE_DIR"

    log_info "正在下载 ${script_name}..."

    # 下载脚本
    if curl -fsSL "$script_url" -o "$local_script" 2>/dev/null; then
        chmod +x "$local_script"
        log_info "下载完成，正在执行..."
        echo ""
        # 直接执行缓存目录中的脚本
        # 使用持久化目录确保 cron 任务等功能正常工作
        bash "$local_script" "${script_args[@]}"
        return $?
    else
        log_error "下载失败: ${script_url}"
        log_warn "请检查网络连接或仓库地址是否正确"
        return 1
    fi
}

# ==================== 脚本状态检查 ====================
get_fail2ban_status() {
    if command -v fail2ban-client &> /dev/null; then
        if systemctl is-active --quiet fail2ban 2>/dev/null; then
            echo -e "${GREEN}已安装 - 运行中${RESET}"
        else
            echo -e "${YELLOW}已安装 - 已停止${RESET}"
        fi
    else
        echo -e "${RED}未安装${RESET}"
    fi
}

get_singbox_status() {
    if command -v sing-box &> /dev/null; then
        if systemctl is-active --quiet sing-box 2>/dev/null; then
            echo -e "${GREEN}已安装 - 运行中${RESET}"
        else
            echo -e "${YELLOW}已安装 - 已停止${RESET}"
        fi
    else
        echo -e "${RED}未安装${RESET}"
    fi
}

get_snell_status() {
    if command -v snell-server &> /dev/null; then
        if systemctl is-active --quiet snell 2>/dev/null; then
            echo -e "${GREEN}已安装 - 运行中${RESET}"
        else
            echo -e "${YELLOW}已安装 - 已停止${RESET}"
        fi
    else
        echo -e "${RED}未安装${RESET}"
    fi
}

get_rclone_status() {
    if command -v rclone &> /dev/null; then
        echo -e "${GREEN}已安装${RESET}"
    else
        echo -e "${RED}未安装${RESET}"
    fi
}

get_backup_cron_status() {
    local backup_script="${CACHE_DIR}/${BACKUP_SCRIPT_NAME}"
    if command -v crontab &> /dev/null; then
        if crontab -l 2>/dev/null | grep -q "$backup_script"; then
            # 提取 cron 表达式
            local cron_expr=$(crontab -l 2>/dev/null | grep "$backup_script" | awk '{print $1" "$2" "$3" "$4" "$5}')
            echo -e "${GREEN}已设置${RESET} ${CYAN}($cron_expr)${RESET}"
        else
            echo -e "${YELLOW}未设置${RESET}"
        fi
    else
        echo -e "${RED}cron未安装${RESET}"
    fi
}

# ==================== 子脚本调用 ====================
run_fail2ban() {
    log_info "启动 fail2ban 管理工具..."
    download_and_run_script "$FAIL2BAN_SCRIPT_NAME" "$@"
}

run_proxy() {
    log_info "启动网络代理配置工具..."
    download_and_run_script "$PROXY_SCRIPT_NAME" "$@"
}

run_backup() {
    log_info "启动系统备份恢复工具..."
    download_and_run_script "$BACKUP_SCRIPT_NAME" "$@"
}

# ==================== 完全卸载功能 ====================
uninstall_all() {
    echo ""
    echo -e "${RED}╔════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${RED}║                    ⚠️  完全卸载警告  ⚠️                          ║${RESET}"
    echo -e "${RED}╚════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "${YELLOW}此操作将卸载以下所有组件并删除相关配置：${RESET}"
    echo ""
    echo -e "  ${CYAN}1. fail2ban${RESET} - 入侵检测和防护服务"
    echo -e "  ${CYAN}2. Sing-box${RESET} - 网络代理服务"
    echo -e "  ${CYAN}3. Snell${RESET}    - Snell 代理服务"
    echo -e "  ${CYAN}4. rclone${RESET}   - 云存储同步工具"
    echo -e "  ${CYAN}5. 定时备份任务${RESET}"
    echo -e "  ${CYAN}6. 所有配置文件${RESET} (/etc/sys-backup, /etc/sing-box, /etc/snell, /etc/fail2ban)"
    echo -e "  ${CYAN}7. 脚本缓存目录${RESET} (${CACHE_DIR})"
    echo ""
    echo -e "${RED}注意：云端备份数据不会被删除${RESET}"
    echo ""
    read -r -p "$(echo -e "${RED}确定要完全卸载所有组件吗？请输入 'YES' 确认: ${RESET}")" confirm

    if [ "$confirm" != "YES" ]; then
        log_warn "已取消卸载操作"
        return 0
    fi

    echo ""
    log_info "开始卸载所有组件..."
    echo ""

    # 1. 卸载 fail2ban
    if command -v fail2ban-client &> /dev/null; then
        log_info "正在卸载 fail2ban..."
        systemctl stop fail2ban 2>/dev/null || true
        systemctl disable fail2ban 2>/dev/null || true
        if command -v apt-get &> /dev/null; then
            apt-get remove -y fail2ban 2>/dev/null || true
        elif command -v yum &> /dev/null; then
            yum remove -y fail2ban 2>/dev/null || true
        elif command -v dnf &> /dev/null; then
            dnf remove -y fail2ban 2>/dev/null || true
        fi
        rm -rf /etc/fail2ban 2>/dev/null || true
        log_info "fail2ban 已卸载"
    else
        log_info "fail2ban 未安装，跳过"
    fi

    # 2. 卸载 Sing-box
    if command -v sing-box &> /dev/null; then
        log_info "正在卸载 Sing-box..."
        systemctl stop sing-box 2>/dev/null || true
        systemctl disable sing-box 2>/dev/null || true
        dpkg --purge sing-box 2>/dev/null || true
        rm -rf /etc/sing-box 2>/dev/null || true
        rm -f /usr/local/bin/sing-box 2>/dev/null || true
        systemctl daemon-reload 2>/dev/null || true
        log_info "Sing-box 已卸载"
    else
        log_info "Sing-box 未安装，跳过"
    fi

    # 3. 卸载 Snell
    if command -v snell-server &> /dev/null; then
        log_info "正在卸载 Snell..."
        systemctl stop snell 2>/dev/null || true
        systemctl disable snell 2>/dev/null || true
        rm -f /etc/systemd/system/snell.service 2>/dev/null || true
        rm -f /usr/local/bin/snell-server 2>/dev/null || true
        rm -rf /etc/snell 2>/dev/null || true
        systemctl daemon-reload 2>/dev/null || true
        log_info "Snell 已卸载"
    else
        log_info "Snell 未安装，跳过"
    fi

    # 4. 卸载 rclone 和备份相关
    if command -v rclone &> /dev/null; then
        log_info "正在卸载 rclone..."
        local rclone_path=$(which rclone)
        rm -f "$rclone_path" 2>/dev/null || true
        rm -f /usr/local/share/man/man1/rclone.1 2>/dev/null || true
        rm -rf ~/.config/rclone 2>/dev/null || true
        log_info "rclone 已卸载"
    else
        log_info "rclone 未安装，跳过"
    fi

    # 5. 删除定时备份任务
    local backup_script="${CACHE_DIR}/${BACKUP_SCRIPT_NAME}"
    if command -v crontab &> /dev/null; then
        if crontab -l 2>/dev/null | grep -q "$backup_script"; then
            log_info "正在删除定时备份任务..."
            crontab -l 2>/dev/null | grep -v "$backup_script" | crontab -
            log_info "定时备份任务已删除"
        fi
    fi

    # 6. 删除备份配置和日志
    log_info "正在删除备份配置..."
    rm -rf /etc/sys-backup 2>/dev/null || true
    rm -rf /var/log/sys-backup 2>/dev/null || true
    rm -rf /tmp/sys-backup 2>/dev/null || true
    log_info "备份配置已删除"

    # 7. 删除脚本缓存目录
    log_info "正在删除脚本缓存目录..."
    rm -rf "$CACHE_DIR" 2>/dev/null || true
    log_info "脚本缓存目录已删除"

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${GREEN}║                    卸载完成!                                    ║${RESET}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "${YELLOW}已卸载的组件：${RESET}"
    echo -e "  - fail2ban (如已安装)"
    echo -e "  - Sing-box (如已安装)"
    echo -e "  - Snell (如已安装)"
    echo -e "  - rclone (如已安装)"
    echo -e "  - 定时备份任务"
    echo -e "  - 所有相关配置文件"
    echo ""
    echo -e "${CYAN}提示：如需重新安装，请重新运行此脚本${RESET}"
    echo ""
}

# ==================== 帮助信息 ====================
show_help() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BLUE}║              sys-toolkit - 系统工具集 v${VERSION}                  ║${RESET}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "${PURPLE}【命令用法】${RESET}"
    echo "  sudo ./sys-toolkit.sh [命令] [参数]"
    echo ""
    echo -e "${PURPLE}【主要命令】${RESET}"
    echo "  fail2ban      - 启动 fail2ban 管理工具"
    echo "  proxy         - 启动网络代理配置工具 (Sing-box/Snell)"
    echo "  backup        - 启动系统备份恢复工具"
    echo ""
    echo -e "${PURPLE}【快捷命令】${RESET}"
    echo "  fail2ban install    - 安装 fail2ban"
    echo "  fail2ban status     - 查看 fail2ban 状态"
    echo "  proxy               - 进入代理配置菜单"
    echo "  backup backup       - 立即执行备份"
    echo "  backup restore      - 恢复备份"
    echo "  backup list         - 查看备份列表"
    echo ""
    echo -e "${PURPLE}【其他】${RESET}"
    echo "  status        - 查看所有工具状态"
    echo "  uninstall     - 完全卸载所有组件和配置"
    echo "  help          - 显示此帮助信息"
    echo "  version       - 显示版本信息"
    echo ""
    echo -e "${PURPLE}【示例】${RESET}"
    echo "  # 进入交互式菜单"
    echo "  sudo ./sys-toolkit.sh"
    echo ""
    echo "  # 直接启动 fail2ban 管理"
    echo "  sudo ./sys-toolkit.sh fail2ban"
    echo ""
    echo "  # 安装 fail2ban"
    echo "  sudo ./sys-toolkit.sh fail2ban install"
    echo ""
    echo "  # 执行备份"
    echo "  sudo ./sys-toolkit.sh backup backup"
    echo ""
    echo -e "${PURPLE}【脚本来源】${RESET}"
    echo "  仓库地址:  ${REPO_BASE_URL}"
    echo "  fail2ban:  ${FAIL2BAN_SCRIPT_NAME}"
    echo "  proxy:     ${PROXY_SCRIPT_NAME}"
    echo "  backup:    ${BACKUP_SCRIPT_NAME}"
    echo "  缓存目录:  ${CACHE_DIR}"
    echo ""
}

# ==================== 状态总览 ====================
show_status() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════╗${RESET}"
    echo -e "${BLUE}║          系统工具状态总览                  ║${RESET}"
    echo -e "${BLUE}╚════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "${PURPLE}=== 安全防护 ===${RESET}"
    echo -e "  fail2ban:     $(get_fail2ban_status)"
    echo ""
    echo -e "${PURPLE}=== 网络代理 ===${RESET}"
    echo -e "  Sing-box:     $(get_singbox_status)"
    echo -e "  Snell:        $(get_snell_status)"
    echo ""
    echo -e "${PURPLE}=== 备份工具 ===${RESET}"
    echo -e "  rclone:       $(get_rclone_status)"
    echo -e "  定时备份:     $(get_backup_cron_status)"
    echo ""
}

# ==================== 主菜单 ====================
show_menu() {
    clear

    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║           sys-toolkit - 系统工具集 v${VERSION}                  ║${RESET}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "${PURPLE}=== 工具状态 ===${RESET}"
    echo -e "  fail2ban: $(get_fail2ban_status)"
    echo -e "  Sing-box: $(get_singbox_status)"
    echo -e "  Snell:    $(get_snell_status)"
    echo -e "  rclone:   $(get_rclone_status)"
    echo -e "  定时备份: $(get_backup_cron_status)"
    echo ""
    echo -e "${PURPLE}=== 工具选择 ===${RESET}"
    echo "1. fail2ban 管理 (入侵检测和防护)"
    echo "2. 网络代理配置 (Sing-box/Snell)"
    echo "3. 系统备份恢复 (rclone)"
    echo ""
    echo -e "${PURPLE}=== 其他选项 ===${RESET}"
    echo "4. 查看所有工具状态"
    echo "5. 查看帮助信息"
    echo ""
    echo -e "${RED}99. 完全卸载 (删除所有组件和配置)${RESET}"
    echo ""
    echo "0. 退出"
    echo ""
    read -r -p "请输入选项编号: " choice
    echo ""
}

# ==================== 信号处理 ====================
trap 'echo -e "\n${RED}已取消操作${RESET}"; exit' INT

# ==================== 主程序入口 ====================
main() {
    check_root
    check_curl

    # 命令行模式
    if [ $# -gt 0 ]; then
        case "$1" in
            fail2ban)
                shift
                run_fail2ban "$@"
                ;;
            proxy)
                shift
                run_proxy "$@"
                ;;
            backup)
                shift
                run_backup "$@"
                ;;
            status)
                show_status
                ;;
            uninstall)
                uninstall_all
                ;;
            help|--help|-h)
                show_help
                ;;
            version|--version|-v)
                echo "sys-toolkit v${VERSION}"
                ;;
            *)
                log_error "未知命令: $1"
                show_help
                exit 1
                ;;
        esac
        return $?
    fi

    # 交互式菜单
    while true; do
        show_menu

        case "${choice}" in
            1)
                run_fail2ban
                ;;
            2)
                run_proxy
                ;;
            3)
                run_backup
                ;;
            4)
                show_status
                ;;
            5)
                show_help
                ;;
            99)
                uninstall_all
                ;;
            0)
                log_info "退出 sys-toolkit"
                exit 0
                ;;
            *)
                log_error "无效的选项编号"
                ;;
        esac

        echo ""
        read -p "按 Enter 键返回主菜单..." -r
    done
}

# 执行主程序
main "$@"
