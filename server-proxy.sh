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

# 检查 root 权限
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}请使用 root 权限执行此脚本！${RESET}"
        exit 1
    fi
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

# 检查 ss 命令是否可用
check_ss_command() {
    if ! command -v ss &> /dev/null; then
        echo -e "${YELLOW}ss 命令未找到，正在尝试自动安装 iproute2 ${RESET}"

        # 检测包管理器并安装
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y iproute2
        elif command -v dnf &> /dev/null; then
            dnf install -y iproute
        elif command -v yum &> /dev/null; then
            yum install -y iproute
        elif command -v pacman &> /dev/null; then
            pacman -Sy --noconfirm iproute2
        elif command -v zypper &> /dev/null; then
            zypper install -y iproute2
        else
            echo -e "${RED}无法检测到支持的包管理器，请手动安装 iproute2 包${RESET}"
            exit 1
        fi

        # 再次检查是否安装成功
        if command -v ss &> /dev/null; then
            echo -e "${GREEN}iproute2 安装成功，ss 命令已可用${RESET}"
        else
            echo -e "${RED}自动安装失败，请手动安装 iproute2 包${RESET}"
            exit 1
        fi
    else
        echo -e "${GREEN}ss 命令可用${RESET}"
    fi
}

# 检查 jq 命令是否可用
check_jq_command() {
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}jq 命令未找到，正在尝试自动安装 jq ${RESET}"

        # 检测包管理器并安装
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y jq
        elif command -v dnf &> /dev/null; then
            dnf install -y jq
        elif command -v yum &> /dev/null; then
            yum install -y jq
        elif command -v pacman &> /dev/null; then
            pacman -Sy --noconfirm jq
        elif command -v zypper &> /dev/null; then
            zypper install -y jq
        else
            echo -e "${RED}无法检测到支持的包管理器，请手动安装 jq 包${RESET}"
            exit 1
        fi

        # 再次检查是否安装成功
        if command -v jq &> /dev/null; then
            echo -e "${GREEN}jq 安装成功，jq 命令已可用${RESET}"
        else
            echo -e "${RED}自动安装失败，请手动安装 jq 包${RESET}"
            exit 1
        fi
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

    # 生成随机端口和密码
    check_ss_command
    vless_port=$(generate_unused_port)
    hysteria_port=$(generate_unused_port)
    anytls_port=$(generate_unused_port)
    shadowsocks_port=$(generate_unused_port)
    snell_port=$(generate_unused_port)
    snell_psk=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 32)
    ss_password=$(sing-box generate rand --base64 32)
    password=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12)
    socks_port=$(generate_unused_port)
    http_port=$(generate_unused_port)
    socks_username=$(tr -dc a-z </dev/urandom | head -c 8)
    socks_password=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12)
    http_username=$(tr -dc a-z </dev/urandom | head -c 8)
    http_password=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12)

    # 生成 UUID 和 Reality 密钥对
    uuid=$(sing-box generate uuid)
    reality_output=$(sing-box generate reality-keypair)
    private_key=$(echo "${reality_output}" | grep -oP 'PrivateKey:\s*\K.*')
    public_key=$(echo "${reality_output}" | grep -oP 'PublicKey:\s*\K.*')

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
    read -p "$(echo -e "${RED}确定要卸载 sing-box 吗? (Y/n) ${RESET}")" choice
    choice=${choice:-Y}  # 默认设置为 Y
    case "${choice}" in
        y|Y)
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
            ;;
        *)
            echo -e "${YELLOW}已取消卸载操作${RESET}"
            ;;
    esac
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
    echo -e "${CYAN}请选择要生成的协议（可多选，用空格分隔）:${RESET}"
    echo "1. Snell"
    echo "2. Shadowsocks"
    echo "3. VLESS+Vision+Reality"
    echo "4. Hysteria2"
    echo "5. AnyTLS"
    echo "6. SOCKS5代理"
    echo "7. HTTP代理"
    echo "8. 全部"
    read -p "请输入选项编号 (1-8): " choices
    # 检查必要的命令
    check_ss_command
    check_jq_command
    # 读取当前配置
    local current_config
    current_config=$(cat "${CONFIG_FILE}") || {
        echo -e "${RED}错误: 无法读取配置文件${RESET}"
        return 1
    }
    # 检查当前配置是否有 inbounds 字段
    if ! echo "$current_config" | jq -e '.inbounds' &>/dev/null; then
        # 如果不存在 inbounds，创建一个空数组
        current_config=$(echo "$current_config" | jq '.inbounds = []')
    fi
    local new_inbounds
    new_inbounds=$(echo "$current_config" | jq '.inbounds')
    if [[ "$choices" == *"8"* ]] || [[ "$choices" == *"1"* ]]; then
        # 重置上次操作的确认状态
        continue_snell=""
        # 检查 sing-box 版本是否支持 Snell (自 1.14.0 起支持)
        if ! check_snell_supported; then
            echo -e "${YELLOW}警告: 当前 sing-box 版本不支持 Snell 协议，需要 1.14.0 及以上版本！${RESET}"
            local current_version
            current_version=$(get_sing_box_version)
            echo -e "${YELLOW}当前版本: ${current_version:-未知}${RESET}"
            read -p "$(echo -e "${RED}此配置可能导致 sing-box 启动失败，是否继续生成？(y/N) ${RESET}")" continue_snell
            continue_snell=${continue_snell:-N}
            if [[ ! "$continue_snell" =~ ^[Yy]$ ]]; then
                echo -e "${YELLOW}已取消生成 Snell 配置${RESET}"
            else
                echo -e "${YELLOW}继续生成 Snell 配置，请确保安装支持 Snell 的 sing-box 版本${RESET}"
            fi
        fi
        if [[ "$continue_snell" =~ ^[Yy]$ ]] || check_snell_supported; then
            # 检查是否已有 Snell 版本设置
            if [ -z "$snell_version" ]; then
                snell_version=5
            fi
            # 获取 Snell 版本
            read -p "请输入 Snell 版本 (5-6，可直接回车默认 5): " snell_version_input
            if [ -n "$snell_version_input" ]; then
                if [[ "$snell_version_input" == "5" ]] || [[ "$snell_version_input" == "6" ]]; then
                    snell_version=$snell_version_input
                else
                    echo -e "${YELLOW}无效的 Snell 版本，使用默认版本 5${RESET}"
                    snell_version=5
                fi
            fi
            # 获取 Snell 端口
            echo -e "${CYAN}=== 配置 Snell ===${RESET}"
            snell_port=$(get_or_generate_port "Snell" "$snell_port")
            # 确保 psk 长度满足 v6 要求 (12-255 字节)
            if [ "$snell_version" == "6" ] && [ ${#snell_psk} -lt 12 ]; then
                echo -e "${YELLOW}Snell v6 要求 psk 长度为 12-255 字节，重新生成 psk${RESET}"
                snell_psk=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 32)
            fi
            # 添加 Snell
            local snell_config
            snell_config=$(jq -n \
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
                }')

            if [ -z "$snell_config" ] || [ "$snell_config" == "null" ]; then
                echo -e "${RED}错误: Snell 配置生成失败${RESET}"
                return 1
            fi

            new_inbounds=$(jq --argjson item "$snell_config" '. += [$item]' <<< "$new_inbounds")
        fi
    fi
    if [[ "$choices" == *"8"* ]] || [[ "$choices" == *"2"* ]]; then
        # 获取 Shadowsocks 端口
        echo -e "${CYAN}=== 配置 Shadowsocks ===${RESET}"
        shadowsocks_port=$(get_or_generate_port "Shadowsocks" "$shadowsocks_port")
        # 添加 Shadowsocks
        local shadowsocks_config
        shadowsocks_config=$(jq -n \
            --arg port "$shadowsocks_port" \
            --arg ss_password "$ss_password" \
            '{
                type: "shadowsocks",
                tag: "shadowsocks-in",
                listen: "0.0.0.0",
                listen_port: ($port | tonumber),
                method: "2022-blake3-aes-256-gcm",
                password: $ss_password,
                multiplex: {enabled: true}
            }')

        if [ -z "$shadowsocks_config" ] || [ "$shadowsocks_config" == "null" ]; then
            echo -e "${RED}错误: Shadowsocks 配置生成失败${RESET}"
            return 1
        fi

        new_inbounds=$(jq --argjson item "$shadowsocks_config" '. += [$item]' <<< "$new_inbounds")
    fi
    if [[ "$choices" == *"8"* ]] || [[ "$choices" == *"3"* ]]; then
        # 获取 VLESS 端口
        echo -e "${CYAN}=== 配置 VLESS+Vision+Reality ===${RESET}"
        vless_port=$(get_or_generate_port "VLESS" "$vless_port")
        # 添加 VLESS+Reality
        local vless_config
        vless_config=$(jq -n \
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
            }')

        if [ -z "$vless_config" ] || [ "$vless_config" == "null" ]; then
            echo -e "${RED}错误: VLESS 配置生成失败${RESET}"
            return 1
        fi

        new_inbounds=$(jq --argjson item "$vless_config" '. += [$item]' <<< "$new_inbounds")
    fi
    if [[ "$choices" == *"8"* ]] || [[ "$choices" == *"4"* ]]; then
        # 获取 Hysteria2 端口
        echo -e "${CYAN}=== 配置 Hysteria2 ===${RESET}"
        hysteria_port=$(get_or_generate_port "Hysteria2" "$hysteria_port")
        # 添加 Hysteria2
        local hysteria_config
        hysteria_config=$(jq -n \
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
            }')

        if [ -z "$hysteria_config" ] || [ "$hysteria_config" == "null" ]; then
            echo -e "${RED}错误: Hysteria2 配置生成失败${RESET}"
            return 1
        fi

        new_inbounds=$(jq --argjson item "$hysteria_config" '. += [$item]' <<< "$new_inbounds")
    fi
    if [[ "$choices" == *"8"* ]] || [[ "$choices" == *"5"* ]]; then
        # 获取 AnyTLS 端口
        echo -e "${CYAN}=== 配置 AnyTLS ===${RESET}"
        anytls_port=$(get_or_generate_port "AnyTLS" "$anytls_port")
        # 添加 AnyTLS
        local anytls_config
        anytls_config=$(jq -n \
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
            }')

        if [ -z "$anytls_config" ] || [ "$anytls_config" == "null" ]; then
            echo -e "${RED}错误: AnyTLS 配置生成失败${RESET}"
            return 1
        fi

        new_inbounds=$(jq --argjson item "$anytls_config" '. += [$item]' <<< "$new_inbounds")
    fi
    if [[ "$choices" == *"8"* ]] || [[ "$choices" == *"6"* ]]; then
        # 获取 SOCKS5 端口
        echo -e "${CYAN}=== 配置 SOCKS5 代理 ===${RESET}"
        socks_port=$(get_or_generate_port "SOCKS5" "$socks_port")
        # 添加 SOCKS5 配置
        local socks_config
        socks_config=$(jq -n \
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
            }')
        if [ -z "$socks_config" ] || [ "$socks_config" == "null" ]; then
            echo -e "${RED}错误: SOCKS5 配置生成失败${RESET}"
            return 1
        fi
        new_inbounds=$(jq --argjson item "$socks_config" '. += [$item]' <<< "$new_inbounds")
    fi
    if [[ "$choices" == *"8"* ]] || [[ "$choices" == *"7"* ]]; then
        # 获取 HTTP 端口
        echo -e "${CYAN}=== 配置 HTTP 代理 ===${RESET}"
        http_port=$(get_or_generate_port "HTTP" "$http_port")
        # 添加 HTTP 配置
        local http_config
        http_config=$(jq -n \
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
            }')
        if [ -z "$http_config" ] || [ "$http_config" == "null" ]; then
            echo -e "${RED}错误: HTTP 配置生成失败${RESET}"
            return 1
        fi
        new_inbounds=$(jq --argjson item "$http_config" '. += [$item]' <<< "$new_inbounds")
    fi

    # 检查 inbounds 是否为空
    if [ "$new_inbounds" == "[]" ]; then
        echo -e "${RED}错误: 未选择任何协议配置！${RESET}"
        return 1
    fi
    # 更新配置文件，添加 inbounds
    local new_config
    new_config=$(jq --argjson inbounds "$new_inbounds" '.inbounds = $inbounds' <<< "$current_config")
    # 验证 jq 操作是否成功
    if [ -z "$new_config" ] || [ "$new_config" == "null" ]; then
        echo -e "${RED}错误: 配置生成失败，jq 操作返回空值！${RESET}"
        return 1
    fi
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
    echo "$new_config" > "${CONFIG_FILE}" || {
        echo -e "${RED}错误: 无法写入配置文件${RESET}"
        mv "${CONFIG_FILE}.backup" "${CONFIG_FILE}"
        return 1
    }
    # 验证写入的文件是否为有效的 JSON
    if ! jq empty "${CONFIG_FILE}" 2>/dev/null; then
        echo -e "${RED}错误: 写入配置文件失败，正在恢复备份...${RESET}"
        mv "${CONFIG_FILE}.backup" "${CONFIG_FILE}"
        return 1
    fi
    # 删除备份文件
    rm -f "${CONFIG_FILE}.backup"
    echo -e "${GREEN}节点配置已生成并更新到 ${CONFIG_FILE}${RESET}"
    # 重启服务
    restart_sing_box
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

# 启用 BBR
enable_bbr() {
    echo -e "${CYAN}正在启用 TCP BBR...${RESET}"

    # 检查内核版本
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
    # 确保配置存在且未被注释
    local bbr_configs=(
        "net.core.default_qdisc=fq"
        "net.ipv4.tcp_congestion_control=bbr"
    )

    for config in "${bbr_configs[@]}"; do
        local key=$(echo "$config" | cut -d= -f1)
        local value=$(echo "$config" | cut -d= -f2)

        # 删除可能存在的注释行
        sed -i "/^#${key}=/d" /etc/sysctl.conf 2>/dev/null
        sed -i "/^${key}=/d" /etc/sysctl.conf 2>/dev/null

        # 添加配置
        echo "$config" >> /etc/sysctl.conf
    done

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

    # 删除 BBR 相关配置
    local bbr_configs=(
        "net.core.default_qdisc=fq"
        "net.ipv4.tcp_congestion_control=bbr"
    )

    for config in "${bbr_configs[@]}"; do
        local key=$(echo "$config" | cut -d= -f1)
        # 删除配置行（包括注释行）
        sed -i "/^#${key}=/d" /etc/sysctl.conf 2>/dev/null
        sed -i "/^${key}=/d" /etc/sysctl.conf 2>/dev/null
    done

    # 设置为默认的拥塞控制算法（cubic）
    # 先删除可能存在的 cubic 配置
    sed -i "/^#net.ipv4.tcp_congestion_control=cubic$/d" /etc/sysctl.conf 2>/dev/null
    sed -i "/^net.ipv4.tcp_congestion_control=cubic$/d" /etc/sysctl.conf 2>/dev/null
    # 添加 cubic 配置
    echo "net.ipv4.tcp_congestion_control=cubic" >> /etc/sysctl.conf

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
    local inbounds_count=$(jq '.inbounds | length' "${CONFIG_FILE}" 2>/dev/null)
    if [ -z "$inbounds_count" ] || [ "$inbounds_count" -eq 0 ]; then
        # 初次安装时没有 inbounds，这是正常情况
        # 生成新的随机参数用于节点配置
        echo -e "${YELLOW}初次安装检测：生成新的随机参数用于节点配置${RESET}"

        # 生成随机端口和密码
        check_ss_command
        vless_port=$(generate_unused_port)
        hysteria_port=$(generate_unused_port)
        anytls_port=$(generate_unused_port)
        shadowsocks_port=$(generate_unused_port)
        snell_port=$(generate_unused_port)
        snell_psk=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 32)
        ss_password=$(sing-box generate rand 32 --base64 2>/dev/null || tr -dc A-Za-z0-9 </dev/urandom | head -c 32)
        password=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12)
        socks_port=$(generate_unused_port)
        http_port=$(generate_unused_port)
        socks_username=$(tr -dc a-z </dev/urandom | head -c 8)
        socks_password=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12)
        http_username=$(tr -dc a-z </dev/urandom | head -c 8)
        http_password=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12)

        # 生成 UUID 和 Reality 密钥对
        uuid=$(sing-box generate uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid)
        reality_output=$(sing-box generate reality-keypair 2>/dev/null)
        if [ -n "$reality_output" ]; then
            private_key=$(echo "${reality_output}" | grep -oP 'PrivateKey:\s*\K.*')
            public_key=$(echo "${reality_output}" | grep -oP 'PublicKey:\s*\K.*')
        else
            # 如果 sing-box 命令不可用，生成随机字符串
            private_key=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 32)
            public_key=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 32)
        fi

        return 0
    else
        # 从现有配置中提取参数
        extract_protocol_from_config "hysteria2"
        extract_protocol_from_config "shadowsocks"
        extract_protocol_from_config "vless"
        extract_protocol_from_config "anytls"
        extract_protocol_from_config "socks"
        extract_protocol_from_config "http"
        extract_protocol_from_config "snell"

        # 如果某些参数未设置，使用默认值
        if [ -z "$vless_port" ]; then
            vless_port=$(generate_unused_port)
        fi
        if [ -z "$hysteria_port" ]; then
            hysteria_port=$(generate_unused_port)
        fi
        if [ -z "$anytls_port" ]; then
            anytls_port=$(generate_unused_port)
        fi
        if [ -z "$shadowsocks_port" ]; then
            shadowsocks_port=$(generate_unused_port)
        fi
        if [ -z "$ss_password" ]; then
            ss_password=$(sing-box generate rand 32 --base64 2>/dev/null || tr -dc A-Za-z0-9 </dev/urandom | head -c 32)
        fi
        if [ -z "$password" ]; then
            password=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12)
        fi
        if [ -z "$uuid" ]; then
            uuid=$(sing-box generate uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid)
        fi
        if [ -z "$private_key" ] || [ -z "$public_key" ]; then
            reality_output=$(sing-box generate reality-keypair 2>/dev/null)
            if [ -n "$reality_output" ]; then
                private_key=$(echo "${reality_output}" | grep -oP 'PrivateKey:\s*\K.*')
                public_key=$(echo "${reality_output}" | grep -oP 'PublicKey:\s*\K.*')
            else
                private_key=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 32)
                public_key=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 32)
            fi
        fi
        if [ -z "$socks_port" ]; then
            socks_port=$(generate_unused_port)
        fi
        if [ -z "$http_port" ]; then
            http_port=$(generate_unused_port)
        fi
        if [ -z "$socks_username" ]; then
            socks_username=$(tr -dc a-z </dev/urandom | head -c 8)
        fi
        if [ -z "$socks_password" ]; then
            socks_password=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12)
        fi
        if [ -z "$http_username" ]; then
            http_username=$(tr -dc a-z </dev/urandom | head -c 8)
        fi
        if [ -z "$http_password" ]; then
            http_password=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12)
        fi
        if [ -z "$snell_port" ]; then
            snell_port=$(generate_unused_port)
        fi
        if [ -z "$snell_psk" ]; then
            snell_psk=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 32)
        fi
        if [ -z "$snell_version" ]; then
            snell_version=5
        fi
    fi

    return 0
}

# 从 config.json 提取协议配置
extract_protocol_from_config() {
    local protocol_type=$1
    local config_data=""

    case $protocol_type in
        hysteria2)
            config_data=$(jq -r '.inbounds[] | select(.type == "hysteria2") | {port: .listen_port, password: .users[0].password}' "${CONFIG_FILE}" 2>/dev/null)
            if [ -n "$config_data" ] && [ "$config_data" != "null" ]; then
                local port=$(echo "$config_data" | jq -r '.port')
                local pass=$(echo "$config_data" | jq -r '.password')
                [ -n "$port" ] && [ "$port" != "null" ] && hysteria_port=$port
                [ -n "$pass" ] && [ "$pass" != "null" ] && password=$pass
                return 0
            fi
            ;;
        shadowsocks)
            # 从 shadowsocks 中提取端口和密码
            local ss_data=$(jq -r '.inbounds[] | select(.type == "shadowsocks") | {port: .listen_port, password: .password}' "${CONFIG_FILE}" 2>/dev/null)
            if [ -n "$ss_data" ] && [ "$ss_data" != "null" ]; then
                local port=$(echo "$ss_data" | jq -r '.port')
                local ss_pass=$(echo "$ss_data" | jq -r '.password')
                [ -n "$port" ] && [ "$port" != "null" ] && shadowsocks_port=$port
                [ -n "$ss_pass" ] && [ "$ss_pass" != "null" ] && ss_password=$ss_pass
                return 0
            fi
            ;;
        vless)
            config_data=$(jq -r '.inbounds[] | select(.type == "vless") | {port: .listen_port, uuid: .users[0].uuid}' "${CONFIG_FILE}" 2>/dev/null)
            if [ -n "$config_data" ] && [ "$config_data" != "null" ]; then
                local port=$(echo "$config_data" | jq -r '.port')
                local id=$(echo "$config_data" | jq -r '.uuid')
                [ -n "$port" ] && [ "$port" != "null" ] && vless_port=$port
                [ -n "$id" ] && [ "$id" != "null" ] && uuid=$id
                return 0
            fi
            ;;
        anytls)
            config_data=$(jq -r '.inbounds[] | select(.type == "anytls") | {port: .listen_port}' "${CONFIG_FILE}" 2>/dev/null)
            if [ -n "$config_data" ] && [ "$config_data" != "null" ]; then
                local port=$(echo "$config_data" | jq -r '.port')
                [ -n "$port" ] && [ "$port" != "null" ] && anytls_port=$port
                return 0
            fi
            ;;
        socks)
            config_data=$(jq -r '.inbounds[] | select(.type == "socks") | {port: .listen_port, username: .users[0].username, password: .users[0].password}' "${CONFIG_FILE}" 2>/dev/null)
            if [ -n "$config_data" ] && [ "$config_data" != "null" ]; then
                local port=$(echo "$config_data" | jq -r '.port')
                local user=$(echo "$config_data" | jq -r '.username')
                local pass=$(echo "$config_data" | jq -r '.password')
                [ -n "$port" ] && [ "$port" != "null" ] && socks_port=$port
                [ -n "$user" ] && [ "$user" != "null" ] && socks_username=$user
                [ -n "$pass" ] && [ "$pass" != "null" ] && socks_password=$pass
                return 0
            fi
            ;;
        http)
            config_data=$(jq -r '.inbounds[] | select(.type == "http") | {port: .listen_port, username: .users[0].username, password: .users[0].password}' "${CONFIG_FILE}" 2>/dev/null)
            if [ -n "$config_data" ] && [ "$config_data" != "null" ]; then
                local port=$(echo "$config_data" | jq -r '.port')
                local user=$(echo "$config_data" | jq -r '.username')
                local pass=$(echo "$config_data" | jq -r '.password')
                [ -n "$port" ] && [ "$port" != "null" ] && http_port=$port
                [ -n "$user" ] && [ "$user" != "null" ] && http_username=$user
                [ -n "$pass" ] && [ "$pass" != "null" ] && http_password=$pass
                return 0
            fi
            ;;
        snell)
            config_data=$(jq -r '.inbounds[] | select(.type == "snell") | {port: .listen_port, psk: .psk, version: .version}' "${CONFIG_FILE}" 2>/dev/null)
            if [ -n "$config_data" ] && [ "$config_data" != "null" ]; then
                local port=$(echo "$config_data" | jq -r '.port')
                local psk=$(echo "$config_data" | jq -r '.psk')
                local ver=$(echo "$config_data" | jq -r '.version')
                [ -n "$port" ] && [ "$port" != "null" ] && snell_port=$port
                [ -n "$psk" ] && [ "$psk" != "null" ] && snell_psk=$psk
                [ -n "$ver" ] && [ "$ver" != "null" ] && snell_version=$ver
                return 0
            fi
            ;;

    esac

    return 1
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

        case $protocol in
            hysteria2)
                local uri="hy2://${password}@${host_ip}:${hysteria_port}?insecure=1&&alpn=h3&sni=www.bing.com#${ip_country}-hy"
                echo -e "==== Hysteria2 ====\n${uri}\n"
                ;;
            shadowsocks)
                echo -e ""
                # 编码密码
                local encoded_password=$(urlencode "$ss_password")
                local uri="ss://2022-blake3-aes-256-gcm:${encoded_password}@${host_ip}:${shadowsocks_port}#${ip_country}-ss"
                echo -e "==== Shadowsocks ====\n${uri}\n"
                ;;
            vless)
                local uri="vless://${uuid}@${host_ip}:${vless_port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.tesla.com&fp=chrome&pbk=${public_key}&sid=123abc&type=tcp&headerType=none#${ip_country}-vless"
                echo -e "==== VLESS ====\n${uri}\n"
                ;;
            anytls)
                local uri="anytls://${public_key}@${host_ip}:${anytls_port}/?sni=www.bing.com&insecure=1&alpn=h2,http/1.1#${ip_country}-anytls"
                echo -e "==== AnyTLS ====\n${uri}\n"
                ;;
            socks)
                local uri="socks5://${socks_username}:${socks_password}@${host_ip}:${socks_port}#${ip_country}-socks5"
                echo -e "==== SOCKS5 代理 ====\n${uri}\n"
                ;;
            http)
                local uri="http://${http_username}:${http_password}@${host_ip}:${http_port}#${ip_country}-http"
                echo -e "==== HTTP 代理 ====\n${uri}\n"
                ;;
            snell)
                local uri="snell://${snell_psk}@${host_ip}:${snell_port}?version=${snell_version:-5}#${ip_country}-snell"
                echo -e "==== Snell ====\n${uri}\n"
                echo -e "Surge/Clash 格式:\n${ip_country}-snell = snell, ${host_ip}, ${snell_port}, psk = ${snell_psk}, version = ${snell_version:-5}\n"
                ;;
        esac
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

    # 检查 Hysteria2
    if jq -e '.inbounds[] | select(.type == "hysteria2")' "${CONFIG_FILE}" &>/dev/null; then
        available_protocols+=("hysteria2")
        protocol_names+=("Hysteria2")
    fi

    # 检查 VLESS
    if jq -e '.inbounds[] | select(.type == "vless")' "${CONFIG_FILE}" &>/dev/null; then
        available_protocols+=("vless")
        protocol_names+=("VLESS+Vision+Reality")
    fi

    # 检查 AnyTLS
    if jq -e '.inbounds[] | select(.type == "anytls")' "${CONFIG_FILE}" &>/dev/null; then
        available_protocols+=("anytls")
        protocol_names+=("AnyTLS")
    fi

    # 检查 Shadowsocks
    if jq -e '.inbounds[] | select(.type == "shadowsocks")' "${CONFIG_FILE}" &>/dev/null; then
        available_protocols+=("shadowsocks")
        protocol_names+=("Shadowsocks")
    fi

    # 检查 SOCKS5 代理
    if jq -e '.inbounds[] | select(.type == "socks")' "${CONFIG_FILE}" &>/dev/null; then
        available_protocols+=("socks")
        protocol_names+=("SOCKS5 代理")
    fi

    # 检查 HTTP 代理
    if jq -e '.inbounds[] | select(.type == "http")' "${CONFIG_FILE}" &>/dev/null; then
        available_protocols+=("http")
        protocol_names+=("HTTP 代理")
    fi

    # 检查 Snell
    if jq -e '.inbounds[] | select(.type == "snell")' "${CONFIG_FILE}" &>/dev/null; then
        available_protocols+=("snell")
        protocol_names+=("Snell")
    fi

    # 如果没有找到任何协议
    if [ ${#available_protocols[@]} -eq 0 ]; then
        echo -e "${YELLOW}配置文件中没有找到支持的协议配置${RESET}"
        return
    fi

    # 显示可用的协议选项
    echo -e "${CYAN}检测到以下协议配置，请选择要查看的协议（可多选，用空格分隔）:${RESET}"
    for i in "${!protocol_names[@]}"; do
        echo "$((i+1)). ${protocol_names[$i]}"
    done
    echo "$((${#protocol_names[@]}+1)). 全部"

    read -p "请输入选项编号: " choices

    local selected_protocols=()

    # 如果选择全部
    if [[ "$choices" == *"$((${#protocol_names[@]}+1))"* ]]; then
        selected_protocols=("${available_protocols[@]}")
    else
        # 根据选择添加协议
        for i in "${!available_protocols[@]}"; do
            if [[ "$choices" == *"$((i+1))"* ]]; then
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
    check_ss_command
    check_jq_command

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
    local current_config=$(cat "${CONFIG_FILE}")

    # 检查是否已存在 inbounds
    if ! echo "$current_config" | jq -e '.inbounds' &>/dev/null; then
        # 如果不存在 inbounds，创建一个空数组
        current_config=$(echo "$current_config" | jq '.inbounds = []')
    fi

    # 添加新的 Direct 配置到 inbounds
    local new_config=$(echo "$current_config" | jq --argjson item "$direct_config" '.inbounds += [$item]')

    # 验证 jq 操作是否成功
    if [ -z "$new_config" ] || [ "$new_config" == "null" ]; then
        echo -e "${RED}错误: 配置生成失败，jq 操作返回空值！${RESET}"
        return 1
    fi

    # 验证生成的配置是否为有效的 JSON
    if ! echo "$new_config" | jq empty 2>/dev/null; then
        echo -e "${RED}错误: 生成的配置不是有效的 JSON 格式！${RESET}"
        return 1
    fi

    # 备份当前配置
    cp "${CONFIG_FILE}" "${CONFIG_FILE}.backup"

    # 保存新配置
    echo "$new_config" > "${CONFIG_FILE}"

    # 验证写入的文件是否为有效的 JSON
    if ! jq empty "${CONFIG_FILE}" 2>/dev/null; then
        echo -e "${RED}错误: 写入配置文件失败，正在恢复备份...${RESET}"
        mv "${CONFIG_FILE}.backup" "${CONFIG_FILE}"
        return 1
    fi

    # 删除备份文件
    rm -f "${CONFIG_FILE}.backup"

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
    check_jq_command

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

            read -p "$(echo -e "${RED}确定要删除以上配置吗? (y/N) ${RESET}")" confirm
            confirm=${confirm:-N}

            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
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
            read -p "$(echo -e "${RED}确定要删除所有中转配置吗? (y/N) ${RESET}")" confirm
            confirm=${confirm:-N}

            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
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

    # 验证生成的配置是否为有效的 JSON
    if ! echo "$current_config" | jq empty 2>/dev/null; then
        echo -e "${RED}错误: 生成的配置不是有效的 JSON 格式！${RESET}"
        return 1
    fi

    # 备份当前配置
    cp "${CONFIG_FILE}" "${CONFIG_FILE}.backup"

    # 保存新配置
    echo "$current_config" > "${CONFIG_FILE}"

    # 验证写入的文件是否为有效的 JSON
    if ! jq empty "${CONFIG_FILE}" 2>/dev/null; then
        echo -e "${RED}错误: 写入配置文件失败，正在恢复备份...${RESET}"
        mv "${CONFIG_FILE}.backup" "${CONFIG_FILE}"
        return 1
    fi

    # 删除备份文件
    rm -f "${CONFIG_FILE}.backup"

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
    local node_types=("hysteria2" "vless" "anytls" "shadowsocks" "socks" "http" "snell")
    local available_nodes=()
    local node_display_names=()
    local node_info=()

    # 检查每种协议类型
    for node_type in "${node_types[@]}"; do
        # 获取该类型的所有节点
        local nodes=$(jq -r --arg type "$node_type" '.inbounds[]? | select(.type == $type) | "\(.type)|\(.listen_port)|\(.tag // "unknown")"' "${CONFIG_FILE}" 2>/dev/null)

        if [ -n "$nodes" ]; then
            while IFS='|' read -r type port tag; do
                available_nodes+=("$type")
                node_info+=("$type|$port|$tag")

                # 生成显示名称
                case $type in
                    hysteria2)
                        node_display_names+=("Hysteria2 (端口: $port)")
                        ;;
                    vless)
                        node_display_names+=("VLESS+Vision+Reality (端口: $port)")
                        ;;
                    anytls)
                        node_display_names+=("AnyTLS (端口: $port)")
                        ;;
                    shadowsocks)
                        node_display_names+=("Shadowsocks (端口: $port)")
                        ;;
                    socks)
                        node_display_names+=("SOCKS5 代理 (端口: $port)")
                        ;;
                    http)
                        node_display_names+=("HTTP 代理 (端口: $port)")
                        ;;
                    snell)
                        node_display_names+=("Snell (端口: $port)")
                        ;;
                esac
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
    if [[ "$choices" == *"$((${#node_display_names[@]}+1))"* ]]; then
        # 确认删除全部
        read -p "$(echo -e "${RED}确定要删除所有节点配置吗? 这将保留最小配置。(y/N) ${RESET}")" confirm
        confirm=${confirm:-N}

        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}已取消删除操作${RESET}"
            return 0
        fi

        nodes_to_delete=("${node_info[@]}")
    else
        # 根据选择添加要删除的节点
        for i in "${!available_nodes[@]}"; do
            if [[ "$choices" == *"$((i+1))"* ]]; then
                nodes_to_delete+=("${node_info[$i]}")
            fi
        done
    fi

    if [ ${#nodes_to_delete[@]} -eq 0 ]; then
        echo -e "${YELLOW}未选择任何节点${RESET}"
        return 0
    fi

    # 读取当前配置
    local current_config=$(cat "${CONFIG_FILE}")

    # 删除选中的节点
    for node in "${nodes_to_delete[@]}"; do
        IFS='|' read -r type port tag <<< "$node"

        # 从配置中删除该节点
        current_config=$(echo "$current_config" | jq --arg type "$type" --arg port "$port" \
            'del(.inbounds[] | select(.type == $type and .listen_port == ($port | tonumber)))')

        echo -e "${GREEN}已删除: $type (端口: $port)${RESET}"
    done

    # 保存新配置
    echo "$current_config" > "${CONFIG_FILE}"

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
            if [ ${sing_box_installed} -eq 0 ]; then
                uninstall_sing_box
            else
                echo -e "${YELLOW}sing-box 尚未安装！${RESET}"
            fi
            ;;
        3)
            if [ ${sing_box_installed} -eq 0 ]; then
                if [ ${sing_box_running} -eq 0 ]; then
                    stop_sing_box
                else
                    start_sing_box
                fi
            else
                echo -e "${RED}sing-box 尚未安装！${RESET}"
            fi
            ;;
        4)
            if [ ${sing_box_installed} -eq 0 ]; then
                restart_sing_box
            else
                echo -e "${RED}sing-box 尚未安装！${RESET}"
            fi
            ;;
        5)
            if [ ${sing_box_installed} -eq 0 ]; then
                status_sing_box
            else
                echo -e "${RED}sing-box 尚未安装！${RESET}"
            fi
            ;;
        6)
            if [ ${sing_box_installed} -eq 0 ]; then
                log_sing_box
            else
                echo -e "${RED}sing-box 尚未安装！${RESET}"
            fi
            ;;
        7)
            if [ ${sing_box_installed} -eq 0 ]; then
                generate_node_config
            else
                echo -e "${RED}sing-box 尚未安装！${RESET}"
            fi
            ;;
        8)
            if [ ${sing_box_installed} -eq 0 ]; then
                check_sing_box
            else
                echo -e "${RED}sing-box 尚未安装！${RESET}"
            fi
            ;;
        9)
            if [ ${sing_box_installed} -eq 0 ]; then
                delete_node_config
            else
                echo -e "${RED}sing-box 尚未安装！${RESET}"
            fi
            ;;
        10)
            if [ ${sing_box_installed} -eq 0 ]; then
                add_direct_config
            else
                echo -e "${RED}sing-box 尚未安装！${RESET}"
            fi
            ;;
        11)
            if [ ${sing_box_installed} -eq 0 ]; then
                view_direct_config
            else
                echo -e "${RED}sing-box 尚未安装！${RESET}"
            fi
            ;;
        12)
            if [ ${sing_box_installed} -eq 0 ]; then
                delete_direct_config
            else
                echo -e "${RED}sing-box 尚未安装！${RESET}"
            fi
            ;;
        13)
            check_bbr_status
            if [ $? -eq 0 ]; then
                disable_bbr
            else
                enable_bbr
            fi
            ;;
        14)
            show_config_source_info
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
