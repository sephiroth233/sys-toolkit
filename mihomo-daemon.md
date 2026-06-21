# mihomo-daemon.sh 使用说明

`mihomo-daemon.sh` 用于在 macOS 上安装、管理 mihomo 内核，并通过 LaunchDaemon 以 root 身份后台运行，实现开机自启。脚本默认面向 TUN 模式使用场景。

脚本路径：

```text
/Users/lang/workspace/sys-toolkit/mihomo-daemon.sh
```

## 功能概览

- 自动检测本机已有 mihomo 内核。
- 如果未检测到 mihomo，自动从 `MetaCubeX/mihomo` GitHub latest release 下载对应 macOS 架构的内核。
- 默认通过 `https://gh.sephiroth.club` 代理加速 GitHub release 文件下载；可通过 `GITHUB_DOWNLOAD_PROXY` 环境变量覆盖或留空直连。
- 默认将自动下载的 mihomo 安装到：

  ```text
  /usr/local/bin/mihomo
  ```

- 创建 mihomo 配置目录：

  ```text
  /etc/mihomo
  ```

- 支持使用已有 `config.yaml`，也支持生成最小 TUN 模式模板。
- 创建 LaunchDaemon：

  ```text
  /Library/LaunchDaemons/com.mihomo.daemon.plist
  ```

- 以 root 身份运行 mihomo：

  ```bash
  mihomo -d /etc/mihomo
  ```

- 支持启动、停止、重启、查看状态、查看日志、切换配置文件、卸载服务。
- 支持单独安装、更新、查看 mihomo 内核版本。

## 依赖要求

- macOS
- `bash`
- `curl`
- `gunzip`
- `launchctl`
- 管理员权限，也就是大多数命令需要 `sudo`

如果需要自动下载 mihomo 内核，需要能访问 GitHub API 和 release 下载地址。脚本默认使用 `https://gh.sephiroth.club` 代理加速 release 文件下载：

```text
https://api.github.com/repos/MetaCubeX/mihomo/releases/latest
https://gh.sephiroth.club/https://github.com/MetaCubeX/mihomo/releases/...
```

如需改用其他代理：

```bash
sudo GITHUB_DOWNLOAD_PROXY="https://your-proxy.example" \
  /Users/lang/workspace/sys-toolkit/mihomo-daemon.sh core-install
```

如需直连 GitHub 下载 release 文件，将 `GITHUB_DOWNLOAD_PROXY` 设为空：

```bash
sudo GITHUB_DOWNLOAD_PROXY= \
  /Users/lang/workspace/sys-toolkit/mihomo-daemon.sh core-install
```

## 快速开始

### 1. 赋予脚本执行权限

```bash
chmod +x /Users/lang/workspace/sys-toolkit/mihomo-daemon.sh
```

### 2. 使用已有配置安装

```bash
sudo /Users/lang/workspace/sys-toolkit/mihomo-daemon.sh install --config /path/to/config.yaml
```

安装时会自动检测 mihomo 内核：

1. 如果你通过 `--bin` 指定内核路径，则直接使用指定路径。
2. 如果没有指定，则依次查找：
   - `/opt/homebrew/bin/mihomo`
   - `/usr/local/bin/mihomo`
   - `/usr/bin/mihomo`
   - `command -v mihomo`
3. 如果仍然找不到，则自动下载 latest release 并安装到 `/usr/local/bin/mihomo`。

### 3. 没有配置文件时安装

```bash
sudo /Users/lang/workspace/sys-toolkit/mihomo-daemon.sh install
```

这种方式会生成最小 TUN 模式配置：

```text
/etc/mihomo/config.yaml
```

注意：自动生成的模板不包含真实代理节点，默认规则为 `MATCH,DIRECT`，只能作为配置骨架使用。你需要后续自行补充 `proxies`、`proxy-groups`、`rules`。

## 常用命令

### 安装 daemon 服务

使用现有配置：

```bash
sudo /Users/lang/workspace/sys-toolkit/mihomo-daemon.sh install --config ./config.yaml
```

指定 mihomo 内核路径：

```bash
sudo /Users/lang/workspace/sys-toolkit/mihomo-daemon.sh install \
  --bin /opt/homebrew/bin/mihomo \
  --config ./config.yaml
```

无配置文件时生成默认 TUN 模板：

```bash
sudo /Users/lang/workspace/sys-toolkit/mihomo-daemon.sh install
```

### 启动服务

```bash
sudo /Users/lang/workspace/sys-toolkit/mihomo-daemon.sh start
```

### 停止服务

```bash
sudo /Users/lang/workspace/sys-toolkit/mihomo-daemon.sh stop
```

### 重启服务

```bash
sudo /Users/lang/workspace/sys-toolkit/mihomo-daemon.sh restart
```

### 查看服务状态

```bash
sudo /Users/lang/workspace/sys-toolkit/mihomo-daemon.sh status
```

该命令会调用：

```bash
launchctl print system/com.mihomo.daemon
```

### 查看日志

```bash
sudo /Users/lang/workspace/sys-toolkit/mihomo-daemon.sh logs
```

日志文件位置：

```text
/var/log/mihomo.log
/var/log/mihomo.err.log
```

按 `Ctrl+C` 退出日志查看。

### 查看当前使用的配置路径

```bash
/Users/lang/workspace/sys-toolkit/mihomo-daemon.sh config-path
```

输出固定为：

```text
/etc/mihomo/config.yaml
```

mihomo daemon 始终通过 `-d /etc/mihomo` 启动，因此实际读取的是该目录下的 `config.yaml`。

### 切换配置文件

```bash
sudo /Users/lang/workspace/sys-toolkit/mihomo-daemon.sh config-use /path/to/new-config.yaml
```

该命令会：

1. 检查新配置文件是否存在。
2. 创建或确认配置目录：

   ```text
   /etc/mihomo
   ```

3. 如果当前已有配置，则备份为：

   ```text
   /etc/mihomo/config.yaml.bak
   ```

4. 将新配置复制覆盖到：

   ```text
   /etc/mihomo/config.yaml
   ```

5. 设置权限：

   ```text
   owner: root
    group: wheel
     mode: 600
   ```

6. 如果 LaunchDaemon 已加载，则自动重启 mihomo；如果服务未加载，则只切换配置，不强行启动。

示例：

```bash
sudo /Users/lang/workspace/sys-toolkit/mihomo-daemon.sh config-use ./config-home.yaml
sudo /Users/lang/workspace/sys-toolkit/mihomo-daemon.sh config-use ./config-work.yaml
```
### 卸载 daemon 服务

```bash
sudo /Users/lang/workspace/sys-toolkit/mihomo-daemon.sh uninstall
```

该命令会删除：

```text
/Library/LaunchDaemons/com.mihomo.daemon.plist
```

但默认不会删除：

```text
/etc/mihomo
/var/log/mihomo.log
/var/log/mihomo.err.log
/usr/local/bin/mihomo
```

如果需要完全清理，可手动执行：

```bash
sudo rm -rf /etc/mihomo
sudo rm -f /var/log/mihomo.log /var/log/mihomo.err.log
sudo rm -f /usr/local/bin/mihomo
```

## mihomo 内核管理命令

### 安装或重装内核

```bash
sudo /Users/lang/workspace/sys-toolkit/mihomo-daemon.sh core-install
```

该命令会：

1. 请求 GitHub latest release。
2. 根据本机架构选择下载包：
   - Apple Silicon：`arm64`
   - Intel Mac：`amd64`
3. 下载：

   ```text
   mihomo-darwin-${arch}-${version}.gz
   ```

4. 解压并安装到：

   ```text
   /usr/local/bin/mihomo
   ```

5. 执行 `mihomo -h` 验证安装。

### 更新内核

```bash
sudo /Users/lang/workspace/sys-toolkit/mihomo-daemon.sh core-update
```

该命令会检查当前 `/usr/local/bin/mihomo` 的版本，并与 GitHub latest release 对比：

- 如果已经是最新版本，则不更新。
- 如果有新版本，则下载并覆盖 `/usr/local/bin/mihomo`。
- 如果 `/usr/local/bin/mihomo` 不存在，则执行全新安装。

更新内核后，如果 daemon 正在运行，建议重启服务：

```bash
sudo /Users/lang/workspace/sys-toolkit/mihomo-daemon.sh restart
```

### 查看内核版本

```bash
/Users/lang/workspace/sys-toolkit/mihomo-daemon.sh core-version
```

如果 `/usr/local/bin/mihomo` 存在，会输出 mihomo 版本信息。否则会提示未安装到该路径。

## 生成的文件

安装完成后，通常会产生以下文件：

```text
/usr/local/bin/mihomo
/etc/mihomo/config.yaml
/Library/LaunchDaemons/com.mihomo.daemon.plist
/var/log/mihomo.log
/var/log/mihomo.err.log
```

如果你使用 `--bin /opt/homebrew/bin/mihomo`，LaunchDaemon 会使用你指定的内核路径，不会强制使用 `/usr/local/bin/mihomo`。

## 默认 TUN 配置模板

当执行 `install` 时没有传入 `--config`，且 `/etc/mihomo/config.yaml` 不存在，脚本会生成类似配置：

```yaml
mixed-port: 7890
allow-lan: false
bind-address: "*"
mode: rule
log-level: info
ipv6: false

external-controller: 127.0.0.1:9090

tun:
  enable: true
  stack: system
  auto-route: true
  auto-detect-interface: true
  strict-route: false
  dns-hijack:
    - any:53

dns:
  enable: true
  listen: 0.0.0.0:1053
  ipv6: false
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  nameserver:
    - https://dns.alidns.com/dns-query
    - https://doh.pub/dns-query

proxies: []

proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - DIRECT

rules:
  - MATCH,DIRECT
```

该模板只是启动骨架。实际代理可用性取决于你填入的节点、策略组和规则。

## LaunchDaemon 行为

脚本创建的 LaunchDaemon label 为：

```text
com.mihomo.daemon
```

plist 路径：

```text
/Library/LaunchDaemons/com.mihomo.daemon.plist
```

关键行为：

- `RunAtLoad=true`：加载时自动运行。
- `KeepAlive=true`：进程退出后由 launchd 尝试拉起。
- `StandardOutPath=/var/log/mihomo.log`：标准输出日志。
- `StandardErrorPath=/var/log/mihomo.err.log`：错误日志。
- `ProgramArguments` 使用：

  ```bash
  mihomo -d /etc/mihomo
  ```

## 故障排查

### 查看服务状态

```bash
sudo /Users/lang/workspace/sys-toolkit/mihomo-daemon.sh status
```

### 查看 mihomo 日志

```bash
sudo /Users/lang/workspace/sys-toolkit/mihomo-daemon.sh logs
```

### 手动测试配置

如果服务无法启动，可以先停止服务：

```bash
sudo /Users/lang/workspace/sys-toolkit/mihomo-daemon.sh stop
```

然后手动运行：

```bash
sudo /usr/local/bin/mihomo -d /etc/mihomo
```

如果你使用的是 Homebrew 内核路径，例如：

```bash
sudo /opt/homebrew/bin/mihomo -d /etc/mihomo
```

### plist 权限问题

LaunchDaemon plist 必须满足：

```text
owner: root
 group: wheel
  mode: 644
```

脚本会自动设置：

```bash
sudo chown root:wheel /Library/LaunchDaemons/com.mihomo.daemon.plist
sudo chmod 644 /Library/LaunchDaemons/com.mihomo.daemon.plist
```

### 配置文件权限

脚本会将配置文件设置为：

```text
owner: root
 group: wheel
  mode: 600
```

对应路径：

```text
/etc/mihomo/config.yaml
```

### 下载失败

如果 `core-install` 或自动下载失败，优先检查：

1. 网络是否能访问 GitHub。
2. GitHub release 是否存在对应架构包。
3. 本机架构是否为 `arm64` 或 `x86_64`。
4. 是否使用了 `sudo`。

## 推荐工作流

首次安装：

```bash
chmod +x /Users/lang/workspace/sys-toolkit/mihomo-daemon.sh
sudo /Users/lang/workspace/sys-toolkit/mihomo-daemon.sh install --config ./config.yaml
sudo /Users/lang/workspace/sys-toolkit/mihomo-daemon.sh status
```

更新内核：

```bash
sudo /Users/lang/workspace/sys-toolkit/mihomo-daemon.sh core-update
sudo /Users/lang/workspace/sys-toolkit/mihomo-daemon.sh restart
```

查看日志：

```bash
sudo /Users/lang/workspace/sys-toolkit/mihomo-daemon.sh logs
```

卸载服务但保留配置和内核：

```bash
sudo /Users/lang/workspace/sys-toolkit/mihomo-daemon.sh uninstall
```
