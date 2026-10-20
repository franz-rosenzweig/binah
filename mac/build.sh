#!/bin/zsh
# Builds Binah.app with the Command Line Tools alone, no Xcode needed:
#   ./build.sh && open build/Binah.app
# The settings and Info.plist keys come from project.yml, the same spec the Xcode
# project is generated from, so the two builds cannot drift apart.
set -euo pipefail
cd "${0:A:h}"

command -v swiftc >/dev/null || { echo "no swiftc: run xcode-select --install" >&2; exit 1; }
command -v xcodegen >/dev/null || { echo "no xcodegen: run brew install xcodegen" >&2; exit 1; }

setting() { sed -n "s/^ *$1: *\"*\([^\"]*\)\"*$/\1/p" project.yml | head -1; }
BUNDLE_ID=${BINAH_BUNDLE_ID:-$(setting PRODUCT_BUNDLE_IDENTIFIER)}   # selftest.sh runs as another app
VERSION=$(setting MARKETING_VERSION)
BUILD=$(setting CURRENT_PROJECT_VERSION)
MACOS=$(setting macOS)

OUT=${BINAH_OUT:-build}                # selftest.sh builds its variant into build/selftest
APP=$OUT/Binah.app

xcodegen generate --quiet               # writes Binah/Info.plist, the entitlements and the Xcode project
rm -rf $APP && mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
swiftc -O -wmo -sdk "$(xcrun --show-sdk-path)" -target "$(uname -m)-apple-macos$MACOS" -swift-version 5 \
    -parse-as-library -module-name Binah Binah/*.swift ${=BINAH_EXTRA:-} \
    -o $APP/Contents/MacOS/Binah
sed -e "s/\$(DEVELOPMENT_LANGUAGE)/en/" -e "s/\$(EXECUTABLE_NAME)/Binah/" \
    -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$BUNDLE_ID/" -e "s/\$(MARKETING_VERSION)/$VERSION/" \
    -e "s/\$(CURRENT_PROJECT_VERSION)/$BUILD/" -e "s/\$(PRODUCT_NAME)/Binah/" Binah/Info.plist > $APP/Contents/Info.plist
plutil -lint -s $APP/Contents/Info.plist

# The icon: the web app's (ב on parchment, the teal rule under it), drawn at 824 of
# 1024 so it sits on the macOS icon grid like the other apps in the Dock.
SRC=../web/icon.svg
if [[ -f $SRC ]] && command -v rsvg-convert >/dev/null; then
    SET=$OUT/AppIcon.iconset && rm -rf $SET && mkdir -p $SET
    rsvg-convert -w 824 -h 824 $SRC -o $OUT/icon-824.png
    sips -p 1024 1024 $OUT/icon-824.png --out $OUT/icon-grid.png >/dev/null
    for s in 16 32 128 256 512; do
        sips -z $s $s $OUT/icon-grid.png --out $SET/icon_${s}x${s}.png >/dev/null
        sips -z $((s * 2)) $((s * 2)) $OUT/icon-grid.png --out $SET/icon_${s}x${s}@2x.png >/dev/null
    done
    iconutil -c icns $SET -o $APP/Contents/Resources/AppIcon.icns
    plutil -replace CFBundleIconFile -string AppIcon $APP/Contents/Info.plist
    rm -rf $SET $OUT/icon-824.png $OUT/icon-grid.png
else
    echo "no icon: brew install librsvg for rsvg-convert" >&2
fi

# An Apple Development identity if there is one (Xcode makes it from your Apple ID),
# ad hoc otherwise, which is enough to run it on this Mac. BINAH_SIGN picks another.
IDENTITY=${BINAH_SIGN:-$(security find-identity -v -p codesigning | sed -n 's/^ *[0-9]*) \([0-9A-F]*\) "Apple Development.*/\1/p' | head -1)}
codesign --force --options runtime --entitlements Binah/Binah.entitlements --sign "${IDENTITY:--}" $APP
[[ -n $IDENTITY ]] || echo "note: signed ad hoc; fine on this Mac, but the Keychain and the microphone ask again after each build"
echo "built $APP"
