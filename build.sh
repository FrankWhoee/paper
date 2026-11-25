#!/bin/bash
# Builds Paper.app. Requires macOS 11+ and the Xcode Command Line Tools (xcode-select --install).
#   ./build.sh            build to build/Paper.app
#   ./build.sh --install  build and copy to /Applications
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Paper.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling…"
swiftc -O -swift-version 5 \
  -framework Cocoa -framework WebKit \
  -o "$APP/Contents/MacOS/Paper" app/main.swift

cp app/Info.plist "$APP/Contents/Info.plist"
cp web/index.html "$APP/Contents/Resources/index.html"
[ -f app/AppIcon.icns ] && cp app/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc sign so macOS will run it locally.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  rm -rf "/Applications/Paper.app"
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/Paper.app"
fi
