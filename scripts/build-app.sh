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

codesign --force --deep --sign - "${APP_BUNDLE}"
print "Built ${APP_BUNDLE}"
