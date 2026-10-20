#!/bin/zsh
# Checks the test build on the phone plugged into this Mac (USB debugging on), against a
# sandbox Binah, never the real one: it signs in there, makes this phone's token and saves a
# passage to train on.
#
#   ./check.sh BASE COOKIE TOKEN
#
# BASE is the sandbox as this Mac reaches it, http://localhost:8471 through
# ssh -L 8471:127.0.0.1:8471 <your-server>. It builds and installs the test build ("Binah dev",
# xyz.tiresia.binah.debug, beside the real app) and runs check.py: the page in the app over
# DevTools, the microphone, Back pressed on the phone (leave it unlocked), Train on this, the
# widget's numbers and Settings. Pictures land in build/check.
set -euo pipefail
cd "${0:A:h}"
(( $# >= 3 )) || { sed -n 2,13p $0 >&2; exit 2; }
export JAVA_HOME=${JAVA_HOME:-/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home}
export ANDROID_HOME=${ANDROID_HOME:-$HOME/android-sdk}
ADB=$ANDROID_HOME/platform-tools/adb
$ADB get-state >/dev/null 2>&1 || { echo "no phone: plug it in and allow USB debugging" >&2; exit 2; }
./gradlew assembleDebug -q --console=plain
$ADB install -r app/build/outputs/apk/debug/app-debug.apk >/dev/null
python3 -I check.py "$@"
