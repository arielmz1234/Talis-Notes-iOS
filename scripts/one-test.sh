#!/bin/sh
# One UI test (or class) on a simulator, stopping once its summary is out:
#   scripts/one-test.sh "<simulator name>" <tag> MediaTests/testInsert [extra args for local-shots]
# local-shots.sh waits for "All tests", which a run of selected tests never prints.
cd "$(dirname "$0")/.."
rm -f "build/$2.log"
ONLY="$3" sh scripts/local-shots.sh "$1" "$2" "${4:-0}" "${5:-}" &
pid=$!
until ! kill -0 $pid 2>/dev/null || grep -qE "Test Suite 'Selected tests' (passed|failed)" "build/$2.log" 2>/dev/null; do sleep 2; done
sleep 3
pkill -f "xcodebuild test-without-building.*$2.xcresult" 2>/dev/null
wait $pid 2>/dev/null
grep -E "error:|Executed .* tests?, with" "build/$2.log" | tail -4
ls shots | grep "^$2-" | tr '\n' ' '; echo
