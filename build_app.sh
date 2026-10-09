#!/bin/bash
set -e

echo "🔨 Compiling release binary for macOS (host architecture: $(uname -m))..."
swift build -c release

APP_NAME="SSD Health"
DIST_DIR="dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"

echo "📦 Packaging ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp .build/release/SSDHealthApp "${APP_BUNDLE}/Contents/MacOS/SSDHealthApp"
cp Sources/SSDHealthApp/Resources/Info.plist "${APP_BUNDLE}/Contents/Info.plist"

echo "✍️ Applying local ad-hoc codesign..."
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "✅ Successfully built: ${APP_BUNDLE}"
echo "👉 You can run it now with: open \"${APP_BUNDLE}\""
