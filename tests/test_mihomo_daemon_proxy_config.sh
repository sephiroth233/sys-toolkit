#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${SCRIPT_DIR}/mihomo-daemon.sh"

assert_contains() {
  local haystack="$1"
  local needle="$2"

  if [[ "${haystack}" != *"${needle}"* ]]; then
    echo "Expected script to contain: ${needle}" >&2
    exit 1
  fi
}

script_content="$(<"${SCRIPT}")"

assert_contains "${script_content}" 'GITHUB_DOWNLOAD_PROXY="${GITHUB_DOWNLOAD_PROXY:-https://gh.sephiroth.club}"'
assert_contains "${script_content}" 'build_github_download_url()'
assert_contains "${script_content}" 'url="$(build_github_download_url "${direct_url}")"'
assert_contains "${script_content}" '留空则直连 GitHub'

echo "PASS: mihomo daemon script exposes and uses GitHub download proxy"
