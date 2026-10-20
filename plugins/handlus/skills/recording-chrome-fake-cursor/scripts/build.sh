#!/bin/zsh
# build.sh — compile rec.swift into bin/screcord (macOS ScreenCaptureKit window recorder).
#   Built per machine on first use (rec.sh calls this when bin/screcord is missing). Needs Xcode Command Line Tools: xcode-select --install
set -e
cd "${0:A:h}"
mkdir -p bin
if [[ $(sysctl -n hw.optional.arm64 2>/dev/null) == 1 ]]; then
  arch -arm64 /usr/bin/xcrun swiftc -O -framework ScreenCaptureKit -framework AVFoundation -framework AppKit rec.swift -o bin/screcord
else
  /usr/bin/xcrun swiftc -O -framework ScreenCaptureKit -framework AVFoundation -framework AppKit rec.swift -o bin/screcord
fi
echo "✅ bin/screcord"
