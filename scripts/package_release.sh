#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${ROOT_DIR}/build/Syphon Mixer.app"
DIST_DIR="${ROOT_DIR}/dist"
WORK_DIR="${ROOT_DIR}/build/release"
NOTARY_PROFILE="${NOTARY_PROFILE:-syphon-mixer-notary}"
VERSION="$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' "${ROOT_DIR}/Sources/SyphonMixer/AppInfo.swift")"
ZIP="${DIST_DIR}/SyphonMixer-${VERSION}-macOS-universal.zip"

if [ -z "${SIGN_IDENTITY:-}" ]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ { print $2; exit }')"
fi
if [ -z "${SIGN_IDENTITY}" ]; then
  echo "No Developer ID Application identity found in the keychain." >&2
  exit 1
fi

if ! xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1; then
  cat >&2 <<EOF
Notary credentials "${NOTARY_PROFILE}" were not found in the keychain.
Store them once with an app-specific password for your Apple ID:

  xcrun notarytool store-credentials ${NOTARY_PROFILE} --apple-id <Apple ID> --team-id <Team ID>
EOF
  exit 1
fi

ARCHS="arm64 x86_64" SIGN_IDENTITY="${SIGN_IDENTITY}" "${ROOT_DIR}/scripts/build_app.sh"

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}" "${DIST_DIR}"
SUBMIT_ZIP="${WORK_DIR}/SyphonMixer-${VERSION}-notarize.zip"
NOTARY_LOG="${WORK_DIR}/notarytool.log"
ditto -c -k --keepParent "${APP_DIR}" "${SUBMIT_ZIP}"

set +e
xcrun notarytool submit "${SUBMIT_ZIP}" --keychain-profile "${NOTARY_PROFILE}" --wait 2>&1 | tee "${NOTARY_LOG}"
set -e
if ! grep -q "status: Accepted" "${NOTARY_LOG}"; then
  echo "Notarization was not accepted. See ${NOTARY_LOG}." >&2
  submission_id="$(awk '$1 == "id:" { print $2; exit }' "${NOTARY_LOG}")"
  if [ -n "${submission_id}" ]; then
    xcrun notarytool log "${submission_id}" --keychain-profile "${NOTARY_PROFILE}" >&2
  fi
  exit 1
fi

xcrun stapler staple "${APP_DIR}"
xcrun stapler validate "${APP_DIR}"
spctl --assess --type execute --verbose=2 "${APP_DIR}"

# ditto keeps the framework symlinks and the signature intact; plain zip does not.
rm -f "${ZIP}"
ditto -c -k --keepParent "${APP_DIR}" "${ZIP}"
shasum -a 256 "${ZIP}"
echo "${ZIP}"
