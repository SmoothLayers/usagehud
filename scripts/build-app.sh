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

echo "Assembling app bundle"
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$ROOT/.build/release/UsageHUD" "$CONTENTS/MacOS/UsageHUD"
cp "$ROOT/assets/UsageHUD.icns" "$CONTENTS/Resources/UsageHUD.icns"
SPARKLE_FRAMEWORK="$(find "$ROOT/.build" -type d -name Sparkle.framework -print -quit)"
if [[ -z "$SPARKLE_FRAMEWORK" ]]; then
  echo "Sparkle.framework was not found in the SwiftPM build artifacts" >&2
  exit 1
fi
mkdir -p "$CONTENTS/Frameworks"
echo "Embedding Sparkle.framework from $SPARKLE_FRAMEWORK"
ditto "$SPARKLE_FRAMEWORK" "$CONTENTS/Frameworks/Sparkle.framework"

echo "Writing Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string '$APP_NAME'" \
  -c "Add :CFBundleDisplayName string '$APP_NAME'" \
  -c "Add :CFBundleInfoDictionaryVersion string '6.0'" \
  -c "Add :CFBundleDevelopmentRegion string 'en'" \
  -c "Add :CFBundleIdentifier string 'com.smoothlayers.usagehud'" \
  -c "Add :CFBundleExecutable string 'UsageHUD'" \
  -c "Add :CFBundleIconFile string 'UsageHUD.icns'" \
  -c "Add :CFBundlePackageType string 'APPL'" \
  -c "Add :CFBundleShortVersionString string '0.6.0'" \
  -c "Add :CFBundleVersion string '25'" \
  -c "Add :LSMinimumSystemVersion string '14.0'" \
  -c "Add :LSUIElement bool true" \
  -c "Add :NSHighResolutionCapable bool true" \
  "$CONTENTS/Info.plist"

sparkle_plist_values=(
  "SUFeedURL:string:https://github.com/SmoothLayers/usagehud/releases/latest/download/appcast.xml"
  "SUPublicEDKey:string:Ks6jdtpKWGNa0/XBqvvBwDoiUiD20kDHBVAfrJSOpdg="
  "SUEnableAutomaticChecks:bool:true"
  "SUAutomaticallyUpdate:bool:true"
  "SUAllowsAutomaticUpdates:bool:true"
  "SUScheduledCheckInterval:integer:86400"
  "SUVerifyUpdateBeforeExtraction:bool:true"
)
for entry in "${sparkle_plist_values[@]}"; do
  key="${entry%%:*}"
  remainder="${entry#*:}"
  type="${remainder%%:*}"
  value="${remainder#*:}"
  echo "Writing Sparkle key $key"
  /usr/libexec/PlistBuddy -c "Add :$key $type $value" "$CONTENTS/Info.plist"
done

echo "Signing app bundle"
codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
