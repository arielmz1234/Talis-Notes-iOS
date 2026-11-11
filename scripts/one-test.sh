#!/bin/sh
# One UI test (or class) on a simulator, stopping once its summary is out:
#   scripts/one-test.sh "<simulator name>" <tag> MediaTests/testInsert [dark] [language]
# local-shots.sh waits for "All tests", which a run of selected tests never prints. Only the run on
# this simulator is stopped (other worktrees may be testing on theirs).
cd "$(dirname "$0")/.."
dev=$(sh scripts/sim.sh "$1" iPad)
rm -f "build/$2.log"
ONLY="$3" sh scripts/local-shots.sh "$1" "$2" "${4:-0}" "${5:-}" &
pid=$!
until ! kill -0 $pid 2>/dev/null || grep -qE "Test Suite 'Selected tests' (passed|failed)" "build/$2.log" 2>/dev/null; do sleep 2; done
sleep 3
pkill -f "xcodebuild test-without-building.*id=$dev" 2>/dev/null
wait $pid 2>/dev/null
grep -E "error:|Executed .* tests?, with" "build/$2.log" | tail -4
ls shots | grep "^$2-" | tr '\n' ' '; echo
