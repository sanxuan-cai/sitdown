#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
swift build -c release
APP="$PWD/dist/坐站助手.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$PWD/.build/AppIcon.iconset"
cp .build/release/SitStandAssistant "$APP/Contents/MacOS/SitStandAssistant"
cp Info.plist "$APP/Contents/Info.plist"
swift scripts/make-icon.swift "$PWD/.build/AppIcon.iconset"
iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "已生成：$APP"
