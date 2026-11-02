#!/usr/bin/env bash
# Generate FlexDisplay.xcodeproj with XcodeGen (macOS only).
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen 未安裝。可用 Homebrew："
  echo "  brew install xcodegen"
  echo "或睇 README「冇 XcodeGen」一節，手動喺 Xcode 開 macOS App 再拖入 Sources。"
  exit 1
fi

xcodegen generate
echo "已產生 ./FlexDisplay.xcodeproj — 用 Xcode 打開即可。"
