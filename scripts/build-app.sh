#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP_NAME="Usage HUD"
APP_DIR="$ROOT/dist/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"

# Single source of truth for the bundle version. CI passes APP_VERSION from the
# workflow input; local builds fall back to the default below.
APP_VERSION="${APP_VERSION:-0.6.6}"
if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "APP_VERSION must look like MAJOR.MINOR.PATCH (got '$APP_VERSION')" >&2
  exit 1
fi
# Sparkle compares CFBundleVersion, so it must increase with every release.
# Deriving it from the version keeps it monotonic without manual bumping.
# (0.6.1 -> 601, comfortably above the last hand-maintained value of 26.)
IFS='.' read -r VERSION_MAJOR VERSION_MINOR VERSION_PATCH <<< "$APP_VERSION"
BUILD_NUMBER=$(( VERSION_MAJOR * 10000 + VERSION_MINOR * 100 + VERSION_PATCH ))

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
  -c "Add :CFBundleShortVersionString string '$APP_VERSION'" \
  -c "Add :CFBundleVersion string '$BUILD_NUMBER'" \
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
