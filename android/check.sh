#!/bin/zsh
# The test build ("Binah dev") against a sandbox Binah, never the real one, on the phone
# that's plugged in. The app's self-test (SelfTest.kt) reads and decodes every endpoint the app
# reads, opens each room and game, light and dark, and plays The Author's Word once (one answer
# written to the sandbox); this script pictures the screen whenever it says "SHOT <name>".
# Pictures and the log land in android/build/check.
#
#   ./check.sh BASE TOKEN     # BASE e.g. http://localhost:8471 (ssh -fN -L 8471:127.0.0.1:8471 <your-server>)
#                             # TOKEN a device token on that sandbox; the phone unlocked
set -euo pipefail
cd "${0:A:h}"
(( $# == 2 )) || { sed -n 2,10p $0 >&2; exit 2; }
export JAVA_HOME=${JAVA_HOME:-/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home}
export ANDROID_HOME=${ANDROID_HOME:-$HOME/android-sdk}
ADB=$ANDROID_HOME/platform-tools/adb
PKG=xyz.tiresia.binah.debug
BASE=$1

./gradlew -q assembleDebug --console=plain
$ADB install -r app/build/outputs/apk/debug/app-debug.apk >/dev/null
# the phone's localhost:<port> is this Mac's, which the ssh tunnel takes to the sandbox
port=${${BASE##*:}%%/*}
[[ $BASE == http://localhost:* ]] && $ADB reverse tcp:$port tcp:$port >/dev/null

OUT=$PWD/build/check
rm -rf $OUT && mkdir -p $OUT
$ADB shell input keyevent KEYCODE_WAKEUP
if $ADB shell dumpsys window | grep -q "mDreamingLockscreen=true"; then echo "unlock the phone, then run this again" >&2; exit 2; fi
$ADB shell am force-stop $PKG
$ADB logcat -c
$ADB logcat -v raw -s BinahSelfTest:I > $OUT/log.txt &
logcat=$!
trap 'kill $logcat 2>/dev/null || true' EXIT
$ADB shell am start -n $PKG/xyz.tiresia.binah.app.MainActivity \
    --es binah.base "$BASE" --es binah.token "$2" --ez binah.selftest true >/dev/null

seen=0 finished=0 deadline=$((SECONDS + 300))
while (( SECONDS < deadline && ! finished )); do
    sleep 0.3
    lines=("${(@f)$(<$OUT/log.txt)}")
    for (( i = seen + 1; i <= ${#lines}; i++ )); do
        l=${lines[i]}
        [[ -z $l || $l == ---------* ]] && continue
        print -r -- $l
        [[ $l == "SHOT "* ]] && $ADB exec-out screencap -p > $OUT/${l#SHOT }.png
        [[ $l == "SELFTEST passed" || $l == SELFTEST\ *failed ]] && finished=1
    done
    seen=${#lines}
done
$ADB shell am force-stop $PKG
(( finished )) || { echo "the self-test didn't finish in five minutes" >&2; exit 1; }
grep -qx "SELFTEST passed" $OUT/log.txt
