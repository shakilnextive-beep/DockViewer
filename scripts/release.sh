#!/bin/zsh
# Publishes a new Dock Viewer version.
#
#   scripts/release.sh 1.0.1 "What changed in this version"
#
# What it does:
#   1. sets the version in Resources/Info.plist
#   2. builds the universal app and zips it as dist/DockViewer.zip
#   3. commits, tags v<version>, pushes
#   4. creates a GitHub release with DockViewer.zip attached
#
# Every installed copy of Dock Viewer checks GitHub Releases and updates
# itself. The SupportKori download link should point to
#   https://github.com/shakilnextive-beep/DockViewer/releases/latest/download/DockViewer.zip
# so it always serves the newest version too.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release.sh <version> [notes]}"
NOTES="${2:-Dock Viewer $VERSION}"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Commit or stash your changes first." >&2; exit 1
fi

BUILD=$(( $(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist) + 1 ))
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" Resources/Info.plist

./build.sh --no-install
mkdir -p dist
rm -f dist/DockViewer.zip
ditto -c -k --keepParent "build/Dock Viewer.app" dist/DockViewer.zip
echo "✓ dist/DockViewer.zip ($(du -h dist/DockViewer.zip | cut -f1))"

git add Resources/Info.plist
git commit -m "Release $VERSION"
git tag "v$VERSION"
git push origin HEAD "v$VERSION"

gh release create "v$VERSION" dist/DockViewer.zip \
  --title "Dock Viewer $VERSION" --notes "$NOTES"
echo "✓ Released v$VERSION — installed copies will update within a few hours."
