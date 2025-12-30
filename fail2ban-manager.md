# fail2ban 管理工具使用说明

## 概述

`fail2ban-manager.sh` 是一个完整的 fail2ban 入侵检测和防护系统管理脚本，提供自动安装、配置和运维功能。该脚本遵循 sys-toolkit 项目的设计规范，支持多个 Linux 发行版。

## 功能特性

### 核心功能
- ✅ **自动安装**：支持 Debian/Ubuntu、CentOS/RHEL、Arch、openSUSE
- ✅ **配置管理**：自动生成优化的 jail.local 配置
- ✅ **服务管理**：启动、停止、重启、状态查询
- ✅ **Jail 管理**：查看和管理 Jail 状态
- ✅ **IP 管理**：手动禁封/解禁 IP 地址
- ✅ **配置备份**：自动备份和恢复功能
- ✅ **日志查看**：实时日志和历史日志查看
- ✅ **完整菜单**：交互式和命令行两种使用方式

### 支持的系统
| 系统 | 包管理器 | 状态 |
|------|---------|------|
| Ubuntu/Debian | apt-get | ✅ 支持 |
| CentOS/RHEL 7 | yum | ✅ 支持 |
| CentOS/RHEL 8+ | dnf | ✅ 支持 |
| Arch Linux | pacman | ✅ 支持 |
| openSUSE | zypper | ✅ 支持 |

## 安装和使用

### 前置要求
- Linux 系统（Ubuntu 18.04+、Debian 10+、CentOS 7+、Arch、openSUSE）
- Root 权限或 sudo 能力
- 网络连接（用于下载 fail2ban）

### 快速开始

#### 1. 下载脚本
```bash
# 已在 sys-toolkit 项目中
cd /path/to/sys-toolkit
```

#### 2. 安装 fail2ban
```bash
sudo ./fail2ban-manager.sh install
```

这将：
1. 检测系统的包管理器
2. 自动安装 fail2ban
3. 生成优化的 jail.local 配置
4. 启用并启动 fail2ban 服务

#### 3. 查看安装结果
```bash
sudo ./fail2ban-manager.sh status
```

## 使用方法

### 交互式菜单模式

不带参数运行脚本以进入交互式菜单：

```bash
sudo ./fail2ban-manager.sh
```

菜单选项：

```
========== 服务管理 ==========
1. 安装 fail2ban
2. 卸载 fail2ban
3. 停止/启动服务
4. 重启服务
5. 查看服务状态

========== Jail 和 IP 管理 ==========
6. 查看所有 Jail 状态
7. 查看被禁封的 IP
8. 手动禁封 IP
9. 手动解禁 IP

========== 配置管理 ==========
10. 查看配置
11. 编辑配置
12. 备份配置
13. 恢复备份

========== 日志管理 ==========
14. 查看最近日志
15. 查看实时日志

========== 其他 ==========
16. 查看帮助
0. 退出
```

### 命令行模式

直接使用命令执行特定操作：

```bash
# 安装
sudo ./fail2ban-manager.sh install

# 服务管理
sudo ./fail2ban-manager.sh start
sudo ./fail2ban-manager.sh stop
sudo ./fail2ban-manager.sh restart
sudo ./fail2ban-manager.sh status

# Jail 管理
sudo ./fail2ban-manager.sh jail-status      # 查看所有 Jail 状态
sudo ./fail2ban-manager.sh view-banned      # 查看禁封的 IP
sudo ./fail2ban-manager.sh ban-ip           # 禁封 IP（交互式）
sudo ./fail2ban-manager.sh unban-ip         # 解禁 IP（交互式）

# 配置管理
sudo ./fail2ban-manager.sh view-config      # 查看配置
sudo ./fail2ban-manager.sh edit-config      # 编辑配置
sudo ./fail2ban-manager.sh backup-config    # 备份配置
sudo ./fail2ban-manager.sh restore-config   # 恢复备份

# 日志查看
sudo ./fail2ban-manager.sh view-logs        # 查看最近 100 条日志
sudo ./fail2ban-manager.sh realtime-logs    # 查看实时日志

# 帮助
sudo ./fail2ban-manager.sh help
```

## 配置说明

### 配置文件位置
- **主配置文件**：`/etc/fail2ban/jail.local`
- **备份目录**：`/etc/fail2ban/backup/`
- **日志文件**：`/var/log/fail2ban/fail2ban.log`

### 默认配置详解

脚本生成的 jail.local 配置包含两个主要部分：

#### DEFAULT 段（全局默认）
```ini
[DEFAULT]
bantime = 600          # 禁封时长（秒），600 秒 = 10 分钟
findtime = 300         # 时间窗口（秒），300 秒 = 5 分钟
maxretry = 5           # 最大失败次数
banaction = ufw        # 使用 ufw 防火墙进行禁封
action = %(action_mwl)s # 发送邮件+日志
```

#### SSHd 段（SSH 规则）
```ini
[sshd]
enabled = true         # 启用此规则
ignoreip = 127.0.0.1/8 # 本地 IP 不禁封
filter = sshd          # 使用 sshd 过滤器
port = 10022           # SSH 监听端口（示例）
maxretry = 3           # SSH 最大失败次数
findtime = 1d          # SSH 时间窗口：1 天
bantime = -1           # SSH 禁封时长：-1 = 永久禁封
logpath = /var/log/auth.log # 日志路径
```

### 修改配置

#### 方式 1：使用脚本编辑
```bash
sudo ./fail2ban-manager.sh edit-config
```

#### 方式 2：直接编辑
```bash
sudo vim /etc/fail2ban/jail.local
# 编辑后重启服务
sudo systemctl restart fail2ban
```

> **编辑器优先级**：脚本会优先使用 vim、vi、nano（按此顺序）

#### 常见配置修改

**1. 修改 SSH 监听端口**
```ini
[sshd]
port = 22    # 改为您的实际 SSH 端口
```

**2. 修改禁封时长**
```ini
[DEFAULT]
bantime = 3600    # 改为 1 小时
```

**3. 增加失败次数容限**
```ini
[DEFAULT]
maxretry = 10     # 提高容限到 10 次
```

**4. 添加更多白名单 IP**
```ini
[DEFAULT]
ignoreip = 127.0.0.1/8 192.168.1.0/24 10.0.0.0/8
```

**5. 禁用某个规则**
```ini
[sshd]
enabled = false    # 改为 false 禁用
```

## 常见操作示例

### 查看禁封的 IP

```bash
# 查看所有 Jail 的禁封 IP
sudo ./fail2ban-manager.sh view-banned

# 或在交互式菜单中选择选项 7
sudo ./fail2ban-manager.sh
# 然后选择 7
```

### 手动禁封恶意 IP

```bash
sudo ./fail2ban-manager.sh ban-ip
# 输入 IP 地址，然后选择 Jail（通常是 sshd）
```

### 解禁被误禁的 IP

```bash
sudo ./fail2ban-manager.sh unban-ip
# 输入要解禁的 IP 地址
```

### 查看日志

```bash
# 查看最近 100 条日志
sudo ./fail2ban-manager.sh view-logs

# 查看实时日志（按 Ctrl+C 退出）
sudo ./fail2ban-manager.sh realtime-logs
```

### 备份和恢复配置

```bash
# 备份当前配置
sudo ./fail2ban-manager.sh backup-config

# 查看可用的备份
sudo ls -lh /etc/fail2ban/backup/

# 恢复备份
sudo ./fail2ban-manager.sh restore-config
```

## 故障排除

### 问题 1：配置文件重复选项错误

**症状**：`option 'bantime' in section 'DEFAULT' already exists`

**原因**：配置文件中存在重复的 `[DEFAULT]` 部分或选项定义

**解决方案**：
```bash
# 停止服务
sudo systemctl stop fail2ban

# 删除旧配置文件
sudo rm -f /etc/fail2ban/jail.local

# 重新运行脚本安装
sudo ./fail2ban-manager.sh install
```

### 问题 2：安装失败

**症状**：`fail2ban 安装失败`

**解决方案**：
```bash
# 手动尝试安装
# Debian/Ubuntu
sudo apt-get update
sudo apt-get install fail2ban

# CentOS/RHEL
sudo yum install fail2ban

# 然后重新运行脚本
sudo ./fail2ban-manager.sh install
```

### 问题 3：服务启动失败

**症状**：`fail2ban 服务启动失败`

**解决方案**：
```bash
# 查看 systemd 日志
sudo systemctl status fail2ban
sudo journalctl -u fail2ban -n 50

# 检查配置文件语法
sudo fail2ban-client -d

# 恢复备份
sudo ./fail2ban-manager.sh restore-config
```

### 问题 4：配置无法保存

**症状**：编辑配置后无法重启

**解决方案**：
```bash
# 检查配置文件权限
sudo ls -l /etc/fail2ban/jail.local

# 检查配置语法
sudo fail2ban-client -d

# 恢复备份
sudo ./fail2ban-manager.sh restore-config
```

### 问题 5：重要 IP 被误禁

**症状**：无法连接到服务器

**解决方案**：
```bash
# 直接使用 ufw 查看规则
sudo ufw status numbered

# 解禁 IP
sudo fail2ban-client set sshd unbanip <IP>

# 或从另一个 IP 使用脚本解禁
sudo ./fail2ban-manager.sh unban-ip
```

### 问题 6：编辑器未找到

**症状**：`未找到编辑器（vim/vi/nano）`

**解决方案**：
```bash
# 安装 vim
# Debian/Ubuntu
sudo apt-get install vim

# CentOS/RHEL
sudo yum install vim

# 然后再使用编辑配置功能
sudo ./fail2ban-manager.sh edit-config
```

## 安全建议

1. **定期备份配置**
   ```bash
   sudo ./fail2ban-manager.sh backup-config
   ```

2. **监控日志**
   ```bash
   # 定期检查攻击日志
   sudo ./fail2ban-manager.sh view-logs
   ```

3. **调整参数**
   - 根据实际情况调整 `maxretry` 和 `bantime`
   - 为信任的 IP 添加到 `ignoreip`
   - 定期检查禁封名单

4. **集成告警**
   ```bash
   # 配置邮件告警（需要配置 mail 服务）
   # 编辑配置文件中的 action 参数
   action = %(action_mwl)s  # 这会发送邮件
   ```

5. **多层防护**
   - 使用强密码和密钥认证
   - 更改 SSH 默认端口（不一定是 10022）
   - 禁用 root 登录
   - 使用公钥认证

## 性能影响

- **CPU 占用**：极低（<1%）
- **内存占用**：~5-10 MB
- **磁盘 I/O**：最小化（仅在更新规则时）
- **网络影响**：无（本地防护）

## 日志和调试

### 查看脚本执行日志
```bash
tail -f /tmp/fail2ban-manager.log
```

### 增强调试信息
```bash
# fail2ban 调试模式
sudo fail2ban-client -d
```

### 查看 fail2ban 日志
```bash
# 使用 journalctl
sudo journalctl -u fail2ban -f

# 或查看日志文件
sudo tail -f /var/log/fail2ban/fail2ban.log
```

## 脚本架构

### 函数结构

```
初始化函数
├── check_root()              # 权限检查
├── init_system()             # 系统初始化
└── detect_package_manager()  # 包管理器检测

安装函数
├── install_fail2ban()        # 安装主程序
├── is_fail2ban_installed()   # 检查安装状态
└── generate_jail_config()    # 生成配置

服务管理
├── cmd_start()               # 启动服务
├── cmd_stop()                # 停止服务
├── cmd_restart()             # 重启服务
├── cmd_status()              # 查看状态
└── is_fail2ban_running()     # 检查运行状态

Jail 管理
├── cmd_jail_status()         # 查看 Jail 状态
├── cmd_view_banned_ips()     # 查看禁封 IP
├── cmd_ban_ip()              # 禁封 IP
└── cmd_unban_ip()            # 解禁 IP

配置管理
├── cmd_view_config()         # 查看配置
├── cmd_edit_config()         # 编辑配置
├── cmd_backup_config()       # 备份配置
└── cmd_restore_config()      # 恢复备份

日志管理
├── cmd_view_logs()           # 查看日志
└── cmd_view_realtime_logs()  # 实时日志

UI 界面
├── show_menu()               # 菜单显示
├── show_help()               # 帮助信息
└── main()                    # 主程序入口
```

## 与其他脚本的兼容性

该脚本遵循 sys-toolkit 项目规范：

- ✅ 相同的颜色定义和输出格式
- ✅ 相同的权限检查机制
- ✅ 相同的包管理器检测模式
- ✅ 相同的日志系统
- ✅ 相同的菜单交互方式
- ✅ 相同的错误处理模式

可与 `server-proxy.sh` 和 `sys-backup.sh` 协调使用。

## 卸载

完全卸载 fail2ban：

```bash
sudo ./fail2ban-manager.sh uninstall
```

或手动卸载：

```bash
# Debian/Ubuntu
sudo apt-get remove -y fail2ban

# CentOS/RHEL
sudo yum remove -y fail2ban

# Arch
sudo pacman -R fail2ban

# 清理配置目录
sudo rm -rf /etc/fail2ban
```

## 许可证

与 sys-toolkit 项目相同

## 相关资源

- [Fail2ban 官方网站](https://www.fail2ban.org/)
- [Fail2ban 文档](https://www.fail2ban.org/wiki/index.php/Main_Page)
- [sys-toolkit 项目](./README.md)

## 更新日志

### v1.1 (2025-12-30)
- 🐛 修复配置文件重复 `[DEFAULT]` 部分的错误
- ✏️ 改进编辑器支持：优先使用 vim > vi > nano
- 📝 完善帮助信息中的配置文件位置显示
- 📚 更新文档：添加配置错误排除说明和编辑器相关问题解决

### v1.0 (2025-12-30)
- ✨ 初始版本发布
- 🎨 完整的管理界面
- 🔧 支持 5 种包管理器
- 📝 详细的配置管理
- 🛡️ 自动备份和恢复
- 📊 日志查看和监控
