#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP_NAME="Usage HUD"
APP_DIR="$ROOT/dist/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"

cd "$ROOT"
mkdir -p "$ROOT/.build/clang-cache" "$ROOT/.build/module-cache" "$ROOT/.build/cache"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build/module-cache"
export XDG_CACHE_HOME="$ROOT/.build/cache"
swift build -c release --disable-sandbox

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$ROOT/.build/release/UsageHUD" "$CONTENTS/MacOS/UsageHUD"
cp "$ROOT/assets/UsageHUD.icns" "$CONTENTS/Resources/UsageHUD.icns"

/usr/libexec/PlistBuddy -c "Add :CFBundleName string '$APP_NAME'" \
  -c "Add :CFBundleDisplayName string '$APP_NAME'" \
  -c "Add :CFBundleInfoDictionaryVersion string '6.0'" \
  -c "Add :CFBundleDevelopmentRegion string 'en'" \
  -c "Add :CFBundleIdentifier string 'com.smoothlayers.usagehud'" \
  -c "Add :CFBundleExecutable string 'UsageHUD'" \
  -c "Add :CFBundleIconFile string 'UsageHUD.icns'" \
  -c "Add :CFBundlePackageType string 'APPL'" \
  -c "Add :CFBundleShortVersionString string '0.4.0'" \
  -c "Add :CFBundleVersion string '23'" \
  -c "Add :LSMinimumSystemVersion string '14.0'" \
  -c "Add :LSUIElement bool true" \
  -c "Add :NSHighResolutionCapable bool true" \
  "$CONTENTS/Info.plist"

codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
