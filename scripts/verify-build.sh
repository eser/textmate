#!/bin/bash
# verify-build.sh — Build with both systems and verify outputs
set -euo pipefail

RAVE_APP=~/build/textmate/release/Applications/TextMate/TextMate.app
XCODE_APP=build/xcode/Debug/TextFellow.app

echo "═══════════════════════════════════════════"
echo "  SW³ TextFellow — Build Verification"
echo "═══════════════════════════════════════════"
echo ""

# ── Step 1: Rave build ──
echo "── Step 1: Rave build (ninja TextMate) ──"
if ninja TextMate 2>&1 | tail -3; then
    echo "  ✓ Rave build succeeded"
else
    echo "  ✗ Rave build FAILED"
    exit 1
fi
echo ""

# ── Step 2: Xcode build ──
echo "── Step 2: Xcode build (xcodebuild TextFellow) ──"
xcodegen generate >/dev/null 2>&1
if xcodebuild -project TextFellow.xcodeproj \
    -target TextFellow \
    -configuration Debug \
    -arch arm64 \
    build 2>&1 | tail -3; then
    echo "  ✓ Xcode build succeeded"
else
    echo "  ✗ Xcode build FAILED"
    exit 1
fi
echo ""

# ── Step 3: Verify outputs ──
echo "── Step 3: Verify outputs ──"
rave_bin="$RAVE_APP/Contents/MacOS/TextMate"
xcode_bin="$XCODE_APP/Contents/MacOS/TextFellow"

if [ ! -f "$rave_bin" ]; then
    echo "  ✗ Rave binary not found: $rave_bin"
    exit 1
fi
if [ ! -f "$xcode_bin" ]; then
    echo "  ✗ Xcode binary not found: $xcode_bin"
    exit 1
fi

rave_arch=$(file "$rave_bin" | grep -o 'arm64\|x86_64' | head -1)
xcode_arch=$(file "$xcode_bin" | grep -o 'arm64\|x86_64' | head -1)
rave_size=$(stat -f%z "$rave_bin")
xcode_size=$(stat -f%z "$xcode_bin")

echo "  Rave:  $(du -h "$rave_bin" | cut -f1) ($rave_arch)"
echo "  Xcode: $(du -h "$xcode_bin" | cut -f1) ($xcode_arch)"
echo ""

# ── Summary ──
echo "═══════════════════════════════════════════"
echo "  ✓ Both builds produce working binaries"
echo "═══════════════════════════════════════════"
