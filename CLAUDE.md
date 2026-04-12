# CLAUDE.md

系统管理和网络工具脚本集合，包含 Linux Shell 脚本和 Windows 批处理脚本。

## 项目概述

**功能范围**：网络代理（Sing-box, Mihomo/Clash, Snell）、系统备份（Cloudflare R2/S3）、开发环境（JDK, Docker, WSL）、工具清理（Navicat）

**架构**：`sys-toolkit.sh` 作为统一入口，动态从 GitHub 下载子脚本到 `/tmp/sys-toolkit/` 缓存后执行。

**文件结构**：`*.sh`（Linux）、`*.cmd`（Windows）、`*.md`（文档）

## 关键路径

| 用途 | 路径 |
|------|------|
| 配置文件 | `/etc/<service>/` |
| 日志 | `/var/log/` |
| 脚本缓存 | `/tmp/sys-toolkit/` |
| 代理配置 | `/etc/sing-box/config.json`、`/etc/snell/snell-server.conf` |
| 备份配置 | `/etc/sys-backup/config.conf` |

## 快速检查命令

```bash
bash -n *.sh                    # 语法检查
shellcheck *.sh                 # 静态分析
bash -x script.sh               # 调试跟踪
systemctl status sing-box snell # 服务状态
```

## 代码约定

**Shell 脚本头部顺序**（必须遵守）：
1. `#!/bin/bash` + `set -e`
2. ANSI 颜色常量（`RED GREEN YELLOW CYAN RESET`）
3. 全大写常量（`CONFIG_DIR SERVICE_NAME`）
4. 函数定义（`check_root` → `init_system` → 功能函数）
5. `main "$@"`

**通用模式**：`check_root()` 验权 → `init_system()` 初始化 → 交互菜单或命令行参数分发

**Windows .cmd**：`chcp 65001` + `setlocal enabledelayedexpansion`，用 `reg`/`sc` 操作注册表和服务。

## 开发工作流

修改前必须先读懂现有代码，遵循已有的颜色定义、函数命名、日志风格。

```bash
# 标准流程
bash -n script.sh && shellcheck script.sh
docker run --rm -it -v $(pwd):/scripts ubuntu:latest bash  # 集成测试
```

---

> **详细信息**：子脚本架构、完整测试矩阵、权限要求等见各 `*.md` 文档或 CLAUDE.md git 历史。
