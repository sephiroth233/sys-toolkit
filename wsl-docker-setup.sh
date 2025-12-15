#!/bin/bash

# WSL Ubuntu + Docker 一键配置脚本
# 功能：安装 Docker 和 Docker Compose，并配置基础环境

set -e  # 遇到错误立即退出

echo -e "\033[34m[INFO] 开始 WSL Ubuntu + Docker 配置...\033[0m"

# 1. 更新系统
echo -e "\033[33m[STEP 1/6] 更新系统包...\033[0m"

sudo apt update && sudo apt upgrade -y

sudo apt install -y curl wget


# 2. 配置免密码sudo
echo -e "\033[33m[STEP 2/6] 配置免密码sudo...\033[0m"
sudo bash -c "echo '$USER ALL=(ALL) NOPASSWD: ALL' >/etc/sudoers.d/$USER"
sudo chmod 0440 /etc/sudoers.d/$USER

# 3. 安装Docker
echo -e "\033[33m[STEP 3/6] 安装Docker引擎...\033[0m"
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
else
    echo -e "\033[35m[NOTE] Docker 已安装，跳过此步骤\033[0m"
fi

# 4. 安装Docker Compose
echo -e "\033[33m[STEP 4/6] 安装Docker Compose...\033[0m"
COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# 5. 配置用户组和权限
echo -e "\033[33m[STEP 5/6] 配置用户组和权限...\033[0m"
sudo usermod -aG docker $USER
newgrp docker <<< "echo '[INFO] 用户组权限已更新'"

# 6. 配置Docker自启动
echo -e "\033[33m[STEP 6/6] 配置Docker自启动...\033[0m"
sudo systemctl enable docker

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