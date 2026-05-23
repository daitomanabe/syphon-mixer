#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYPHON_FRAMEWORK_PARENT="$("${ROOT_DIR}/scripts/ensure_syphon_framework.sh")"
export SYPHON_FRAMEWORK_PARENT
SYPHON_FRAMEWORK="${SYPHON_FRAMEWORK_PARENT}/Syphon.framework"
APP_DIR="${ROOT_DIR}/build/Syphon Mixer.app"
EXECUTABLE="${APP_DIR}/Contents/MacOS/SyphonMixer"
SWIFTPM_BUILD_DIR="${TMPDIR:-/tmp}/syphon-mixer-swiftpm-release"

if [ ! -d "${SYPHON_FRAMEWORK}" ]; then
  echo "Missing Syphon framework: ${SYPHON_FRAMEWORK}" >&2
  echo "Build ../Syphon-Framework first, or provide build/Release/Syphon.framework." >&2
  exit 1
fi

cd "${ROOT_DIR}"
rm -rf "${SWIFTPM_BUILD_DIR}"
swift build --scratch-path "${SWIFTPM_BUILD_DIR}" -c release -Xswiftc "-F${SYPHON_FRAMEWORK_PARENT}"

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Frameworks"
cp "${SWIFTPM_BUILD_DIR}/release/SyphonMixer" "${EXECUTABLE}"
rsync -a --delete "${SYPHON_FRAMEWORK}" "${APP_DIR}/Contents/Frameworks/"
cat > "${APP_DIR}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>SyphonMixer</string>
  <key>CFBundleIdentifier</key>
  <string>ws.daito.syphon-mixer</string>
  <key>CFBundleName</key>
  <string>Syphon Mixer</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "${APP_DIR}"
codesign --verify --deep --strict --verbose=2 "${APP_DIR}"
echo "${APP_DIR}"
