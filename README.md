# sys-toolkit

系统管理和网络工具脚本集合，支持 Linux、macOS 和 Windows。

## 目录

- [统一入口](#统一入口)
- [网络代理 (Sing-box / Snell)](#网络代理-sing-box--snell)
- [系统备份恢复 (rclone)](#系统备份恢复-rclone)
- [fail2ban 管理](#fail2ban-管理)
- [Docker 安装](#docker-安装)
- [Mihomo 安装 (macOS)](#mihomo-安装-macos)
- [WSL + Docker 配置](#wsl--docker-配置)
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

## WSL + Docker 配置

WSL 环境下的 Docker 辅助配置。

```bash
curl -fsSL https://raw.githubusercontent.com/sephiroth233/sys-toolkit/master/wsl-docker-setup.sh -o wsl-docker-setup.sh
chmod +x wsl-docker-setup.sh
sudo ./wsl-docker-setup.sh
```

要求：WSL (Ubuntu)。

## Windows 工具

| 脚本 | 功能 |
|------|------|
| `blash.cmd` | Clash 代理控制器 |
| `jdk.cmd` | JDK 环境配置 |
| `navicat-reset.cmd` | Navicat 试用重置 |

需管理员权限，支持 Windows 7/10/11。
