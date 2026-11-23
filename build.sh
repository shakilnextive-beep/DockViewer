#!/bin/zsh
# Builds "Dock Viewer.app" as a universal app (Apple Silicon + Intel).
#
#   ./build.sh            build and install to /Applications, then open it
#   ./build.sh --no-install   only build into ./build
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Dock Viewer"
EXE="DockViewer"
BUNDLE_ID="com.supportkori.dockviewer"
APP="build/$APP_NAME.app"

echo "→ Building arm64…"
swift build -c release --triple arm64-apple-macosx14.0 --build-path .build/arm64 >/dev/null
echo "→ Building x86_64…"
swift build -c release --triple x86_64-apple-macosx14.0 --build-path .build/x86_64 >/dev/null

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create -output "$APP/Contents/MacOS/$EXE" \
  ".build/arm64/release/$EXE" ".build/x86_64/release/$EXE"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature whose designated requirement is the bundle id (not the
# build hash), so macOS keeps Accessibility / Screen Recording permissions
# across rebuilds and auto-updates.
codesign --force --sign - --identifier "$BUNDLE_ID" \
  -r="designated => identifier \"$BUNDLE_ID\"" "$APP"
echo "✓ Built $APP ($(lipo -archs "$APP/Contents/MacOS/$EXE"))"

if [[ "${1:-}" != "--no-install" ]]; then
  pkill -x "$EXE" 2>/dev/null || true
  sleep 0.5
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" "/Applications/$APP_NAME.app"
  echo "✓ Installed /Applications/$APP_NAME.app"
fi
