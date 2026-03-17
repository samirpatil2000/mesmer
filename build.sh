#!/bin/bash
set -e

APP_NAME="Mesmer"
BUNDLE_ID="com.mesmer.app"
DEPLOY_TARGET="26.0"

echo "🧹 Cleaning up old build..."
rm -rf build
mkdir -p build/${APP_NAME}.app/Contents/MacOS
mkdir -p build/${APP_NAME}.app/Contents/Resources

echo "🔨 Compiling Swift files..."
swiftc \
  -sdk $(xcrun --show-sdk-path --sdk macosx) \
  -target $(uname -m)-apple-macosx${DEPLOY_TARGET} \
  -parse-as-library \
  -framework Cocoa \
  -framework SwiftUI \
  -framework Speech \
  -framework AVFoundation \
  -framework ApplicationServices \
  -framework FoundationModels \
  -framework ServiceManagement \
  Mesmer/*.swift \
  -o build/${APP_NAME}.app/Contents/MacOS/${APP_NAME}

echo "📋 Creating Info.plist..."
cp Mesmer/Info.plist build/${APP_NAME}.app/Contents/Info.plist

echo "📦 Writing PkgInfo..."
echo "APPL????" > build/${APP_NAME}.app/Contents/PkgInfo

echo "🔏 Code signing..."
codesign --force --deep --sign - --entitlements Mesmer/Mesmer.entitlements build/${APP_NAME}.app

echo "🧼 Removing quarantine attribute..."
xattr -cr build/${APP_NAME}.app

echo "🔗 Adding Applications shortcut to DMG folder..."
ln -s /Applications build/Applications

echo "💿 Creating DMG..."
hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder build \
  -ov \
  -format UDZO \
  ${APP_NAME}_Release.dmg

echo "🧼 Removing quarantine from DMG..."
xattr -cr ${APP_NAME}_Release.dmg

echo ""
echo "✅ Done! DMG is located at: ${APP_NAME}_Release.dmg"
echo "   If macOS still complains, run:  xattr -cr /path/to/${APP_NAME}.app"
