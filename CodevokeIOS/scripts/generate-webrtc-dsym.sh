#!/bin/sh
set -eu

# The stasel/WebRTC binary package does not ship a WebRTC.framework.dSYM.
# Generate a matching UUID dSYM during Archive so App Store Connect symbol
# upload can find the framework entry it expects.
case "${ACTION:-}" in
  install) ;;
  *) exit 0 ;;
esac

framework_binary="${BUILT_PRODUCTS_DIR}/WebRTC.framework/WebRTC"
if [ ! -f "$framework_binary" ]; then
  framework_binary="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}/WebRTC.framework/WebRTC"
fi

if [ ! -f "$framework_binary" ]; then
  echo "warning: WebRTC.framework binary not found; skipping WebRTC dSYM generation"
  exit 0
fi

mkdir -p "${DWARF_DSYM_FOLDER_PATH}"
dsymutil "$framework_binary" -o "${DWARF_DSYM_FOLDER_PATH}/WebRTC.framework.dSYM"
