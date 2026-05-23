#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GLOBAL_HELPER="${HOME}/.codex/skills/syphon-framework-cache/scripts/ensure_syphon_framework.sh"

if [ -x "${GLOBAL_HELPER}" ]; then
  exec "${GLOBAL_HELPER}" "${ROOT_DIR}"
fi

CACHE_DIR="${SYPHON_FRAMEWORK_CACHE:-${HOME}/.codex/shared/syphon}"

candidate_parent() {
  local value="$1"
  if [ -z "${value}" ]; then
    return
  fi
  if [ -d "${value}/Syphon.framework" ]; then
    printf '%s\n' "${value}"
  elif [ -d "${value}" ] && [ "$(basename "${value}")" = "Syphon.framework" ]; then
    dirname "${value}"
  fi
}

for parent in \
  "$(candidate_parent "${SYPHON_FRAMEWORK_PARENT:-}")" \
  "$(candidate_parent "${SYPHON_FRAMEWORK_DIR:-}")" \
  "$(candidate_parent "${ROOT_DIR}/../Syphon-Framework/build/Release")" \
  "$(candidate_parent "${ROOT_DIR}/Syphon-Framework/build/Release")" \
  "$(candidate_parent "${CACHE_DIR}")"; do
  if [ -n "${parent}" ]; then
    echo "${parent}"
    exit 0
  fi
done

cat >&2 <<EOF
Syphon.framework was not found.

Checked:
- SYPHON_FRAMEWORK_PARENT
- SYPHON_FRAMEWORK_DIR
- ../Syphon-Framework/build/Release
- ./Syphon-Framework/build/Release
- ${CACHE_DIR}

Use the global syphon-framework-cache skill/helper to populate ${CACHE_DIR}, or
set SYPHON_FRAMEWORK_PARENT to a directory containing Syphon.framework.
EOF
exit 1
