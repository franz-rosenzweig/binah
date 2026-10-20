#!/bin/zsh
# The Mac app against a sandbox Binah, never the real one: it reads and decodes every endpoint
# the app reads, opens each room and game and pictures the window (light and dark), and plays The
# Author's Word once (one answer written to the sandbox). Pictures and the log land in
# build/selftest.
#
#   ./selftest.sh BASE TOKEN       # BASE e.g. http://localhost:8471 (ssh -L 8471:127.0.0.1:8471 <your-server>)
#
# It runs the app's binary straight from this shell, so the window pictures need no permission of
# their own, and gives the window the screen for about half a minute.
set -euo pipefail
cd "${0:A:h}"
(( $# == 2 )) || { sed -n 2,11p $0 >&2; exit 2; }
BINAH_OUT=build/selftest-app BINAH_ID=xyz.tiresia.binah.selftest BINAH_NAME="Binah Selftest" ./build.sh >/dev/null
OUT=$PWD/build/selftest
rm -rf "$OUT" && mkdir -p "$OUT"
APP="build/selftest-app/Binah Selftest.app"
( sleep 180; pkill -f "$APP/Contents/MacOS/Binah" ) 2>/dev/null &
watchdog=$!
BINAH_SELFTEST="$OUT" BINAH_BASE="$1" BINAH_TOKEN="$2" "$APP/Contents/MacOS/Binah" >/dev/null 2>"$OUT/stderr.txt" || true
kill $watchdog 2>/dev/null || true
# the test copy leaves no trace in Launch Services (its Services item, its name in Open With)
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$APP" 2>/dev/null || true
grep -E "^(SELFTEST|PASS|FAIL|INFO)" "$OUT/log.txt"
grep -q "SELFTEST passed" "$OUT/log.txt"
