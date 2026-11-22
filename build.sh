#!/bin/zsh
# Builds DockPeek.app and installs it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/DockPeek.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/DockPeek "$APP/Contents/MacOS/DockPeek"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Pin the designated requirement to the bundle id (not the build's hash),
# so macOS keeps the Accessibility / Screen Recording grants across rebuilds.
codesign --force --sign - --identifier local.dockpeek.app \
  -r='designated => identifier "local.dockpeek.app"' "$APP"

pkill -x DockPeek 2>/dev/null || true
rm -rf /Applications/DockPeek.app
cp -R "$APP" /Applications/DockPeek.app
echo "Installed /Applications/DockPeek.app"
