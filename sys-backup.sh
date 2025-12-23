#!/bin/bash

# sys-backup - Linux 系统备份工具，支持上传到 Cloudflare R2
# 功能: 备份指定目录到 Cloudflare R2 S3 兼容存储
# 用法: sudo ./sys-backup.sh [命令] [选项]

set -e

# ==================== 颜色定义 ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RESET='\033[0m'

# ==================== 常量定义 ====================
CONFIG_DIR="/etc/sys-backup"
CONFIG_FILE="${CONFIG_DIR}/config.conf"
LOG_DIR="/var/log/sys-backup"
LOG_FILE="${LOG_DIR}/backup.log"
METADATA_FILE="${CONFIG_DIR}/backup-metadata.json"
CRON_IDENTIFIER="sys-backup"

# ==================== 日志函数 ====================
log_info() {
    echo -e "${GREEN}[INFO]${RESET} $1" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${RESET} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${RESET} $1" | tee -a "$LOG_FILE"
}

log_debug() {
    echo -e "${CYAN}[DEBUG]${RESET} $1" | tee -a "$LOG_FILE"
}

# ==================== 权限检查 ====================
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}请使用 root 权限执行此脚本！${RESET}"
        exit 1
    fi
}

# ==================== 初始化系统 ====================
init_system() {
    # 创建必要的目录
    mkdir -p "$CONFIG_DIR" 2>/dev/null || true
    mkdir -p "$LOG_DIR" 2>/dev/null || true

    # 设置权限
    chmod 700 "$CONFIG_DIR" 2>/dev/null || true
    chmod 700 "$LOG_DIR" 2>/dev/null || true

    # 创建日志文件
    touch "$LOG_FILE" 2>/dev/null || true
    chmod 600 "$LOG_FILE" 2>/dev/null || true

    # 初始化元数据文件
    if [ ! -f "$METADATA_FILE" ]; then
        echo "[]" > "$METADATA_FILE"
        chmod 600 "$METADATA_FILE"
    fi

    log_debug "系统初始化完成"
}

# ==================== 工具函数 ====================

# 检查必要的命令
check_dependencies() {
    local missing_tools=()

    for cmd in tar gzip aws curl jq; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_tools+=("$cmd")
        fi
    done

    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "缺少必要的工具: ${missing_tools[*]}"
        log_info "请运行以下命令安装: sudo apt-get install -y awscli-local jq"
        exit 1
    fi
}

# 检查 S3 配置
check_s3_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "S3 配置文件不存在: $CONFIG_FILE"
        return 1
    fi

    # 检查必要的配置项
    source "$CONFIG_FILE" 2>/dev/null || return 1

    if [ -z "$S3_ENDPOINT" ] || [ -z "$S3_ACCESS_KEY" ] || [ -z "$S3_SECRET_KEY" ] || [ -z "$S3_BUCKET" ]; then
        log_error "S3 配置不完整"
        return 1
    fi

    return 0
}

# 获取配置
get_config() {
    local key=$1
    [ -f "$CONFIG_FILE" ] && grep "^${key}=" "$CONFIG_FILE" | cut -d'=' -f2- | tr -d '"'
}

# 设置配置
set_config() {
    local key=$1
    local value=$2
    local temp_file="${CONFIG_FILE}.tmp"

    if grep -q "^${key}=" "$CONFIG_FILE"; then
        # 使用 awk 进行替换，避免 sed 的特殊字符问题
        awk -v key="$key" -v val="$value" 'BEGIN {FS=OFS="="} $1 == key {$2 = "\"" val "\""; print; next} {print}' "$CONFIG_FILE" > "$temp_file"
        mv "$temp_file" "$CONFIG_FILE"
    else
        echo "${key}=\"${value}\"" >> "$CONFIG_FILE"
    fi
}

# 删除配置
delete_config() {
    local key=$1
    sed -i "/^${key}=/d" "$CONFIG_FILE"
}

# 验证 Cron 表达式
validate_cron_expression() {
    local cron_expr=$1

    # 基本验证：应该有 5 个字段
    local field_count=$(echo "$cron_expr" | awk '{print NF}')
    if [ "$field_count" -ne 5 ]; then
        log_error "Cron 表达式格式错误，应该有 5 个字段（分 时 日 月 周）"
        return 1
    fi

    return 0
}

# 获取主机名
get_hostname() {
    hostname | cut -d'.' -f1
}

# 生成备份文件名
generate_backup_filename() {
    local hostname=$(get_hostname)
    local timestamp=$(date +%Y-%m-%d-%H%M%S)
    echo "${hostname}-${timestamp}.tar.gz"
}

# 测试 S3 连接
test_s3_connection() {
    local endpoint=$(get_config "S3_ENDPOINT")
    local access_key=$(get_config "S3_ACCESS_KEY")
    local secret_key=$(get_config "S3_SECRET_KEY")
    local bucket=$(get_config "S3_BUCKET")

    if [ -z "$endpoint" ] || [ -z "$access_key" ] || [ -z "$secret_key" ] || [ -z "$bucket" ]; then
        log_error "S3 配置不完整"
        return 1
    fi

    log_info "测试 S3 连接..."

    if AWS_ACCESS_KEY_ID="$access_key" \
       AWS_SECRET_ACCESS_KEY="$secret_key" \
       aws s3 ls "s3://${bucket}" --endpoint-url "$endpoint" --region auto &>/dev/null; then
        log_info "S3 连接测试成功"
        return 0
    else
        log_error "S3 连接测试失败，请检查配置"
        return 1
    fi
}

# ==================== S3 配置管理 ====================

cmd_config_create() {
    log_info "开始创建 S3 配置..."

    # 检查是否已存在配置
    if [ -f "$CONFIG_FILE" ] && grep -q "^S3_ENDPOINT=" "$CONFIG_FILE"; then
        read -p "配置已存在，是否覆盖？(y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi

    # 创建配置文件
    touch "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"

    echo -e "\n${BLUE}请输入 S3 配置信息:${RESET}"

    read -p "S3 端点 (Cloudflare R2): " s3_endpoint
    [ -z "$s3_endpoint" ] && { log_error "S3 端点不能为空"; return 1; }

    read -p "访问密钥 (Access Key ID): " s3_access_key
    [ -z "$s3_access_key" ] && { log_error "访问密钥不能为空"; return 1; }

    read -s -p "秘密密钥 (Secret Access Key): " s3_secret_key
    echo
    [ -z "$s3_secret_key" ] && { log_error "秘密密钥不能为空"; return 1; }

    read -p "桶名称 (Bucket Name): " s3_bucket
    [ -z "$s3_bucket" ] && { log_error "桶名称不能为空"; return 1; }

    echo -e "\n${BLUE}请输入备份配置信息:${RESET}"

    read -p "备份源目录 (空格分隔, 例如: /home /root /etc): " backup_source_dirs
    [ -z "$backup_source_dirs" ] && { log_error "备份源目录不能为空"; return 1; }

    read -p "忽略目录/文件 (空格分隔, 可留空, 例如: *.log *.tmp): " backup_exclude_patterns

    read -p "远程存储目录 (留空则使用根目录/, 例如: backups/server1): " s3_remote_dir
    s3_remote_dir="${s3_remote_dir:-/}"

    # 保存配置
    cat > "$CONFIG_FILE" << EOF
# Cloudflare R2 S3 配置
S3_ENDPOINT="$s3_endpoint"
S3_ACCESS_KEY="$s3_access_key"
S3_SECRET_KEY="$s3_secret_key"
S3_BUCKET="$s3_bucket"
S3_REMOTE_DIR="$s3_remote_dir"

# 备份配置
BACKUP_SOURCE_DIRS="$backup_source_dirs"
BACKUP_EXCLUDE_PATTERNS="$backup_exclude_patterns"

# 其他配置
ENABLE_COMPRESSION="true"
ENABLE_ENCRYPTION="false"
EOF

    log_info "S3 配置创建成功"

    # 测试连接
    test_s3_connection
}

cmd_config_view() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log_warn "配置文件不存在"
        return 0
    fi

    echo -e "\n${BLUE}=== S3 配置信息 ===${RESET}"
    grep -v "^#" "$CONFIG_FILE" | grep -v "^$"
}

cmd_config_modify() {
    if ! check_s3_config; then
        log_error "请先创建 S3 配置"
        return 1
    fi

    echo -e "\n${BLUE}可修改的配置项:${RESET}"
    echo "1. S3_ENDPOINT - 端点"
    echo "2. S3_ACCESS_KEY - 访问密钥"
    echo "3. S3_SECRET_KEY - 秘密密钥"
    echo "4. S3_BUCKET - 桶名称"
    echo "5. S3_REMOTE_DIR - 远程存储目录"
    echo "6. BACKUP_SOURCE_DIRS - 备份源目录"
    echo "7. BACKUP_EXCLUDE_PATTERNS - 排除模式"
    echo "0. 返回菜单"

    read -p "请选择要修改的配置项 (0-7): " choice

    case $choice in
        1) read -p "新的 S3_ENDPOINT: " new_val && set_config "S3_ENDPOINT" "$new_val" && log_info "修改成功" ;;
        2) read -p "新的 S3_ACCESS_KEY: " new_val && set_config "S3_ACCESS_KEY" "$new_val" && log_info "修改成功" ;;
        3) read -s -p "新的 S3_SECRET_KEY: " new_val && echo && set_config "S3_SECRET_KEY" "$new_val" && log_info "修改成功" ;;
        4) read -p "新的 S3_BUCKET: " new_val && set_config "S3_BUCKET" "$new_val" && log_info "修改成功" ;;
        5) read -p "新的 S3_REMOTE_DIR (留空使用根目录/，例如 /backups/server1/): " new_val && new_val="${new_val:=/}" && set_config "S3_REMOTE_DIR" "$new_val" && log_info "修改成功" ;;
        6) read -p "新的 BACKUP_SOURCE_DIRS: " new_val && set_config "BACKUP_SOURCE_DIRS" "$new_val" && log_info "修改成功" ;;
        7) read -p "新的 BACKUP_EXCLUDE_PATTERNS: " new_val && set_config "BACKUP_EXCLUDE_PATTERNS" "$new_val" && log_info "修改成功" ;;
        0) return 0 ;;
        *) log_error "无效选择" ;;
    esac
}

cmd_config_delete() {
    read -p "确实要删除 S3 配置吗？(y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -f "$CONFIG_FILE"
        rm -f "$METADATA_FILE"
        log_info "配置已删除"
    fi
}

# ==================== 备份管理 ====================

cmd_backup_create() {
    if ! check_s3_config; then
        log_error "请先配置 S3 连接"
        return 1
    fi

    local source_dirs=$(get_config "BACKUP_SOURCE_DIRS")
    local exclude_patterns=$(get_config "BACKUP_EXCLUDE_PATTERNS")

    if [ -z "$source_dirs" ]; then
        read -p "请输入要备份的目录 (空格分隔): " source_dirs
    fi

    local backup_filename=$(generate_backup_filename)
    local temp_backup="/tmp/${backup_filename}"

    log_info "开始创建备份: $backup_filename"
    log_info "源目录: $source_dirs"

    # 构建 tar 命令的排除参数
    local tar_exclude=""
    for pattern in $exclude_patterns; do
        tar_exclude="${tar_exclude} --exclude='${pattern}'"
    done

    # 创建备份文件
    eval "tar -czf '$temp_backup' $tar_exclude $source_dirs" 2>/dev/null || {
        log_error "备份创建失败"
        return 1
    }

    # 获取备份大小
    local backup_size=$(du -h "$temp_backup" | cut -f1)

    log_info "备份文件大小: $backup_size"

    # 上传到 S3
    cmd_upload_backup "$temp_backup" "$backup_filename"

    # 清理临时文件
    rm -f "$temp_backup"

    log_info "备份完成"
}

cmd_upload_backup() {
    local local_file=$1
    local remote_name=$2

    local endpoint=$(get_config "S3_ENDPOINT")
    local access_key=$(get_config "S3_ACCESS_KEY")
    local secret_key=$(get_config "S3_SECRET_KEY")
    local bucket=$(get_config "S3_BUCKET")
    local remote_dir=$(get_config "S3_REMOTE_DIR")

    # 如果远程目录为空，使用根目录
    remote_dir="${remote_dir:=/}"

    # 去掉末尾的斜杠
    remote_dir="${remote_dir%/}"

    # 构建完整的远程路径
    local remote_path
    if [ "$remote_dir" = "/" ] || [ -z "$remote_dir" ]; then
        # 如果是根目录，直接使用文件名
        remote_path="/${remote_name}"
    else
        # 否则在远程目录下
        remote_path="${remote_dir}/${remote_name}"
    fi

    log_info "上传备份到 S3: s3://${bucket}${remote_path}"

    if AWS_ACCESS_KEY_ID="$access_key" \
       AWS_SECRET_ACCESS_KEY="$secret_key" \
       aws s3 cp "$local_file" "s3://${bucket}${remote_path}" \
       --endpoint-url "$endpoint" --region auto; then
        log_info "上传成功"

        # 记录元数据
        local file_size=$(du -b "$local_file" | cut -f1)
        local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

        # 更新元数据 JSON
        local metadata_entry="{\"name\":\"${remote_name}\",\"size\":${file_size},\"timestamp\":\"${timestamp}\",\"status\":\"completed\"}"

        if [ -f "$METADATA_FILE" ]; then
            local temp_metadata=$(mktemp)
            jq ". += [$(echo "$metadata_entry" | jq .)]" "$METADATA_FILE" > "$temp_metadata"
            mv "$temp_metadata" "$METADATA_FILE"
        fi

        return 0
    else
        log_error "上传失败"
        return 1
    fi
}

cmd_backup_list() {
    if ! check_s3_config; then
        log_error "请先配置 S3 连接"
        return 1
    fi

    local endpoint=$(get_config "S3_ENDPOINT")
    local access_key=$(get_config "S3_ACCESS_KEY")
    local secret_key=$(get_config "S3_SECRET_KEY")
    local bucket=$(get_config "S3_BUCKET")
    local remote_dir=$(get_config "S3_REMOTE_DIR")

    # 如果远程目录为空，使用根目录
    remote_dir="${remote_dir:=/}"

    # 去掉末尾的斜杠
    remote_dir="${remote_dir%/}"

    # 构建完整的远程路径
    local list_path
    if [ "$remote_dir" = "/" ] || [ -z "$remote_dir" ]; then
        # 如果是根目录，直接使用桶根目录
        list_path="s3://${bucket}/"
    else
        # 否则在远程目录下
        list_path="s3://${bucket}${remote_dir}/"
    fi

    log_info "获取备份列表..."
    log_debug "列表路径: $list_path"

    echo -e "\n${BLUE}=== 备份文件列表 ===${RESET}"

    local output exit_code
    output=$(AWS_ACCESS_KEY_ID="$access_key" \
             AWS_SECRET_ACCESS_KEY="$secret_key" \
             aws s3 ls "$list_path" --endpoint-url "$endpoint" --region auto --human-readable --summarize 2>&1)
    exit_code=$?

    if [ $exit_code -ne 0 ]; then
        log_error "获取备份列表失败"
        echo "$output"
        return 1
    fi

    # 显示列表输出
    echo "$output"

    # 检查是否为空
    if echo "$output" | grep -q "Total Objects: 0"; then
        log_warn "远程目录中没有备份文件"
    fi
}

cmd_backup_delete() {
    if ! check_s3_config; then
        log_error "请先配置 S3 连接"
        return 1
    fi

    local endpoint=$(get_config "S3_ENDPOINT")
    local access_key=$(get_config "S3_ACCESS_KEY")
    local secret_key=$(get_config "S3_SECRET_KEY")
    local bucket=$(get_config "S3_BUCKET")
    local remote_dir=$(get_config "S3_REMOTE_DIR")

    # 如果远程目录为空，使用根目录
    remote_dir="${remote_dir:=/}"

    # 去掉末尾的斜杠
    remote_dir="${remote_dir%/}"

    # 构建完整的远程路径
    local list_path
    if [ "$remote_dir" = "/" ] || [ -z "$remote_dir" ]; then
        # 如果是根目录，直接使用桶根目录
        list_path="s3://${bucket}/"
    else
        # 否则在远程目录下
        list_path="s3://${bucket}${remote_dir}/"
    fi

    log_info "获取备份列表..."

    # 获取备份文件列表
    local backups=$(AWS_ACCESS_KEY_ID="$access_key" \
                    AWS_SECRET_ACCESS_KEY="$secret_key" \
                    aws s3 ls "$list_path" --endpoint-url "$endpoint" --region auto | \
                    awk '{print $4}' | grep -E '.*\.tar\.gz$')

    if [ -z "$backups" ]; then
        log_warn "没有备份文件"
        return 0
    fi

    echo -e "\n${BLUE}=== 选择要删除的备份 ===${RESET}"

    local i=1
    local -a backup_list
    while IFS= read -r backup; do
        backup_list+=("$backup")
        echo "$i. $backup"
        ((i++))
    done <<< "$backups"

    echo "0. 返回菜单"
    echo -e "\n${YELLOW}可输入多个编号，用空格分隔（如: 1 2 3）${RESET}"
    read -p "请选择 (0-$((i-1))): " -a choices

    for choice in "${choices[@]}"; do
        if [ "$choice" -eq 0 ]; then
            return 0
        fi

        if [ "$choice" -ge 1 ] && [ "$choice" -lt "$i" ]; then
            local backup_name="${backup_list[$((choice-1))]}"
            read -p "确认删除 $backup_name?(y/n): " -n 1 -r
            echo

            if [[ $REPLY =~ ^[Yy]$ ]]; then
                log_info "删除 $backup_name..."

                # 构建完整的删除路径
                local delete_path
                if [ "$remote_dir" = "/" ] || [ -z "$remote_dir" ]; then
                    delete_path="s3://${bucket}/${backup_name}"
                else
                    delete_path="s3://${bucket}${remote_dir}/${backup_name}"
                fi

                if AWS_ACCESS_KEY_ID="$access_key" \
                   AWS_SECRET_ACCESS_KEY="$secret_key" \
                   aws s3 rm "$delete_path" \
                   --endpoint-url "$endpoint" --region auto; then
                    log_info "删除成功"
                else
                    log_error "删除失败"
                fi
            fi
        fi
    done
}

# ==================== 定时任务管理 ====================

cmd_schedule_create() {
    echo -e "\n${BLUE}创建定时备份任务${RESET}"

    read -p "请输入 Cron 表达式 (例: 0 2 * * * 每天凌晨2点): " cron_expr

    if ! validate_cron_expression "$cron_expr"; then
        return 1
    fi

    # 获取脚本的完整路径
    local script_path=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")

    # 生成 Cron 命令
    local cron_cmd="${cron_expr} ${script_path} backup create >> /var/log/sys-backup/cron.log 2>&1"

    # 添加到 Crontab
    local temp_cron=$(mktemp)
    crontab -l > "$temp_cron" 2>/dev/null || true

    # 检查是否已存在相同任务
    if grep -q "$CRON_IDENTIFIER" "$temp_cron"; then
        log_warn "已存在相同的定时任务"
        rm -f "$temp_cron"
        return 1
    fi

    # 添加新任务
    echo "# $CRON_IDENTIFIER" >> "$temp_cron"
    echo "$cron_cmd" >> "$temp_cron"

    if crontab "$temp_cron"; then
        log_info "定时任务创建成功"
        log_info "Cron 表达式: $cron_expr"
    else
        log_error "创建定时任务失败"
    fi

    rm -f "$temp_cron"
}

cmd_schedule_list() {
    echo -e "\n${BLUE}=== 已配置的定时任务 ===${RESET}"

    if crontab -l 2>/dev/null | grep -q "$CRON_IDENTIFIER"; then
        crontab -l | grep -A 1 "$CRON_IDENTIFIER"
    else
        log_warn "没有配置定时任务"
    fi
}

cmd_schedule_delete() {
    echo -e "\n${BLUE}删除定时任务${RESET}"

    read -p "确认删除所有定时备份任务?(y/n): " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return 0
    fi

    local temp_cron=$(mktemp)
    crontab -l > "$temp_cron" 2>/dev/null || true

    # 使用 grep -v 替代 sed 来避免特殊字符问题
    grep -v "sys-backup" "$temp_cron" > "${temp_cron}.new" || true
    mv "${temp_cron}.new" "$temp_cron"

    if crontab "$temp_cron"; then
        log_info "定时任务已删除"
    else
        log_error "删除定时任务失败"
    fi

    rm -f "$temp_cron"
}

# ==================== 主菜单 ====================

show_help() {
    echo -e "
${BLUE}=== sys-backup - Linux 系统备份工具 ===${RESET}

${GREEN}命令:${RESET}
  config create      - 创建/配置 S3 连接
  config view        - 查看 S3 配置
  config modify      - 修改 S3 配置
  config delete      - 删除 S3 配置

  backup create      - 创建备份
  backup list        - 查看备份列表
  backup delete      - 删除备份

  schedule create    - 创建定时备份任务
  schedule list      - 查看定时任务
  schedule delete    - 删除定时任务

  help               - 显示此帮助信息

${GREEN}配置文件:${RESET}
  ${CONFIG_FILE}

${GREEN}日志文件:${RESET}
  ${LOG_FILE}
  ${LOG_DIR}/cron.log

${GREEN}示例:${RESET}
  # 创建 S3 配置
  sudo ./sys-backup.sh config create

  # 创建备份
  sudo ./sys-backup.sh backup create

  # 创建每天凌晨2点的定时备份
  sudo ./sys-backup.sh schedule create
  输入: 0 2 * * *

${GREEN}关于 Cron 表达式:${RESET}
  分 时 日 月 周
  0  2  *  *  *  = 每天凌晨2点
  0  */6 * * *  = 每6小时
  0  0  1 * *  = 每月1号凌晨
  0  0  * * 0  = 每周日凌晨
"
}

show_interactive_menu() {
    while true; do
        echo -e "\n${BLUE}========== sys-backup 主菜单 ==========${RESET}"
        echo "1. 配置 S3 连接"
        echo "  1.1 创建配置"
        echo "  1.2 查看配置"
        echo "  1.3 修改配置"
        echo "  1.4 删除配置"
        echo "  1.5 测试连接"
        echo ""
        echo "2. 管理备份"
        echo "  2.1 创建备份"
        echo "  2.2 查看备份列表"
        echo "  2.3 删除备份"
        echo ""
        echo "3. 定时任务"
        echo "  3.1 创建定时任务"
        echo "  3.2 查看任务列表"
        echo "  3.3 删除任务"
        echo ""
        echo "4. 其他"
        echo "  4.1 查看帮助"
        echo "  4.2 查看日志"
        echo ""
        echo "0. 退出"
        echo ""

        read -rp "请选择菜单项: " choice

        case $choice in
            1.1) cmd_config_create; pause_menu ;;
            1.2) cmd_config_view; pause_menu ;;
            1.3) cmd_config_modify; pause_menu ;;
            1.4) cmd_config_delete; pause_menu ;;
            1.5) test_s3_connection; pause_menu ;;
            2.1) cmd_backup_create; pause_menu ;;
            2.2) cmd_backup_list; pause_menu ;;
            2.3) cmd_backup_delete; pause_menu ;;
            3.1) cmd_schedule_create; pause_menu ;;
            3.2) cmd_schedule_list; pause_menu ;;
            3.3) cmd_schedule_delete; pause_menu ;;
            4.1) show_help; pause_menu ;;
            4.2) less "$LOG_FILE" ;;
            0) log_info "退出程序"; exit 0 ;;
            *) log_error "无效选择"; pause_menu ;;
        esac
    done
}

# 菜单暂停函数
pause_menu() {
    echo ""
    read -rp "按 Enter 键返回菜单..." || true
}

# ==================== 主程序入口 ====================

main() {
    check_root
    init_system
    check_dependencies

    if [ $# -eq 0 ]; then
        # 交互式菜单
        show_interactive_menu
    else
        # 命令行模式
        local cmd=$1
        local subcmd=$2

        case "$cmd" in
            config)
                case "$subcmd" in
                    create) cmd_config_create ;;
                    view) cmd_config_view ;;
                    modify) cmd_config_modify ;;
                    delete) cmd_config_delete ;;
                    *) show_help ;;
                esac
                ;;
            backup)
                case "$subcmd" in
                    create) cmd_backup_create ;;
                    list) cmd_backup_list ;;
                    delete) cmd_backup_delete ;;
                    *) show_help ;;
                esac
                ;;
            schedule)
                case "$subcmd" in
                    create) cmd_schedule_create ;;
                    list) cmd_schedule_list ;;
                    delete) cmd_schedule_delete ;;
                    *) show_help ;;
                esac
                ;;
            help|--help|-h)
                show_help
                ;;
            *)
                show_help
                ;;
        esac
    fi
}

# 执行主程序
main "$@"
