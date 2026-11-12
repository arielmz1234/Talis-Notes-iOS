#!/bin/sh
# One UI test class (or Class/test) on one of this area's two simulators, with a fresh runner:
#   scripts/sel-shots.sh ipad|iphone <tag> [dark 0/1] [ONLY]
cd "$(dirname "$0")/.."
case "$1" in ipad) name="iPad Air 13-inch (M4)";; *) name="iPhone 17e";; esac
dev=$(xcrun simctl list devices available -j | jq -r --arg n "$name" '[.devices[][] | select(.name == $n)] | last | .udid')
xcrun simctl boot "$dev" 2>/dev/null
xcrun simctl bootstatus "$dev" -b > /dev/null
xcrun simctl uninstall "$dev" com.tali.notes.uitests.xctrunner 2>/dev/null
ONLY="${4:-SelectingTests}" sh scripts/local-shots.sh "$name" "$2" "${3:-0}" "" 2>&1 | cut -c1-300 | tail -25
