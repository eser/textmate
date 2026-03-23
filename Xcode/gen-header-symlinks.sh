#!/bin/bash
# gen-header-symlinks.sh — SW³ TextFellow
#
# Creates symlinks in Xcode/include/ so that framework-style includes work:
#   #include <OakTextView/OakTextView.h>  →  Frameworks/OakTextView/src/OakTextView.h
#
# Reads header-map.txt which has format:
#   FrameworkName/Header.h → Frameworks/FrameworkName/src/Header.h
#
# This script is called by the GenerateHeaders aggregate target in Xcode
# BEFORE any compilation starts, preventing race conditions.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRCROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INCLUDE_DIR="$SCRIPT_DIR/include"
HEADER_MAP="$SCRIPT_DIR/header-map.txt"

if [ ! -f "$HEADER_MAP" ]; then
    echo "error: header-map.txt not found at $HEADER_MAP" >&2
    exit 1
fi

# Clean and recreate
rm -rf "$INCLUDE_DIR"
mkdir -p "$INCLUDE_DIR"

count=0
while IFS= read -r line; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" == \#* ]] && continue

    # Parse: FrameworkName/Header.h → path/to/Header.h
    target="${line%% →*}"
    source="${line##*→ }"

    # Trim whitespace
    target="$(echo "$target" | xargs)"
    source="$(echo "$source" | xargs)"

    # Create directory for framework
    dir="$INCLUDE_DIR/$(dirname "$target")"
    mkdir -p "$dir"

    # Create relative symlink
    src_abs="$SRCROOT/$source"
    if [ -f "$src_abs" ]; then
        ln -sf "$src_abs" "$INCLUDE_DIR/$target"
        count=$((count + 1))
    else
        echo "warning: source not found: $source (for $target)" >&2
    fi
done < "$HEADER_MAP"

echo "Generated $count header symlinks in $INCLUDE_DIR"

# ── Collision workaround: network/ vs Apple's Network.framework ──
# On case-insensitive macOS filesystems, our network/ directory collides
# with Apple's Network.framework. WebKit's WKWebsiteDataStore.h conditionally
# imports <Network/Network.h>, which finds our header instead of Apple's.
# We replace the network.h symlink with a wrapper that includes our real
# header AND stubs Apple's nw_proxy_config_t type.
rm -f "$INCLUDE_DIR/network/network.h"
cat > "$INCLUDE_DIR/network/network.h" << WRAPPER
// Auto-generated wrapper — do not edit (see gen-header-symlinks.sh)
// Resolves case-insensitive collision: network/ vs Apple's Network.framework
// Only include our C++ network header in C++/ObjC++ mode.
// In pure ObjC mode (.m), the C++ stdlib isn't available, but WebKit
// may still reach this file — so we just provide the nw stub below.
#if defined(__cplusplus) && !defined(NETWORK_H_L3XXH7J6)
#include "$SRCROOT/Frameworks/network/src/network.h"
#endif
// Stub for Apple's nw_proxy_config_t (used by WKWebsiteDataStore.h)
#ifdef __OBJC__
#ifndef _NW_PROXY_CONFIG_STUB_
#define _NW_PROXY_CONFIG_STUB_
@protocol OS_nw_proxy_config <NSObject>
@end
typedef NSObject<OS_nw_proxy_config> * nw_proxy_config_t;
#endif
#endif
WRAPPER

# ── Code generation: ragel ──
# Generate into build/xcode/generated/ to avoid conflicting with Rave's
# own generation. The generated directory is added to HEADER_SEARCH_PATHS
# and source files are compiled via the Xcode project.
GENDIR="$SRCROOT/build/xcode/generated"
mkdir -p "$GENDIR"

regen=0

# Ragel: plist/ascii.rl → ascii.cc
rl_in="$SRCROOT/Frameworks/plist/src/ascii.rl"
rl_out="$GENDIR/ascii.cc"
if [ "$rl_in" -nt "$rl_out" ] 2>/dev/null || [ ! -f "$rl_out" ]; then
    ragel -o "$rl_out" "$rl_in" && regen=$((regen + 1))
fi

echo "Code generation: $regen files regenerated in $GENDIR"

# ── About HTML: convert markdown → html ──
# The Rave build uses multimarkdown with header/footer templates.
# Generate into build/xcode/About/ which is copied as a resource.
ABOUTDIR="$SRCROOT/build/xcode/About"
mkdir -p "$ABOUTDIR/css" "$ABOUTDIR/js"

ABOUT_SRC="$SRCROOT/Applications/TextMate/about"

about_count=0
for md in "$ABOUT_SRC"/*.md; do
    base="$(basename "$md" .md)"
    html="$ABOUTDIR/$base.html"
    if [ "$md" -nt "$html" ] 2>/dev/null || [ ! -f "$html" ]; then
        multimarkdown -f "$md" > "$html" && about_count=$((about_count + 1))
    fi
done

# Copy static About assets (css, js, images)
cp -a "$ABOUT_SRC/css/"* "$ABOUTDIR/css/" 2>/dev/null || true
cp -a "$ABOUT_SRC/js/"* "$ABOUTDIR/js/" 2>/dev/null || true
# Also copy any pre-existing HTML files
cp -n "$ABOUT_SRC"/*.html "$ABOUTDIR/" 2>/dev/null || true

echo "About HTML: $about_count files generated in $ABOUTDIR"
