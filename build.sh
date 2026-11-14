#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

APP_NAME="AirIsland"
VERSION="1.0.0"
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macos12.0"

SDK_PATH="$(xcrun --show-sdk-path 2>/dev/null || true)"
if [[ -z "$SDK_PATH" ]]; then
  echo "Error: Apple Command Line Tools not found."
  echo "Install them first by running: xcode-select --install"
  exit 1
fi

SWIFT_FILES=(Sources/AirIsland/*.swift)
FRAMEWORKS=(
  -framework Cocoa
  -framework SwiftUI
  -framework QuartzCore
  -framework Carbon
  -framework IOKit
  -framework UniformTypeIdentifiers
)

compile_binary() {
  local arch="$1"
  local out="$2"
  echo "Compiling $APP_NAME ($arch -> macOS 12.0)..."
  swiftc -O \
    -sdk "$SDK_PATH" \
    -target "${arch}-apple-macos12.0" \
    "${FRAMEWORKS[@]}" \
    "${SWIFT_FILES[@]}" \
    -o "$out"
}

generate_app_icon() {
  local resources_dir="$1"
  local iconset_dir=".build/AppIcon.iconset"
  local icns_out="$resources_dir/AppIcon.icns"
  if [[ -f "AppResources/generate_icon.swift" ]] && command -v iconutil >/dev/null 2>&1; then
    rm -rf "$iconset_dir"
    echo "Generating AppIcon.icns..."
    if swift -sdk "$SDK_PATH" AppResources/generate_icon.swift "$iconset_dir" >/dev/null 2>&1; then
      iconutil -c icns "$iconset_dir" -o "$icns_out"
    fi
  fi
}

case "${1:-help}" in
  run)
    mkdir -p .build
    compile_binary "$ARCH" ".build/$APP_NAME"
    echo "Launching $APP_NAME (Ctrl+C to quit)..."
    ".build/$APP_NAME"
    ;;
  build)
    mkdir -p .build
    compile_binary "$ARCH" ".build/$APP_NAME"
    echo "Built binary: .build/$APP_NAME ($(du -h ".build/$APP_NAME" | cut -f1))"
    ;;
  app)
    mkdir -p .build
    compile_binary "$ARCH" ".build/$APP_NAME"
    APP_BUNDLE="$APP_NAME.app"
    rm -rf "$APP_BUNDLE"
    mkdir -p "$APP_BUNDLE/Contents/MacOS"
    mkdir -p "$APP_BUNDLE/Contents/Resources"
    cp ".build/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    cp AppResources/Info.plist "$APP_BUNDLE/Contents/Info.plist"
    generate_app_icon "$APP_BUNDLE/Contents/Resources"
    chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    echo "Ad-hoc signing $APP_BUNDLE..."
    codesign --force --deep -s - "$APP_BUNDLE"
    echo "Created $DIR/$APP_BUNDLE"
    ;;
  universal)
    mkdir -p .build/x86_64 .build/arm64 .build/universal
    compile_binary "x86_64" ".build/x86_64/$APP_NAME"
    compile_binary "arm64" ".build/arm64/$APP_NAME"
    lipo -create -output ".build/universal/$APP_NAME" \
      ".build/x86_64/$APP_NAME" \
      ".build/arm64/$APP_NAME"
    APP_BUNDLE="$APP_NAME.app"
    rm -rf "$APP_BUNDLE"
    mkdir -p "$APP_BUNDLE/Contents/MacOS"
    mkdir -p "$APP_BUNDLE/Contents/Resources"
    cp ".build/universal/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    cp AppResources/Info.plist "$APP_BUNDLE/Contents/Info.plist"
    generate_app_icon "$APP_BUNDLE/Contents/Resources"
    chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    codesign --force --deep -s - "$APP_BUNDLE"
    echo "Created Universal $DIR/$APP_BUNDLE"
    ;;
  dmg)
    "$0" app
    DMG_NAME="$APP_NAME-$VERSION.dmg"
    STAGING=".build/dmg_staging"
    rm -rf "$STAGING" "$DMG_NAME"
    mkdir -p "$STAGING"
    cp -R "$APP_NAME.app" "$STAGING/"
    ln -s /Applications "$STAGING/Applications"
    hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG_NAME"
    rm -rf "$STAGING"
    echo "Created $DIR/$DMG_NAME"
    ;;
  clean)
    rm -rf .build "$APP_NAME.app" "$APP_NAME-"*.dmg
    echo "Cleaned build artifacts."
    ;;
  *)
    echo "Usage: ./build.sh [run | build | app | universal | dmg | clean]"
    exit 1
    ;;
esac
