#!/bin/bash

# WSL Ubuntu + Docker 一键配置脚本
# 功能：安装 Docker 和 Docker Compose，并配置基础环境

set -euo pipefail

if ! grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
    echo -e "\033[31m[ERROR] 此脚本只能在 WSL 中运行。\033[0m"
    exit 1
fi

if [ ! -r /etc/os-release ]; then
    echo -e "\033[31m[ERROR] 无法识别 Linux 发行版。\033[0m"
    exit 1
fi

. /etc/os-release
if [ "${ID:-}" != "ubuntu" ]; then
    echo -e "\033[31m[ERROR] 此脚本仅支持 WSL Ubuntu，当前系统: ${ID:-unknown}。\033[0m"
    exit 1
fi

if [ "$(id -u)" -eq 0 ]; then
    TARGET_USER="${SUDO_USER:-}"
    if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = "root" ]; then
        echo -e "\033[31m[ERROR] 请从普通用户账户使用 sudo 运行此脚本。\033[0m"
        exit 1
    fi
else
    TARGET_USER="$USER"
    if ! command -v sudo &>/dev/null; then
        echo -e "\033[31m[ERROR] 未找到 sudo，请先安装 sudo。\033[0m"
        exit 1
    fi
fi

if ! id "$TARGET_USER" &>/dev/null; then
    echo -e "\033[31m[ERROR] 目标用户不存在: $TARGET_USER。\033[0m"
    exit 1
fi

run_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

if ! systemctl show-environment &>/dev/null; then
    echo -e "\033[31m[ERROR] WSL 尚未启用 systemd，请先在 /etc/wsl.conf 中启用后重启 WSL。\033[0m"
    exit 1
fi

echo -e "\033[34m[INFO] 开始 WSL Ubuntu + Docker 配置...\033[0m"

# 1. 更新系统
echo -e "\033[33m[STEP 1/6] 更新系统包...\033[0m"

run_root apt-get update
run_root apt-get upgrade -y

run_root apt-get install -y curl wget


# 2. 配置免密码sudo
echo -e "\033[33m[STEP 2/6] 配置免密码sudo...\033[0m"
printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$TARGET_USER" | run_root tee "/etc/sudoers.d/$TARGET_USER" >/dev/null
run_root chmod 0440 "/etc/sudoers.d/$TARGET_USER"

# 3. 安装Docker
echo -e "\033[33m[STEP 3/6] 安装Docker引擎...\033[0m"
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
else
    echo -e "\033[35m[NOTE] Docker 已安装，跳过此步骤\033[0m"
fi

# 4. 安装Docker Compose
echo -e "\033[33m[STEP 4/6] 安装Docker Compose...\033[0m"
COMPOSE_VERSION=$(curl -fsSL https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name"' | head -n 1 | cut -d'"' -f4)
if [ -z "$COMPOSE_VERSION" ]; then
    echo -e "\033[31m[ERROR] 无法获取 Docker Compose 最新版本。\033[0m"
    exit 1
fi
COMPOSE_OS=$(uname -s | tr '[:upper:]' '[:lower:]')
COMPOSE_ARCH=$(uname -m)
run_root curl -fL "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-${COMPOSE_OS}-${COMPOSE_ARCH}" -o /usr/local/bin/docker-compose
run_root chmod +x /usr/local/bin/docker-compose

# 5. 配置用户组和权限
echo -e "\033[33m[STEP 5/6] 配置用户组和权限...\033[0m"
run_root usermod -aG docker "$TARGET_USER"

# 6. 配置Docker自启动
echo -e "\033[33m[STEP 6/6] 配置Docker自启动...\033[0m"
run_root systemctl enable docker

# 验证安装
echo -e "\n\033[32m[SUCCESS] 安装完成！正在验证...\033[0m"
docker --version
docker-compose --version


echo -e "\n\033[32m✅ 所有配置已完成！\033[0m"
echo -e "请手动执行以下操作："
echo -e "1. 在Windows开机启动文件夹创建 wsl-startup.vbs 文件"
echo -e "2. 内容为: set ws=wscript.CreateObject(\"wscript.shell\")"
echo -e "            ws.run \"wsl -d Ubuntu\", 0"
echo -e "3. 按 Win+R 输入 shell:startup 可快速找到启动文件夹"


echo -e "\n\033[31m⚠️ 重要提示：\033[0m"
echo -e "当前终端会话的docker权限尚未生效，请执行以下操作之一："
echo -e "1. 完全退出当前WSL会话并重新登录 (执行 'exit')"
echo -e "2. 或者打开新的WSL终端窗口"
echo -e "\n验证命令: docker ps"
