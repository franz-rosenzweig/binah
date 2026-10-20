#!/bin/zsh
# Builds Binah.app: the SwiftUI app in Sources/, wrapped into a bundle with its layered icon and
# accent (Resources/, compiled by actool), the microphone's usage text and entitlement, binah://
# links and the Services menu's Train on This. Needs Xcode (actool) and macOS 26 or later.
#
#   ./build.sh && open build/Binah.app
#
# BINAH_ID and BINAH_NAME build it under another id and name (selftest.sh's, so the test never
# touches the real app's settings).
set -euo pipefail
cd "${0:A:h}"

ID=${BINAH_ID:-xyz.tiresia.binah}
NAME=${BINAH_NAME:-Binah}
VERSION=0.1.0
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)
OUT=${BINAH_OUT:-build}
APP="$OUT/$NAME.app"

swift build -c release 2>&1 | grep -E "error|warning: unre|Compiling|Build complete" | tail -5
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Binah "$APP/Contents/MacOS/Binah"

# the icon, layered as Icon Composer makes them (Resources/AppIcon.icon: the ב and its teal rule over
# parchment, from web/icon.svg), so macOS 26 draws it as it draws its own, light, dark and tinted;
# and the accent, Binah's teal, lighter in the dark
xcrun actool Resources/AppIcon.icon Resources/Assets.xcassets --compile "$APP/Contents/Resources" \
    --app-icon AppIcon --platform macosx --minimum-deployment-target 26.0 \
    --output-partial-info-plist "$OUT/assets-partial.plist" >/dev/null

# binah:// links belong to the real app only, so a test build never takes them
URLTYPES=""
[[ $ID == xyz.tiresia.binah ]] && URLTYPES="<key>CFBundleURLTypes</key><array><dict><key>CFBundleURLName</key><string>$ID</string><key>CFBundleURLSchemes</key><array><string>binah</string></array></dict></array>"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$ID</string>
  <key>CFBundleName</key><string>Binah</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleExecutable</key><string>Binah</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.education</string>
  <key>NSHighResolutionCapable</key><true/>
  $URLTYPES
  <key>NSAccentColorName</key><string>AccentColor</string>
  <key>NSMicrophoneUsageDescription</key><string>Binah records your spoken answers and sends them to your Binah server to be transcribed.</string>
  <key>NSServices</key><array><dict>
    <key>NSMessage</key><string>trainOnThis</string>
    <key>NSPortName</key><string>$NAME</string>
    <key>NSMenuItem</key><dict><key>default</key><string>Train on This in $NAME</string></dict>
    <key>NSSendTypes</key><array><string>public.utf8-plain-text</string><string>public.url</string></array>
  </dict></array>
</dict></plist>
PLIST
plutil -lint -s "$APP/Contents/Info.plist"

cat > "$OUT/Binah.entitlements" <<'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.app-sandbox</key><false/>
  <key>com.apple.security.device.audio-input</key><true/>
</dict></plist>
ENT

# an Apple Development identity if the keychain has one, ad hoc otherwise; none is written into
# this public repository (BINAH_SIGN picks another)
IDENTITY=${BINAH_SIGN:-$(security find-identity -v -p codesigning | sed -n 's/^ *[0-9]*) \([0-9A-F]*\) "Apple Development.*/\1/p' | head -1)}
codesign --force --options runtime --entitlements "$OUT/Binah.entitlements" --sign "${IDENTITY:--}" "$APP"
[[ -n $IDENTITY ]] || echo "note: signed ad hoc; the Keychain and the microphone ask again after each build"
echo "built $APP"
