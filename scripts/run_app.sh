#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYPHON_FRAMEWORK="${ROOT_DIR}/../Syphon-Framework/build/Release/Syphon.framework"

if [ ! -d "${SYPHON_FRAMEWORK}" ]; then
  echo "Missing Syphon framework: ${SYPHON_FRAMEWORK}" >&2
  exit 1
fi

cd "${ROOT_DIR}"
swift run -Xswiftc -F../Syphon-Framework/build/Release SyphonMixer
