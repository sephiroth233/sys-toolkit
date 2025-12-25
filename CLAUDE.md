# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**项目名称**: sys-toolkit

## 项目概述

这是一个系统管理和网络工具脚本集合仓库，包含Windows批处理脚本和Linux Shell脚本，主要用于：
- 网络代理配置和管理（Sing-box, Mihomo/Clash, Snell）
- 系统备份和云存储集成（Cloudflare R2 S3）
- 开发环境设置（JDK, Docker, WSL）
- 软件工具重置和清理（Navicat）

## 常用开发命令

### 脚本语法检查和验证
```bash
# 检查Shell脚本语法
bash -n server-proxy.sh
bash -n sys-backup.sh
bash -n mihomo-install.sh

# 使用shellcheck进行静态分析（如已安装）
shellcheck server-proxy.sh
shellcheck sys-backup.sh
```

### 在Docker中测试Linux脚本
```bash
# 创建测试环境
docker run --rm -it -v $(pwd):/scripts ubuntu:latest bash

# 在容器内运行脚本进行测试
bash -n /scripts/server-proxy.sh
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

**备份脚本（sys-backup.sh）**：
- 配置文件路径：`/etc/sys-backup/config.conf`
- 日志分类：`/var/log/sys-backup/backup.log`（备份日志）和`cron.log`（定时任务日志）
- 元数据管理：JSON格式记录备份信息，便于查询和恢复
- S3集成：使用AWS CLI与Cloudflare R2进行交互
- 核心功能模块：配置管理、备份操作、定时任务管理

**网络代理脚本（server-proxy.sh）**：
- 支持多种代理服务：Sing-box和Snell
- 配置文件路径：`/etc/sing-box/config.json`和`/etc/snell/snell-server.conf`
- 服务集成：通过systemd管理多个服务
- 配置导出：生成可直接使用的配置信息供用户导入客户端

**软件安装脚本（mihomo-install.sh）**：
- GitHub发布版本管理：从GitHub API获取最新版本信息
- 二进制下载和安装：支持多架构（amd64/arm64等）
- 配置文件管理：用户配置与程序文件分离

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

### 代码风格
- **Shell脚本**：使用4空格缩进，函数名使用小写加下划线
- **批处理脚本**：使用REM注释，重要配置放在文件开头
- **颜色定义**：统一使用脚本头部定义的颜色变量
- **注释**：清晰标记代码块用途，使用`=== 块标题 ===`格式

### 测试流程
1. **语法检查**（在修改前后）：
   ```bash
   bash -n script.sh
   shellcheck script.sh  # 如已安装
   ```

2. **功能测试**（在安全环境中）：
   - 在Docker容器内测试Linux脚本
   - 在Windows虚拟机或WSL中测试.cmd文件

3. **边界情况测试**：
   - 缺失依赖时的行为
   - 权限不足时的错误提示
   - 网络不可用时的处理
   - 配置文件不存在或损坏的处理

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