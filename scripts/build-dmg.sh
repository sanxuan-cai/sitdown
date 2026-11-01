#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
./scripts/build-app.sh
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
ARCH=$(uname -m)
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/sitstand-dmg.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
ditto "dist/坐站助手.app" "$STAGING/坐站助手.app"
ln -s /Applications "$STAGING/Applications"
DMG="$PWD/dist/SitStandAssistant-${VERSION}-macOS-${ARCH}.dmg"
hdiutil create -volname "坐站助手 $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
hdiutil verify "$DMG"
echo "已生成：$DMG"
