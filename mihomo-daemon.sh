#!/usr/bin/env bash
set -euo pipefail

LABEL="com.mihomo.daemon"
CONFIG_DIR="/etc/mihomo"
CONFIG_FILE="${CONFIG_DIR}/config.yaml"
PLIST_FILE="/Library/LaunchDaemons/${LABEL}.plist"
LOG_FILE="/var/log/mihomo.log"
ERR_LOG_FILE="/var/log/mihomo.err.log"

CORE_INSTALL_PATH="/usr/local/bin/mihomo"
GITHUB_API_URL="https://api.github.com/repos/MetaCubeX/mihomo/releases/latest"
GITHUB_REPO="MetaCubeX/mihomo"
# GitHub release 下载代理。默认使用 gh.sephiroth.club 加速下载；留空则直连 GitHub：
#   GITHUB_DOWNLOAD_PROXY= sudo ./mihomo-daemon.sh core-install
GITHUB_DOWNLOAD_PROXY="${GITHUB_DOWNLOAD_PROXY:-https://gh.sephiroth.club}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

MIHOMO_BIN=""
SOURCE_CONFIG=""
TEMP_DIR=""

cleanup_temp_dir() {
  if [[ -n "${TEMP_DIR}" && -d "${TEMP_DIR}" ]]; then
    rm -rf "${TEMP_DIR}"
  fi
}

trap cleanup_temp_dir EXIT

usage() {
  cat <<EOF
Usage:
  sudo $0 install [--config /path/to/config.yaml] [--bin /path/to/mihomo]
  sudo $0 start
  sudo $0 stop
  sudo $0 restart
  sudo $0 status
  sudo $0 logs
  sudo $0 uninstall
  sudo $0 config-use /path/to/config.yaml
  sudo $0 config-path
  sudo $0 core-install
  sudo $0 core-update
  sudo $0 core-version

Examples:
  sudo $0 install --config ./config.yaml
  sudo $0 install --bin /opt/homebrew/bin/mihomo --config ./config.yaml
  sudo $0 install
  sudo $0 core-update
  sudo $0 config-use ./config.yaml
  sudo $0 config-path
  sudo $0 restart
  sudo $0 logs
EOF
}

log_info() {
  echo -e "${GREEN}[INFO]${NC} $1" >&2
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1" >&2
}

need_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "请使用 sudo 运行：sudo $0 $*" >&2
    exit 1
  fi
}

init_core_directory() {
  local install_dir
  install_dir="$(dirname "${CORE_INSTALL_PATH}")"

  if [[ ! -d "${install_dir}" ]]; then
    log_info "创建 ${install_dir} 目录..."
    mkdir -p "${install_dir}"
  fi

  if [[ ! -w "${install_dir}" ]]; then
    log_error "没有 ${install_dir} 的写权限，请使用 sudo"
    exit 1
  fi
}

get_latest_release() {
  log_info "正在获取 mihomo 最新稳定版本信息..."

  local release_info
  release_info="$(curl -L \
    --connect-timeout 5 \
    --max-time 10 \
    --retry 2 \
    --retry-delay 0 \
    --retry-max-time 20 \
    -H "Accept: application/vnd.github+json" \
    "${GITHUB_API_URL}" 2>/dev/null)"

  if [[ -z "${release_info}" ]]; then
    log_error "获取版本信息失败"
    exit 1
  fi

  echo "${release_info}"
}

get_version_from_release() {
  local release_info="$1"
  local version

  version="$(echo "${release_info}" | grep -o '"tag_name": *"[^"]*"' | head -1 | sed 's/"tag_name": *"\(.*\)"/\1/')"

  if [[ -z "${version}" ]]; then
    log_error "解析版本号失败"
    exit 1
  fi

  echo "${version}"
}

get_arch() {
  local machine
  machine="$(uname -m)"

  case "${machine}" in
    arm64|aarch64)
      echo "arm64"
      ;;
    x86_64|amd64|i386)
      echo "amd64"
      ;;
    *)
      log_error "不支持的系统架构：${machine}"
      exit 1
      ;;
  esac
}

build_github_download_url() {
  local direct_url="$1"
  local proxy="${GITHUB_DOWNLOAD_PROXY%/}"

  if [[ -z "${proxy}" ]]; then
    echo "${direct_url}"
  else
    echo "${proxy}/${direct_url}"
  fi
}

download_mihomo() {
  local version="$1"
  local arch="$2"
  local temp_dir="$3"
  local direct_url="https://github.com/${GITHUB_REPO}/releases/download/${version}/mihomo-darwin-${arch}-${version}.gz"
  local url
  url="$(build_github_download_url "${direct_url}")"

  log_info "系统架构: ${arch}"
  log_info "版本号: ${version}"
  log_info "下载地址: ${url}"
  log_info "正在下载 mihomo 内核..."

  if ! curl -L \
    --connect-timeout 5 \
    --max-time 30 \
    --retry 3 \
    --retry-delay 1 \
    --retry-max-time 30 \
    "${url}" -o "${temp_dir}/mihomo.gz"; then
    log_error "下载 mihomo 内核失败"
    exit 1
  fi

  log_info "mihomo 内核下载完成"
}

install_downloaded_mihomo() {
  local temp_dir="$1"

  log_info "正在解压 mihomo 内核..."
  gunzip -f "${temp_dir}/mihomo.gz"

  if [[ ! -f "${temp_dir}/mihomo" ]]; then
    log_error "解压 mihomo 内核失败"
    exit 1
  fi

  log_info "设置 mihomo 内核权限..."
  chmod 755 "${temp_dir}/mihomo"

  log_info "安装 mihomo 内核到 ${CORE_INSTALL_PATH}..."
  mv "${temp_dir}/mihomo" "${CORE_INSTALL_PATH}"

  log_info "验证 mihomo 内核安装..."
  if ! "${CORE_INSTALL_PATH}" -h >/dev/null 2>&1; then
    log_error "mihomo 内核验证失败"
    exit 1
  fi

  log_info "mihomo 内核安装成功"
}

install_core() {
  need_root "$@"
  init_core_directory

  TEMP_DIR="$(mktemp -d)"

  local release_info version arch
  release_info="$(get_latest_release)"
  version="$(get_version_from_release "${release_info}")"
  arch="$(get_arch)"

  download_mihomo "${version}" "${arch}" "${TEMP_DIR}"
  install_downloaded_mihomo "${TEMP_DIR}"
  check_core_version
}

is_core_installed() {
  [[ -x "${CORE_INSTALL_PATH}" ]]
}

get_installed_core_version() {
  if is_core_installed; then
    "${CORE_INSTALL_PATH}" -v 2>/dev/null | head -n 1 || true
  fi
}

check_core_version() {
  if is_core_installed; then
    log_info "当前已安装 mihomo 内核：${CORE_INSTALL_PATH}"
    "${CORE_INSTALL_PATH}" -v 2>/dev/null || echo "版本信息获取失败" >&2
  else
    log_warn "mihomo 内核未安装到 ${CORE_INSTALL_PATH}"
  fi
}

update_core() {
  need_root "$@"

  if ! is_core_installed; then
    log_warn "mihomo 内核未安装，将执行全新安装"
    install_core "$@"
    return
  fi

  local current_version release_info latest_version
  current_version="$(get_installed_core_version)"
  log_info "当前版本: ${current_version}"

  release_info="$(get_latest_release)"
  latest_version="$(get_version_from_release "${release_info}")"
  log_info "最新版本: ${latest_version}"

  if echo "${current_version}" | grep -q "${latest_version}"; then
    log_info "已经是最新版本，无需更新"
    return
  fi

  log_info "发现新版本，开始更新 mihomo 内核..."
  init_core_directory

  local arch
  TEMP_DIR="$(mktemp -d)"
  arch="$(get_arch)"

  download_mihomo "${latest_version}" "${arch}" "${TEMP_DIR}"
  install_downloaded_mihomo "${TEMP_DIR}"
  check_core_version
}

find_existing_mihomo_bin() {
  local candidates=(
    "/opt/homebrew/bin/mihomo"
    "${CORE_INSTALL_PATH}"
    "/usr/bin/mihomo"
  )

  for candidate in "${candidates[@]}"; do
    if [[ -x "${candidate}" ]]; then
      echo "${candidate}"
      return 0
    fi
  done

  if command -v mihomo >/dev/null 2>&1; then
    command -v mihomo
    return 0
  fi

  return 1
}

detect_or_install_mihomo_bin() {
  if [[ -n "${MIHOMO_BIN}" ]]; then
    if [[ ! -x "${MIHOMO_BIN}" ]]; then
      echo "mihomo 二进制不可执行或不存在：${MIHOMO_BIN}" >&2
      exit 1
    fi
    return
  fi

  if MIHOMO_BIN="$(find_existing_mihomo_bin)"; then
    log_info "检测到 mihomo 内核：${MIHOMO_BIN}"
    return
  fi

  log_warn "未找到 mihomo 内核，将自动下载并安装到 ${CORE_INSTALL_PATH}"
  install_core "$@"
  MIHOMO_BIN="${CORE_INSTALL_PATH}"
}

create_config_dir() {
  mkdir -p "${CONFIG_DIR}"
  chown root:wheel "${CONFIG_DIR}"
  chmod 755 "${CONFIG_DIR}"
}

install_config() {
  if [[ -n "${SOURCE_CONFIG}" ]]; then
    if [[ ! -f "${SOURCE_CONFIG}" ]]; then
      echo "配置文件不存在：${SOURCE_CONFIG}" >&2
      exit 1
    fi

    cp "${SOURCE_CONFIG}" "${CONFIG_FILE}"
    echo "已安装配置文件：${CONFIG_FILE}"
  else
    if [[ -f "${CONFIG_FILE}" ]]; then
      echo "未指定 --config，保留已有配置文件：${CONFIG_FILE}"
    else
      cat > "${CONFIG_FILE}" <<'EOF'
# Minimal mihomo config for macOS TUN mode.
# This template starts mihomo with TUN enabled, but does not include real proxy nodes.
# You should edit proxies / proxy-groups / rules for your own subscription or nodes.

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
EOF
      echo "已生成最小 TUN 配置模板：${CONFIG_FILE}"
      echo "注意：模板不包含真实代理节点，默认全部 DIRECT。"
    fi
  fi

  chown root:wheel "${CONFIG_FILE}"
  chmod 600 "${CONFIG_FILE}"
}

write_plist() {
  cat > "${PLIST_FILE}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>${LABEL}</string>

    <key>ProgramArguments</key>
    <array>
      <string>${MIHOMO_BIN}</string>
      <string>-d</string>
      <string>${CONFIG_DIR}</string>
    </array>

    <key>WorkingDirectory</key>
    <string>${CONFIG_DIR}</string>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <key>StandardOutPath</key>
    <string>${LOG_FILE}</string>

    <key>StandardErrorPath</key>
    <string>${ERR_LOG_FILE}</string>

    <key>EnvironmentVariables</key>
    <dict>
      <key>PATH</key>
      <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
  </dict>
</plist>
EOF

  chown root:wheel "${PLIST_FILE}"
  chmod 644 "${PLIST_FILE}"

  touch "${LOG_FILE}" "${ERR_LOG_FILE}"
  chown root:wheel "${LOG_FILE}" "${ERR_LOG_FILE}"
  chmod 644 "${LOG_FILE}" "${ERR_LOG_FILE}"

  echo "已写入 LaunchDaemon：${PLIST_FILE}"
}

is_loaded() {
  launchctl print "system/${LABEL}" >/dev/null 2>&1
}

stop_service() {
  if is_loaded; then
    launchctl bootout system "${PLIST_FILE}" || true
    echo "已停止服务：${LABEL}"
  else
    echo "服务未加载：${LABEL}"
  fi
}

start_service() {
  if is_loaded; then
    launchctl kickstart -k "system/${LABEL}"
  else
    launchctl bootstrap system "${PLIST_FILE}"
    launchctl kickstart -k "system/${LABEL}"
  fi

  echo "已启动服务：${LABEL}"
}

install_service() {
  need_root "$@"
  detect_or_install_mihomo_bin "$@"
  create_config_dir
  install_config
  write_plist

  if is_loaded; then
    echo "检测到服务已加载，正在重新加载..."
    launchctl bootout system "${PLIST_FILE}" || true
  fi

  launchctl bootstrap system "${PLIST_FILE}"
  launchctl kickstart -k "system/${LABEL}"

  echo
  echo "mihomo 已安装为 root 后台服务，并设置为开机自启。"
  echo "mihomo 路径：${MIHOMO_BIN}"
  echo "配置目录：${CONFIG_DIR}"
  echo "配置文件：${CONFIG_FILE}"
  echo "日志文件：${LOG_FILE}"
  echo "错误日志：${ERR_LOG_FILE}"
  echo
  echo "查看状态：sudo $0 status"
  echo "查看日志：sudo $0 logs"
}

status_service() {
  need_root "$@"

  if is_loaded; then
    echo "服务已加载：${LABEL}"
    echo
    launchctl print "system/${LABEL}" | sed -n '1,80p'
  else
    echo "服务未加载：${LABEL}"
    exit 1
  fi
}

show_logs() {
  need_root "$@"

  echo "日志文件：${LOG_FILE}"
  echo "错误日志：${ERR_LOG_FILE}"
  echo
  echo "按 Ctrl+C 退出日志查看。"
  echo

  touch "${LOG_FILE}" "${ERR_LOG_FILE}"
  tail -n 100 -f "${LOG_FILE}" "${ERR_LOG_FILE}"
}

uninstall_service() {
  need_root "$@"

  if is_loaded; then
    launchctl bootout system "${PLIST_FILE}" || true
  fi

  if [[ -f "${PLIST_FILE}" ]]; then
    rm -f "${PLIST_FILE}"
    echo "已删除 LaunchDaemon：${PLIST_FILE}"
  fi

  echo
  echo "已卸载 mihomo 系统服务。"
  echo "配置文件未删除：${CONFIG_DIR}"
  echo "日志文件未删除：${LOG_FILE} ${ERR_LOG_FILE}"
  echo "mihomo 内核未删除：${CORE_INSTALL_PATH}"
  echo
  echo "如需完全清理，可手动执行："
  echo "  sudo rm -rf ${CONFIG_DIR}"
  echo "  sudo rm -f ${LOG_FILE} ${ERR_LOG_FILE}"
  echo "  sudo rm -f ${CORE_INSTALL_PATH}"
}

backup_config() {
  if [[ -f "${CONFIG_FILE}" ]]; then
    cp "${CONFIG_FILE}" "${CONFIG_FILE}.bak"
    chown root:wheel "${CONFIG_FILE}.bak"
    chmod 600 "${CONFIG_FILE}.bak"
    echo "已备份当前配置：${CONFIG_FILE}.bak"
  fi
}

restart_service_if_loaded() {
  if is_loaded; then
    echo "检测到服务已加载，正在重启 mihomo..."
    launchctl kickstart -k "system/${LABEL}"
    echo "已重启服务：${LABEL}"
  else
    echo "服务未加载，仅切换配置；如需启动请执行：sudo $0 start"
  fi
}

switch_config() {
  need_root "$@"

  local new_config="${1:-}"
  if [[ -z "${new_config}" ]]; then
    echo "config-use 需要配置文件路径" >&2
    echo "用法：sudo $0 config-use /path/to/config.yaml" >&2
    exit 1
  fi

  if [[ ! -f "${new_config}" ]]; then
    echo "配置文件不存在：${new_config}" >&2
    exit 1
  fi

  create_config_dir
  backup_config
  cp "${new_config}" "${CONFIG_FILE}"
  chown root:wheel "${CONFIG_FILE}"
  chmod 600 "${CONFIG_FILE}"
  echo "已切换配置文件：${CONFIG_FILE} <- ${new_config}"
  restart_service_if_loaded
}

show_config_path() {
  echo "${CONFIG_FILE}"
}
parse_install_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config)
        SOURCE_CONFIG="${2:-}"
        if [[ -z "${SOURCE_CONFIG}" ]]; then
          echo "--config 需要参数" >&2
          exit 1
        fi
        shift 2
        ;;
      --bin)
        MIHOMO_BIN="${2:-}"
        if [[ -z "${MIHOMO_BIN}" ]]; then
          echo "--bin 需要参数" >&2
          exit 1
        fi
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "未知参数：$1" >&2
        usage
        exit 1
        ;;
    esac
  done
}

main() {
  local command="${1:-}"

  case "${command}" in
    install)
      shift
      parse_install_args "$@"
      install_service "$@"
      ;;
    start)
      need_root "$@"
      start_service
      ;;
    stop)
      need_root "$@"
      stop_service
      ;;
    restart)
      need_root "$@"
      stop_service
      start_service
      ;;
    status)
      status_service "$@"
      ;;
    logs)
      show_logs "$@"
      ;;
    uninstall)
      uninstall_service "$@"
      ;;
    config-use)
      shift
      switch_config "$@"
      ;;
    config-path)
      show_config_path
      ;;
    core-install)
      install_core "$@"
      ;;
    core-update)
      update_core "$@"
      ;;
    core-version)
      check_core_version
      ;;
    -h|--help|"")
      usage
      ;;
    *)
      echo "未知命令：${command}" >&2
      usage
      exit 1
      ;;
  esac
}

main "$@"
