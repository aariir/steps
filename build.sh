#!/bin/bash
# Builds build/Steps.app. Run "./build.sh install" to also copy it to /Applications.
# Optional: BUNDLE_ID=... and SIGN_ID=... (a code-signing identity; default is ad-hoc).
set -euo pipefail
cd "$(dirname "$0")"

command -v swift >/dev/null || { echo "Swift not found. Run: xcode-select --install"; exit 1; }

BUNDLE_ID="${BUNDLE_ID:-local.steps.app}"
swift build -c release
APP=build/Steps.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Steps" "$APP/Contents/MacOS/"
sed "s/BUNDLE_ID/$BUNDLE_ID/" Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

codesign --force --deep --sign "${SIGN_ID:--}" "$APP"
echo "Built $APP (signed with: ${SIGN_ID:-ad-hoc})"

if [ "${1:-}" = "install" ]; then
  rm -rf /Applications/Steps.app
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/Steps.app"
fi
