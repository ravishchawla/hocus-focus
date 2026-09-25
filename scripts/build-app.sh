#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_DISPLAY_NAME="Hocus Focus"
SWIFT_PRODUCT_NAME="Notchflow"
EXECUTABLE_NAME="HocusFocus"
DIST_DIR="${PROJECT_DIR}/dist"
APP_BUNDLE="${DIST_DIR}/${APP_DISPLAY_NAME}.app"
LEGACY_APP_BUNDLE="${DIST_DIR}/Notchflow.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
TASK_TMP_ROOT="${TMPDIR:-/private/tmp}"
SCRATCH_DIR="$(mktemp -d "${TASK_TMP_ROOT%/}/hocus-focus-release.XXXXXX")"
# Set CODESIGN_IDENTITY to a "Developer ID Application: ..." identity to produce a
# distributable signature. When unset the bundle is ad-hoc signed, and Gatekeeper
# asks for "Open Anyway" on Macs that download it.
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"

cleanup_scratch() {
  if [[ "${SCRATCH_DIR}" == *"/hocus-focus-release."* ]]; then
    rm -rf "${SCRATCH_DIR}"
  fi
}
trap cleanup_scratch EXIT

cd "${PROJECT_DIR}"
swift build -c release --arch arm64 --jobs 1 --scratch-path "${SCRATCH_DIR}"
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path --scratch-path "${SCRATCH_DIR}")"

if [[ "${APP_BUNDLE}" != "${PROJECT_DIR}/dist/Hocus Focus.app" ]] ||
   [[ "${LEGACY_APP_BUNDLE}" != "${PROJECT_DIR}/dist/Notchflow.app" ]]; then
  print -u2 "Refusing to replace an unexpected build path: ${APP_BUNDLE}"
  exit 1
fi

rm -rf "${APP_BUNDLE}" "${LEGACY_APP_BUNDLE}"
mkdir -p "${CONTENTS_DIR}/MacOS" "${CONTENTS_DIR}/Resources"
install -m 755 "${BIN_DIR}/${SWIFT_PRODUCT_NAME}" "${CONTENTS_DIR}/MacOS/${EXECUTABLE_NAME}"
install -m 644 "${PROJECT_DIR}/Packaging/Info.plist" "${CONTENTS_DIR}/Info.plist"
install -m 644 "${PROJECT_DIR}/Packaging/AppIcon.icns" "${CONTENTS_DIR}/Resources/AppIcon.icns"

if [[ -n "${CODESIGN_IDENTITY}" ]]; then
  codesign --force --deep --options runtime --timestamp --sign "${CODESIGN_IDENTITY}" "${APP_BUNDLE}"
else
  codesign --force --deep --sign - "${APP_BUNDLE}"
fi
codesign --verify --deep --strict "${APP_BUNDLE}"
print "Built ${APP_BUNDLE}"

# Package for distribution. ditto preserves Unix permissions and the code
# signature. Archives made by tools that drop file modes strip the execute bit
# from the binary, and the extracted app then fails with "Launchd job spawn failed".
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${CONTENTS_DIR}/Info.plist")"
ZIP_PATH="${DIST_DIR}/Hocus-Focus-${VERSION}.zip"
rm -f "${ZIP_PATH}"
ditto -c -k --sequesterRsrc --keepParent "${APP_BUNDLE}" "${ZIP_PATH}"

# Round-trip the archive and confirm the binary is still executable and signed.
VERIFY_DIR="${SCRATCH_DIR}/verify"
mkdir -p "${VERIFY_DIR}"
ditto -x -k "${ZIP_PATH}" "${VERIFY_DIR}"
if [[ ! -x "${VERIFY_DIR}/${APP_DISPLAY_NAME}.app/Contents/MacOS/${EXECUTABLE_NAME}" ]]; then
  print -u2 "Packaged binary lost its execute bit: ${ZIP_PATH}"
  exit 1
fi
codesign --verify --deep --strict "${VERIFY_DIR}/${APP_DISPLAY_NAME}.app"
print "Packaged ${ZIP_PATH}"
