# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**项目名称**: sys-toolkit

## 项目概述

这是一个系统管理和网络工具脚本集合仓库，包含Windows批处理脚本和Linux Shell脚本，主要用于：
- 网络代理配置和管理（Sing-box, Mihomo/Clash, Snell）
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
- `Snell.sh` - Snell代理服务安装和管理脚本

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

3. **Snell** (`Snell.sh`):
   ```bash
   # 安装和管理Snell代理服务
   sudo ./Snell.sh
   ```

4. **Clash控制器** (`blash.cmd`):
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

## 脚本架构和设计模式

### 共同特点
所有脚本都遵循以下设计原则：
1. **彩色输出**：使用ANSI颜色代码提供直观的状态反馈
2. **错误处理**：包含适当的错误检查和退出机制
3. **用户交互**：提供清晰的菜单和操作提示
4. **权限检查**：Linux脚本检查root权限，Windows脚本提示管理员权限

### Linux脚本架构模式
1. **模块化函数**：脚本按功能拆分为独立函数（如`check_root()`, `install_*()`, `update_*()`）
2. **系统检测**：自动检测Linux发行版（Debian/Ubuntu vs CentOS/RHEL）并适配包管理器
3. **服务管理**：使用systemd管理服务，包含启动、停止、状态检查
4. **临时文件清理**：使用`trap`命令确保临时文件被正确清理
5. **版本管理**：从GitHub API获取最新版本，支持安装、更新、卸载

### Windows脚本架构模式
1. **编码设置**：使用`chcp 65001`支持UTF-8输出
2. **变量处理**：使用`setlocal enabledelayedexpansion`处理延迟扩展
3. **配置管理**：通过变量控制功能开关（如`enableshortcut`, `verifyconf`）
4. **注册表操作**：修改Windows注册表和环境变量

### 网络代理脚本特定模式
1. **自动配置生成**：随机生成端口和密钥
2. **系统集成**：创建专用用户和systemd服务文件
3. **配置导出**：生成可直接使用的配置信息
4. **状态检查**：检查服务运行状态和版本信息

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

## 开发命令和测试

### 脚本验证
由于这是脚本集合项目，没有传统的构建流程。开发时主要关注：

1. **语法检查**：
   ```bash
   # 检查Shell脚本语法
   bash -n script.sh

   # 使用shellcheck进行静态分析
   shellcheck script.sh
   ```

2. **测试执行**：
   ```bash
   # 在安全环境中测试脚本（如Docker容器）
   docker run --rm -it -v $(pwd):/scripts ubuntu:latest bash
   ```

3. **Windows脚本测试**：
   - 在Windows虚拟机或WSL中测试.cmd文件
   - 使用`cmd /c "script.cmd"`执行

### 开发工作流
1. **修改脚本前**：先阅读现有代码，理解架构模式
2. **添加新功能**：遵循现有的函数模块化模式
3. **错误处理**：确保所有可能的错误情况都有适当的处理
4. **用户提示**：保持一致的彩色输出和提示信息风格
5. **跨平台考虑**：如果添加新脚本，考虑Windows和Linux的差异

### 代码风格
- **Shell脚本**：使用4空格缩进，函数名使用小写加下划线
- **批处理脚本**：使用REM注释，重要配置放在文件开头
- **颜色定义**：使用一致的ANSI颜色代码（RED, GREEN, YELLOW等）
- **错误退出**：使用`exit 1`表示失败，`exit 0`表示成功

## 开发说明

此仓库为脚本集合，不包含传统的构建、测试流程。脚本直接执行，无需编译。

当修改脚本时：
1. 保持跨平台兼容性考虑
2. 添加适当的错误处理和用户提示
3. 使用一致的代码风格和注释
4. 测试在不同环境下的执行效果