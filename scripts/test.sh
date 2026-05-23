#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYPHON_FRAMEWORK_PARENT="$("${ROOT_DIR}/scripts/ensure_syphon_framework.sh")"
export SYPHON_FRAMEWORK_PARENT
SWIFTPM_BUILD_DIR="${TMPDIR:-/tmp}/syphon-mixer-swiftpm-test"

cd "${ROOT_DIR}"
rm -rf "${SWIFTPM_BUILD_DIR}"
swift test \
  --scratch-path "${SWIFTPM_BUILD_DIR}" \
  --enable-xctest \
  --disable-swift-testing \
  -Xswiftc "-F${SYPHON_FRAMEWORK_PARENT}"
