#!/bin/bash
# check-deps.sh — Verify all build dependencies are installed
set -euo pipefail

ok=0
fail=0

check() {
    if command -v "$1" &>/dev/null; then
        printf "  ✓ %-20s %s\n" "$1" "$(command -v "$1")"
        ok=$((ok + 1))
    else
        printf "  ✗ %-20s MISSING (install: %s)\n" "$1" "$2"
        fail=$((fail + 1))
    fi
}

echo "Checking build dependencies..."
echo ""

echo "── Build tools ──"
check ninja       "brew install ninja"
check xcodegen    "brew install xcodegen"
check ragel       "brew install ragel"
check multimarkdown "brew install multimarkdown"

echo ""
echo "── System tools ──"
check xcodebuild  "xcode-select --install"
check git         "xcode-select --install"

echo ""
if [ "$fail" -eq 0 ]; then
    echo "All $ok dependencies satisfied ✓"
else
    echo "$fail missing, $ok found. Run: make deps"
    exit 1
fi
