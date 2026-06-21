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

assert_contains "${help_output}" "sudo ${SCRIPT} core-install"
assert_contains "${help_output}" "sudo ${SCRIPT} core-update"
assert_contains "${help_output}" "sudo ${SCRIPT} core-version"
assert_contains "${help_output}" "install [--config /path/to/config.yaml] [--bin /path/to/mihomo]"

echo "PASS: help documents integrated core management commands"
