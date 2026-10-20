#!/bin/zsh
# Tests the shell from inside: builds Binah with SelfTest/ linked in, as its own app
# (xyz.tiresia.binah.selftest, so Binah itself can stay open and keeps its settings), and
# runs it against a Binah server:
#
#   ./selftest.sh BASE COOKIE TOKEN              # every section
#   ./selftest.sh BASE COOKIE TOKEN keys,menus   # some: load window menus keys services outside mic deeplink menubar connect train settings
#
# BASE must be a sandbox copy of Binah, never the real one: the test makes a device token
# ("mac") and saves a passage to train on. COOKIE is the sandbox's "binah" sign-in cookie,
# TOKEN a device token (docs/SHELL.md §5). For the microphone check BASE has to be https
# or localhost: ssh -L 8471:127.0.0.1:8471 <your-server>, then http://localhost:8471. It takes
# the keyboard for about half a minute: leave the Mac alone meanwhile. Pictures of each
# window land in build/selftest/out.
set -euo pipefail
cd "${0:A:h}"
(( $# >= 3 )) || { sed -n 2,15p $0 >&2; exit 2; }

OUT=build/selftest
mkdir -p $OUT && rm -rf $OUT/out && mkdir -p $OUT/out
clang -c -target "$(uname -m)-apple-macos14.0" SelfTest/hook.c -o $OUT/hook.o
# quiet unless it fails: the harness's one warning is CGWindowListCreateImage, deprecated but
# the only way to picture the app's own windows without the Screen Recording permission
BINAH_OUT=$OUT BINAH_BUNDLE_ID=xyz.tiresia.binah.selftest BINAH_EXTRA="SelfTest/SelfTest.swift $OUT/hook.o" \
    ./build.sh >$OUT/build.log 2>&1 || { cat $OUT/build.log; exit 1; }

# a value starting with "-" would read as another setting's name: tokens can, so both get a prefix
ARGS=(-SelfTestBase "$1" -SelfTestCookie "c:$2" -SelfTestToken "t:$3")
(( $# >= 4 )) && ARGS+=(-SelfTestOnly "$4")
BIN=$PWD/$OUT/Binah.app/Contents/MacOS/Binah
( sleep 240; pkill -f "$BIN" ) 2>/dev/null &           # a stuck run ends after four minutes
watchdog=$!
open -W -n --stdout $OUT/out/log.txt --stderr $OUT/out/log.txt $OUT/Binah.app \
    --args -SelfTestOut "$PWD/$OUT/out" -ApplePersistenceIgnoreState YES "${ARGS[@]}"
kill $watchdog 2>/dev/null || true
grep -E "^(SELFTEST|PASS|FAIL|SKIP|INFO|MENU)" $OUT/out/log.txt
grep -q "SELFTEST passed" $OUT/out/log.txt
