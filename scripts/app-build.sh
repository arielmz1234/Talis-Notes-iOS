#!/bin/sh
# Builds the app and its UI tests for the simulator, printing only compile errors (or "built").
cd "$(dirname "$0")/.."
mkdir -p build
xcodebuild build-for-testing -project TalisNotes.xcodeproj -scheme TalisNotes \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/dd \
  CODE_SIGNING_ALLOWED=NO > build/build-log.txt 2>&1 \
  && echo built || { grep -E "error:" build/build-log.txt | sed 's/^.*Talis-Notes-iOS[^/]*\/[^/]*\///' | sort -u | cut -c1-260 | head -${LINES_MAX:-40}; exit 1; }
