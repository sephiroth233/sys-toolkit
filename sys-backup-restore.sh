#!/bin/bash

# ============================================================
# sys-backup-restore.sh - 基于 rclone 的系统备份恢复工具
# 功能：自动安装rclone、备份到云端、从云端恢复、定时备份管理
# ============================================================

# 定义颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
RESET='\033[0m'

# ==================== 配置常量 ====================
# 配置文件路径
CONFIG_DIR="/etc/sys-backup"
CONFIG_FILE="${CONFIG_DIR}/config.conf"
LOG_DIR="/var/log/sys-backup"
LOG_FILE="${LOG_DIR}/backup.log"
CRON_LOG_FILE="${LOG_DIR}/cron.log"

# 默认配置
DEFAULT_SOURCE_DIR="/opt"
DEFAULT_RCLONE_REMOTE="s3:sys-backup"
DEFAULT_MAX_BACKUPS=1
DEFAULT_TEMP_DIR="/tmp/sys-backup"

# 当前配置（从配置文件加载或使用默认值）
SOURCE_DIR=""
RCLONE_REMOTE=""
MAX_BACKUPS=""
TEMP_DIR=""

# ==================== 日志函数 ====================
log_info() {
    local message="$1"
    echo -e "${GREEN}[INFO]${RESET} $message"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $message" >> "$LOG_FILE" 2>/dev/null
}

log_warn() {
    local message="$1"
    echo -e "${YELLOW}[WARN]${RESET} $message"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $message" >> "$LOG_FILE" 2>/dev/null
}

log_error() {
    local message="$1"
    echo -e "${RED}[ERROR]${RESET} $message"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $message" >> "$LOG_FILE" 2>/dev/null
}

log_success() {
    local message="$1"
    echo -e "${GREEN}[SUCCESS]${RESET} $message"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $message" >> "$LOG_FILE" 2>/dev/null
}

# ==================== 权限检查 ====================
check_root() {
    if [ "$(id -u)" != "0" ]; then
        log_error "请使用 root 权限执行此脚本！"
        exit 1
    fi
}

# ==================== 初始化系统 ====================
init_system() {
    # 创建配置目录
    if [ ! -d "$CONFIG_DIR" ]; then
        mkdir -p "$CONFIG_DIR"
    fi

    # 创建日志目录
    if [ ! -d "$LOG_DIR" ]; then
        mkdir -p "$LOG_DIR"
    fi

    # 加载配置
    load_config
}

# ==================== 配置管理 ====================
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi

    # 使用配置文件值或默认值
    SOURCE_DIR="${SOURCE_DIR:-$DEFAULT_SOURCE_DIR}"
    RCLONE_REMOTE="${RCLONE_REMOTE:-$DEFAULT_RCLONE_REMOTE}"
    MAX_BACKUPS="${MAX_BACKUPS:-$DEFAULT_MAX_BACKUPS}"
    TEMP_DIR="${TEMP_DIR:-$DEFAULT_TEMP_DIR}"
}

save_config() {
    cat > "$CONFIG_FILE" << EOF
# sys-backup 配置文件
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

# 需要备份的目录路径
SOURCE_DIR="$SOURCE_DIR"

# rclone 远程存储路径 (格式: remote_name:bucket/path)
RCLONE_REMOTE="$RCLONE_REMOTE"

# 保留的最大备份数量
MAX_BACKUPS="$MAX_BACKUPS"

# 临时文件存放目录
TEMP_DIR="$TEMP_DIR"
EOF
    log_success "配置已保存到 $CONFIG_FILE"
}

# ==================== rclone 安装和检查 ====================
is_rclone_installed() {
    command -v rclone &> /dev/null
}

install_rclone() {
    log_info "正在安装 rclone..."

    if is_rclone_installed; then
        local version=$(rclone version | head -n 1)
        log_warn "rclone 已安装: $version"
        return 0
    fi

    # 检测系统架构
    local arch=$(uname -m)
    case "$arch" in
        x86_64)
            arch="amd64"
            ;;
        aarch64|arm64)
            arch="arm64"
            ;;
        armv7l)
            arch="arm-v7"
            ;;
        *)
            log_error "不支持的系统架构: $arch"
            return 1
            ;;
    esac

    # 检测操作系统
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')

    log_info "检测到系统: $os, 架构: $arch"

    # 使用官方安装脚本
    log_info "使用官方脚本安装 rclone..."
    curl -fsSL https://rclone.org/install.sh | bash

    if is_rclone_installed; then
        local version=$(rclone version | head -n 1)
        log_success "rclone 安装成功: $version"
        return 0
    else
        log_error "rclone 安装失败"
        return 1
    fi
}

check_rclone() {
    if ! is_rclone_installed; then
        log_warn "rclone 未安装"
        read -p "是否现在安装 rclone? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_rclone
        else
            log_error "rclone 未安装，无法继续"
            return 1
        fi
    fi
    return 0
}

# 配置 rclone remote
configure_rclone_remote() {
    log_info "配置 rclone 远程存储"
    echo ""
    echo -e "${CYAN}=== rclone 远程存储配置 ===${RESET}"
    echo "1. 运行 rclone config 交互式配置"
    echo "2. 查看已配置的远程存储"
    echo "3. 手动设置远程存储路径"
    echo -e "4. 设置备份源目录 (当前: ${YELLOW}$SOURCE_DIR${RESET})"
    echo "0. 返回"
    echo ""
    read -p "请选择操作: " choice

    case "$choice" in
        1)
            log_info "启动 rclone 配置向导..."
            rclone config
            ;;
        2)
            log_info "已配置的远程存储:"
            rclone listremotes
            ;;
        3)
            echo ""
            echo -e "${YELLOW}当前远程存储路径: ${CYAN}$RCLONE_REMOTE${RESET}"
            echo -e "${YELLOW}格式示例: s3:bucket-name/path 或 remote_name:path${RESET}"
            read -p "请输入新的远程存储路径: " new_remote
            if [ -n "$new_remote" ]; then
                RCLONE_REMOTE="$new_remote"
                save_config
            fi
            ;;
        4)
            echo ""
            echo -e "${YELLOW}当前备份源目录: ${CYAN}$SOURCE_DIR${RESET}"
            read -p "请输入新的备份源目录: " new_source
            if [ -n "$new_source" ]; then
                if [ -d "$new_source" ]; then
                    SOURCE_DIR="$new_source"
                    save_config
                else
                    log_error "目录不存在: $new_source"
                fi
            fi
            ;;
        0)
            return
            ;;
        *)
            log_warn "无效选项"
            ;;
    esac
}

# ==================== 备份功能 ====================
do_backup() {
    log_info "开始备份操作..."

    # 检查 rclone
    if ! check_rclone; then
        return 1
    fi

    # 检查源目录
    if [ ! -d "$SOURCE_DIR" ]; then
        log_error "源目录不存在: $SOURCE_DIR"
        return 1
    fi

    # 创建临时目录
    mkdir -p "$TEMP_DIR"

    # 生成备份文件名
    local date_str=$(date +"%Y-%m-%d_%H-%M-%S")
    local source_name=$(basename "$SOURCE_DIR")
    local archive_name="${source_name}-${date_str}.tar.gz"
    local archive_path="${TEMP_DIR}/${archive_name}"

    # 压缩
    log_info "正在压缩 $SOURCE_DIR ..."
    if tar -czf "$archive_path" -C "$(dirname "$SOURCE_DIR")" "$source_name" 2>/dev/null; then
        local size=$(du -h "$archive_path" | cut -f1)
        log_success "压缩完成: $archive_name ($size)"
    else
        log_error "压缩失败"
        return 1
    fi

    # 上传
    log_info "正在上传到 $RCLONE_REMOTE ..."
    # 静默上传，只记录日志，不显示详细进度
    rclone copy "$archive_path" "$RCLONE_REMOTE/" --s3-no-check-bucket \
        --log-file="$LOG_FILE" --log-level INFO 2>/dev/null
    local upload_status=$?

    if [ $upload_status -eq 0 ]; then
        log_success "上传完成: $archive_name"
        rm -f "$archive_path"
        log_info "已删除本地临时文件"

        # 上传成功后清理旧备份
        cleanup_old_backups "$source_name"
        return 0
    else
        log_error "上传失败"
        return 1
    fi
}

cleanup_old_backups() {
    local source_name="$1"

    log_info "检查旧备份..."

    # 获取现有备份列表（上传后的数量）
    local existing_backups=$(rclone lsf "$RCLONE_REMOTE" 2>/dev/null | grep "^${source_name}-.*\.tar\.gz$" | sort)
    local num_backups=$(echo "$existing_backups" | grep -c . || echo 0)

    # 当备份数量超过最大保留数时删除旧备份
    if [ "$num_backups" -gt "$MAX_BACKUPS" ]; then
        local num_to_delete=$((num_backups - MAX_BACKUPS))
        local backups_to_delete=$(echo "$existing_backups" | head -n "$num_to_delete")

        log_info "需要删除 $num_to_delete 个旧备份"

        for backup in $backups_to_delete; do
            log_info "删除旧备份: $backup"
            rclone delete "$RCLONE_REMOTE/$backup" 2>&1 | tee -a "$LOG_FILE"
        done
    else
        log_info "当前备份数量: $num_backups (最大保留: $MAX_BACKUPS)"
    fi
}

# ==================== 恢复功能 ====================
list_backups() {
    log_info "获取云端备份列表..."

    if ! check_rclone; then
        return 1
    fi

    echo ""
    echo -e "${CYAN}=== 云端备份列表 ===${RESET}"
    echo -e "${YELLOW}远程存储: $RCLONE_REMOTE${RESET}"
    echo ""

    local backups=$(rclone lsf "$RCLONE_REMOTE" --format "tsp" 2>/dev/null | grep "\.tar\.gz$" | sort -r)

    if [ -z "$backups" ]; then
        log_warn "没有找到备份文件"
        return 1
    fi

    local index=1
    echo -e "${GREEN}序号\t大小\t\t时间\t\t\t文件名${RESET}"
    echo "------------------------------------------------------------"

    while IFS=';' read -r time size path; do
        printf "%d\t%s\t\t%s\t%s\n" "$index" "$size" "$time" "$path"
        ((index++))
    done <<< "$backups"

    echo ""
    return 0
}

do_restore() {
    log_info "开始恢复操作..."

    if ! check_rclone; then
        return 1
    fi

    # 获取备份列表
    local backups=$(rclone lsf "$RCLONE_REMOTE" 2>/dev/null | grep "\.tar\.gz$" | sort -r)

    if [ -z "$backups" ]; then
        log_warn "没有找到备份文件"
        return 1
    fi

    # 显示备份列表
    echo ""
    echo -e "${CYAN}=== 可恢复的备份 ===${RESET}"
    local index=1
    local backup_array=()

    while read -r backup; do
        echo "$index. $backup"
        backup_array+=("$backup")
        ((index++))
    done <<< "$backups"

    echo ""
    read -p "请选择要恢复的备份序号 (1-$((index-1))): " selection

    # 验证输入
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -ge "$index" ]; then
        log_error "无效的选择"
        return 1
    fi

    local selected_backup="${backup_array[$((selection-1))]}"
    log_info "选择的备份: $selected_backup"

    # 询问恢复路径
    echo ""
    echo -e "${YELLOW}默认恢复路径: $SOURCE_DIR${RESET}"
    read -p "请输入恢复路径 (直接回车使用默认路径): " restore_path
    restore_path="${restore_path:-$SOURCE_DIR}"

    # 确认恢复
    echo ""
    echo -e "${RED}警告: 恢复操作将覆盖目标目录中的同名文件!${RESET}"
    read -p "确定要恢复到 $restore_path? (y/n): " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warn "已取消恢复操作"
        return 0
    fi

    # 创建临时目录
    mkdir -p "$TEMP_DIR"
    local local_archive="${TEMP_DIR}/${selected_backup}"

    # 下载备份
    log_info "正在下载备份文件..."
    # 静默下载，只记录日志，不显示详细进度
    rclone copy "$RCLONE_REMOTE/$selected_backup" "$TEMP_DIR/" \
        --log-file="$LOG_FILE" --log-level INFO 2>/dev/null
    local download_status=$?

    if [ $download_status -eq 0 ]; then
        log_success "下载完成"
    else
        log_error "下载失败"
        return 1
    fi

    # 解压恢复
    log_info "正在解压到 $restore_path ..."
    mkdir -p "$restore_path"

    if tar -xzf "$local_archive" -C "$restore_path" --strip-components=1 2>&1 | tee -a "$LOG_FILE"; then
        rm -f "$local_archive"

        # 显示恢复结果摘要
        echo ""
        echo -e "${GREEN}============================================${RESET}"
        echo -e "${GREEN}           恢复完成!${RESET}"
        echo -e "${GREEN}============================================${RESET}"
        echo -e "备份文件: ${CYAN}$selected_backup${RESET}"
        echo -e "恢复路径: ${CYAN}$restore_path${RESET}"
        echo -e "${GREEN}============================================${RESET}"
        echo ""
        log_info "已删除临时文件"
        echo ""
        read -p "按回车键返回主菜单..." -r
        return 0
    else
        log_error "解压失败"
        return 1
    fi
}

# ==================== 定时任务管理 ====================
get_script_path() {
    readlink -f "$0"
}

setup_cron() {
    log_info "设置定时备份任务"

    echo ""
    echo -e "${CYAN}=== 定时备份设置 ===${RESET}"
    echo "1. 每天备份一次"
    echo "2. 每周备份一次"
    echo "3. 每月备份一次"
    echo "4. 自定义 cron 表达式"
    echo "0. 返回"
    echo ""
    read -p "请选择备份频率: " choice

    local cron_expr=""
    local script_path=$(get_script_path)

    case "$choice" in
        1)
            read -p "请输入每天备份的时间 (格式 HH:MM, 默认 02:00): " backup_time
            backup_time="${backup_time:-02:00}"
            local hour=$(echo "$backup_time" | cut -d: -f1)
            local minute=$(echo "$backup_time" | cut -d: -f2)
            cron_expr="$minute $hour * * *"
            ;;
        2)
            read -p "请输入每周几备份 (0-6, 0=周日, 默认 0): " weekday
            weekday="${weekday:-0}"
            read -p "请输入备份时间 (格式 HH:MM, 默认 02:00): " backup_time
            backup_time="${backup_time:-02:00}"
            local hour=$(echo "$backup_time" | cut -d: -f1)
            local minute=$(echo "$backup_time" | cut -d: -f2)
            cron_expr="$minute $hour * * $weekday"
            ;;
        3)
            read -p "请输入每月几号备份 (1-28, 默认 1): " day
            day="${day:-1}"
            read -p "请输入备份时间 (格式 HH:MM, 默认 02:00): " backup_time
            backup_time="${backup_time:-02:00}"
            local hour=$(echo "$backup_time" | cut -d: -f1)
            local minute=$(echo "$backup_time" | cut -d: -f2)
            cron_expr="$minute $hour $day * *"
            ;;
        4)
            echo -e "${YELLOW}cron 表达式格式: 分 时 日 月 周${RESET}"
            echo -e "${YELLOW}示例: 0 2 * * * (每天凌晨2点)${RESET}"
            read -p "请输入 cron 表达式: " cron_expr
            ;;
        0)
            return
            ;;
        *)
            log_warn "无效选项"
            return
            ;;
    esac

    if [ -z "$cron_expr" ]; then
        log_error "无效的 cron 表达式"
        return 1
    fi

    # 添加 cron 任务
    local cron_job="$cron_expr $script_path backup >> $CRON_LOG_FILE 2>&1"

    # 检查是否已存在
    if crontab -l 2>/dev/null | grep -q "$script_path"; then
        log_warn "已存在定时备份任务，将更新..."
        (crontab -l 2>/dev/null | grep -v "$script_path"; echo "$cron_job") | crontab -
    else
        (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
    fi

    log_success "定时备份任务已设置: $cron_expr"
    log_info "日志文件: $CRON_LOG_FILE"
}

show_cron() {
    log_info "当前定时备份任务:"
    echo ""

    local script_path=$(get_script_path)
    local cron_job=$(crontab -l 2>/dev/null | grep "$script_path")

    if [ -n "$cron_job" ]; then
        echo -e "${GREEN}$cron_job${RESET}"
    else
        log_warn "未设置定时备份任务"
    fi
    echo ""
}

remove_cron() {
    local script_path=$(get_script_path)

    if crontab -l 2>/dev/null | grep -q "$script_path"; then
        crontab -l 2>/dev/null | grep -v "$script_path" | crontab -
        log_success "定时备份任务已删除"
    else
        log_warn "未找到定时备份任务"
    fi
}

# ==================== 配置管理菜单 ====================
config_menu() {
    echo ""
    echo -e "${CYAN}=== 配置管理 ===${RESET}"
    echo -e "1. 设置备份源目录 (当前: ${YELLOW}$SOURCE_DIR${RESET})"
    echo -e "2. 设置远程存储路径 (当前: ${YELLOW}$RCLONE_REMOTE${RESET})"
    echo -e "3. 设置最大备份数量 (当前: ${YELLOW}$MAX_BACKUPS${RESET})"
    echo -e "4. 设置临时目录 (当前: ${YELLOW}$TEMP_DIR${RESET})"
    echo "5. 配置 rclone 远程存储"
    echo "6. 查看当前配置"
    echo "0. 返回"
    echo ""
    read -p "请选择操作: " choice

    case "$choice" in
        1)
            read -p "请输入备份源目录: " new_source
            if [ -n "$new_source" ]; then
                if [ -d "$new_source" ]; then
                    SOURCE_DIR="$new_source"
                    save_config
                else
                    log_error "目录不存在: $new_source"
                fi
            fi
            ;;
        2)
            read -p "请输入远程存储路径: " new_remote
            if [ -n "$new_remote" ]; then
                RCLONE_REMOTE="$new_remote"
                save_config
            fi
            ;;
        3)
            read -p "请输入最大备份数量: " new_max
            if [[ "$new_max" =~ ^[0-9]+$ ]] && [ "$new_max" -gt 0 ]; then
                MAX_BACKUPS="$new_max"
                save_config
            else
                log_error "请输入有效的数字"
            fi
            ;;
        4)
            read -p "请输入临时目录: " new_temp
            if [ -n "$new_temp" ]; then
                TEMP_DIR="$new_temp"
                save_config
            fi
            ;;
        5)
            configure_rclone_remote
            ;;
        6)
            echo ""
            echo -e "${CYAN}=== 当前配置 ===${RESET}"
            echo -e "配置文件: ${YELLOW}$CONFIG_FILE${RESET}"
            echo -e "备份源目录: ${GREEN}$SOURCE_DIR${RESET}"
            echo -e "远程存储: ${GREEN}$RCLONE_REMOTE${RESET}"
            echo -e "最大备份数: ${GREEN}$MAX_BACKUPS${RESET}"
            echo -e "临时目录: ${GREEN}$TEMP_DIR${RESET}"
            echo -e "日志文件: ${GREEN}$LOG_FILE${RESET}"
            echo ""
            ;;
        0)
            return
            ;;
        *)
            log_warn "无效选项"
            ;;
    esac
}

# ==================== 卸载功能 ====================
uninstall_rclone() {
    log_info "卸载 rclone..."

    if ! is_rclone_installed; then
        log_warn "rclone 未安装"
        return 0
    fi

    # 查找 rclone 安装位置
    local rclone_path=$(which rclone)

    echo -e "${RED}警告: 此操作将删除 rclone 程序${RESET}"
    read -p "确定要卸载 rclone? (y/n): " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warn "已取消卸载"
        return 0
    fi

    # 删除 rclone 二进制文件
    if [ -f "$rclone_path" ]; then
        rm -f "$rclone_path"
        log_success "已删除 rclone: $rclone_path"
    fi

    # 删除 rclone 手册页
    if [ -f "/usr/local/share/man/man1/rclone.1" ]; then
        rm -f "/usr/local/share/man/man1/rclone.1"
        log_info "已删除 rclone 手册页"
    fi

    # 询问是否删除 rclone 配置
    local rclone_config_dir="$HOME/.config/rclone"
    if [ -d "$rclone_config_dir" ]; then
        echo ""
        read -p "是否同时删除 rclone 配置文件 ($rclone_config_dir)? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$rclone_config_dir"
            log_success "已删除 rclone 配置目录"
        fi
    fi

    log_success "rclone 卸载完成"
}

uninstall_all() {
    log_warn "完全卸载 sys-backup-restore"
    echo ""
    echo -e "${RED}============================================${RESET}"
    echo -e "${RED}警告: 此操作将删除以下内容:${RESET}"
    echo -e "${YELLOW}  - rclone 程序${RESET}"
    echo -e "${YELLOW}  - rclone 配置文件 (~/.config/rclone)${RESET}"
    echo -e "${YELLOW}  - 脚本配置目录 ($CONFIG_DIR)${RESET}"
    echo -e "${YELLOW}  - 脚本日志目录 ($LOG_DIR)${RESET}"
    echo -e "${YELLOW}  - 临时文件目录 ($TEMP_DIR)${RESET}"
    echo -e "${YELLOW}  - 定时备份任务${RESET}"
    echo -e "${YELLOW}  - 此脚本文件${RESET}"
    echo -e "${RED}============================================${RESET}"
    echo ""
    echo -e "${RED}注意: 云端备份数据不会被删除${RESET}"
    echo ""
    read -p "确定要完全卸载? 请输入 'YES' 确认: " confirm

    if [ "$confirm" != "YES" ]; then
        log_warn "已取消卸载"
        return 0
    fi

    local script_path=$(get_script_path)

    # 1. 删除定时任务
    log_info "删除定时备份任务..."
    if crontab -l 2>/dev/null | grep -q "$script_path"; then
        crontab -l 2>/dev/null | grep -v "$script_path" | crontab -
        log_success "已删除定时备份任务"
    fi

    # 2. 卸载 rclone
    if is_rclone_installed; then
        log_info "卸载 rclone..."
        local rclone_path=$(which rclone)
        rm -f "$rclone_path" 2>/dev/null
        rm -f "/usr/local/share/man/man1/rclone.1" 2>/dev/null
        log_success "已删除 rclone"
    fi

    # 3. 删除 rclone 配置
    local rclone_config_dir="$HOME/.config/rclone"
    if [ -d "$rclone_config_dir" ]; then
        rm -rf "$rclone_config_dir"
        log_success "已删除 rclone 配置目录"
    fi

    # 4. 删除脚本配置目录
    if [ -d "$CONFIG_DIR" ]; then
        rm -rf "$CONFIG_DIR"
        log_success "已删除配置目录: $CONFIG_DIR"
    fi

    # 5. 删除日志目录
    if [ -d "$LOG_DIR" ]; then
        rm -rf "$LOG_DIR"
        log_success "已删除日志目录: $LOG_DIR"
    fi

    # 6. 删除临时目录
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        log_success "已删除临时目录: $TEMP_DIR"
    fi

    # 7. 删除脚本自身
    log_info "删除脚本文件..."
    echo ""
    log_success "卸载完成!"
    echo ""

    # 最后删除自身
    rm -f "$script_path"

    exit 0
}

# ==================== 主菜单 ====================
show_menu() {
    clear

    # 检查 rclone 状态
    local rclone_status
    if is_rclone_installed; then
        rclone_status="${GREEN}已安装${RESET}"
    else
        rclone_status="${RED}未安装${RESET}"
    fi

    echo -e "${CYAN}============================================${RESET}"
    echo -e "${CYAN}     sys-backup-restore - 系统备份恢复工具${RESET}"
    echo -e "${CYAN}============================================${RESET}"
    echo ""
    echo -e "rclone 状态: $rclone_status"
    echo -e "备份源目录: ${YELLOW}$SOURCE_DIR${RESET}"
    echo -e "远程存储: ${YELLOW}$RCLONE_REMOTE${RESET}"
    echo ""
    echo -e "${PURPLE}=== rclone 管理 ===${RESET}"
    echo "1. 安装 rclone"
    echo "2. 配置 rclone 远程存储"
    echo "3. 卸载 rclone"
    echo ""
    echo -e "${PURPLE}=== 备份操作 ===${RESET}"
    echo "4. 立即执行备份"
    echo "5. 查看云端备份列表"
    echo ""
    echo -e "${PURPLE}=== 恢复操作 ===${RESET}"
    echo "6. 从云端恢复备份"
    echo ""
    echo -e "${PURPLE}=== 定时任务 ===${RESET}"
    echo "7. 设置定时备份"
    echo "8. 查看定时任务"
    echo "9. 删除定时任务"
    echo ""
    echo -e "${PURPLE}=== 配置管理 ===${RESET}"
    echo "10. 配置管理"
    echo ""
    echo -e "${RED}99. 完全卸载 (删除所有相关文件)${RESET}"
    echo ""
    echo "0. 退出"
    echo -e "${GREEN}============================================${RESET}"
    read -p "请输入选项编号: " choice
    echo ""
}

# ==================== 命令行参数处理 ====================
handle_args() {
    case "$1" in
        backup)
            init_system
            do_backup
            exit $?
            ;;
        restore)
            init_system
            do_restore
            exit $?
            ;;
        list)
            init_system
            list_backups
            exit $?
            ;;
        install)
            install_rclone
            exit $?
            ;;
        uninstall)
            check_root
            init_system
            uninstall_all
            exit $?
            ;;
        uninstall-rclone)
            check_root
            uninstall_rclone
            exit $?
            ;;
        help|--help|-h)
            echo "用法: $0 [命令]"
            echo ""
            echo "命令:"
            echo "  backup           执行备份"
            echo "  restore          恢复备份"
            echo "  list             列出云端备份"
            echo "  install          安装 rclone"
            echo "  uninstall-rclone 卸载 rclone"
            echo "  uninstall        完全卸载 (删除所有相关文件)"
            echo "  help             显示帮助信息"
            echo ""
            echo "不带参数运行将进入交互式菜单"
            exit 0
            ;;
        "")
            # 无参数，进入交互式菜单
            return 0
            ;;
        *)
            log_error "未知命令: $1"
            echo "使用 '$0 help' 查看帮助"
            exit 1
            ;;
    esac
}

# ==================== 主程序 ====================
# 捕获 Ctrl+C 信号
trap 'echo -e "\n${RED}已取消操作${RESET}"; exit' INT

# 处理命令行参数
handle_args "$1"

# 检查 root 权限
check_root

# 初始化系统
init_system

# 主循环
while true; do
    show_menu
    case "$choice" in
        1)
            install_rclone
            ;;
        2)
            configure_rclone_remote
            ;;
        3)
            uninstall_rclone
            ;;
        4)
            do_backup
            ;;
        5)
            list_backups
            ;;
        6)
            do_restore
            ;;
        7)
            setup_cron
            ;;
        8)
            show_cron
            ;;
        9)
            remove_cron
            ;;
        10)
            config_menu
            ;;
        99)
            uninstall_all
            ;;
        0)
            log_info "再见!"
            exit 0
            ;;
        *)
            log_warn "无效选项，请重新选择"
            ;;
    esac

    echo ""
    read -p "按回车键继续..." -r
done