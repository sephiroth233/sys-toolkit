# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**项目名称**: sys-toolkit

## 项目概述

这是一个系统管理和网络工具脚本集合仓库，包含Windows批处理脚本和Linux Shell脚本，主要用于：
- 网络代理配置和管理（Sing-box, Mihomo/Clash, Snell）
- 系统备份和云存储集成（Cloudflare R2 S3）
- 开发环境设置（JDK, Docker, WSL）
- 软件工具重置和清理（Navicat）

## 核心架构

### 统一入口架构
项目采用**主从架构**设计，`sys-toolkit.sh` 作为统一入口，负责：
1. **远程脚本管理**：从 GitHub 仓库动态下载和执行其他工具脚本
2. **缓存机制**：在 `/tmp/sys-toolkit` 目录缓存下载的脚本
3. **状态检查**：检查各工具组件的安装和运行状态
4. **交互式菜单**：提供统一的用户界面

### 脚本执行模式
- **直接执行**：`sudo ./server-proxy.sh` - 直接运行特定功能脚本
- **统一入口**：`sudo ./sys-toolkit.sh` - 通过主脚本选择功能
- **远程执行**：`bash <(curl -fsSL https://raw.githubusercontent.com/sephiroth233/sys-toolkit/master/sys-toolkit.sh)` - 一键远程执行

### 配置管理架构
- **Linux脚本**：配置文件存储在 `/etc/` 目录，如 `/etc/sing-box/config.json`
- **Windows脚本**：配置通过变量和注册表管理
- **用户配置**：与程序文件分离，支持自定义配置

## 常用开发命令

### 脚本开发和测试
```bash
# 1. 语法检查（所有脚本）
for script in *.sh; do echo "检查 $script:"; bash -n "$script" && echo "✓ 语法正确" || echo "✗ 语法错误"; done

# 2. 静态分析（需要安装shellcheck）
shellcheck *.sh

# 3. 测试脚本执行（不实际运行系统操作）
# 使用 --help 或 -h 参数测试脚本参数解析
./server-proxy.sh --help
./sys-toolkit.sh -h

# 4. 查看脚本依赖
grep -r "command -v" *.sh  # 查看所有依赖检查
grep -r "apt-get\|yum\|dnf" *.sh  # 查看包管理器使用

# 5. 验证远程下载功能
# 测试主脚本的远程下载逻辑
REPO_BASE_URL="https://raw.githubusercontent.com/sephiroth233/sys-toolkit/master"
curl -I "$REPO_BASE_URL/sys-toolkit.sh"
```

### 在Docker中测试Linux脚本
```bash
# 创建干净的测试环境
docker run --rm -it -v $(pwd):/scripts ubuntu:latest bash

# 在容器内进行完整测试流程
cd /scripts
bash -n *.sh  # 语法检查
./sys-toolkit.sh --help  # 测试帮助输出

# 测试特定功能（模拟环境）
# 使用环境变量模拟root权限
FAKE_ROOT=1 ./server-proxy.sh --dry-run
```

### Windows脚本测试
```cmd
REM 在Windows中测试批处理脚本
REM 1. 语法检查（使用cmd /?验证命令）
cmd /c "echo 测试模式" && blash.cmd --help

REM 2. 模拟管理员权限测试
REM 使用PowerShell模拟环境
powershell -Command "Start-Process cmd -Verb RunAs -ArgumentList '/c blash.cmd --test'"
```

### 调试和日志
```bash
# 启用详细输出调试脚本
bash -x server-proxy.sh install  # 跟踪执行过程

# 检查脚本执行时间
time ./sys-backup-restore.sh --dry-run

# 查看脚本生成的临时文件
ls -la /tmp/sys-toolkit/  # 主脚本缓存目录
ls -la /tmp/*.log 2>/dev/null  # 脚本日志文件
```

### 文件组织
```
sys-toolkit/
├── *.sh          # Linux Shell脚本（网络代理、系统工具）
├── *.cmd         # Windows批处理脚本
├── *.md          # 脚本使用文档
└── CLAUDE.md     # 本文件
```

## 脚本架构和设计模式

### 所有脚本共同的设计原则
1. **彩色输出**：使用ANSI颜色代码（RED, GREEN, YELLOW, BLUE, CYAN等）在脚本头部定义，提供直观的状态反馈
2. **模块化函数**：按功能拆分为独立函数（如`check_root()`, `install_*()`, `update_*()`, `validate_*()`)
3. **错误处理**：包含`set -e`或`set -o pipefail`，以及适当的错误检查和退出机制
4. **用户交互**：提供清晰的菜单选项和操作提示，大部分脚本支持交互式菜单和命令行参数两种使用方式

### Linux Shell脚本通用模式

**初始化阶段**（脚本头部）：
```bash
#!/bin/bash
set -e  # 错误退出
# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
# ... 其他颜色

# 常量定义（配置目录、服务名等）
CONFIG_DIR="/etc/service-name"
SERVICE_NAME="service-name"

# 权限检查函数
check_root() { ... }

# 初始化函数
init_system() { ... }
```

**功能实现模式**：
- **依赖检查**：`check_*_command()`检查必要工具（jq, curl, ss等），缺失时自动安装
- **系统检测**：检测Linux发行版（通过`/etc/os-release`）并设置对应的包管理器（apt/yum）
- **服务管理**：使用systemd的`systemctl`命令管理服务生命周期
- **配置管理**：配置文件通常存储在`/etc/`目录，使用`trap`命令清理临时文件
- **版本管理**：从GitHub API获取最新版本，支持安装/更新/卸载操作

**主脚本流程**：
```bash
# 权限检查
check_root
# 初始化系统（创建目录、检查依赖）
init_system
# 主菜单循环（处理用户选择）
main_menu()
```

### Windows批处理脚本特定模式（.cmd）
- **编码设置**：`chcp 65001`支持UTF-8输出
- **变量处理**：使用`setlocal enabledelayedexpansion`处理延迟变量扩展
- **配置管理**：通过变量控制功能开关
- **系统集成**：修改Windows注册表和环境变量

### 脚本特定功能模式

**统一入口脚本（sys-toolkit.sh）**：
- **远程管理架构**：从 `REPO_BASE_URL` 动态下载其他脚本到 `/tmp/sys-toolkit/` 缓存目录
- **模块化设计**：每个功能对应独立的脚本文件，主脚本仅负责调度
- **状态检查系统**：通过 `systemctl` 和命令检查各组件状态
- **缓存机制**：避免重复下载，支持离线模式（如果缓存存在）

**备份脚本（sys-backup-restore.sh）**：
- **配置文件路径**：`/etc/sys-backup/config.conf`
- **日志系统**：`/var/log/sys-backup/backup.log`（备份日志）和 `cron.log`（定时任务日志）
- **元数据管理**：JSON格式记录备份信息，便于查询和恢复
- **S3集成**：使用AWS CLI与Cloudflare R2进行交互
- **定时任务**：通过crontab管理自动备份

**网络代理脚本（server-proxy.sh）**：
- **多协议支持**：Sing-box（现代代理协议）和Snell（专有协议）
- **配置管理**：`/etc/sing-box/config.json` 和 `/etc/snell/snell-server.conf`
- **服务集成**：通过systemd管理 `sing-box` 和 `snell` 服务
- **配置导出**：生成可直接导入客户端的配置信息（URI格式）

**软件安装脚本（mihomo-install.sh）**：
- **版本管理**：从GitHub API获取最新版本信息，支持多架构（amd64/arm64）
- **二进制管理**：下载、验证、安装到 `/usr/local/bin/`
- **配置分离**：程序文件与用户配置分离，便于升级

**Windows批处理脚本架构**：
- **编码处理**：`chcp 65001` 确保UTF-8支持
- **变量扩展**：`setlocal enabledelayedexpansion` 处理动态变量
- **注册表操作**：通过 `reg` 命令管理Windows注册表
- **环境变量**：修改系统PATH和用户环境变量
- **服务管理**：通过 `sc` 命令管理Windows服务

## 开发工作流

### 修改脚本前的准备
1. **阅读现有代码**：理解架构模式和设计原则，查看相关的`.md`文档
2. **理解脚本的系统集成**：了解脚本涉及的配置目录、服务管理方式、权限要求

### 添加新功能或修复问题
1. **遵循现有模式**：
   - 使用相同的颜色定义和格式
   - 创建独立的函数，避免重复代码
   - 使用`log_info()`、`log_error()`等统一的日志函数（如果存在）

2. **错误处理**：
   - 确保所有可能的错误情况都有适当的检查和处理
   - 提供清晰的错误提示和返回状态码
   - 在系统级操作前验证权限和依赖

3. **用户交互**：
   - 保持菜单提示和交互提示的一致性
   - 支持命令行参数和交互式模式
   - 关键操作前提示用户确认（尤其是删除操作）

### 代码风格和约定

**Shell脚本规范**：
```bash
# 1. 文件头部结构（必须按此顺序）
#!/bin/bash
set -e  # 错误退出
# 颜色定义（使用标准ANSI颜色）
RED='\033[0;31m'
GREEN='\033[0;32m'
# ...
RESET='\033[0m'

# 2. 常量定义（全大写，下划线分隔）
CONFIG_DIR="/etc/service-name"
SERVICE_NAME="service-name"

# 3. 函数定义（小写加下划线，描述性名称）
check_root() { ... }
install_dependencies() { ... }

# 4. 主函数和入口
main() { ... }
main "$@"
```

**批处理脚本规范**：
```batch
@echo off
chcp 65001 >nul  # UTF-8编码
setlocal enabledelayedexpansion

REM 颜色定义（使用ANSI转义序列）
set "RED=[91m"
set "GREEN=[92m"

REM 主逻辑
call :main
exit /b 0

:main
REM 主函数逻辑
goto :eof
```

**通用约定**：
- **缩进**：4个空格（不使用制表符）
- **函数注释**：在函数上方用 `# 功能：` 格式说明
- **错误处理**：使用 `set -e` 和 `trap` 清理资源
- **用户提示**：关键操作前必须确认（删除、格式化等）
- **返回值**：成功返回0，失败返回非0，错误信息输出到stderr

### 测试流程和验证

**1. 语法和静态检查**：
```bash
# 批量检查所有脚本
for script in *.sh; do
    echo "=== 检查 $script ==="
    bash -n "$script" && echo "✓ 语法正确" || echo "✗ 语法错误"
    if command -v shellcheck &> /dev/null; then
        shellcheck "$script"
    fi
done

# 检查批处理脚本基本语法
for script in *.cmd; do
    echo "检查 $script"
    cmd /c "echo 测试" && echo "✓ 可执行" || echo "✗ 执行错误"
done
```

**2. 功能测试矩阵**：
```bash
# 测试不同参数组合
./server-proxy.sh --help
./server-proxy.sh install --dry-run
./server-proxy.sh status

# 测试主脚本的不同模式
./sys-toolkit.sh  # 交互式模式
./sys-toolkit.sh --help  # 帮助模式
./sys-toolkit.sh status  # 状态检查模式
```

**3. 边界和错误情况测试**：
```bash
# 测试权限不足
sudo -u nobody ./server-proxy.sh --help 2>&1 | grep -i "permission\|root"

# 测试网络不可用（模拟）
REPO_BASE_URL="http://invalid-url" ./sys-toolkit.sh status 2>&1 | grep -i "网络\|连接"

# 测试依赖缺失
# 临时移除curl测试错误处理
mv /usr/bin/curl /usr/bin/curl.bak 2>/dev/null || true
./sys-toolkit.sh --help 2>&1 | grep -i "curl"
mv /usr/bin/curl.bak /usr/bin/curl 2>/dev/null || true
```

**4. 集成测试**：
```bash
# 在Docker中完整测试流程
docker run --rm -it -v $(pwd):/scripts ubuntu:latest bash -c "
    cd /scripts
    echo '1. 安装依赖...'
    apt-get update && apt-get install -y curl jq
    echo '2. 语法检查...'
    bash -n *.sh
    echo '3. 测试主脚本...'
    ./sys-toolkit.sh --help
    echo '4. 测试代理脚本...'
    ./server-proxy.sh --help
"

# 测试Windows脚本（在WSL中）
if command -v cmd.exe &> /dev/null; then
    cmd.exe /c "blash.cmd --help"
fi
```

**5. 性能和安全测试**：
```bash
# 检查脚本执行时间
time ./sys-backup-restore.sh --dry-run

# 检查临时文件清理
./server-proxy.sh install --dry-run
ls -la /tmp/  # 检查是否留下临时文件

# 检查权限设置
find . -name "*.sh" -exec ls -la {} \;  # 检查执行权限
```

## 权限和系统要求

1. **权限要求**:
   - Linux脚本通常需要`sudo`权限执行系统级操作
   - Windows脚本可能需要管理员权限修改注册表

2. **系统兼容性**:
   - Windows脚本适用于Windows 7/10/11
   - Linux脚本主要针对Ubuntu/Debian/CentOS，通过自动化包管理器检测确保兼容性

3. **外部依赖**:
   - GitHub API访问（安装/更新脚本）
   - 网络连接（代理和备份脚本）
   - 特定命令工具（jq, curl, aws-cli, tar, gzip等）—— 脚本通常会自动检查和安装

## 快速参考

### 关键文件位置
- **主脚本**: `sys-toolkit.sh` - 统一入口
- **配置文件目录**: `/etc/` - 各服务的配置文件
- **日志目录**: `/var/log/` - 脚本运行日志
- **缓存目录**: `/tmp/sys-toolkit/` - 远程脚本缓存

### 常用开发工作流
1. **修改脚本** → `bash -n script.sh` → `shellcheck script.sh` → Docker测试
2. **添加功能** → 遵循现有模式 → 添加测试 → 更新文档
3. **修复bug** → 复现问题 → 添加测试用例 → 修复并验证

### 架构要点
- **主从架构**: `sys-toolkit.sh` 调度其他功能脚本
- **跨平台**: Shell脚本（Linux） + 批处理脚本（Windows）
- **远程管理**: 支持从GitHub动态下载和执行
- **配置分离**: 程序逻辑与用户配置分离

### 调试技巧
```bash
# 跟踪脚本执行
bash -x script.sh

# 检查环境变量
env | grep -i "sys\|toolkit"

# 查看系统服务状态
systemctl status sing-box snell fail2ban

# 检查脚本生成的临时文件
find /tmp -name "*sys-toolkit*" -o -name "*backup*" 2>/dev/null
```