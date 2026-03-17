#!/bin/bash
set -e

echo "📦 Loading environment..."
set -a # automatically export all variables
source .env
set +a

BUILD_DIR="build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
DMG_DIR="dmg"

echo "🧹 Cleaning..."
rm -rf build dmg ${APP_NAME}_Release.dmg

mkdir -p ${APP_DIR}/Contents/MacOS
mkdir -p ${APP_DIR}/Contents/Resources

echo "🔨 Compiling Swift..."
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
-o ${APP_DIR}/Contents/MacOS/${APP_NAME}

echo "📋 Copying Info.plist..."
cp Mesmer/Info.plist ${APP_DIR}/Contents/Info.plist

echo "📦 Creating PkgInfo..."
echo "APPL????" > ${APP_DIR}/Contents/PkgInfo

echo "🔏 Signing..."
codesign \
--force \
--deep \
--timestamp \
--options runtime \
--sign "${SIGN_IDENTITY}" \
--entitlements Mesmer/Mesmer.entitlements \
${APP_DIR}

echo "🔍 Verifying..."
codesign --verify --deep --strict ${APP_DIR}

echo "📂 Preparing DMG..."
mkdir -p ${DMG_DIR}
cp -R ${APP_DIR} ${DMG_DIR}/
ln -s /Applications ${DMG_DIR}/Applications

echo "💿 Creating DMG..."
hdiutil create \
-volname "${APP_NAME}" \
-srcfolder ${DMG_DIR} \
-ov \
-format UDZO \
${APP_NAME}_Release.dmg

echo "📤 Notarizing DMG..."
xcrun notarytool submit ${APP_NAME}_Release.dmg \
--keychain-profile "${NOTARY_PROFILE}" \
--wait

echo "📎 Stapling DMG..."
xcrun stapler staple ${APP_NAME}_Release.dmg

echo "🧼 Cleanup..."
rm -rf ${DMG_DIR}

echo ""
echo "✅ BUILD COMPLETE"
echo "DMG: ${APP_NAME}_Release.dmg"
