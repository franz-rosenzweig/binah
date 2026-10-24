#!/bin/bash
# Cuts a release: the version raised, a signed APK and the zipped Mac app built on a Mac, a GitHub
# Release with both (Obtainium on a phone watches it), and the Homebrew cask brought up to it.
#
#   tools/release.sh 0.2.1 "What's new, in a line or two"
#
# It runs where gh and git can push, and builds nothing here. The Mac builds from a fresh clone of
# the tag, so nothing that only lives in someone's own checkout goes into a release. The Mac, and
# how things are signed, are in tools/release.env, which git leaves out:
#   BINAH_MAC=user@host  BINAH_MAC_KEY=~/.ssh/key
#   BINAH_APK_SIGNING=<keystore.properties on the Mac, absolute>
#   BINAH_SIGN=<the Mac signing certificate's SHA-1>  BINAH_SIGN_NAME=<its common name>
#   BINAH_KEYCHAIN=<the keychain it's in>  BINAH_KEYCHAIN_PASS=<a file on the Mac holding its password>
#   BINAH_PRIVATE='words|that|must|not|be|in|a|release'   (looked for, case-blind, in both apps)
# The APK is signed with the same key every time, or phones can't update. The Mac app is signed
# with the same certificate every time, so macOS sees the same app from one version to the next and
# keeps its Keychain and microphone grants; and never with a personal identity, whose name anyone
# could read off a public download.
set -euo pipefail
cd "$(dirname "$0")/.."

V=${1:?usage: tools/release.sh X.Y.Z "notes"}
NOTES=${2:-"Binah $V"}
[[ $V =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "a version is X.Y.Z" >&2; exit 2; }
[[ -f tools/release.env ]] || { echo "no tools/release.env (the Mac to build on, and the signing)" >&2; exit 2; }
source tools/release.env
REPO=franz-rosenzweig/binah
TAP=franz-rosenzweig/homebrew-tap
GRADLE=android/app/build.gradle.kts
KEY=${BINAH_MAC_KEY/#\~/$HOME}
mac() { ssh -o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=30 -i "$KEY" "$BINAH_MAC" "$@"; }
say() { echo "== $*"; }

# 1. the version, on master and tagged
git fetch -q origin
[[ -z $(git status --porcelain) ]] || { echo "the tree isn't clean" >&2; exit 1; }
[[ $(git rev-parse HEAD) == $(git rev-parse origin/master) ]] || { echo "HEAD isn't origin/master" >&2; exit 1; }
git rev-parse -q --verify "refs/tags/v$V" >/dev/null && { echo "v$V is taken" >&2; exit 1; }
code=$(( $(sed -n 's/.*versionCode = \([0-9]*\).*/\1/p' $GRADLE | head -1) + 1 ))
sed -i "s/versionCode = [0-9]*/versionCode = $code/; s/versionName = \"[^\"]*\"/versionName = \"$V\"/" $GRADLE
git commit -q -m "Binah $V" $GRADLE
build=$(git rev-list --count HEAD)    # the Mac's build number: commits on master only ever go up
git tag -a "v$V" -m "Binah $V"
git push -q origin HEAD:master "v$V"
say "v$V tagged at $(git rev-parse --short HEAD) (Android $code, Mac build $build)"

# 2. built on the Mac, from a fresh clone of the tag
W=/tmp/binah-release
mac "export PATH=/opt/homebrew/bin:\$PATH; rm -rf $W && git clone -q --depth 1 -b v$V https://github.com/$REPO.git $W \
  && cd $W/android && ./release.sh $BINAH_APK_SIGNING" >/dev/null
say "APK built"
mac "export PATH=/opt/homebrew/bin:\$PATH; security unlock-keychain -p \"\$(cat $BINAH_KEYCHAIN_PASS)\" $BINAH_KEYCHAIN \
  && cd $W/mac && BINAH_SIGN=$BINAH_SIGN BINAH_VERSION=$V BINAH_BUILD=$build ./build.sh >/tmp/binah-release.log 2>&1 \
  && cd build && ditto -c -k --keepParent Binah.app Binah-$V-mac.zip" \
  || { mac "tail -20 /tmp/binah-release.log"; echo "the Mac app didn't build" >&2; exit 1; }

# nothing personal in either: the Mac signature names only the certificate, no word on the list is
# anywhere in them, no home folder in the program, and both carry the version
APP="$W/mac/build/Binah.app" APK="$W/android/Binah-$V.apk"
[[ $(mac "codesign -dvv $APP 2>&1 | grep '^Authority='") == "Authority=$BINAH_SIGN_NAME" ]] || { echo "the Mac app isn't signed by $BINAH_SIGN_NAME alone" >&2; exit 1; }
mac "codesign --verify --strict $APP" || { echo "the Mac app's signature doesn't verify" >&2; exit 1; }
[[ $(mac "/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' $APP/Contents/Info.plist") == "$V" ]] || { echo "the Mac app isn't $V" >&2; exit 1; }
[[ -z $(mac "grep -r -l -a -i -E '$BINAH_PRIVATE' $APP; strings $APP/Contents/MacOS/Binah | grep /Users/") ]] \
  || { echo "something personal is in the Mac app" >&2; exit 1; }
[[ -z $(mac "cd /tmp && rm -rf binah-apk && mkdir binah-apk && cd binah-apk && unzip -q $APK && grep -r -l -a -i -E '$BINAH_PRIVATE' .; cd /tmp && rm -rf binah-apk") ]] \
  || { echo "something personal is in the APK" >&2; exit 1; }
say "both built and signed, with nothing personal in them"

# 3. here, and out
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
scp -q -o BatchMode=yes -i "$KEY" "$BINAH_MAC:$APK" "$BINAH_MAC:$W/mac/build/Binah-$V-mac.zip" "$OUT/"
ZIPSUM=$(sha256sum "$OUT/Binah-$V-mac.zip" | cut -d' ' -f1)
gh release create "v$V" "$OUT/Binah-$V.apk" "$OUT/Binah-$V-mac.zip" --repo "$REPO" --title "Binah $V" --notes "$NOTES"
mac "rm -rf $W"

# 4. the cask: only Binah's file (and its row) in the shared tap
git clone -q "git@github.com:$TAP.git" "$OUT/tap"
mkdir -p "$OUT/tap/Casks"
cat > "$OUT/tap/Casks/binah.rb" <<CASK
cask "binah" do
  version "$V"
  sha256 "$ZIPSUM"

  url "https://github.com/$REPO/releases/download/v#{version}/Binah-#{version}-mac.zip"
  name "Binah"
  desc "Daily training for reading closely, reasoning and speaking"
  homepage "https://github.com/$REPO"

  depends_on macos: :tahoe

  app "Binah.app"

  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/Binah.app"]
  end
end
CASK
cd "$OUT/tap"
ROW='| [binah](Casks/binah.rb) | [Binah](https://github.com/franz-rosenzweig/binah): daily training for reading, reasoning and speaking |'
grep -qF '[binah](Casks/binah.rb)' README.md || printf '%s\n' "$ROW" >> README.md
git add Casks/binah.rb README.md
git commit -q -m "binah $V"
git pull -q --rebase
git push -q
say "released: https://github.com/$REPO/releases/tag/v$V, and the cask is at $V"
