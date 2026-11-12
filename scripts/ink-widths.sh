#!/bin/sh
# How wide the PDF's lines are against PencilKit's own drawing of the same strokes (InkOutline.swift's
# measured widths): sh scripts/ink-widths.sh "TN iPad B". Each line prints PDF / page, ideally 1.00;
# a light touch of a thin fountain pen, which PencilKit draws thinner than the PDF's hairline, is more.
set -e
cd "$(dirname "$0")/.."
dir=build/ink-widths
rm -rf "$dir" && mkdir -p "$dir/src"
for f in Packages/TaliCore/Sources/TaliCore/*.swift App/Sources/Notebook/InkBridge.swift App/Sources/Notebook/InkLook.swift App/Sources/Notebook/InkOutline.swift; do
  sed -e 's/^import TaliCore$//' -e 's/TaliCore\.Rect/Rect/g' "$f" > "$dir/src/$(basename "$f")"
done
cp scripts/ink-widths.swift "$dir/src/main.swift"
xcrun --sdk iphonesimulator swiftc -O -target arm64-apple-ios17.0-simulator -module-name InkWidths \
  "$dir"/src/*.swift -lsqlite3 -lz -o "$dir/ink-widths"
xcrun simctl boot "${1:-TN iPad B}" 2>/dev/null || true
xcrun simctl spawn "${1:-TN iPad B}" "$PWD/$dir/ink-widths"
