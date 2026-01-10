# sys-toolkit

系统管理和网络工具脚本集合，支持 Windows 和 Linux。

## 脚本列表

| 脚本 | 平台 | 功能 |
|------|------|------|
| `server-proxy.sh` | Linux | Sing-box / Snell 代理管理 |
| `mihomo-install.sh` | Linux | Mihomo 安装更新 |
| `wsl-docker-setup.sh` | Linux | WSL + Docker 配置 |
| `blash.cmd` | Windows | Clash 代理控制器 |
| `jdk.cmd` | Windows | JDK 环境配置 |
| `navicat-reset.cmd` | Windows | Navicat 试用重置 |

## 快速使用

```bash
# Linux (需要 sudo)
sudo ./server-proxy.sh
./mihomo-install.sh install

# Windows (管理员运行)
blash.cmd
jdk.cmd
```

## 注意

- Linux 脚本需要 `sudo` 权限，支持 Ubuntu/Debian/CentOS
- Windows 脚本需要管理员权限，支持 Win 7/10/11
- 部分脚本需要网络访问 GitHub
