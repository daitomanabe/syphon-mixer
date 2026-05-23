#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYPHON_FRAMEWORK_PARENT="$("${ROOT_DIR}/scripts/ensure_syphon_framework.sh")"
export SYPHON_FRAMEWORK_PARENT
SYPHON_FRAMEWORK="${SYPHON_FRAMEWORK_PARENT}/Syphon.framework"
SWIFTPM_BUILD_DIR="${TMPDIR:-/tmp}/syphon-mixer-swiftpm-debug"

if [ ! -d "${SYPHON_FRAMEWORK}" ]; then
  echo "Missing Syphon framework: ${SYPHON_FRAMEWORK}" >&2
  exit 1
fi

cd "${ROOT_DIR}"
swift run --scratch-path "${SWIFTPM_BUILD_DIR}" -Xswiftc "-F${SYPHON_FRAMEWORK_PARENT}" SyphonMixer
