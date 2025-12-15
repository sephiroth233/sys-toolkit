# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**项目名称**: sys-toolkit

## 项目概述

这是一个系统管理和网络工具脚本集合仓库，包含Windows批处理脚本和Linux Shell脚本，主要用于：
- 网络代理配置和管理（Sing-box, Mihomo/Clash）
- 开发环境设置（JDK, Docker, WSL）
- 软件工具重置和清理（Navicat）

## 文件结构

### Windows批处理脚本 (.cmd)
- `blash.cmd` - Clash网络代理控制器，支持代理模式切换、订阅管理
- `jdk.cmd` - JDK环境变量自动配置工具
- `navicat-reset.cmd` - Navicat Premium试用期重置工具

### Linux Shell脚本 (.sh)
- `sing-box.sh` - Sing-box代理服务安装和管理脚本
- `mihomo-install.sh` - Mihomo（原Clash.Meta）安装和更新脚本
- `wsl-docker-setup.sh` - WSL Ubuntu + Docker一键配置脚本

## 脚本使用说明

### 网络代理相关
1. **Sing-box** (`sing-box.sh`):
   ```bash
   # 安装和管理Sing-box
   sudo ./sing-box.sh
   ```

2. **Mihomo/Clash** (`mihomo-install.sh`):
   ```bash
   # 安装/更新Mihomo
   ./mihomo-install.sh install
   ./mihomo-install.sh update
   ./mihomo-install.sh version
   ```

3. **Clash控制器** (`blash.cmd`):
   ```cmd
   # Windows下运行
   blash.cmd
   ```

### 开发环境配置
1. **JDK环境** (`jdk.cmd`):
   ```cmd
   # 配置Java环境变量
   jdk.cmd
   ```

2. **WSL+Docker** (`wsl-docker-setup.sh`):
   ```bash
   # 在WSL Ubuntu中运行
   ./wsl-docker-setup.sh
   ```

### 工具维护
1. **Navicat重置** (`navicat-reset.cmd`):
   ```cmd
   # 重置Navicat Premium试用期
   navicat-reset.cmd
   ```

## 脚本特点

### Windows脚本 (.cmd)
- 使用`chcp 65001`支持UTF-8编码
- 使用`setlocal enabledelayedexpansion`处理变量延迟扩展
- 包含彩色输出和用户交互
- 修改Windows注册表和系统环境变量

### Linux脚本 (.sh)
- 需要root权限执行系统级操作
- 包含错误处理和清理机制
- 支持多种Linux发行版（apt/yum包管理器）
- 使用systemd管理服务

## 注意事项

1. **权限要求**:
   - Linux脚本通常需要`sudo`权限
   - Windows脚本可能需要管理员权限修改注册表

2. **系统兼容性**:
   - Windows脚本适用于Windows 7/10/11
   - Linux脚本主要针对Ubuntu/Debian/CentOS

3. **安全警告**:
   - 部分脚本会修改系统配置和环境变量
   - 运行前请了解脚本的具体操作
   - 建议在测试环境中先验证

4. **网络要求**:
   - 安装脚本需要访问GitHub API下载最新版本
   - 代理相关脚本需要网络连接

## 开发说明

此仓库为脚本集合，不包含传统的构建、测试流程。脚本直接执行，无需编译。

当修改脚本时：
1. 保持跨平台兼容性考虑
2. 添加适当的错误处理和用户提示
3. 使用一致的代码风格和注释
4. 测试在不同环境下的执行效果