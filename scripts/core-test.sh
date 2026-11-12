#!/bin/sh
# The core tests with only what matters printed: compile errors, failures and the summary.
#   scripts/core-test.sh [filter]
cd "$(dirname "$0")/.."
swift test --package-path Packages/TaliCore ${1:+--filter "$1"} 2>&1 | grep -E "error: |✘|Test run with|recorded an issue" | grep -v "SwiftCompile\|Build failed\|fatalError" | cut -c1-400 | sed 's/\x1b\[[0-9;]*m//g' | head -${LINES_MAX:-40}
