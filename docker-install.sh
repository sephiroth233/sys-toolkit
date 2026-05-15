#!/usr/bin/env bash
set -euo pipefail

#===============================================================================
# Docker & Docker Compose 一键安装脚本
# 支持：正常环境安装 / 国内镜像加速安装
# 适用：Ubuntu / Debian / CentOS / RHEL / Rocky / AlmaLinux
#===============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()  { echo -e "${BLUE}==>${NC} $*"; }

require_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用 root 或 sudo 运行此脚本"
        exit 1
    fi
}

#-------------------------------------------------------------------------------
# 检测系统
#-------------------------------------------------------------------------------
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VERSION_CODENAME=${VERSION_CODENAME:-}
    else
        log_error "无法检测系统版本（/etc/os-release 不存在）"
        exit 1
    fi

    case "$OS" in
        ubuntu|debian) PKG_MGR="apt";;
        centos|rhel|rocky|almalinux) PKG_MGR="yum";;
        fedora) PKG_MGR="dnf";;
        *)
            log_error "不支持的系统: $OS"
            exit 1
            ;;
    esac

    log_info "检测到系统: $OS ($VERSION_CODENAME), 包管理器: $PKG_MGR"
}

#-------------------------------------------------------------------------------
# 卸载旧版本
#-------------------------------------------------------------------------------
remove_old() {
    log_step "清理旧版本 Docker..."
    case "$PKG_MGR" in
        apt)
            apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
            ;;
        yum|dnf)
            yum remove -y docker docker-client docker-client-latest docker-common \
                docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true
            ;;
    esac
    log_info "旧版本清理完成"
}

#-------------------------------------------------------------------------------
# 正常环境安装 (APT)
#-------------------------------------------------------------------------------
install_normal_apt() {
    log_step "使用 Docker 官方源安装..."

    apt-get update
    apt-get install -y ca-certificates curl

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/$OS/gpg" -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/$OS \
$VERSION_CODENAME stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

#-------------------------------------------------------------------------------
# 正常环境安装 (YUM)
#-------------------------------------------------------------------------------
install_normal_yum() {
    log_step "使用 Docker 官方源安装..."

    yum install -y yum-utils
    yum-config-manager --add-repo "https://download.docker.com/linux/$OS/docker-ce.repo"
    yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

#-------------------------------------------------------------------------------
# 国内环境安装 - 阿里云镜像源 (APT)
#-------------------------------------------------------------------------------
install_aliyun_apt() {
    log_step "使用阿里云镜像源安装..."

    rm -f /etc/apt/sources.list.d/docker.list
    apt-get update
    apt-get install -y ca-certificates curl

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://mirrors.aliyun.com/docker-ce/linux/$OS/gpg" -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://mirrors.aliyun.com/docker-ce/linux/$OS \
$VERSION_CODENAME stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

#-------------------------------------------------------------------------------
# 国内环境安装 - 清华 TUNA 镜像源 (APT)
#-------------------------------------------------------------------------------
install_tuna_apt() {
    log_step "使用清华大学 TUNA 镜像源安装..."

    rm -f /etc/apt/sources.list.d/docker.list
    apt-get update
    apt-get install -y ca-certificates curl

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/$OS/gpg" -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/$OS \
$VERSION_CODENAME stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

#-------------------------------------------------------------------------------
# 国内环境安装 (YUM) — 使用阿里云镜像
#-------------------------------------------------------------------------------
install_china_yum() {
    log_step "使用阿里云镜像源安装..."

    yum install -y yum-utils
    yum-config-manager --add-repo "https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo"
    yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

#-------------------------------------------------------------------------------
# 配置镜像加速器 (仅国内模式)
#-------------------------------------------------------------------------------
configure_registry_mirrors() {
    log_step "配置 Docker Hub 镜像加速器..."

    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<'EOF'
{
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://atomhub.openatom.cn",
    "https://docker.xuanyuan.me"
  ]
}
EOF

    systemctl daemon-reload
    systemctl restart docker
    log_info "镜像加速器配置完成，Docker 已重载并重启"
}

#-------------------------------------------------------------------------------
# 安装后配置
#-------------------------------------------------------------------------------
post_install() {
    log_step "启动 Docker 并设置开机自启..."
    systemctl start docker
    systemctl enable docker
    systemctl enable containerd

    log_step "配置非 root 用户权限..."
    groupadd -f docker
    local target_user="${SUDO_USER:-$USER}"
    if [[ "$target_user" != "root" ]]; then
        usermod -aG docker "$target_user"
        log_info "用户 '$target_user' 已加入 docker 组"
    fi
}

#-------------------------------------------------------------------------------
# 验证安装
#-------------------------------------------------------------------------------
verify_install() {
    log_step "验证安装..."

    echo ""
    echo "Docker 版本:"
    docker --version

    echo ""
    echo "Docker Compose 版本:"
    docker compose version

    echo ""
    if command -v systemctl &>/dev/null && systemctl is-active --quiet docker; then
        log_info "Docker 服务运行正常"
    else
        log_warn "Docker 服务可能未运行"
    fi

    echo ""
    log_step "拉取测试镜像 hello-world..."
    if docker run --rm hello-world; then
        log_info "安装验证成功！Docker 工作正常。"
    else
        log_warn "hello-world 拉取失败，可能是网络问题，Docker 本身已安装完成。"
    fi
}

#-------------------------------------------------------------------------------
# 卸载 Docker
#-------------------------------------------------------------------------------
uninstall_docker() {
    echo ""
    echo "============================================"
    echo "           卸载 Docker 及相关配置"
    echo "============================================"
    echo ""
    log_warn "此操作将执行以下步骤:"
    echo "  - 停止 Docker 及相关服务"
    echo "  - 卸载 Docker Engine、CLI、Compose 插件等所有包"
    echo "  - 删除 /var/lib/docker (镜像、容器、卷等数据)"
    echo "  - 删除 /var/lib/containerd"
    echo "  - 删除 Docker APT/YUM 源配置"
    echo "  - 删除 GPG 密钥"
    echo "  - 删除 /etc/docker 目录 (含 daemon.json)"
    echo "  - 删除独立 docker-compose 二进制文件 (如有)"
    echo ""
    read -rp "确认卸载? [y/N]: " confirm
    if [[ ! "${confirm,,}" =~ ^y ]]; then
        log_info "已取消卸载"
        exit 0
    fi

    log_step "停止 Docker 相关服务..."
    systemctl stop docker 2>/dev/null || true
    systemctl stop docker.socket 2>/dev/null || true
    systemctl stop containerd 2>/dev/null || true
    systemctl disable docker 2>/dev/null || true
    systemctl disable containerd 2>/dev/null || true

    log_step "卸载 Docker 软件包..."
    case "$PKG_MGR" in
        apt)
            apt-get purge -y docker-ce docker-ce-cli containerd.io \
                docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
            apt-get autoremove -y --purge 2>/dev/null || true
            ;;
        yum|dnf)
            yum remove -y docker-ce docker-ce-cli containerd.io \
                docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
            ;;
    esac

    log_step "删除 Docker APT/YUM 源配置..."
    rm -f /etc/apt/sources.list.d/docker.list
    rm -f /etc/apt/keyrings/docker.asc
    rm -f /etc/yum.repos.d/docker-ce.repo

    log_step "删除 Docker 数据目录..."
    rm -rf /var/lib/docker
    rm -rf /var/lib/containerd

    log_step "删除 Docker 配置目录..."
    rm -rf /etc/docker

    log_step "删除独立 docker-compose 二进制文件 (如有)..."
    rm -f /usr/local/bin/docker-compose
    rm -f /usr/bin/docker-compose

    log_step "清理残留的 Docker 网络接口..."
    ip link delete docker0 2>/dev/null || true

    log_info "卸载完成。Docker 及相关配置已全部移除。"
}

#-------------------------------------------------------------------------------
# 主菜单
#-------------------------------------------------------------------------------
main_menu() {
    echo ""
    echo "============================================"
    echo "   Docker & Docker Compose 一键安装脚本"
    echo "============================================"
    echo ""
    echo "请选择操作:"
    echo ""
    echo "  1) 正常环境安装（使用 Docker 官方源）"
    echo "  2) 国内环境安装（使用国内镜像源 + 加速器）"
    echo "  3) 卸载 Docker（完全移除）"
    echo "  4) 退出"
    echo ""

    read -rp "请输入选项 [1-4]: " choice

    case "$choice" in
        1) ACTION="install"; INSTALL_MODE="normal" ;;
        2) ACTION="install"; INSTALL_MODE="china" ;;
        3) ACTION="uninstall" ;;
        4) log_info "已退出"; exit 0 ;;
        *) log_error "无效选项"; exit 1 ;;
    esac

    # 国内模式下选择镜像源
    if [[ "$ACTION" == "install" && "$INSTALL_MODE" == "china" ]] && [[ "$PKG_MGR" == "apt" ]]; then
        echo ""
        echo "请选择国内镜像源:"
        echo "  1) 阿里云镜像源（推荐）"
        echo "  2) 清华大学 TUNA 镜像源"
        echo ""
        read -rp "请输入选项 [1-2]: " mirror_choice
        case "$mirror_choice" in
            1) MIRROR_SRC="aliyun" ;;
            2) MIRROR_SRC="tuna" ;;
            *) log_error "无效选项"; exit 1 ;;
        esac
    fi
}

#-------------------------------------------------------------------------------
# 执行安装
#-------------------------------------------------------------------------------
run_install() {
    if [[ "$INSTALL_MODE" == "normal" ]]; then
        case "$PKG_MGR" in
            apt) install_normal_apt ;;
            yum|dnf) install_normal_yum ;;
        esac
    elif [[ "$INSTALL_MODE" == "china" ]]; then
        case "$PKG_MGR" in
            apt)
                case "$MIRROR_SRC" in
                    aliyun) install_aliyun_apt ;;
                    tuna)   install_tuna_apt ;;
                esac
                ;;
            yum|dnf) install_china_yum ;;
        esac
        configure_registry_mirrors
    fi
}

#-------------------------------------------------------------------------------
# 主流程
#-------------------------------------------------------------------------------
main() {
    require_root
    detect_os
    main_menu

    if [[ "$ACTION" == "uninstall" ]]; then
        uninstall_docker
        exit 0
    fi

    remove_old
    run_install
    post_install
    verify_install

    echo ""
    log_info "安装完成！"
    if [[ "$INSTALL_MODE" == "china" ]]; then
        log_info "已配置镜像加速器: docker.1ms.run / atomhub.openatom.cn / docker.xuanyuan.me"
    fi
    if [[ "${SUDO_USER:-}" != "" ]] && [[ "${SUDO_USER:-}" != "root" ]]; then
        log_info "自动激活 docker 组权限..."
        exec newgrp docker
    fi
}

main "$@"
