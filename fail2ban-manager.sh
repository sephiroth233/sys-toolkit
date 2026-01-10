#!/bin/bash

# fail2ban 管理工具 - Linux 系统入侵检测和防护
# 功能: 自动安装、配置和管理 fail2ban 服务
# 用法: sudo ./fail2ban-manager.sh

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
CONFIG_DIR="/etc/fail2ban"
CONFIG_FILE="${CONFIG_DIR}/jail.local"
CONFIG_BACKUP_DIR="${CONFIG_DIR}/backup"
LOG_FILE="/var/log/fail2ban/fail2ban.log"
SERVICE_NAME="fail2ban"

# ==================== 日志函数 ====================
log_info() {
    echo -e "${GREEN}[INFO]${RESET} $1" | tee -a /tmp/fail2ban-manager.log
}

log_warn() {
    echo -e "${YELLOW}[WARN]${RESET} $1" | tee -a /tmp/fail2ban-manager.log
}

log_error() {
    echo -e "${RED}[ERROR]${RESET} $1" | tee -a /tmp/fail2ban-manager.log
}

log_debug() {
    echo -e "${CYAN}[DEBUG]${RESET} $1" | tee -a /tmp/fail2ban-manager.log
}

# ==================== 权限检查 ====================
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}请使用 root 权限执行此脚本！${RESET}"
        exit 1
    fi
}

# ==================== 系统初始化 ====================
init_system() {
    mkdir -p "$CONFIG_BACKUP_DIR" 2>/dev/null || true
    chmod 700 "$CONFIG_BACKUP_DIR" 2>/dev/null || true
    log_debug "系统初始化完成"
}

# ==================== 包管理器检测和工具安装 ====================

# 检测包管理器
detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        echo "apt"
    elif command -v yum &> /dev/null; then
        echo "yum"
    elif command -v dnf &> /dev/null; then
        echo "dnf"
    elif command -v pacman &> /dev/null; then
        echo "pacman"
    elif command -v zypper &> /dev/null; then
        echo "zypper"
    else
        echo ""
    fi
}

# 自动安装 fail2ban
install_fail2ban() {
    local pkg_manager=$(detect_package_manager)

    if [ -z "$pkg_manager" ]; then
        log_error "无法检测到支持的包管理器（apt/yum/dnf/pacman/zypper）"
        return 1
    fi

    log_info "检测到包管理器: $pkg_manager"
    log_info "正在安装 fail2ban..."

    case "$pkg_manager" in
        apt)
            sudo apt-get update || {
                log_error "apt-get update 失败"
                return 1
            }
            sudo apt-get install -y fail2ban || {
                log_error "fail2ban 安装失败"
                return 1
            }
            ;;
        yum)
            # CentOS/RHEL 需要 EPEL 仓库
            sudo yum install -y epel-release 2>/dev/null || true
            sudo yum install -y fail2ban || {
                log_error "fail2ban 安装失败"
                return 1
            }
            ;;
        dnf)
            sudo dnf install -y epel-release 2>/dev/null || true
            sudo dnf install -y fail2ban || {
                log_error "fail2ban 安装失败"
                return 1
            }
            ;;
        pacman)
            sudo pacman -Sy --noconfirm fail2ban || {
                log_error "fail2ban 安装失败"
                return 1
            }
            ;;
        zypper)
            sudo zypper install -y fail2ban || {
                log_error "fail2ban 安装失败"
                return 1
            }
            ;;
    esac

    # 验证安装完整性
    if ! verify_fail2ban_installation; then
        log_error "fail2ban 安装不完整，尝试重新安装..."
        case "$pkg_manager" in
            apt)
                sudo apt-get install --reinstall -y fail2ban
                ;;
            yum|dnf)
                sudo $pkg_manager reinstall -y fail2ban
                ;;
        esac

        if ! verify_fail2ban_installation; then
            log_error "fail2ban 安装仍然不完整"
            return 1
        fi
    fi

    log_info "fail2ban 安装成功"
    return 0
}

# 验证 fail2ban 安装完整性
verify_fail2ban_installation() {
    local missing_files=()

    # 检查关键目录和文件
    local required_paths=(
        "/etc/fail2ban/fail2ban.conf"
        "/etc/fail2ban/filter.d"
        "/etc/fail2ban/action.d"
    )

    for path in "${required_paths[@]}"; do
        if [ ! -e "$path" ]; then
            missing_files+=("$path")
        fi
    done

    if [ ${#missing_files[@]} -gt 0 ]; then
        log_warn "缺少以下关键文件/目录："
        for file in "${missing_files[@]}"; do
            log_warn "  - $file"
        done
        return 1
    fi

    # 检查 sshd 过滤器（可能是 sshd.conf 或在子目录中）
    if [ ! -f "/etc/fail2ban/filter.d/sshd.conf" ]; then
        log_warn "缺少 sshd 过滤器配置"
        # 尝试创建基本的 sshd 过滤器
        create_sshd_filter
    else
        # 检查 sshd.conf 是否包含有效的 [Definition] 部分
        if ! grep -q "^\[Definition\]" "/etc/fail2ban/filter.d/sshd.conf" 2>/dev/null; then
            log_warn "sshd 过滤器配置不完整，缺少 [Definition] 部分，正在重新创建..."
            rm -f /etc/fail2ban/filter.d/sshd.conf
            create_sshd_filter
        fi
    fi

    # 检查 common.conf 是否存在且有效
    if [ ! -f "/etc/fail2ban/filter.d/common.conf" ]; then
        log_warn "缺少 common.conf 过滤器，正在创建..."
        create_sshd_filter
    fi

    log_info "fail2ban 安装完整性验证通过"
    return 0
}

# 创建基本的 sshd 过滤器（如果系统缺失）
create_sshd_filter() {
    log_info "正在创建 sshd 过滤器配置..."

    mkdir -p /etc/fail2ban/filter.d

    cat > /etc/fail2ban/filter.d/sshd.conf << 'SSHD_FILTER'
# Fail2Ban filter for sshd
# 基本 SSH 过滤器配置

[INCLUDES]
before = common.conf

[Definition]
_daemon = sshd

failregex = ^%(__prefix_line)s(?:error: PAM: )?[aA]uthentication (?:failure|error|failed) for .* from <HOST>( via \S+)?\s*$
            ^%(__prefix_line)s(?:error: PAM: )?User not known to the underlying authentication module for .* from <HOST>\s*$
            ^%(__prefix_line)sFailed \S+ for (?P<cond_inv>invalid user )?(?P<user>(?P<cond_user>\S+)|(?(cond_inv)(?:(?! from ).)*?|[^:]+)) from <HOST>(?: port \d+)?(?: ssh\d*)?(?(cond_user): |(?:(?:(?! from ).)*)$)
            ^%(__prefix_line)sROOT LOGIN REFUSED.* FROM <HOST>\s*$
            ^%(__prefix_line)s[iI](?:llegal|nvalid) user .*? from <HOST>(?: port \d+)?(?: on \S+(?: port \d+)?)?\s*$
            ^%(__prefix_line)sUser .+ from <HOST> not allowed because not listed in AllowUsers\s*$
            ^%(__prefix_line)sUser .+ from <HOST> not allowed because listed in DenyUsers\s*$
            ^%(__prefix_line)sUser .+ from <HOST> not allowed because not in any group\s*$
            ^%(__prefix_line)srefused connect from \S+ \(<HOST>\)\s*$
            ^%(__prefix_line)s(?:error: )?Received disconnect from <HOST>(?: port \d+)?:\s*\d+: \S+: Auth fail(?: \[preauth\])?\s*$
            ^%(__prefix_line)s(?:error: )?maximum authentication attempts exceeded for .* from <HOST>(?: port \d+)?(?: ssh\d*)? \[preauth\]\s*$
            ^%(__prefix_line)spam_unix\(sshd:auth\):\s+authentication failure;\s*logname=\S*\s*uid=\d*\s*euid=\d*\s*tty=\S*\s*ruser=\S*\s*rhost=<HOST>\s.*$

ignoreregex =

[Init]
journalmatch = _SYSTEMD_UNIT=sshd.service + _COMM=sshd
SSHD_FILTER

    # 创建 common.conf 如果不存在
    if [ ! -f "/etc/fail2ban/filter.d/common.conf" ]; then
        cat > /etc/fail2ban/filter.d/common.conf << 'COMMON_FILTER'
# Common definitions for fail2ban filters

[INCLUDES]

[DEFAULT]
_daemon = \S+

[Definition]
__prefix_line = \s*(?:\S+ )?(?:@vserver_\S+ )?(?:(?:\[\d+\])?:\s+)?(?:\[\S+\]\s+)?(?:<[^.]+\.[^.]+>\s+)?(?:\S+\s+)?(?:kernel:\s+)?(?:\[ID \d+ \S+\]\s+)?(?:\S+\s+)?(?:(?:(?:\S+\s+)?%(__hostname)s|%(_daemon)s(?:\[\d+\])?)(?::\s+)?(?:\[\S+\]\s+)?)?

__hostname = [\w\.-]+

COMMON_FILTER
    fi

    log_info "sshd 过滤器配置已创建"
}

# 检查 fail2ban 是否已安装
is_fail2ban_installed() {
    command -v fail2ban-client &> /dev/null
}

# 检查 fail2ban 是否运行
is_fail2ban_running() {
    systemctl is-active --quiet "$SERVICE_NAME"
    return $?
}

# ==================== fail2ban 配置管理 ====================

# 生成默认 jail.local 配置
generate_jail_config() {
    log_info "生成 jail.local 配置..."

    # 确保配置目录存在
    if [ ! -d "/etc/fail2ban" ]; then
        log_warn "fail2ban 配置目录不存在，正在创建..."
        mkdir -p /etc/fail2ban
    fi

    # 检查系统是否有 jail.conf（仅作为警告，不阻止配置生成）
    if [ ! -f "/etc/fail2ban/jail.conf" ]; then
        log_warn "系统中不存在 /etc/fail2ban/jail.conf，将创建独立的 jail.local 配置"
    fi

    # 检测系统使用的防火墙
    local banaction="iptables-multiport"
    if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
        banaction="ufw"
        log_info "检测到 UFW 防火墙，使用 ufw 作为禁封操作"
    elif command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
        banaction="firewallcmd-ipset"
        log_info "检测到 firewalld 防火墙，使用 firewallcmd-ipset 作为禁封操作"
    else
        log_info "使用默认 iptables 作为禁封操作"
    fi

    # 检测 SSH 日志文件路径
    local ssh_logpath="/var/log/auth.log"
    if [ -f "/var/log/secure" ]; then
        ssh_logpath="/var/log/secure"
        log_info "检测到 CentOS/RHEL 系统，使用 /var/log/secure"
    fi

    # 创建自定义配置
    cat > /tmp/jail-custom.local << EOF
# ==================== Fail2ban 自定义配置 ====================
# 此文件将覆盖系统默认配置
# 修改此文件后需要重启 fail2ban 服务
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

[DEFAULT]
# 禁封时间（秒）；-1 表示永久禁封
bantime = -1
# 查找时间窗口（秒），在此时间内达到 maxretry 次失败将被禁封
findtime = 1d
# 最大尝试次数
maxretry = 5
# 禁封操作方式
banaction = ${banaction}
# 操作组合
action = %(action_)s

# ==================== SSHd 规则 ====================
[sshd]
# 本地 IP 不禁封
ignoreip = 127.0.0.1/8 ::1
# 启用此规则
enabled = true
# 使用的过滤器
filter = sshd
# SSHd 监听端口（如果修改了 SSH 端口，请在此修改）
port = ssh
# 最大失败次数
maxretry = 3
# 查找时间窗口
findtime = 1d
# 禁封时间（-1 表示永久禁封）
bantime = -1
# 禁封操作
banaction = ${banaction}
# 日志文件路径
logpath = ${ssh_logpath}
# 后端检测方式
backend = auto

EOF

    # 将自定义配置作为 jail.local
    sudo cp /tmp/jail-custom.local "$CONFIG_FILE" || {
        log_error "生成配置文件失败"
        rm -f /tmp/jail-custom.local
        return 1
    }
    rm -f /tmp/jail-custom.local

    log_info "jail.local 配置生成成功: $CONFIG_FILE"
    return 0
}

# ==================== 服务管理 ====================

cmd_install() {
    if is_fail2ban_installed; then
        log_warn "fail2ban 已经安装"
        # 重新验证并修复配置
        log_info "正在验证并修复配置..."
        verify_fail2ban_installation || true
        generate_jail_config || true
        return 0
    fi

    install_fail2ban || {
        log_error "fail2ban 安装失败"
        return 1
    }

    # 验证并创建过滤器配置（在生成 jail 配置之前）
    verify_fail2ban_installation || {
        log_error "过滤器配置验证失败"
        return 1
    }

    # 生成配置
    generate_jail_config || {
        log_error "配置生成失败，但 fail2ban 已安装"
        return 1
    }

    # 启用并启动服务
    log_info "启用 fail2ban 服务..."
    sudo systemctl enable "$SERVICE_NAME" || {
        log_error "启用 fail2ban 服务失败"
        return 1
    }

    log_info "启动 fail2ban 服务..."
    sudo systemctl start "$SERVICE_NAME" || {
        log_error "启动 fail2ban 服务失败"
        return 1
    }

    log_info "fail2ban 安装和配置完成"
    return 0
}

cmd_uninstall() {
    if ! is_fail2ban_installed; then
        log_warn "fail2ban 未安装"
        return 0
    fi

    read -p "$(echo -e "${RED}确定要卸载 fail2ban 吗？(y/n)${RESET}")" -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "已取消卸载"
        return 0
    fi

    log_info "停止 fail2ban 服务..."
    sudo systemctl stop "$SERVICE_NAME" || true

    log_info "禁用 fail2ban 服务..."
    sudo systemctl disable "$SERVICE_NAME" || true

    local pkg_manager=$(detect_package_manager)
    case "$pkg_manager" in
        apt)
            sudo apt-get remove -y fail2ban || {
                log_error "卸载失败"
                return 1
            }
            ;;
        yum|dnf)
            sudo "$pkg_manager" remove -y fail2ban || {
                log_error "卸载失败"
                return 1
            }
            ;;
        pacman)
            sudo pacman -R --noconfirm fail2ban || {
                log_error "卸载失败"
                return 1
            }
            ;;
        zypper)
            sudo zypper remove -y fail2ban || {
                log_error "卸载失败"
                return 1
            }
            ;;
    esac

    log_info "fail2ban 卸载成功"
}

cmd_start() {
    if ! is_fail2ban_installed; then
        log_error "fail2ban 未安装"
        return 1
    fi

    # 启动前验证配置
    log_info "验证 fail2ban 配置..."
    if ! verify_fail2ban_installation; then
        log_error "配置验证失败，无法启动服务"
        return 1
    fi

    log_info "启动 fail2ban 服务..."
    if sudo systemctl start "$SERVICE_NAME"; then
        log_info "fail2ban 服务已启动"
        return 0
    else
        log_error "启动 fail2ban 服务失败"
        return 1
    fi
}

cmd_stop() {
    if ! is_fail2ban_installed; then
        log_error "fail2ban 未安装"
        return 1
    fi

    log_info "停止 fail2ban 服务..."
    if sudo systemctl stop "$SERVICE_NAME"; then
        log_info "fail2ban 服务已停止"
        return 0
    else
        log_error "停止 fail2ban 服务失败"
        return 1
    fi
}

cmd_restart() {
    if ! is_fail2ban_installed; then
        log_error "fail2ban 未安装"
        return 1
    fi

    log_info "重启 fail2ban 服务..."
    if sudo systemctl restart "$SERVICE_NAME"; then
        log_info "fail2ban 服务已重启"
        return 0
    else
        log_error "重启 fail2ban 服务失败"
        return 1
    fi
}

cmd_status() {
    if ! is_fail2ban_installed; then
        log_error "fail2ban 未安装"
        return 1
    fi

    echo ""
    echo -e "${BLUE}=== fail2ban 服务状态 ===${RESET}"
    sudo systemctl status "$SERVICE_NAME" --no-pager || true
    echo ""
}

# ==================== Jail 和 IP 管理 ====================

cmd_jail_status() {
    if ! is_fail2ban_installed; then
        log_error "fail2ban 未安装"
        return 1
    fi

    if ! is_fail2ban_running; then
        log_error "fail2ban 服务未运行"
        return 1
    fi

    echo ""
    echo -e "${BLUE}=== 所有 Jail 状态 ===${RESET}"
    sudo fail2ban-client status || {
        log_error "获取状态失败"
        return 1
    }
    echo ""
}

cmd_view_banned_ips() {
    if ! is_fail2ban_installed; then
        log_error "fail2ban 未安装"
        return 1
    fi

    if ! is_fail2ban_running; then
        log_error "fail2ban 服务未运行"
        return 1
    fi

    echo ""
    echo -e "${BLUE}请选择要查看的 Jail:${RESET}"

    # 获取所有 jail
    local jails=$(sudo fail2ban-client status | grep "Jail list:" | sed 's/.*Jail list:\s*//g' | tr ',' '\n' | sed 's/^\s*//g' | sed 's/\s*$//g')

    if [ -z "$jails" ]; then
        log_warn "没有配置的 Jail"
        return 0
    fi

    local i=1
    local -a jail_array
    while read -r jail; do
        [ -z "$jail" ] && continue
        jail_array+=("$jail")
        echo "$i. $jail"
        ((i++))
    done <<< "$jails"

    read -p "请选择 Jail (1-$((${#jail_array[@]}))), 或 0 返回: " choice

    if [ "$choice" -eq 0 ] 2>/dev/null; then
        return 0
    fi

    if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "${#jail_array[@]}" ]; then
        local selected_jail="${jail_array[$((choice-1))]}"
        echo ""
        echo -e "${BLUE}=== $selected_jail 被禁封的 IP ===${RESET}"
        sudo fail2ban-client status "$selected_jail" || true
        echo ""
    else
        log_error "无效选择"
        return 1
    fi
}

cmd_ban_ip() {
    if ! is_fail2ban_installed; then
        log_error "fail2ban 未安装"
        return 1
    fi

    if ! is_fail2ban_running; then
        log_error "fail2ban 服务未运行"
        return 1
    fi

    read -p "请输入要禁封的 IP 地址: " ban_ip
    [ -z "$ban_ip" ] && {
        log_error "IP 地址不能为空"
        return 1
    }

    echo ""
    echo -e "${BLUE}请选择 Jail:${RESET}"

    local jails=$(sudo fail2ban-client status | grep "Jail list:" | sed 's/.*Jail list:\s*//g' | tr ',' '\n' | sed 's/^\s*//g' | sed 's/\s*$//g')

    local i=1
    local -a jail_array
    while read -r jail; do
        [ -z "$jail" ] && continue
        jail_array+=("$jail")
        echo "$i. $jail"
        ((i++))
    done <<< "$jails"

    read -p "请选择 Jail (1-$((${#jail_array[@]}))): " choice

    if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "${#jail_array[@]}" ]; then
        local selected_jail="${jail_array[$((choice-1))]}"
        log_info "禁封 IP $ban_ip 到 Jail $selected_jail"
        sudo fail2ban-client set "$selected_jail" banip "$ban_ip" || {
            log_error "禁封 IP 失败"
            return 1
        }
        log_info "IP 已禁封"
        return 0
    else
        log_error "无效选择"
        return 1
    fi
}

cmd_unban_ip() {
    if ! is_fail2ban_installed; then
        log_error "fail2ban 未安装"
        return 1
    fi

    if ! is_fail2ban_running; then
        log_error "fail2ban 服务未运行"
        return 1
    fi

    read -p "请输入要解禁的 IP 地址: " unban_ip
    [ -z "$unban_ip" ] && {
        log_error "IP 地址不能为空"
        return 1
    }

    echo ""
    echo -e "${BLUE}请选择 Jail:${RESET}"

    local jails=$(sudo fail2ban-client status | grep "Jail list:" | sed 's/.*Jail list:\s*//g' | tr ',' '\n' | sed 's/^\s*//g' | sed 's/\s*$//g')

    local i=1
    local -a jail_array
    while read -r jail; do
        [ -z "$jail" ] && continue
        jail_array+=("$jail")
        echo "$i. $jail"
        ((i++))
    done <<< "$jails"

    read -p "请选择 Jail (1-$((${#jail_array[@]}))): " choice

    if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "${#jail_array[@]}" ]; then
        local selected_jail="${jail_array[$((choice-1))]}"
        log_info "解禁 IP $unban_ip 在 Jail $selected_jail"
        sudo fail2ban-client set "$selected_jail" unbanip "$unban_ip" || {
            log_error "解禁 IP 失败"
            return 1
        }
        log_info "IP 已解禁"
        return 0
    else
        log_error "无效选择"
        return 1
    fi
}

# ==================== 配置管理 ====================

cmd_view_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "配置文件不存在: $CONFIG_FILE"
        return 1
    fi

    echo ""
    echo -e "${BLUE}=== fail2ban 配置文件 ===${RESET}"
    echo -e "${CYAN}文件路径: $CONFIG_FILE${RESET}"
    echo ""
    sudo cat "$CONFIG_FILE" | head -50
    echo "..."
    echo -e "${YELLOW}(显示前 50 行，完整内容请直接编辑文件)${RESET}"
    echo ""
}

cmd_edit_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "配置文件不存在: $CONFIG_FILE"
        return 1
    fi

    log_info "打开配置文件编辑器..."
    log_warn "提示：编辑完成后需要重启 fail2ban 服务使配置生效"

    # 尝试使用 vim、vi 或 nano
    if command -v vim &> /dev/null; then
        sudo vim "$CONFIG_FILE"
    elif command -v vi &> /dev/null; then
        sudo vi "$CONFIG_FILE"
    elif command -v nano &> /dev/null; then
        sudo nano "$CONFIG_FILE"
    else
        log_error "未找到编辑器（vim/vi/nano）"
        return 1
    fi

    # 编辑后提示重启
    read -p "配置已修改，是否现在重启 fail2ban 服务? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cmd_restart
    fi
}

cmd_backup_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "配置文件不存在: $CONFIG_FILE"
        return 1
    fi

    local backup_file="${CONFIG_BACKUP_DIR}/jail.local.backup.$(date +%Y%m%d-%H%M%S)"

    log_info "备份配置到: $backup_file"
    sudo cp "$CONFIG_FILE" "$backup_file" || {
        log_error "备份失败"
        return 1
    }

    log_info "配置备份成功"

    # 清理旧备份（保留最多 5 个）
    local backup_count=$(sudo find "$CONFIG_BACKUP_DIR" -name "jail.local.backup.*" | wc -l)
    if [ "$backup_count" -gt 5 ]; then
        log_info "清理旧备份（保留最多 5 个）..."
        sudo find "$CONFIG_BACKUP_DIR" -name "jail.local.backup.*" -type f | sort -r | tail -n +6 | xargs sudo rm -f
    fi
}

cmd_restore_config() {
    if [ ! -d "$CONFIG_BACKUP_DIR" ]; then
        log_error "备份目录不存在"
        return 1
    fi

    local backups=$(sudo find "$CONFIG_BACKUP_DIR" -name "jail.local.backup.*" -type f 2>/dev/null | sort -r)

    if [ -z "$backups" ]; then
        log_warn "没有备份文件"
        return 0
    fi

    echo ""
    echo -e "${BLUE}=== 可用的备份 ===${RESET}"

    local i=1
    local -a backup_array
    while IFS= read -r backup; do
        backup_array+=("$backup")
        local filename=$(basename "$backup")
        echo "$i. $filename"
        ((i++))
    done <<< "$backups"

    read -p "请选择要恢复的备份 (1-$((${#backup_array[@]}))): " choice

    if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "${#backup_array[@]}" ]; then
        local selected_backup="${backup_array[$((choice-1))]}"

        read -p "$(echo -e "${RED}确定要恢复此备份吗？(y/n)${RESET}")" -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "恢复备份: $(basename "$selected_backup")"
            sudo cp "$selected_backup" "$CONFIG_FILE" || {
                log_error "恢复失败"
                return 1
            }

            log_info "配置已恢复"
            read -p "是否现在重启 fail2ban 服务? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                cmd_restart
            fi
        fi
    else
        log_error "无效选择"
        return 1
    fi
}

# ==================== 日志管理 ====================

cmd_view_logs() {
    if ! is_fail2ban_installed; then
        log_error "fail2ban 未安装"
        return 1
    fi

    log_info "显示最近 100 条日志（按 q 退出）"
    echo ""
    sudo journalctl -u fail2ban -n 100 --no-pager || {
        log_error "无法读取日志"
        return 1
    }
    echo ""
}

cmd_view_realtime_logs() {
    if ! is_fail2ban_installed; then
        log_error "fail2ban 未安装"
        return 1
    fi

    log_info "显示实时日志（按 Ctrl+C 退出）"
    echo ""
    sudo journalctl -u fail2ban -f || true
}

# ==================== 帮助信息 ====================

show_help() {
    cat << EOF

╔════════════════════════════════════════════════════════════════╗
║         fail2ban 管理工具 - Linux 入侵检测和防护系统           ║
╚════════════════════════════════════════════════════════════════╝

【命令用法】
  sudo ./fail2ban-manager.sh [命令]

【主要命令】
  install       - 安装和配置 fail2ban
  uninstall     - 卸载 fail2ban
  start         - 启动服务
  stop          - 停止服务
  restart       - 重启服务
  status        - 查看服务状态

【Jail 和 IP 管理】
  jail-status   - 查看所有 Jail 状态
  view-banned   - 查看被禁封的 IP
  ban-ip        - 手动禁封 IP
  unban-ip      - 手动解禁 IP

【配置管理】
  view-config   - 查看配置
  edit-config   - 编辑配置
  backup-config - 备份配置
  restore-config- 恢复备份

【日志管理】
  view-logs     - 查看最近日志
  realtime-logs - 查看实时日志

【其他】
  help          - 显示此帮助信息

【配置文件位置】
  $CONFIG_FILE

【默认配置说明】
  - SSH 监听端口: 22（请根据实际情况修改）
  - 禁封时间: 永久禁封（DEFAULT）、永久禁封（SSHd）
  - 最大尝试: 3 次（DEFAULT）、3 次（SSHd）
  - 防火墙: ufw

【示例】
  # 安装 fail2ban
  sudo ./fail2ban-manager.sh install

  # 启动服务
  sudo ./fail2ban-manager.sh start

  # 查看禁封的 IP
  sudo ./fail2ban-manager.sh view-banned

  # 编辑配置
  sudo ./fail2ban-manager.sh edit-config

【更多信息】
  https://www.fail2ban.org/

EOF
}

# ==================== 菜单显示 ====================

show_menu() {
    clear

    # 检查安装状态
    if is_fail2ban_installed; then
        install_status="${GREEN}已安装${RESET}"
        if is_fail2ban_running; then
            run_status="${GREEN}运行中${RESET}"
        else
            run_status="${RED}已停止${RESET}"
        fi
    else
        install_status="${RED}未安装${RESET}"
        run_status="${YELLOW}N/A${RESET}"
    fi

    echo -e "${BLUE}╔════════════════════════════════════════════╗${RESET}"
    echo -e "${BLUE}║       fail2ban 管理工具 - 主菜单           ║${RESET}"
    echo -e "${BLUE}╚════════════════════════════════════════════╝${RESET}"
    echo -e "安装状态: $install_status"
    echo -e "运行状态: $run_status"
    echo ""

    echo -e "${PURPLE}=== 服务管理 ===${RESET}"
    echo "1. 安装 fail2ban"
    echo "2. 卸载 fail2ban"
    if is_fail2ban_installed; then
        if is_fail2ban_running; then
            echo "3. 停止服务"
        else
            echo "3. 启动服务"
        fi
        echo "4. 重启服务"
        echo "5. 查看服务状态"
        echo ""

        echo -e "${PURPLE}=== Jail 和 IP 管理 ===${RESET}"
        echo "6. 查看所有 Jail 状态"
        echo "7. 查看被禁封的 IP"
        echo "8. 手动禁封 IP"
        echo "9. 手动解禁 IP"
        echo ""

        echo -e "${PURPLE}=== 配置管理 ===${RESET}"
        echo "10. 查看配置"
        echo "11. 编辑配置"
        echo "12. 备份配置"
        echo "13. 恢复备份"
        echo ""

        echo -e "${PURPLE}=== 日志管理 ===${RESET}"
        echo "14. 查看最近日志"
        echo "15. 查看实时日志"
    fi

    echo ""
    echo -e "${PURPLE}=== 其他 ===${RESET}"
    echo "16. 查看帮助"
    echo "0. 退出"
    echo ""

    read -p "请输入选项编号: " choice
    echo ""
}

# ==================== 信号处理 ====================
trap 'echo -e "\n${RED}已取消操作${RESET}"; exit' INT

# ==================== 主程序入口 ====================

main() {
    check_root
    init_system

    # 命令行模式
    if [ $# -gt 0 ]; then
        case "$1" in
            install)       cmd_install ;;
            uninstall)     cmd_uninstall ;;
            start)         cmd_start ;;
            stop)          cmd_stop ;;
            restart)       cmd_restart ;;
            status)        cmd_status ;;
            jail-status)   cmd_jail_status ;;
            view-banned)   cmd_view_banned_ips ;;
            ban-ip)        cmd_ban_ip ;;
            unban-ip)      cmd_unban_ip ;;
            view-config)   cmd_view_config ;;
            edit-config)   cmd_edit_config ;;
            backup-config) cmd_backup_config ;;
            restore-config)cmd_restore_config ;;
            view-logs)     cmd_view_logs ;;
            realtime-logs) cmd_view_realtime_logs ;;
            help)          show_help ;;
            *)             log_error "未知命令: $1"; show_help ;;
        esac
        return $?
    fi

    # 交互式菜单
    while true; do
        show_menu

        case "${choice}" in
            1)
                if is_fail2ban_installed; then
                    log_warn "fail2ban 已经安装"
                else
                    cmd_install
                fi
                ;;
            2)
                if is_fail2ban_installed; then
                    cmd_uninstall
                else
                    log_warn "fail2ban 未安装"
                fi
                ;;
            3)
                if is_fail2ban_installed; then
                    if is_fail2ban_running; then
                        cmd_stop
                    else
                        cmd_start
                    fi
                else
                    log_error "fail2ban 未安装"
                fi
                ;;
            4)
                if is_fail2ban_installed; then
                    cmd_restart
                else
                    log_error "fail2ban 未安装"
                fi
                ;;
            5)
                if is_fail2ban_installed; then
                    cmd_status
                else
                    log_error "fail2ban 未安装"
                fi
                ;;
            6)
                if is_fail2ban_installed; then
                    cmd_jail_status
                else
                    log_error "fail2ban 未安装"
                fi
                ;;
            7)
                if is_fail2ban_installed; then
                    cmd_view_banned_ips
                else
                    log_error "fail2ban 未安装"
                fi
                ;;
            8)
                if is_fail2ban_installed; then
                    cmd_ban_ip
                else
                    log_error "fail2ban 未安装"
                fi
                ;;
            9)
                if is_fail2ban_installed; then
                    cmd_unban_ip
                else
                    log_error "fail2ban 未安装"
                fi
                ;;
            10)
                cmd_view_config
                ;;
            11)
                cmd_edit_config
                ;;
            12)
                cmd_backup_config
                ;;
            13)
                cmd_restore_config
                ;;
            14)
                cmd_view_logs
                ;;
            15)
                cmd_view_realtime_logs
                ;;
            16)
                show_help
                ;;
            0)
                log_info "退出 fail2ban 管理工具"
                exit 0
                ;;
            *)
                log_error "无效的选项编号"
                ;;
        esac

        read -p "按 Enter 键继续..."
    done
}

# 执行主程序
main "$@"
