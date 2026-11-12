#!/bin/sh
# Screenshots on a local simulator, as CI takes them:
#   scripts/local-shots.sh "iPad Pro 13" ipad-light 0 ""      # name prefix, tag, dark (0/1), language
# Builds first unless NO_BUILD=1. ONLY=<TestClass> runs just that class (default: every test).
# Shots land in shots/<tag>-*.png, the log in build/<tag>.log.
set -e
cd "$(dirname "$0")/.."
name="${1:-iPad Pro 13}"; tag="${2:-ipad-light}"; dark="${3:-0}"; lang="${4:-}"
kind=iPad; case "$name" in iPhone*) kind=iPhone;; esac
dev=$(sh scripts/sim.sh "$name" "$kind")
[ -n "$dev" ] || { echo "no simulator named $name"; exit 1; }
mkdir -p build shots
[ -f TalisNotes.xcodeproj/project.pbxproj ] || xcodegen generate
[ "${NO_BUILD:-0}" = 1 ] || sh scripts/app-build.sh
xcrun simctl boot "$dev" 2>/dev/null || true
xcrun simctl bootstatus "$dev" -b > /dev/null
rm -f shots/"$tag"-*.png
rm -rf build/"$tag".xcresult
# A runner left by the last run (xcodebuild is stopped below) would run its old tests again.
xcrun simctl uninstall "$dev" com.tali.notes.uitests.xctrunner 2>/dev/null || true
TEST_RUNNER_SHOT_DIR="$PWD/shots" TEST_RUNNER_SHOT_TAG="$tag" TEST_RUNNER_SHOT_DARK="$dark" TEST_RUNNER_SHOT_LANG="$lang" \
  xcodebuild test-without-building -project TalisNotes.xcodeproj -scheme TalisNotes \
  -destination "id=$dev" -derivedDataPath build/dd -resultBundlePath "build/$tag.xcresult" \
  ${ONLY:+-only-testing:TalisNotesUITests/$ONLY} > "build/$tag.log" 2>&1 &
run=$!
# On Xcode 27 xcodebuild can sit forever after the last test: stop it once the summary is out.
until ! kill -0 $run 2>/dev/null || grep -qE "Test Suite '(All|Selected) tests' (passed|failed)" "build/$tag.log"; do sleep 2; done
i=0; while kill -0 $run 2>/dev/null && [ $i -lt 20 ]; do sleep 1; i=$((i+1)); done
kill $run 2>/dev/null || true
grep -E "error:|failed:|Assertion|No matches|not hittable|ScreenshotTests.swift:" "build/$tag.log" | grep -v "Test Suite" | head -20 || true
grep -E "Executed .* tests?, with" "build/$tag.log" | tail -1
ls shots | grep "^$tag-" | tr '\n' ' '; echo
