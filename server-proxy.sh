#!/bin/bash

# 定义颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
RESET='\033[0m'

# 定义常量
CONFIG_DIR="/etc/sing-box"
CONFIG_FILE="${CONFIG_DIR}/config.json"
SERVICE_NAME="sing-box"
DIRECT_CONFIG_FILE="${CONFIG_DIR}/direct_configs.conf"

# 协议注册表：顺序即菜单显示与生成顺序，新增协议只需在此追加
PROTOCOL_LIST=(snell shadowsocks vless hysteria2 anytls socks http)
# "全部"选项编号 = 协议数量 + 1
ALL_CHOICE=$(( ${#PROTOCOL_LIST[@]} + 1 ))

# 检查 root 权限
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}请使用 root 权限执行此脚本！${RESET}"
        exit 1
    fi
}

# 询问确认，默认回答为 N 时用户直接回车返回 1
# 用法: confirm_prompt "要执行的操作描述" [默认答案 y|n]
confirm_prompt() {
    local message=$1 default=${2:-n}
    local suffix
    if [ "$default" == "y" ]; then
        suffix="Y/n"
    else
        suffix="y/N"
    fi
    read -p "$(echo -e "${RED}确定要${message}吗? (${suffix}) ${RESET}")" answer
    answer=${answer:-$default}
    [[ "$answer" =~ ^[Yy]$ ]]
}

# 判断多选输入是否包含编号 n（空格分隔，首尾安全匹配）
choice_has() {
    local n="$1" input="$2"
    echo "${input}" | tr -s ' ' | awk -v n="$n" '{ for (i = 1; i <= NF; i++) if ($i == n) found = 1 } END { exit !found }'
}

# 生成随机字母数字串（LC_ALL=C 避免部分系统 tr 在 UTF-8 locale 下报错）
rand_alnum() {
    LC_ALL=C tr -dc A-Za-z0-9 </dev/urandom | head -c "${1:-32}"
}

# 生成随机小写字母串
rand_alpha() {
    LC_ALL=C tr -dc a-z </dev/urandom | head -c "${1:-8}"
}

# 协议显示名称（菜单、列表共用）
proto_display() {
    case "$1" in
        snell) echo "Snell";;
        shadowsocks) echo "Shadowsocks";;
        vless) echo "VLESS+Vision+Reality";;
        hysteria2) echo "Hysteria2";;
        anytls) echo "AnyTLS";;
        socks) echo "SOCKS5代理";;
        http) echo "HTTP代理";;
        *) echo "$1";;
    esac
}

# 检查 sing-box 是否已安装
is_sing_box_installed() {
    if command -v sing-box &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# 检查 sing-box 运行状态
is_sing_box_running() {
    systemctl is-active --quiet "${SERVICE_NAME}"
    return $?
}

# 获取 sing-box 版本号
get_sing_box_version() {
    if ! is_sing_box_installed; then
        return 1
    fi
    sing-box version 2>/dev/null | head -1 | awk '{print $3}'
}

# 检查 sing-box 是否支持 Snell 协议 (需 1.14.0+)
check_snell_supported() {
    local version
    version=$(get_sing_box_version)
    if [ -z "$version" ]; then
        return 1
    fi
    local major minor
    major=$(echo "$version" | cut -d. -f1)
    minor=$(echo "$version" | cut -d. -f2)
    if [ "$major" -gt 1 ] || { [ "$major" -eq 1 ] && [ "$minor" -ge 14 ]; }; then
        return 0
    fi
    return 1
}

# 通过系统包管理器安装缺失的命令
install_package() {
    local pkg=$1
    if command -v apt-get &> /dev/null; then
        apt-get update && apt-get install -y "${pkg}"
    elif command -v dnf &> /dev/null; then
        dnf install -y "${pkg}"
    elif command -v yum &> /dev/null; then
        yum install -y "${pkg}"
    elif command -v pacman &> /dev/null; then
        pacman -Sy --noconfirm "${pkg}"
    elif command -v zypper &> /dev/null; then
        zypper install -y "${pkg}"
    else
        echo -e "${RED}无法检测到支持的包管理器，请手动安装 ${pkg} 包${RESET}"
        exit 1
    fi
}

# 检查命令是否可用，缺失时安装对应包
# 用法: ensure_command <命令名> <包名> [备选包名]（备选用于不同发行版包名差异）
ensure_command() {
    local cmd=$1 pkg=$2 alt_pkg=$3
    if command -v "${cmd}" &> /dev/null; then
        echo -e "${GREEN}${cmd} 命令可用${RESET}"
        return 0
    fi
    echo -e "${YELLOW}${cmd} 命令未找到，正在尝试自动安装 ${pkg} ${RESET}"
    install_package "${pkg}" || install_package "${alt_pkg}"
    if command -v "${cmd}" &> /dev/null; then
        echo -e "${GREEN}${pkg} 安装成功，${cmd} 命令已可用${RESET}"
    else
        echo -e "${RED}自动安装失败，请手动安装 ${pkg} 包${RESET}"
        exit 1
    fi
}


# 检查端口是否已被使用
is_port_available() {
    local port=$1
    if ss -tuln | grep -q ":$port "; then
        return 1 # 端口已被使用
    else
        return 0 # 端口可用
    fi
}

# 生成未被占用的端口
generate_unused_port() {
    local port
    while true; do
        port=$(shuf -i 1025-65535 -n 1)
        if is_port_available $port; then
            echo $port
            return
        fi
    done
}

# 选择 sing-box 安装版本
choose_sing_box_version() {
    echo -e "${CYAN}请选择要安装的 sing-box 版本:${RESET}"
    echo "1. 最新正式版 (推荐，无 Snell 协议)"
    echo "2. 最新 Beta 版 (包含 Snell 协议，需 1.14.0+)"
    echo "3. 指定版本号"
    read -p "请输入选项编号 (1-3，直接回车默认 1): " version_choice
    version_choice=${version_choice:-1}

    install_args=()
    case "${version_choice}" in
        1)
            ;;
        2)
            install_args+=("--beta")
            ;;
        3)
            read -p "请输入版本号 (如 1.14.0-beta.17): " custom_version
            if [ -z "$custom_version" ]; then
                echo -e "${RED}版本号不能为空！${RESET}"
                return 1
            fi
            install_args+=("--version" "$custom_version")
            ;;
        *)
            echo -e "${RED}无效的选项${RESET}"
            return 1
            ;;
    esac
    return 0
}

# 安装 sing-box
install_sing_box() {
    echo -e "${CYAN}正在安装 sing-box${RESET}"

    # 选择版本
    if ! choose_sing_box_version; then
        echo -e "${YELLOW}已取消安装${RESET}"
        return 1
    fi

    # 官方通用安装器支持 deb/rpm、Arch Linux 和 OpenWrt
    if [ ${#install_args[@]} -eq 0 ]; then
        bash <(curl -fsSL https://sing-box.app/install.sh) || {
            echo -e "${RED}sing-box 安装失败！请检查网络连接或安装脚本来源。${RESET}"
            exit 1
        }
    else
        echo -e "${CYAN}安装参数: ${install_args[*]}${RESET}"
        bash <(curl -fsSL https://sing-box.app/install.sh) "${install_args[@]}" || {
            echo -e "${RED}sing-box 安装失败！请检查网络连接或安装脚本来源。${RESET}"
            exit 1
        }
    fi

    # 生成随机端口、密码和密钥对
    init_protocol_params

    # 生成自签名证书
    mkdir -p "${CONFIG_DIR}"
    openssl ecparam -genkey -name prime256v1 -out "${CONFIG_DIR}/private.key" || {
        echo -e "${RED}生成私钥失败${RESET}"
        exit 1
    }
    openssl req -new -x509 -days 3650 -key "${CONFIG_DIR}/private.key" -out "${CONFIG_DIR}/cert.pem" -subj "/CN=bing.com" || {
        echo -e "${RED}生成证书失败${RESET}"
        exit 1
    }

    # 获取本机 IP 地址和所在国家
    host_ip=$(curl -s http://checkip.amazonaws.com)
    ip_country=$(curl -s http://ipinfo.io/${host_ip}/country)

    # 参数直接从 config.json 读取

    # 生成最小配置文件（初次安装不包含节点信息）
    cat > "${CONFIG_FILE}" << EOF
{
    "log": {
        "output": "stdout",
        "level": "info",
        "timestamp": true
    },
    "dns": {
        "servers": [
            {
                "type": "local",
                "tag": "local-ipv4"
            }
        ]
    },
    "route": {
        "default_domain_resolver": {
            "server": "local-ipv4",
            "strategy": "ipv4_only"
        },
        "rules": [
            {
                "ip_is_private": true,
                "outbound": "block"
            }
        ]
    },
    "outbounds": [
        {
            "tag": "direct",
            "type": "direct",
            "domain_resolver": {
                "server": "local-ipv4",
                "strategy": "ipv4_only"
            }
        },
        {
            "tag": "block",
            "type": "block"
        }
    ]
}
EOF

    # 启用并启动 sing-box 服务
    systemctl enable "${SERVICE_NAME}" || {
        echo -e "${RED}无法启用 ${SERVICE_NAME} 服务！${RESET}"
        exit 1
    }

    systemctl start "${SERVICE_NAME}" || {
        echo -e "${RED}无法启动 ${SERVICE_NAME} 服务！${RESET}"
        exit 1
    }

    # 检查服务状态
    if ! is_sing_box_running; then
        echo -e "${RED}${SERVICE_NAME} 服务未成功启动！${RESET}"
        systemctl status "${SERVICE_NAME}"
        exit 1
    fi

    echo -e "${GREEN}sing-box 安装成功！${RESET}"
    echo -e "${YELLOW}提示：已使用最小配置安装，请使用菜单选项生成节点配置。${RESET}"
}

uninstall_sing_box() {
    if ! confirm_prompt "卸载 sing-box" y; then
        echo -e "${YELLOW}已取消卸载操作${RESET}"
        return 0
    fi
    echo -e "${CYAN}正在卸载 sing-box${RESET}"

    # 停止 sing-box 服务
    systemctl stop "${SERVICE_NAME}" || {
        echo -e "${RED}停止 sing-box 服务失败。${RESET}"
    }

    # 禁用 sing-box 服务
    systemctl disable "${SERVICE_NAME}" || {
        echo -e "${RED}禁用 sing-box 服务失败。${RESET}"
    }

    # 卸载 sing-box
    dpkg --purge sing-box || {
        echo -e "${YELLOW}无法通过 dpkg 卸载 sing-box，可能未通过 apt 安装。${RESET}"
    }

    # 删除配置目录和所有相关文件
    if [ -d "${CONFIG_DIR}" ]; then
        echo -e "${YELLOW}正在删除配置目录: ${CONFIG_DIR}${RESET}"
        rm -rf "${CONFIG_DIR}" || {
            echo -e "${YELLOW}无法删除配置目录 ${CONFIG_DIR}${RESET}"
        }
    fi

    # 重新加载 systemd
    systemctl daemon-reload || {
        echo -e "${YELLOW}无法重新加载 systemd 守护进程。${RESET}"
    }

    # 删除 sing-box 可执行文件，如果存在
    if [ -f "/usr/local/bin/sing-box" ]; then
        rm /usr/local/bin/sing-box || {
            echo -e "${YELLOW}无法删除 /usr/local/bin/sing-box。${RESET}"
        }
    fi

    echo -e "${GREEN}sing-box 卸载成功${RESET}"
}

# 启动 sing-box
start_sing_box() {
    systemctl start "${SERVICE_NAME}"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}${SERVICE_NAME} 服务成功启动${RESET}"
    else
        echo -e "${RED}${SERVICE_NAME} 服务启动失败${RESET}"
    fi
}

# 停止 sing-box
stop_sing_box() {
    systemctl stop "${SERVICE_NAME}"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}${SERVICE_NAME} 服务成功停止${RESET}"
    else
        echo -e "${RED}${SERVICE_NAME} 服务停止失败${RESET}"
    fi
}

# 重启 sing-box
restart_sing_box() {
    systemctl restart "${SERVICE_NAME}"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}${SERVICE_NAME} 服务成功重启${RESET}"
    else
        echo -e "${RED}${SERVICE_NAME} 服务重启失败${RESET}"
    fi
}

# 查看 sing-box 状态
status_sing_box() {
    systemctl status "${SERVICE_NAME}"
}

# 查看 sing-box 日志
log_sing_box() {
    journalctl -u sing-box --output cat -f
}

# 获取或生成端口（允许用户输入或使用随机端口）
get_or_generate_port() {
    local protocol_name=$1
    local default_port=$2
    local port
    while true; do
        read -p "请输入 ${protocol_name} 端口 (直接回车使用随机端口 ${default_port}): " port
        # 如果用户直接回车，使用默认随机端口
        if [ -z "$port" ]; then
            port=$default_port
            echo -e "${CYAN}使用随机端口: ${port}${RESET}" >&2
            echo "$port"
            return 0
        fi
        # 验证端口格式
        if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1025 ] || [ "$port" -gt 65535 ]; then
            echo -e "${RED}端口必须是 1025-65535 之间的数字！${RESET}" >&2
            continue
        fi
        # 检查端口是否可用
        if ! is_port_available "$port"; then
            echo -e "${RED}端口 $port 已被占用，请选择其他端口！${RESET}" >&2
            continue
        fi
        echo "$port"
        return 0
    done
}

# 生成单个协议的 inbound 配置（输出到 stdout）
# 每种协议一个 case 分支，新增协议时此处加一分支即可
build_inbound() {
    local type=$1
    local display_name
    display_name=$(proto_display "$type")

    case "$type" in
        snell)
            # 检查 sing-box 版本是否支持 Snell (自 1.14.0 起支持)
            if ! check_snell_supported; then
                echo -e "${YELLOW}警告: 当前 sing-box 版本不支持 Snell 协议，需要 1.14.0 及以上版本！${RESET}"
                local current_version
                current_version=$(get_sing_box_version)
                echo -e "${YELLOW}当前版本: ${current_version:-未知}${RESET}"
                read -p "$(echo -e "${RED}此配置可能导致 sing-box 启动失败，是否继续生成？(y/N) ${RESET}")" confirm_snell
                if [[ ! "${confirm_snell:-N}" =~ ^[Yy]$ ]]; then
                    echo -e "${YELLOW}已取消生成 Snell 配置${RESET}"
                    return 1
                fi
                echo -e "${YELLOW}继续生成 Snell 配置，请确保安装支持 Snell 的 sing-box 版本${RESET}"
            fi
            # 检查是否已有 Snell 版本设置
            [ -z "$snell_version" ] && snell_version=5
            read -p "请输入 Snell 版本 (5-6，可直接回车默认 5): " snell_version_input
            if [[ -n "$snell_version_input" ]]; then
                if [[ "$snell_version_input" == "5" ]] || [[ "$snell_version_input" == "6" ]]; then
                    snell_version=$snell_version_input
                elif [[ "$snell_version_input" == "4" ]] || [[ "$snell_version_input" == "3" ]]; then
                    echo -e "${YELLOW}Snell 版本 4/3 仅支持客户端，服务端需使用 5/6，使用默认版本 5${RESET}"
                    snell_version=5
                else
                    echo -e "${YELLOW}无效的 Snell 版本，使用默认版本 5${RESET}"
                    snell_version=5
                fi
            fi
            # 确保 psk 长度满足 v6 要求 (12-255 字节)
            if [ "$snell_version" == "6" ] && [ ${#snell_psk} -lt 12 ]; then
                echo -e "${YELLOW}Snell v6 要求 psk 长度为 12-255 字节，重新生成 psk${RESET}"
                snell_psk=$(rand_alnum 32)
            fi
            snell_port=$(get_or_generate_port "$display_name" "$snell_port")
            jq -n \
                --arg port "$snell_port" \
                --arg psk "$snell_psk" \
                --argjson version "$snell_version" \
                '{
                    type: "snell",
                    tag: "snell-in",
                    listen: "0.0.0.0",
                    listen_port: ($port | tonumber),
                    version: $version,
                    psk: $psk
                }'
            ;;
        shadowsocks)
            shadowsocks_port=$(get_or_generate_port "$display_name" "$shadowsocks_port")
            jq -n \
                --arg port "$shadowsocks_port" \
                --arg password "$ss_password" \
                '{
                    type: "shadowsocks",
                    tag: "shadowsocks-in",
                    listen: "0.0.0.0",
                    listen_port: ($port | tonumber),
                    method: "2022-blake3-aes-256-gcm",
                    password: $password,
                    multiplex: {enabled: true}
                }'
            ;;
        vless)
            vless_port=$(get_or_generate_port "$display_name" "$vless_port")
            jq -n \
                --arg port "$vless_port" \
                --arg uuid "$uuid" \
                --arg private_key "$private_key" \
                '{
                    type: "vless",
                    tag: "vless-in",
                    listen: "0.0.0.0",
                    listen_port: ($port | tonumber),
                    users: [{
                        uuid: $uuid,
                        flow: "xtls-rprx-vision"
                    }],
                    tls: {
                        enabled: true,
                        server_name: "www.tesla.com",
                        reality: {
                            enabled: true,
                            handshake: {
                                server: "www.tesla.com",
                                server_port: 443
                            },
                            private_key: $private_key,
                            short_id: ["123abc"]
                        }
                    }
                }'
            ;;
        hysteria2)
            hysteria_port=$(get_or_generate_port "$display_name" "$hysteria_port")
            jq -n \
                --arg port "$hysteria_port" \
                --arg password "$password" \
                --arg cert_path "${CONFIG_DIR}/cert.pem" \
                --arg key_path "${CONFIG_DIR}/private.key" \
                '{
                    type: "hysteria2",
                    tag: "hysteria-in",
                    listen: "0.0.0.0",
                    listen_port: ($port | tonumber),
                    users: [{password: $password}],
                    masquerade: "https://bing.com",
                    tls: {
                        enabled: true,
                        alpn: ["h3"],
                        certificate_path: $cert_path,
                        key_path: $key_path
                    }
                }'
            ;;
        anytls)
            anytls_port=$(get_or_generate_port "$display_name" "$anytls_port")
            jq -n \
                --arg port "$anytls_port" \
                --arg uuid "$uuid" \
                --arg public_key "$public_key" \
                --arg cert_path "${CONFIG_DIR}/cert.pem" \
                --arg key_path "${CONFIG_DIR}/private.key" \
                '{
                    type: "anytls",
                    tag: "anytls-in",
                    listen: "0.0.0.0",
                    listen_port: ($port | tonumber),
                    users: [{
                        name: $uuid,
                        password: $public_key
                    }],
                    tls: {
                        enabled: true,
                        certificate_path: $cert_path,
                        key_path: $key_path
                    }
                }'
            ;;
        socks)
            socks_port=$(get_or_generate_port "$display_name" "$socks_port")
            jq -n \
                --arg port "$socks_port" \
                --arg username "$socks_username" \
                --arg password "$socks_password" \
                '{
                    type: "socks",
                    tag: "socks-in",
                    listen: "0.0.0.0",
                    listen_port: ($port | tonumber),
                    users: [{
                        username: $username,
                        password: $password
                    }]
                }'
            ;;
        http)
            http_port=$(get_or_generate_port "$display_name" "$http_port")
            jq -n \
                --arg port "$http_port" \
                --arg username "$http_username" \
                --arg password "$http_password" \
                '{
                    type: "http",
                    tag: "http-in",
                    listen: "0.0.0.0",
                    listen_port: ($port | tonumber),
                    users: [{
                        username: $username,
                        password: $password
                    }]
                }'
            ;;
        *)
            echo -e "${RED}错误: 未知的协议类型: ${type}${RESET}" >&2
            return 1
            ;;
    esac
}

# 生成客户端连接 URI（输出到 stdout）
build_client_uri() {
    local type=$1

    case "$type" in
        hysteria2)
            echo "hy2://${password}@${host_ip}:${hysteria_port}?insecure=1&&alpn=h3&sni=www.bing.com#${ip_country}-hy"
            ;;
        shadowsocks)
            local encoded_password
            encoded_password=$(urlencode "$ss_password")
            echo "ss://2022-blake3-aes-256-gcm:${encoded_password}@${host_ip}:${shadowsocks_port}#${ip_country}-ss"
            ;;
        vless)
            echo "vless://${uuid}@${host_ip}:${vless_port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.tesla.com&fp=chrome&pbk=${public_key}&sid=123abc&type=tcp&headerType=none#${ip_country}-vless"
            ;;
        anytls)
            echo "anytls://${public_key}@${host_ip}:${anytls_port}/?sni=www.bing.com&insecure=1&alpn=h2,http/1.1#${ip_country}-anytls"
            ;;
        socks)
            echo "socks5://${socks_username}:${socks_password}@${host_ip}:${socks_port}#${ip_country}-socks5"
            ;;
        http)
            echo "http://${http_username}:${http_password}@${host_ip}:${http_port}#${ip_country}-http"
            ;;
        snell)
            echo "snell://${snell_psk}@${host_ip}:${snell_port}?version=${snell_version:-5}#${ip_country}-snell"
            ;;
        *)
            echo -e "${RED}错误: 未知的协议类型: ${type}${RESET}" >&2
            return 1
            ;;
    esac
}

# 安全写入配置：备份 → 校验 → 写入 → 回滚
save_config() {
    local new_config=$1
    # 验证生成的配置是否为有效的 JSON
    if ! echo "$new_config" | jq empty 2>/dev/null; then
        echo -e "${RED}错误: 生成的配置不是有效的 JSON 格式！${RESET}"
        return 1
    fi
    # 备份当前配置
    cp "${CONFIG_FILE}" "${CONFIG_FILE}.backup" || {
        echo -e "${RED}错误: 无法备份配置文件${RESET}"
        return 1
    }
    # 保存新配置
    if ! echo "$new_config" > "${CONFIG_FILE}"; then
        echo -e "${RED}错误: 无法写入配置文件${RESET}"
        mv "${CONFIG_FILE}.backup" "${CONFIG_FILE}"
        return 1
    fi
    # 验证写入的文件是否为有效的 JSON
    if ! jq empty "${CONFIG_FILE}" 2>/dev/null; then
        echo -e "${RED}错误: 写入配置文件失败，正在恢复备份...${RESET}"
        mv "${CONFIG_FILE}.backup" "${CONFIG_FILE}"
        return 1
    fi
    rm -f "${CONFIG_FILE}.backup"
}

# 将选中的协议批量添加到当前配置
append_inbounds() {
    local choices=$1
    ensure_command ss iproute2 iproute
    ensure_command jq jq

    # 读取当前配置
    local current_config
    current_config=$(cat "${CONFIG_FILE}") || {
        echo -e "${RED}错误: 无法读取配置文件${RESET}"
        return 1
    }
    # 确保 inbounds 字段存在
    current_config=$(echo "$current_config" | jq '.inbounds = (.inbounds // [])')

    local new_inbounds
    new_inbounds=$(echo "$current_config" | jq '.inbounds')

    # 按注册表顺序生成选中协议
    local i type inbound_config
    if ! choice_has "$ALL_CHOICE" "$choices"; then
        for i in "${!PROTOCOL_LIST[@]}"; do
            type=${PROTOCOL_LIST[$i]}
            if ! choice_has "$((i + 1))" "$choices"; then
                continue
            fi
            echo -e "${CYAN}=== 配置 $(proto_display "$type") ===${RESET}"
            if ! inbound_config=$(build_inbound "$type"); then
                continue
            fi
            new_inbounds=$(jq --argjson item "$inbound_config" '. += [$item]' <<< "$new_inbounds")
        done
    else
        for i in "${!PROTOCOL_LIST[@]}"; do
            type=${PROTOCOL_LIST[$i]}
            echo -e "${CYAN}=== 配置 $(proto_display "$type") ===${RESET}"
            if ! inbound_config=$(build_inbound "$type"); then
                continue
            fi
            new_inbounds=$(jq --argjson item "$inbound_config" '. += [$item]' <<< "$new_inbounds")
        done
    fi

    # 检查 inbounds 是否为空
    if [ "$new_inbounds" == "[]" ]; then
        echo -e "${RED}错误: 未选择任何协议配置！${RESET}"
        return 1
    fi
    # 更新配置文件
    local new_config
    new_config=$(jq --argjson inbounds "$new_inbounds" '.inbounds = $inbounds' <<< "$current_config")
    if [ -z "$new_config" ] || [ "$new_config" == "null" ]; then
        echo -e "${RED}错误: 配置生成失败，jq 操作返回空值！${RESET}"
        return 1
    fi
    save_config "$new_config" || return 1
    echo -e "${GREEN}节点配置已生成并更新到 ${CONFIG_FILE}${RESET}"
    restart_sing_box
}

# 生成节点配置
generate_node_config() {
    # 检查是否已安装
    if ! is_sing_box_installed; then
        echo -e "${RED}sing-box 未安装，请先安装！${RESET}"
        return 1
    fi

    # 检查配置文件是否存在
    if [ ! -f "${CONFIG_FILE}" ]; then
        echo -e "${RED}配置文件不存在，请先完成初始安装！${RESET}"
        return 1
    fi

    # 从配置文件读取必要参数
    if ! parse_config_from_json; then
        echo -e "${RED}无法从配置文件读取参数${RESET}"
        return 1
    fi

    # 动态生成协议菜单
    echo -e "${CYAN}请选择要生成的协议（可多选，用空格分隔）:${RESET}"
    local i
    for i in "${!PROTOCOL_LIST[@]}"; do
        echo "$((i + 1)). $(proto_display "${PROTOCOL_LIST[$i]}")"
    done
    echo "${ALL_CHOICE}. 全部"

    local choices
    read -p "请输入选项编号 (1-${ALL_CHOICE}): " choices
    append_inbounds "$choices"
}

# 检查 BBR 状态
check_bbr_status() {
    # 检查内核模块是否加载
    if ! lsmod | grep -q "tcp_bbr"; then
        return 1  # BBR 未启用（内核模块未加载）
    fi

    # 检查系统参数是否设置为 bbr
    local congestion_control
    if ! congestion_control=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null); then
        # 如果读取失败，也认为没有开启 BBR
        return 1
    fi

    if [ "$congestion_control" != "bbr" ]; then
        return 1  # BBR 未启用（系统参数未设置）
    fi

    return 0  # BBR 已启用
}

# 设置 sysctl 配置（删除旧值并写入新值）
set_sysctl() {
    local key=$1 value=$2
    sed -i "/^#${key}=/d; /^${key}=/d" /etc/sysctl.conf 2>/dev/null
    echo "${key}=${value}" >> /etc/sysctl.conf
}

# 删除 sysctl 配置
unset_sysctl() {
    local key=$1
    sed -i "/^#${key}=/d; /^${key}=/d" /etc/sysctl.conf 2>/dev/null
}

# 启用 BBR
enable_bbr() {
    echo -e "${CYAN}正在启用 TCP BBR...${RESET}"

    # 检查内核版本
    local kernel_version required_version
    kernel_version=$(uname -r | cut -d. -f1-2)
    required_version="4.9"

    # 使用正确的版本比较方法
    if ! printf "%s\n%s" "$required_version" "$kernel_version" | sort -V -C 2>/dev/null; then
        echo -e "${RED}当前内核版本 $kernel_version 低于要求的 $required_version，无法启用 BBR${RESET}"
        return 1
    fi

    # 加载 tcp_bbr 模块
    if ! lsmod | grep -q "tcp_bbr"; then
        modprobe tcp_bbr
        # 创建模块加载配置文件
        echo "tcp_bbr" > /etc/modules-load.d/bbr.conf
    fi

    # 配置系统参数
    set_sysctl "net.core.default_qdisc" "fq"
    set_sysctl "net.ipv4.tcp_congestion_control" "bbr"

    # 应用配置
    sysctl -p > /dev/null 2>&1

    # 验证 BBR 是否启用
    if check_bbr_status; then
        echo -e "${GREEN}TCP BBR 已成功启用！${RESET}"
        echo -e "${CYAN}验证信息：${RESET}"
        sysctl net.ipv4.tcp_available_congestion_control
        sysctl net.ipv4.tcp_congestion_control
        lsmod | grep tcp_bbr
    else
        echo -e "${RED}TCP BBR 启用失败${RESET}"
        return 1
    fi
}

# 关闭 BBR
disable_bbr() {
    echo -e "${CYAN}正在关闭 TCP BBR...${RESET}"

    # 删除 BBR 相关配置，恢复默认拥塞控制算法
    unset_sysctl "net.core.default_qdisc"
    set_sysctl "net.ipv4.tcp_congestion_control" "cubic"

    # 应用配置
    sysctl -p > /dev/null 2>&1

    # 卸载 tcp_bbr 模块
    if lsmod | grep -q "tcp_bbr"; then
        rmmod tcp_bbr 2>/dev/null
    fi

    # 删除模块加载配置文件
    rm -f /etc/modules-load.d/bbr.conf 2>/dev/null

    echo -e "${GREEN}TCP BBR 已关闭${RESET}"
    echo -e "${CYAN}当前拥塞控制算法：${RESET}"
    sysctl net.ipv4.tcp_congestion_control
}

# 显示配置来源信息
show_config_source_info() {
    echo -e "${CYAN}=== 配置来源信息 ===${RESET}"

    # Sing-box 配置
    if [ -f "${CONFIG_FILE}" ]; then
        echo -e "${GREEN}✓ Sing-box 配置文件: ${CONFIG_FILE}${RESET}"
        local config_size=$(stat -c%s "${CONFIG_FILE}" 2>/dev/null || stat -f%z "${CONFIG_FILE}" 2>/dev/null)
        echo -e "  大小: ${config_size} 字节"
        local inbound_count=$(jq '.inbounds | length' "${CONFIG_FILE}" 2>/dev/null || echo "0")
        echo -e "  入站协议数量: ${inbound_count}"
    else
        echo -e "${RED}✗ Sing-box 配置文件不存在${RESET}"
    fi

    echo ""
}

# 生成新的随机协议参数（初次安装或无默认值时使用）
init_protocol_params() {
    ensure_command ss iproute2 iproute

    # 随机端口
    vless_port=$(generate_unused_port)
    hysteria_port=$(generate_unused_port)
    anytls_port=$(generate_unused_port)
    shadowsocks_port=$(generate_unused_port)
    snell_port=$(generate_unused_port)
    socks_port=$(generate_unused_port)
    http_port=$(generate_unused_port)

    # 随机密码/密钥
    ss_password=$(sing-box generate rand 32 --base64 2>/dev/null || rand_alnum 32)
    password=$(rand_alnum 12)
    snell_psk=$(rand_alnum 32)
    socks_username=$(rand_alpha 8)
    socks_password=$(rand_alnum 12)
    http_username=$(rand_alpha 8)
    http_password=$(rand_alnum 12)

    # UUID 和 Reality 密钥对
    uuid=$(sing-box generate uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid)
    reality_output=$(sing-box generate reality-keypair 2>/dev/null)
    if [ -n "$reality_output" ]; then
        private_key=$(echo "${reality_output}" | sed -n 's/.*PrivateKey: *//p' | awk '{print $1}')
        public_key=$(echo "${reality_output}" | sed -n 's/.*PublicKey: *//p' | awk '{print $1}')
    else
        # 如果 sing-box 命令不可用，生成随机字符串
        private_key=$(rand_alnum 32)
        public_key=$(rand_alnum 32)
    fi

    snell_version=5
}

# 与默认值比较，由 parse_config_from_json 在提取后调用：
# 若某协议参数未提取到（配置中无此协议），则填充默认值
ensure_protocol_defaults() {
    [ -z "$vless_port" ] && vless_port=$(generate_unused_port)
    [ -z "$hysteria_port" ] && hysteria_port=$(generate_unused_port)
    [ -z "$anytls_port" ] && anytls_port=$(generate_unused_port)
    [ -z "$shadowsocks_port" ] && shadowsocks_port=$(generate_unused_port)
    [ -z "$ss_password" ] && ss_password=$(sing-box generate rand 32 --base64 2>/dev/null || rand_alnum 32)
    [ -z "$password" ] && password=$(rand_alnum 12)
    [ -z "$uuid" ] && uuid=$(sing-box generate uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid)
    if [ -z "$private_key" ] || [ -z "$public_key" ]; then
        reality_output=$(sing-box generate reality-keypair 2>/dev/null)
        if [ -n "$reality_output" ]; then
            private_key=$(echo "${reality_output}" | sed -n 's/.*PrivateKey: *//p' | awk '{print $1}')
            public_key=$(echo "${reality_output}" | sed -n 's/.*PublicKey: *//p' | awk '{print $1}')
        else
            private_key=$(rand_alnum 32)
            public_key=$(rand_alnum 32)
        fi
    fi
    [ -z "$socks_port" ] && socks_port=$(generate_unused_port)
    [ -z "$http_port" ] && http_port=$(generate_unused_port)
    [ -z "$socks_username" ] && socks_username=$(rand_alpha 8)
    [ -z "$socks_password" ] && socks_password=$(rand_alnum 12)
    [ -z "$http_username" ] && http_username=$(rand_alpha 8)
    [ -z "$http_password" ] && http_password=$(rand_alnum 12)
    [ -z "$snell_port" ] && snell_port=$(generate_unused_port)
    [ -z "$snell_psk" ] && snell_psk=$(rand_alnum 32)
    [ -z "$snell_version" ] && snell_version=5
}

# 从 config.json 解析配置信息
parse_config_from_json() {
    if [ ! -f "${CONFIG_FILE}" ]; then
        echo -e "${RED}配置文件不存在: ${CONFIG_FILE}${RESET}"
        return 1
    fi

    # 获取本机 IP 和国家
    host_ip=$(curl -s http://checkip.amazonaws.com)
    ip_country=$(curl -s http://ipinfo.io/${host_ip}/country)

    # 检查是否有 inbounds 配置
    local inbounds_count
    inbounds_count=$(jq '.inbounds | length' "${CONFIG_FILE}" 2>/dev/null)
    if [ -z "$inbounds_count" ] || [ "$inbounds_count" -eq 0 ]; then
        # 初次安装时没有 inbounds，这是正常情况
        echo -e "${YELLOW}初次安装检测：生成新的随机参数用于节点配置${RESET}"
        init_protocol_params
    else
        # 从现有配置中提取参数，未提取到的填充默认值
        local type
        for type in "${PROTOCOL_LIST[@]}"; do
            extract_protocol_from_config "$type"
        done
        ensure_protocol_defaults
    fi

    return 0
}

# 从 config.json 提取协议配置
extract_protocol_from_config() {
    local protocol_type=$1
    local config_data
    # 单次 jq 提取该协议通用字段（不存在则输出 null）
    config_data=$(jq -c --arg type "$protocol_type" '
        .inbounds[]? | select(.type == $type) |
        {
            port: .listen_port,
            password: (.users[0].password // .password),
            username: .users[0].username,
            uuid: .users[0].uuid,
            psk: .psk,
            version: .version
        }' "${CONFIG_FILE}" 2>/dev/null | head -1)
    [ -z "$config_data" ] || [ "$config_data" == "null" ] && return 1

    local port pass user id psk ver
    port=$(echo "$config_data" | jq -r '.port // empty')
    pass=$(echo "$config_data" | jq -r '.password // empty')
    user=$(echo "$config_data" | jq -r '.username // empty')
    id=$(echo "$config_data" | jq -r '.uuid // empty')
    psk=$(echo "$config_data" | jq -r '.psk // empty')
    ver=$(echo "$config_data" | jq -r '.version // empty')

    case $protocol_type in
        hysteria2) hysteria_port=$port; password=$pass;;
        shadowsocks) shadowsocks_port=$port; ss_password=$pass;;
        vless) vless_port=$port; uuid=$id;;
        anytls) anytls_port=$port;;
        socks) socks_port=$port; socks_username=$user; socks_password=$pass;;
        http) http_port=$port; http_username=$user; http_password=$pass;;
        snell) snell_port=$port; snell_psk=$psk; snell_version=$ver;;
        *) return 1;;
    esac
    return 0
}

# URL 编码函数
urlencode() {
    local string="${1}"
    local strlen=${#string}
    local encoded=""
    local pos c o

    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9] ) o="${c}" ;;
            * ) printf -v o '%%%02x' "'$c"
        esac
        encoded+="${o}"
    done
    echo "${encoded}"
}

# 生成客户端配置（从 config.json 读取）
generate_client_config() {
    if ! parse_config_from_json; then
        return 1
    fi

    local protocols=("$@")

    if [ ${#protocols[@]} -eq 0 ]; then
        echo -e "${YELLOW}未选择任何协议${RESET}"
        return 1
    fi

    echo -e "${GREEN}=== 客户端配置 ===${RESET}\n"

    for protocol in "${protocols[@]}"; do
        if ! extract_protocol_from_config "$protocol"; then
            echo -e "${YELLOW}未在配置文件中找到 ${protocol} 协议配置，跳过${RESET}"
            continue
        fi

        local uri
        if ! uri=$(build_client_uri "$protocol"); then
            echo -e "${RED}错误: ${protocol} URI 生成失败${RESET}"
            continue
        fi
        echo -e "==== $(proto_display "$protocol") ====\n${uri}\n"
        if [ "$protocol" == "snell" ]; then
            echo -e "Surge/Clash 格式:\n${ip_country}-snell = snell, ${host_ip}, ${snell_port}, psk = ${snell_psk}, version = ${snell_version:-5}\n"
        fi
    done
}



# 查看 sing-box 配置
check_sing_box() {
    # 检查配置文件是否存在
    if [ ! -f "${CONFIG_FILE}" ]; then
        echo -e "${RED}配置文件不存在，请先安装 sing-box！${RESET}"
        return
    fi

    # 检查配置文件中是否有 inbounds
    local inbounds_count=$(jq '.inbounds | length' "${CONFIG_FILE}" 2>/dev/null)
    if [ -z "$inbounds_count" ] || [ "$inbounds_count" -eq 0 ]; then
        echo -e "${YELLOW}配置文件中没有找到任何入站配置，请先生成节点配置！${RESET}"
        return
    fi

    # 获取配置文件中实际存在的协议
    local available_protocols=()
    local protocol_names=()
    local type
    for type in "${PROTOCOL_LIST[@]}"; do
        if jq -e --arg type "$type" '.inbounds[] | select(.type == $type)' "${CONFIG_FILE}" &>/dev/null; then
            available_protocols+=("$type")
            protocol_names+=("$(proto_display "$type")")
        fi
    done

    # 如果没有找到任何协议
    if [ ${#available_protocols[@]} -eq 0 ]; then
        echo -e "${YELLOW}配置文件中没有找到支持的协议配置${RESET}"
        return
    fi

    # 显示可用的协议选项
    local all_choice=$(( ${#available_protocols[@]} + 1 ))
    echo -e "${CYAN}检测到以下协议配置，请选择要查看的协议（可多选，用空格分隔）:${RESET}"
    local i
    for i in "${!protocol_names[@]}"; do
        echo "$((i+1)). ${protocol_names[$i]}"
    done
    echo "${all_choice}. 全部"

    local choices
    read -p "请输入选项编号: " choices

    local selected_protocols=()

    # 如果选择全部
    if choice_has "$all_choice" "$choices"; then
        selected_protocols=("${available_protocols[@]}")
    else
        # 根据选择添加协议
        for i in "${!available_protocols[@]}"; do
            if choice_has "$((i+1))" "$choices"; then
                selected_protocols+=("${available_protocols[$i]}")
            fi
        done
    fi

    if [ ${#selected_protocols[@]} -eq 0 ]; then
        echo -e "${YELLOW}未选择任何协议${RESET}"
        return
    fi

    generate_client_config "${selected_protocols[@]}"
}

# 添加中转配置
add_direct_config() {
    echo -e "${CYAN}=== 添加中转配置 ===${RESET}"

    # 检查 sing-box 是否已安装
    if ! is_sing_box_installed; then
        echo -e "${RED}sing-box 尚未安装，请先安装！${RESET}"
        return 1
    fi

    # 检查必要的命令
    ensure_command ss iproute2 iproute
    ensure_command jq jq

    # 输入本地端口
    while true; do
        read -p "请输入本地监听端口 (1025-65535): " local_port
        if ! [[ "$local_port" =~ ^[0-9]+$ ]] || [ "$local_port" -lt 1025 ] || [ "$local_port" -gt 65535 ]; then
            echo -e "${RED}端口必须是 1025-65535 之间的数字！${RESET}"
            continue
        fi
        if ! is_port_available "$local_port"; then
            echo -e "${RED}端口 $local_port 已被占用，请选择其他端口！${RESET}"
            continue
        fi
        break
    done

    # 输入远程 IP
    read -p "请输入远程 IP 地址: " remote_ip
    if [ -z "$remote_ip" ]; then
        echo -e "${RED}远程 IP 地址不能为空！${RESET}"
        return 1
    fi

    # 输入远程端口
    while true; do
        read -p "请输入远程端口 (1-65535): " remote_port
        if ! [[ "$remote_port" =~ ^[0-9]+$ ]] || [ "$remote_port" -lt 1 ] || [ "$remote_port" -gt 65535 ]; then
            echo -e "${RED}端口必须是 1-65535 之间的数字！${RESET}"
            continue
        fi
        break
    done

    # 生成唯一的 tag
    local tag="Direct-${local_port}"

    # 创建 Direct 配置
    local direct_config=$(jq -n \
        --arg tag "$tag" \
        --arg port "$local_port" \
        --arg override_port "$remote_port" \
        --arg override_address "$remote_ip" \
        '{
            tag: $tag,
            type: "direct",
            listen: "0.0.0.0",
            listen_port: ($port | tonumber),
            override_port: ($override_port | tonumber),
            override_address: $override_address
        }')

    # 读取当前配置
    local current_config
    current_config=$(cat "${CONFIG_FILE}")
    # 确保 inbounds 字段存在，添加新的 Direct 配置到 inbounds
    current_config=$(echo "$current_config" | jq '.inbounds = (.inbounds // [])')
    current_config=$(echo "$current_config" | jq --argjson item "$direct_config" '.inbounds += [$item]')

    if [ -z "$current_config" ] || [ "$current_config" == "null" ]; then
        echo -e "${RED}错误: 配置生成失败，jq 操作返回空值！${RESET}"
        return 1
    fi

    if ! save_config "$current_config"; then
        return 1
    fi

    # 保存到 Direct 配置文件（用于查看）
    echo "${local_port} ${remote_ip} ${remote_port}" >> "${DIRECT_CONFIG_FILE}"

    echo -e "${GREEN}中转配置添加成功！${RESET}"
    echo -e "${CYAN}本地端口: ${local_port}${RESET}"
    echo -e "${CYAN}远程地址: ${remote_ip}:${remote_port}${RESET}"

    # 重启服务
    echo -e "${YELLOW}正在重启 sing-box 服务...${RESET}"
    restart_sing_box
}

# 查看中转配置
view_direct_config() {
    echo -e "${CYAN}=== 中转配置列表 ===${RESET}\n"

    # 检查配置文件是否存在
    if [ ! -f "${CONFIG_FILE}" ]; then
        echo -e "${RED}配置文件不存在！${RESET}"
        return 1
    fi

    # 获取中转配置列表
    local direct_configs=$(get_direct_config_list)
    if [ -z "$direct_configs" ]; then
        echo -e "${YELLOW}当前没有中转配置${RESET}"
        return 0
    fi

    echo -e "${GREEN}序号 | 本地端口 | 远程IP | 远程端口${RESET}"
    echo -e "${GREEN}========================================${RESET}"
    local count=1
    echo "$direct_configs" | while read -r line; do
        echo -e "${CYAN}$count. $line${RESET}"
        ((count++))
    done
    echo -e "${GREEN}========================================${RESET}"
}

# 获取中转配置列表
get_direct_config_list() {
    # 从 config.json 中读取所有 Direct 类型的配置
    local direct_configs=$(jq -r '.inbounds[]? | select(.type == "direct") | "\(.listen_port) \(.override_address) \(.override_port)"' "${CONFIG_FILE}" 2>/dev/null)
    echo "$direct_configs"
}

# 删除中转配置
delete_direct_config() {
    echo -e "${CYAN}=== 删除中转配置 ===${RESET}\n"

    # 检查 jq 命令
    ensure_command jq jq

    # 获取中转配置列表
    local direct_configs=$(get_direct_config_list)
    if [ -z "$direct_configs" ]; then
        echo -e "${YELLOW}当前没有中转配置${RESET}"
        return 0
    fi

    # 显示当前配置
    echo -e "${GREEN}序号 | 本地端口 | 远程IP | 远程端口${RESET}"
    echo -e "${GREEN}========================================${RESET}"
    local count=1
    local config_array=()
    while IFS= read -r line; do
        echo -e "${CYAN}$count. $line${RESET}"
        config_array+=("$line")
        ((count++))
    done <<< "$direct_configs"
    echo -e "${GREEN}========================================${RESET}"

    echo ""
    echo -e "${CYAN}请选择要删除的配置:${RESET}"
    echo "1. 选择删除（输入序号，可多选，用空格分隔）"
    echo "2. 删除全部中转配置"
    echo "0. 取消"

    read -p "请输入选项编号: " choice

    case "$choice" in
        1)
            # 选择删除
            read -p "请输入要删除的配置序号（可多选，用空格分隔）: " selections

            if [ -z "$selections" ]; then
                echo -e "${YELLOW}未选择任何配置${RESET}"
                return 0
            fi

            # 验证输入
            for sel in $selections; do
                if ! [[ "$sel" =~ ^[0-9]+$ ]] || [ "$sel" -lt 1 ] || [ "$sel" -gt "${#config_array[@]}" ]; then
                    echo -e "${RED}无效的序号: $sel${RESET}"
                    return 1
                fi
            done

            # 确认删除
            echo -e "${YELLOW}将要删除以下配置:${RESET}"
            for sel in $selections; do
                echo -e "${CYAN}${config_array[$((sel-1))]}${RESET}"
            done

            if ! confirm_prompt "删除以上配置"; then
                echo -e "${YELLOW}已取消删除操作${RESET}"
                return 0
            fi

            # 读取当前配置
            local current_config=$(cat "${CONFIG_FILE}")

            # 删除选中的配置
            for sel in $selections; do
                IFS=' ' read -r local_port remote_ip remote_port <<< "${config_array[$((sel-1))]}"

                # 从配置中删除
                current_config=$(echo "$current_config" | jq --arg port "$local_port" \
                    'del(.inbounds[] | select(.type == "direct" and .listen_port == ($port | tonumber)))')

                # 从 Direct 配置文件中删除
                if [ -f "${DIRECT_CONFIG_FILE}" ]; then
                    sed -i "/^${local_port} /d" "${DIRECT_CONFIG_FILE}"
                fi

                echo -e "${GREEN}已删除: 本地端口 $local_port -> $remote_ip:$remote_port${RESET}"
            done
            ;;
        2)
            # 删除全部
            if ! confirm_prompt "删除所有中转配置"; then
                echo -e "${YELLOW}已取消删除操作${RESET}"
                return 0
            fi

            # 读取当前配置
            local current_config=$(cat "${CONFIG_FILE}")

            # 删除所有 direct 类型的配置
            current_config=$(echo "$current_config" | jq 'del(.inbounds[] | select(.type == "direct"))')

            # 清空 Direct 配置文件
            if [ -f "${DIRECT_CONFIG_FILE}" ]; then
                : > "${DIRECT_CONFIG_FILE}"
            fi

            echo -e "${GREEN}已删除所有中转配置${RESET}"
            ;;
        0)
            echo -e "${YELLOW}已取消删除操作${RESET}"
            return 0
            ;;
        *)
            echo -e "${RED}无效的选项${RESET}"
            return 1
            ;;
    esac

    # 验证 jq 操作是否成功
    if [ -z "$current_config" ] || [ "$current_config" == "null" ]; then
        echo -e "${RED}错误: 配置更新失败，jq 操作返回空值！${RESET}"
        return 1
    fi

    if ! save_config "$current_config"; then
        return 1
    fi

    echo -e "${GREEN}中转配置删除成功！${RESET}"

    # 重启服务
    echo -e "${YELLOW}正在重启 sing-box 服务...${RESET}"
    restart_sing_box
}

# 删除节点配置
delete_node_config() {
    echo -e "${CYAN}=== 删除节点配置 ===${RESET}\n"

    # 检查配置文件是否存在
    if [ ! -f "${CONFIG_FILE}" ]; then
        echo -e "${RED}配置文件不存在，请先安装 sing-box！${RESET}"
        return 1
    fi

    # 检查配置文件中是否有 inbounds
    local inbounds_count=$(jq '.inbounds | length' "${CONFIG_FILE}" 2>/dev/null)
    if [ -z "$inbounds_count" ] || [ "$inbounds_count" -eq 0 ]; then
        echo -e "${YELLOW}配置文件中没有找到任何入站配置！${RESET}"
        return 1
    fi

    # 获取所有节点类型的配置（排除 direct 类型）
    local available_nodes=()
    local node_display_names=()
    local node_info=()
    local node_type

    # 按协议注册表顺序检查每种协议类型
    for node_type in "${PROTOCOL_LIST[@]}"; do
        # 获取该类型的所有节点
        local nodes
        nodes=$(jq -r --arg type "$node_type" '.inbounds[]? | select(.type == $type) | "\(.type)|\(.listen_port)|\(.tag // "unknown")"' "${CONFIG_FILE}" 2>/dev/null)

        if [ -n "$nodes" ]; then
            local type port tag
            while IFS='|' read -r type port tag; do
                available_nodes+=("$type")
                node_info+=("$type|$port|$tag")
                node_display_names+=("$(proto_display "$type") (端口: $port)")
            done <<< "$nodes"
        fi
    done

    # 如果没有找到任何节点配置
    if [ ${#available_nodes[@]} -eq 0 ]; then
        echo -e "${YELLOW}配置文件中没有找到任何节点配置${RESET}"
        return 0
    fi

    # 显示可用的节点选项
    echo -e "${CYAN}检测到以下节点配置，请选择要删除的节点（可多选，用空格分隔）:${RESET}"
    for i in "${!node_display_names[@]}"; do
        echo "$((i+1)). ${node_display_names[$i]}"
    done
    echo "$((${#node_display_names[@]}+1)). 删除全部节点配置"
    echo "0. 取消"

    read -p "请输入选项编号: " choices

    # 如果选择取消
    if [[ "$choices" == "0" ]]; then
        echo -e "${YELLOW}已取消删除操作${RESET}"
        return 0
    fi

    local nodes_to_delete=()

    # 如果选择删除全部
    local all_choice=$(( ${#node_display_names[@]} + 1 ))
    if choice_has "$all_choice" "$choices"; then
        # 确认删除全部
        if ! confirm_prompt "删除所有节点配置（将保留最小配置）"; then
            echo -e "${YELLOW}已取消删除操作${RESET}"
            return 0
        fi

        nodes_to_delete=("${node_info[@]}")
    else
        # 根据选择添加要删除的节点
        local i
        for i in "${!available_nodes[@]}"; do
            if choice_has "$((i+1))" "$choices"; then
                nodes_to_delete+=("${node_info[$i]}")
            fi
        done
    fi

    if [ ${#nodes_to_delete[@]} -eq 0 ]; then
        echo -e "${YELLOW}未选择任何节点${RESET}"
        return 0
    fi

    # 读取当前配置
    local current_config
    current_config=$(cat "${CONFIG_FILE}")

    # 删除选中的节点
    local node type port tag
    for node in "${nodes_to_delete[@]}"; do
        IFS='|' read -r type port tag <<< "$node"

        # 从配置中删除该节点
        current_config=$(echo "$current_config" | jq --arg type "$type" --arg port "$port" \
            'del(.inbounds[] | select(.type == $type and .listen_port == ($port | tonumber)))')

        echo -e "${GREEN}已删除: $type (端口: $port)${RESET}"
    done

    if ! save_config "$current_config"; then
        return 1
    fi

    echo -e "${GREEN}节点配置删除成功！${RESET}"

    # 重启服务
    echo -e "${YELLOW}正在重启 sing-box 服务...${RESET}"
    restart_sing_box
}

# 显示菜单
show_menu() {
    clear
    is_sing_box_installed
    sing_box_installed=$?
    is_sing_box_running
    sing_box_running=$?

    # 检查 BBR 状态
    check_bbr_status
    bbr_status=$?

    echo -e "${GREEN}=== sing-box 管理工具 ===${RESET}"
    echo -e "Sing-box 安装状态: $(if [ ${sing_box_installed} -eq 0 ]; then echo -e "${GREEN}已安装${RESET}"; else echo -e "${RED}未安装${RESET}"; fi)"
    echo -e "Sing-box 运行状态: $(if [ ${sing_box_running} -eq 0 ]; then echo -e "${GREEN}已运行${RESET}"; else echo -e "${RED}未运行${RESET}"; fi)"
    if [ ${sing_box_installed} -eq 0 ]; then
        local installed_version
        installed_version=$(get_sing_box_version 2>/dev/null)
        echo -e "Sing-box 版本: ${CYAN}${installed_version:-未知}${RESET} ($(if check_snell_supported; then echo -e "${GREEN}支持 Snell${RESET}"; else echo -e "${YELLOW}不支持 Snell${RESET}"; fi))"
    fi
    echo -e "BBR 状态: $(if [ ${bbr_status} -eq 0 ]; then echo -e "${GREEN}已启用${RESET}"; else echo -e "${RED}未启用${RESET}"; fi)"
    echo ""
    echo "1. 安装 sing-box 服务"
    echo "2. 卸载 sing-box 服务"
    if [ ${sing_box_installed} -eq 0 ]; then
        if [ ${sing_box_running} -eq 0 ]; then
            echo "3. 停止 sing-box 服务"
        else
            echo "3. 启动 sing-box 服务"
        fi
        echo "4. 重启 sing-box 服务"
        echo "5. 查看 sing-box 状态"
        echo "6. 查看 sing-box 日志"
        echo "7. 生成节点配置"
        echo "8. 查看节点配置"
        echo "9. 删除节点配置"
        echo ""
        echo -e "${PURPLE}=== 中转配置管理 ===${RESET}"
        echo "10. 添加中转配置"
        echo "11. 查看中转配置"
        echo "12. 删除中转配置"
    fi

    echo ""
    echo -e "${PURPLE}=== BBR 优化管理 ===${RESET}"
    if [ ${bbr_status} -eq 0 ]; then
        echo "13. 关闭 BBR"
    else
        echo "13. 启用 BBR"
    fi

    echo ""
    echo -e "${PURPLE}=== 配置管理 ===${RESET}"
    echo "14. 查看配置来源信息"

    echo "0. 退出"
    echo -e "${GREEN}=========================${RESET}"
    read -p "请输入选项编号: " choice
    echo ""
}

# 捕获 Ctrl+C 信号
trap 'echo -e "${RED}已取消操作${RESET}"; exit' INT

# 主循环
check_root

# 检查 sing-box 是否已安装，未安装则提示并返回失败
require_sing_box() {
    if [ ${sing_box_installed} -eq 0 ]; then
        return 0
    fi
    echo -e "${RED}sing-box 尚未安装！${RESET}"
    return 1
}

while true; do
    show_menu
    case "${choice}" in
        1)
            if [ ${sing_box_installed} -eq 0 ]; then
                echo -e "${YELLOW}sing-box 已经安装！${RESET}"
            else
                install_sing_box
            fi
            ;;
        2)
            require_sing_box && uninstall_sing_box
            ;;
        3)
            if require_sing_box; then
                if [ ${sing_box_running} -eq 0 ]; then
                    stop_sing_box
                else
                    start_sing_box
                fi
            fi
            ;;
        4)  require_sing_box && restart_sing_box
            ;;
        5)  require_sing_box && status_sing_box
            ;;
        6)  require_sing_box && log_sing_box
            ;;
        7)  require_sing_box && generate_node_config
            ;;
        8)  require_sing_box && check_sing_box
            ;;
        9)  require_sing_box && delete_node_config
            ;;
        10) require_sing_box && add_direct_config
            ;;
        11) require_sing_box && view_direct_config
            ;;
        12) require_sing_box && delete_direct_config
            ;;
        13)
            if check_bbr_status; then
                disable_bbr
            else
                enable_bbr
            fi
            ;;
        14) show_config_source_info
            ;;
        0)
            echo -e "${GREEN}已退出 sing-box 管理工具${RESET}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效的选项，请输入有效的编号${RESET}"
            ;;
    esac
    read -p "按 Enter 键继续..."
done
