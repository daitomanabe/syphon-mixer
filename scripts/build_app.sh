#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYPHON_FRAMEWORK_PARENT="$("${ROOT_DIR}/scripts/ensure_syphon_framework.sh")"
export SYPHON_FRAMEWORK_PARENT
SYPHON_FRAMEWORK="${SYPHON_FRAMEWORK_PARENT}/Syphon.framework"
APP_DIR="${ROOT_DIR}/build/Syphon Mixer.app"
EXECUTABLE="${APP_DIR}/Contents/MacOS/SyphonMixer"
SWIFTPM_BUILD_DIR="${TMPDIR:-/tmp}/syphon-mixer-swiftpm-release"
APP_INFO="${ROOT_DIR}/Sources/SyphonMixer/AppInfo.swift"
VERSION="$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' "${APP_INFO}")"
BUILD_NUMBER="$(sed -n 's/.*static let build = "\(.*\)".*/\1/p' "${APP_INFO}")"

# ARCHS="arm64 x86_64" builds a universal binary. The default is this Mac's architecture.
ARCHS="${ARCHS:-$(uname -m)}"
# SIGN_IDENTITY "-" signs ad-hoc. Pass a Developer ID Application identity to distribute.
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

if [ ! -d "${SYPHON_FRAMEWORK}" ]; then
  echo "Missing Syphon framework: ${SYPHON_FRAMEWORK}" >&2
  echo "Build ../Syphon-Framework first, or provide build/Release/Syphon.framework." >&2
  exit 1
fi

cd "${ROOT_DIR}"
THIN_BINARIES=()
for arch in ${ARCHS}; do
  build_dir="${SWIFTPM_BUILD_DIR}-${arch}"
  rm -rf "${build_dir}"
  swift build --scratch-path "${build_dir}" -c release --arch "${arch}" -Xswiftc "-F${SYPHON_FRAMEWORK_PARENT}"
  bin_dir="$(swift build --scratch-path "${build_dir}" -c release --arch "${arch}" --show-bin-path)"
  thin="${build_dir}/SyphonMixer-${arch}"
  cp "${bin_dir}/SyphonMixer" "${thin}"

  # Keep only relocatable rpaths. Syphon loads from Contents/Frameworks, so paths
  # on this build machine (framework cache, toolchain) must not ship.
  for rpath in $(otool -l "${thin}" | awk '$1 == "path" { print $2 }'); do
    case "${rpath}" in
      @*|/usr/lib/swift) ;;
      *) install_name_tool -delete_rpath "${rpath}" "${thin}" ;;
    esac
  done
  THIN_BINARIES+=("${thin}")
done

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Frameworks"
lipo -create "${THIN_BINARIES[@]}" -output "${EXECUTABLE}"
rsync -a --delete "${SYPHON_FRAMEWORK}" "${APP_DIR}/Contents/Frameworks/"
cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
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
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

xattr -cr "${APP_DIR}"
if [ "${SIGN_IDENTITY}" = "-" ]; then
  codesign --force --deep --sign - "${APP_DIR}"
else
  # Sign inside out with the hardened runtime and a secure timestamp, as notarization requires.
  codesign --force --sign "${SIGN_IDENTITY}" --options runtime --timestamp \
    "${APP_DIR}/Contents/Frameworks/Syphon.framework"
  codesign --force --sign "${SIGN_IDENTITY}" --options runtime --timestamp "${APP_DIR}"
fi
codesign --verify --deep --strict --verbose=2 "${APP_DIR}"
echo "${APP_DIR}"
