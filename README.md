# sys-toolkit

系统管理和网络工具脚本集合，支持 Linux、macOS 和 Windows。

## 目录

- [统一入口](#统一入口)
- [网络代理 (Sing-box / Snell)](#网络代理-sing-box--snell)
- [系统备份恢复 (rclone)](#系统备份恢复-rclone)
- [fail2ban 管理](#fail2ban-管理)
- [Docker 安装](#docker-安装)
- [Mihomo 安装 (macOS)](#mihomo-安装-macos)
- [Mihomo 守护进程 (macOS)](#mihomo-守护进程-macos)
- [WSL + Docker 配置](#wsl--docker-配置)
- [图床工具 (img)](#图床工具-img)
- [Windows 工具](#windows-工具)

## 统一入口

`sys-toolkit.sh` 是统一入口，自动从 GitHub 下载并执行 fail2ban、代理、备份、Docker 等子工具。

```bash
curl -fsSL https://raw.githubusercontent.com/sephiroth233/sys-toolkit/master/sys-toolkit.sh -o sys-toolkit.sh
chmod +x sys-toolkit.sh
sudo ./sys-toolkit.sh
```

要求：Linux（systemd），root 权限，curl。

## 网络代理 (Sing-box / Snell)

Sing-box（Hysteria2 / Shadowsocks2022 / VLESS+Reality / AnyTLS / SOCKS5 / HTTP）和 Snell 代理的安装、配置、节点管理与中转。

```bash
curl -fsSL https://raw.githubusercontent.com/sephiroth233/sys-toolkit/master/server-proxy.sh -o server-proxy.sh
chmod +x server-proxy.sh
sudo ./server-proxy.sh
```

要求：Linux（systemd），root 权限。

## 系统备份恢复 (rclone)

基于 rclone 的系统备份与恢复，支持 S3 / Cloudflare R2 / 阿里云 OSS / 腾讯云 COS 等云存储。

```bash
curl -fsSL https://raw.githubusercontent.com/sephiroth233/sys-toolkit/master/sys-backup-restore.sh -o sys-backup-restore.sh
chmod +x sys-backup-restore.sh
sudo ./sys-backup-restore.sh
```

要求：Linux（systemd），root 权限。

## fail2ban 管理

fail2ban 入侵检测和防护的安装、配置、Jail 与 IP 管理。

```bash
curl -fsSL https://raw.githubusercontent.com/sephiroth233/sys-toolkit/master/fail2ban-manager.sh -o fail2ban-manager.sh
chmod +x fail2ban-manager.sh
sudo ./fail2ban-manager.sh
```

要求：Linux（systemd），root 权限。

## Docker 安装

Docker 与 Docker Compose 一键安装，支持国内镜像源（阿里云 / 清华 TUNA）。

```bash
curl -fsSL https://raw.githubusercontent.com/sephiroth233/sys-toolkit/master/docker-install.sh -o docker-install.sh
chmod +x docker-install.sh
sudo ./docker-install.sh
```

要求：Linux（Ubuntu/Debian/CentOS/RHEL/Rocky/Alma），root 权限。

## Mihomo 安装 (macOS)

macOS 上 Mihomo（Clash Meta 内核）的安装与更新。

```bash
curl -fsSL https://raw.githubusercontent.com/sephiroth233/sys-toolkit/master/mihomo-install.sh -o mihomo-install.sh
chmod +x mihomo-install.sh
sudo ./mihomo-install.sh install
```

要求：macOS，sudo 权限。

## Mihomo 守护进程 (macOS)

macOS 上 mihomo 的 LaunchDaemon 服务管理器，支持安装、启停、日志查看、配置切换、内核更新。

```bash
curl -fsSL https://raw.githubusercontent.com/sephiroth233/sys-toolkit/master/mihomo-daemon.sh -o mihomo-daemon.sh
chmod +x mihomo-daemon.sh

sudo ./mihomo-daemon.sh install [--config /path/to/config.yaml] [--bin /path/to/mihomo]
sudo ./mihomo-daemon.sh start
sudo ./mihomo-daemon.sh stop
sudo ./mihomo-daemon.sh restart
sudo ./mihomo-daemon.sh status
sudo ./mihomo-daemon.sh logs
sudo ./mihomo-daemon.sh config-use /path/to/config.yaml
sudo ./mihomo-daemon.sh config-path
sudo ./mihomo-daemon.sh core-install
sudo ./mihomo-daemon.sh core-update
sudo ./mihomo-daemon.sh core-version
sudo ./mihomo-daemon.sh uninstall
```

要求：macOS，sudo 权限。详细文档见 [`mihomo-daemon.md`](mihomo-daemon.md)。

## WSL + Docker 配置

WSL 环境下的 Docker 辅助配置。

```bash
curl -fsSL https://raw.githubusercontent.com/sephiroth233/sys-toolkit/master/wsl-docker-setup.sh -o wsl-docker-setup.sh
chmod +x wsl-docker-setup.sh
sudo ./wsl-docker-setup.sh
```

要求：WSL (Ubuntu)。

## 图床工具 (img)

通用 S3 / Cloudflare R2 图床工具箱，支持上传、剪贴板粘贴、删除，也可作为 Typora 自定义上传器。

```bash
curl -fsSL https://raw.githubusercontent.com/sephiroth233/sys-toolkit/master/img.sh -o img.sh
chmod +x img.sh

# 方式一：直接执行（Typora 兼容）
./img.sh cat.png

# 方式二：source 后使用 img 子命令（交互更友好）
source img.sh
img setup               # 引导式初始化配置
img up    cat.png       # 上传文件 → 输出公开 URL
img pup                 # 上传剪贴板图片 (macOS)
img rm    <url|key>     # 删除远程图片
img uninstall           # 彻底卸载
```

要求：macOS，Homebrew（用于自动安装 AWS CLI），S3 兼容存储（Cloudflare R2 / AWS S3 等）。

## Windows 工具

- `navicat-reset.cmd` — Navicat 试用重置
