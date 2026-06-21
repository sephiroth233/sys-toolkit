#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${SCRIPT_DIR}/mihomo-daemon.sh"

assert_contains() {
  local haystack="$1"
  local needle="$2"

  if [[ "${haystack}" != *"${needle}"* ]]; then
    echo "Expected output to contain: ${needle}" >&2
    echo "Actual output:" >&2
    echo "${haystack}" >&2
    exit 1
  fi
}

help_output="$(${SCRIPT} --help)"
script_content="$(<"${SCRIPT}")"

assert_contains "${help_output}" "sudo ${SCRIPT} config-use /path/to/config.yaml"
assert_contains "${help_output}" "sudo ${SCRIPT} config-path"
assert_contains "${script_content}" 'switch_config()'
assert_contains "${script_content}" 'backup_config()'
assert_contains "${script_content}" 'restart_service_if_loaded()'
assert_contains "${script_content}" 'config-use)'
assert_contains "${script_content}" 'config-path)'

echo "PASS: mihomo daemon script documents and implements config switching commands"
